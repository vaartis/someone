#pragma once

#include <map>

class StoryParser {
    sol::state &lua;
public:
    sol::table &lines;

    StoryParser(sol::table &lines, sol::state &state) : lua(state), lines(lines) {}

    void parse(std::string file_name);

    /** If "next" references a namespace, parse the file that contains
     *  this namespace if it hasn't already been parsed.
     */
    void maybe_parse_referenced_file(std::string next);

    #ifndef NDEBUG
    void total_wordcount();
    #endif
};
