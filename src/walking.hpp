#pragma once

#include <map>

#include "SFML/Graphics.hpp"

#include "logger.hpp"
#include "lua_module_env.hpp"

class WalkingEnv : public LuaModuleEnv {
private:
    sol::protected_function update_f, draw_f, draw_overlay_f, add_event_f, room_shaders_f, debug_menu_f,
        clear_event_store_f;

    sol::table shaders;

    sf::RenderTexture shaders_texture;
    sf::Sprite shaders_sprite;
public:
    WalkingEnv(sol::state &lua) : LuaModuleEnv(lua) {
        // This both defines a global for the module and returns it
        module = lua.require_script("WalkingModule", "return require('walking')");

        update_f = module["update"];
        draw_f = module["draw"];
        draw_overlay_f = module["draw_overlay"];
        add_event_f = module["add_event"];
        room_shaders_f = module["room_shaders"];
        debug_menu_f = module["debug_menu"];
        clear_event_store_f = module["clear_event_store"];

        shaders = lua.create_table();
        lua["GLOBAL"]["available_shaders"] = shaders;

        {
            auto shader = std::make_unique<sf::Shader>();
            shader->loadFromFile("resources/shaders/room_darker.frag", sf::Shader::Fragment);
            shaders["room_darker"] = lua.create_table_with(
                "shader", std::move(shader),
                "declared_args", lua.create_table_with(
                    "n", "integer",
                    "ambientLightLevel", "float"
                )
            );
        }

        {
            auto shader = std::make_unique<sf::Shader>();
            shader->loadFromFile("resources/shaders/circle_light.frag", sf::Shader::Fragment);
            shaders["circle_light"] = lua.create_table_with(
                "shader", std::move(shader),
                "declared_args", lua.create_table_with(
                    "n", "integer",
                    "brightness", "float",
                    "point", "vec2i"
                ),
                "need_screen_size", true
            );
        }
    }

    void update(float dt) {
        call_or_throw(update_f, dt);
    }

    void draw() {
        call_or_throw(draw_f);
    }

    void draw_overlay() {
        call_or_throw(draw_overlay_f);
    }

    void add_event(sf::Event &event) {
        call_or_throw(
            add_event_f,
            // For some reason, copying the event makes the values break after a bit in lua, but copying and
            // allocating a pointer to that works fine
            std::make_shared<sf::Event>(event)
        );
    }

    void draw_target_to_window(sf::RenderWindow &target_window, sf::Sprite &final_sprite) {
        // First, draw the actual sprite
        target_window.draw(final_sprite);

        // If the texture is not the same size as the window, recreate it.
        // This will also create it the first time it's used and is not yet initialized;
        auto screen_size = target_window.getSize();
        if (shaders_texture.getSize() != screen_size) {
            shaders_texture.create(screen_size.x, screen_size.y);
            shaders_sprite.setTexture(shaders_texture.getTexture());
        }
        shaders_texture.clear(sf::Color::Transparent);

        auto shaders_data_obj = call_or_throw(room_shaders_f);
        auto shaders_data = shaders_data_obj.get<std::map<std::string, std::map<std::string, sol::object>>>();

        // Sort the shaders based on the N value, lower going first
        std::vector<std::pair<std::string, std::map<std::string, sol::object>>> sorted_shaders;
        std::copy(shaders_data.begin(), shaders_data.end(), std::back_inserter(sorted_shaders));
        std::sort(
            sorted_shaders.begin(),
            sorted_shaders.end(),
            [](auto &lhs, auto &rhs) {
                return lhs.second["n"].template as<int32_t>() < rhs.second["n"].template as<int32_t>();
            }
        );

        // Then, draw the shaders for the room over the sprite, blending them together
        if (sorted_shaders.size() > 0) {
            for (auto &[shader_name, shader_data] : sorted_shaders) {
                sol::optional<sol::table> shader_tbl_ = shaders[shader_name];
                if (!shader_tbl_) {
                    continue;
                }

                auto shader_tbl = *shader_tbl_;
                std::unique_ptr<sf::Shader> &shader = shader_tbl["shader"];

                if (sol::optional<bool> need_screen_size = shader_tbl["need_screen_size"];
                    need_screen_size.has_value() && *need_screen_size) {
                    shader->setUniform("screenSize", sf::Vector2f(target_window.getSize()));
                }

                bool enabled = true;
                sol::object enabled_lua = shaders_data_obj.get<sol::table>()[shader_name][sol::metatable_key]["enabled_compiled"];
                if (enabled_lua.is<sol::protected_function>()) {
                    // If "enabled" is a function, call it and convert result to bool
                    auto result_function = enabled_lua.as<sol::protected_function>();
                    enabled = bool(call_or_throw(result_function));
                } else {
                    // Otherwise just convert to bool
                    enabled = enabled_lua.as<bool>();
                }

                // If the shader is evaluated as enabled, skip the paramter
                // and go to the next one, if it's disabled, stop processing and don't run the shader
                if (!enabled) continue;

                for (auto &param_data : shader_data) {
                    auto [name, value] = param_data;

                    // Skip the n and enabled field
                    if (name == "n" || name == "enabled") continue;

                    if (value.is<float>()) {
                        shader->setUniform(name, value.as<float>());

                        continue;
                    } else if (value.is<std::vector<int32_t>>()) {
                        auto vec = value.as<std::vector<int32_t>>();
                        if (vec.size() == 2) {
                            shader->setUniform(name, sf::Vector2f(vec[0], vec[1]));

                            continue;
                        }
                    }

                    spdlog::error("Parameter {} of unknown type in shader {}", name, shader_name);
                }

                if (enabled) target_window.draw(shaders_sprite, shader.get());
            }
        }
    }

    void debug_menu() {
        call_or_throw(debug_menu_f);
    }

    void clear_event_store() {
        call_or_throw(clear_event_store_f);
    }
};
