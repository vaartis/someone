#pragma once

namespace sf {

template<typename T>
struct Rect {
    T left {}, top {}, width {}, height {};

    Rect() = default;
    Rect(T left, T top, T width, T height) : left(left), top(top), width(width), height(height) { }
};

using FloatRect = Rect<float>;
using IntRect = Rect<int>;
}
