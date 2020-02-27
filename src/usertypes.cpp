#include <SFML/Graphics.hpp>
#include <SFML/Window/Event.hpp>
#include <SFML/Audio/Sound.hpp>
#include <SFML/Audio/SoundBuffer.hpp>

#include "sol/sol.hpp"
#include <fmt/format.h>

#include "usertypes.hpp"
#include "fonts.hpp"
#include "string_utils.hpp"
#include "line_data.hpp"

// Custom to_string implementations for lua usage

namespace sf {

template<typename T>
std::string to_string(const sf::Vector2<T> &vec) {
    return fmt::format("Vector2({}, {})", vec.x, vec.y);
}

template<typename T>
std::string to_string(const sf::Rect<T> &rec) {
    return fmt::format(
        "Rect(left = {}, top = {}, width = {}, height = {})",
        rec.left, rec.top, rec.width, rec.height
    );
}

std::string to_string(const sf::Color &col) {
    return fmt::format(
        "Color(r = {}, g = {}, b = {}, a = {})",
        col.r, col.g, col.b, col.a
    );
}

} // namespace sf

namespace {

template<typename T>
decltype(auto) register_vector2(sol::state &lua, std::string name) {
    using VecT = sf::Vector2<T>;
    using ConstVecRefT = std::add_lvalue_reference_t<std::add_const_t<VecT>>;

    return lua.new_usertype<VecT>(
        name, sol::constructors<VecT(T, T)>(),
        "x", &VecT::x,
        "y", &VecT::y,
        sol::meta_function::addition, sol::resolve<VecT(ConstVecRefT, ConstVecRefT)>(&sf::operator+),
        sol::meta_function::subtraction, sol::resolve<VecT(ConstVecRefT, ConstVecRefT)>(&sf::operator-),
        sol::meta_function::multiplication, sol::overload(
            sol::resolve<VecT(ConstVecRefT, T)>(&sf::operator*),
            sol::resolve<VecT(T, ConstVecRefT)>(&sf::operator*)
        )
    );
}

template<typename T>
decltype(auto) register_rect(sol::state &lua, std::string name) {
    return lua.new_usertype<sf::Rect<T>>(
        name, sol::constructors<sf::Rect<T>(T, T, T, T)>(),
        "left", &sf::Rect<T>::left,
        "top", &sf::Rect<T>::top,
        "width", &sf::Rect<T>::width,
        "height", &sf::Rect<T>::height,
        "intersects", sol::resolve<bool (const sf::Rect<T>&) const>(&sf::Rect<T>::intersects)
    );
}
} // namespace

