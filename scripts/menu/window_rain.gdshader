shader_type canvas_item;
// 小面积窗外细雨，百叶横条不绘雨。由菜单可暂停时钟控制。
uniform float clock = 0.0;

float hash(float value) {
	return fract(sin(value * 127.1) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float column = floor((uv.x + uv.y * 0.075) * 19.0);
	float seed = hash(column);
	float x = fract((uv.x + uv.y * 0.075) * 19.0);
	float head = fract(uv.y * 2.0 + clock * (0.40 + seed * 0.35) + seed);
	float streak = (1.0 - smoothstep(0.025, 0.12, abs(x - 0.5)))
		* smoothstep(0.60, 0.91, head) * (1.0 - smoothstep(0.94, 1.0, head));
	float slats = smoothstep(0.29, 0.46, fract(uv.y * 7.0));
	float inset = smoothstep(0.0, 0.05, uv.x) * (1.0 - smoothstep(0.95, 1.0, uv.x));
	COLOR = vec4(0.55, 0.84, 0.94, streak * slats * inset * 0.30);
}
