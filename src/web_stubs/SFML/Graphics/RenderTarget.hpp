#pragma once

#include "SDL.h"

#include "SFML/System/Vector2.hpp"
#include "SFML/Graphics/Drawable.hpp"
#include "SFML/Graphics/Shader.hpp"

namespace sf {
class RenderTarget {
public:
    virtual void draw(Drawable &drawable, Shader *shader = nullptr) = 0;

    void display() {
        //SDL_RenderPresent(renderer);
    }

    virtual Vector2u getSize() const = 0;

    virtual ~RenderTarget() { }
};
}
