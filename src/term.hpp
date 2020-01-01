#pragma once

#include <map>
#include <memory>
#include <optional>

#include <SFML/Graphics/RenderWindow.hpp>

class TerminalLine;

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
