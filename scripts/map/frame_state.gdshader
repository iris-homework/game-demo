shader_type canvas_item;
// 深色实底与加宽的状态亮边隔开城市纹理，保留原始切角透明轮廓。
uniform float hover_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 edge_color : source_color = vec4(1.0);
uniform vec4 plate_color : source_color = vec4(0.055, 0.075, 0.12, 1.0);

float edge_at(vec4 sample_color) {
	return smoothstep(0.16, 0.35, max(sample_color.r, max(sample_color.g, sample_color.b))) * sample_color.a;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec2 step_uv = vec2(1.0 / 64.0, 1.0 / 72.0);
	float edge = edge_at(source);
	edge = max(edge, edge_at(texture(TEXTURE, UV + vec2(step_uv.x, 0.0))));
	edge = max(edge, edge_at(texture(TEXTURE, UV - vec2(step_uv.x, 0.0))));
	edge = max(edge, edge_at(texture(TEXTURE, UV + vec2(0.0, step_uv.y))));
	edge = max(edge, edge_at(texture(TEXTURE, UV - vec2(0.0, step_uv.y))));
	vec3 base = mix(plate_color.rgb, edge_color.rgb, edge);
	vec3 lit = mix(base, vec3(1.0), hover_amount * mix(0.06, 0.22, edge));
	COLOR = vec4(lit, source.a * edge_color.a);
}
