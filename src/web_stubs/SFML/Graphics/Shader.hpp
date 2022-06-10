#pragma once

#include "SDL_gpu.h"

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

        return true;
    }

    void setUniform(std::string name, Vector2f value) {
        GPU_ShaderBlock block = GPU_LoadShaderBlock(program, "gpu_Vertex", "gpu_TexCoord", "gpu_Color", "gpu_ModelViewProjectionMatrix");

        auto oldProgram = GPU_GetCurrentShaderProgram();
        auto oldProgamBlock = GPU_GetShaderBlock();

        float values[] = { value.x, value.y };
        GPU_ActivateShaderProgram(program, &block);
        GPU_SetUniformfv(
            GPU_GetUniformLocation(program, name.c_str()),
            2,
            1,
            values
        );
        GPU_ActivateShaderProgram(oldProgram, &oldProgamBlock);
    }

    void setUniform(std::string name, float value) {
        auto oldProgram = GPU_GetCurrentShaderProgram();
        auto oldProgamBlock = GPU_GetShaderBlock();

        GPU_ActivateShaderProgram(program, &block);
        GPU_SetUniformf(
            GPU_GetUniformLocation(program, name.c_str()),
            value
        );
        GPU_ActivateShaderProgram(oldProgram, &oldProgamBlock);
    }

    void drawWithTexture(RenderTexture &renderTexture, GPU_Target *target)  {
        Texture &texture = renderTexture.texture;

        GPU_ShaderBlock block = GPU_LoadShaderBlock(program, "gpu_Vertex", "gpu_TexCoord", "gpu_Color", "gpu_ModelViewProjectionMatrix");
        GPU_ActivateShaderProgram(program, &block);

        GPU_Blit(texture.texture, nullptr, target, 0, 0);

        GPU_DeactivateShaderProgram();
    }


    ~Shader() { }
};
}
