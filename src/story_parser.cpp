#include <filesystem>

#include <SFML/Graphics/Color.hpp>

#include "sol/sol.hpp"
#include "fmt/format.h"
#include "yaml-cpp/yaml.h"

#include "story_parser.hpp"
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

std::string namespace_of(std::string next) {
    auto last_separator_pos = next.find_last_of("/");
    if (last_separator_pos != std::string::npos) {
        return next.substr(0, last_separator_pos);
    } else {
        throw std::invalid_argument(fmt::format("{} doesn't not contain a namespace serparator", next));
    }
}

void StoryParser::maybe_parse_referenced_file(std::string next, lines_type &result, sol::state &lua) {
    // If it IS namespaced, try parsing a file that it references if it's not parsed yet

    auto next_namespace = namespace_of(next);

    auto any_already = std::find_if(
        result.begin(),
        result.end(),
        [&](auto pair) {
            auto &[k, v] = pair;
            return namespace_of(k) == next_namespace;
        }
    );

    // If it has not already been parsed, parse the referenced file
    if (any_already == result.end()) {
        spdlog::debug("Encountered a reference to a new namespace {}, parsing it", next_namespace);

        StoryParser::parse(result, next_namespace, lua);
    }
}

void StoryParser::parse(lines_type &result, std::string file_name, sol::state &lua) {
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

        // A map of reference to the nodes to check after everything has been built
        std::map<std::string, std::string> next_references_to_check;

        for (auto name_and_val : root_node) {
            auto name = name_and_val.first.as<std::string>();
            auto node = name_and_val.second;

            // Skip the config node
            if (name == "config") continue;

            auto inserted_name = fmt::format("{}/{}", nmspace, name);

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
                } else if (!node["next"] && StringUtils::is_number(name)) {
                    // If there's no next node, but the name of the node is a number,
                    // try using the next number as the next node

                    auto next_num = std::stoi(name) + 1;
                    auto maybe_next_name = std::to_string(next_num);
                    auto maybe_next_numbered = root_node[maybe_next_name];

                    if (maybe_next_numbered)
                        // If it exists, mark it as next
                        next = maybe_next_name;
                    else
                        // Otherwise log that there was no more numbers, let "" be there
                        spdlog::warn("Next numbered line not found for {} and there's no 'next'", inserted_name);
                } else {
                    // If there was no next at all and no patterns matched, let "" be there
                    spdlog::warn("No 'next' on {} and no shortcut patterns matched", inserted_name);
                }

                // Now add the namespace to it
                if (next != "") {
                    if (next.find('/') == std::string::npos)
                        next = fmt::format("{}/{}", nmspace, next);
                    else
                        // If the name is namespaced, parse the referenced file now
                        maybe_parse_referenced_file(next, result, lua);


                    next_references_to_check.insert({inserted_name, next});
                }

                if (node_char != "description") {
                    result_object = sol::make_object<TerminalOutputLineData>(lua, text, next);
                } else {
                    result_object = sol::make_object<TerminalDescriptionLineData>(lua, text, next);
                }
            } else if (node["responses"]) {
                decltype(TerminalVariantInputLineData::variants) variants;

                for (auto resp : node["responses"]) {
                    auto resp_text = resp["text"].as<std::string>();

                    std::string resp_next;
                    if (!resp["next"] && StringUtils::is_number(name)) {
                        // If there's no next node, but the name of the node is a number,
                        // try using the next number as the next node

                        auto next_num = std::stoi(name) + 1;
                        auto maybe_next_name = std::to_string(next_num);
                        auto maybe_next_numbered = root_node[maybe_next_name];

                        if (maybe_next_numbered) {
                            // If it exists, mark it as next
                            resp_next = maybe_next_name;
                        } else {
                            spdlog::error(
                                "Next numbered line not found for variant '{}' of {} and there's no 'next', the response needs to have somewhere to go",
                                resp_text, inserted_name
                            );
                            std::terminate();
                        }
                    } else if (resp["next"]) {
                        resp_next = resp["next"].as<std::string>();
                    } else {
                        spdlog::error(
                            "response '{}' of {} has no 'next' and the name is not a number, it needs to have somewhere to go to",
                            resp_text, inserted_name
                        );
                        std::terminate();
                    }

                    // Add the namespace to next if needed
                    if (resp_next.find('/') == std::string::npos)
                        resp_next = fmt::format("{}/{}", nmspace, resp_next);
                    else
                        maybe_parse_referenced_file(resp_next, result, lua);

                    next_references_to_check.insert({
                            fmt::format("response '{}' of {}", resp_text, inserted_name),
                            resp_next
                    });

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

        for (auto &[at, expected_next] : next_references_to_check) {
            if (!result[expected_next]) {
                spdlog::warn("{} wants {} as next, but it does not exist", at, expected_next);
            }
        }
}
