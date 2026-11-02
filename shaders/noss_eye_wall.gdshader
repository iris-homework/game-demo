shader_type canvas_item;
render_mode unshaded;

// Vertex RGBA is data, not tint: seed, opening order, depth, artwork aspect.
// A single cached quad mesh; no per-eye materials, scene reads, textures or TIME.
uniform float reveal_progress : hint_range(0.0, 1.0) = 0.0;
uniform float ambient_time = 0.0;
uniform bool wall_mode = false;
uniform float floor_horizon = 402.0;
varying vec4 eye_data;
varying vec2 artwork_position;

void vertex() {
	eye_data = COLOR;
	artwork_position = VERTEX.xy;
}

float hash11(float n) {
	return fract(sin(n * 127.1 + 19.3) * 43758.5453);
}

vec3 spectrum(float h) {
	vec3 rgb = clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	return mix(vec3(0.19), rgb, 0.88);
}

void fragment() {
	float seed = eye_data.r;
	float phase = seed * 71.7;
	float clock = pow(clamp(reveal_progress, 0.0, 1.0), 2.25);
	float opened = smoothstep(eye_data.g, eye_data.g + 0.058, clock);
	// First eye takes ~1.1 s; later witnesses arrive increasingly close together.
	float period = 5.8 + hash11(seed + 4.2) * 7.0;
	float blink_phase = mod(ambient_time + phase, period);
	float blink = 1.0 - 0.93 * (1.0 - smoothstep(0.0, 0.13, abs(blink_phase - 0.15)));
	float aperture = opened * blink * (0.97 + 0.03 * sin(ambient_time * 0.73 + phase));
	vec2 p = (UV - vec2(0.5)) * 2.0;
	// Icon reference in colored linework: almond contour and circular rings.
	// All enclosed areas stay black. The small pupil has no highlight or reflection.
	float x = p.x;
	float arch = max(0.0, 1.0 - x*x);
	float upper = -arch * 0.85 * aperture;
	float lower = arch * 0.85 * aperture;
	float signed_lid = min(p.y - upper, lower - p.y);
	float aa = max(fwidth(signed_lid), 0.008);
	float outer = smoothstep(-aa, aa, signed_lid);
	outer *= 1.0 - smoothstep(0.985, 1.0, abs(x));
	float inside = smoothstep(0.125 - aa, 0.125 + aa, signed_lid);
	float visibility = smoothstep(0.0, 0.065, opened);
	vec3 hue = spectrum(fract(seed * 8.37 + 0.07));
	vec3 line_color = mix(hue, vec3(1.0), 0.13);
	// Artwork quads are wider than tall. Correct that aspect for circular rings.
	vec2 iris_p = vec2(p.x, p.y * eye_data.a);
	float radius = length(iris_p);
	float iris_radius = eye_data.a * 0.80;
	float ring_outer = 1.0 - smoothstep(iris_radius-0.006, iris_radius+0.006, radius);
	float ring_inner = 1.0 - smoothstep(iris_radius*0.72-0.006, iris_radius*0.72+0.006, radius);
	float pupil_outer = 1.0 - smoothstep(iris_radius*0.28-0.005, iris_radius*0.28+0.005, radius);
	float pupil_inner = 1.0 - smoothstep(iris_radius*0.20-0.005, iris_radius*0.20+0.005, radius);
	float iris_line = ring_outer * (1.0-ring_inner);
	float pupil_line = pupil_outer * (1.0-pupil_inner);
	float contour = 1.0-inside;
	float line_mask = max(contour,max(iris_line,pupil_line));
	vec3 color = line_color * line_mask;
	float brightness = mix(0.74, 1.13, eye_data.b);
	float lower_fade = 1.0 - smoothstep(460.0, 895.0, artwork_position.y);
	float side = smoothstep(250.0, 630.0, abs(artwork_position.x - 720.0));
	float background_dimming = mix(0.10, 0.72, lower_fade) + side * 0.06;
	brightness *= wall_mode ? background_dimming : mix(0.60, 1.0, lower_fade);
	color *= brightness;
	float wall_mask = wall_mode ? 1.0-smoothstep(floor_horizon-42.0,floor_horizon+10.0,artwork_position.y) : 1.0;
	COLOR = vec4(color, outer * visibility * wall_mask);
}
