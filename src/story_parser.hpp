#pragma once

#include <map>

class StoryParser {
public:
    using lines_type = std::map<std::string, sol::object>;

    static void parse(lines_type &result, std::string file_name, sol::state &lua);
private:
    /** If "next" references a namespace, parse the file that contains
     *  this namespace if it hasn't already been parsed.
     */
    static void maybe_parse_referenced_file(std::string next, lines_type &result, sol::state &lua);
};
