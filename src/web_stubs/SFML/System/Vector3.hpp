#pragma once

namespace sf {

template <typename T>
struct Vector3 {
    T x {}, y {}, z {};

    Vector3() { }
    Vector3(T x, T y, T z) : x(x), y(y), z(z) { }
};

using Vector3f = Vector3<float>;
using Vector3u = Vector3<unsigned int>;
using Vector3i = Vector3<int>;

template<typename T>
bool operator==(const sf::Vector3<T> &left, const sf::Vector3<T> &right) {
    return left.x == right.x && left.y == right.y && left.z == right.z;
}

template<typename T>
Vector3<T> operator+(const sf::Vector3<T> &left, const sf::Vector3<T> &right) {
    return Vector3(left.x + right.x, left.y + right.y, left.z + right.z);
}

template<typename T>
Vector3<T> operator-(const sf::Vector3<T> &left, const sf::Vector3<T> &right) {
    return Vector3(left.x - right.x, left.y - right.y, left.z - right.z);
}

template<typename T>
Vector3<T> operator*(const sf::Vector3<T> &left, T right) {
    return Vector3(left.x * right, left.y * right, left.z * right);
}

template<typename T>
Vector3<T> operator*(T right, const sf::Vector3<T> &left) {
    return Vector3(left.x * right, left.y * right, left.z * right);
}

template<typename T>
Vector3<T> operator/(const sf::Vector3<T> &left, T right) {
    return Vector3(left.x / right, left.y / right, left.z / right);
}

}
