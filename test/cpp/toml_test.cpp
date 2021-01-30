#include <filesystem>
#include <fstream>

#include "catch2/catch.hpp"

#include "sol/sol.hpp"

#include "toml.hpp"
#include "usertypes.hpp"

void test_file_equal(const std::filesystem::path &path, const std::filesystem::path &test_path) {
    std::ifstream file;
    file.open(path);
    REQUIRE(file.good());
    std::string contents((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());

    std::ifstream test_file;
    test_file.open(test_path);
    REQUIRE(test_file.good());

    std::string test_contents((std::istreambuf_iterator<char>(test_file)), std::istreambuf_iterator<char>());

    REQUIRE(contents == test_contents);
}

TEST_CASE("TOML", "[toml]") {
    sol::state lua;
    lua.open_libraries(sol::lib::base, sol::lib::table, sol::lib::string, sol::lib::package,
                       sol::lib::coroutine, sol::lib::math, sol::lib::debug, sol::lib::os, sol::lib::io,
                       sol::lib::utf8);

    // Setup the lua path to see luarocks packages
    auto package_path = std::filesystem::path("resources") / "lua" / "share" / "lua" / SOMEONE_LUA_VERSION / "?.lua;";
    package_path += std::filesystem::path("resources") / "lua" / "share" / "lua" / SOMEONE_LUA_VERSION / "?" / "init.lua;";
    lua["package"]["path"] = std::string(package_path.string()) + std::string(lua["package"]["path"]);

    auto package_cpath = std::filesystem::path("resources") / "lua" / "lib" / "lua" / SOMEONE_LUA_VERSION / "?." SOMEONE_LIB_EXT ";";
    lua["package"]["cpath"] = std::string(package_cpath.string()) + std::string(lua["package"]["cpath"]);

    sol::this_state this_lua(lua);

    sol::table lines = lua.create_table();

    StaticFonts static_fonts;
    register_usertypes(lua, static_fonts);

    SECTION("Encoding") {
        auto lua_obj = lua.create_table_with(
            "string", "test",
            "int", 413,
            "float", 413.0,
            "bool", true,
            "table", lua.create_table_with("test", 1),
            "array", lua.create_table_with(0, "test", 1, "test 2")
        );

        SECTION("Inline table") {
            auto result = encode_toml(this_lua, lua_obj, true);
            REQUIRE(result ==
                    R"({ array = [ "test", "test 2" ], bool = true, float = 413.0, int = 413, string = "test", table = { test = 1 } })"
            );
        }
        SECTION("Non-inline table") {
            auto result = encode_toml(this_lua, lua_obj, false);
            REQUIRE(result == R"(array = [ "test", "test 2" ]
bool = true
float = 413.0
int = 413
string = "test"

[table]
test = 1)");
        }
    }

    SECTION("Parsing") {
        auto [parsed_, parse_err] = parse_toml(this_lua, "resources/rooms/test1/test.toml");
        REQUIRE(parse_err == sol::lua_nil);

        sol::table parsed(parsed_);

        std::function<bool(sol::object, sol::object)> deep_equal =
            lua.script("return require('util').deep_equal");

        SECTION("Parsed data") {
            REQUIRE(
                deep_equal(
                    parsed,
                    lua.script(R"(
return {
  entities = {
    test = {
      collider = { trigger= true, mode = "sprite" },
      transformable = { position = {100, 100} },
      drawable = { z = 1, kind = "sprite", texture_asset = "mainchar" }
    }
  }
})")
                )
            );
        }

        SECTION("Parsed data source") {
            sol::table parsed_src = parsed[sol::metatable_key]["toml_location"];
            sol::table tf_src = parsed_src["entities"]["test"]["transformable"];
            REQUIRE(
                tf_src["__node_file"].get<std::string>() == "resources/rooms/test1/test.toml"
            );
            REQUIRE(
                tf_src["__node_path"] == std::vector<std::string> { "entities", "test", "transformable" }
            );
        }
    }

    SECTION("Saving components") {
        std::filesystem::path original_file("resources/rooms/test1/test.toml");
        std::filesystem::path backup_file = std::filesystem::temp_directory_path() / original_file.filename();

        SECTION("Copy the original file") {
            // Back up the original file before running the tests
            std::filesystem::copy(
                original_file,
                backup_file,
                std::filesystem::copy_options::overwrite_existing
            );
        }

        // Copy the original back before every test
        std::filesystem::copy(backup_file, original_file, std::filesystem::copy_options::overwrite_existing);

        sol::table rooms = lua.script("return require('components.rooms')");
        // Load the room
        rooms["load_room"]("test1/test", true);

        sol::table test_entity = rooms["engine"]["entities"][1];
        auto get_comp = test_entity["get"].get<std::function<sol::table(sol::object, std::string)>>();

        auto save_comp_test = [&](std::string name, std::string comp_name, std::vector<std::string> part_names_,
                                  sol::table part_values, std::string result_name) {
            sol::table part_names = sol::make_object(lua, sol::as_table(part_names_));

            save_entity_component(
                this_lua,
                test_entity,
                name,
                get_comp(test_entity, comp_name),
                part_names,
                part_values
            );

            std::filesystem::path test_path("resources/rooms/test1/results/");
            test_path /= result_name + ".toml";

            test_file_equal(original_file, test_path);
        };

        SECTION("Updating component part") {
            SECTION("In an inline component") {
                save_comp_test(
                    "collider", "Collider",
                    { "mode" },
                    lua.create_table_with("mode", "constant"),
                    "inline_update_mode"
                );
            }
            SECTION("In a non-inline component") {
                save_comp_test(
                    "transformable", "Transformable",
                    { "position" },
                    lua.create_table_with("position", lua.create_table_with(0, 200, 1, 200)),
                    "update_pos"
                );
            }
        }

        SECTION("Removing component part") {
             SECTION("In an inline component") {
                 SECTION("In the beginning") {
                     save_comp_test(
                         "collider", "Collider",
                         { "trigger" },
                         lua.create_table_with("trigger", sol::lua_nil),
                         "inline_remove_trigger"
                     );
                 }
                 SECTION("In the end") {
                     save_comp_test(
                         "collider", "Collider",
                         { "mode" },
                         lua.create_table_with("mode", sol::lua_nil),
                         "inline_remove_mode"
                     );
                 }
             }

             SECTION("In a non-inline component") {
                 save_comp_test(
                     "drawable", "Drawable",
                     { "z" },
                     lua.create_table_with("z", sol::lua_nil),
                     "remove_z"
                 );
             }

             SECTION("Component with no parts") {
                 SECTION("Non-inline component") {
                     save_comp_test(
                         "transformable", "Transformable",
                         { "position" },
                         lua.create_table_with("position", sol::lua_nil),
                         "remove_pos_and_comp"
                     );
                 }
                 // Not possible yet, waiting for toml-cpp to implement table key source lookup
                 /*
                 SECTION("Inline component") {
                     save_comp_test(
                         "collider", "Collider",
                         { "mode", "trigger" },
                         lua.create_table_with(),
                         "inline_remove_collider"
                     );
                 }
                 */
             }
        }

        SECTION("Adding a component part") {
            SECTION("To an inline component") {
                save_comp_test(
                    "collider", "Collider",
                    { "test" },
                    lua.create_table_with("test", 1),
                    "inline_add_collider_test"
                );
            }

            SECTION("To a non-inline component") {
                save_comp_test(
                    "transformable", "Transformable",
                    { "test" },
                    lua.create_table_with("test", 1),
                    "add_transformable_test"
                );
            }
        }

        SECTION("Remove the temporary file") {
            // After everything ran, remove the temporary file
            std::filesystem::remove(backup_file);
        }
    }
}
