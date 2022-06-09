#pragma once

#include "SFML/Graphics/Texture.hpp"
#include <SDL_gpu.h>
#include <SDL_render.h>
#include <string>
#include <iostream>
#include <sstream>
#include <fstream>

#define GL_GLEXT_PROTOTYPES
#include <GL/gl.h>
#include <GL/glext.h>

#include <SFML/System/Vector2.hpp>
#include <SFML/Graphics/RenderTexture.hpp>

#include "logger.hpp"

namespace sf {
class Shader {
    GLuint shader = 0;
    GLuint program = 0;

    GPU_ShaderBlock block;
public:
    enum Type {
        Fragment
    };

    bool loadFromFile(const std::string &file, Type type) {
        std::ifstream shaderFile;
        shaderFile.open(file);
        if (!shaderFile.is_open())
            return false;

        std::ostringstream sstr;
        sstr << shaderFile.rdbuf();

        std::string shaderCode = sstr.str();
        shaderFile >> shaderCode;
        shaderFile.close();

        switch (type) {
        case Fragment:
            shader = GPU_CompileShader(GPU_FRAGMENT_SHADER, shaderCode.c_str());
            break;
        }
        if (shader == 0) {
            spdlog::error("{}", GPU_GetShaderMessage());
            return false;
        }
        auto vertShader = GPU_LoadShader(GPU_VERTEX_SHADER, "resources/shaders/common.vert");

        program = GPU_LinkShaders(vertShader, shader);
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
