#pragma once

#include <toml++/toml.h>

#include <sol/sol.hpp>

std::tuple<sol::object, sol::object> parse_toml(sol::this_state lua, const std::string &path);
std::string encode_toml(sol::this_state lua_, sol::object from, bool inline_tables = false);
void save_entity_component(sol::this_state lua_, sol::table entity, const std::string &name, sol::table comp,
                           sol::table part_names, sol::table part_values);
void create_new_room(const std::string &full_path);
void save_shaders(sol::this_state lua_, sol::optional<sol::table> shaders_);
void save_asset(sol::this_state lua_,
                sol::table asset_data, const std::string &category_key,
                const sol::optional<std::string> &name_, const sol::optional<std::string> &new_name_, const std::string &path);
