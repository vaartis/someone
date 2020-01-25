#include "string_utils.hpp"

#include <algorithm>
#include <vector>
#include <sstream>

bool StringUtils::is_number(const std::string &str) {
    return std::all_of(str.begin(), str.end(), ::isdigit);
}
