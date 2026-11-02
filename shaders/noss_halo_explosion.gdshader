shader_type canvas_item;
render_mode blend_add, unshaded;

// Local, finite animation clock. No scene texture, external art or global TIME.
uniform float blast_age = 0.0;
uniform float lifetime = 0.72;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(cell), hash21(cell + vec2(1.0, 0.0)), u.x),
		mix(hash21(cell + vec2(0.0, 1.0)), hash21(cell + vec2(1.0)), u.x), u.y);
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r = length(p);
	float angle = atan(p.y, p.x);
	float age = max(blast_age, 0.0);
	float t = clamp(age / lifetime, 0.0, 1.0);
	float remaining = pow(1.0 - t, 1.7);
	float flash = exp(-age * 19.0);
	float heat = exp(-age * 7.5);
	float expansion = 1.0 - exp(-age * 18.0);
	float turbulence = noise2(p * 9.0 + vec2(age * 3.0, -age * 4.0));
	turbulence += noise2(p * 21.0 - vec2(age * 6.0)) * 0.45;
	float lobes = 1.0 + 0.12 * sin(angle * 7.0 + 0.7) + 0.07 * sin(angle * 13.0);
	float core_radius = mix(0.13, 0.34, expansion) * lobes;
	float core = exp(-pow(r / core_radius, 3.0)) * heat * (1.8 + turbulence * 1.5);
	float corona = exp(-r * r / 0.24) * heat * (0.45 + turbulence * 0.45);
	float spokes = pow(max(0.0, sin(angle * 17.0 + sin(angle * 5.0))), 32.0);
	spokes += pow(max(0.0, cos(angle * 11.0 + 1.7)), 48.0) * 0.55;
	float rays = spokes * exp(-r * 3.6) * heat * 1.7;
	float cross_light = (exp(-abs(p.y) * 85.0) * exp(-abs(p.x) * 2.4)
		+ exp(-abs(p.x) * 120.0) * exp(-abs(p.y) * 3.6)) * flash * 2.6;
	float front = mix(0.14, 0.88, 1.0 - pow(1.0 - t, 3.0));
	float wave_distance = abs(r - front);
	float shock = exp(-pow(wave_distance / 0.022, 2.0)) * remaining * 1.1;
	shock += exp(-pow(wave_distance / 0.075, 2.0)) * remaining * 0.25;
	float echo_front = max(0.0, front - 0.095);
	float echo = exp(-pow(abs(r - echo_front) / 0.010, 2.0)) * remaining * 0.40;
	float edge = 1.0 - smoothstep(0.86, 1.0, r);
	vec3 gold = vec3(1.0, 0.89, 0.34);
	vec3 ivory = vec3(1.0, 1.0, 0.94);
	vec3 light = ivory * (core + cross_light) + gold * (corona + rays + shock + echo);
	COLOR = vec4(light * edge, 1.0);
}
