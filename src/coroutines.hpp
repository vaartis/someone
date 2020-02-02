#pragma once

#include "lua_module_env.hpp"

class CoroutinesEnv : public LuaModuleEnv {
private:
    sol::protected_function run_f;
public:
    void run() {
        call_or_throw(run_f);
    }

    CoroutinesEnv(sol::state &lua) : LuaModuleEnv(lua) {
        // This both defines a global for the module and returns it
        module = lua.require_script("CoroutinesModule", "return require('coroutines')");

        run_f = module["run"];
    }
};
