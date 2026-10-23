shader_type canvas_item;
render_mode unshaded;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float clock = 0.0;
uniform vec4 cyan : source_color = vec4(0.392, 1.0, 0.882, 1.0);
uniform vec4 pink : source_color = vec4(1.0, 0.224, 0.557, 1.0);

float hash21(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float active = smoothstep(0.0, 0.15, progress) * (1.0 - smoothstep(0.84, 1.0, progress));
	float tick = floor(clock * 28.0);
	float band = floor(UV.y * 38.0);
	float noise = hash21(vec2(band, tick));
	float jump = (noise - 0.5) * step(0.58, noise) * 0.12 * active;
	vec2 uv = UV + vec2(jump, 0.0);
	vec4 source = texture(TEXTURE, uv);
	float split = 0.013 * active;
	vec4 left = texture(TEXTURE, uv + vec2(split, 0.0));
	vec4 right = texture(TEXTURE, uv - vec2(split, 0.0));
	// Alpha-weighted channels prevent transparent texels becoming opaque streaks.
	vec3 separated = vec3(left.r * left.a, source.g * source.a, right.b * right.a);
	float alpha = max(source.a, max(left.a, right.a) * active);
	vec3 color = mix(source.rgb, separated / max(alpha, 0.001), active * 0.9);
	// The stable block mask erases from bottom to top; time only jitters the slices.
	vec2 cell = floor(UV * vec2(29.0, 43.0));
	float threshold = (1.0 - UV.y) * 0.72 + hash21(cell) * 0.28;
	float cut = progress * 1.18 - 0.08;
	float surviving = smoothstep(cut - 0.018, cut + 0.018, threshold);
	float rim = (1.0 - smoothstep(0.016, 0.075, abs(threshold - cut))) * active;
	vec3 neon = mix(cyan.rgb, pink.rgb, step(0.52, hash21(vec2(band, tick + 4.0))));
	color = mix(color, neon, rim * 0.92);
	color += neon * step(0.90, noise) * active * 0.25;
	float scan = 1.0 - step(0.80, fract(UV.y * 137.0)) * active * 0.26;
	COLOR = vec4(color * scan, alpha * surviving * (1.0 - step(0.999, progress)));
}
