#pragma once

#include <string>
#include <map>
#include <vector>

#ifndef SOMEONE_EMSCRIPTEN
#include "al.h"
#include "alc.h"
#include "alext.h"
#else
#include "AL/al.h"
#include "AL/alc.h"
// Emscripten doesn't provide this constant for some reason
#define AL_LOOP_POINTS_SOFT 0x2015
#endif

#include "SFML/System/Vector3.hpp"

namespace someone {

class SoundBuffer {
    ALuint buffer;

public:
    SoundBuffer();

    bool loadFromFile(const std::string &path, bool music = false);
    void setLoopPoints(float start, float end);

    friend class Sound;

    ~SoundBuffer();
};

class Sound {
    ALuint source;

    SoundBuffer *buffer = nullptr;
public:
    enum class Status {
        Stopped,
        Playing
    };

    Sound();

    Status status();

    void play();
    void stop();

    void setVolume(int volume);
    int getVolume();

    void setPosition(sf::Vector3f pos);

    SoundBuffer *getBuffer() { return buffer; };
    void setBuffer(SoundBuffer *buf);

    void setLoop(bool loop);
    bool getLoop();

    ~Sound();
};

static std::map<int, Sound*> playing_sounds;

}
