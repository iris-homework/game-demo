shader_type canvas_item;
// 地图当前位置头像：从既有立绘中裁出头肩区域，运行时去除白底并做圆形遮罩。
// 原始 PNG 不做任何修改，只改变这一处渲染结果。

uniform vec2 region_origin = vec2(0.0);
uniform vec2 region_size = vec2(1.0);
uniform float edge_radius : hint_range(0.25, 3.0) = 1.2;
uniform float circle_feather : hint_range(0.01, 0.25) = 0.06;
uniform float white_key : hint_range(0.0, 1.0) = 1.0;
uniform float zoom : hint_range(0.5, 2.0) = 1.0;

varying vec4 tint;

float paper_value(vec3 color) {
	return min(color.r, min(color.g, color.b));
}

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec2 centered = clamp((UV - vec2(0.5)) * zoom + vec2(0.5), vec2(0.0), vec2(1.0));
	vec2 uv = region_origin + centered * region_size;
	vec4 c = texture(TEXTURE, uv);
	float value = paper_value(c.rgb);
	float darkest = value;
	float lightest = value;
	vec2 step_uv = TEXTURE_PIXEL_SIZE * edge_radius;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			float neighbor = paper_value(texture(TEXTURE, uv + vec2(float(x), float(y)) * step_uv).rgb);
			darkest = min(darkest, neighbor);
			lightest = max(lightest, neighbor);
		}
	}
	float coverage = clamp((1.0 - value) / max(1.0 - darkest, 0.001), 0.0, 1.0);
	float edge = smoothstep(0.92, 0.99, lightest);
	float matte_alpha = 1.0 - smoothstep(0.90, 0.98, value);
	float a = mix(matte_alpha, coverage * matte_alpha, edge);
	a = mix(1.0, a, white_key);
	float circle = 1.0 - smoothstep(1.0 - circle_feather, 1.0, length(UV * 2.0 - 1.0));
	vec3 clean = clamp((c.rgb - vec3(1.0 - a)) / max(a, 0.001), vec3(0.0), vec3(1.0));
	COLOR = vec4(clean, c.a * a * circle) * tint;
}

