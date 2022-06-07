#pragma once

#include <SDL.h>
#include <SDL2_rotozoom.h>

#include "SFML/System/Rect.hpp"
#include "SFML/Graphics/Transformable.hpp"
#include "SFML/Graphics/RenderTexture.hpp"
#include "SFML/Graphics/Texture.hpp"

namespace sf {
class Sprite : public Transformable, public Drawable {
    Texture *texture = nullptr;

    IntRect textureRect;
public:
    Sprite() = default;
    Sprite(Texture *texture) : texture(texture) { }

    void setTexture(Texture *newTexture) {
        texture = newTexture;

        textureRect.left = 0;
        textureRect.top = 0;

        Vector2u textureSize = newTexture->getSize();
        textureRect.width = textureSize.x;
        textureRect.height = textureSize.y;
    }

    IntRect getTextureRect() { return textureRect; }
    void setTextureRect(const IntRect &rect) {
        textureRect = rect;
    }

    IntRect getGlobalBounds() {
        IntRect result;

        auto position = getPosition();
        result.top = position.x;
        result.left = position.y;

        auto scale = getScale();
        rotozoomSurfaceSizeXY(textureRect.width, textureRect.height,
                            getRotation(), scale.x, scale.y,
                            &result.width, &result.height);

        return result;
    }

    Texture *getTexture() {
        return texture;
    }
};
}
