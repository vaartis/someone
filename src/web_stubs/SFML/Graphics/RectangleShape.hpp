#pragma once

#include "SFML/Graphics/Color.hpp"
#include "SFML/Graphics/Drawable.hpp"
#include "SFML/Graphics/Transformable.hpp"
#include "SFML/System/Vector2.hpp"

namespace sf {

extern SDL_Renderer *currentRenderer;

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

    void drawToTarget() override {
        auto pos = getPosition();
        SDL_Rect rect = {
            .x = (int)pos.x, .y = (int)pos.y,
            .w = (int)size.x, .h = (int)size.y
        };

        SDL_SetRenderDrawColor(currentRenderer, outlineColor.r, outlineColor.g, outlineColor.b, outlineColor.a);
        SDL_RenderDrawRect(currentRenderer, &rect);
        SDL_SetRenderDrawColor(currentRenderer, fillColor.r, fillColor.g, fillColor.b, fillColor.a);
        SDL_RenderFillRect(currentRenderer, &rect);
    }
};
}
