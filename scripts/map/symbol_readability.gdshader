shader_type canvas_item;
// 提亮导入符号的暗部，保留建筑明暗与透明边缘；不改源图片。
uniform float lift : hint_range(0.0, 0.6) = 0.36;
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec3 bright = mix(source.rgb, vec3(1.0), lift);
	COLOR = vec4(bright, source.a) * tint;
}
