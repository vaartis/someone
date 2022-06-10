#pragma once

#include <string>

#include <SFML/System/Vector2.hpp>

#include <SDL_gpu.h>

#include "logger.hpp"

namespace sf {

class Texture {
    int w = 0, h = 0;

    GPU_Target *target = nullptr;

    void updateForTexture() {
        w = texture->w;
        h = texture->h;
        format = texture->format;

        GPU_SetImageFilter(texture, GPU_FILTER_NEAREST);
    }
public:
    uint32_t format = 0;

    GPU_Image *texture = nullptr;

    Texture() = default;

    Texture(GPU_Image *texture) : texture(texture) {
        updateForTexture();
    }

    Texture(const Texture&) = delete;
    void operator=(Texture const &) = delete;
    Texture &operator=(Texture&& other) {
        texture = other.texture;
        updateForTexture();

        other.texture = nullptr;

        return *this;
    }

    void loadFromFile(const std::string &filename) {
        texture = GPU_LoadImage(filename.c_str());
        if (!texture) {
            spdlog::error("Failed loading {}: {}", filename, GPU_PopErrorCode().details);
            return;
        }
        updateForTexture();
    }

    Vector2u getSize() const {
        return Vector2u(w, h);
    }

    GPU_Target *getTarget() {
        if (target == nullptr)
            target = GPU_LoadTarget(texture);
        return target;
    }

    ~Texture() {
        if (texture != nullptr)
            GPU_FreeImage(texture);
        if (target != nullptr)
            GPU_FreeTarget(target);
    }
};
}
