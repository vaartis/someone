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
#include "lines.hpp"
#include "story_parser.hpp"

Terminal::Terminal(sf::RenderWindow &window_, std::string first_line) : window(window_), first_line_on_screen(first_line) {
    lines = StoryParser::parse("resources/story/prologue.yml", *this);
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
