#pragma once

#include "SDL.h"

namespace sf {
class Drawable {
public:
    virtual void drawToTarget() { }

    virtual ~Drawable() {}
};
}
