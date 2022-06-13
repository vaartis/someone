#pragma once

#include "sol/sol.hpp"

class LuaModuleEnv {
protected:
    sol::state &lua;
    sol::table module;

    LuaModuleEnv(sol::state &lua) : lua(lua) {}

    template<typename... T>
    decltype(auto) call_or_throw(sol::protected_function &fnc, T... args) {
        auto res = fnc(args...);
        if (!res.valid()) {
            auto err = sol::error(res);

#ifdef SOMEONE_EMSCRIPTEN
            spdlog::error("{}", err.what());;
#endif

            throw err;
        }
        return res;
    }
};
