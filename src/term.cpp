#include <iostream>
#include <memory>
#include <algorithm>
#include <stdexcept>

#include <fmt/format.h>

#include <SFML/Window/Event.hpp>
#include <SFML/Graphics/RenderWindow.hpp>
#include <SFML/Graphics/RectangleShape.hpp>
#include <SFML/Graphics/Text.hpp>
#include <SFML/Graphics/Color.hpp>

#include "fonts.hpp"
#include "term.hpp"
#include "string_utils.hpp"

// TerminalOutputLine

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
    txt.setFillColor(sf::Color::White);

    return txt;
}

const std::string TerminalOutputLine::next() const { return next_line; }

// TerminalVariantInputLine

TerminalVariantInputLine::TerminalVariantInputLine(
    std::vector<std::tuple<std::string, std::string>> vars, Terminal &term
) : variants(vars), terminal(term) {

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
        txt.setFillColor(sf::Color::White);

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


// Terminal

Terminal::Terminal(sf::RenderWindow &window_, std::string first_line) : window(window_), first_line_on_screen(first_line) {
    lines.insert({"test",
                  std::make_shared<TerminalOutputLine>(
                      "Sit exercitationem corrupti nulla dicta. Et dolor debitis id perferendis.", "test2", *this)
        }
    );
    lines.insert({"test2",
            std::make_shared<TerminalVariantInputLine>(
                std::vector<std::tuple<std::string, std::string>> { {"Test 1", "test3"}, {"Test 2 2", "test3"} },
                *this
            )
        }
    );
    lines.insert({"test3",
                  std::make_shared<TerminalOutputLine>(
                      R"(Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Diam sit amet nisl suscipit adipiscing bibendum est ultricies integer. Scelerisque felis imperdiet proin fermentum leo. Id diam maecenas ultricies mi eget mauris. Elementum eu facilisis sed odio morbi quis commodo. Augue ut lectus arcu bibendum. In fermentum posuere urna nec tincidunt praesent semper feugiat. Neque convallis a cras semper auctor neque. Sapien eget mi proin sed libero. Suspendisse ultrices gravida dictum fusce ut. Pellentesque habitant morbi tristique senectus et netus. Posuere urna nec tincidunt praesent semper feugiat nibh sed. Congue mauris rhoncus aenean vel elit. Faucibus ornare suspendisse sed nisi lacus sed viverra tellus. Tempus imperdiet nulla malesuada pellentesque elit eget gravida cum sociis.)", "test4", *this)
        }
    );
        lines.insert({"test4",
                  std::make_shared<TerminalOutputLine>(
                      R"(Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Diam sit amet nisl suscipit adipiscing bibendum est ultricies integer. Scelerisque felis imperdiet proin fermentum leo. Id diam maecenas ultricies mi eget mauris. Elementum eu facilisis sed odio morbi quis commodo. Augue ut lectus arcu bibendum. In fermentum posuere urna nec tincidunt praesent semper feugiat. Neque convallis a cras semper auctor neque. Sapien eget mi proin sed libero. Suspendisse ultrices gravida dictum fusce ut. Pellentesque habitant morbi tristique senectus et netus. Posuere urna nec tincidunt praesent semper feugiat nibh sed. Congue mauris rhoncus aenean vel elit. Faucibus ornare suspendisse sed nisi lacus sed viverra tellus. Tempus imperdiet nulla malesuada pellentesque elit eget gravida cum sociis.)", "test5", *this)
        }
    );
            lines.insert({"test5",
                  std::make_shared<TerminalOutputLine>(
                      R"(Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Diam sit amet nisl suscipit adipiscing bibendum est ultricies integer. Scelerisque felis imperdiet proin fermentum leo. Id diam maecenas ultricies mi eget mauris. Elementum eu facilisis sed odio morbi quis commodo. Augue ut lectus arcu bibendum. In fermentum posuere urna nec tincidunt praesent semper feugiat. Neque convallis a cras semper auctor neque. Sapien eget mi proin sed libero. Suspendisse ultrices gravida dictum fusce ut. Pellentesque habitant morbi tristique senectus et netus. Posuere urna nec tincidunt praesent semper feugiat nibh sed. Congue mauris rhoncus aenean vel elit. Faucibus ornare suspendisse sed nisi lacus sed viverra tellus. Tempus imperdiet nulla malesuada pellentesque elit eget gravida cum sociis.)", "test6", *this)
        }
    );
                lines.insert({"test6",
                  std::make_shared<TerminalOutputLine>(
                      R"(Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Diam sit amet nisl suscipit adipiscing bibendum est ultricies integer. Scelerisque felis imperdiet proin fermentum leo. Id diam maecenas ultricies mi eget mauris. Elementum eu facilisis sed odio morbi quis commodo. Augue ut lectus arcu bibendum. In fermentum posuere urna nec tincidunt praesent semper feugiat. Neque convallis a cras semper auctor neque. Sapien eget mi proin sed libero. Suspendisse ultrices gravida dictum fusce ut. Pellentesque habitant morbi tristique senectus et netus. Posuere urna nec tincidunt praesent semper feugiat nibh sed. Congue mauris rhoncus aenean vel elit. Faucibus ornare suspendisse sed nisi lacus sed viverra tellus. Tempus imperdiet nulla malesuada pellentesque elit eget gravida cum sociis.)", "test7", *this)
        }
    );
                    lines.insert({"test7",
                  std::make_shared<TerminalOutputLine>(
                      R"(Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Diam sit amet nisl suscipit adipiscing bibendum est ultricies integer. Scelerisque felis imperdiet proin fermentum leo. Id diam maecenas ultricies mi eget mauris. Elementum eu facilisis sed odio morbi quis commodo. Augue ut lectus arcu bibendum. In fermentum posuere urna nec tincidunt praesent semper feugiat. Neque convallis a cras semper auctor neque. Sapien eget mi proin sed libero. Suspendisse ultrices gravida dictum fusce ut. Pellentesque habitant morbi tristique senectus et netus. Posuere urna nec tincidunt praesent semper feugiat nibh sed. Congue mauris rhoncus aenean vel elit. Faucibus ornare suspendisse sed nisi lacus sed viverra tellus. Tempus imperdiet nulla malesuada pellentesque elit eget gravida cum sociis.)", "test8", *this)
        }
    );
                    lines.insert({"test8",
                  std::make_shared<TerminalOutputLine>(
                      R"(Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Diam sit amet nisl suscipit adipiscing bibendum est ultricies integer. Scelerisque felis imperdiet proin fermentum leo. Id diam maecenas ultricies mi eget mauris. Elementum eu facilisis sed odio morbi quis commodo. Augue ut lectus arcu bibendum. In fermentum posuere urna nec tincidunt praesent semper feugiat. Neque convallis a cras semper auctor neque. Sapien eget mi proin sed libero. Suspendisse ultrices gravida dictum fusce ut. Pellentesque habitant morbi tristique senectus et netus. Posuere urna nec tincidunt praesent semper feugiat nibh sed. Congue mauris rhoncus aenean vel elit. Faucibus ornare suspendisse sed nisi lacus sed viverra tellus. Tempus imperdiet nulla malesuada pellentesque elit eget gravida cum sociis.)", "", *this)
        }
    );
}


uint32_t Terminal::calc_max_text_width() {
    auto win_size = window.getSize();

    float width_offset = win_size.x / 100,
        height_offset = win_size.y / 100 * 2;


    float rect_height = win_size.y / 100 * (80 - 10),
        rect_width = win_size.x - (width_offset * 2);

    return (rect_width - (width_offset * 2)) / (StaticFonts::font_size / 2.0);
}

void Terminal::draw(float dt) {
    auto win_size = window.getSize();

    float width_offset = win_size.x / 100,
        height_offset = win_size.y / 100 * 2;


    float rect_height = win_size.y / 100 * (80 - 10),
        rect_width = win_size.x - (width_offset * 2);

    uint32_t max_text_width = calc_max_text_width();

    auto rect = sf::RectangleShape({rect_width, rect_height});
    rect.setOutlineThickness(2.0);
    rect.setOutlineColor(sf::Color::Black);
    rect.setFillColor(sf::Color::Black);
    rect.setPosition({width_offset, height_offset});

    window.draw(rect);

    const auto beginning_line_height_offset = (height_offset * 2);

    auto line_width_offset = (width_offset * 2);
    auto line_height_offset = beginning_line_height_offset;

    // The total amount that text is currently taking on screen
    float total_line_height = 0;

    std::string current_line_name = first_line_on_screen;
    while (true) {
        auto &line = lines.at(current_line_name);

        auto should_wait = line->should_wait();

        if (should_wait) {
            line->tick_letter_timer(dt);
            line->maybe_increment_letter_count();
        }

        if (auto text_outp = dynamic_cast<TerminalOutputLine *>(line.get())) {
            auto text = text_outp->current_text();

            text.setPosition({line_width_offset, line_height_offset});

            auto line_height = text_outp->max_line_height();

            total_line_height += line_height + (StaticFonts::font_size / 2);
            line_height_offset = beginning_line_height_offset + total_line_height;

            window.draw(text);
        } else if (auto text_inp_vars = dynamic_cast<TerminalVariantInputLine *>(line.get())) {
            auto variants = text_inp_vars->current_text();

            for (int i = 0; i < variants.size(); i++) {
                auto variant = variants[i];

                variant.setPosition({line_width_offset, line_height_offset});

                auto line_height = text_inp_vars->max_line_height(i);

                total_line_height += line_height + (StaticFonts::font_size / 2);
                line_height_offset = beginning_line_height_offset + total_line_height;

                window.draw(variant);
            }

            total_line_height += StaticFonts::font_size / 2;
            line_height_offset = beginning_line_height_offset + total_line_height;
        }

        if (should_wait || line->next() == "") break;

        current_line_name = line->next();
    }

    if (total_line_height > rect_height - (height_offset * 2)) {
        auto curr_first_line = lines.at(first_line_on_screen);

        if (curr_first_line->next() != "") {
            first_line_on_screen = curr_first_line->next();
        }
    }
}

void Terminal::processEvent(sf::Event event) {
 std::string current_line_name = first_line_on_screen;
    while (true) {
        auto &line = lines.at(current_line_name);

        auto should_wait = line->should_wait();

        if (auto text_outp = dynamic_cast<TerminalOutputLine *>(line.get())) {
            // TODO: allow skipping
        } else if (auto text_inp_vars = dynamic_cast<TerminalVariantInputLine *>(line.get())) {
            if (text_inp_vars->should_wait() && text_inp_vars->is_interactive()) {
                text_inp_vars->handle_interaction(event);
            }
        }

        if (should_wait || line->next() == "") break;

        current_line_name = line->next();
    }
}
