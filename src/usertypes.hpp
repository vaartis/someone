#pragma once

#include "fonts.hpp"

void register_sfml_usertypes(sol::state &lua, StaticFonts &fonts);
void register_imgui_usertypes(sol::state &lua);

void register_usertypes(sol::state &lua, StaticFonts &fonts);
