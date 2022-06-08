#pragma once

#include "SDL.h"

#include "SFML/System/Vector2.hpp"
#include "SFML/Graphics/Drawable.hpp"
#include "SFML/Graphics/Shader.hpp"
#include "SFML/Graphics/View.hpp"

namespace sf {

extern SDL_Renderer *currentRenderer;

class RenderTarget {
protected:
    View view;
public:
    virtual void draw(Drawable &drawable, Shader *shader = nullptr) = 0;

    virtual void setView(View other) { view = other; }
    View getView() { return view; }
    View getDefaultView() { return View(); }

    Vector2f mapPixelToCoords(Vector2i pos) const {
        Vector2i result;
        SDL_RenderLogicalToWindow(currentRenderer, pos.x, pos.y, &result.x, &result.y);

        return {(float)result.x, (float)result.y};
    }
    Vector2i mapCoordsToPixel(Vector2f pos) const {
        Vector2f result;
        SDL_RenderWindowToLogical(currentRenderer, pos.x, pos.y, &result.x, &result.y);

        return {(int)result.x, (int)result.y};
    }

    virtual Vector2u getSize() const = 0;

    virtual ~RenderTarget() { }
};
}
