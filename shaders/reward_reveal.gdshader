shader_type canvas_item;
render_mode unshaded;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;

float hash21(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	// A deterministic clock keeps the three signals distinct without using game RNG.
	float tick = floor(progress * 19.0);
	float row = floor(UV.y * 47.0);
	float noise = hash21(vec2(row + seed, tick));
	float interference = 1.0 - smoothstep(0.45, 1.0, progress);
	float jump = (noise - 0.5) * step(0.62, noise) * 0.075 * interference;
	vec2 uv = UV + vec2(jump, 0.0);
	vec4 source = texture(TEXTURE, uv);
	float split = 0.009 * interference;
	vec4 red = texture(TEXTURE, uv + vec2(split, 0.0));
	vec4 blue = texture(TEXTURE, uv - vec2(split, 0.0));
	float alpha = max(source.a, max(red.a, blue.a) * interference);
	vec3 separated = vec3(red.r * red.a, source.g * source.a, blue.b * blue.a);
	vec3 color = mix(source.rgb, separated / max(alpha, 0.001), interference * 0.85);
	vec2 cell = floor(UV * vec2(23.0, 47.0));
	float threshold = UV.y * 0.64 + hash21(cell + seed) * 0.36;
	float front = progress * 1.24 - 0.10;
	float reveal = 1.0 - smoothstep(front - 0.025, front + 0.025, threshold);
	float rim = (1.0 - smoothstep(0.015, 0.095, abs(threshold - front))) * interference;
	vec3 neon = mix(vec3(0.12, 1.0, 0.88), vec3(1.0, 0.16, 0.57), step(0.5, noise));
	color = mix(color, neon, rim * 0.85);
	color += neon * step(0.91, noise) * interference * 0.30;
	float scan = 1.0 - step(0.78, fract(UV.y * 205.0)) * interference * 0.20;
	float flicker = 1.0 - step(0.87, hash21(vec2(tick, seed))) * interference * 0.28;
	COLOR = vec4(color * scan, alpha * reveal * flicker * step(0.001, progress));
}
