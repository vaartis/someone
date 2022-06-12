#pragma once

#include "SFML/System/Vector2.hpp"

namespace sf {
class Transformable {
    Vector2f position;
    Vector2f origin;
    Vector2f scale { 1, 1 };
    float rotation = 0;

public:
    Vector2f &getPosition() { return position; }
    void setPosition(const Vector2f &pos) { position = pos; }

    Vector2f getOrigin() { return { std::abs(origin.x * scale.x), std::abs(origin.y * scale.y) }; }
    void setOrigin(const Vector2f &orig) { origin = orig; }

    Vector2f &getScale() { return scale; }
    void setScale(const Vector2f &scal) { scale = scal; }

    float getRotation() { return rotation; }
    void setRotation(float rot) {
        rotation = (int)rot % 360;
        if (rotation < 0) {
            rotation += 360;
        }
    }

    void rotate(float rot) {
        setRotation(rotation + rot);
    }

    virtual ~Transformable() { }
};
}
