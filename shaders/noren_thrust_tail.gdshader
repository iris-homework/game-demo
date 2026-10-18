shader_type canvas_item;
render_mode unshaded;

uniform float front_thickness = 0.65;
uniform float tail_thickness = 2.4;
varying vec4 sprite_color;

void vertex() {
	sprite_color = COLOR;
}

void fragment() {
	// The source points left: a slim leading section widens toward the rear.
	float center_y = 0.51;
	float tail = smoothstep(0.22, 0.88, UV.x);
	float near_body = 1.0 - smoothstep(0.12, 0.25, abs(UV.y - center_y));
	float profile = mix(front_thickness, tail_thickness, tail);
	float width = mix(1.0, profile, near_body);
	vec2 source_uv = vec2(UV.x, center_y + (UV.y - center_y) / width);
	COLOR = texture(TEXTURE, source_uv) * sprite_color;
}
