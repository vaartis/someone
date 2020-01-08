#include <SFML/Window/Keyboard.hpp>
#include <filesystem>
#include <fstream>
#include <limits>

#include "SFML/Graphics/Sprite.hpp"
#include "SFML/Audio/SoundBuffer.hpp"
#include "SFML/Audio/Sound.hpp"

#include "nlohmann/json.hpp"

class MainChar {
private:
    sf::RenderTarget &target;

    sf::Texture char_texture;
    sf::Sprite char_sprite;

    const std::string footstep_sound_path = "resources/sounds/footstep.ogg";
    sf::SoundBuffer footstep_sound_buf;
    sf::Sound footstep_sound;

    bool walking = false;
    int8_t look_direction = 1;
    int current_frame = 0;
    float time_since_frame_change = 0.0f;

    std::vector<sf::IntRect> frames;
    std::vector<float> frame_durations;
public:
    sf::Vector2f position = sf::Vector2f(180, 880);

    MainChar(sf::RenderTarget &target_, std::string sprite_dir_path) : target(target_) {
        std::filesystem::path dir_path(sprite_dir_path);

        if (sprite_dir_path[sprite_dir_path.length() - 1] == '/') {
            spdlog::error("Path {} must not end on a '/'", sprite_dir_path);
            std::terminate();
        }

        std::string name = dir_path.stem();
        auto sheet_path = dir_path / name;
        sheet_path.replace_extension(".png");
        auto json_path = sheet_path;
        json_path.replace_extension(".json");

        std::ifstream json_stream(json_path);
        nlohmann::json json;
        json_stream >> json;

        // Write all the frame rectangles
        for (auto frame : json["frames"]) {
            auto frame_f = frame["frame"];
            frames.push_back(
                sf::IntRect(frame_f["x"], frame_f["y"], frame_f["w"], frame_f["h"])
            );
            frame_durations.push_back(sf::milliseconds(frame["duration"]).asSeconds());
        }

        if (!char_texture.loadFromFile(sheet_path)) {
            spdlog::error("Error loading sprite {}", std::string(sheet_path));

            std::terminate();
        }
        char_sprite.setTexture(char_texture);

        // Set the pivot to the center of the sprite
        auto firstFrame = frames.front();
        auto half_width = firstFrame.width / 2;
        char_sprite.setOrigin(half_width, firstFrame.height);

        if (!footstep_sound_buf.loadFromFile(footstep_sound_path)) {
            spdlog::error("Error loading sound {}", std::string(sheet_path));

            std::terminate();
        }
        footstep_sound.setBuffer(footstep_sound_buf);
    }

    void update(float dt) {
        time_since_frame_change += dt;

        if (walking) {
            if (time_since_frame_change > frame_durations.at(current_frame)) {
                time_since_frame_change = 0;

                if (current_frame + 1 < frames.size()) {
                    current_frame++;
                } else {
                    current_frame = 0;
                }
            }
        } else {
            // If the character isn't walking, set the animation to the first frame
            current_frame = 0;
        }

        char_sprite.setPosition(position);

        if (sf::Keyboard::isKeyPressed(sf::Keyboard::D)) {
            position += sf::Vector2f(1.0f, 0.0f);
            look_direction = 1;
            walking = true;
        } else if (sf::Keyboard::isKeyPressed(sf::Keyboard::A)) {
            position += sf::Vector2f(-1.0f, 0.0f);
            look_direction = -1;
            walking = true;
        } else {
            walking = false;
        }

        if (walking && current_frame % 2 != 0 && footstep_sound.getStatus() != sf::Sound::Status::Playing) {
            footstep_sound.play();
        }

        char_sprite.setScale(look_direction, 1.0f);

        /*
        view.setCenter(position);
        window.setView(view);
        */
    }

    void display() {
        char_sprite.setTextureRect(frames[current_frame]);

        target.draw(char_sprite);
    }
};
