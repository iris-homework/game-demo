shader_type canvas_item;
render_mode unshaded;

// Preserve the map geometry. Reconstruct enlarged texels with Catmull-Rom;
// keep mipmapped linear sampling for minification to avoid shimmering.
varying vec4 vertex_tint;

void vertex() {
	vertex_tint = COLOR;
}

vec4 cubic_weights(float t) {
	float t2 = t * t;
	float t3 = t2 * t;
	return vec4(-0.5 * t + t2 - 0.5 * t3,
		1.0 - 2.5 * t2 + 1.5 * t3,
		0.5 * t + 2.0 * t2 - 1.5 * t3,
		-0.5 * t2 + 0.5 * t3);
}

void fragment() {
	vec2 pixel = UV / TEXTURE_PIXEL_SIZE;
	float footprint = max(length(dFdx(pixel)), length(dFdy(pixel)));
	vec4 linear_color = texture(TEXTURE, UV);
	vec4 result = linear_color;
	if (footprint < 1.0) {
		vec2 position = pixel - 0.5;
		vec2 base = floor(position);
		vec2 fraction = fract(position);
		vec4 wx = cubic_weights(fraction.x);
		vec4 wy = cubic_weights(fraction.y);
		vec4 cubic = vec4(0.0);
		vec4 low = vec4(1.0);
		vec4 high = vec4(0.0);
		for (int y = 0; y < 4; y++) {
			for (int x = 0; x < 4; x++) {
				vec2 sample_uv = (base + vec2(float(x - 1), float(y - 1)) + 0.5) * TEXTURE_PIXEL_SIZE;
				sample_uv = clamp(sample_uv, TEXTURE_PIXEL_SIZE * 0.5, vec2(1.0) - TEXTURE_PIXEL_SIZE * 0.5);
				vec4 texel = textureLod(TEXTURE, sample_uv, 0.0);
				cubic += texel * wx[x] * wy[y];
				if (x >= 1 && x <= 2 && y >= 1 && y <= 2) {
					low = min(low, texel);
					high = max(high, texel);
				}
			}
		}
		// Bound interpolation overshoot around bright neon and dark outlines.
		result = mix(linear_color, clamp(cubic, low, high), 1.0 - smoothstep(0.8, 1.0, footprint));
	}
	COLOR = result * vertex_tint;
}
