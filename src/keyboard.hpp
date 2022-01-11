#include <map>

#include <SFML/Window/Event.hpp>

namespace someone {

class KeypressTracker {
    inline static std::map<sf::Keyboard::Key, bool> buttons;

public:

    static void processEvent(const sf::Event &event) {
        switch (event.type) {
        case sf::Event::KeyPressed:
            buttons[event.key.code] = true;

            break;
        case sf::Event::KeyReleased:
            buttons[event.key.code] = false;

            break;

        case sf::Event::LostFocus:
            // Clear all button presses when losing focus
            buttons.clear();

            break;
        default: break;
        }
    }

    static bool is_key_pressed(sf::Keyboard::Key key) {
        return buttons.contains(key) && buttons[key];
    }
};

}
