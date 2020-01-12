#pragma once

struct CharacterConfig {
    sf::Color color;

    CharacterConfig(sf::Color color_ = sf::Color::White) : color(color_) {}
};

struct TerminalLineData {
    CharacterConfig character_config;

    TerminalLineData(CharacterConfig config) : character_config(config) { }

    virtual ~TerminalLineData() { }
};

struct TerminalOutputLineData : TerminalLineData {
    std::string text;
    std::string next;

    TerminalOutputLineData(std::string text, std::string next, CharacterConfig config)
        : TerminalLineData(config), text(text), next(next) { }
};

struct TerminalDescriptionLineData : TerminalOutputLineData {
    TerminalDescriptionLineData(std::string text, std::string next, CharacterConfig config)
        : TerminalOutputLineData(text, next, config) { }
};

struct TerminalVariantInputLineData : TerminalLineData {
    std::vector<std::tuple<std::string, std::string>> variants;

    TerminalVariantInputLineData(decltype(variants) variants, CharacterConfig config)
        : TerminalLineData(config), variants(variants) { }
};
