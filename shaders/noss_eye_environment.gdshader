shader_type canvas_item;
render_mode unshaded;

uniform float ambient_time = 0.0;
uniform float glitch_strength = 0.0;
uniform bool wall_mode = false;
uniform float floor_horizon = 402.0;

float hash11(float n) {
	return fract(sin(n*127.1+19.3)*43758.5453);
}

void fragment() {
	vec2 p = UV*vec2(1440.0,900.0);
	// The original scenery remains underneath. Expose its existing perspective floor.
	float floor_mix = wall_mode ? smoothstep(floor_horizon-20.0,floor_horizon+50.0,p.y) : 0.0;
	float alpha = mix(1.0,0.30,floor_mix);
	vec3 color = mix(vec3(0.0),vec3(0.008,0.009,0.022),floor_mix);
	float wall_mask = 1.0-smoothstep(floor_horizon-50.0,floor_horizon+15.0,p.y);
	if (!wall_mode) wall_mask = 1.0-smoothstep(640.0,880.0,p.y);
	float cycle = floor(ambient_time/5.2);
	float jitter = floor(ambient_time*24.0);
	vec3 bars = vec3(0.0);
	for (int i=0;i<12;i++) {
		float seed = float(i)*19.7+cycle*13.1;
		float center_y = 55.0+hash11(seed+2.0)*(wall_mode ? floor_horizon-90.0 : 620.0);
		float left = -90.0+hash11(seed+5.0)*1330.0;
		float width = 95.0+hash11(seed+7.0)*390.0;
		float height = 2.0+hash11(seed+11.0)*9.0;
		left += (hash11(jitter+seed)-0.5)*32.0;
		float strip = step(left,p.x)*step(p.x,left+width)*step(abs(p.y-center_y),height*0.5);
		float ghost = step(left+17.0,p.x)*step(p.x,left+width+35.0)*step(abs(p.y-center_y-3.0),1.0);
		float cut = step(0.14,hash11(floor((p.x-left)/26.0)+seed+jitter));
		vec3 tint = mod(float(i),3.0)<1.0 ? vec3(0.08,0.95,1.0) : vec3(1.0,0.06,0.50);
		if (mod(float(i),3.0)>1.5) tint = vec3(0.62,0.33,1.0);
		bars += tint*(strip*cut+ghost*0.35);
	}
	color += min(bars,vec3(1.0))*glitch_strength*wall_mask*0.78;
	COLOR = vec4(color,alpha);
}
