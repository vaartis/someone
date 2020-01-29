#pragma once

class LuaModuleEnv {
protected:
    sol::state &lua;
    sol::table module;

    LuaModuleEnv(sol::state &lua) : lua(lua) {}

    template<typename... T>
    decltype(auto) call_or_throw(sol::protected_function &fnc, T... args) {
        auto res = fnc(args...);
        if (!res.valid())
            throw sol::error(res);
    }
};
