#include "string_utils.hpp"

#include <vector>
#include <sstream>

std::string StringUtils::wrap_words_at(const std::string &str_to_fit, uint32_t wrap_at) {
    std::string result;

    auto current_width = 0;

    std::stringstream ss(str_to_fit);

    std::string item;
    while (std::getline(ss, item, ' '))
    {
        if (current_width + item.length() < wrap_at) {
            if (!result.empty()) {
                result.push_back(' ');
            }
            result.append(item);

            current_width += item.length() + 1;
        } else {
            if (!result.empty()) {
                result.push_back('\n');
                current_width = 0;
            }

            result.append(item);
        }
    }

    return result;
}
