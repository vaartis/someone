#pragma once

struct CharacterConfig {
    sf::Color color;

    CharacterConfig(sf::Color color_ = sf::Color::White) : color(color_) {}
};

struct TerminalLine {
protected:
    TerminalLine(CharacterConfig config, Terminal &term) : character_config(config), terminal(term) { }

    Terminal &terminal;

    uint32_t letters_output = 0;
    float time_since_last_letter = 0.0f;
public:
    CharacterConfig character_config;

    virtual bool should_wait() = 0;

    virtual void maybe_increment_letter_count() = 0;

    virtual void tick_letter_timer(float dt) {
        time_since_last_letter += dt;
    }

    virtual const std::string next() const = 0;

    virtual ~TerminalLine() { }
};

struct TerminalInteractiveLine : public virtual TerminalLine {
    virtual bool is_interactive() const = 0;
    virtual void handle_interaction(sf::Event event) = 0;
};
