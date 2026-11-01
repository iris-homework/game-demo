shader_type canvas_item;
render_mode unshaded;

// A soft gold silhouette with a narrow white highlight, without a dark border.
uniform vec4 gold : source_color = vec4(1.0, 0.76, 0.18, 1.0);

void fragment() {
	vec2 p = (UV - vec2(0.5)) * vec2(72.0, 88.0);
	vec2 q = abs(p - vec2(0.0, 6.0)) - vec2(7.0, 17.0);
	float stem = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0);
	float slope = 20.0 / 21.0;
	float head = max(max((abs(p.x) - (p.y + 26.0) * slope) / sqrt(1.0 + slope * slope), -26.0 - p.y), p.y + 5.0);
	float distance_to_arrow = min(stem, head);
	float silhouette = 1.0 - smoothstep(-2.0, 4.5, distance_to_arrow);
	float halo = exp(-pow(max(distance_to_arrow, 0.0) / 6.0, 2.0));
	float highlight = exp(-pow((p.x + 1.0) / 2.5, 2.0)) * 0.85 * silhouette;
	COLOR = vec4(mix(gold.rgb, vec3(1.0), highlight), (0.64 * silhouette + 0.12 * halo) * COLOR.a);
}
