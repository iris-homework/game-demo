shader_type canvas_item;
render_mode unshaded;

// Opening-transition palette and stepped noise, scaled to each individual slot.
uniform float phase = 0.0;
uniform float seed = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }

void fragment() {
	float tick = floor(phase * 18.0);
	float row = floor(UV.y * 6.0);
	float noise = hash(vec2(row + seed * 3.1, tick));
	float shift = (noise - 0.5) * 0.20;
	float column = floor((UV.x + shift) * 10.0);
	float block = hash(vec2(column + seed * 13.0, row + tick));
	float band = mod(row + floor(tick * 0.3) + seed, 3.0);
	vec3 cyan = vec3(0.04,0.90,0.94);
	vec3 pink = vec3(0.92,0.10,0.56);
	vec3 violet = vec3(0.49,0.25,1.0);
	vec3 neon = band < 1.0 ? cyan : (band < 2.0 ? pink : violet);
	vec3 color = neon * (0.65 + 0.35 * step(0.42, block));
	// Broken dark blocks, RGB fringes and fine scan lines replace a smooth rainbow.
	color = mix(color, vec3(0.025,0.025,0.075), step(0.90, block) * 0.85);
	float split_edge = step(0.84,fract((UV.x + shift) * 6.0));
	color = mix(color, band < 1.0 ? pink : cyan, split_edge * 0.42);
	color *= 0.76 + 0.24 * step(0.18,fract(UV.y * 6.0));
	float fragment = step(0.95, hash(vec2(column + tick, row + seed)));
	color = mix(color, vec3(0.85,0.96,1.0), fragment * 0.72);
	COLOR = vec4(color,1.0);
}
