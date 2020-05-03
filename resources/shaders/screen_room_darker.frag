#version 130

uniform vec2 screenSize;

uniform sampler2D currentTexture;

uniform vec2 monitorTop;
uniform vec2 monitorBottom;

uniform float ambientLightLevel;

void main() {
    vec2 coord = gl_TexCoord[0].st;
    vec4 color = texture(currentTexture, coord);

    vec2 screenMonitorTop = monitorTop / screenSize;
    vec2 screenMonitorBottom = monitorBottom / screenSize;

    // Because of rendering to a RenderTexture, the rendering process is actually going bottom to top,
    // so Y actually goes up, not down. Therefore it has to be subtracted from the screen top to represent
    // the actual position
    screenMonitorTop.y = 1 - screenMonitorTop.y;
    screenMonitorBottom.y = 1 - screenMonitorBottom.y;

    // Distance between the Xes of the monitor & the current point
    float xDist = abs(screenMonitorTop.x - coord.x);

    float lightLevel = ambientLightLevel;

    // Because Y is going bottom to top, the the bottom is actually lower than the top, unlike it usually is
    // when Y is going top to bottom
    if ((coord.x >= screenMonitorTop.x && (coord.y < screenMonitorTop.y + xDist && coord.y > screenMonitorBottom.y - xDist)))
        lightLevel += max(0.1 - xDist, 0);

    vec4 newColor = vec4(color.rgb * lightLevel, color.a);

    gl_FragColor = newColor;
}
