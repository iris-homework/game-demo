shader_type canvas_item;
render_mode unshaded;

uniform bool impact_only = false;

void fragment() {
	// Move the complete diagonal cut and contact burst together, not just white pixels.
	vec2 local = (UV - vec2(0.62, 0.59)) / vec2(0.115, 0.22);
	float region = 1.0 - smoothstep(0.78, 1.0, length(local));
	float fine_cut = (1.0 - smoothstep(0.018, 0.028, abs(UV.y - (0.825 - 0.394 * UV.x))))
		* smoothstep(0.13, 0.16, UV.x);
	float broad_cut = (1.0 - smoothstep(0.045, 0.075, abs(UV.y - (0.730 - 0.210 * UV.x))))
		* smoothstep(0.29, 0.34, UV.x);
	float strike = max(region, max(fine_cut, broad_cut));
	COLOR.a *= impact_only ? strike : 1.0 - strike;
}
