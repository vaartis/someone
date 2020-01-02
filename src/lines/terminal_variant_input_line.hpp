#pragma once

class TerminalVariantInputLine : public TerminalInteractiveLine {
private:
    std::vector<std::tuple<std::string, std::string>> variants;

    std::optional<uint32_t> selected_variant;

    uint32_t longest_var_length;
public:
    TerminalVariantInputLine(std::vector<std::tuple<std::string, std::string>> vars, CharacterConfig config, Terminal &term);

    float max_line_height(uint32_t variant);

    std::vector<sf::Text> current_text();

    bool should_wait() override;

    void maybe_increment_letter_count() override;

    const std::string next() const override;

    bool is_interactive() const override;
    void handle_interaction(sf::Event event) override;
};

TerminalVariantInputLine::TerminalVariantInputLine(
    std::vector<std::tuple<std::string, std::string>> vars,
    CharacterConfig config,
    Terminal &term
) : TerminalLine(config, term), variants(vars) {

    auto longest_var = std::max_element(variants.begin(), variants.end(),
                     [&](auto a, auto b) {
                         auto [a_str, _a] = a;
                         auto [b_str, _b] = b;

                         return a_str.length() < b_str.length();
                     }
    );
    auto [longest_var_str, _nxt] = *longest_var;
    longest_var_length = longest_var_str.length();
}


float TerminalVariantInputLine::max_line_height(uint32_t variant) {
    auto term_width = terminal.calc_max_text_width();

    auto [var_str, _var_next] = variants.at(variant);
    auto fit_str = StringUtils::wrap_words_at(var_str, term_width);

    auto temp_text = sf::Text(fit_str, StaticFonts::main_font, StaticFonts::font_size);

    return temp_text.getGlobalBounds().height;
}

bool TerminalVariantInputLine::should_wait() {
    return (letters_output < longest_var_length && time_since_last_letter < terminal.time_per_letter) || !selected_variant.has_value();
}

void TerminalVariantInputLine::maybe_increment_letter_count() {
    if (letters_output < longest_var_length && time_since_last_letter >= terminal.time_per_letter) {
        time_since_last_letter = 0.0;

        letters_output += 1;
    }
}

std::vector<sf::Text> TerminalVariantInputLine::current_text() {

    std::vector<sf::Text> result;
    for (int i = 0; i < variants.size(); i++) {
        auto [var_str, _var_next] = variants.at(i);

        auto substr =
            fmt::format(
                "{}. {}",
                i + 1,
                StringUtils::wrap_words_at(
                    var_str.substr(0, letters_output),
                    terminal.calc_max_text_width()
                )
            );

        auto txt = sf::Text(
            substr,
            StaticFonts::main_font,
            StaticFonts::font_size
        );
        txt.setFillColor(character_config.color);

        if (selected_variant.has_value() && selected_variant.value() == i) {
            txt.setStyle(sf::Text::Underlined);
        }

        result.push_back(txt);
    }

    return result;
}

const std::string TerminalVariantInputLine::next() const {
    if (!selected_variant.has_value()) return "";

    try {
        auto [_var_str, var_next] = variants.at(selected_variant.value());

        return var_next;
    } catch (std::out_of_range) {
        throw std::runtime_error("Unknown variant selected");
    }
}

bool TerminalVariantInputLine::is_interactive() const {
    return letters_output == longest_var_length && !selected_variant.has_value();
}

void TerminalVariantInputLine::handle_interaction(sf::Event event) {
    switch (event.type) {
    case sf::Event::TextEntered:
        char ch = event.text.unicode;

        if (std::isdigit(ch)) {
            auto var_num = std::stoi(std::string(1, ch));

            if (var_num > 0 && var_num <= variants.size()) {
                selected_variant = var_num - 1;
            }
        }

        break;
    }
}
