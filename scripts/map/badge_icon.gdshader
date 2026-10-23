shader_type canvas_item;
render_mode unshaded;

// Supplied black silhouettes act as alpha masks; state color comes from modulate.
uniform bool boss_effect = false;
varying vec4 state_tint;

void vertex() {
	state_tint = COLOR;
}

void fragment() {
	vec2 uv = UV;
	vec3 tint = state_tint.rgb;
	if (boss_effect) {
		float tick = floor(TIME * 9.0);
		float band = floor(UV.y * 9.0);
		float burst = step(0.82, fract(sin(tick * 17.13 + band * 41.7) * 43758.5));
		uv.x += sin(tick + band) * burst * 0.055;
		tint = 0.62 + 0.38 * cos(vec3(0.0, 2.094, 4.189) + TIME * 2.0 + UV.y * 5.0);
		tint = mix(tint, vec3(1.0), burst * 0.28);
	}
	COLOR = vec4(tint, texture(TEXTURE, uv).a * state_tint.a);
}
