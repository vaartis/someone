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

    SECTION("Numbered lines increment properly") {
        // Hide the warning logs about the fact that there's no next on the last line
        spdlog::set_level(spdlog::level::err);

        StoryParser::parse(lines, "test/numbered_lines", lua);

        SECTION("Simple lines with just numbers increment") {
            auto l1 = lines.at("test/numbered_lines/1").as<TerminalOutputLineData>();

            REQUIRE(l1.next == "test/numbered_lines/2");
        }

        SECTION("Response lines increment") {
            auto l3 = lines.at("test/numbered_lines/3").as<TerminalVariantInputLineData>();

            REQUIRE(l3.variants.size() == 1);
            REQUIRE(l3.variants.front().next == "test/numbered_lines/4");
        }

        SECTION("Lines with text before the numbers increment") {
            auto l3 = lines.at("test/numbered_lines/test-5").as<TerminalOutputLineData>();

            REQUIRE(l3.next == "test/numbered_lines/test-6");
        }

        SECTION("Names without numbers but with dashes aren't affected") {
            auto l5 = lines.at("test/numbered_lines/test-end").as<TerminalOutputLineData>();

            REQUIRE(l5.next == "");
        }
    }

    SECTION("Cross-file references work") {
        StoryParser::parse(lines, "test/reference", lua);

        SECTION("In text lines") {
            auto referenced = lines.at("test/referenced/1").as<TerminalOutputLineData>();

            REQUIRE(referenced.text == "referenced");
        }

        SECTION("In response lines") {
            auto referenced2 = lines.at("test/referenced_2/1").as<TerminalOutputLineData>();

            REQUIRE(referenced2.text == "referenced-2");
        }
    }

    SECTION("Text input lines parse correctly") {
        StoryParser::parse(lines, "test/text_input", lua);

        SECTION("With next line specified") {
            auto l1 = lines.at("test/text_input/1").as<TerminalTextInputLineData>();

            REQUIRE(l1.before == "before");
            REQUIRE(l1.after == "after");
            REQUIRE(l1.variable == "v1");
            REQUIRE(l1.max_length == 1);

            auto l2 = lines.at(l1.next).as<TerminalTextInputLineData>();

            REQUIRE(l2.before == "before2");
            REQUIRE(l2.after == "after2");
            REQUIRE(l2.variable == "v2");
            REQUIRE(l2.max_length == 2);

            auto l3 = lines.at(l2.next).as<TerminalOutputLineData>();

            REQUIRE(l3.text == "test3");
        }
    }
}
