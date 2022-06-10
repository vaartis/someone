#pragma once

#include <SDL_timer.h>
#include <cstdint>

#include "SDL.h"

namespace sf {

class Time {
    uint64_t ms;
public:
    Time(uint64_t ms) : ms(ms) { }

    uint64_t asMilliseconds() { return ms; }
    float asSeconds() {
        return (float)ms / 1000.0;
    }
};

class Clock {
    uint64_t startTime;
public:
    Clock() {
        startTime = SDL_GetTicks64();
    }

    Time restart() {
        auto ticks = SDL_GetTicks64();
        auto result = Time(ticks - startTime);

        // Update time
        startTime = SDL_GetTicks64();

        return result;
    }
};

}
