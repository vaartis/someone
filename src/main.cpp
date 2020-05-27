#include <filesystem>

#include <SFML/Graphics.hpp>
#include <SFML/Window/Event.hpp>
#include <SFML/System/Clock.hpp>

#include "imgui.h"
#include "imgui-SFML.h"

#include "sol/sol.hpp"

#include "logger.hpp"
#include "string_utils.hpp"
#include "fonts.hpp"
#include "story_parser.hpp"
#include "usertypes.hpp"

#include "terminal.hpp"
#include "walking.hpp"
#include "coroutines.hpp"

enum class CurrentState {
    Terminal,
    Walking
};

int main(int argc, char **argv) {
    // Change cwd to where the program is
    std::filesystem::current_path(std::filesystem::path(argv[0]).parent_path());

    #ifndef NDEBUG
    spdlog::set_level(spdlog::level::debug);
    #endif

    sf::RenderWindow window(sf::VideoMode(1280, 1024), "Someone");
    window.setFramerateLimit(60);

    ImGui::SFML::Init(window);
    ImGuiIO& io = ImGui::GetIO();
    // Disable the ini file
    io.IniFilename = nullptr;

    sf::RenderTexture target;
    {
        auto winSize = window.getSize();
        target.create(winSize.x, winSize.y);
    }
    auto &targetTexture = target.getTexture();
    sf::Sprite targetSprite(targetTexture);

    StaticFonts static_fonts;

    /*
    sf::Texture lightTexture;
    lightTexture.loadFromFile("resources/sprites/room/light.png");
    sf::Sprite lightSprite(lightTexture);
    auto rect = lightSprite.getTextureRect();
    lightSprite.setOrigin(rect.width / 2, rect.height / 2);
    lightSprite.setPosition(387, 600);
    */

    sol::state lua;
    lua.open_libraries(sol::lib::base, sol::lib::table, sol::lib::string, sol::lib::package,
                       sol::lib::coroutine, sol::lib::math, sol::lib::debug, sol::lib::os, sol::lib::io);

    // Setup the lua path to see luarocks packages
    auto package_path = std::filesystem::path("resources") / "lua" / "share" / "lua" / SOMEONE_LUA_VERSION / "?.lua;";
    package_path += std::filesystem::path("resources") / "lua" / "share" / "lua" / SOMEONE_LUA_VERSION / "?" / "init.lua;";
    lua["package"]["path"] = std::string(package_path.u8string()) + std::string(lua["package"]["path"]);

    auto package_cpath = std::filesystem::path("resources") / "lua" / "lib" / "lua" / SOMEONE_LUA_VERSION / "?." SOMEONE_LIB_EXT ";";
    lua["package"]["cpath"] = std::string(package_cpath.u8string()) + std::string(lua["package"]["cpath"]);

    #ifdef SOMEONE_TESTING
    // Has to be included as the first thing to cover everything
    lua.script("require('luacov')");
    // Tests use moonscript
    lua.script("require('moonscript')");
    #endif

    register_usertypes(lua, static_fonts);

    CoroutinesEnv coroutines_env(lua);
    TerminalEnv terminal_env(lua);
    WalkingEnv walking_env(lua);

    auto current_state = CurrentState::Walking;

    auto current_state_type = lua.new_enum(
        "CurrentState",
        "Terminal", CurrentState::Terminal,
        "Walking", CurrentState::Walking
    );
    lua["GLOBAL"] = lua.create_table_with(
        "drawing_target", &target,
        "set_current_state", [&](CurrentState new_state) { current_state = new_state; },
        // Apparently lua doesn't have a good equivalent
        "isalpha", [](int num) { return std::isalpha(num) != 0; }
    );

#ifdef SOMEONE_TESTING
    for (int i = 1; i < argc; i++) {
        lua[sol::create_if_nil]["arg"][i] = std::string(argv[i]);
    }

    walking_env.run_tests();

    return 0;
#endif

    bool debug_menu = false;

    sf::Clock clock;
    while (true) {
        auto dt_time = clock.restart();
        auto dt = dt_time.asSeconds();

        sf::Color clear_color;
        switch (current_state) {
        case CurrentState::Terminal:
            clear_color = sf::Color::White;
            break;
        case CurrentState::Walking:
            clear_color = sf::Color::Black;
        }
        target.clear(clear_color);

        sf::Event event;
        while (window.pollEvent(event)) {
            switch (event.type) {
            case sf::Event::Closed:
                window.close();

                break;
            case sf::Event::Resized: {
                float width = event.size.width,
                    height = event.size.height;
                target.setView(
                    sf::View(
                        {width / 2, height / 2},
                        {width, height}
                    )
                );
                break;
            }
            case sf::Event::KeyReleased: {
                // Activate debug menu on ~
                if (event.key.code == sf::Keyboard::Tilde)
                    debug_menu = !debug_menu;
                break;
            }

            default: break;
            }

            if (!debug_menu) {
                switch (current_state) {
                case CurrentState::Terminal:
                    terminal_env.process_event(event);
                    break;
                case CurrentState::Walking:
                    walking_env.add_event(event);
                    break;
                }
            } else {
                ImGui::SFML::ProcessEvent(event);
            }
        }

        window.clear();

        switch (current_state) {
        case CurrentState::Terminal:
            terminal_env.update_event_timer(dt);
            terminal_env.draw(dt);

            // Don't draw to the screen yet, will be drawn after coroutines run

            break;
        case CurrentState::Walking:
            walking_env.update(dt);

            // Run all the drawing in lua and then draw it to the screen
            walking_env.draw();
            walking_env.draw_target_to_window(window, targetSprite);

            // Now clear the target and draw the overlay
            target.clear(sf::Color::Transparent);
            walking_env.draw_overlay();

            // Don't draw yet, wait for coroutines to run,
            // then everything will be drawn

            break;
        }

        // After everything has been drawn and processed, run the coroutines
        coroutines_env.run(dt);

        // Draw what hasn't been drawn yet
        window.draw(targetSprite);

        target.display();

        if (debug_menu) {
            ImGui::SFML::Update(window, dt_time);

            ImGui::Begin("Debug menu", nullptr, ImGuiWindowFlags_AlwaysAutoResize);

            switch (current_state) {
            case CurrentState::Terminal:
                terminal_env.debug_menu();
                break;
            case CurrentState::Walking:
                break;
            }

            ImGui::End();

            ImGui::SFML::Render(window);
        }
        window.display();
    }
}
