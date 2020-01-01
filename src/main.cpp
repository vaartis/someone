#include <SFML/Window/Event.hpp>
#include <SFML/Graphics/RenderWindow.hpp>
#include <SFML/System/Clock.hpp>

#include "logger.hpp"

#include "string_utils.hpp"
#include "fonts.hpp"
#include "term.hpp"

using namespace sf;

int main() {
    RenderWindow window(VideoMode(1280, 1024), "Vacances");
    window.setFramerateLimit(60);

    StaticFonts::initFonts();

    Terminal term(window, "prologue/1");

    sf::Clock clock;
    while (true) {
        auto dt = clock.restart().asSeconds();

        window.clear(sf::Color::White);

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

            term.processEvent(event);
        }

        term.draw(dt);
        window.display();
    }
}
