#include <filesystem>

#include <SFML/Graphics/Color.hpp>

#include "sol/sol.hpp"
#include "fmt/format.h"
#include "yaml-cpp/yaml.h"

#include "story_parser.hpp"
#include "logger.hpp"
#include "string_utils.hpp"
#include "line_data.hpp"

#ifndef NDEBUG
#include <fstream>
#include "toml++/toml.h"
#endif

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
        if (node["font_size"])
            rhs.font_size = node["font_size"].as<uint32_t>();

        return true;
    }
};

}

#ifndef NDEBUG
void StoryParser::total_wordcount() {
  std::vector<std::string> all_strings;

  for (const auto [_key, line_data] : lines) {
      if (auto line = line_data.as<std::optional<TerminalOutputLineData>>(); line.has_value())
          all_strings.push_back(line->text);
      else if (auto line = line_data.as<std::optional<TerminalVariantInputLineData>>(); line.has_value())
          for (auto &variant : line->variants)
              all_strings.push_back(variant.text);
      else if (auto line = line_data.as<std::optional<TerminalTextInputLineData>>(); line.has_value()) {
          all_strings.push_back(line->before);
          all_strings.push_back(line->after);
      }
  }

  uint32_t total_wordcount = 0;
  uint32_t wordcount = 0;
  for (const auto &str : all_strings) {
      bool in_script = false;

      for (const char ch : str) {
          if (ch == '<' && !in_script)
              in_script = true;
          if (ch == '>' && in_script)
              in_script = false;
          if (!in_script && std::isspace(ch))
              wordcount++;
      }
  }
  total_wordcount += wordcount;

  uint32_t notes_wordcount = 0;
  {
      auto notes_file = toml::parse_file("resources/rooms/notes.toml");
      for (auto kv : notes_file) {
          toml::table *note = kv.second.as_table();

          auto main_text = note->get("text");
          auto text = main_text->as_string()->get();
          for (const char ch : text) {
              if (std::isspace(ch))
                  notes_wordcount++;
          }

          if (auto bottom_text = note->get("bottom_text"); bottom_text) {
              auto bot_text = bottom_text->as_string()->get();
              for (const char ch : bot_text) {
                  if (std::isspace(ch))
                      notes_wordcount++;
              }
          }
      }
  }
  total_wordcount += notes_wordcount;

  spdlog::debug("Total amount of words: {} ({} + {})", total_wordcount, wordcount, notes_wordcount);
}
#endif

std::string namespace_of(std::string next) {
    auto last_separator_pos = next.find_last_of("/");
    if (last_separator_pos != std::string::npos) {
        return next.substr(0, last_separator_pos);
    } else {
        throw std::invalid_argument(fmt::format("{} doesn't not contain a namespace serparator", next));
    }
}

void StoryParser::maybe_parse_referenced_file(std::string next) {
    // If it IS namespaced, try parsing a file that it references if it's not parsed yet

    auto next_namespace = namespace_of(next);

    bool any_already = false;
    for (const auto &[key, value] : lines) {
        if (namespace_of(key.as<std::string>()) == next_namespace) {
            any_already = true;

            break;
        }
    }

    // If it has not already been parsed, parse the referenced file
    if (!any_already) {
        spdlog::debug("Encountered a reference to a new namespace {}, parsing it", next_namespace);

        StoryParser::parse(next_namespace);
    }
}

std::optional<std::tuple<std::string, uint32_t>> split_as_numbered(const std::string &name) {
    auto maybe_last_dash = name.rfind('-');

    // number_string is something that might be a number, from which
    // the next line can be derived by incrementing that number
    std::string before_number_string;
    std::string maybe_number_string;
    if (maybe_last_dash == name.npos) {
        maybe_number_string = name;
    } else {
        before_number_string = name.substr(0, maybe_last_dash + 1);
        maybe_number_string = name.substr(maybe_last_dash + 1);
    }

    if (StringUtils::is_number(maybe_number_string)) {
        return std::make_tuple(before_number_string, std::stoi(maybe_number_string));
    } else {
        return std::nullopt;
    }
}

