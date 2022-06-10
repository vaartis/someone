#pragma once

#include "SDL_gpu.h"

#include "SFML/System/Vector2.hpp"
#include "SFML/Graphics/Drawable.hpp"
#include "SFML/Graphics/View.hpp"


namespace sf {

class RenderTarget {
protected:
    View view;
public:
    virtual void display() = 0;
    virtual void draw(Drawable &drawable) = 0;

    virtual void setView(View other) { view = other; }
    View getView() { return view; }
    View getDefaultView() { return View(); }

    Vector2f mapPixelToCoords(Vector2i pos) const {
        Vector2i result = { pos.x, pos.y };
        //SDL_RenderLogicalToWindow(currentRenderer, pos.x, pos.y, &result.x, &result.y);

        return {(float)result.x, (float)result.y};
    }
    Vector2i mapCoordsToPixel(Vector2f pos) const {
        Vector2f result = { pos.x, pos.y };
        //SDL_RenderWindowToLogical(currentRenderer, pos.x, pos.y, &result.x, &result.y);

        return {(int)result.x, (int)result.y};
    }

    virtual Vector2u getSize() const = 0;

    virtual ~RenderTarget() { }
};
}
