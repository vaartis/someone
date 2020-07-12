#include <filesystem>

#include "catch2/catch.hpp"

#include "sol/sol.hpp"

#include "story_parser.hpp"
#include "line_data.hpp"
#include "usertypes.hpp"
#include "logger.hpp"

TEST_CASE("Story parser", "[story_parser]") {
    sol::state lua;
    sol::table lines = lua.create_table();
    StoryParser parser(lines, lua);

    StaticFonts static_fonts;
    register_usertypes(lua, static_fonts);

    SECTION("Dialogue between characters") {
        parser.parse("test/dialogue_between");

        SECTION("Dialogue starts from the first character") {
            auto first = lines["test/dialogue_between/1"].get<TerminalOutputLineData>();

            REQUIRE(first.character_config.color == sf::Color(0, 0, 0));
        }

        SECTION("Dialogue switches to the second character") {
            auto second = lines["test/dialogue_between/2"].get<TerminalOutputLineData>();

            REQUIRE(second.character_config.color == sf::Color(1, 1, 1));
        }

        SECTION("Explicitly selecting a character updates the current next character") {
            auto third = lines["test/dialogue_between/3"].get<TerminalOutputLineData>();
            auto fourth = lines["test/dialogue_between/4"].get<TerminalOutputLineData>();

            REQUIRE(third.character_config.color == sf::Color(1, 1, 1));
            REQUIRE(fourth.character_config.color == sf::Color(0, 0, 0));
        }
    }

    SECTION("Numbered lines increment properly") {
        // Hide the warning logs about the fact that there's no next on the last line
        spdlog::set_level(spdlog::level::err);

        parser.parse("test/numbered_lines");

        SECTION("Simple lines with just numbers increment") {
            auto l1 = lines["test/numbered_lines/1"].get<TerminalOutputLineData>();

            REQUIRE(l1.next == "test/numbered_lines/2");
        }

        SECTION("Response lines increment") {
            auto l3 = lines["test/numbered_lines/3"].get<TerminalVariantInputLineData>();

            REQUIRE(l3.variants.size() == 1);
            REQUIRE(l3.variants.front().next == "test/numbered_lines/4");
        }

        SECTION("Lines with text before the numbers increment") {
            auto l3 = lines["test/numbered_lines/test-5"].get<TerminalOutputLineData>();

            REQUIRE(l3.next == "test/numbered_lines/test-6");
        }

        SECTION("Names without numbers but with dashes aren't affected") {
            auto l5 = lines["test/numbered_lines/test-end"].get<TerminalOutputLineData>();

            REQUIRE(l5.next == "");
        }
    }

    SECTION("Cross-file references work") {
        parser.parse("test/reference");

        SECTION("In text lines") {
            auto referenced = lines["test/referenced/1"].get<TerminalOutputLineData>();

            REQUIRE(referenced.text == "referenced");
        }

        SECTION("In response lines") {
            auto referenced2 = lines["test/referenced_2/1"].get<TerminalOutputLineData>();

            REQUIRE(referenced2.text == "referenced-2");
        }
    }

    SECTION("Text input lines parse correctly") {
        parser.parse("test/text_input");

        SECTION("With next line specified") {
            auto l1 = lines["test/text_input/1"].get<TerminalTextInputLineData>();

            REQUIRE(l1.before == "before");
            REQUIRE(l1.after == "after");
            REQUIRE(l1.variable == "v1");
            REQUIRE(l1.max_length == 1);

            auto l2 = lines[l1.next].get<TerminalTextInputLineData>();

            REQUIRE(l2.before == "before2");
            REQUIRE(l2.after == "after2");
            REQUIRE(l2.variable == "v2");
            REQUIRE(l2.max_length == 2);

            auto l3 = lines[l2.next].get<TerminalOutputLineData>();

            REQUIRE(l3.text == "test3");
        }
    }
}