void register_usertypes(sol::state &lua) {

    // Basic SFML types

    auto vec2f_type = register_vector2<float>(lua, "Vector2f");
    auto vec2u_type = register_vector2<unsigned int>(lua, "Vector2u");

    auto float_rect_type = register_rect<float>(lua, "FloatRect");
    auto int_rect_type = register_rect<int>(lua, "IntRect");

    auto color_type = lua.new_usertype<sf::Color>(
        "Color", sol::constructors<sf::Color(uint8_t red, uint8_t green, uint8_t blue, uint8_t alpha)>(),
        "r", &sf::Color::r,
        "g", &sf::Color::g,
        "b", &sf::Color::b,
        "a", &sf::Color::a,

        "Black", sol::var(sf::Color::Black)
    );

    auto tf_type = lua.new_usertype<sf::Transformable>(
        "Transformable",
        "position", sol::property(
            &sf::Transformable::getPosition,
            sol::resolve<void(const sf::Vector2f&)>(&sf::Transformable::setPosition)
        )
    );

    auto render_target_type = lua.new_usertype<sf::RenderTarget>(
        "RenderTarget",
        "draw", [](sf::RenderTarget &target, const sf::Drawable &drawable) { target.draw(drawable); },
        "size", sol::property(&sf::RenderTarget::getSize)
    );
    auto render_states_type = lua.new_usertype<sf::RenderStates>("RenderStates");

    auto render_texture_type = lua.new_usertype<sf::RenderTexture>(
        "RenderTexture",
        sol::base_classes, sol::bases<sf::RenderTarget>(),
        "size", sol::property(&sf::RenderTexture::getSize)
    );

    auto drawable_type = lua.new_usertype<sf::Drawable>("Drawable");

    auto font_type = lua.new_usertype<sf::Font>("Font");

    auto text_type = lua.new_usertype<sf::Text>(
        "Text", sol::constructors<sf::Text(const std::string&, const sf::Font&, unsigned int)>(),
        sol::base_classes, sol::bases<sf::Drawable, sf::Transformable>(),
        "global_bounds", sol::property(&sf::Text::getGlobalBounds),
        "fill_color", sol::property(&sf::Text::getFillColor, &sf::Text::setFillColor),
        "style", sol::property(&sf::Text::getStyle, &sf::Text::setStyle)
    );

    auto text_style_enum = lua.new_enum(
        "TextStyle",
        "Regular", sf::Text::Regular,
        "Bold", sf::Text::Bold,
        "Italic", sf::Text::Italic,
        "Underlined", sf::Text::Underlined,
        "StrikeThrough", sf::Text::StrikeThrough
    );

    auto rect_shape_type = lua.new_usertype<sf::RectangleShape>(
        "RectangleShape", sol::constructors<sf::RectangleShape(const sf::Vector2f&)>(),
        sol::base_classes, sol::bases<sf::Drawable, sf::Transformable>(),
        "outline_thickness", sol::property(
            &sf::RectangleShape::getOutlineThickness,
            &sf::RectangleShape::setOutlineThickness
        ),
        "outline_color", sol::property(
            &sf::RectangleShape::getOutlineColor,
            &sf::RectangleShape::setOutlineColor
        ),
        "fill_color", sol::property(
            &sf::RectangleShape::getFillColor,
            &sf::RectangleShape::setFillColor
        )
    );

    auto texture_type = lua.new_usertype<sf::Texture>(
        "Texture", sol::constructors<sf::Texture()>(),
        "load_from_file", [](sf::Texture &texture, const std::string filename) { texture.loadFromFile(filename); },
        "size", sol::property(&sf::Texture::getSize)
    );

    auto sprite = lua.new_usertype<sf::Sprite>(
        "Sprite", sol::constructors<sf::Sprite()>(),
        sol::base_classes, sol::bases<sf::Drawable, sf::Transformable>(),
        "texture", sol::property(&sf::Sprite::getTexture, [](sf::Sprite &sprite, const sf::Texture &texture) { sprite.setTexture(texture); }),
        "origin",  sol::property(
            &sf::Sprite::getOrigin,
            sol::resolve<void(const sf::Vector2f&)>(&sf::Sprite::setOrigin)
        ),
        "scale",  sol::property(
            &sf::Sprite::getScale,
            sol::resolve<void(const sf::Vector2f&)>(&sf::Sprite::setScale)
        ),
        "texture_rect", sol::property(&sf::Sprite::getTextureRect, &sf::Sprite::setTextureRect),
        "global_bounds", sol::property(&sf::Sprite::getGlobalBounds)
    );

    auto event_type = lua.new_usertype<sf::Event>(
        "Event",
        "type", sol::readonly(&sf::Event::type),
        // Keyboard events
        "key", sol::readonly(&sf::Event::key),
        // Text entered event
        "text", sol::readonly(&sf::Event::text)
    );
    auto key_event_type = lua.new_usertype<sf::Event::KeyEvent>(
        "KeyEvent",
        "code", sol::readonly(&sf::Event::KeyEvent::code),
        "alt", sol::readonly(&sf::Event::KeyEvent::alt),
        "control", sol::readonly(&sf::Event::KeyEvent::control),
        "shift", sol::readonly(&sf::Event::KeyEvent::shift),
        "system", sol::readonly(&sf::Event::KeyEvent::system)
    );
    auto text_event_type = lua.new_usertype<sf::Event::TextEvent>(
        "TextEvent",
        "unicode", sol::readonly(&sf::Event::TextEvent::unicode)
    );

    auto keyboard_type = lua.new_usertype<sf::Keyboard>(
        "Keyboard",
        "is_key_pressed", &sf::Keyboard::isKeyPressed
    );

    auto key_enum = lua.new_enum(
        "KeyboardKey",
        "Space", sf::Keyboard::Space,
        "D", sf::Keyboard::D,
        "A", sf::Keyboard::A,
        "E", sf::Keyboard::E
    );
    auto event_t_enum = lua.new_enum(
        "EventType",
        "KeyReleased", sf::Event::KeyReleased,
        "KeyPressed", sf::Event::KeyPressed,
        "TextEntered", sf::Event::TextEntered
    );

    auto sound_buf_type = lua.new_usertype<sf::SoundBuffer>(
        "SoundBuffer", sol::constructors<sf::SoundBuffer()>(),
        "load_from_file", &sf::SoundBuffer::loadFromFile
    );
    auto sound_type = lua.new_usertype<sf::Sound>(
        "Sound", sol::constructors<sf::Sound()>(),
        "buffer", sol::property(
            &sf::Sound::getBuffer,
            &sf::Sound::setBuffer
        ),
        "status", sol::property(&sf::Sound::getStatus),
        "play", &sf::Sound::play
    );
    auto sound_status_enum = lua.new_enum(
        "SoundStatus",
        "Playing", sf::Sound::Status::Playing
    );

    // Helper classes

    auto static_fonts_type = lua.new_usertype<StaticFonts>(
        "StaticFonts",
        "main_font", sol::var(std::ref(StaticFonts::main_font)),
        "font_size", sol::var(std::ref(StaticFonts::font_size))
    );

    // Data

    auto char_config_type = lua.new_usertype<CharacterConfig>(
        "CharacterConfig",
        "color", sol::readonly(&CharacterConfig::color)
    );

    auto term_line_type = lua.new_usertype<TerminalLineData>(
        "TerminalLineData",
        "character_config", sol::readonly(&TerminalLineData::character_config),
        "script", sol::readonly(&TerminalLineData::script),
        "script_after", sol::readonly(&TerminalLineData::script_after)
    );
    auto term_output_line_type = lua.new_usertype<TerminalOutputLineData>(
        "TerminalOutputLineData",
        sol::base_classes, sol::bases<TerminalLineData>(),
        "text", sol::readonly(&TerminalOutputLineData::text),
        "next", sol::readonly(&TerminalOutputLineData::next)
    );

    auto term_variant_input_type = lua.new_usertype<TerminalVariantInputLineData>(
        "TerminalVariantInputLineData",
        sol::base_classes, sol::bases<TerminalLineData>(),
        "variants", sol::readonly(&TerminalVariantInputLineData::variants)
    );

    using Variant = TerminalVariantInputLineData::Variant;
    auto term_variant_variant_type = lua.new_usertype<Variant>(
        "TerminalVariantInputLineDataVariant",
        "text", sol::readonly(&Variant::text),
        "next", sol::readonly(&Variant::next),
        "condition", sol::readonly(&Variant::condition)
    );


    auto input_wait_line_type = lua.new_usertype<TerminalInputWaitLineData>(
        "TerminalInputWaitLineData",
        sol::base_classes, sol::bases<TerminalLineData, TerminalOutputLineData>()
    );
}
