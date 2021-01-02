#include <fstream>
#include <filesystem>

#include <fmt/format.h>

#include "toml.hpp"
#include "logger.hpp"

namespace {

static std::map<std::string, toml::table> file_node_map;

toml::node_view<const toml::node> find_by_path(const std::string &file, const std::vector<std::string> &path) {
    const toml::table &file_table = file_node_map[file];

    toml::node_view current_node(file_table);

    for (const auto &path_element : path) {
        if (!current_node.as_table()->contains(path_element)) {
            spdlog::error("Can't find path element {} in file {}", path_element, file);
            std::terminate();
        }


        current_node = current_node[path_element];
    }

    return current_node;
}

/// Converts the TOML types to lua/C++
std::tuple<sol::object, sol::table> convert_to_lua(
    sol::state_view &lua, const toml::node &node, std::vector<std::string> full_path = std::vector<std::string>()
) {
        using namespace toml;

        sol::object result;
        sol::table result_src;

        switch (node.type()) {
        case node_type::table: {
            auto node_file = *node.as_table()->source().path;

            auto this_tbl = lua.create_table();
            auto tbl_src = lua.create_table();

            for (auto [k, v] : *node.as_table()) {
                auto sub_path = full_path;
                sub_path.push_back(k);

                auto [val, src] = convert_to_lua(lua, v, sub_path);
                if (src == sol::lua_nil)
                    src = lua.create_table();
                src["__node_file"] = sol::make_object(lua, node_file);
                src["__node_path"] = sol::make_object(lua, sub_path);

                this_tbl[k] = val;
                tbl_src[k] = src;
            }
            tbl_src["__node_file"] = sol::make_object(lua, node_file);
            tbl_src["__node_path"] = sol::make_object(lua, full_path);

            result = this_tbl;
            result_src = tbl_src;

            break;
        }
        case node_type::array: {
            auto this_arr = lua.create_table();

            for (auto &v : *node.as_array()) {
                auto [val, _] = convert_to_lua(lua, v);

                this_arr.add(val);
            }

            result = this_arr;

            break;
        }
        case node_type::string:
            result = sol::make_object(lua, std::string(*node.as_string()));
            break;
        case node_type::integer:
            result = sol::make_object(lua, **node.as_integer());
            break;
        case node_type::floating_point:
            result = sol::make_object(lua, **node.as_floating_point());
            break;
        case node_type::boolean:
            result = sol::make_object(lua, **node.as_boolean());
            break;
        case node_type::date:
        case node_type::time:
        case node_type::date_time:
        case node_type::none:
            spdlog::error("Got an unknown TOML type somehwere in {}", *node.source().path);
            std::terminate();
        }

        return {result, result_src};
    };

}

sol::table parse_toml(sol::this_state lua_, const std::string &path) {
    sol::state_view lua(lua_);

    auto result = lua.create_table();

    try {
        toml::table parsed_root = toml::parse_file(path);

        auto source_path = *parsed_root.source().path;

        file_node_map[source_path] = std::move(parsed_root);
        const toml::table &root = file_node_map[source_path];

        auto [val, src] = convert_to_lua(lua, root);
        if (val.is<sol::table>()) {
            val.as<sol::table>()[sol::create_if_nil][sol::metatable_key]["toml_location"] = src;
        }

        return val;
    } catch (const toml::parse_error &err) {
        return sol::make_object(lua, std::make_tuple(sol::lua_nil, err.description()));
    }
}

std::string encode_toml(sol::this_state lua_, sol::object from) {
    sol::state_view lua(lua_);

    // Converts from lua to toml.
    // Need a pointer because node is an abstract type
    std::function<std::shared_ptr<toml::node>(sol::object &)> convert = [&](sol::object &node) -> std::shared_ptr<toml::node> {
        using namespace toml;

        if (auto maybe_tbl = node.as<std::optional<sol::table>>(); maybe_tbl) {
            sol::table tbl = *maybe_tbl;

            // Size is only defined for arrays
            bool is_array = tbl.size() > 0;
            if (is_array) {
                auto arr = std::make_shared<toml::array>();

                for (auto [_, v] : tbl) {
                    arr->push_back(*convert(v));
                }

                return arr;
            } else {
                auto toml_tbl = std::make_shared<toml::table>();

                for (auto [k, v] : tbl) {
                    toml_tbl->insert(k.as<std::string>(), *convert(v));
                }

                return toml_tbl;
            }
        } else if (auto maybe_str = node.as<std::optional<std::string>>(); maybe_str) {
            return std::make_shared<toml::value<std::string>>(*maybe_str);
        } else if (auto maybe_int = node.as<std::optional<int>>(); maybe_int) {
            return std::make_shared<toml::value<int64_t>>(*maybe_int);
        } else if (auto maybe_float = node.as<std::optional<float>>(); maybe_float) {
            return std::make_shared<toml::value<double>>(*maybe_float);
        } else if (auto maybe_bool = node.as<std::optional<bool>>(); maybe_bool) {
            return std::make_shared<toml::value<bool>>(*maybe_bool);
        } else {
            spdlog::error("Got an unknown lua type in: {}", lua["tostring"](node).get<std::string>());
            std::terminate();
        }
    };
    auto result = convert(from);
    toml::node_view result_view(*result);

    std::stringstream ss;

    toml::default_formatter formatter(
        *result_view.node(),
        // Disable literal strings format flag by overriding it in the formatter
        toml::format_flags::allow_multi_line_strings | toml::format_flags::allow_value_format_flags
    );
    ss << formatter;

    return ss.str();
}

