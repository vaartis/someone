#include "SDL.h"

#include "logger.hpp"
#include "sound.hpp"

namespace {

static bool audio_initiliazed = false;

void ensure_audio_initialized() {
    if (!audio_initiliazed) {
        if (SDL_Init(SDL_INIT_AUDIO) < 0) {
            spdlog::error("Couldn't initialize SDL_mixer: {}", SDL_GetError());
            return;
        }

        if (Mix_OpenAudio(44100, MIX_DEFAULT_FORMAT, MIX_DEFAULT_CHANNELS, 4096) < 0) {
            spdlog::error("Couldn't open SDL_mixer audio: {}", SDL_GetError());
            return;
        }

        Mix_ChannelFinished(someone::on_channel_finished);

        audio_initiliazed = true;
    }
}

}

namespace someone {

SoundBuffer::SoundBuffer() {
    ensure_audio_initialized();
}

bool SoundBuffer::loadFromFile(const std::string &path) {
    chunk = Mix_LoadWAV(path.data());
    if (chunk == nullptr) {
        spdlog::error("Failed to load audio file {}: {}", path, SDL_GetError());
        return false;
    }

    return true;
}

Sound::Status Sound::status() {
    if (playing_sounds.contains(channel) && playing_sounds[channel] == this) {
        return Status::Playing;
    } else
        return Status::Stopped;
}

void Sound::play() {
    if (status() == Status::Playing) return;

    // Loop the sound if requested by passing -1
    channel = Mix_PlayChannel(-1, buffer.chunk, loop ? -1 : 0);
    if (channel == -1) {
        spdlog::error("Could not play the sound: {}", SDL_GetError());
        return;
    }
    playing_sounds[channel] = this;

    Mix_Volume(channel, volume);

    if (positioned) {
        do_set_position();
    }
}

void Sound::stop() {
    if (status() == Status::Playing) {
        Mix_HaltChannel(channel);
    }
}

// The volume functions convert from 100 to 255 and back for SDL_mixer

void Sound::setVolume(int volume) {
    this->volume = (255 * volume) / 100;
    if (status() == Status::Playing) {
        Mix_Volume(channel, this->volume);
    }
}


int Sound::getVolume() {
    return (100 * volume) / 255;
}


void Sound::setPosition(int angle, int dist) {
    if (angle == 0 && dist == 0) {
        angle = 1;
        dist = 0;
    }

    this->angle = angle;
    this->distance = dist;

    positioned = true;
    if (status() == Status::Playing) {
        do_set_position();
    }
}

void Sound::do_set_position() {
    if (Mix_SetPosition(channel, angle, distance) == 0) {
        spdlog::error("Failed to set position on channel {} with angle = {}, distance = {}", channel, angle, distance);
    }
};

void Sound::finished_playing() {
    if (positioned) {
        Mix_SetPosition(channel, 0, 0);
    }
}

void on_channel_finished(int channel) {
    playing_sounds[channel]->finished_playing();
    playing_sounds.erase(channel);
}

}
