shader_type canvas_item;
render_mode unshaded;

// Vertex RGBA is data, not tint: seed, opening order, depth, artwork aspect.
// A single cached quad mesh; no per-eye materials, scene reads, textures or TIME.
uniform float reveal_progress : hint_range(0.0, 1.0) = 0.0;
uniform float ambient_time = 0.0;
uniform bool wall_mode = false;
uniform float floor_horizon = 402.0;
uniform vec2 gaze_position = vec2(720.0, 280.0);
// The first five authored anchors only: center XY and rotation cosine/sine.
uniform vec4 tracking_frames[5];
uniform vec4 summary_region = vec4(0.0);
uniform vec4 intent_region = vec4(0.0);
varying vec4 eye_data;
varying vec2 artwork_position;
varying vec2 gaze_offset;

void vertex() {
	eye_data = COLOR;
	artwork_position = VERTEX.xy;
	gaze_offset = vec2(0.0);
	// Opening ranks of the five anchors precede the shuffled crowd.
	float order = COLOR.g * 81.0 / 0.935;
	if (wall_mode && order < 4.5) {
		int index = int(clamp(floor(order + 0.5), 0.0, 4.0));
		vec4 frame = tracking_frames[index];
		vec2 direction = (gaze_position - frame.xy) / vec2(480.0, 300.0);
		direction /= max(1.0, length(direction));
		vec2 local_direction = vec2(dot(direction, frame.zw), dot(direction, vec2(-frame.w, frame.z)));
		gaze_offset = local_direction * vec2(0.18, 0.10);
	}
}

float quiet_region(vec2 point, vec4 region) {
	if (region.z <= 0.0 || region.w <= 0.0) return 0.0;
	vec2 distance_to_box = max(abs(point - region.xy - region.zw * 0.5) - region.zw * 0.5, vec2(0.0));
	return 1.0 - smoothstep(4.0, 56.0, length(distance_to_box));
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
	vec2 iris_p = vec2(p.x-gaze_offset.x, (p.y-gaze_offset.y) * eye_data.a);
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
	if (wall_mode) {
		float order = eye_data.g * 81.0 / 0.935;
		float hierarchy = order < 4.5 ? 0.92 : (order < 26.5 ? 0.58 : 0.34);
		float quiet = max(quiet_region(artwork_position, summary_region), quiet_region(artwork_position, intent_region));
		brightness *= hierarchy * mix(1.0, 0.25, quiet);
	}
	color *= brightness;
	// Let the lowest eyes sink into the same dark depth falloff as the floor.
	float horizon = floor_horizon + sin(artwork_position.x*0.006+0.8)*4.0 + sin(artwork_position.x*0.017)*1.5;
	float wall_mask = wall_mode ? 1.0-smoothstep(horizon-96.0,horizon+24.0,artwork_position.y) : 1.0;
	COLOR = vec4(color, outer * visibility * wall_mask);
}
