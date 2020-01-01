#pragma once

#include <string>

struct StringUtils {
    /** Wraps the string at wrap_at characters, splitting it by spaces. */
    static std::string wrap_words_at(const std::string &str_to_fit, uint32_t wrap_at);

    static bool is_number(const std::string &str);
};
