#pragma once

#include <SFML/Graphics/Color.hpp>
#include "fonts.hpp"

struct CharacterConfig {
    sf::Color color;
    uint32_t font_size;

    CharacterConfig(sf::Color color = sf::Color::White, uint32_t size = StaticFonts::font_size) : color(color), font_size(size) {}
};

struct TerminalLineData {
    CharacterConfig character_config;
    std::optional<std::string> script;
    std::optional<std::string> script_after;

    virtual ~TerminalLineData() { }
};

struct TerminalOutputLineData : TerminalLineData {
    std::string text;
    std::string next;

    TerminalOutputLineData(std::string text, std::string next)
        : text(text), next(next) { }
};

struct TerminalInputWaitLineData : TerminalOutputLineData {
    TerminalInputWaitLineData(std::string text, std::string next)
        : TerminalOutputLineData(text, next) { }
};

struct TerminalVariantInputLineData : TerminalLineData {
    struct Variant {
        std::string text;
        std::string next;
        std::optional<std::string> condition;

        Variant(std::string text, std::string next) : text(text), next(next) {}
    };

    std::vector<Variant> variants;

    TerminalVariantInputLineData(decltype(variants) variants)
        : variants(variants) { }
};

struct TerminalTextInputLineData : TerminalLineData {
    std::string before, after, variable, next;
    uint32_t max_length;
    std::vector<std::string> filters;

    TerminalTextInputLineData(std::string before, std::string after, std::string variable, uint32_t max_length,
                              std::vector<std::string> filters, std::string next)
        : before(before), after(after), variable(variable), max_length(max_length), next(next), filters(filters) {}
};

struct TerminalCustomLineData : TerminalLineData {
    sol::object class_;
    sol::object data;

    TerminalCustomLineData(sol::object class_, sol::object data)
        : data(data), class_(class_) { }
};
