shader_type canvas_item;
uniform float coverage : hint_range(0.0, 1.0) = 0.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
void fragment() {
    float row = floor(UV.y * 85.0);
    float tick = floor(TIME * 18.0);
    float noise = hash(vec2(row, tick));
    float front = 1.0 - coverage;
    float mask = step(front, UV.y);
    float edge = (1.0-smoothstep(0.0,0.14,UV.y-front)) * mask;
    float blocks = step(0.55, hash(vec2(floor(UV.x * 24.0), row + tick)));
    vec3 neon = mix(vec3(0.04,0.90,0.94), vec3(0.92,0.10,0.56), step(0.5, noise));
    neon = mix(neon, vec3(0.49,0.25,1.0), step(0.81,noise));
    vec3 color = mix(vec3(0.025,0.025,0.075), neon, edge * 0.7 + blocks * 0.22);
    color += vec3(0.1,0.18,0.2) * step(0.97,fract(UV.y * 170.0));
    COLOR = vec4(color, mask * fade);
}
