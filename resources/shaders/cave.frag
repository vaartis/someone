#version 130

uniform vec2 screenSize;

uniform sampler2D currentTexture;

uniform vec2 lightPoint;

void main() {
    vec2 coord = gl_TexCoord[0].st;
    vec4 color = texture(currentTexture, coord);

    vec2 screenPoint = lightPoint / screenSize;

    vec4 newColor = vec4(0, 0, 0, 1);
    float dist = distance(screenPoint, coord) * 10;
    newColor.a = dist;

    gl_FragColor = newColor;
}
