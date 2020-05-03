#pragma once

#include <map>
#include "lua_module_env.hpp"

class WalkingEnv : public LuaModuleEnv {
private:
    sol::protected_function update_f, draw_f, add_event_f, room_shader_name_f;

    std::vector<std::string> need_screen_size;
    std::map<std::string, sf::Shader> shaders;

public:
    WalkingEnv(sol::state &lua) : LuaModuleEnv(lua) {
        // This both defines a global for the module and returns it
        module = lua.require_script("WalkingModule", "return require('walking')");

        update_f = module["update"];
        draw_f = module["draw"];
        add_event_f = module["add_event"];
        room_shader_name_f = module["room_shader_name"];

        const float ambient_light_level = 0.4;

        {
            const auto &[pair, _] =
                shaders.emplace(std::piecewise_construct, std::forward_as_tuple("room_darker"), std::forward_as_tuple());
            auto &shader = pair->second;
            shader.loadFromFile("resources/shaders/room_darker.frag", sf::Shader::Fragment);
            shader.setUniform("ambientLightLevel", ambient_light_level);
        }

        {
            const auto &[pair, _] =
                shaders.emplace(std::piecewise_construct, std::forward_as_tuple("screen_room_darker"), std::forward_as_tuple());
            auto &shader = pair->second;
            shader.loadFromFile("resources/shaders/screen_room_darker.frag", sf::Shader::Fragment);
            shader.setUniform("monitorTop", sf::Vector2f(237, 708));
            shader.setUniform("monitorBottom", sf::Vector2f(237, 765));
            shader.setUniform("ambientLightLevel", ambient_light_level);
            need_screen_size.push_back("screen_room_darker");
        }
    }

    void update(float dt) {
        call_or_throw(update_f, dt);
    }

    void draw() {
        call_or_throw(draw_f);
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
        auto name = call_or_throw(room_shader_name_f).get<std::optional<std::string>>();

        if (name) {
            auto &shader = shaders[*name];

            if (std::find(need_screen_size.begin(), need_screen_size.end(), name) != need_screen_size.end()) {
                shader.setUniform("screenSize", sf::Vector2f(target_window.getSize()));
            }

            shader.setUniform("currentTexture", sf::Shader::CurrentTexture);

            target_window.draw(final_sprite, &shader);
        } else {
            target_window.draw(final_sprite);
        }
    }
};
