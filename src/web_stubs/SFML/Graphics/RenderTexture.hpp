#pragma once

#include <SDL.h>

#include "SFML/Graphics/Drawable.hpp"
#include "SFML/Graphics/Transformable.hpp"
#include <SFML/Graphics/Texture.hpp>
#include <SFML/Graphics/RenderTarget.hpp>
#include <SFML/System/Vector2.hpp>
#include <SFML/Graphics/Color.hpp>

namespace sf {

extern SDL_Renderer *currentRenderer;

class RenderTexture : public RenderTarget, public Drawable {
    Texture texture;
public:
    void create(unsigned w, unsigned h) {
        auto *texturePtr = SDL_CreateTexture(currentRenderer, SDL_PIXELFORMAT_RGBA32, SDL_TEXTUREACCESS_TARGET, w, h);
        if (!texturePtr) {
            spdlog::error("{}", SDL_GetError());
            return;
        }

        texture = Texture(texturePtr);
    }

    Vector2u getSize() const override {
        return texture.getSize();
    }

    void setView(View other) override {
        RenderTarget::setView(other);

        if (view.isDefault()) {
            SDL_RenderSetViewport(currentRenderer, nullptr);
            SDL_RenderSetClipRect(currentRenderer, nullptr);
        } else {
            SDL_Rect viewRect;
            viewRect.x = view.viewport.left;
            viewRect.y = view.viewport.top;
            viewRect.w = view.viewport.width;
            viewRect.h = view.viewport.height;

            SDL_Rect clipRect;
            clipRect.x = view.shownRect.left;
            clipRect.y = view.shownRect.top;
            clipRect.w = view.shownRect.width;
            clipRect.h = view.shownRect.height;

            SDL_RenderSetViewport(currentRenderer, &viewRect);
            SDL_RenderSetClipRect(currentRenderer, &clipRect);
        }
    }

    void clear(const sf::Color &color) {
        SDL_SetRenderTarget(currentRenderer, texture.texture);

        SDL_SetRenderDrawColor(currentRenderer, color.r, color.g, color.b, color.a);
        SDL_RenderFillRect(currentRenderer, nullptr);
        SDL_SetRenderTarget(currentRenderer, nullptr);
    }

    void drawToTarget() override {
        SDL_RenderCopy(currentRenderer, texture.texture, nullptr, nullptr);
    }

    void draw(Drawable &drawable, Shader *shader = nullptr) override {
        SDL_SetRenderTarget(currentRenderer, texture.texture);

        drawable.drawToTarget();

        SDL_SetRenderTarget(currentRenderer, nullptr);
    }
};

}
