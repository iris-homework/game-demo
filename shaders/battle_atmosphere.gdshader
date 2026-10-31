shader_type canvas_item;
render_mode unshaded;

// All masks live in the original illustration UVs and follow the existing camera.
// No TIME: pauses, hidden scenes and minimization freeze the supplied clock.
uniform float atmosphere_time = 0.0;
uniform bool motion_enabled = true;
uniform float art_aspect = 1.6;
uniform float ground_start = 0.5;
uniform float fog_strength = 0.0;
uniform float dust_strength = 0.0;
uniform float light_strength = 0.0;
uniform float ray_strength = 0.0;
uniform float water_strength = 0.0;
uniform float wind = 0.5;
uniform vec3 fog_color : source_color = vec3(0.53, 0.62, 0.72);
uniform vec3 dust_color : source_color = vec3(0.80, 0.87, 0.92);
uniform vec3 ray_color : source_color = vec3(1.0, 0.93, 0.78);
uniform vec2 ray_origin = vec2(0.2, -0.15);
// left, top, right, bottom: only open water, never buildings or the combat floor.
uniform vec4 water_rect = vec4(0.0);
uniform float flicker_strength = 0.0;
uniform vec4 light_boxes[4];
uniform float stream_strength = 0.0;
// Top center xy, bottom center zw; widths are half-widths along the image x axis.
uniform vec4 stream_paths[3];
uniform vec3 stream_widths = vec3(0.0);
varying vec4 vertex_tint;

void vertex() {
    vertex_tint = COLOR;
}

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}
float noise2(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
        mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), f.x), f.y);
}
float water_mask(vec2 uv) {
    vec2 inset = smoothstep(water_rect.xy, water_rect.xy + vec2(0.025, 0.009), uv);
    vec2 outset = 1.0 - smoothstep(water_rect.zw - vec2(0.025, 0.009), water_rect.zw, uv);
    return inset.x * inset.y * outset.x * outset.y * water_strength;
}
float motes(vec2 uv, float t, float density, float speed, float radius) {
    vec2 p = uv * vec2(art_aspect, 1.0) * density;
    p -= vec2(t * speed * wind, -t * speed * 0.32);
    vec2 cell = floor(p);
    float seed = hash21(cell);
    vec2 center = vec2(0.25 + seed * 0.5, 0.25 + hash21(cell + 7.7) * 0.5);
    center += vec2(sin(t * 0.37 + seed * 30.0), cos(t * 0.29 + seed * 21.0)) * 0.13;
    float distance_to_mote = length(fract(p) - center);
    float glow = 1.0 - smoothstep(radius * 0.3, radius * 2.7, distance_to_mote);
    float core = 1.0 - smoothstep(0.0, radius, distance_to_mote);
    float breathe = 0.45 + 0.55 * pow(sin(t * 0.58 + seed * 40.0) * 0.5 + 0.5, 2.0);
    return (core + glow * 0.23) * breathe * step(0.68, seed);
}

float box_mask(vec2 uv, vec4 box) {
    vec2 a = smoothstep(box.xy, box.xy + vec2(0.004), uv);
    vec2 b = 1.0 - smoothstep(box.zw - vec2(0.004), box.zw, uv);
    return a.x * a.y * b.x * b.y;
}

float stream_mask(vec2 uv, vec4 path, float width) {
    float along = (uv.y - path.y) / max(path.w - path.y, 0.001);
    float center_x = mix(path.x, path.z, clamp(along, 0.0, 1.0));
    float side = 1.0 - smoothstep(width * 0.65, max(width, 0.001), abs(uv.x - center_x));
    return side * smoothstep(0.0, 0.12, along) * (1.0 - smoothstep(0.88, 1.0, along));
}

