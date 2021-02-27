#include "sol/sol.hpp"

void run_lua_tests(sol::state &lua) {
    // Make busted thing it's run by a runner and find tests on its own
    lua[sol::create_if_nil]["arg"] = sol::as_table(
        std::vector<std::string> {
            "-p", ".*%_test.moon$", "."
        }
    );

    // This runs the tests
    lua.script("require('busted.runner')({ standalone = false })");
}
