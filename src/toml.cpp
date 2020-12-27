#include <fstream>

#include "toml.hpp"
#include "logger.hpp"

sol::table parse_toml(sol::this_state lua_, const std::string &path) {
    sol::state_view lua(lua_);

    auto result = lua.create_table();

    toml::table root;
    try {
        root = toml::parse_file(path);
    } catch (const toml::parse_error &err) {
        return sol::make_object(lua, std::make_tuple(sol::lua_nil, err.description()));
    }

    // Converts the TOML types to lua/C++
    std::function<sol::object(toml::node &)> convert = [&](toml::node &node) -> sol::object {
        using namespace toml;

        switch (node.type()) {
        case node_type::table: {
            auto this_tbl = lua.create_table();

            for (auto [k, v] : *node.as_table()) {
                this_tbl[k] = convert(v);
            }

            return this_tbl;
        }
        case node_type::array: {
            auto this_arr = lua.create_table();

            for (auto &v : *node.as_array()) {
                this_arr.add(convert(v));
            }

            return this_arr;
        }
        case node_type::string:
            return sol::make_object(lua, std::string(*node.as_string()));
        case node_type::integer:
            return sol::make_object(lua, **node.as_integer());
        case node_type::floating_point:
            return sol::make_object(lua, **node.as_floating_point());
        case node_type::boolean:
            return sol::make_object(lua, **node.as_boolean());
        case node_type::date:
        case node_type::time:
        case node_type::date_time:
        case node_type::none:
            spdlog::error("Got an unknown TOML type somehwere in {}", path);
            std::terminate();
        }
    };

    return convert(root);
}

std::string encode_toml(sol::this_state lua_, sol::table table) {
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
    auto result = convert(table);
    toml::node_view result_view(*result);

    std::stringstream ss;
    ss << result_view;

    return ss.str();
}
