#version 130

uniform vec2 screenSize;

uniform sampler2D currentTexture;

uniform vec2 monitorTop;
uniform vec2 monitorBottom;

uniform ivec2 lightPos;
uniform vec4 lightTint;
uniform float ambientLightLevel;
uniform float lightPower;

void main() {
    vec2 coord = gl_TexCoord[0].st;
    vec4 color = texture(currentTexture, coord);

    vec2 worldMonitorTop = monitorTop / screenSize;
    vec2 worldMonitorBottom = monitorBottom / screenSize;

    // Distance between the Xes of the monitor & the current point
    float xDist = abs(worldMonitorTop.x - coord.x);

    float lightLevel = ambientLightLevel;
    if ((coord.x >= worldMonitorTop.x && (coord.y > worldMonitorTop.y - xDist - 0.005 && coord.y <= worldMonitorBottom.y + xDist - 0.005)))
        lightLevel += max(0.1 - xDist, 0);


    vec4 newColor = color * lightLevel;

    gl_FragColor = newColor;
}
