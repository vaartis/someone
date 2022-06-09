#version 130

uniform sampler2D currentTexture;

uniform vec2 screenSize;
uniform float brightness;
uniform vec2 point;

varying vec2 texCoord;

void main() {
    vec2 coord = texCoord.st;
    vec4 color = texture(currentTexture, coord);

    vec2 screenPoint = point / screenSize;

    float lightLevel = max(brightness - distance(screenPoint, coord), 0);
    vec4 newColor = vec4(1, 1, 1, color.a + lightLevel);

    gl_FragColor = newColor;
}
