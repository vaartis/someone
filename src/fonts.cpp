#include "fonts.hpp"

#include <exception>

using namespace std;

sf::Font StaticFonts::main_font;

void StaticFonts::initFonts() {
    if (!main_font.loadFromFile("resources/fonts/Ubuntu-R.ttf")) {
        throw std::runtime_error("Error loading font");
    }
}
