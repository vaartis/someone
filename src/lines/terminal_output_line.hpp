#pragma once

class TerminalOutputLine : public TerminalLine {
private:
    std::string text;
public:
    std::string next_line;

    TerminalOutputLine(std::string text_, std::string next_, CharacterConfig config, Terminal &term)
        : TerminalLine(config, term), text(text_), next_line(next_) { }

    sf::Text current_text();

    float max_line_height();

    bool should_wait() override;

    void maybe_increment_letter_count() override;

    const std::string next() const override;

    ~TerminalOutputLine() override { }
};

float TerminalOutputLine::max_line_height() {
    auto term_width = terminal.calc_max_text_width();

    auto fit_str = StringUtils::wrap_words_at(text, term_width);

    auto temp_text = sf::Text(fit_str, StaticFonts::main_font, StaticFonts::font_size);

    return temp_text.getGlobalBounds().height;
}

bool TerminalOutputLine::should_wait() {
    return letters_output < text.length() && time_since_last_letter < terminal.time_per_letter;
}

void TerminalOutputLine::maybe_increment_letter_count() {
    if (letters_output < text.length() && time_since_last_letter >= terminal.time_per_letter) {
        time_since_last_letter = 0.0;

        letters_output += 1;
    }
}

sf::Text TerminalOutputLine::current_text() {
    auto substr = StringUtils::wrap_words_at(
        text.substr(0, letters_output),
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

const std::string TerminalOutputLine::next() const { return next_line; }
