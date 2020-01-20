#include <SFML/Graphics/Transformable.hpp>
#include <SFML/Window/Event.hpp>
#include <SFML/Graphics/RenderWindow.hpp>
#include <SFML/Graphics/RenderTexture.hpp>
#include <SFML/Graphics/Shader.hpp>
#include <SFML/System/Clock.hpp>
#include <SFML/Graphics/Text.hpp>

#include "sol/sol.hpp"

#include "logger.hpp"
#include "string_utils.hpp"
#include "fonts.hpp"
#include "story_parser.hpp"
#include "usertypes.hpp"
#include "mainchar.hpp"

int main() {
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

    sf::Texture lightTexture;
    lightTexture.loadFromFile("resources/sprites/room/light.png");
    sf::Sprite lightSprite(lightTexture);
    auto rect = lightSprite.getTextureRect();
    lightSprite.setOrigin(rect.width / 2, rect.height / 2);
    lightSprite.setPosition(387, 600);

    sf::Texture roomTexture;
    roomTexture.loadFromFile("resources/sprites/room/room.png");

    sf::Sprite roomSprite(roomTexture);

    //MainChar mainChar(target, "resources/sprites/mainchar");


    sol::state lua;
    lua.open_libraries(sol::lib::base, sol::lib::table, sol::lib::string, sol::lib::package, sol::lib::coroutine, sol::lib::math, sol::lib::debug);

    lua["package"]["path"] = std::string("resources/lua/share/lua/" VACANCES_LUA_VERSION "/?.lua;resources/lua/share/lua/" VACANCES_LUA_VERSION "/?/init.lua;") + std::string(lua["package"]["path"]);
    lua["package"]["cpath"] = std::string("resources/lua/lib/lua/" VACANCES_LUA_VERSION "/?.so;") + std::string(lua["package"]["cpath"]);

    register_usertypes(lua);

    auto t = sf::Text("test", StaticFonts::main_font, StaticFonts::font_size);
    lua["DRAWING_TARGET"] = &target;

    /*
    sf::Shader roomDarkerShader;
    roomDarkerShader.loadFromFile("resources/shaders/room_darker.frag",
sf::Shader::Fragment);

    roomDarkerShader.setUniform("screenSize", sf::Vector2f(target.getSize()));
    roomDarkerShader.setUniform("monitorTop", sf::Vector2f(237, 708));
    roomDarkerShader.setUniform("monitorBottom", sf::Vector2f(237, 765));
    roomDarkerShader.setUniform("ambientLightLevel", 0.4f);
    roomDarkerShader.setUniform("currentTexture", targetTexture);
    */

    auto lines = StoryParser::parse("resources/story/prologue.yml", lua);

    // This both defines a global for the module and returns it
    sol::table terminal_module = lua.require_script("TerminalModule", "return require('terminal')");

    // Add the lines from the loaded file
    sol::protected_function add_lines = terminal_module["add_native_lines"];
    {
        auto res = add_lines(lines);
        if (!res.valid())
            throw sol::error(res);
    }

    // After the lines are added, set up the first line on screen
    sol::protected_function set_first_line = terminal_module["set_first_line_on_screen"];
    {
        auto res = set_first_line("prologue/1");
        if (!res.valid())
            throw sol::error(res);
    }

    sol::protected_function draw_terminal = terminal_module["draw"];
    sol::protected_function process_terminal_event = terminal_module["process_event"];

    sf::Clock clock;
    while (true) {
        auto dt = clock.restart().asSeconds();

        target.clear(sf::Color::White);

        sf::Event event;
        while (window.pollEvent(event)) {
            switch (event.type) {
            case sf::Event::Closed:
                window.close();

                return 0;

            case sf::Event::Resized: {
                float width = event.size.width,
                    height = event.size.height;
                target.setView(sf::View(
                                   {width / 2, height / 2},
                                   {width, height}
                               ));
                break;
            }

            default: break;
            }

            {
                auto res = process_terminal_event(event);
                if (!res.valid())
                    throw sol::error(res);
            }
        }

        {
            auto res = draw_terminal(dt);
            if (!res.valid())
                throw sol::error(res);
        }

        //mainChar.update(dt);

        //target.draw(roomSprite);
        //window.draw(lightSprite);
        //mainChar.display();

        target.display();

        window.clear();
        window.draw(targetSprite);
        //window.draw(targetSprite, &roomDarkerShader);
        window.display();
    }
}
