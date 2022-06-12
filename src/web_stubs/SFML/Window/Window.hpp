#pragma once

#include <string>

#include "SDL.h"
#include "SDL_ttf.h"
#include "SDL_gpu.h"

#include "SFML/Graphics/RenderTexture.hpp"
#include "SFML/Graphics/Texture.hpp"
#include "SFML/Graphics/Shader.hpp"
#include "SFML/Graphics/RenderTarget.hpp"
#include "SFML/Graphics/Sprite.hpp"
#include "SFML/System/Vector2.hpp"

namespace sf {

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
        TextEntered,
        GainedFocus,
        LostFocus
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

    SDL_Event sdlEvent;

    EventType type = Unknown;

    KeyEvent key;
    TextEvent text;
};

class RenderWindow : public RenderTarget {
    VideoMode mode;
public:
    SDL_Window *window = nullptr;
    GPU_Target *target = nullptr;

    SDL_GLContext glContext = nullptr;

    RenderWindow(const VideoMode mode, const std::string &title) : mode(mode) {
        SDL_Init(SDL_INIT_VIDEO);
        TTF_Init();

        target = GPU_Init(mode.w, mode.h, GPU_DEFAULT_INIT_FLAGS);
        if (!target)
            spdlog::error("{}", GPU_PopErrorCode().details);

        window = SDL_GetWindowFromID(target->context->windowID);
        SDL_SetWindowTitle(window, title.c_str());

        GPU_SetDefaultAnchor(0, 0);
        GPU_SetVirtualResolution(target, mode.w, mode.h);
    }

    void draw(RenderTexture &texture, Shader *shader = nullptr) {
        texture.drawToTarget(target);

        if (shader != nullptr)
            shader->drawWithTexture(texture, target);
    }

    void draw(Drawable &drawable) override {
        drawable.drawToTarget(target);
    }

    void setSize(Vector2u newSize) {
        GPU_SetWindowResolution(newSize.x, newSize.y);
        GPU_SetVirtualResolution(target, mode.w, mode.h);
    }

    void setPosition(Vector2i pos) {
        SDL_SetWindowPosition(window, pos.x, pos.y);
        GPU_SetVirtualResolution(target, mode.w, mode.h);
    }

    void display() override {
        GPU_Flip(target);
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
        case SDL_WINDOWEVENT:
            if (sdlEvent.window.type == SDL_WINDOWEVENT_FOCUS_GAINED) {
                theEvent.type = Event::GainedFocus;
            } else if (sdlEvent.window.type == SDL_WINDOWEVENT_FOCUS_LOST) {
                theEvent.type = Event::LostFocus;
            }

            break;
        default:
            theEvent.type = Event::Unknown;
            break;
        }
        theEvent.sdlEvent = sdlEvent;

        return result;
    }

    void clear() {
        GPU_Clear(target);
    }

    void close() {
        SDL_DestroyWindow(window);
    }

    ~RenderWindow() {
        TTF_Quit();
        GPU_Quit();
        SDL_Quit();
    }
};
}
