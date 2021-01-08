#pragma once

#include <toml++/toml.h>

#include <sol/sol.hpp>

std::tuple<sol::object, sol::object> parse_toml(sol::this_state lua, const std::string &path);
std::string encode_toml(sol::this_state lua_, sol::object from, bool inline_tables = false);
void save_entity_component(sol::this_state lua_, sol::table entity, const std::string &name, sol::table comp,
                           sol::table part_names, sol::table part_values);