void StoryParser::parse(std::string file_name, std::filesystem::path base) {
    auto full_file_name = base / file_name;
    full_file_name.replace_extension(".yml");

    std::string nmspace = file_name;

    YAML::Node root_node = YAML::LoadFile(full_file_name.string());

    std::map<std::string, CharacterConfig> character_configs;

    std::vector<std::string> dialogue_between_chars;
    std::optional<uint32_t> dialogue_between_chars_current;

    if (root_node["config"]) {
        auto config = root_node["config"];

        if (config["chars"]) {
            character_configs = config["chars"].as<decltype(character_configs)>();
        }

        // dialogue_between works as follows: there's a list of characters in the dialogue, and, provided
        // that the characters are alternating every phrase, it will automatically switch to the next character
        // in that list every time, unless the character is explicitly specified. If the character is specified,
        // then, if it's one of those participating in the dialogue, the dialogue tracking switches to that character,
        // and if not, then it does nothing and the dialogue continues as usual on the next phrase.
        //
        // However, it only correctly works if the dialogue is going linearly and there are no hubs or anything of sort,
        // then it might behave strangely. A good practice would be to put characters on every hub answer beginning.
        // Since the parser does not consider branching, there's no easy way to allow skipping names for hubs.
        if (config["dialogue_between"]) {
            auto dialogue_chars = config["dialogue_between"].as<std::vector<std::string>>();
            dialogue_between_chars.insert(dialogue_between_chars.end(), dialogue_chars.begin(), dialogue_chars.end());
            // When run for the first time, the first character will be selected, bringing this to 0
            dialogue_between_chars_current = -1;
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

        std::string node_char;
        if (node["char"]) {
            node_char = node["char"].as<std::string>();
            if (!dialogue_between_chars.empty()) {
                // If the character specified is a dialogue character, then the dialogue switches to them and continues with the next character
                auto maybe_found_char_iter = std::find(dialogue_between_chars.begin(), dialogue_between_chars.end(), node_char);
                if (maybe_found_char_iter != dialogue_between_chars.end()) {
                    dialogue_between_chars_current = std::distance(dialogue_between_chars.begin(), maybe_found_char_iter);
                }
            }
        } else {
            if (!dialogue_between_chars.empty()) {
                dialogue_between_chars_current =
                    // If the next number would go out of bounds, wrap around
                    *dialogue_between_chars_current + 1 >= dialogue_between_chars.size()
                    ? 0
                    // Otherwise, switch to the next character
                    : *dialogue_between_chars_current + 1;

                node_char = dialogue_between_chars[*dialogue_between_chars_current];
            } else {
                spdlog::error("{} doesn't specify a character and there's no dialogue going on", inserted_name);
            }
        }

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
        if (node["script"]) node_script = node["script"].as<std::string>();

        std::optional<std::string> node_script_after;
        if (node["script_after"])
            node_script_after = node["script_after"].as<std::string>();


        sol::object result_object;

        if (node["text"]) {
            // Get the text of the node
            auto text = node["text"].as<std::string>();

            std::string next;
            if (node["next"]) {
                next = node["next"].as<std::string>();
            } else {
                if (auto splitted = split_as_numbered(name); splitted) {
                    auto [before_number_string, number] = *splitted;

                    auto next_num = number + 1;
                    // Next name is anything that was before + an incremented number,
                    // or just an incremented number if the while name is a number
                    std::string next_name = before_number_string + std::to_string(next_num);
                    auto maybe_next_numbered = root_node[next_name];

                    if (maybe_next_numbered) {
                        // If it exists, mark it as next
                        next = next_name;
                    } else {
                        // Otherwise log that there was no more numbers, let "" be there
                        spdlog::warn("Next numbered line not found for {} and there's no 'next'", inserted_name);
                    }
                } else {
                    // If there was no next at all and no patterns matched, let "" be there
                    spdlog::warn("No 'next' on {} and no shortcut patterns matched", inserted_name);
                }
            }

            // Now add the namespace to it
            if (next != "") {
                if (next.find('/') == std::string::npos)
                    next = fmt::format("{}/{}", nmspace, next);
                else
                    // If the name is namespaced, parse the referenced file now
                    maybe_parse_referenced_file(next);


                next_references_to_check.insert({inserted_name, next});
            }

            if (node["wait"] && node["wait"].as<bool>()) {
                result_object = sol::make_object<TerminalInputWaitLineData>(lua, text, next);
            } else {
                result_object = sol::make_object<TerminalOutputLineData>(lua, text, next);
            }
        } else if (node["responses"]) {
            decltype(TerminalVariantInputLineData::variants) variants;

            if (!node["responses"].IsSequence()) {
                spdlog::error("'responses' needs to be a sequence, but it's not a sequence in {}", inserted_name);
                std::terminate();
            }

            for (auto resp : node["responses"]) {
                auto resp_text = resp["text"].as<std::string>();

                std::string resp_next;
                if (resp["next"]) {
                    resp_next = resp["next"].as<std::string>();
                } else {
                    if (auto splitted = split_as_numbered(name); splitted) {
                        auto [before_number_string, number] = *splitted;

                        auto next_num = number + 1;
                        // Next name is anything that was before + an incremented number,
                        // or just an incremented number if the while name is a number
                        std::string next_name = before_number_string + std::to_string(next_num);
                        auto maybe_next_numbered = root_node[next_name];

                        if (maybe_next_numbered) {
                            // If it exists, mark it as next
                            resp_next = next_name;
                        } else {
                            // Otherwise log that there was no more numbers, let "" be there
                            spdlog::error(
                                "response '{}' of {} has no 'next' and the next numbered line {} does not exist, the response "
                                "needs to have somewhere to go to",
                                resp_text, inserted_name, next_name
                            );
                            std::terminate();
                        }
                    } else {
                        spdlog::error(
                            "response '{}' of {} has no 'next' and the name is not a number, it needs to have somewhere to go to",
                            resp_text, inserted_name
                        );
                        std::terminate();
                    }
                }

                // Add the namespace to next if needed
                if (resp_next.find('/') == std::string::npos)
                    resp_next = fmt::format("{}/{}", nmspace, resp_next);
                else
                    maybe_parse_referenced_file(resp_next);

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
        } else if (node["text_input"]) {
            auto data = node["text_input"];

            std::string next;
            if (node["next"]) {
                next = node["next"].as<std::string>();
            } else {
                if (auto splitted = split_as_numbered(name); splitted) {
                    auto [before_number_string, number] = *splitted;

                    auto next_num = number + 1;
                    // Next name is anything that was before + an incremented number,
                    // or just an incremented number if the while name is a number
                    std::string next_name = before_number_string + std::to_string(next_num);
                    auto maybe_next_numbered = root_node[next_name];

                    if (maybe_next_numbered) {
                        // If it exists, mark it as next
                        next = next_name;
                    } else {
                        // Otherwise log that there was no more numbers, let "" be there
                        spdlog::warn("Next numbered line not found for {} and there's no 'next'", inserted_name);
                    }
                } else {
                    // If there was no next at all and no patterns matched, let "" be there
                    spdlog::warn("No 'next' on {} and no shortcut patterns matched", inserted_name);
                }
            }

            // Now add the namespace to it
            if (next != "") {
                if (next.find('/') == std::string::npos)
                    next = fmt::format("{}/{}", nmspace, next);
                else
                    // If the name is namespaced, parse the referenced file now
                    maybe_parse_referenced_file(next);


                next_references_to_check.insert({inserted_name, next});
            }

            std::vector<std::string> filters;
            if (data["filters"]) {
                filters = data["filters"].as<std::vector<std::string>>();
            } else {
                filters = { "alpha" };
            }

            result_object =
                sol::make_object<TerminalTextInputLineData>(
                    lua,
                    data["before"].as<std::string>(), data["after"].as<std::string>(), data["variable"].as<std::string>(),
                    data["max_length"].as<uint32_t>(), filters, next
                );
        } else if (node["custom"]) {
            auto custom = node["custom"];

            auto as_map = custom.as<std::map<std::string, YAML::Node>>();
            if (as_map.size() != 1) {
                spdlog::error("custom directive must include exactly one key, but in line {} it includes {}", inserted_name, as_map.size());

                std::terminate();
            }
            auto [custom_name, data] = *as_map.cbegin();

            auto last_dot = custom_name.rfind('.');
            if (last_dot == std::string::npos) {
                spdlog::error("No dot separator found in custom line directive of {}", inserted_name);

                std::terminate();
            }
            auto module = custom_name.substr(0, last_dot);
            auto class_ = custom_name.substr(last_dot + 1, custom_name.size());

            sol::object imported_module = lua.script(fmt::format("return require('{}')", module));
            if (!imported_module.is<sol::table>()) {
              std::string string_repr = lua["tostring"](imported_module);

              spdlog::error(
                "The {} module for the {} custom line is expected to export a table, but exports {}",
                module, inserted_name, string_repr
              );
              std::terminate();
            }

            sol::optional<sol::object> maybe_class = imported_module.as<sol::table>().get<sol::optional<sol::object>>(class_);
            if (!maybe_class) {
                spdlog::error("Cannot find the {} class in the {} module for the {} custom line", class_, module, inserted_name);
                std::terminate();
            }
            if (!maybe_class->is<sol::table>()) {
              std::string string_repr = lua["tostring"](*maybe_class);
              spdlog::error(
                "The object that is supposed to be a custom line class {}.{} for the line {} is actually {}",
                module, class_, inserted_name, string_repr
              );
              std::terminate();
            }

            std::function<sol::object (const YAML::Node &)> convert =
                [&](const YAML::Node &data_entry) -> sol::object {
                    using namespace YAML;

                    switch (data_entry.Type()) {
                    case NodeType::Null:
                        return sol::lua_nil;
                    case NodeType::Scalar:
                        // If there's a line-name tag, parse the data as a line name and try resolving the reference
                        if (data_entry.Tag() == "!line-name") {
                            std::string val = data_entry.as<std::string>();
                            if (val.find('/') == std::string::npos)
                                val = fmt::format("{}/{}", nmspace, val);
                            else
                                // If the name is namespaced, parse the referenced file now
                                maybe_parse_referenced_file(val);

                            return sol::make_object(lua, val);
                        }

                        // int convertion must be first, since a convertion
                        // to a float succeedes from an integer just fine
                        if (int val; YAML::convert<int>::decode(data_entry, val))
                            return sol::make_object(lua, val);
                        else if (float val; YAML::convert<float>::decode(data_entry, val))
                            return sol::make_object(lua, val);
                        else if (std::string val; YAML::convert<std::string>::decode(data_entry, val))
                            return sol::make_object(lua, val);
                    case NodeType::Sequence: {
                        auto arr = lua.create_table();
                        for (auto val : data_entry) {
                            arr.add(convert(val));
                        }

                        return arr;
                    }
                    case NodeType::Map: {
                        sol::table table = lua.create_table();

                        for (const auto &kv : data_entry) {
                            auto name = kv.first.as<std::string>();
                            auto data_entry = kv.second;

                            table[name] = convert(data_entry);
                        }

                        return table;
                    }
                    case NodeType::Undefined:
                        throw std::runtime_error("Undefined key found?");
                    }
                };

            result_object = sol::make_object<TerminalCustomLineData>(lua, *maybe_class, convert(custom[custom_name]));
        } else {
            spdlog::error("Unknown line type at {}", inserted_name);
            std::terminate();
        }

        auto &general_line = result_object.as<TerminalLineData>();
        general_line.character_config = char_config;
        general_line.script = node_script;
        general_line.script_after = node_script_after;

        lines[inserted_name] = result_object;
    }

    for (auto &[at, expected_next] : next_references_to_check) {
        sol::optional maybe_next = lines[expected_next];

        if (!maybe_next) {
            spdlog::warn("{} wants {} as next, but it does not exist", at, expected_next);
        }
    }
}

sol::table StoryParser::load_mods(sol::state &lua) {
  namespace fs = std::filesystem;

  auto result = lua.create_table();

  auto mods_path = fs::path("resources/mods");

  if (!fs::exists(mods_path)) return result;

  for (const auto &dir : fs::directory_iterator(mods_path)) {
    if (!dir.is_directory()) continue;

    auto name = dir.path().filename();
    const auto name_string = name.string();

    auto mod_yml = dir.path() / "mod.yml";
    if (!fs::exists(mod_yml)) {
      spdlog::warn("Mod {} is missing mod.yml, skipping", name_string);

      continue;
    }

    YAML::Node root_node = YAML::LoadFile(mod_yml.string());

    ModData mod_data = {
        .name = name_string,
        .lua_files = lua.create_table(),
        .lines = lua.create_table(),
        .parser = StoryParser(mod_data.lines, lua),
    };

    if (root_node["entrypoint"]) {
        auto entrypoint = root_node["entrypoint"].as<std::string>();
        auto last_slash = entrypoint.rfind('/');
        if (last_slash == std::string::npos) {
            spdlog::warn("No separator found in {} mod entrypoint, skipping", name_string);

            continue;
        }

        auto entrypoint_file = entrypoint.substr(0, last_slash);
        auto entrypoint_line = entrypoint.substr(last_slash + 1, entrypoint.size());

        mod_data.first_line = fmt::format("{}/{}", entrypoint_file, entrypoint_line);
        mod_data.parser.parse(entrypoint_file, mods_path / name);
    } else if (root_node["entrypoint_walking"]) {
        mod_data.first_room = root_node["entrypoint_walking"].as<std::string>();
    } else {
        spdlog::error("Neither entrypoint, nor entrypoint_walking found for mod {}, skipping", name_string);

        continue;
    }


    if (auto pretty_name_node = root_node["pretty_name"]; pretty_name_node)
      mod_data.pretty_name = pretty_name_node.as<std::string>();

    if (auto lua_node = root_node["lua"]; lua_node) {
      // Try to convert it to a lua map
      if (lua_node.IsMap()) {
        std::function<void(const YAML::Node&, sol::table &)> traverse_into_namespace = [&](const YAML::Node nm, sol::table into) {
          for (auto pair : nm) {
            auto key = pair.first.as<std::string>();
            auto value = pair.second;

            if (value.IsMap()) {
              auto table = lua.create_table();
              into[key] = table;
              traverse_into_namespace(value, table);
            } else {
              into[key] = value.as<std::string>();
            }
          }
        };

        traverse_into_namespace(lua_node, mod_data.lua_files);
      } else {
        spdlog::warn(
          "The lua key in mod.yml of {} was expected to be a sequence of namespaces and names to file names, skipping",
          name_string
        );

        continue;
      }
    }

    result.add(mod_data);

    spdlog::info("Loaded mod {}", name_string);
  }

  return result;
}
