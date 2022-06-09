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

        float x_scale_modifier = scale.x > 0 ? 1 - scale.x : scale.x * -1;
        float y_scale_modifier = scale.y > 0 ? 1 - scale.y : scale.y * -1;

        result.left = position.x - (orig.x * scale.x) - (textureRect.width * x_scale_modifier);
        result.top = position.y - (orig.y * scale.y) - (textureRect.height * y_scale_modifier);

        result.width = std::abs(textureRect.width * scale.x);
        result.height = std::abs(textureRect.height * scale.y);
        if (result.height == 0)
            result.height = 1;
        if (result.width == 0)
            result.width = 1;

        return result;
    }

    void drawToTarget() override {
        SDL_Rect texRect;
        texRect.x = textureRect.left;
        texRect.y = textureRect.top;
        texRect.h = textureRect.height;
        texRect.w = textureRect.width;

        auto bounds = getGlobalBounds();

        auto orig = getOrigin();
        auto scale = getScale();

        SDL_Rect dstRect;
        dstRect.x = bounds.left;
        dstRect.y = bounds.top;
        dstRect.w = bounds.width;
        dstRect.h = bounds.height;

        SDL_Point origin = { .x = (int)orig.x, .y = (int)orig.y };

        SDL_RendererFlip flip = SDL_FLIP_NONE;
        if (scale.x < 0) {
            flip = (SDL_RendererFlip)(flip | SDL_FLIP_HORIZONTAL);
        }
        if (scale.y < 0) {
            flip = (SDL_RendererFlip)(flip | SDL_FLIP_VERTICAL);
        }

        //spdlog::info("tex {} {} {} {}", texRect.x, texRect.y, texRect.w, texRect.h);
        //spdlog::info("dst {} {} {} {}", dstRect.x, dstRect.y, dstRect.w, dstRect.h);
        //spdlog::info("---");

        int result = SDL_RenderCopyEx(
            currentRenderer,
            texture->texture,
            &texRect,
            &dstRect,
            getRotation(),
            &origin,
            flip
        );

        if (result != 0)
            spdlog::error("{}", SDL_GetError());
    }

    Texture *getTexture() {
        return texture;
    }
};
}
