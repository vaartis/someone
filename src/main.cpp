#include <filesystem>

#include <SFML/Graphics.hpp>
#include <SFML/Window/Event.hpp>
#include <SFML/System/Clock.hpp>

#include "imgui.h"
#include "imgui-SFML.h"

#include "sol/sol.hpp"

#include "args.hxx"

#include "logger.hpp"
#include "string_utils.hpp"
#include "fonts.hpp"
#include "story_parser.hpp"
#include "usertypes.hpp"

#include "terminal.hpp"
#include "walking.hpp"
#include "coroutines.hpp"

#ifdef SOMEONE_TESTING
#include "lua_testing.hpp"
#endif

#ifdef SOMEONE_APPLE
#include "keyboard.hpp"
#endif

enum class CurrentState {
    Terminal,
    Walking
};

int main(int argc, char **argv) {
    args::ArgumentParser arg_parser("Someone - engine options");
    arg_parser.helpParams.width = 100;
    arg_parser.helpParams.showProglineOptions = false;

    args::HelpFlag help(arg_parser, "help", "Display this help message", {'h', "help"});
    args::ValueFlag<std::string> load_mod(arg_parser, "mod name", "Start a mod instead of the main game", {'l', "load-mod"});
    try {
        arg_parser.ParseCLI(argc, argv);
    } catch (const args::Help&) {
        std::cout << arg_parser;
        return 0;
    } catch (const args::Error &e) {
        std::cerr << e.what() << std::endl;
        std::cerr << arg_parser;

        return 1;
    }

    // Change cwd to where the program is
    std::filesystem::current_path(std::filesystem::path(argv[0]).parent_path());

    #ifndef NDEBUG
    spdlog::set_level(spdlog::level::debug);
    #endif

    constexpr std::pair<int, int> initial_size(1280, 1024);
    const std::vector<sf::Vector2u> window_sizes = {
        { initial_size.first, initial_size.second },
        { initial_size.first / 2, initial_size.second / 2},
        { initial_size.first * 2, initial_size.second * 2}
    };
    uint8_t current_window_size = 0;

    const auto &default_size = window_sizes[current_window_size];
    sf::RenderWindow window(sf::VideoMode(default_size.x, default_size.y), "Someone", sf::Style::Titlebar | sf::Style::Close);
    window.setFramerateLimit(60);
    window.setPosition(sf::Vector2i(0, 0));

    ImGui::SFML::Init(window);
    ImGuiIO& io = ImGui::GetIO();
    // Disable the ini file
    io.IniFilename = nullptr;

    sf::RenderTexture target;
    {
        auto winSize = window.getSize();
        target.create(winSize.x, winSize.y);
    }
    auto &targetTexture = target.getTexture();
    sf::Sprite targetSprite(targetTexture);

    StaticFonts static_fonts;

    sol::state lua;
    lua.open_libraries(sol::lib::base, sol::lib::table, sol::lib::string, sol::lib::package,
                       sol::lib::coroutine, sol::lib::math, sol::lib::debug, sol::lib::os, sol::lib::io,
                       sol::lib::utf8);

    // Setup the lua path to see luarocks packages
    auto package_path = std::filesystem::path("resources") / "lua" / "share" / "lua" / SOMEONE_LUA_VERSION / "?.lua;";
    package_path += std::filesystem::path("resources") / "lua" / "share" / "lua" / SOMEONE_LUA_VERSION / "?" / "init.lua;";
    lua["package"]["path"] = std::string(package_path.string()) + std::string(lua["package"]["path"]);

    auto package_cpath = std::filesystem::path("resources") / "lua" / "lib" / "lua" / SOMEONE_LUA_VERSION / "?." SOMEONE_LIB_EXT ";";
    lua["package"]["cpath"] = std::string(package_cpath.string()) + std::string(lua["package"]["cpath"]);

    #ifdef SOMEONE_TESTING
    // Has to be included as the first thing to cover everything
    lua.script("require('luacov')");
    // Tests use moonscript
    lua.script("require('moonscript')");
    #endif

    register_usertypes(lua, static_fonts);

    CoroutinesEnv coroutines_env(lua);
    TerminalEnv terminal_env(lua);

    auto loaded_mods = terminal_env.parser.load_mods(lua);

    auto current_state = CurrentState::Terminal;

    auto current_state_type = lua.new_enum(
        "CurrentState",
        "Terminal", CurrentState::Terminal,
        "Walking", CurrentState::Walking
    );
    lua["GLOBAL"] = lua.create_table_with(
        "drawing_target", &target,
        "window", &window,
        "set_current_state", [&](CurrentState new_state) { current_state = new_state; },
        "get_current_state", [&]() { return current_state; },
        // Apparently lua doesn't have a good equivalent
        "isalpha", [](int num) { return std::isalpha(num) != 0; },
        "iscntrl", [](int num) { return std::iscntrl(num) != 0; },
        "loaded_mods", loaded_mods
    );

    // Initialize the walking env after GLOBAL, because it needs to put things in there
    WalkingEnv walking_env(lua);

#ifndef NDEBUG
    terminal_env.parser.total_wordcount();
#endif

#ifdef SOMEONE_TESTING
    run_lua_tests(lua);

    return 0;
#endif

    if (load_mod) {
        auto mod_name = args::get(load_mod);

        std::optional<ModData *> loaded_mod;
        for (auto &[_k, v_] : loaded_mods) {
            auto v = v_.as<ModData *>();
            if (v->name == mod_name)
                loaded_mod = v;
        }
        if (!loaded_mod) {
            spdlog::error("Mod {} not found, exiting", mod_name);
            return 1;
        }

        auto first_room = loaded_mod.value()->first_room;
        if (first_room != "") {
            current_state = CurrentState::Walking;
        }

        // Load the mod now, because state needs to be set to walking (if needed) before that
        terminal_env.load_mod(mod_name);

        if (first_room != "") {
            walking_env.load_room(first_room, true);
        }
    }

    bool debug_menu = false;

    sf::Clock clock;
    while (true) {
        auto dt_time = clock.restart();
        auto dt = dt_time.asSeconds();

        sf::Color clear_color;
        switch (current_state) {
        case CurrentState::Terminal:
            clear_color = sf::Color::White;
            break;
        case CurrentState::Walking:
            clear_color = sf::Color::Black;
        }
        target.clear(clear_color);

        sf::Event event;
        while (window.pollEvent(event)) {
#ifdef SOMEONE_APPLE
            // Track keyboard manually
            someone::KeypressTracker::processEvent(event);
#endif

            switch (event.type) {
            case sf::Event::Closed:
                window.close();

                return 0;
            case sf::Event::KeyReleased: {
                switch (event.key.code) {
                case sf::Keyboard::Tilde:
                    // Activate debug menu on ~
                    debug_menu = !debug_menu;
                    break;
                case sf::Keyboard::F1:
                    if (current_window_size + 1 >= window_sizes.size()) {
                        current_window_size = 0;
                    } else {
                        current_window_size++;
                    }
                    window.setSize(window_sizes[current_window_size]);

                    break;
                default:
                    break;
                }

                break;
            }

            default: break;
            }

            if (!debug_menu) {
                switch (current_state) {
                case CurrentState::Terminal:
                    terminal_env.process_event(event);
                    break;
                case CurrentState::Walking:
                    walking_env.add_event(event);
                    break;
                }
            } else {
                ImGui::SFML::ProcessEvent(event);
            }
        }

        window.clear();

        switch (current_state) {
        case CurrentState::Terminal:
            terminal_env.update_event_timer(dt);
            terminal_env.draw(dt);

            // Don't draw to the screen yet, will be drawn after coroutines run

            break;
        case CurrentState::Walking:
            walking_env.update(dt);

            // Run all the drawing in lua and then draw it to the screen
            walking_env.draw();
            walking_env.draw_target_to_window(window, targetSprite);

            // Now clear the target and draw the overlay
            target.clear(sf::Color::Transparent);
            walking_env.draw_overlay();

            // Don't draw yet, wait for coroutines to run,
            // then everything will be drawn

            break;
        }

        // After everything has been drawn and processed, run the coroutines
        coroutines_env.run(dt);

        if (current_state == CurrentState::Walking) {
            // Clear the event store as the very last thing, after the coroutines run
            walking_env.clear_event_store();
        }

        // Draw what hasn't been drawn yet
        window.draw(targetSprite);

        target.display();

        if (debug_menu) {
            ImGui::SFML::Update(window, dt_time);

            ImGui::Begin("Debug menu", nullptr, ImGuiWindowFlags_AlwaysAutoResize);

            switch (current_state) {
            case CurrentState::Terminal:
                terminal_env.debug_menu();
                break;
            case CurrentState::Walking:
                walking_env.debug_menu();
                break;
            }

            ImGui::End();

            ImGui::SFML::Render(window);
        }
        window.display();
    }
}
