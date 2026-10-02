shader_type canvas_item;

// Recover coverage against the original white paper using nearby foreground.
// Removing the white contribution as well as alpha prevents pale fringes when
// large RGB portraits are filtered down to their in-game size.
uniform float edge_radius : hint_range(0.5, 3.0) = 1.5;
varying vec4 tint;
void vertex() { tint = COLOR; }

float paper_value(vec3 color) {
    return min(color.r, min(color.g, color.b));
}

void fragment() {
    vec4 c = texture(TEXTURE, UV);
    float value = paper_value(c.rgb);
    float darkest = value;
    float lightest = value;
    vec2 step_uv = TEXTURE_PIXEL_SIZE * edge_radius;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float neighbor = paper_value(texture(TEXTURE, UV + vec2(float(x), float(y)) * step_uv).rgb);
            darkest = min(darkest, neighbor);
            lightest = max(lightest, neighbor);
        }
    }
    float coverage = clamp((1.0 - value) / max(1.0 - darkest, 0.001), 0.0, 1.0);
    float edge = smoothstep(0.92, 0.99, lightest);
    float matte_alpha = 1.0 - smoothstep(0.90, 0.98, value);
    float a = mix(matte_alpha, coverage * matte_alpha, edge);
    vec3 clean = clamp((c.rgb - vec3(1.0 - a)) / max(a, 0.001), vec3(0.0), vec3(1.0));
    COLOR = vec4(clean, c.a * a) * tint;
}
