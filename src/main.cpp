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

enum class CurrentState {
    Terminal,
    Walking
};

int main() {
    #ifndef NDEBUG
    spdlog::set_level(spdlog::level::debug);
    #endif

    sf::RenderWindow window(sf::VideoMode(1280, 1024), "Vacances");
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
    lua["package"]["path"] = std::string(
        "resources/lua/share/lua/" VACANCES_LUA_VERSION "/?.lua;resources/lua/share/lua/" VACANCES_LUA_VERSION "/?/init.lua;"
    ) + std::string(lua["package"]["path"]);
    lua["package"]["cpath"] = std::string(
        "resources/lua/lib/lua/" VACANCES_LUA_VERSION "/?.so;"
    ) + std::string(lua["package"]["cpath"]);

    register_usertypes(lua);

    TerminalEnv terminal_env(lua);
    WalkingEnv walking_env(lua);

    auto current_state = CurrentState::Walking;

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
            terminal_env.draw(dt);
            break;
        case CurrentState::Walking:
            walking_env.update(dt);
            walking_env.draw();

            break;
        }

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
