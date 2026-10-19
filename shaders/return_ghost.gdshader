shader_type canvas_item;
render_mode unshaded, blend_add;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 neon_color : source_color = vec4(0.2, 1.0, 0.9, 1.0);
uniform float seed = 0.0;
uniform bool white_key_enabled = false;
float hash(float value) {
	return fract(sin(value * 127.1 + 311.7) * 43758.5453);
}
float silhouette(vec4 sample_color) {
	float paper = min(sample_color.r, min(sample_color.g, sample_color.b));
	float coverage = white_key_enabled ? 1.0 - smoothstep(0.90, 0.98, paper) : 1.0;
	return sample_color.a * coverage;
}
void fragment() {
	float tick = floor(progress * 20.0);
	float band = floor(UV.y * 38.0);
	float disruption = 1.0 - smoothstep(0.30, 0.94, progress);
	float shift = (hash(band + tick * 7.0 + seed) - 0.5) * 0.065 * disruption;
	vec2 sample_uv = UV + vec2(shift, 0.0);
	float mask = silhouette(texture(TEXTURE, sample_uv));
	float rim = abs(silhouette(texture(TEXTURE, sample_uv + vec2(0.004, 0.0))) - silhouette(texture(TEXTURE, sample_uv - vec2(0.004, 0.0))));
	float slices = mix(0.25, 1.0, step(0.24, hash(band * 3.0 + tick + seed)));
	float scan = 0.70 + 0.30 * sin(UV.y * 750.0 + tick);
	float entrance = smoothstep(0.0, 0.08, progress);
	float dissolve = 1.0 - smoothstep(0.42, 1.0, progress);
	vec3 hue = mix(neon_color.rgb, vec3(0.62, 0.40, 1.0), UV.y * 0.35);
	COLOR = vec4(hue + vec3(rim * 0.35), clamp(mask * slices * scan + rim * 0.40, 0.0, 1.0) * entrance * dissolve * neon_color.a);
}
