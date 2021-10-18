#include "fonts.hpp"

#include <stdexcept>

StaticFonts::StaticFonts() {
    if (!main_font.loadFromFile("resources/fonts/Abaddon Bold.ttf")) {
        throw std::runtime_error("Error loading font");
    }
}
