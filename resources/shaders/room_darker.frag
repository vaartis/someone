uniform sampler2D currentTexture;

uniform float ambientLightLevel;

out vec4 fragColor;

void main() {
    // Non-solid black color that gets blended over the texture
    vec4 newColor = vec4(0, 0, 0, 1.0 - ambientLightLevel);

    fragColor = newColor;
}
