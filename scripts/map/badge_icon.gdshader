shader_type canvas_item;
render_mode unshaded;

// Supplied black silhouettes act as alpha masks; state color comes from modulate.
varying vec4 state_tint;

void vertex() {
	state_tint = COLOR;
}

void fragment() {
	COLOR = vec4(state_tint.rgb, texture(TEXTURE, UV).a * state_tint.a);
}
