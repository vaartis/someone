#pragma once

namespace sf {
template <typename T>
struct Vector2 {
    T x {}, y {};

    Vector2() { }
    Vector2(T x, T y) : x(x), y(y) { }

    operator Vector2<float>() {
        Vector2<float> result;
        result.x = (float)x;
        result.y = (float)y;

        return result;
    }
};

using Vector2f = Vector2<float>;
using Vector2u = Vector2<unsigned int>;
using Vector2i = Vector2<int>;

template<typename T>
bool operator==(const sf::Vector2<T> left, const sf::Vector2<T> &right) {
    return left.x == right.x && left.y == right.y;
}

template<typename T>
Vector2<T> operator+(const sf::Vector2<T> &left, const sf::Vector2<T> &right) {
    return Vector2(left.x + right.x, left.y + right.y);
}

template<typename T>
Vector2<T> operator-(const sf::Vector2<T> &left, const sf::Vector2<T> &right) {
    return Vector2(left.x - right.x, left.y - right.y);
}

template<typename T>
Vector2<T> operator*(const sf::Vector2<T> &left, T right) {
    return Vector2(left.x * right, left.y * right);
}

template<typename T>
Vector2<T> operator*(T right, const sf::Vector2<T> &left) {
    return Vector2(left.x * right, left.y * right);
}

template<typename T>
Vector2<T> operator*(const sf::Vector2<T> &left, const sf::Vector2<T> &right) {
    return Vector2(left.x * right.x, left.y * right.x);
}


template<typename T>
Vector2<T> operator/(const sf::Vector2<T> &left, T right) {
    return Vector2(left.x / right, left.y / right);
}

}
