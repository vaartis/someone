#pragma once

#include <string>
#include <map>

#include <SDL_ttf.h>

#include "SFML/System/Rect.hpp"
#include "SFML/System/Vector2.hpp"
#include "SFML/Graphics/Drawable.hpp"
#include "SFML/Graphics/Transformable.hpp"
#include "SFML/Graphics/Color.hpp"
#include "SFML/Graphics/Texture.hpp"

#include "logger.hpp"

namespace sf {

extern SDL_Renderer *currentRenderer;

class Text;
class Font {
    std::string fontFile;
    std::map<unsigned int, TTF_Font *> fonts;

    bool loadFontSize(unsigned int size) {
        if (!fonts.contains(size)) {
            TTF_Font *font = TTF_OpenFont(fontFile.c_str(), size);
            if (!font) {
                spdlog::error("Error loading font {}: {}", fontFile, std::string(TTF_GetError()));
                return false;
            }
            fonts[size] = font;
        }

        return true;
    }

    void textSize(const std::string &text, unsigned int size, int *w, int* h) {
        loadFontSize(size);

        TTF_SizeUTF8(fonts[size], text.c_str(), w, h);
    }

    friend class Text;
public:
    bool loadFromFile(std::string file, int defaultSize = 16) {
        fontFile = file;

        return loadFontSize(defaultSize);
    }

    ~Font() {
        for (auto kv : fonts) {
            TTF_CloseFont(kv.second);
        }
    }
};

class Text : public Transformable, public Drawable {
public:
    enum Style : int {
        Regular = TTF_STYLE_NORMAL,
        Bold = TTF_STYLE_BOLD,
        Italic = TTF_STYLE_ITALIC,
        Underlined = TTF_STYLE_UNDERLINE,
        StrikeThrough = TTF_STYLE_STRIKETHROUGH
    };
private:
    std::string text;
    Color color;
    Style style = Regular;

    Font &font;
    unsigned int size;

    SDL_Texture *texture = nullptr;

    void recreateTexture() {
        font.loadFontSize(size);

        TTF_SetFontStyle(font.fonts[size], style);
        SDL_Surface *textSurface =
            TTF_RenderUTF8_Blended(
                // SDL_ttf doesn't like empty text
                font.fonts[size], text.empty() ? " " : text.c_str(),
                SDL_Color { .r = color.r, .g = color.g, .b = color.b, .a = color.a }
            );
        if(!textSurface) {
            spdlog::error("{}", TTF_GetError());
        } else {
            if (texture != nullptr)
                SDL_DestroyTexture(texture);
            texture = SDL_CreateTextureFromSurface(currentRenderer, textSurface);
            SDL_FreeSurface(textSurface);
        }
    }
public:
    Text(const std::string &text, Font &font, unsigned int size) : text(text), font(font), size(size) {
        recreateTexture();
    }

    std::string getString() { return text; }
    void setString(const std::string other) {
        if (text != other) {
            text = other;

            recreateTexture();
        }
    }

    Color getFillColor() { return color; }
    void setFillColor(const Color other) {
        if (color != other) {
            color = other;

            recreateTexture();
        }
    }

    Style getStyle() { return style; }
    void setStyle(Style other) {
        if (style != other) {
            style = other;

            recreateTexture();
        }
    }

    int getCharacterSize() { return size; }
    void setCharacterSize(int other) {
        if (size != other) {
            size = other;

            recreateTexture();
        }
    }

    IntRect getGlobalBounds() {
        IntRect result;

        auto pos = getPosition();
        result.left = pos.x;
        result.top = pos.y;

        font.textSize(text, size, &result.width, &result.height);

        return result;
    }

    virtual void drawToTarget() {
        auto pos = getGlobalBounds();
        SDL_Rect dest { .x = pos.left, .y = pos.top, .w = pos.width, .h = pos.height };

        if (SDL_RenderCopy(currentRenderer, texture, nullptr, &dest) != 0)
            spdlog::error("{}", SDL_GetError());
    }

    ~Text() {
        if (texture != nullptr)
            SDL_DestroyTexture(texture);
    }
};

}
