shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform bool piercing = false;
uniform bool impact_only = false;
uniform sampler2D opacity_reference : filter_linear_mipmap, repeat_disable;
varying vec4 sprite_color;

void vertex() {
	// Preserve draw_texture_rect / Sprite2D modulation exactly once.
	sprite_color = COLOR;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float alpha = source.a;
	vec3 mapped;
	if (piercing) {
		// Keep both new holes and the airy interior from the reference; never fill either.
		alpha = min(alpha, texture(opacity_reference, UV).a);
		float body = smoothstep(0.05, 0.85, source.r);
		vec3 ink = mix(vec3(0.018, 0.022, 0.032), vec3(0.105, 0.122, 0.153), body);
		// The source's pale hairline highlights have G/B; its broad red body does not.
		float highlight = smoothstep(0.18, 0.68, max(source.g, source.b));
		mapped = mix(ink, vec3(1.0, 1.05, 1.12), highlight * 0.96);
	} else {
		// Reuse the full diagonal cut/burst mask, with separate fixed-contact layers.
		vec2 local = (UV - vec2(0.62, 0.59)) / vec2(0.115, 0.22);
		float region = 1.0 - smoothstep(0.78, 1.0, length(local));
		float fine_cut = (1.0 - smoothstep(0.018, 0.028, abs(UV.y - (0.825 - 0.394 * UV.x))))
			* smoothstep(0.13, 0.16, UV.x);
		float broad_cut = (1.0 - smoothstep(0.045, 0.075, abs(UV.y - (0.730 - 0.210 * UV.x))))
			* smoothstep(0.29, 0.34, UV.x);
		float strike = max(region, max(fine_cut, broad_cut));
		alpha *= impact_only ? strike : 1.0 - strike;
		float energy = max(source.r, max(source.g, source.b));
		float body = smoothstep(0.025, 0.42, energy);
		// Source dark trails become cold contours; red body becomes layered white/gray.
		mapped = mix(vec3(0.065, 0.082, 0.108), vec3(1.14, 1.18, 1.24), body);
		float highlight = smoothstep(0.22, 0.72, max(source.g, source.b));
		mapped = mix(mapped, vec3(1.45), highlight);
	}
	COLOR = vec4(mapped * sprite_color.rgb, alpha * sprite_color.a);
}
