#pragma once

#include <SDL_gpu.h>

namespace sf {
class Drawable {
public:
    virtual void drawToTarget(GPU_Target *toTarget) { }

    virtual ~Drawable() {}
};
}
