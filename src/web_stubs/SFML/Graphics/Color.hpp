#pragma once

#include <cstdint>

namespace sf {
struct Color {
    uint8_t r = 0, g = 0, b = 0, a = 255;

    Color() = default;
    Color(uint8_t r, uint8_t g, uint8_t b, uint8_t a = 255) : r(r), g(g), b(b), a(a) { }

    static const Color White, Transparent, Black, Red, Yellow, Green;
};

inline bool operator==(const Color &left, const Color &right) {
    return left.r == right.r && left.g == right.g && left.b == right.b && left.a == right.a;
}

inline const Color Color::Black(0, 0, 0);
inline const Color Color::White(255, 255, 255);
inline const Color Color::Red(255, 0, 0);
inline const Color Color::Green(0, 255, 0);
inline const Color Color::Yellow(255, 255, 0);
inline const Color Color::Transparent(0, 0, 0, 0);

}
