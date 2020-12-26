#pragma once

#include <toml++/toml.h>

#include <sol/sol.hpp>

sol::table parse_toml(sol::this_state lua, const std::string &path);
std::string encode_toml(sol::this_state lua_, sol::table table);
