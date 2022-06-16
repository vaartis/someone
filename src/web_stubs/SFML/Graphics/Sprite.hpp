#pragma once

#include "SDL.h"
#include "SDL_render.h"

#include "SFML/System/Rect.hpp"
#include "SFML/Graphics/Transformable.hpp"
#include "SFML/Graphics/RenderTexture.hpp"
#include "SFML/Graphics/Texture.hpp"

namespace sf {
class Sprite : public Transformable, public Drawable {
protected:
    Texture *texture = nullptr;

    Color color = Color::White;
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

    sf::Color &getColor() { return color; }
    void setColor(sf::Color other) { color = other; }

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

        auto unscaledOrigin = getUnscaledOrigin();

        GPU_SetRGBA(texture->texture, color.r, color.g, color.b, color.a);
        GPU_BlitRectX(
            texture->texture,
            &texRect,
            toTarget,
            &dstRect,
            getRotation(),
            unscaledOrigin.x,
            unscaledOrigin.y,
            flip
        );
        GPU_UnsetColor(texture->texture);
    }

    Texture *getTexture() {
        return texture;
    }

    virtual ~Sprite() { }
};

class NineSliceSprite : public Sprite {
    Vector2i size;
public:
    const Vector2i &getSize() { return size; };
    void setSize(Vector2i other) { size = other; };

    void drawToTarget(GPU_Target *toTarget) override {
        auto texSize = texture->getSize();

        auto topLeftRect = GPU_MakeRect(0, 0, textureRect.left, textureRect.top);
        auto topCenterRect = GPU_MakeRect(textureRect.left, 0, textureRect.width, textureRect.top);
        auto topRightRect = GPU_MakeRect(textureRect.left + textureRect.width, 0, texSize.x - (textureRect.left + textureRect.width), textureRect.top);

        auto centerLeftRect = GPU_MakeRect(0, textureRect.top, textureRect.left, textureRect.height);
        auto centerRect = GPU_MakeRect(textureRect.left, textureRect.top, textureRect.width, textureRect.height);
        auto centerRightRect = GPU_MakeRect(topRightRect.x, textureRect.top, topRightRect.w, textureRect.height);

        auto bottomLeftRect = GPU_MakeRect(0, textureRect.top + textureRect.height, textureRect.left, textureRect.top);
        auto bottomCenterRect = GPU_MakeRect(topCenterRect.x, bottomLeftRect.y,
                                             textureRect.width, texSize.y - (textureRect.top + textureRect.height));
        auto bottomRightRect = GPU_MakeRect(topRightRect.x, bottomLeftRect.y,
                                            topRightRect.w, topRightRect.h);

        auto bounds = getGlobalBounds();
        GPU_Rect dstRect = GPU_MakeRect(bounds.left, bounds.top, topLeftRect.w, topLeftRect.h);

        GPU_SetRGBA(texture->texture, color.r, color.g, color.b, color.a);

        GPU_BlitRect(
            texture->texture,
            &topLeftRect,
            toTarget,
            &dstRect
        );
        dstRect.x += dstRect.w;
        dstRect.w = size.x - (topLeftRect.w + topRightRect.w);
        GPU_BlitRect(
            texture->texture,
            &topCenterRect,
            toTarget,
            &dstRect
        );
        dstRect.x += dstRect.w;
        dstRect.w = topRightRect.w;
        GPU_BlitRect(
            texture->texture,
            &topRightRect,
            toTarget,
            &dstRect
        );
        dstRect.x = bounds.left;
        dstRect.y = bounds.top + topLeftRect.h;
        dstRect.w = centerLeftRect.w;
        dstRect.h = size.y - (topLeftRect.h + bottomLeftRect.h);
        GPU_BlitRect(
            texture->texture,
            &centerLeftRect,
            toTarget,
            &dstRect
        );
        dstRect.x += dstRect.w;
        dstRect.w = size.x - (topLeftRect.w + topRightRect.w);
        GPU_BlitRect(
            texture->texture,
            &centerRect,
            toTarget,
            &dstRect
        );
        dstRect.x += dstRect.w;
        dstRect.w = centerRightRect.w;
        GPU_BlitRect(
            texture->texture,
            &centerRightRect,
            toTarget,
            &dstRect
        );
        dstRect.x = bounds.left;
        dstRect.y += dstRect.h;
        dstRect.w = bottomLeftRect.w;
        dstRect.h = bottomLeftRect.h;
        GPU_BlitRect(
            texture->texture,
            &bottomLeftRect,
            toTarget,
            &dstRect
        );
        dstRect.x += dstRect.w;
        dstRect.w = size.x - (topLeftRect.w + topRightRect.w);
        GPU_BlitRect(
            texture->texture,
            &bottomCenterRect,
            toTarget,
            &dstRect
        );
        dstRect.x += dstRect.w;
        dstRect.w = bottomRightRect.w;
        GPU_BlitRect(
            texture->texture,
            &bottomRightRect,
            toTarget,
            &dstRect
        );


        GPU_UnsetColor(texture->texture);
    }
};
}
