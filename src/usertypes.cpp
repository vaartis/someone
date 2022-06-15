#include <filesystem>
#include <numeric>

#include <zlib.h>

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
    lua["decode_base64_and_decompress_zlib"] = [](const std::string &encoded, int dataSize) {
        auto base64_decode = [](std::string const& encoded_string) {
            static const std::string base64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
            auto is_base64 = [](unsigned char c) { return (isalnum(c) || (c == '+') || (c == '/')); };

            int in_len = encoded_string.size();
            int i = 0;
            int j = 0;
            int in_ = 0;
            unsigned char char_array_4[4], char_array_3[3];
            std::vector<unsigned char> ret;

            while (in_len-- && ( encoded_string[in_] != '=') && is_base64(encoded_string[in_])) {
                char_array_4[i++] = encoded_string[in_]; in_++;
                if (i ==4) {
                    for (i = 0; i <4; i++)
                        char_array_4[i] = base64_chars.find(char_array_4[i]);

                    char_array_3[0] = (char_array_4[0] << 2) + ((char_array_4[1] & 0x30) >> 4);
                    char_array_3[1] = ((char_array_4[1] & 0xf) << 4) + ((char_array_4[2] & 0x3c) >> 2);
                    char_array_3[2] = ((char_array_4[2] & 0x3) << 6) + char_array_4[3];

                    for (i = 0; (i < 3); i++)
                        ret.push_back(char_array_3[i]);
                    i = 0;
                }
            }

            if (i) {
                for (j = i; j <4; j++)
                    char_array_4[j] = 0;

                for (j = 0; j <4; j++)
                    char_array_4[j] = base64_chars.find(char_array_4[j]);

                char_array_3[0] = (char_array_4[0] << 2) + ((char_array_4[1] & 0x30) >> 4);
                char_array_3[1] = ((char_array_4[1] & 0xf) << 4) + ((char_array_4[2] & 0x3c) >> 2);
                char_array_3[2] = ((char_array_4[2] & 0x3) << 6) + char_array_4[3];

                for (j = 0; (j < i - 1); j++) ret.push_back(char_array_3[j]);
            }

            return ret;
        };

        auto decoded = base64_decode(encoded);
        uint32_t decodedSize = decoded.size();

        uLongf decompressedSize = dataSize * sizeof(uint32_t);

        std::vector<Bytef> decompressedData(decompressedSize);
        uncompress(decompressedData.data(), &decompressedSize,
                   (const Bytef*)decoded.data(), decodedSize);

        std::vector<uint32_t> data;
        data.reserve(dataSize);
        auto tileIds = (uint32_t*)decompressedData.data();
        for (auto i = 0; i < dataSize; i++)
            data.push_back(tileIds[i]);

        return data;
    };
}
