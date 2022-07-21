#include <filesystem>

#include "SFML/Window/Window.hpp"
#include "SFML/System/Vector2.hpp"
#include "SFML/System/Clock.hpp"
#include "SFML/Graphics/Shader.hpp"

#include "imgui.h"
#include "backends/imgui_impl_sdl.h"
#include "backends/imgui_impl_opengl3.h"

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

#ifdef SOMEONE_EMSCRIPTEN
#include <emscripten.h>
#endif

enum class CurrentState {
    Terminal,
    Walking
};

struct MainLoopContext {
    sf::Clock clock;
    CurrentState &current_state;
    sf::RenderWindow &window;

    bool should_exit = false;
    bool debug_menu = false;

    int current_window_size = 0;

    sf::RenderTexture &target;

    WalkingEnv &walking_env;
    TerminalEnv &terminal_env;
    CoroutinesEnv &coroutines_env;
};

constexpr std::pair<int, int> initial_size(1280, 1024);
const std::vector<sf::Vector2u> window_sizes = {
    { initial_size.first, initial_size.second },
    { initial_size.first / 2, initial_size.second / 2},
    { initial_size.first * 2, initial_size.second * 2}
};

void main_loop(void *ctx_) {
    auto &ctx = *(MainLoopContext *)ctx_;

    auto dt_time = ctx.clock.restart();
    auto dt = dt_time.asSeconds();

    sf::Color clear_color;
    switch (ctx.current_state) {
    case CurrentState::Terminal:
        clear_color = sf::Color::White;
        break;
    case CurrentState::Walking:
        clear_color = sf::Color::Black;
    }
    ctx.target.clear(clear_color);

    sf::Event event;
    while (ctx.window.pollEvent(event)) {
#ifdef SOMEONE_APPLE
        // Track keyboard manually
        someone::KeypressTracker::processEvent(event);
#endif

        switch (event.type) {
        case sf::Event::Closed:
            ctx.window.close();
            ctx.should_exit = true;

            return;
        case sf::Event::KeyReleased: {
            switch (event.key.code) {
            case sf::Keyboard::Tilde:
                // Activate debug menu on ~
                ctx.debug_menu = !ctx.debug_menu;
                break;
#ifndef SOMEONE_EMSCRIPTEN
            case sf::Keyboard::F1:
                if (ctx.current_window_size + 1 >= window_sizes.size()) {
                    ctx.current_window_size = 0;
                } else {
                    ctx.current_window_size++;
                }
                ctx.window.setSize(window_sizes[ctx.current_window_size]);

                break;
#endif
            default:
                break;
            }

            break;
        }

        default: break;
        }

        if (!ctx.debug_menu) {
            switch (ctx.current_state) {
            case CurrentState::Terminal:
                ctx.terminal_env.process_event(event);
                break;
            case CurrentState::Walking:
                ctx.walking_env.add_event(event);
                break;
            }
        }
        ImGui_ImplSDL2_ProcessEvent(&event.sdlEvent);
    }

    ctx.window.clear();

    switch (ctx.current_state) {
    case CurrentState::Terminal:
        ctx.terminal_env.update_event_timer(dt);
        ctx.terminal_env.draw(dt);

        // Don't draw to the screen yet, will be drawn after coroutines run

        break;
    case CurrentState::Walking:
        ctx.walking_env.update(dt);

        // Run all the drawing in lua and then draw it to the screen
        ctx.walking_env.draw();
        ctx.walking_env.draw_target_to_window(ctx.window, ctx.target);

        // Now clear the target and draw the overlay
        ctx.target.clear(sf::Color::Transparent);
        ctx.walking_env.draw_overlay();

        // Don't draw yet, wait for coroutines to run,
        // then everything will be drawn

        break;
    }

    // After everything has been drawn and processed, run the coroutines
    ctx.coroutines_env.run(dt);

    if (ctx.current_state == CurrentState::Walking) {
        // Clear the event store as the very last thing, after the coroutines run
        ctx.walking_env.clear_event_store();
    }

    // Draw what hasn't been drawn yet
    ctx.window.draw(ctx.target);

    ctx.target.display();

    ImGui_ImplOpenGL3_NewFrame();
    ImGui_ImplSDL2_NewFrame();
    ImGui::NewFrame();

    switch (ctx.current_state) {
    case CurrentState::Walking:
        ctx.walking_env.draw_imgui();
        break;
    default: break;
    }

    if (ctx.debug_menu) {
        ImGui::Begin("Debug menu", nullptr, ImGuiWindowFlags_AlwaysAutoResize);

        switch (ctx.current_state) {
        case CurrentState::Terminal:
            ctx.terminal_env.debug_menu();
            break;
        case CurrentState::Walking:
            ctx.walking_env.debug_menu();
            break;
        }
        ImGui::End();
    }

    ImGui::Render();
    ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());

    ctx.window.display();
}

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
    sf::RenderWindow window(sf::VideoMode(default_size.x, default_size.y), "Someone");

    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    // Disable the ini file
    io.IniFilename = nullptr;

    ImGui_ImplSDL2_InitForOpenGL(window.window, window.target->context->context);
    ImGui_ImplOpenGL3_Init(nullptr);

    sf::RenderTexture target;
    {
        auto winSize = window.getSize();
        target.create(winSize.x, winSize.y);
    }

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

    auto current_state = CurrentState::Walking;

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
        "isalpha", [](const std::string &num) { return std::all_of(num.begin(), num.end(), [](int ch) { return std::isalpha(ch); }); },
        "iscntrl", [](const std::string &num) { return std::all_of(num.begin(), num.end(), [](int ch) { return std::iscntrl(ch); }); },
        "loaded_mods", loaded_mods,
        "synchronize_saves", []() {
#if SOMEONE_EMSCRIPTEN
            EM_ASM(FS.syncfs(false, (err) => { if (err) console.error("Could not save to IndexedDB") }));
#endif
        }
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

    MainLoopContext context = {
        .current_state = current_state,
        .window = window,

        .target = target,

        .walking_env = walking_env,
        .terminal_env = terminal_env,
        .coroutines_env = coroutines_env
    };


#ifndef SOMEONE_EMSCRIPTEN
    while(true) {
        main_loop(&context);
        if (context.should_exit)
            break;
    }
#else
    EM_ASM(
        FS.mkdir("saves");
        FS.mount(IDBFS, {}, "saves");

        // Synchronize any files that are in IndexedDB
        FS.syncfs(true, (err) => { if (err) console.error("Could not load from IndexedDB") });
    );

    emscripten_set_main_loop_arg(&main_loop, &context, 0, true);
#endif

    ImGui_ImplOpenGL3_Shutdown();
    ImGui_ImplSDL2_Shutdown();
    ImGui::DestroyContext();
}
