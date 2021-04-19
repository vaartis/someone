#include <map>

#include "SDL_mixer.h"

namespace someone {

void on_channel_finished(int channel);

class SoundBuffer {
    Mix_Chunk *chunk;

public:
    SoundBuffer();

    bool loadFromFile(const std::string &path);

    friend class Sound;
};

class Sound {
    int channel = -1;
    int volume = 240;

    int angle = 0, distance = 0;
    bool positioned = false;

    void do_set_position();
    void finished_playing();
public:
    enum class Status {
        Stopped,
        Playing
    };

    bool loop = false;

    SoundBuffer buffer;

    Sound() { }

    Status status();

    void play();

    void stop();

    void setVolume(int volume);
    int getVolume();

    void setPosition(int angle, int dist);

    friend void on_channel_finished(int channel);
};

static std::map<int, Sound*> playing_sounds;

}
