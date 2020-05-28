#include <filesystem>

#include "catch2/catch.hpp"

#include "sol/sol.hpp"

#include "story_parser.hpp"
#include "line_data.hpp"
#include "usertypes.hpp"
#include "logger.hpp"

TEST_CASE("Story parser", "[story_parser]") {
    sol::state lua;

    StaticFonts static_fonts;
    register_usertypes(lua, static_fonts);

    StoryParser::lines_type lines;

    SECTION("Dialogue between characters") {
        StoryParser::parse(lines, "test/dialogue_between", lua);

        SECTION("Dialogue starts from the first character") {
            auto first = lines.at("test/dialogue_between/1").as<TerminalOutputLineData>();

            REQUIRE(first.character_config.color == sf::Color(0, 0, 0));
        }

        SECTION("Dialogue switches to the second character") {
            auto second = lines.at("test/dialogue_between/2").as<TerminalOutputLineData>();

            REQUIRE(second.character_config.color == sf::Color(1, 1, 1));
        }

        SECTION("Explicitly selecting a character updates the current next character") {
            auto third = lines.at("test/dialogue_between/3").as<TerminalOutputLineData>();
            auto fourth = lines.at("test/dialogue_between/4").as<TerminalOutputLineData>();

            REQUIRE(third.character_config.color == sf::Color(1, 1, 1));
            REQUIRE(fourth.character_config.color == sf::Color(0, 0, 0));
        }
    }
}
