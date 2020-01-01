#pragma once

#include <SFML/Graphics/Font.hpp>

struct StaticFonts {
    static sf::Font main_font;

    static void initFonts();

    static const uint32_t font_size = 16;
};
