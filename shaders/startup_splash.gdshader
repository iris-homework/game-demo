shader_type canvas_item;
render_mode unshaded;

uniform float timeline : hint_range(0.0, 3.0) = 0.0;
uniform sampler2D title_texture : filter_linear, repeat_disable;

const vec2 CANVAS = vec2(1440.0, 900.0);
// Screen Y points down: this blade travels from lower left to upper right.
const vec2 BLADE = vec2(0.8660254, -0.5);
const vec2 CUT_NORMAL = vec2(0.5, 0.8660254);
const vec3 BACKDROP = vec3(0.02745098, 0.02352941, 0.06274510);
const vec3 CYAN = vec3(0.25, 0.96, 1.0);
const vec3 PINK = vec3(1.0, 0.15, 0.47);

vec3 curtain_sample(vec2 point) {
	vec2 uv = point / CANVAS + vec2(0.5);
	vec3 ink = texture(title_texture, clamp(uv, vec2(0.0), vec2(1.0))).rgb;
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	// Sampling offset affects only the title's short split/glitch. The backdrop
	// dissolves in place; extending it avoids a rectangular sampling boundary.
	return mix(BACKDROP, ink, inside);
}

float hash_cell(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 point = (UV - vec2(0.5)) * CANVAS;
	float normal_distance = dot(point, CUT_NORMAL);
	float along = dot(point, BLADE);
	float nick = smoothstep(1.67, 1.87, timeline);
	float dissolve = clamp((timeline - 1.67) / 1.27, 0.0, 1.0);
	float settle = 1.0 - smoothstep(2.80, 3.0, timeline);
	// The wave travels outwards from the slash, while row/block noise breaks its
	// boundary into small horizontal fragments instead of two geometric curtains.
	float row = floor((point.y + 450.0) / 7.0);
	float row_offset = hash_cell(vec2(row, 9.0)) * 57.0;
	vec2 cell = vec2(floor((point.x + 720.0 + row_offset) / 83.0), row);
	vec2 coarse = floor((point + CANVAS * 0.5) / vec2(177.0, 29.0));
	float fine_noise = hash_cell(cell);
	float coarse_noise = hash_cell(coarse + vec2(41.0, 13.0));
	float irregularity = ((fine_noise - 0.5) * 49.0 + (coarse_noise - 0.5) * 61.0) * nick;
	float wave = -5.0 + 890.0 * pow(dissolve, 0.92);
	float passed = wave - abs(normal_distance) + irregularity;
	float cover = (1.0 - smoothstep(-1.5, 2.5, passed)) * settle;
	float front_zone = exp(-abs(passed) / 48.0) * nick;
	float flicker = hash_cell(cell + vec2(floor(timeline * 24.0), 73.0));
	float glitch_shift = (fine_noise - 0.5) * 48.0 * front_zone * step(0.40, flicker);
	// A slight split remains in the lettering, but there is no outward translation
	// of the dark screen. Each region is erased exactly where it was drawn.
	float side = mix(-1.0, 1.0, step(0.0, normal_distance));
	vec2 source = point - side * (CUT_NORMAL * 8.0 + BLADE * 12.0) * nick;
	source.x += glitch_shift;
	vec3 premultiplied = curtain_sample(source) * cover;

	// A narrow white blade with cyan halo and a short, offset magenta afterimage.
	float sweep = clamp((timeline - 1.50) / 0.15, 0.0, 1.0);
	float head = mix(-980.0, 980.0, sweep);
	float behind = head - along;
	float tail = smoothstep(-8.0, 5.0, behind) * (1.0 - smoothstep(100.0, 570.0, behind));
	float active = step(1.50, timeline) * (1.0 - smoothstep(1.65, 1.83, timeline));
	float white_blade = exp(-pow(normal_distance / 1.35, 2.0)) * tail * active;
	float cyan_blade = exp(-abs(normal_distance) / 9.0) * tail * active * 0.60;
	float pink_trail = exp(-pow((normal_distance - 4.0) / 2.0, 2.0)) * tail * active * 0.55;
	// A visibly wider neon fringe breaks into horizontal chips at the erasing
	// front. Irregular cells keep it fragmented instead of a straight light bar.
	float local_x = mod(point.x + 720.0 + row_offset, 83.0);
	float local_y = mod(point.y + 450.0, 7.0);
	float bar_width = mix(13.0, 61.0, hash_cell(cell + vec2(5.0, 8.0)));
	float bar = step(3.0, local_x) * (1.0 - step(bar_width, local_x));
	bar *= 1.0 - smoothstep(2.8, 4.4, local_y);
	bar *= step(0.48, fine_noise) * step(0.20, flicker);
	float residue_life = exp(-max(passed, 0.0) / 68.0) * smoothstep(-33.0, 2.0, passed);
	float residue = bar * residue_life * nick * settle * 0.78;
	float neon_fringe = front_zone * settle * (0.22 + 0.78 * step(0.40, fine_noise));
	neon_fringe *= (0.50 + 0.50 * step(0.24, flicker)) * 0.58;
	vec3 residue_color = mix(CYAN, PINK, step(0.52, hash_cell(cell + vec2(25.0, 12.0))));
	// RGB ghosting follows actual title pixels, never paints a solid neon band.
	vec3 cyan_sample = max(curtain_sample(source + vec2(17.0, 0.0)) - BACKDROP, vec3(0.0));
	vec3 pink_sample = max(curtain_sample(source - vec2(21.0, 0.0)) - BACKDROP, vec3(0.0));
	float ghost_window = residue_life * nick * settle * step(0.28, flicker);
	float cyan_ghost = clamp(max(cyan_sample.r, max(cyan_sample.g, cyan_sample.b)), 0.0, 1.0) * ghost_window * 0.42;
	float pink_ghost = clamp(max(pink_sample.r, max(pink_sample.g, pink_sample.b)), 0.0, 1.0) * ghost_window * 0.34;
	vec3 effects = vec3(0.92, 1.0, 1.0) * white_blade + CYAN * cyan_blade + PINK * pink_trail;
	effects += residue_color * (residue + neon_fringe) + CYAN * cyan_ghost + PINK * pink_ghost;
	float effect_alpha = clamp(white_blade + cyan_blade + pink_trail + residue + neon_fringe + cyan_ghost + pink_ghost, 0.0, 1.0);
	float alpha = max(cover, effect_alpha);
	// Straight alpha output also preserves the thin glow inside the open gap.
	COLOR = vec4((premultiplied + effects) / max(alpha, 0.0001), alpha);
}
