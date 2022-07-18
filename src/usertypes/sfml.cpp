#include "SFML/Window/Window.hpp"
#include "SFML/System/Vector2.hpp"
#include "SFML/System/Vector3.hpp"
#include "SFML/System/Rect.hpp"
#include "SFML/Graphics/Color.hpp"
#include "SFML/Graphics/RectangleShape.hpp"
#include "SFML/Graphics/Texture.hpp"
#include "SFML/Graphics/RenderTarget.hpp"
#include "SFML/Graphics/Transformable.hpp"
#include "SFML/Graphics/View.hpp"

#include <fmt/format.h>

#include "usertypes.hpp"
#include "sound.hpp"

#ifdef SOMEONE_APPLE
#include "keyboard.hpp"
#endif

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
decltype(auto) register_vector3(sol::state &lua, std::string name) {
    using VecT = sf::Vector3<T>;
    using ConstVecRefT = std::add_lvalue_reference_t<std::add_const_t<VecT>>;

    return lua.new_usertype<VecT>(
        name, sol::constructors<VecT(T, T, T)>(),
        "x", &VecT::x,
        "y", &VecT::y,
        "z", &VecT::z,
        sol::meta_function::addition, sol::resolve<VecT(ConstVecRefT, ConstVecRefT)>(&sf::operator+),
        sol::meta_function::subtraction, sol::resolve<VecT(ConstVecRefT, ConstVecRefT)>(&sf::operator-),
        sol::meta_function::multiplication, sol::overload(
            sol::resolve<VecT(ConstVecRefT, T)>(&sf::operator*),
            sol::resolve<VecT(T, ConstVecRefT)>(&sf::operator*)
        ),
        sol::meta_function::division, sol::resolve<VecT(ConstVecRefT, T)>(&sf::operator/)
    );
}

