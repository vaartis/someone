#pragma once

#include <string>

#include <SFML/Graphics/Text.hpp>

struct StaticFonts {
    StaticFonts();

    sf::Font main_font;
    static constexpr unsigned int font_size = 16;
};
