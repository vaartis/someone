#pragma once

#include <map>
#include <memory>
#include <optional>

#include <SFML/Graphics/RenderWindow.hpp>

struct TerminalLine {
    uint32_t letters_output = 0;
    float time_since_last_letter = 0.0f;

    virtual bool should_wait() = 0;

    virtual void maybe_increment_letter_count() = 0;

    virtual void tick_letter_timer(float dt) {
        time_since_last_letter += dt;
    }

    virtual const std::string next() const = 0;

    virtual ~TerminalLine() { }
};

class Terminal {
private:
    sf::RenderWindow &window;

    std::map<std::string, std::shared_ptr<TerminalLine>> lines;

    std::string first_line_on_screen;
public:
    Terminal(sf::RenderWindow &window_, std::string first_line);

    static constexpr float time_per_letter = 0.001f;

    uint32_t calc_max_text_width();

    void draw(float dt);
    void processEvent(sf::Event event);
};

class TerminalOutputLine : public TerminalLine {
private:
    Terminal &terminal;

    std::string text;
public:
    std::string next_line;

    TerminalOutputLine(std::string text_, std::string next_, Terminal &term) : text(text_), terminal(term), next_line(next_) { }

    sf::Text current_text();

    float max_line_height();

    bool should_wait() override;

    void maybe_increment_letter_count() override;

    const std::string next() const override;

    ~TerminalOutputLine() override { }
};

class TerminalVariantInputLine : public TerminalLine {
private:
    Terminal &terminal;

    std::vector<std::tuple<std::string, std::string>> variants;

    std::optional<uint32_t> selected_variant;

    uint32_t longest_var_length;
public:
    TerminalVariantInputLine(std::vector<std::tuple<std::string, std::string>> vars, Terminal &term);

    float max_line_height(uint32_t variant);

    std::vector<sf::Text> current_text();

    bool should_wait() override;

    void maybe_increment_letter_count() override;

    const std::string next() const override;

    bool is_interactive() const;
    void handle_interaction(sf::Event event);
};
