#pragma once

#include "SFML/System/Rect.hpp"

class RenderTarget;

namespace sf {
class View {
    FloatRect viewport;
    FloatRect shownRect;
public:
    void setViewport(FloatRect other) { viewport = other; }
    FloatRect getViewport() { return viewport; }

    void reset(FloatRect pos) { shownRect = pos; }

    bool isDefault() {
        return viewport.height == 0 && viewport.width == 0;
    }

    friend class RenderTexture;
};
}
