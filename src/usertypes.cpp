#include <filesystem>
#include <numeric>

#include "story_parser.hpp"
#include "usertypes.hpp"
#include "line_data.hpp"

#include "toml.hpp"

#include "sol/sol.hpp"

void register_usertypes(sol::state &lua, StaticFonts &fonts) {
    // Basic SFML types
    register_sfml_usertypes(lua, fonts);

    // ImGui
    register_imgui_usertypes(lua);

    // Helper classes

    auto mod_data_type = lua.new_usertype<ModData>(
        "ModData",
        "name", &ModData::name,
        "pretty_name", &ModData::pretty_name,
        "lua_files", &ModData::lua_files,
        "lines", &ModData::lines,
        "first_line", &ModData::first_line,
        "first_room", &ModData::first_room
    );

    auto static_fonts_type = lua.new_usertype<StaticFonts>(
        "StaticFonts",
        "main_font", sol::var(std::ref(fonts.main_font)),
        "font_size", sol::var(std::ref(fonts.font_size))
    );

    lua["TOML"] = lua.create_table_with(
        "parse", &parse_toml,
        "encode", [](sol::this_state lua_, sol::object obj) { return encode_toml(lua_, obj); },
        "save_entity_component", &save_entity_component,
        "create_new_room", &create_new_room,
        "save_shaders", &save_shaders,
        "save_asset", &save_asset
    );

    // Data

    auto char_config_type = lua.new_usertype<CharacterConfig>(
        "CharacterConfig",
        "color", sol::readonly(&CharacterConfig::color),
        "font_size", sol::readonly(&CharacterConfig::font_size)
    );

    auto term_line_type = lua.new_usertype<TerminalLineData>(
        "TerminalLineData",
        "character_config", sol::readonly(&TerminalLineData::character_config),
        "script", sol::readonly(&TerminalLineData::script),
        "script_after", sol::readonly(&TerminalLineData::script_after)
    );
    auto term_output_line_type = lua.new_usertype<TerminalOutputLineData>(
        "TerminalOutputLineData",
        sol::base_classes, sol::bases<TerminalLineData>(),
        "text", sol::readonly(&TerminalOutputLineData::text),
        "next", sol::readonly(&TerminalOutputLineData::next)
    );

    auto term_variant_input_type = lua.new_usertype<TerminalVariantInputLineData>(
        "TerminalVariantInputLineData",
        sol::base_classes, sol::bases<TerminalLineData>(),
        "variants", sol::readonly(&TerminalVariantInputLineData::variants)
    );

    using Variant = TerminalVariantInputLineData::Variant;
    auto term_variant_variant_type = lua.new_usertype<Variant>(
        "TerminalVariantInputLineDataVariant",
        "text", sol::readonly(&Variant::text),
        "next", sol::readonly(&Variant::next),
        "condition", sol::readonly(&Variant::condition)
    );


    auto input_wait_line_type = lua.new_usertype<TerminalInputWaitLineData>(
        "TerminalInputWaitLineData",
        sol::base_classes, sol::bases<TerminalLineData, TerminalOutputLineData>()
    );

    auto term_text_input_type = lua.new_usertype<TerminalTextInputLineData>(
        "TerminalTextInputLineData",
        sol::base_classes, sol::bases<TerminalLineData>(),
        "before", sol::readonly(&TerminalTextInputLineData::before),
        "after", sol::readonly(&TerminalTextInputLineData::after),
        "variable", sol::readonly(&TerminalTextInputLineData::variable),
        "max_length", sol::readonly(&TerminalTextInputLineData::max_length),
        "filters", sol::readonly(&TerminalTextInputLineData::filters),
        "next", sol::readonly(&TerminalTextInputLineData::next)
    );

    auto custom_line_type = lua.new_usertype<TerminalCustomLineData>(
        "TerminalCustomLineData",
        sol::base_classes, sol::bases<TerminalLineData>(),
        "class", sol::readonly(&TerminalCustomLineData::class_),
        "data", sol::readonly(&TerminalCustomLineData::data)
    );

    lua["fs"] = lua.create_table_with(
        "isdir", [](const std::string &path) { return std::filesystem::is_directory(path); },
        "isfile", [](const std::string &path) { return std::filesystem::is_regular_file(path); },
        "exists", [](const std::string &path) { return std::filesystem::exists(path); },
        "mkdir", [](const std::string &path) { return std::filesystem::create_directory(path); },
        "each", [](const std::string &path) { return std::filesystem::create_directory(path); },
        "dir", [&lua](const std::string &path) {
            auto result = lua.create_table();
            for (const auto &entry : std::filesystem::directory_iterator(path)) {
                std::string basePath = std::filesystem::path(entry).filename().string();
                result.add(basePath);
            }
            result.add("..");

            return result;
        }
    );
}
