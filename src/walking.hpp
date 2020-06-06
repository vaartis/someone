#pragma once

#include <map>
#include "lua_module_env.hpp"

class WalkingEnv : public LuaModuleEnv {
private:
    sol::protected_function update_f, draw_f, draw_overlay_f, add_event_f, room_shaders_f;

    std::vector<std::string> need_screen_size;
    std::map<std::string, sf::Shader> shaders;

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

        {
            const auto &[pair, _] =
                shaders.emplace(std::piecewise_construct, std::forward_as_tuple("room_darker"), std::forward_as_tuple());
            pair->second.loadFromFile("resources/shaders/room_darker.frag", sf::Shader::Fragment);
        }

        {
            const auto &[pair, _] =
                shaders.emplace(std::piecewise_construct, std::forward_as_tuple("circle_light"), std::forward_as_tuple());
            pair->second.loadFromFile("resources/shaders/circle_light.frag", sf::Shader::Fragment);
            need_screen_size.push_back("circle_light");
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

        auto shaders_data = call_or_throw(room_shaders_f).get<std::map<std::string, std::map<std::string, sol::object>>>();

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
                auto shader_iter = shaders.find(shader_name);
                if (shader_iter == shaders.end()) {
                    continue;
                }

                auto &shader = shader_iter->second;

                if (std::find(need_screen_size.begin(), need_screen_size.end(), shader_name) != need_screen_size.end()) {
                    shader.setUniform("screenSize", sf::Vector2f(target_window.getSize()));
                }

                bool enabled = true;

                for (auto &param_data : shader_data) {
                    auto [name, value] = param_data;

                    if (name == "enabled") {
                        if (value.is<sol::protected_function>()) {
                            // If "enabled" is a function, call it and convert result to bool
                            auto result_function = value.as<sol::protected_function>();
                            enabled = bool(call_or_throw(result_function));
                        } else {
                            // Otherwise just convert to bool
                            enabled = bool(value);
                        }

                        // If the shader is evaluated as enabled, skip the paramter
                        // and go to the next one, if it's disabled, stop processing paramters
                        // and don't run the shader
                        if (enabled) continue; else break;
                    }

                    // Skip the n field
                    if (name == "n") continue;

                    if (value.is<float>()) {
                        shader.setUniform(name, value.as<float>());

                        continue;
                    } else if (value.is<std::vector<int32_t>>()) {
                        auto vec = value.as<std::vector<int32_t>>();
                        if (vec.size() == 2) {
                            shader.setUniform(name, sf::Vector2f(vec[0], vec[1]));

                            continue;
                        }
                    }

                    spdlog::error("Parameter {} of unknown type in shader {}", name, shader_name);
                }

                if (enabled) target_window.draw(shaders_sprite, &shader);
            }
        }
    }

#ifdef SOMEONE_TESTING
    void run_tests() {
        lua[sol::create_if_nil]["TESTING"]["WALKING"] = lua.create_table_with(
            "update", [&](float dt) { update(dt); },
            "draw", [&]() { draw(); },
            "add_event", [&](sf::Event event) { add_event(event); }
        );

        // This runs the tests
        lua.script("require('test.walking')");
    }
#endif
};
