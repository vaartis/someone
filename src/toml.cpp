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
    sol::state_view &lua, const toml::node &node,
    bool need_source = true,
    std::vector<std::string> full_path = std::vector<std::string>()
) {
        using namespace toml;

        sol::object result;
        sol::table result_src;

        node.visit([&](auto&& node) {
            if constexpr (toml::is_table<decltype(node)>) {
                std::string node_file;
                if (need_source) {
                    node_file = *node.source().path;
                }

                auto this_tbl = lua.create_table();
                auto tbl_src = lua.create_table();

                for (auto [k, v] : node) {
                    auto sub_path = full_path;
                    sub_path.push_back(k);

                    auto [val, src] = convert_to_lua(lua, v, need_source, sub_path);
                    if (src == sol::lua_nil)
                        src = lua.create_table();
                    if (need_source) {
                        src["__node_file"] = sol::make_object(lua, node_file);
                        src["__node_path"] = sol::make_object(lua, sub_path);
                    }

                    this_tbl[k] = val;
                    tbl_src[k] = src;
                }
                if (need_source) {
                    tbl_src["__node_file"] = sol::make_object(lua, node_file);
                    tbl_src["__node_path"] = sol::make_object(lua, full_path);
                }

                result = this_tbl;
                result_src = tbl_src;
            } else if constexpr (toml::is_array<decltype(node)>) {
                auto this_arr = lua.create_table();

                for (auto &v : node) {
                    auto [val, _] = convert_to_lua(lua, v, need_source);

                    this_arr.add(val);
                }

                result = this_arr;
            } else if constexpr (toml::is_date<decltype(node)> || toml::is_time<decltype(node)>
                                 || toml::is_date_time<decltype(node)>) {
                spdlog::error("Got an unknown TOML type somehwere in {}", *node.source().path);
                std::terminate();
            } else {
                result = sol::make_object(lua, *node);
            }
        });

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

std::string encode_toml(sol::this_state lua_, sol::object from, int inline_from_level) {
    sol::state_view lua(lua_);

    // Converts from lua to toml.
    // Need a pointer because node is an abstract type
    std::function<std::shared_ptr<toml::node>(sol::object &, int, int)> convert =
        [&](sol::object &node, int curr_level = 0, int inline_from = 0) -> std::shared_ptr<toml::node> {
        using namespace toml;

        if (auto maybe_tbl = node.as<std::optional<sol::table>>(); maybe_tbl) {
            sol::table tbl = *maybe_tbl;

            // Size is only defined for arrays
            bool is_array = tbl.size() > 0;
            if (is_array) {
                auto arr = std::make_shared<toml::array>();

                for (auto [_, v] : tbl) {
                    arr->push_back(*convert(v, 0, 0));
                }

                return arr;
            } else {
                auto toml_tbl = std::make_shared<toml::table>();

                if (inline_from < 0) {
                    toml_tbl->is_inline(false);
                } else if (curr_level < inline_from) {
                    toml_tbl->is_inline(false);

                    curr_level++;
                } else {
                    toml_tbl->is_inline(true);
                }

                for (auto [k, v] : tbl) {
                    toml_tbl->insert(k.as<std::string>(), *convert(v, curr_level, inline_from));
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
    auto result = convert(from, 0, inline_from_level);
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

uint32_t find_in_string(std::string str, toml::source_position pos) {
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
}

void create_new_entity_location(sol::state_view lua, sol::table entity, sol::table result_table) {
    // Get the current room file. If the entity has no location, then it's a new entity
    // that just got added to the room. Usually this information is stored in the entity itself,
    // but when adding new entities it has to be added from somewhere. This path is set in rooms.load_room
    std::string current_room_file = lua.script("return require('components.rooms').current_room_file");

    result_table["__node_file"] = current_room_file;
    entity["__toml_location"] = result_table;
}

void delete_part_from_comp(sol::state_view lua, const std::string &deleted_name, sol::table locations, const std::string &name) {
    sol::table this_location = locations[name];

    // If it doesn't exist in the component, then nothing is to be deleted
    if (!this_location[deleted_name].get<sol::optional<sol::object>>())
        return;

    auto deleted_file = this_location[deleted_name]["__node_file"].get<std::string>();
    auto deleted_path = this_location[deleted_name]["__node_path"].get<std::vector<std::string>>();

    auto parent_path(deleted_path);
    parent_path.pop_back();

    auto parent_node = find_by_path(deleted_file, parent_path).as_table();
    if (parent_node->find(deleted_name) == parent_node->end())
        // Again, if it doesn't exist in the parent node, then nothing is to be deleted
        return;

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

        while(contents[end] != ',' && contents[end] != '}')
            end++;
        if (contents[end] == '}')
            // Go one character backward to not accidentally remove the }
            end--;
        else
            // Capture the possible comma
            end++;
    }

    auto amount_to_replace = end - beginning;
    if (!parent_node->is_inline())
        amount_to_replace++;
    // In case of non-inline deletion, also delete the following newline
    contents.replace(beginning, amount_to_replace, "");

    rewrite_resource_file(deleted_file, contents);

    // Re-parse the source file, update the file_node_map
    parse_toml(sol::this_state(lua), deleted_file);

    this_location[deleted_name] = sol::lua_nil;
}

void insert_new_part(
    sol::state_view lua, sol::table this_location, std::string part_name,
    toml::source_region *ret_source, bool *ret_to_inline_table
) {
    const auto &parent_file = this_location["__node_file"].get<const std::string &>();
    auto parent_path = this_location["__node_path"].get<std::vector<std::string>>();

    const toml::table *toml_table = find_by_path(
        parent_file,
        parent_path
    ).as_table();

    std::vector<std::string> this_path(parent_path);
    this_path.push_back(part_name);

    this_location[part_name] = lua.create_table_with(
        "__node_file", parent_file,
        "__node_path", this_path
    );

    bool to_inline_table = toml_table->is_inline();

    toml::source_region source;
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

    *ret_source = source;
    *ret_to_inline_table = to_inline_table;
}

std::tuple<const toml::node *, std::vector<std::string>> find_last_comp(sol::state_view lua, sol::table locations) {
    sol::table comp_locations = lua.create_table();

    int location_count = 0;
    // Collect all nodes that are actually tables and not some string or userdata
    for (auto [k, v] : locations) {
        if (v.is<sol::table>() && !v.is<sol::userdata>()) {
            comp_locations[k] = v;
            location_count++;
        }
    }

    if (location_count == 0) {
        // In case there are no other nodes on the entity, add the "self" node, in particular
        // this is applicable to the entity that is made from a prefab and didn't override anything.
        //
        // However, the "self" node is only valid when no components exist.
        // If such a node does not exist in a file, but its source is retreived from code,
        // it will point to some other node that actually exists which DOES NOT WORK and breaks things.
        //
        // So, only create the "self" node in case there are no other nodes but
        // the entity exists in the file: therefore it is guaranteed that the
        // node will be pointing to an entity node with no components.
        if (locations["__node_path"].get<sol::optional<std::vector<std::string>>>()
            && locations["__node_file"].get<sol::optional<std::string>>()) {
            comp_locations["self"] = lua.create_table_with(
                "__node_file", locations["__node_file"],
                "__node_path", locations["__node_path"]
            );
        }
    }

    sol::optional<std::string> node_prefab_file = locations["__node_prefab_file"];

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

        // Skip the nodes that are from a prefab
        if (node_prefab_file && file == *node_prefab_file)
            continue;

        const auto view = find_by_path(file, path);
        auto line = view.node()->source().end.line;

        // Only count tables as components
        if (line > max_line && view.is_table()) {
            max_line = line;
            last_comp = view.node();

            last_path = path;

            // Pop the last element (the component name), as it's not needed,
            // except on "self", where there's no component name
            if (k.as<std::string>() != "self") {
                last_path.pop_back();
            }
        }
    }

    return { last_comp, last_path };
}

const toml::node *find_last_source(const toml::table &table) {
    auto last_node_iter = std::max_element(
        table.begin(),
        table.cend(),
        [](const auto &a, const auto &b) {
            const auto &[_, a_val] = a;
            const auto &[_2, b_val] = b;

            return a_val.source().end.line < b_val.source().end.line;
        }
    );

    if (last_node_iter == table.cend())
        return nullptr;
    else {
        auto [_, last_node] = *last_node_iter;
        return &last_node;
    }
};

std::tuple<const toml::node *, std::vector<std::string>> path_for_new_comp_and_entity(sol::table locations, sol::table entity) {
    // Iterate entities
    const auto &file_entities = file_node_map[locations["__node_file"].get<std::string>()]["entities"].as_table();

    // Find the last entity in the file
    auto last_entity = find_last_source(*file_entities);

    // Find the last component of the entity
    auto last_entity_tbl = last_entity->as_table();
    auto last_node = find_last_source(*last_entity_tbl);

    // Get the name by finding the Name component and getting the name from it
    sol::protected_function get_f = entity["get"];
    sol::table name_comp = get_f(entity, "Name");
    std::string ent_name = name_comp["name"];

    auto last_comp = last_node;
    // Create a path for this entity.
    std::vector<std::string> last_path = { "entities", ent_name };
    locations["__node_path"] = last_path;

    return { last_comp, last_path };
}

bool is_zero_transform_with_drawable(sol::state_view lua, const std::string &name, sol::table part_values, sol::table locations) {
    std::function<bool(sol::object, sol::object)> deep_equal = lua.script("return require('util').deep_equal");

    if (name == "transformable") {
        auto position_part = part_values["position"];
        // First check for drawable, then
        // compare position with a table of {0, 0}
        if (locations["drawable"].get<sol::optional<sol::table>>() && deep_equal(position_part, lua.create_table_with(1, 0, 2, 0))) {
            return true;
        }
    }

    return false;
}

void save_entity_component(
    sol::this_state lua_, sol::table entity, const std::string &name, sol::table comp,
    sol::table part_names, sol::table part_values
) {
    if (part_values.size() > 0) {
        spdlog::error("part_values was an array when saving {} but needs to be a table, this is a bug in editor code, refusing to save!", name);

        return;
    }

    sol::state_view lua(lua_);

    sol::optional<sol::table> locations_ = entity["__toml_location"];
    if (!locations_ || !(*locations_)["__node_file"].get<sol::optional<std::string>>()) {
        if (!locations_)
            locations_ = lua.create_table();
        create_new_entity_location(lua, entity, *locations_);
    }

    auto locations = *locations_;

    sol::optional<std::string> node_prefab_file = locations["__node_prefab_file"];

    // A deep equal function defined in lua, the function can compare tables
    std::function<bool(sol::object, sol::object)> deep_equal = lua.script("return require('util').deep_equal");

    sol::optional<sol::table> this_location_ = locations[name];

    bool this_location_only_defined_in_prefab = this_location_ && node_prefab_file
        // If the node's __node_file points to the prefab, the location is only defined in prefab,
        // so it needs to be created in the file
        && (*this_location_)["__node_file"].get<std::string>() == *node_prefab_file;

    std::map<std::string, bool> parts_overriding_prefab;
    if (node_prefab_file) {
        auto prefab_file_map = file_node_map[*node_prefab_file];

        for (auto [_, k] : part_names) {
            sol::optional<sol::object> v_ = part_values[k];

            if (v_) {
                auto maybe_prefab_comp_node = prefab_file_map[name];
                if (maybe_prefab_comp_node) {
                    auto maybe_prefab_comp_value = maybe_prefab_comp_node[k.as<std::string>()];
                    if (maybe_prefab_comp_value) {
                        auto [converted_prefab_val, _] = convert_to_lua(lua, *maybe_prefab_comp_value.node(), false);

                        parts_overriding_prefab[k.as<std::string>()] =
                            !deep_equal(converted_prefab_val, *v_);
                    }
                }
            }
        }
    }

    // Count the amount of overriden parts (those that have true as value)
    auto overriden_parts = std::count_if(
        parts_overriding_prefab.cbegin(),
        parts_overriding_prefab.cend(),
        [](const auto &arg) { return arg.second; }
    );
    if (!this_location_ || (this_location_only_defined_in_prefab && overriden_parts > 0)) {
        // Find the closest-to-bottom node for this entity.
        auto [last_comp, last_path] = find_last_comp(lua, locations);

        // If there are no other components on this entity, it's a new entity,
        // so just take the position of the last entity in the file and use that
        bool is_new_ent = last_comp == nullptr;

        // Do we need to actually output the component? This is only false when the component
        // is a transformable with position = 0, 0 and has a drawable
        bool output_component = true;

        // As a special case, if:
        // 1. the component is transformable
        // 2. it has a drawable
        // 3. it's position is 0, 0,
        // don't actually add this component to the file.
        // This is probably only the case for the background, but still
        if (is_zero_transform_with_drawable(lua, name, part_values, locations)) {
            bool has_position = parts_overriding_prefab.contains("position");
            bool overrides_position = has_position
                ? parts_overriding_prefab["position"]
                : false;

            if (!overrides_position) {
                // If position is indeed 0, 0 - do not output. UNLESS, it overrides the prefab value.
                // For new entities with a prefab, there is still need to output the header with prefab spec,
                // so just ask to not output the rest, otherwise if it's not a new entity or doesn't have a prefab just exit
                if (is_new_ent && node_prefab_file) {
                    output_component = false;
                } else {
                    return;
                }
            }
        }

        if (is_new_ent) {
            std::tie(last_comp, last_path) = path_for_new_comp_and_entity(locations, entity);
        }

        const toml::table *last_tbl = last_comp->as_table();

        // Find the key that is on the lowest line
        auto last_pair_src = find_last_source(*last_tbl)->source();

        // Table that only contains the path to the component,
        // so the the TOML encoder will create a table header.
        // e.g. { entities = { name = { component = {} } } }
        auto dummy_pathed_table = lua.create_table();
        auto curr_level = dummy_pathed_table;
        // Push the component name to the path
        last_path.push_back(name);

        for (auto path_elem : last_path) {
            // When the next level is the component, insert the prefab into the entity
            if (path_elem == name && is_new_ent && node_prefab_file) {
                const std::string prefab_dir = "resources/rooms/prefabs/";
                auto prefab_dir_pos = node_prefab_file->find(prefab_dir);
                auto prefab_name_with_ext = node_prefab_file->replace(prefab_dir_pos, prefab_dir.size(), "");
                auto prefab_name_path = std::filesystem::path(prefab_name_with_ext);
                prefab_name_path.replace_extension("");

                std::string prefab_name = prefab_name_path.string();

                curr_level["prefab"] = prefab_name;

                // If the component is not to be output, exit the loop now
                if (!output_component)
                    break;
            }

            auto created_level = lua.create_table();
            curr_level[path_elem] = created_level;
            curr_level = created_level;
        }

        auto generated_table_header = encode_toml(lua_, dummy_pathed_table);

        int replaced_char_count = 1;
        if (last_tbl->is_inline()) {
            // For inline tables, go to a new line
            last_pair_src.end.line++;
            last_pair_src.end.column = 1;

            // Don't eat any newlines
            replaced_char_count = 0;

            // Prepend one additional newline for when the table is added after an inline table
            generated_table_header.insert(0, "\n");
        } else {
            // Prepend two additional newlines for when the table is added after a non-inline table
            generated_table_header.insert(0, "\n\n");
        }

        std::ifstream toml_file;
        toml_file.open(*last_pair_src.path);
        std::string contents((std::istreambuf_iterator<char>(toml_file)), std::istreambuf_iterator<char>());

        auto end = find_in_string(contents, last_pair_src.end);
        // Replace the newline character with the new table header
        contents.replace(end, replaced_char_count, generated_table_header);

        rewrite_resource_file(*last_pair_src.path, contents);

        parse_toml(lua_, *last_pair_src.path);

        // If we got here, then a new entity has a prefab but the component has default values,
        // so no need to do the rest, exit now
        if (!output_component)
            return;

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

        bool prefab_has_part = parts_overriding_prefab.contains(k.as<std::string>());
        bool overrides_prefab = prefab_has_part
            ? parts_overriding_prefab[k.as<std::string>()]
            : false;

        bool part_only_in_prefab = false;
        if (auto part_source = this_location[k].get<sol::optional<sol::table>>(); prefab_has_part && part_source) {
            if ((*part_source)["__node_file"].get<const std::string &>() == *node_prefab_file)
                part_only_in_prefab = true;
        }

        // If value for the part was nil, it was deleted. If the value is the same as the default,
        // also delete it
        if (!v_ || deep_equal(*v_, comp_defaults[k])
            || (prefab_has_part && !overrides_prefab && !part_only_in_prefab)
            || (!overrides_prefab && is_zero_transform_with_drawable(lua, name, part_values, locations))
        ) {
            auto deleted_name = k.as<std::string>();

            if (!overrides_prefab) {
                // Delete the part from the component
                delete_part_from_comp(lua, deleted_name, locations, name);

                continue;
            }
        }
        // If we got past here, then the value exists
        auto v = *v_;

        auto source_ = this_location[k].get<sol::optional<sol::table>>();

        bool is_new = false, to_inline_table = false;

        if (!source_ || (part_only_in_prefab && overrides_prefab)) {
            if (!overrides_prefab)
                // Check the default values and if the value is the same as the default,
                // do not create it. However if it overrides the prefab value, do create it.
                if (sol::object comp_default = comp_defaults[k]; comp_default != sol::lua_nil && deep_equal(v, comp_default))
                    continue;

            is_new = true;
            insert_new_part(lua, this_location, k.as<std::string>(), &source, &to_inline_table);
        } else {
            source = find_by_path(
                (*source_)["__node_file"].get<const std::string &>(),
                (*source_)["__node_path"].get<const std::vector<std::string> &>()
            ).node()->source();
        }

        auto edited = encode_toml(lua_, v, 0);

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

    // If this component doesn't have any data anymore - delete it from the file
    auto this_location_file = (this_location)["__node_file"].get<const std::string &>();
    auto this_location_tbl = find_by_path(
        this_location_file,
        (this_location)["__node_path"].get<const std::vector<std::string> &>()
    ).as_table();
    if (this_location_tbl->size() == 0) {
        std::ifstream toml_file;
        toml_file.open(this_location_file);
        std::string contents((std::istreambuf_iterator<char>(toml_file)), std::istreambuf_iterator<char>());

        auto beginning = find_in_string(contents, this_location_tbl->source().begin),
            end = find_in_string(contents, this_location_tbl->source().end);
        // Delete the previous newline
        beginning--;
        // Delete the following newline
        end++;
        contents.replace(beginning, end - beginning, "");
        rewrite_resource_file(this_location_file, contents);
        parse_toml(sol::this_state(lua), this_location_file);

        locations[name] = sol::lua_nil;
    }
}

void create_new_room(const std::string &full_path) {
    std::filesystem::path file_path(full_path);
    auto dir_path = file_path.parent_path();

    // Create all parent dirs
    std::filesystem::create_directories(dir_path);

    std::string new_room_content =
        R"([entities.player]
prefab = "player"

[entities.player.transformable]
position = [500, 500]
)";

    std::ofstream new_room_file(full_path);
    new_room_file << new_room_content;
    new_room_file.close();

#ifdef SOMEONE_EDITOR_BASE_PATH
    // If in debug mode also save to the actual source of the resources

    std::filesystem::path editor_path(SOMEONE_EDITOR_BASE_PATH);
    editor_path /= full_path;

    new_room_file.open(editor_path, std::ios::trunc);
    new_room_file << new_room_content;
#endif
}

void save_shaders(sol::this_state lua_, sol::table shaders) {
    sol::state_view lua(lua_);

    std::string current_room_file = lua.script("return require('components.rooms').current_room_file");

    auto any_shaders = false;
    for (auto &[_k, _v] : shaders) {
        // If there is anything in the shader table, set this to true
        any_shaders = true;
        break;
    }

    bool is_new = false, had_any_before = bool(file_node_map[current_room_file]["shaders"]);
    toml::source_region source;
    if (any_shaders) {
        sol::optional<sol::table> locations_ = shaders[sol::metatable_key]["toml_location"];

        if (!locations_) {
            source.path = std::make_shared<std::string>(current_room_file);

            source.begin.column = 1;
            source.begin.line = 1;

            source.end.column = 1;
            source.end.line = 1;

            shaders[sol::create_if_nil][sol::metatable_key]["toml_location"] = lua.create_table_with(
                "__node_file", current_room_file,
                "__node_path", std::vector<std::string> { "shaders" }
            );
            is_new = true;
        } else {
            auto shaders_node = find_by_path(
                (*locations_)["__node_file"].get<const std::string &>(),
                (*locations_)["__node_path"].get<const std::vector<std::string> &>()
            );

            auto prev_node = shaders_node.node()->as_table();
            // Use previous source
            source = prev_node->source();

            // Find the last shader and use its last position
            auto last_shader = find_last_source(*prev_node)->as_table();
            auto last_line = find_last_source(*last_shader);
            if (last_line != nullptr) {
                source.end = last_line->source().end;
            } else {
                source.end = last_shader->source().end;
            }
        }
    } else {
        if (auto shaders_node = file_node_map[current_room_file]["shaders"]; shaders_node) {
            auto prev_node = shaders_node.node()->as_table();
            // Use previous source
            source = prev_node->source();

            // Find the last shader and use its last position
            auto last_shader = find_last_source(*prev_node)->as_table();
            auto last_line = find_last_source(*last_shader);
            if (last_line != nullptr) {
                source.end = last_line->source().end;
            } else {
                source.end = last_shader->source().end;
            }
        } else {
            // No shaders passed and file didn't have any
            return;
        }
    }

    std::ifstream toml_file;
    toml_file.open(*source.path);
    std::string contents((std::istreambuf_iterator<char>(toml_file)), std::istreambuf_iterator<char>());

    auto beginning = find_in_string(contents, source.begin), end = find_in_string(contents, source.end);

    std::string converted;
    if (any_shaders) {
        auto result = lua.create_table_with("shaders", shaders);
        converted = encode_toml(lua_, result, 3);

        if (is_new) {
            // Add a newline
            converted += "\n";

            if (!had_any_before) {
                // Add an additional newline if there was no shaders before at all,
                // so there'd be space between the shaders and the entities
                converted += "\n";
            }
        } else {
            // Capture the newline
            end++;

            if (!converted.ends_with("\n")) {
                converted += "\n";
            }
        }
    } else {
        converted = "";
        // Capture the newline
        end++;

        // Capture the next newlines too
        while (std::isspace(contents[end]))
            end++;
    }

    // Replace the newline character with the new table header.
    contents.replace(beginning, end - beginning, converted);

    rewrite_resource_file(*source.path, contents);

    parse_toml(lua_, *source.path);
}

void save_asset(sol::this_state lua_,
                sol::table asset_data, const std::string &category_key,
                const sol::optional<std::string> &name_, const sol::optional<std::string> &new_name_, const std::string &path) {
    sol::state_view lua(lua_);

    sol::table category_locations = asset_data[sol::metatable_key]["toml_location"][category_key];

    auto current_file = category_locations["__node_file"].get<std::string>();

    bool is_new = false;

    toml::source_region used_src;
    if (name_) {
        auto &name = *name_;
        auto current_location = category_locations[name];

        auto current_path = current_location["__node_path"].get<std::vector<std::string>>();

        used_src = find_by_path(current_file, current_path).node()->source();
        // Replace from the start of the line
        used_src.begin.column = 1;
    } else {
        auto category_path = category_locations["__node_path"].get<std::vector<std::string>>();

        auto last_node = find_last_source(
            *find_by_path(current_file, category_path).as_table()
        );
        used_src = last_node->source();
        used_src.begin.line++;
        used_src.begin.column = 1;

        used_src.end = used_src.begin;

        is_new = true;
    }

    std::ifstream toml_file;
    toml_file.open(current_file);
    std::string contents((std::istreambuf_iterator<char>(toml_file)), std::istreambuf_iterator<char>());

    auto beginning = find_in_string(contents, used_src.begin), end = find_in_string(contents, used_src.end);

    std::stringstream ss;
    if (new_name_) {
        // Create a key-value pair with the new name
        toml::table kv_table{{ {*new_name_, path} }};
        toml::default_formatter formatter(
            kv_table,
            // Disable literal strings format flag by overriding it in the formatter
            toml::format_flags::allow_multi_line_strings | toml::format_flags::allow_value_format_flags
        );

        ss << formatter;
        if (is_new)
            // Add an additional newline for new entries
            ss << "\n";
    } else {
        // If no new name is set, delete the asset. That is, don't add anything to the stringstream,
        // to replace it with emptiness
        // Also consume the newline afterwards.
        end++;
    }


    contents.replace(beginning, end - beginning, ss.str());
    rewrite_resource_file(current_file, contents);

    parse_toml(lua_, current_file);
}