void fragment() {
    vec2 uv = UV;
    float t = atmosphere_time;
    float enabled = motion_enabled ? 1.0 : 0.0;
    float water = water_mask(uv) * enabled;
    // Visible moving reflections; feathered banks keep the quay and floor fixed.
    uv.x += water * (sin(UV.y * 540.0 + t * 2.8) + sin(UV.y * 287.0 - t * 1.9)) * 0.0025;
    uv.y += water * sin(UV.x * 110.0 + UV.y * 230.0 - t * 2.3) * 0.00065;
    if (enabled > 0.0 && stream_strength > 0.0) {
        for (int i = 0; i < 3; i++) {
            if (stream_widths[i] <= 0.0) { continue; }
            vec4 path = stream_paths[i];
            float mask = stream_mask(UV, path, stream_widths[i]);
            vec2 direction = normalize(path.zw - path.xy);
            float flow = sin(UV.y * 340.0 - t * 8.0 + sin(UV.x * 670.0));
            uv -= direction * flow * mask * stream_strength * 0.0020;
        }
    }
    vec4 art = texture(TEXTURE, clamp(uv, vec2(0.0), vec2(1.0)));
    vec3 color = art.rgb;
    if (enabled > 0.0) {
        float upper = 1.0 - smoothstep(ground_start - 0.03, ground_start + 0.055, UV.y);
        // Saturated bright pixels select painted lamps, without brightening dark walls.
        float hi = max(art.r, max(art.g, art.b));
        float lo = min(art.r, min(art.g, art.b));
        float lamp = smoothstep(0.44, 0.85, hi) * smoothstep(0.10, 0.38, hi - lo) * upper;
        float phase = floor(UV.x * 13.0) * 2.39 + floor(UV.y * 9.0) * 1.71;
        float pulse = sin(t * 0.83 + phase) * 0.62 + sin(t * 1.37 + phase * 1.9) * 0.23;
        color += art.rgb * lamp * pulse * light_strength;
        color += vec3(0.42, 0.61, 0.73) * water * pow(0.5 + 0.5 * sin(UV.y * 920.0 + sin(UV.x * 58.0 + t) * 2.0 - t * 2.8), 10.0) * 0.13;

        if (flicker_strength > 0.0) {
            for (int i = 0; i < 4; i++) {
                vec4 box = light_boxes[i];
                if (box.z <= box.x) { continue; }
                float cycle = fract(t / (2.8 + float(i) * 0.43) + float(i) * 0.231);
                float outage = smoothstep(0.46, 0.49, cycle) * (1.0 - smoothstep(0.66, 0.69, cycle));
                float after_dip = smoothstep(0.76, 0.78, cycle) * (1.0 - smoothstep(0.81, 0.83, cycle));
                float on = 1.0 - max(outage, after_dip * 0.85);
                float bright_pixels = smoothstep(0.32, 0.75, hi) * smoothstep(0.06, 0.26, hi - lo);
                float shape = box_mask(UV, box);
                color += art.rgb * shape * bright_pixels * (on * 1.35 - 0.90) * flicker_strength;
                vec2 center = (box.xy + box.zw) * 0.5;
                vec2 distance_to_light = (UV - center) / ((box.zw - box.xy) * 0.9 + vec2(0.008));
                float halo = exp(-dot(distance_to_light, distance_to_light) * 2.0);
                vec3 lamp_tint = texture(TEXTURE, center).rgb;
                color += lamp_tint * halo * on * 0.24 * flicker_strength;
            }
        }
        if (stream_strength > 0.0) {
            for (int i = 0; i < 3; i++) {
                if (stream_widths[i] <= 0.0) { continue; }
                vec4 path = stream_paths[i];
                float mask = stream_mask(UV, path, stream_widths[i]);
                if (mask <= 0.001) { continue; }
                float along = (UV.y - path.y) / max(path.w - path.y, 0.001);
                float lane = (UV.x - mix(path.x, path.z, along)) * 1800.0;
                // Uneven streaks advect down the spillway instead of a regular grid.
                float streaks = smoothstep(0.45, 0.88, noise2(vec2(lane * 0.11, along * 6.0 - t * 2.3)));
                float cascade = pow(0.5 + 0.5 * sin(along * 33.0 - t * 13.0 + sin(lane) * 1.4), 3.0);
                // Only the cool painted water carries the moving white foam.
                float cool_water = smoothstep(0.01, 0.10, art.b - art.r) * smoothstep(0.18, 0.52, hi);
                color += vec3(0.53, 0.76, 0.93) * mask * cool_water * streaks * cascade * stream_strength * 0.42;
            }
        }

        if (fog_strength > 0.0) {
            vec2 flow = vec2(UV.x * 5.0 - t * 0.035 * wind, UV.y * 13.0 + t * 0.008);
            float fog = noise2(flow) * 0.65 + noise2(flow * 2.13 + vec2(t * 0.016, 4.8)) * 0.35;
            float height = exp(-pow((UV.y - ground_start - 0.055) / 0.11, 2.0));
            float wisps = smoothstep(0.30, 0.82, fog) * height * fog_strength;
            color = mix(color, fog_color, wisps);
        }
        if (ray_strength > 0.0) {
            vec2 from_light = UV - ray_origin;
            float angle = from_light.x / max(from_light.y, 0.08);
            float rays = pow(max(0.0, sin(angle * 16.0 + sin(t * 0.13) * 0.45)), 12.0);
            rays += pow(max(0.0, sin(angle * 29.0 - t * 0.045)), 20.0) * 0.35;
            float falloff = smoothstep(0.06, 0.25, UV.y) * (1.0 - smoothstep(ground_start + 0.02, ground_start + 0.34, UV.y));
            color += ray_color * rays * falloff * ray_strength * 0.65;
        }
        if (dust_strength > 0.0) {
            float depth_fade = smoothstep(0.12, 0.27, UV.y) * (1.0 - smoothstep(0.65, 0.88, UV.y));
            float dust = motes(UV, t, 23.0, 0.16, 0.018) * 0.50;
            dust += motes(UV + vec2(0.37, 0.19), t, 12.0, 0.24, 0.018) * 0.85;
            color += dust_color * dust * dust_strength * depth_fade;
        }
    }
    COLOR = vec4(color, art.a) * vertex_tint;
}
