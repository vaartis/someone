#pragma once

#include <string>
#include <iostream>
#include <fstream>

#define GL_GLEXT_PROTOTYPES
#include <GL/gl.h>
#include <GL/glext.h>

#include <SFML/System/Vector2.hpp>

#include "logger.hpp"

namespace sf {
class Shader {
    GLuint program;

    bool checkError() {
        if (glGetError() != GL_NO_ERROR) {
            spdlog::error("OpenGL error: {}", glGetError());
            return true;
        }

        return false;
    }
public:
    enum Type {
        Fragment
    };

    bool loadFromFile(const std::string &file, Type type) {
        std::ifstream shaderFile;
        shaderFile.open(file);
        if (!shaderFile.is_open())
            return false;

        std::string shaderCode;
        shaderFile >> shaderCode;
        shaderFile.close();

        switch (type) {
        case Fragment:
            program = glCreateShader(GL_FRAGMENT_SHADER);
            break;
        }

        const GLchar *sourceArr[] = { shaderCode.c_str() };
        const GLint lengthArr[] = { (int)shaderCode.length() };

        glShaderSource(program, 1, sourceArr, lengthArr);
        if (checkError())
            return false;

        glCompileShader(program);
        if (checkError())
            return false;

        return true;
    }

    void setUniform(std::string name, Vector2f value) {
        GLint location = glGetUniformLocation(program, name.c_str());
        glUniform2f(location, value.x, value.y);
    }

    void setUniform(std::string name, float value) {
        GLint location = glGetUniformLocation(program, name.c_str());
        glUniform1f(location, value);
    }

    ~Shader() {
        glDeleteShader(program);
    }
};
}
