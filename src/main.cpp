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

    constexpr std::pair<int, int> initial_size(1280, 1024);
    const std::vector<sf::Vector2u> window_sizes = {
        { initial_size.first, initial_size.second },
        { initial_size.first / 2, initial_size.second / 2},
        { initial_size.first * 2, initial_size.second * 2}
    };
    uint8_t current_window_size = 0;

    const auto &default_size = window_sizes[current_window_size];
    sf::RenderWindow window(sf::VideoMode(default_size.x, default_size.y), "Someone", sf::Style::Titlebar | sf::Style::Close);
    window.setFramerateLimit(60);
    window.setPosition(sf::Vector2i(0, 0));

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

    sol::state lua;
    lua.open_libraries(sol::lib::base, sol::lib::table, sol::lib::string, sol::lib::package,
                       sol::lib::coroutine, sol::lib::math, sol::lib::debug, sol::lib::os, sol::lib::io,
                       sol::lib::utf8);

    // Setup the lua path to see luarocks packages
    auto package_path = std::filesystem::path("resources") / "lua" / "share" / "lua" / SOMEONE_LUA_VERSION / "?.lua;";
    package_path += std::filesystem::path("resources") / "lua" / "share" / "lua" / SOMEONE_LUA_VERSION / "?" / "init.lua;";
    lua["package"]["path"] = std::string(package_path.string()) + std::string(lua["package"]["path"]);

    auto package_cpath = std::filesystem::path("resources") / "lua" / "lib" / "lua" / SOMEONE_LUA_VERSION / "?." SOMEONE_LIB_EXT ";";
    lua["package"]["cpath"] = std::string(package_cpath.string()) + std::string(lua["package"]["cpath"]);

    #ifdef SOMEONE_TESTING
    // Has to be included as the first thing to cover everything
    lua.script("require('luacov')");
    // Tests use moonscript
    lua.script("require('moonscript')");
    #endif

    register_usertypes(lua, static_fonts);

    CoroutinesEnv coroutines_env(lua);
    TerminalEnv terminal_env(lua);

    auto loaded_mods = terminal_env.parser.load_mods(lua);

    auto current_state = CurrentState::Walking;

    auto current_state_type = lua.new_enum(
        "CurrentState",
        "Terminal", CurrentState::Terminal,
        "Walking", CurrentState::Walking
    );
    lua["GLOBAL"] = lua.create_table_with(
        "drawing_target", &target,
        "window", &window,
        "set_current_state", [&](CurrentState new_state) { current_state = new_state; },
        // Apparently lua doesn't have a good equivalent
        "isalpha", [](int num) { return std::isalpha(num) != 0; },
        "loaded_mods", loaded_mods
    );

    // Initialize the walking env after GLOBAL, because it needs to put things in there
    WalkingEnv walking_env(lua);

#ifndef NDEBUG
    terminal_env.parser.total_wordcount();
#endif

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

                return 0;
            case sf::Event::KeyReleased: {
                switch (event.key.code) {
                case sf::Keyboard::Tilde:
                    // Activate debug menu on ~
                    debug_menu = !debug_menu;
                    break;
                case sf::Keyboard::F1:
                    if (current_window_size + 1 >= window_sizes.size()) {
                        current_window_size = 0;
                    } else {
                        current_window_size++;
                    }
                    window.setSize(window_sizes[current_window_size]);

                    break;
                default:
                    break;
                }

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

        if (current_state == CurrentState::Walking) {
            // Clear the event store as the very last thing, after the coroutines run
            walking_env.clear_event_store();
        }

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
                walking_env.debug_menu();
                break;
            }

            ImGui::End();

            ImGui::SFML::Render(window);
        }
        window.display();
    }
}
