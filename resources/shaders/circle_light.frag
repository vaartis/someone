uniform sampler2D currentTexture;

uniform vec2 screenSize;
uniform float brightness;
uniform vec2 point;

in vec2 texCoord;
out vec4 fragColor;

void main() {
    vec4 texColor = texture(currentTexture, texCoord);

    vec2 screenPoint = point / screenSize;

    float lightLevel = max(brightness - distance(screenPoint, texCoord), 0.0);
    vec4 newColor = vec4(1, 1, 1, texColor.a + lightLevel);

    fragColor = newColor;
}
