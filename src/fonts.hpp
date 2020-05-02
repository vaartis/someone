#pragma once

#include <SFML/Graphics/Font.hpp>

struct StaticFonts {
    StaticFonts();

    sf::Font main_font;
    static constexpr uint32_t font_size = 16;
};
