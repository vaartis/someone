#pragma once

#include "SDL_gpu.h"

#include "SFML/Graphics/Color.hpp"
#include "SFML/Graphics/Drawable.hpp"
#include "SFML/Graphics/Transformable.hpp"
#include "SFML/System/Vector2.hpp"

namespace sf {

class RectangleShape : public Drawable, public Transformable {
    Vector2f size;

    Color fillColor = Color::Transparent, outlineColor = Color::Transparent;
public:
    RectangleShape(const Vector2f &size) : size(size) {

    }

    void setOutlineColor(const Color &other) { outlineColor = other; }
    Color getOutlineColor() { return outlineColor; }

    void setFillColor(const Color &other) { fillColor = other; }
    Color getFillColor() { return fillColor; }

    void drawToTarget(GPU_Target *toTarget) override {
        auto pos = getPosition();
        SDL_Rect rect = {
            .x = (int)pos.x, .y = (int)pos.y,
            .w = (int)size.x, .h = (int)size.y
        };

        GPU_Rectangle(
            toTarget,
            pos.x, pos.y, pos.x + size.x, pos.y + size.y,
            SDL_Color { outlineColor.r, outlineColor.g, outlineColor.b, outlineColor.a }
        );
        GPU_RectangleFilled(
            toTarget,
            pos.x, pos.y, pos.x + size.x, pos.y + size.y,
            SDL_Color { fillColor.r, fillColor.g, fillColor.b, fillColor.a }
        );
    }
};
}
