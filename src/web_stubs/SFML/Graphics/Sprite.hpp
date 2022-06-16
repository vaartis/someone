#pragma once

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

    struct Vertex {
        float x, y, u, v;
        float r = 1.0, g = 1.0, b = 1.0, a = 1.0;
    } __attribute__((packed));
public:
    const Vector2i &getSize() { return size; };
    void setSize(Vector2i other) { size = other; };

    void drawToTarget(GPU_Target *toTarget) override {
        auto bounds = getGlobalBounds();
        auto texSize = texture->getSize();

        float posX = bounds.left;
        float posY = bounds.top;

        float leftX = textureRect.left;
        float rightX = leftX + textureRect.width;
        float centerTopY = textureRect.top;
        float centerBottomY = centerTopY + textureRect.height;

        auto lx = leftX / texSize.x;
        auto rx = rightX / texSize.x;
        auto ty = centerTopY / texSize.y;
        auto by = centerBottomY / texSize.y;

        // Offsets to be used on the stretched texture to determine where the stretch points end
        auto rightXOffset = texSize.x - rightX;
        auto bottomYOffset = texSize.y - centerBottomY;

        // Now, after calculating texture positions, offset all positions to where they actually are on the screen,
        // this includes positioning rightX and centerBottomY to stretch
        leftX += posX;
        rightX = posX + size.x - rightXOffset;
        centerTopY += posY;
        centerBottomY = posY + size.y - bottomYOffset;
        float w = posX + size.x;
        float h = posY + size.y;

        // 0---l---r---w     0---1---2---3
        // |   |   |   |     | \ | \ | \ |
        // t---+---+---+     4---5---6---7
        // |   |   |   |     | \ | \ | \ |
        // b---+---+---+     8---9---A---B
        // |   |   |   |     | \ | \ | \ |
        // h---+---+---*     C---D---E---F
        std::array<uint16_t, 54> indices = {
            // First row
            0, 5, 4,
            0, 1, 5,

            1, 6, 5,
            1, 2, 6,

            2, 7, 6,
            2, 3, 7,

            // Second row
            4, 9, 8,
            4, 5, 9,

            5, 0xA, 9,
            5, 6, 0xA,

            6, 0xB, 0xA,
            6, 7, 0xB,

            // Third row
            8, 0xD, 0xC,
            8, 9, 0xD,

            9, 0xE, 0xD,
            9, 0xA, 0xE,

            0xA, 0xF, 0xE,
            0xA, 0xF, 0xB,
        };

        // Each member is x y u v r g b a, these members relate to the table comment above,
        // each member is the number in the table, from 1 to 16
        std::array<Vertex, 16> verts = {
            {
                // First row
                { posX, posY, 0, 0 },
                { leftX, posY, lx, 0 },
                { rightX, posY, rx, 0 },
                { w, posY, 1, 0 },
                // Second row
                { posX, centerTopY, 0, ty },
                { leftX, centerTopY, lx, ty },
                { rightX, centerTopY, rx, ty },
                { w, centerTopY, 1, ty },
                // Third row
                { posX, centerBottomY, 0, by },
                { leftX, centerBottomY, lx, by },
                { rightX, centerBottomY, rx, by },
                { w, centerBottomY, 1, by },
                // Fourth row
                { posX, h, 0, 1 },
                { leftX, h, lx, 1 },
                { rightX, h, rx, 1 },
                { w, h, 1, 1 }
            }
        };

        GPU_TriangleBatch(texture->texture, toTarget,
                          verts.size(), (float*)verts.data(),
                          indices.size(), indices.data(),
                          GPU_BATCH_XY_ST_RGBA);
    }
};
}
