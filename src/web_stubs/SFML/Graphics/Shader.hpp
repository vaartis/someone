#pragma once

#include "SDL_gpu.h"

#include <map>
#include <string>
#include <iostream>
#include <sstream>
#include <fstream>

#define GL_GLEXT_PROTOTYPES
#ifdef SOMEONE_APPLE
  #include <OpenGL/gl.h>
  #include <OpenGL/glext.h>
#else
  #include <GL/gl.h>
  #include <GL/glext.h>
#endif

#include "SFML/System/Vector2.hpp"
#include "SFML/Graphics/RenderTexture.hpp"

#include "logger.hpp"

namespace sf {
class Shader {
    GLuint program = 0;

    GPU_ShaderBlock block;

    std::map<std::string, int> uniformLocations;

    int getUniformLocation(const std::string &name) {
        int location;
        if (uniformLocations.contains(name)) {
            location = uniformLocations[name];
        } else {
            location = GPU_GetUniformLocation(program, name.c_str());
            uniformLocations[name] = location;
        }
        return location;
    }
public:
    enum Type {
        Fragment
    };

    bool loadFromFile(const std::string &file, Type type) {
        std::string shaderPrefix;
#if SOMEONE_EMSCRIPTEN
        shaderPrefix = "#version 300 es\nprecision mediump float;";
#else
        shaderPrefix = "#version 130";
#endif

        GLuint fragShader, vertShader;
        {
            std::ifstream shaderFile;
            shaderFile.open(file);
            if (!shaderFile.is_open())
                return false;

            std::ostringstream sstr;
            sstr << shaderFile.rdbuf();
            shaderFile.close();

            std::string shaderCode = shaderPrefix + "\n\n" + sstr.str();

            switch (type) {
            case Fragment:
                fragShader = GPU_CompileShader(GPU_FRAGMENT_SHADER, shaderCode.c_str());
                break;
            }
            if (fragShader == 0) {
                spdlog::error("{}", GPU_GetShaderMessage());
                return false;
            }
        }
        {
            std::ifstream shaderFile;
            shaderFile.open("resources/shaders/common.vert");
            if (!shaderFile.is_open())
                return false;

            std::ostringstream sstr;
            sstr << shaderFile.rdbuf();
            shaderFile.close();

            std::string shaderCode = shaderPrefix + "\n\n" + sstr.str();

            vertShader = GPU_CompileShader(GPU_VERTEX_SHADER, shaderCode.c_str());
            if (vertShader == 0) {
                spdlog::error("{}", GPU_GetShaderMessage());
                return false;
            }
        }

        program = GPU_LinkShaders(vertShader, fragShader);
        if (program == 0) {
            spdlog::error("{}", GPU_GetShaderMessage());
            return false;
        }

        block = GPU_LoadShaderBlock(program, "gpu_Vertex", "gpu_TexCoord", "gpu_Color", "gpu_ModelViewProjectionMatrix");

        GPU_DetachShader(program, vertShader);
        GPU_DetachShader(program, fragShader);
        GPU_FreeShaderProgram(vertShader);
        GPU_FreeShaderProgram(fragShader);

        return true;
    }

    void activate() { GPU_ActivateShaderProgram(program, &block); }
    static void deactivate() { GPU_DeactivateShaderProgram(); }

    void setUniform(std::string name, Vector2f value) {
        float values[] = { value.x, value.y };
        GPU_SetUniformfv(
            getUniformLocation(name),
            2,
            1,
            values
        );
    }

    void setUniform(std::string name, float value) {
        GPU_SetUniformf(
            getUniformLocation(name),
            value
        );
    }

    void drawWithTexture(RenderTexture &renderTexture, GPU_Target *target)  {
        Texture &texture = renderTexture.texture;
        GPU_Blit(texture.texture, nullptr, target, 0, 0);
    }


    ~Shader() { }
};
}