template<typename T>
decltype(auto) register_vector2(sol::state &lua, std::string name) {
    using VecT = sf::Vector2<T>;
    using ConstVecRefT = std::add_lvalue_reference_t<std::add_const_t<VecT>>;

    return lua.new_usertype<VecT>(
        name, sol::constructors<VecT(T, T)>(),
        "copy", [](VecT &self) { return VecT(self.x, self.y); },
        "x", &VecT::x,
        "y", &VecT::y,
        sol::meta_function::addition, sol::resolve<VecT(ConstVecRefT, ConstVecRefT)>(&sf::operator+),
        sol::meta_function::subtraction, sol::resolve<VecT(ConstVecRefT, ConstVecRefT)>(&sf::operator-),
        sol::meta_function::multiplication, sol::overload(
            sol::resolve<VecT(ConstVecRefT, T)>(&sf::operator*),
            sol::resolve<VecT(T, ConstVecRefT)>(&sf::operator*)
        ),
        sol::meta_function::division, sol::resolve<VecT(ConstVecRefT, T)>(&sf::operator/)
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

void register_sfml_usertypes(sol::state &lua, StaticFonts &fonts) {
    auto vec2f_type = register_vector2<float>(lua, "Vector2f");
    auto vec2u_type = register_vector2<unsigned int>(lua, "Vector2u");
    auto vec2i_type = register_vector2<int>(lua, "Vector2i");

    auto vec3f_type = register_vector3<float>(lua, "Vector3f");

    auto float_rect_type = register_rect<float>(lua, "FloatRect");
    auto int_rect_type = register_rect<int>(lua, "IntRect");

    auto color_type = lua.new_usertype<sf::Color>(
        "Color", sol::constructors<sf::Color(uint8_t red, uint8_t green, uint8_t blue, uint8_t alpha)>(),
        "r", &sf::Color::r,
        "g", &sf::Color::g,
        "b", &sf::Color::b,
        "a", &sf::Color::a,

        "White", sol::var(sf::Color::White),
        "Black", sol::var(sf::Color::Black),
        "Red", sol::var(sf::Color::Red),
        "Yellow", sol::var(sf::Color::Yellow),
        "Green", sol::var(sf::Color::Green)
    );

    auto tf_type = lua.new_usertype<sf::Transformable>(
        "Transformable",
        "position", sol::property(
            &sf::Transformable::getPosition,
            sol::resolve<void(const sf::Vector2f&)>(&sf::Transformable::setPosition)
        ),
        "origin", sol::property(
            &sf::Transformable::getOrigin,
            sol::resolve<void(const sf::Vector2f&)>(&sf::Transformable::setOrigin)
        ),
        "scale", sol::property(
            &sf::Transformable::getScale,
            sol::resolve<void(const sf::Vector2f&)>(&sf::Transformable::setScale)
        ),
        "rotation", sol::property(
            &sf::Transformable::getRotation,
            &sf::Transformable::setRotation
        ),
        "rotate", &sf::Transformable::rotate
    );

    auto render_win_type = lua.new_usertype<sf::RenderWindow>(
        "RenderWindow",
        sol::base_classes, sol::bases<sf::RenderTarget>()
    );

    auto render_target_type = lua.new_usertype<sf::RenderTarget>(
        "RenderTarget",
        "draw", [](sf::RenderTarget &target, sf::Drawable &drawable) { target.draw(drawable); },
        "size", sol::property(&sf::RenderTarget::getSize),
        "view", sol::property(&sf::RenderTarget::getView, &sf::RenderTarget::setView),
        "default_view", sol::property(&sf::RenderTarget::getDefaultView),
        "map_pixel_to_coords", [](const sf::RenderTarget &target, const sf::Vector2f& pos) { return target.mapPixelToCoords(sf::Vector2i(pos.x, pos.y)); },
        "map_coords_to_pixel", [](const sf::RenderTarget &target, const sf::Vector2f& pos) { return sf::Vector2f(target.mapCoordsToPixel(pos)); }
    );

    auto render_texture_type = lua.new_usertype<sf::RenderTexture>(
        "RenderTexture",
        sol::base_classes, sol::bases<sf::RenderTarget>(),
        "size", sol::property(&sf::RenderTexture::getSize)
    );

    auto view_type = lua.new_usertype<sf::View>(
        "View", sol::constructors<sf::View()>(),
        "reset", &sf::View::reset,
        "viewport", sol::property(&sf::View::getViewport, &sf::View::setViewport)
    );

    auto drawable_type = lua.new_usertype<sf::Drawable>("Drawable");

    auto font_type = lua.new_usertype<sf::Font>("Font");

    auto text_type = lua.new_usertype<sf::Text>(
        "Text", sol::constructors<sf::Text(const std::string&, sf::Font&, unsigned int)>(),
        sol::base_classes, sol::bases<sf::Drawable, sf::Transformable>(),
        "string", sol::property(
            [](sf::Text &self) { return self.getString(); },
            [](sf::Text &self, std::string str) { return self.setString(str); }
        ),
        "global_bounds", sol::property(&sf::Text::getGlobalBounds),
        "fill_color", sol::property(&sf::Text::getFillColor, &sf::Text::setFillColor),
        "style", sol::property(&sf::Text::getStyle, &sf::Text::setStyle),
        "character_size", sol::property(&sf::Text::getCharacterSize, &sf::Text::setCharacterSize)
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
        /*
        "outline_thickness", sol::property(
            &sf::RectangleShape::getOutlineThickness,
            &sf::RectangleShape::setOutlineThickness
        ),
        */
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
        "texture", sol::property(&sf::Sprite::getTexture, [](sf::Sprite &sprite, sf::Texture *texture) { sprite.setTexture(texture); }),
        "texture_rect", sol::property(&sf::Sprite::getTextureRect, &sf::Sprite::setTextureRect),
        "global_bounds", sol::property(&sf::Sprite::getGlobalBounds),
        "color", sol::property(&sf::Sprite::getColor, &sf::Sprite::setColor)
    );
    auto nineSliceSprite = lua.new_usertype<sf::NineSliceSprite>(
        "NineSliceSprite", sol::constructors<sf::NineSliceSprite()>(),
        sol::base_classes, sol::bases<sf::Sprite, sf::Transformable, sf::Drawable>(),
        "size", sol::property(&sf::NineSliceSprite::getSize, &sf::NineSliceSprite::setSize)
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
        "is_key_pressed", [&](sf::Keyboard::Key key) {
#ifdef SOMEONE_APPLE
            return someone::KeypressTracker::is_key_pressed(key);
#else
            // Because SFML doesn't track if the window is focused or not,
            // this needs to be done manually. Obviously when the window is not focused,
            // no keys should be registered as pressed
            return lua["GLOBAL"]["window"].get<sf::RenderWindow>().hasFocus()
                ? sf::Keyboard::isKeyPressed(key)
                : false;
#endif
        }
    );

    auto key_enum = lua.new_enum(
        "KeyboardKey",
        "Space", sf::Keyboard::Space,
        "Num1", sf::Keyboard::Num1,
        "W", sf::Keyboard::W,
        "A", sf::Keyboard::A,
        "S", sf::Keyboard::S,
        "D", sf::Keyboard::D,
        "E", sf::Keyboard::E,
        "L", sf::Keyboard::L,
        "Z", sf::Keyboard::Z,
        "X", sf::Keyboard::X,
        "R", sf::Keyboard::R,
        "M", sf::Keyboard::M,
        "Q", sf::Keyboard::Q,
        "J", sf::Keyboard::J,
        "K", sf::Keyboard::K,
        "LControl", sf::Keyboard::LControl,
        "LShift", sf::Keyboard::LShift,
        "Return", sf::Keyboard::Return,
        "Backspace", sf::Keyboard::Backspace
    );
    auto event_t_enum = lua.new_enum(
        "EventType",
        "KeyReleased", sf::Event::KeyReleased,
        "KeyPressed", sf::Event::KeyPressed,
        "TextEntered", sf::Event::TextEntered
    );

    auto shader_type = lua.new_usertype<sf::Shader>(
        "Shader", sol::constructors<sf::Shader()>(),
        "load_from_file", sol::resolve<bool(const std::string &, sf::Shader::Type)>(&sf::Shader::loadFromFile)
    );
    auto shader_type_enum = lua.new_enum(
        "ShaderType",
        "Fragment", sf::Shader::Fragment
    );

    // Not SFML, but mimicks the interface

    auto sound_buf_type = lua.new_usertype<someone::SoundBuffer>(
        "SoundBuffer", sol::constructors<someone::SoundBuffer()>(),
        "load_from_file", &someone::SoundBuffer::loadFromFile
    );

    auto sound_type = lua.new_usertype<someone::Sound>(
        "Sound", sol::constructors<someone::Sound()>(),
        "buffer", &someone::Sound::buffer,
        "play", &someone::Sound::play,
        "stop", &someone::Sound::stop,
        "status", sol::property(&someone::Sound::status),
        "volume", sol::property(&someone::Sound::getVolume, &someone::Sound::setVolume),
        "loop", &someone::Sound::loop,
        "set_position", &someone::Sound::setPosition
    );

    auto sound_status_enum = lua.new_enum(
        "SoundStatus",
        "Playing", someone::Sound::Status::Playing,
        "Stopped", someone::Sound::Status::Stopped
    );
}
