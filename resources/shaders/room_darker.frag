#version 130

uniform sampler2D currentTexture;

uniform float ambientLightLevel;

void main() {
    vec2 coord = gl_TexCoord[0].st;
    vec4 color = texture(currentTexture, coord);

    vec4 newColor = vec4(color.rgb * ambientLightLevel, color.a);

    gl_FragColor = newColor;
}
