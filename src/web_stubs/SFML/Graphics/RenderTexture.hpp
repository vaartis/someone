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
