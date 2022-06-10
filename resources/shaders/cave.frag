uniform vec2 screenSize;

uniform sampler2D currentTexture;

uniform vec2 lightPoint;

in vec2 texCoord;
out vec4 fragColor;

void main() {
    vec2 screenPoint = lightPoint / screenSize;

    vec4 newColor = vec4(0, 0, 0, 1);
    float dist = distance(screenPoint, texCoord) * 10;
    newColor.a = dist;

    fragColor = newColor;
}