void save_entity_component(sol::this_state lua_, sol::table entity, const std::string &name, sol::table comp, sol::table parts) {
    sol::state_view lua(lua_);

    auto find_in_string = [](std::string str, toml::source_position pos) {
        uint32_t curr_line = 1, curr_pos = 1, res_pos = 1;

        for (auto ch : str) {
            if (curr_line == pos.line && curr_pos == pos.column)
                break;

            if (ch == '\n') {
                curr_line++;
                curr_pos = 1;
            } else {
                curr_pos++;
            }

            res_pos++;
        }

        return res_pos - 1;
    };

    std::optional<sol::table> locations_ = entity["__toml_location"];
    if (locations_) {
        auto locations = *locations_;

        sol::table comp_defaults = comp[sol::metatable_key]["__defaults"];

        sol::table this_location = locations[name];
        for (auto [k, v] : parts) {
            auto source_ = this_location[k].get<sol::optional<sol::table>>();

            bool is_new = false, to_inline_table = false;
            toml::source_region source;
            if (!source_) {
                // Check the default values and if the value is the same as the default,
                // do not create it.
                if (sol::object comp_default = comp_defaults[k]; comp_default != sol::lua_nil && v == comp_default)
                    continue;

                auto parent_file = this_location["__node_file"].get<const std::string &>();
                auto parent_path = this_location["__node_path"].get<std::vector<std::string>>();

                const toml::table *toml_table = find_by_path(
                    parent_file,
                    parent_path
                ).as_table();

                std::vector<std::string> this_path(parent_path);
                this_path.push_back(k.as<std::string>());

                this_location[k] = lua.create_table_with(
                    "__node_file", parent_file,
                    "__node_path", this_path
                );

                is_new = true;
                to_inline_table = toml_table->is_inline();

                if (to_inline_table) {
                    source = toml_table->source();
                    source.begin = source.end;
                } else {
                    // Find the key that is on the lowest line
                    auto last_pair = std::max_element(
                        toml_table->cbegin(),
                        toml_table->cend(),
                        [](const auto &a, const auto &b) {
                            const auto &[_, a_val] = a;
                            const auto &[_2, b_val] = b;
                            return a_val.source().end.line < b_val.source().end.line;
                        }
                    );

                    auto [_, last_val] = *last_pair;
                    source = last_val.source();

                    // Move the output to the beginning of the next line
                    source.end.line += 1;
                    source.end.column = 1;
                    source.begin = source.end;
                }
            } else {
                source = find_by_path(
                    (*source_)["__node_file"].get<const std::string &>(),
                    (*source_)["__node_path"].get<const std::vector<std::string> &>()
                ).node()->source();
            }

            auto edited = encode_toml(lua_, v);

            std::ifstream toml_file;
            toml_file.open(*source.path);
            std::string contents((std::istreambuf_iterator<char>(toml_file)), std::istreambuf_iterator<char>());

            auto beginning = find_in_string(contents, source.begin), end = find_in_string(contents, source.end);
            if (!is_new) {
                // Unless inserting a new field, try to capture the whole old one

                if (std::isspace(contents[end]))
                    // Go back until we find somethign that's not a space
                    while (std::isspace(contents[end])) end--;
                // If the letter encountered is NOT a comma, go forward one letter to not consume the letter
                if (contents[end] != ',')
                    end++;
            } else if (to_inline_table) {
                // The inline table seems to end after a space that is next, so move the
                // end to before the space and the } (around here ->'} ')
                while (contents[end] == '}' || std::isspace(contents[end]))
                    end--;
                end++;

                beginning = end;
            }

            if (is_new) {
                edited.insert(0, fmt::format("{} = ", k.as<std::string>()));
                if (to_inline_table) {
                    // Prepend the key definition
                    edited.insert(0, ", ");
                } else {
                    edited.insert(0, "\n");
                }
            }

            auto substr = contents.substr(beginning, end - beginning);
            contents.replace(beginning, end - beginning, edited);

            std::ofstream toml_file_w;
            toml_file_w.open(*source.path, std::ios::trunc);
            toml_file_w << contents;
            toml_file_w.close();

#ifdef SOMEONE_EDITOR_BASE_PATH
            // If in debug mode also save the edits to the actual source of the resources

            std::filesystem::path editor_path(SOMEONE_EDITOR_BASE_PATH);
            editor_path /= *source.path;

            toml_file_w.open(editor_path, std::ios::trunc);
            toml_file_w << contents;
            toml_file_w.close();
#endif

            // Re-parse the source file, updaint the file_node_map
            const std::string &path = *source.path;
            parse_toml(lua_, *source.path);
        }
    }
}
