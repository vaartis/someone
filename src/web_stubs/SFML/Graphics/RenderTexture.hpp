#pragma once

#include <SDL.h>

#include "SFML/Graphics/Drawable.hpp"
#include "SFML/Graphics/Transformable.hpp"
#include <SDL_gpu.h>
#include <SDL_render.h>
#include <SFML/Graphics/Texture.hpp>
#include <SFML/Graphics/RenderTarget.hpp>
#include <SFML/System/Vector2.hpp>
#include <SFML/Graphics/Color.hpp>

namespace sf {

class Shader;

class RenderTexture : public RenderTarget, public Drawable {
    Texture texture;

    friend class Shader;
public:
    void create(unsigned w, unsigned h) {
        GPU_Image *texturePtr = GPU_CreateImage(w, h, GPU_FORMAT_RGBA);
        if (!texturePtr) {
            spdlog::error("{}", GPU_PopErrorCode().details);
            return;
        }

        texture = Texture(texturePtr);
    }

    Vector2u getSize() const override {
        return texture.getSize();
    }

    void setView(View other) override {
        RenderTarget::setView(other);

        return;

        if (view.isDefault()) {
            GPU_UnsetViewport(texture.getTarget());
            GPU_UnsetClip(texture.getTarget());
        } else {
            GPU_Rect viewRect;
            viewRect.x = view.viewport.left;
            viewRect.y = view.viewport.top;
            viewRect.w = view.viewport.width;
            viewRect.h = view.viewport.height;

            GPU_Rect clipRect;
            clipRect.x = view.shownRect.left;
            clipRect.y = view.shownRect.top;
            clipRect.w = view.shownRect.width;
            clipRect.h = view.shownRect.height;

            GPU_SetViewport(texture.getTarget(), viewRect);
            GPU_SetClipRect(texture.getTarget(), clipRect);
        }
    }

    void display() override {
        GPU_Flip(texture.getTarget());
    }

    void clear(const sf::Color &color) {
        GPU_ClearColor(texture.getTarget(), SDL_Color { color.r, color.g, color.b, color.a });
    }

    void drawToTarget(GPU_Target *toTarget) override {
        GPU_Blit(texture.texture, nullptr, toTarget, 0, 0);
    }

    void draw(Drawable &drawable) override {
        drawable.drawToTarget(texture.getTarget());
    }
};

}
