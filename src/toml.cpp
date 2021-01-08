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

void rewrite_resource_file(const std::string &path, const std::string &contents) {
    std::ofstream file_w;
    file_w.open(path, std::ios::trunc);
    file_w << contents;
    file_w.close();

#ifdef SOMEONE_EDITOR_BASE_PATH
    // If in debug mode also save to the actual source of the resources

    std::filesystem::path editor_path(SOMEONE_EDITOR_BASE_PATH);
    editor_path /= path;

    file_w.open(editor_path, std::ios::trunc);
    file_w << contents;
    file_w.close();
#endif
}

}

std::tuple<sol::object, sol::object> parse_toml(sol::this_state lua_, const std::string &path) {
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

        return {val, sol::lua_nil};
    } catch (const toml::parse_error &err) {
        std::stringstream ss;
        ss << err;

        return {sol::lua_nil, sol::make_object(lua, ss.str())};
    }
}

std::string encode_toml(sol::this_state lua_, sol::object from, bool inline_tables) {
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
                toml_tbl->is_inline(inline_tables);

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

void save_entity_component(
    sol::this_state lua_, sol::table entity, const std::string &name, sol::table comp,
    sol::table part_names, sol::table part_values
) {
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

    sol::optional<sol::table> locations_ = entity["__toml_location"];
    if (!locations_) {
        // Get the current room file. If the entity has no location, then it's a new entity
        // that just got added to the room. Usually this information is stored in the entity itself,
        // but when adding new entities it has to be added from somewhere. This path is set in rooms.load_room
        std::string current_room_file = lua.script("return require('components.rooms').current_room_file");

        locations_ = lua.create_table_with(
            "__node_file", current_room_file
        );
        entity["__toml_location"] = *locations_;
    }
    auto locations = *locations_;

    // A deep equal function defined in lua, the function can compare tables
    std::function<bool(sol::object, sol::object)> deep_equal = lua.script("return require('util').deep_equal");

    sol::optional<sol::table> this_location_ = locations[name];
    if (!this_location_) {
        // As a special case, if:
        // 1. the component is transformable
        // 2. it has a drawable
        // 3. it's position is 0, 0,
        // don't actually add this component to the file.
        // This is probably only the case for the background, but still
        if (name == "transformable") {
            auto position_part = part_values["position"];
            // First check for drawable, then
            // compare position with a table of {0, 0}
            if (locations["drawable"].get<sol::optional<sol::table>>() && deep_equal(position_part, lua.create_table_with(1, 0, 2, 0))) {
                // If position is indeed 0, 0 - exit
                return;
            }
        }

        sol::table comp_locations = lua.create_table();
        for (auto [k, v] : locations) {
            if (v.is<sol::table>() && !v.is<sol::userdata>()) {
                comp_locations[k] = v;
            }
        }

        // Find the closest-to-bottom node for this entity.
        // For some reason, std::max_element doesn't work for sol::table,
        // so just count the good old way
        const toml::node *last_comp = nullptr;
        std::vector<std::string> last_path;
        uint32_t max_line = 0;
        for (auto [k, v_] : comp_locations) {
            sol::table v = v_;

            const auto &file = v["__node_file"].get<const std::string &>();
            auto path = v["__node_path"].get<std::vector<std::string>>();

            const auto view = find_by_path(file, path);
            auto line = view.node()->source().end.line;

            if (line > max_line) {
                max_line = line;
                last_comp = view.node();

                last_path = path;
                // Pop the last element (the component name), as it's not needed
                last_path.pop_back();
            }
        }

        const auto max_source = [](const toml::table &table) {
            auto [_, last_node] = *std::max_element(
                table.begin(),
                table.cend(),
                [](const auto &a, const auto &b) {
                    const auto &[_, a_val] = a;
                    const auto &[_2, b_val] = b;

                    return a_val.source().end.line < b_val.source().end.line;
                }
            );

            return std::reference_wrapper(last_node);
        };

        // If there are no other components on this entity, it's a new entity,
        // so just take the position of the last entity in the file and use that
        if (last_comp == nullptr) {
            // Iterate entities
            const auto &file_entities = file_node_map[locations["__node_file"].get<std::string>()]["entities"].as_table();

            // Find the last entity in the file
            auto last_entity = max_source(*file_entities);

            // Find the last component of the entity
            auto last_entity_tbl = last_entity.get().as_table();
            auto last_node = max_source(*last_entity_tbl);

            // Get the name by finding the Name component and getting the name from it
            sol::protected_function get_f = entity["get"];
            sol::table name_comp = get_f(entity, "Name");
            std::string ent_name = name_comp["name"];

            last_comp = &last_node.get();
            // Create a path for this entity.
            last_path = { "entities", ent_name };
            locations["__node_path"] = last_path;
        }

        const toml::table *last_tbl = last_comp->as_table();

        // Find the key that is on the lowest line
        auto last_pair = std::max_element(
            last_tbl->cbegin(),
            last_tbl->cend(),
            [](const auto &a, const auto &b) {
                const auto &[_, a_val] = a;
                const auto &[_2, b_val] = b;
                return a_val.source().end.line < b_val.source().end.line;
            }
        );
        auto [_, last_v] = *last_pair;
        auto last_pair_src = last_v.source();

        // Table that only contains the path to the component,
        // so the the TOML encoder will create a table header.
        // e.g. { entities = { name = { component = {} } } }
        auto dummy_pathed_table = lua.create_table();
        auto curr_level = dummy_pathed_table;
        // Push the component name to the path
        last_path.push_back(name);
        for (auto path_elem : last_path) {
            auto created_level = lua.create_table();
            curr_level[path_elem] = created_level;
            curr_level = created_level;
        }
        auto generated_table_header = encode_toml(lua_, dummy_pathed_table);
        // Prepend an additional newline
        generated_table_header.insert(0, "\n\n");

        std::ifstream toml_file;
        toml_file.open(*last_pair_src.path);
        std::string contents((std::istreambuf_iterator<char>(toml_file)), std::istreambuf_iterator<char>());

        auto end = find_in_string(contents, last_pair_src.end);
        // Replace the newline character with the new table header
        contents.replace(end, 1, generated_table_header);

        rewrite_resource_file(*last_pair_src.path, contents);

        parse_toml(lua_, *last_pair_src.path);

        this_location_ = lua.create_table_with(
            "__node_file", *last_pair_src.path,
            "__node_path", last_path
        );
        locations[name] = this_location_;
    }

    sol::table this_location = *this_location_;

    sol::table comp_defaults = comp[sol::metatable_key]["__defaults"];

    for (auto [_, k] : part_names) {
        toml::source_region source;

        sol::optional<sol::object> v_ = part_values[k];

        // If value for the part was nil, it was deleted. If the value is the same as the default,
        // also delete it
        if (!v_ || deep_equal(*v_, comp_defaults[k])) {
            auto deleted_name = k.as<std::string>();

            auto deleted_file = this_location["__node_file"].get<std::string>();
            auto parent_path = this_location["__node_path"].get<std::vector<std::string>>();

            auto deleted_path(parent_path);
            deleted_path.push_back(deleted_name);

            auto parent_node = find_by_path(deleted_file, parent_path).as_table();
            if (parent_node->find(deleted_name) == parent_node->end())
                // If it doesn't exist, then nothing is to be deleted
                continue;

            auto deleted_node = find_by_path(deleted_file, deleted_path).node();
            auto deleted_location = deleted_node->source();

            // For non-inline parent extend the location to capture the whole key
            if (!parent_node->is_inline()) {
                deleted_location.begin.column = 1;
            }

            std::ifstream toml_file;
            toml_file.open(deleted_file);
            std::string contents((std::istreambuf_iterator<char>(toml_file)), std::istreambuf_iterator<char>());

            auto beginning = find_in_string(contents, deleted_location.begin), end = find_in_string(contents, deleted_location.end);

            if (parent_node->is_inline()) {
                // For inline parent, go back until the previous , or {

                // Go back from the initial { of the node if it's a table
                if (deleted_node->is_table())
                    beginning--;
                while (contents[beginning] != ',' && contents[beginning] != '{')
                    beginning--;
                if (contents[beginning] == '{')
                    // Go one character forward to not accidentally remove the {
                    beginning++;
            }

            auto amount_to_replace = end - beginning;
            if (!parent_node->is_inline())
                amount_to_replace++;
            // In case of non-inline deletion, also delete the following newline
            contents.replace(beginning, amount_to_replace, "");

            rewrite_resource_file(deleted_file, contents);

            // Re-parse the source file, update the file_node_map
            const std::string &path = deleted_file;
            parse_toml(lua_, deleted_file);

            this_location[deleted_name] = sol::lua_nil;


            continue;
        }
        // If we got past here, then the value exists
        auto v = *v_;

        auto source_ = this_location[k].get<sol::optional<sol::table>>();

        bool is_new = false, to_inline_table = false;

        if (!source_) {
            // Check the default values and if the value is the same as the default,
            // do not create it.
            if (sol::object comp_default = comp_defaults[k]; comp_default != sol::lua_nil && deep_equal(v, comp_default))
                continue;

            const auto &parent_file = this_location["__node_file"].get<const std::string &>();
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
                // If there were no other keys, use the table header
                if (last_pair != toml_table->cend()) {
                    auto [_, last_val] = *last_pair;
                    source = last_val.source();
                } else {
                    source = toml_table->source();
                }

                // Move the output to the beginning of the next line
                source.begin = source.end;
            }
        } else {
            source = find_by_path(
                (*source_)["__node_file"].get<const std::string &>(),
                (*source_)["__node_path"].get<const std::vector<std::string> &>()
            ).node()->source();
        }

        auto edited = encode_toml(lua_, v, true);

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

        contents.replace(beginning, end - beginning, edited);

        rewrite_resource_file(*source.path, contents);

        // Re-parse the source file, update the file_node_map
        const std::string &path = *source.path;
        parse_toml(lua_, *source.path);
    }
}
