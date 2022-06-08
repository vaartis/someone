#pragma once

#include <string>

#include <SFML/System/Vector2.hpp>

#include <SDL_image.h>

#include "logger.hpp"

namespace sf {

extern SDL_Renderer *currentRenderer;

class Texture {
    int w = 0, h = 0;
public:
    uint32_t format = 0;
    SDL_Texture *texture = nullptr;

    Texture() = default;

    Texture(SDL_Texture *texture) : texture(texture) {
        SDL_QueryTexture(texture, &format, nullptr, &w, &h);
    }

    Texture(const Texture&) = delete;
    void operator=(Texture const &) = delete;
    Texture &operator=(Texture&& other) {
        texture = other.texture;
        SDL_QueryTexture(texture, &format, nullptr, &w, &h);

        other.texture = nullptr;

        return *this;
    }

    void loadFromFile(const std::string &filename) {
        SDL_Surface *surface = IMG_Load(filename.c_str());
        if (!surface) {
            spdlog::error("Failed loading {}", filename);
            return;
        }
        texture = SDL_CreateTextureFromSurface(currentRenderer, surface);
        SDL_FreeSurface(surface);

        SDL_QueryTexture(texture, &format, nullptr, &w, &h);
    }

    Vector2u getSize() const {
        return Vector2u(w, h);
    }

    ~Texture() {
        if (texture != nullptr)
            SDL_DestroyTexture(texture);
    }
};
}
