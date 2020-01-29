#pragma once

#include "lua_module_env.hpp"

class WalkingEnv : public LuaModuleEnv {
private:
    sol::protected_function update_f, draw_f, add_event_f;

    sf::Shader dark_room_shader;
public:
    WalkingEnv(sol::state &lua) : LuaModuleEnv(lua) {
        // This both defines a global for the module and returns it
        module = lua.require_script("WalkingModule", "return require('walking')");

        update_f = module["update"];
        draw_f = module["draw"];
        add_event_f = module["add_event"];

        dark_room_shader.loadFromFile("resources/shaders/room_darker.frag", sf::Shader::Fragment);
    }

    void update(float dt) {
        call_or_throw(update_f, dt);
    }

    void draw() {
        call_or_throw(draw_f);
    }

    void add_event(sf::Event event) {
        call_or_throw(add_event_f, event);
    }

    void draw_target_to_window(sf::RenderWindow &target_window, sf::Sprite &final_sprite) {
        dark_room_shader.setUniform("screenSize", sf::Vector2f(target_window.getSize()));
        dark_room_shader.setUniform("monitorTop", sf::Vector2f(237, 708));
        dark_room_shader.setUniform("monitorBottom", sf::Vector2f(237, 765));
        dark_room_shader.setUniform("ambientLightLevel", 0.4f);
        dark_room_shader.setUniform("currentTexture", sf::Shader::CurrentTexture);

        target_window.draw(final_sprite, &dark_room_shader);
    }
};
