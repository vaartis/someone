#pragma once

#include "story_parser.hpp"
#include "lua_module_env.hpp"

class TerminalEnv : public LuaModuleEnv {
private:
    sol::table lines;

    sol::protected_function set_lines_f, set_first_line_f, draw_f, process_event_f, update_event_timer_f,
        debug_menu_f, load_mod_f;
public:
    StoryParser parser;

    void set_lines() {
        call_or_throw(set_lines_f, lines);
    }

    void set_first_line(std::string &&line) {
        call_or_throw(set_first_line_f, line);
    }
    void set_first_line(sol::table line) {
        call_or_throw(set_first_line_f, line);
    }

    void draw(float dt) {
        call_or_throw(draw_f, dt);
    }

    void process_event(sf::Event &event) {
        call_or_throw(process_event_f, event);
    }

    void update_event_timer(float dt) {
        call_or_throw(update_event_timer_f, dt);
    }

    void debug_menu() {
        call_or_throw(debug_menu_f);
    }

    void load_mod(std::string &name) {
        sol::object mod_line = call_or_throw(load_mod_f, name);

        set_first_line(mod_line);
    }

    TerminalEnv(sol::state &lua) : lines(lua.create_table()), LuaModuleEnv(lua), parser(StoryParser(lines, lua)) {
        // This both defines a global for the module and returns it
        module = lua.require_script("TerminalModule", "return require('terminal')");

        set_lines_f = module["set_native_lines"];
        set_first_line_f = module["set_first_line_on_screen"];
        draw_f = module["draw"];
        process_event_f = module["process_event"];
        update_event_timer_f = module["update_event_timer"];
        debug_menu_f = module["debug_menu"];

        load_mod_f = lua.script("return require('terminal.instance_menu').InstanceMenuLine.load_mod");

        // Parse the lines from the prologue file and going forward from it
        parser.parse("day1/prologue");
        parser.parse("instances/menu");
        parser.parse("save_load/save_load");

        // Add the lines from the loaded file
        set_lines();
        // After the lines are added, set up the first line on screen
        set_first_line("day1/prologue/1");
    }
};
