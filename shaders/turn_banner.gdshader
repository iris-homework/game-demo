shader_type canvas_item;
uniform float reveal : hint_range(0.0, 1.0) = 0.0;
uniform float erase : hint_range(0.0, 1.0) = 0.0;
uniform float clock = 0.0;
uniform vec4 accent : source_color = vec4(0.39, 1.0, 0.88, 1.0);

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
    float row = floor(UV.y * 72.0);
    float tick = floor(clock * 20.0);
    float noise = hash(vec2(row, tick));
    float incoming = 1.0 - reveal;
    float outgoing = 1.0 - erase;
    // Both boundaries move from UV.y = 1 (bottom) toward 0 (top).
    float mask = step(incoming, UV.y) * (1.0 - step(outgoing, UV.y));
    float motion = (reveal < 1.0 || erase > 0.0) ? 1.0 : 0.18;
    float split = (noise - 0.5) * 0.014 * motion * step(0.66, noise);
    vec2 uv = UV + vec2(split, 0.0);
    vec4 glyph = texture(TEXTURE, uv);
    float ghost = texture(TEXTURE, uv + vec2(0.004 * motion, 0.0)).a;
    vec3 tint = mix(glyph.rgb, accent.rgb, 0.12 + step(0.89, noise) * 0.3);
    float edge_in = (1.0 - smoothstep(0.0, 0.045, abs(UV.y - incoming))) * float(reveal < 1.0);
    float edge_out = (1.0 - smoothstep(0.0, 0.045, abs(UV.y - outgoing))) * float(erase > 0.0);
    tint += accent.rgb * max(edge_in, edge_out) * 0.8;
    float scan = 0.84 + 0.16 * step(0.3, fract(UV.y * 110.0));
    float flicker = 0.88 + 0.12 * step(0.17, hash(vec2(tick, 3.0)));
    float alpha = max(glyph.a, ghost * 0.4) * mask * flicker;
    COLOR = vec4(tint * scan, alpha);
}
