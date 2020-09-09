#pragma once

#include <map>
#include <filesystem>

#include <sol/sol.hpp>

struct ModData;

class StoryParser {
    sol::state &lua;
public:
    sol::table &lines;

    StoryParser(sol::table &lines, sol::state &state)
        : lua(state), lines(lines) { }

    void parse(std::string file_name, std::filesystem::path base = std::filesystem::path("resources/story/"));

    /** If "next" references a namespace, parse the file that contains
     *  this namespace if it hasn't already been parsed.
     */
    void maybe_parse_referenced_file(std::string next);

    static sol::table load_mods(sol::state &lua);

    #ifndef NDEBUG
    void total_wordcount();
    #endif
};

struct ModData {
    std::string name;
    std::string pretty_name;
    std::string first_line;
    sol::table lua_files;
    sol::table lines;
    StoryParser parser;
};
