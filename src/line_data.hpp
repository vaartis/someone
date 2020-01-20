#pragma once

struct CharacterConfig {
    sf::Color color;

    CharacterConfig(sf::Color color_ = sf::Color::White) : color(color_) {}
};

struct TerminalLineData {
    CharacterConfig character_config;
    std::optional<std::string> script;

    virtual ~TerminalLineData() { }
};

struct TerminalOutputLineData : TerminalLineData {
    std::string text;
    std::string next;

    TerminalOutputLineData(std::string text, std::string next)
        : text(text), next(next) { }
};

struct TerminalDescriptionLineData : TerminalOutputLineData {
    TerminalDescriptionLineData(std::string text, std::string next)
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
