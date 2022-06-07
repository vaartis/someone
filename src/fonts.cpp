#include "fonts.hpp"

#include <stdexcept>

StaticFonts::StaticFonts() {
    if (!main_font.loadFromFile("resources/fonts/Ubuntu-R.ttf")) {
        throw std::runtime_error("Error loading font");
    }
}
