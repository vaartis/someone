#pragma once

#include "SDL.h"
#include "SDL_gpu.h"
#include "SDL_render.h"

#include "SFML/Graphics/Texture.hpp"
#include "SFML/Graphics/RenderTarget.hpp"
#include "SFML/System/Vector2.hpp"
#include "SFML/Graphics/Color.hpp"

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
        //GPU_SetImageVirtualResolution(texture.texture, w, h);
    }

    Vector2u getSize() const override {
        return texture.getSize();
    }

    void setView(View other) override {
        RenderTarget::setView(other);

        if (view.isDefault()) {
            GPU_UnsetViewport(texture.getTarget());
            GPU_UnsetClip(texture.getTarget());
        } else {
            // This doesn't work for some reason, but I don't really need it anyway
            //GPU_SetViewport(texture.getTarget(), GPU_MakeRect(view.viewport.left, view.viewport.top, view.viewport.width, view.viewport.height));
            GPU_SetClipRect(texture.getTarget(), GPU_MakeRect(view.shownRect.left, view.shownRect.top, view.shownRect.width, view.shownRect.height));
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
