#version 130

uniform sampler2D currentTexture;

uniform float ambientLightLevel;

void main() {
    vec2 coord = gl_TexCoord[0].st;
    vec4 color = texture(currentTexture, coord);

    // Non-solid black color that gets blended over the texture
    vec4 newColor = vec4(0, 0, 0, 1 - ambientLightLevel);

    gl_FragColor = newColor;
}
