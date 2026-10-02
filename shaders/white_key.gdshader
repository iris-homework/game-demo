shader_type canvas_item;
varying vec4 tint;
void vertex() { tint = COLOR; }
void fragment() {
    vec4 c = texture(TEXTURE, UV);
    float a = 1.0 - smoothstep(0.90, 0.975, min(c.r, min(c.g, c.b)));
    vec3 clean = clamp((c.rgb - vec3(1.0 - a)) / max(a, 0.001), vec3(0.0), vec3(1.0));
    COLOR = vec4(clean, c.a * a) * tint;
}
