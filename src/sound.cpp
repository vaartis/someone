#include "al.h"
#include "alc.h"
#include "logger.hpp"
#include "sound.hpp"

#include "vorbis/vorbisfile.h"

#ifndef NDEBUG
  #define alCall(before, ...) before; checkALerror_impl(__FILE__, __LINE__);
#else
  #define alCall(before, ...) before;
#endif

namespace {

#ifndef NDEBUG
bool checkALerror_impl(const char *fileStr, int line) {
    ALenum err = alGetError();

    std::string file(fileStr);
    if(err != AL_NO_ERROR) {
        switch(err) {
        case AL_INVALID_NAME:
            spdlog::error("{}:{}, OpenAL error: AL_INVALID_NAME", file, line);
            break;
        case AL_INVALID_ENUM:
            spdlog::error("{}:{} OpenAL error: AL_INVALID_ENUM", file, line);
            break;
        case AL_INVALID_VALUE:
            spdlog::error("{}:{} OpenAL error: AL_INVALID_VALUE", file, line);
            break;
        case AL_INVALID_OPERATION:
            spdlog::error("{}:{} OpenAL error: AL_INVALID_OPERATION", file, line);
            break;
        case AL_OUT_OF_MEMORY:
            spdlog::error("{}:{} OpenAL error: AL_OUT_OF_MEMORY", file, line);
            break;
        default:
            spdlog::error("{}:{} OpenAL error: {}", file, line, err);
            break;
        }
    }

    return err != AL_NO_ERROR;
}
#endif

static bool audio_initiliazed = false;

void ensure_audio_initialized() {
    if (!audio_initiliazed) {
        auto openALdevice = alcOpenDevice(nullptr);
        auto openALContext = alcCreateContext(openALdevice, nullptr);

        alCall(alcMakeContextCurrent(openALContext));

        audio_initiliazed = true;
    }
}

}

namespace someone {

SoundBuffer::SoundBuffer() {
    ensure_audio_initialized();
}

SoundBuffer::~SoundBuffer() {
    alDeleteBuffers(1, &buffer);
    // Flush the error stack, don't care if the buffer wasn't deleted
    alGetError();
}

bool SoundBuffer::loadFromFile(const std::string &path, bool music) {
    FILE *fileDescriptor = std::fopen(path.data(), "rb");
    if (fileDescriptor == nullptr) {
        spdlog::error("Failed to open audio file {}", path);
        return false;
    }

    OggVorbis_File vorbisFile;
    if (ov_open_callbacks(fileDescriptor, &vorbisFile, nullptr, 0, OV_CALLBACKS_NOCLOSE) < 0) {
        spdlog::error("Failed to decode ogg file {}", path);
        return false;
    }

    vorbis_info *vorbisInfo = ov_info(&vorbisFile, -1);
    ALenum format = vorbisInfo->channels == 1 ? AL_FORMAT_MONO16 : AL_FORMAT_STEREO16;
    // 2 for 16 bits
    size_t fileLength = ov_pcm_total(&vorbisFile, -1) * vorbisInfo->channels * 2;
    std::vector<short> dataVector(fileLength);
    for (size_t size = 0, offset = 0, sel = 0;
         (size = ov_read(&vorbisFile, (char*) dataVector.data() + offset, 4096, 0, sizeof(short), 1, (int*) &sel)) != 0;
         offset += size) {
        if (size < 0) {
            spdlog::error("Error while reading ogg file {}", path);
            return false;
        }
    }

    alCall(alGenBuffers(1, &buffer));
    alCall(alBufferData(buffer, format, dataVector.data(), fileLength, vorbisInfo->rate));

    std::fclose(fileDescriptor);
    ov_clear(&vorbisFile);

    return true;
}

void SoundBuffer::setLoopPoints(float start, float end) {
    ALint freq;
    alCall(alGetBufferi(buffer, AL_FREQUENCY, &freq));
    ALint point = start * freq;
    ALint point2 = end * freq;

    ALint values[] = { point, point2 };
    alCall(alBufferiv(buffer, AL_LOOP_POINTS_SOFT, values));
}

Sound::Sound() {
    ensure_audio_initialized();

    alCall(alGenSources(1, &source));
}

Sound::~Sound() {
    stop();

    alCall(alSourcei(source, AL_BUFFER, 0));
    alCall(alDeleteSources(1, &source));
}

Sound::Status Sound::status() {
    ALint result;
    alCall(alGetSourcei(source, AL_SOURCE_STATE, &result));

    switch (result) {
    case AL_PLAYING:
        return Status::Playing;
    case AL_STOPPED:
    case AL_INITIAL:
    default:
        return Status::Stopped;
    }
}

void Sound::play() {
    if (status() == Status::Playing) return;

    alCall(alSourcePlay(source));
}

void Sound::stop() {
    alCall(alSourceStop(source));
}

// The volume functions convert from 100 to 1.0

void Sound::setVolume(int volume) {
    alCall(alSourcef(source, AL_GAIN, (float)volume / 100));
}


int Sound::getVolume() {
    ALfloat resFloat;
    alCall(alGetSourcef(source, AL_GAIN, &resFloat));
    return resFloat * 100;
}

void Sound::setPosition(sf::Vector3f position) {
    alCall(alSource3f(source, AL_POSITION, position.x, position.y, position.z));
}

void Sound::setBuffer(SoundBuffer *buf) {
    this->buffer = buf;
    alCall(alSourcei(source, AL_BUFFER, buf->buffer));
}

void Sound::setLoop(bool loop) {
    alCall(alSourcei(source, AL_LOOPING, loop ? AL_TRUE : AL_FALSE));
}

bool Sound::getLoop() {
    ALint result;
    alCall(alGetSourcei(source, AL_LOOPING, &result));

    return result == AL_TRUE;
}

}
