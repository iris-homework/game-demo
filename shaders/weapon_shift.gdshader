shader_type canvas_item;
render_mode unshaded;

// Apply to the entire transparent actor sprite, including the weapon.
uniform float progress = 0.0;
uniform float visibility = 1.0;
uniform float intensity = 0.0;
uniform float layer = 0.0;
varying vec4 vertex_tint;

void vertex() {
	vertex_tint = COLOR;
}

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

float inside_texture(vec2 uv) {
	return step(0.0,uv.x)*step(uv.x,1.0)*step(0.0,uv.y)*step(uv.y,1.0);
}

void fragment() {
	float band = floor(UV.y * 54.0);
	float tick = floor(progress * 32.0);
	float noise = hash(band + tick * 11.7);
	vec3 cyan = vec3(0.12,0.95,1.0);
	vec3 pink = vec3(1.0,0.10,0.55);
	vec3 neon = mix(cyan,pink,step(0.5,noise));
	if (layer == 0.0) {
		float offset = (noise-0.5)*0.028*intensity;
		vec2 source_uv = UV-vec2(offset,0.0);
		vec4 original = texture(TEXTURE,source_uv);
		float threshold = clamp(1.0-UV.y,0.08,0.92);
		float reveal = smoothstep(threshold-0.08,threshold+0.08,visibility);
		float scan = step(0.76,noise);
		vec3 color = mix(original.rgb,neon,intensity*(0.25+scan*0.65));
		COLOR = vec4(color,original.a*reveal*inside_texture(source_uv))*vertex_tint;
	} else {
		float offset = layer*(0.012+noise*0.020)*intensity;
		vec2 source_uv = UV-vec2(offset,layer*0.003*intensity);
		vec4 echo = texture(TEXTURE,source_uv);
		float slices = step(0.40,hash(band+tick*8.1+layer*3.0));
		vec3 glow = layer < 0.0 ? cyan : pink;
		COLOR = vec4(glow,echo.a*slices*intensity*0.68*inside_texture(source_uv))*vertex_tint;
	}
}
