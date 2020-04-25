#pragma once

#include "story_parser.hpp"
#include "lua_module_env.hpp"

class TerminalEnv : public LuaModuleEnv {
private:
    StoryParser::lines_type lines;

    sol::protected_function add_lines_f, set_first_line_f, draw_f, process_event_f, update_event_timer_f;
public:
    void add_lines(StoryParser::lines_type &lines) {
        call_or_throw(add_lines_f, lines);
    }

    void set_first_line(std::string &&line) {
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

    TerminalEnv(sol::state &lua) : LuaModuleEnv(lua) {
        // This both defines a global for the module and returns it
        module = lua.require_script("TerminalModule", "return require('terminal')");

        add_lines_f = module["add_native_lines"];
        set_first_line_f = module["set_first_line_on_screen"];
        draw_f = module["draw"];
        process_event_f = module["process_event"];
        update_event_timer_f = module["update_event_timer"];

        // Parse the lines from the prologue file and going forward from it
        StoryParser::parse(lines, "day1/prologue", lua);
        // Add the lines from the loaded file
        add_lines(lines);
        // After the lines are added, set up the first line on screen
        set_first_line("day1/prologue/1");
    }
};
