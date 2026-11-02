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
	// A broad dark depth falloff joins the wall to the original perspective floor.
	// Small, static irregularities avoid a ruler-straight fog band without moving it.
	float horizon = floor_horizon + sin(p.x*0.006+0.8)*4.0 + sin(p.x*0.017)*1.5;
	// Keep the source illustration's wall/columns fully covered above its floor.
	float floor_mix = wall_mode ? smoothstep(horizon+6.0,horizon+146.0,p.y) : 0.0;
	float alpha = mix(1.0,0.30,floor_mix);
	vec3 color = mix(vec3(0.0),vec3(0.008,0.009,0.022),floor_mix);
	// Inlaid gold follows the floor's vanishing point; never appears in dialogue.
	if (wall_mode) {
		float depth = max(p.y-floor_horizon+38.0,1.0);
		float projected_x = (p.x-720.0)*240.0/depth;
		float ray_distance = abs(mod(projected_x+80.0,160.0)-80.0)*depth/240.0;
		float accent_distance = abs(mod(projected_x+68.0,160.0)-80.0)*depth/240.0;
		float line_width = mix(0.7,2.0,clamp(depth/480.0,0.0,1.0));
		float rays = 1.0-smoothstep(line_width,line_width+1.1,ray_distance);
		float accents = (1.0-smoothstep(0.5,1.5,accent_distance))*0.42;
		float bands = 0.0;
		for (int i=0;i<4;i++) {
			float band_depth = 64.0*pow(1.85,float(i));
			float band_width = 0.7+float(i)*0.3;
			bands = max(bands,1.0-smoothstep(band_width,band_width+1.0,abs(p.y-floor_horizon-band_depth)));
		}
		// Distant inlays emerge with the floor rather than piercing the dark join.
		float floor_mask = smoothstep(horizon+40.0,horizon+160.0,p.y);
		float gold = max(max(rays,accents),bands*0.66)*floor_mask;
		color = mix(color,vec3(0.86,0.56,0.16),gold*0.86);
		alpha = mix(alpha,0.78,gold);
	}
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
