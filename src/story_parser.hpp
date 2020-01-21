#include <filesystem>

#include <SFML/Graphics/Color.hpp>

#include "fmt/format.h"
#include "yaml-cpp/yaml.h"

#include "logger.hpp"
#include "string_utils.hpp"
#include "line_data.hpp"

namespace YAML {

template <> struct convert<sf::Color> {
    static bool decode(const Node& node, sf::Color &rhs) {
        if(!node.IsSequence() || node.size() != 3) return false;

        rhs.r = node[0].as<uint32_t>();
        rhs.g = node[1].as<uint32_t>();
        rhs.b = node[2].as<uint32_t>();
        rhs.a = 255;

        return true;
    }
};

template <> struct convert<CharacterConfig> {
    static bool decode(const Node& node, CharacterConfig &rhs) {
        if(!node.IsMap()) return false;

        if (node["color"])
            rhs.color = node["color"].as<sf::Color>();

        return true;
    }
};
}

struct StoryParser {
    static std::map<std::string, sol::object> parse(std::string file_name, sol::state &lua) {
        auto full_file_name = std::filesystem::path("resources/story/") / file_name;
        full_file_name.replace_extension(".yml");

        std::string nmspace = file_name;

        YAML::Node root_node = YAML::LoadFile(full_file_name);

        std::map<std::string, CharacterConfig> character_configs;
        if (root_node["config"]) {
            auto config = root_node["config"];

            if (config["chars"]) {
                character_configs = config["chars"].as<decltype(character_configs)>();
            }
        }

        std::map<std::string, sol::object> result;
        for (auto name_and_val : root_node) {
            auto name = name_and_val.first.as<std::string>();
            auto node = name_and_val.second;

            // Skip the config node
            if (name == "config") continue;

            auto inserted_name = fmt::format("{}/{}", nmspace, name);

            // If there's a reference to the next file, parse that file now
            if (node["next_file"]) {
                auto next_file = node["next_file"].as<std::string>();
                spdlog::info("Encountered a reference to the next file {} in {}, parsing it first", next_file, inserted_name);
                auto parsed_next = StoryParser::parse(next_file, lua);

                result.insert(parsed_next.begin(), parsed_next.end());
            }

            if (!node["char"]) {
                spdlog::error("{} doesn't specify a character", inserted_name);
            }

            auto node_char = node["char"].as<std::string>();

            CharacterConfig char_config;
            auto found_char_config = character_configs.find(node_char);
            if (found_char_config == character_configs.end()) {
                spdlog::warn(
                    "{} uses the character {}, but it does not exist",
                    inserted_name,
                    node_char
                );
            } else {
                char_config = found_char_config->second;
            }

            std::optional<std::string> node_script;
            if (node["script"])
                node_script = node["script"].as<std::string>();

            sol::object result_object;

            if (node["text"]) {
                // Get the text of the node
                auto text = node["text"].as<std::string>();

                std::string next;
                if (node["next"]) {
                    next = node["next"].as<std::string>();
                    // Namespace the next now, as it might also reference an already namespaced name
                    if (next != "" && next.find('/') == std::string::npos)
                        next = fmt::format("{}/{}", nmspace, next);

                    if (!result[next]) {
                        // If the node doesn't exist, log a warning
                        spdlog::warn("{} wants {} as next, but it doesn't exist", inserted_name, next);
                    }
                } else if (!node["next"] && StringUtils::is_number(name)) {
                    // If there's no next node, but the name of the node is a number,
                    // try using the next number as the next node

                    auto next_num = std::stoi(name) + 1;
                    auto maybe_next_name = std::to_string(next_num);
                    auto maybe_next_numbered = root_node[maybe_next_name];

                    if (maybe_next_numbered) {
                        // If it exists, mark it as next
                        next = maybe_next_name;
                    } else {
                        // Otherwise log that there was no more numbers, let "" be there
                        spdlog::info("Next numbered node not found for {} and there's no 'next'", inserted_name);
                    }
                } else {
                    // If there was no next at all and no patterns matched, let "" be there
                    spdlog::warn("No 'next' on {} and no shortcut patterns matched", inserted_name);
                }
                // Now add the namespace to it
                if (next != "" && next.find('/') == std::string::npos)
                    next = fmt::format("{}/{}", nmspace, next);

                if (node_char != "description") {
                    result_object = sol::make_object<TerminalOutputLineData>(lua, text, next);
                } else {
                    result_object = sol::make_object<TerminalDescriptionLineData>(lua, text, next);
                }
            } else if (node["responses"]) {
                decltype(TerminalVariantInputLineData::variants) variants;

                for (auto resp : node["responses"]) {
                    auto resp_text = resp["text"].as<std::string>();
                    if (!resp["next"]) {
                        spdlog::error(
                            "response '{}' of {} has no 'next', it has to have somewhere to go to",
                            resp_text, inserted_name
                        );

                        std::terminate();
                    }

                    auto resp_next = resp["next"].as<std::string>();
                    if (resp_next.find('/') == std::string::npos)
                        resp_next = fmt::format("{}/{}", nmspace, resp_next);

                    if (!result[resp_next]) {
                        spdlog::warn(
                            "response '{}' of {} wants {} as next, but it doesn't exist",
                            resp_text, inserted_name, resp_next
                        );
                    }

                    // Create the variant data with the required parameters
                    auto variant = TerminalVariantInputLineData::Variant(resp_text, resp_next);

                    // If there's a condition, add it too
                    if (resp["condition"])
                        variant.condition = resp["condition"].as<std::string>();

                    variants.push_back(variant);
                }

                result_object = sol::make_object<TerminalVariantInputLineData>(lua, variants);
            } else {
                spdlog::error("Unknown line type at {}", inserted_name);
                std::terminate();
            }

            auto &general_line = result_object.as<TerminalLineData>();
            general_line.character_config = char_config;
            general_line.script = node_script;

            result.insert({inserted_name, result_object});
        }

        return result;
    }
};
