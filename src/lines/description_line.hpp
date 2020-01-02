#pragma once

class TerminalDescriptionLine : public TerminalInteractiveLine {
private:
    bool space_pressed;

    std::string text;
    std::string next_line;
public:
    TerminalDescriptionLine(std::string text_, std::string next_, CharacterConfig config, Terminal &term)
        : TerminalLine(config, term), text(text_), next_line(next_) {
    }

    float max_line_height();

    sf::Text current_text();

    bool is_interactive() const override;
    void handle_interaction(sf::Event event) override;

    bool should_wait() override;

    void maybe_increment_letter_count() override;

    const std::string next() const override;

    ~TerminalDescriptionLine() override { }
};

bool TerminalDescriptionLine::is_interactive() const {
    return letters_output == text.length() && !space_pressed;
}

void TerminalDescriptionLine::handle_interaction(sf::Event event) {
    switch (event.type) {
    case sf::Event::KeyReleased: {
        auto key = event.key.code;

        if (key == sf::Keyboard::Key::Space)
            space_pressed = true;

        break;
    }

    default: break;
    }
}

float TerminalDescriptionLine::max_line_height() {
    auto term_width = terminal.calc_max_text_width();

    auto fit_str = StringUtils::wrap_words_at(text, term_width);

    auto temp_text = sf::Text(fit_str, StaticFonts::main_font, StaticFonts::font_size);

    return temp_text.getGlobalBounds().height;
}

bool TerminalDescriptionLine::should_wait() {
    return (letters_output < text.length() && time_since_last_letter < terminal.time_per_letter) || !space_pressed;
}

void TerminalDescriptionLine::maybe_increment_letter_count() {
    if (letters_output < text.length() && time_since_last_letter >= terminal.time_per_letter) {
        time_since_last_letter = 0.0;

        letters_output += 1;
    }
}

sf::Text TerminalDescriptionLine::current_text() {
    std::string got_text = text.substr(0, letters_output);
    if (is_interactive()) {
        // Indicate that space needs to be pressed.
        // This line goes away when it is
        // TODO: maybe print it slowly like all other text
        got_text.append("\n[Press Space to continue]");
    }

    auto substr = StringUtils::wrap_words_at(
        got_text,
        terminal.calc_max_text_width()
    );

    auto txt = sf::Text(
        substr,
        StaticFonts::main_font,
        StaticFonts::font_size
    );
    txt.setFillColor(character_config.color);

    return txt;
}

const std::string TerminalDescriptionLine::next() const { return next_line; }
