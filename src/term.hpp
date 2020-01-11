#pragma once

#include <map>
#include <memory>
#include <optional>

#include <SFML/Graphics/RenderTexture.hpp>

class TerminalLine;

class Terminal {
private:
    sf::RenderTexture &target;



    std::string first_line_on_screen;
public:
    std::map<std::string, std::shared_ptr<TerminalLine>> lines;

    Terminal(sf::RenderTexture &target_, std::string first_line);

    static constexpr float time_per_letter = 0.001f;

    uint32_t calc_max_text_width();

    void draw(float dt);
    void processEvent(sf::Event event);
};
