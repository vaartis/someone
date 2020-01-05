#include <SFML/Window/Event.hpp>
#include <SFML/Graphics/RenderWindow.hpp>
#include <SFML/System/Clock.hpp>

#include "logger.hpp"

#include "string_utils.hpp"
#include "fonts.hpp"
#include "term.hpp"

#include "mainchar.hpp"

using namespace sf;

int main() {
    RenderWindow window(VideoMode(1280, 1024), "Vacances");
    window.setFramerateLimit(60);

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
    roomSprite.setColor(sf::Color(100, 100, 100));


    MainChar mainChar(window, "resources/sprites/mainchar");

    // Terminal term(window, "prologue/1");

    sf::Clock clock;
    while (true) {
        auto dt = clock.restart().asSeconds();

        window.clear(sf::Color::Black);

        sf::Event event;
        while (window.pollEvent(event)) {
            switch (event.type) {
            case sf::Event::Closed:
                window.close();

                return 0;

            case sf::Event::Resized: {
                float width = event.size.width,
                    height = event.size.height;
                window.setView(View(
                                   {width / 2, height / 2},
                                   {width, height}
                               ));
                break;
            }

            default: break;
            }

            //term.processEvent(event);
        }
        mainChar.update(dt);

        //term.draw(dt);
        window.draw(roomSprite);
        //window.draw(lightSprite);
        mainChar.display();
        window.display();
    }
}
