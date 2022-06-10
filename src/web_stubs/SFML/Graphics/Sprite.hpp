#pragma once

#include <SDL.h>
#include <SDL_render.h>

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

        auto orig = getOrigin();
        auto position = getPosition();
        auto scale = getScale();

        result.left = position.x - orig.x;
        result.top = position.y - orig.y;

        result.width = std::abs(textureRect.width * scale.x);
        result.height = std::abs(textureRect.height * scale.y);
        if (result.height == 0)
            result.height = 1;
        if (result.width == 0)
            result.width = 1;

        return result;
    }

    void drawToTarget(GPU_Target *toTarget) override {
        GPU_Rect texRect;
        texRect.x = textureRect.left;
        texRect.y = textureRect.top;
        texRect.h = textureRect.height;
        texRect.w = textureRect.width;

        auto bounds = getGlobalBounds();

        auto orig = getOrigin();
        auto scale = getScale();

        GPU_Rect dstRect;
        dstRect.x = bounds.left;
        dstRect.y = bounds.top;
        dstRect.w = bounds.width;
        dstRect.h = bounds.height;

        GPU_FlipEnum flip = GPU_FLIP_NONE;
        if (scale.x < 0) {
            flip = (SDL_RendererFlip)(flip | GPU_FLIP_HORIZONTAL);
        }
        if (scale.y < 0) {
            flip = (SDL_RendererFlip)(flip | GPU_FLIP_VERTICAL);
        }

        GPU_BlitRectX(
            texture->texture,
            &texRect,
            toTarget,
            &dstRect,
            getRotation(),
            orig.x,
            orig.y,
            flip
        );
    }

    Texture *getTexture() {
        return texture;
    }
};
}
