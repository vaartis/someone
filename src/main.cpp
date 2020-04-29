#include <filesystem>

#include <SFML/Graphics.hpp>
#include <SFML/Window/Event.hpp>
#include <SFML/System/Clock.hpp>

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


#if defined(SOMEONE_WINDOWS)
  #define LIB_EXT "dll"
#elif defined(SOMEONE_LINUX)
  #define LIB_EXT "so"
#endif

int main() {
    #ifndef NDEBUG
    spdlog::set_level(spdlog::level::debug);
    #endif

    sf::RenderWindow window(sf::VideoMode(1280, 1024), "Someone");
    window.setFramerateLimit(60);

    sf::RenderTexture target;
    {
        auto winSize = window.getSize();
        target.create(winSize.x, winSize.y);
    }
    auto &targetTexture = target.getTexture();
    sf::Sprite targetSprite(targetTexture);

    StaticFonts::initFonts();

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

    auto package_cpath = std::filesystem::path("resources") / "lua" / "lib" / "lua" / SOMEONE_LUA_VERSION / "?." LIB_EXT ";";
    lua["package"]["cpath"] = std::string(package_cpath.u8string()) + std::string(lua["package"]["cpath"]);

    register_usertypes(lua);

    lua.script("require('moonscript')");
    CoroutinesEnv coroutines_env(lua);
    TerminalEnv terminal_env(lua);
    WalkingEnv walking_env(lua);

    auto current_state = CurrentState::Terminal;

    auto current_state_type = lua.new_enum(
        "CurrentState",
        "Terminal", CurrentState::Terminal,
        "Walking", CurrentState::Walking
    );
    current_state_type["GLOBAL"] = lua.create_table_with(
        "drawing_target", &target,
        "set_current_state", [&](CurrentState new_state) { current_state = new_state; }
    );

    sf::Clock clock;
    while (true) {
        auto dt = clock.restart().asSeconds();

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

            default: break;
            }

            switch (current_state) {
            case CurrentState::Terminal:
                terminal_env.process_event(event);
                break;
            case CurrentState::Walking:
                walking_env.add_event(event);
                break;
            }
        }

        switch (current_state) {
        case CurrentState::Terminal:
            terminal_env.update_event_timer(dt);
            terminal_env.draw(dt);
            break;
        case CurrentState::Walking:
            walking_env.update(dt);
            walking_env.draw();

            break;
        }

        // After everything has been drawn and processed, but before it's actually drawn to the screen,
        // run the coroutines
        coroutines_env.run();

        target.display();

        window.clear();

        switch (current_state) {
        case CurrentState::Terminal:
            window.draw(targetSprite);
            break;
        case CurrentState::Walking:
            walking_env.draw_target_to_window(window, targetSprite);
            break;
        }

        window.display();
    }
}
