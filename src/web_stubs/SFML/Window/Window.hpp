#pragma once

#include "spdlog/spdlog.h"
#include <SDL_error.h>
#include <SDL_render.h>
#include <SDL_scancode.h>
#include <SDL_video.h>
#include <string>

#include <SDL.h>
#include <SDL_image.h>
#include <SDL_ttf.h>

#include <SFML/Graphics/Shader.hpp>
#include <SFML/Graphics/RenderTarget.hpp>
#include <SFML/Graphics/Sprite.hpp>
#include <SFML/System/Vector2.hpp>

namespace sf {

inline SDL_Renderer *currentRenderer = nullptr;

struct VideoMode {
    unsigned int w = 0, h = 0;

    VideoMode() = default;
    VideoMode(int w, int h) : w(w), h(h) { }
};

struct Keyboard {
    enum Key {
        Tilde = SDL_SCANCODE_GRAVE,
        F1 = SDL_SCANCODE_F1,
        W = SDL_SCANCODE_W,
        A = SDL_SCANCODE_A,
        S = SDL_SCANCODE_S,
        D = SDL_SCANCODE_D,
        E = SDL_SCANCODE_E,
        L = SDL_SCANCODE_L,
        Z = SDL_SCANCODE_Z,
        X = SDL_SCANCODE_X,
        R = SDL_SCANCODE_R,
        M = SDL_SCANCODE_M,
        Q = SDL_SCANCODE_Q,
        B = SDL_SCANCODE_B,
        LControl = SDL_SCANCODE_LCTRL,
        LShift = SDL_SCANCODE_LSHIFT,
        Return = SDL_SCANCODE_RETURN,
        Backspace = SDL_SCANCODE_BACKSPACE,
        Space = SDL_SCANCODE_SPACE,
        Num1 = SDL_SCANCODE_1
    };

    static bool isKeyPressed(Key key) {
        const uint8_t *state = SDL_GetKeyboardState(nullptr);
        return state[key];
    }
};

struct Event {
    enum EventType {
        Unknown,
        Closed,
        KeyReleased,
        KeyPressed,
        TextEntered
    };

    struct KeyEvent {
        Keyboard::Key code;
        bool alt;
        bool control;
        bool shift;
        bool system;
    };

    struct TextEvent {
        uint32_t unicode;
    };

    EventType type;

    KeyEvent key;
    TextEvent text;
};

class RenderWindow : public RenderTarget {
    SDL_Window *window = nullptr;
    SDL_Renderer *renderer = nullptr;

    float frameLimit;
public:
    RenderWindow(const VideoMode mode, const std::string &title) {
        int rendererFlags = SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC, windowFlags = SDL_WINDOW_OPENGL;

        SDL_Init(SDL_INIT_VIDEO);
        IMG_Init(IMG_INIT_PNG);
        TTF_Init();

        window = SDL_CreateWindow(title.c_str(), SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, mode.w, mode.h, windowFlags);
        if (!window)
            spdlog::error("{}", SDL_GetError());

        renderer = SDL_CreateRenderer(window, -1, rendererFlags);
        if (!renderer)
            spdlog::error("{}", SDL_GetError());

        currentRenderer = renderer;
    }

    void draw(Drawable &drawable, Shader *shader = nullptr) override {
        drawable.drawToTarget();
    }

    void setSize(Vector2u newSize) {
        SDL_SetWindowSize(window, newSize.x, newSize.y);
    }

    void setPosition(Vector2i pos) {
        SDL_SetWindowPosition(window, pos.x, pos.y);
    }

    void setFramerateLimit(float limit) { frameLimit = limit; };

    void display() {
        SDL_RenderPresent(renderer);
    }

    bool hasFocus() {
        uint32_t flags = SDL_GetWindowFlags(window);
        return (flags & SDL_WINDOW_INPUT_FOCUS) || (flags & SDL_WINDOW_MOUSE_FOCUS);
    }

    Vector2u getSize() const override {
        Vector2u result;

        SDL_GetWindowSize(window, (int *)&result.x, (int *)&result.y);

        return result;
    }

    bool pollEvent(Event &theEvent) {
        SDL_Event sdlEvent;
        bool result = SDL_PollEvent(&sdlEvent) == 1;

        switch (sdlEvent.type) {
        case SDL_QUIT: {
            theEvent.type = Event::Closed;
            break;
        }
        case SDL_KEYDOWN:
        case SDL_KEYUP: {
            theEvent.type = sdlEvent.key.type == SDL_KEYDOWN ? Event::KeyPressed : Event::KeyReleased;

            SDL_Keymod mods = SDL_GetModState();
            theEvent.key.alt = (mods & KMOD_ALT);
            theEvent.key.control = (mods & KMOD_CTRL);
            theEvent.key.shift = (mods & KMOD_SHIFT);
            theEvent.key.system = (mods & KMOD_GUI);
            theEvent.key.code = (Keyboard::Key)sdlEvent.key.keysym.scancode;

            break;
        }
        case SDL_TEXTINPUT: {
            theEvent.type = Event::TextEntered;
            theEvent.text.unicode = sdlEvent.text.text[0];

            break;
        }
        }

        return result;
    }

    void clear() {
        SDL_RenderClear(renderer);
    }

    void close() {
        SDL_DestroyRenderer(renderer);
        SDL_DestroyWindow(window);
    }

    ~RenderWindow() {
        IMG_Quit();
        TTF_Quit();
        SDL_Quit();
    }
};
}
