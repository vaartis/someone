#pragma once

#include <SFML/Graphics/RenderTarget.hpp>
#include <SFML/Graphics/Texture.hpp>
#include <SFML/Graphics/Transformable.hpp>
#include <SFML/Graphics/Drawable.hpp>

#include <fmt/format.h>

#include "fonts.hpp"
#include "string_utils.hpp"
#include "lines/shared.hpp"

// Custom to_string implementations for lua usage

namespace sf {

template<typename T>
std::string to_string(const sf::Vector2<T> &vec) {
    return fmt::format("Vector2({}, {})", vec.x, vec.y);
}

} // namespace sf

namespace {

template<typename T>
decltype(auto) register_vector2(sol::state &lua, std::string name) {
    return lua.new_usertype<sf::Vector2<T>>(
        name, sol::constructors<sf::Vector2<T>(T, T)>(),
        "x", &sf::Vector2<T>::x,
        "y", &sf::Vector2<T>::y
    );
}

template<typename T>
decltype(auto) register_rect(sol::state &lua, std::string name) {
    return lua.new_usertype<sf::Rect<T>>(
        name, sol::constructors<sf::Rect<T>(T, T, T, T)>(),
        "left", &sf::Rect<T>::left,
        "top", &sf::Rect<T>::top,
        "width", &sf::Rect<T>::width,
        "height", &sf::Rect<T>::height
    );
}
} // namespace

void register_usertypes(sol::state &lua) {
    auto vec2f_type = register_vector2<float>(lua, "Vector2f");
    auto vec2u_type = register_vector2<unsigned int>(lua, "Vector2u");

    auto float_rect_type = register_rect<float>(lua, "FloatRect");

    auto tf_type = lua.new_usertype<sf::Transformable>(
        "Transformable", sol::no_constructor,
        "position", sol::property(
            &sf::Transformable::getPosition,
            sol::resolve<void(const sf::Vector2f&)>(&sf::Transformable::setPosition)
        )
    );

    auto render_target_type = lua.new_usertype<sf::RenderTarget>(
        "RenderTarget", sol::no_constructor,
        "draw", [](sf::RenderTarget &target, const sf::Drawable &drawable) { target.draw(drawable); }
    );
    auto render_states_type = lua.new_usertype<sf::RenderStates>("RenderStates");

    auto render_texture_type = lua.new_usertype<sf::RenderTexture>(
        "RenderTexture", sol::no_constructor,
        sol::base_classes, sol::bases<sf::RenderTarget>(),
        "size", sol::property(&sf::RenderTexture::getSize)
    );

    auto drawable_type = lua.new_usertype<sf::Drawable>("Drawable");

    auto font_type = lua.new_usertype<sf::Font>("Font", sol::no_constructor);
    auto static_fonts_type = lua.new_usertype<StaticFonts>(
        "StaticFonts", sol::no_constructor,
        "main_font", sol::var(std::ref(StaticFonts::main_font)),
        "font_size", sol::var(std::ref(StaticFonts::font_size))
    );

    auto string_utils_type = lua.new_usertype<StringUtils>(
        "StringUtils", sol::no_constructor,
        "wrap_words_at", &StringUtils::wrap_words_at
    );

    auto text_type = lua.new_usertype<sf::Text>(
        "Text", sol::constructors<sf::Text(const std::string&, const sf::Font&, unsigned int)>(),
        sol::base_classes, sol::bases<sf::Drawable, sf::Transformable>(),
        "global_bounds", sol::property(&sf::Text::getGlobalBounds),
        "fill_color", sol::property(&sf::Text::getFillColor, &sf::Text::setFillColor)
    );

    auto char_config_type = lua.new_usertype<CharacterConfig>(
        "CharacterConfig", sol::no_constructor,
        "color", sol::readonly(&CharacterConfig::color)
    );
}
