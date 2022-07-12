#pragma once

#include <numeric>

#include "sol/sol.hpp"

#include "fonts.hpp"

void register_sfml_usertypes(sol::state &lua, StaticFonts &fonts);
void register_imgui_usertypes(sol::state &lua);

void register_usertypes(sol::state &lua, StaticFonts &fonts);

#ifdef SOMEONE_NETWORKING
void register_networking_usertypes(sol::state &lua);
#endif
