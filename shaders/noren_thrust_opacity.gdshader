shader_type canvas_item;
render_mode unshaded;

uniform sampler2D opacity_reference : filter_linear_mipmap, repeat_disable;
varying vec4 sprite_color;

void vertex() {
	sprite_color = COLOR;
}

void fragment() {
	vec4 cleaned = texture(TEXTURE, UV);
	// Keep the airy interior from the previous sprite after removing its glints.
	// New holes stay transparent; the edit may never refill existing soft areas.
	cleaned.a = min(cleaned.a, texture(opacity_reference, UV).a);
	COLOR = cleaned * sprite_color;
}
