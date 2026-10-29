shader_type canvas_item;
render_mode unshaded;

// Calibrated to the published beacon jellyfish idle illustration only.
uniform float motion_time = 0.0;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
varying vec2 source_uv;
varying vec4 sprite_tint;

void vertex() {
    sprite_tint = COLOR;
    // Transparent margin lets the outer tendrils swing past the source canvas.
    source_uv = UV * 1.16 - vec2(0.08);
    VERTEX += (UV - vec2(0.5)) * 0.16 / TEXTURE_PIXEL_SIZE;
}

void fragment() {
    vec2 uv = source_uv;
    // The bell's rim slopes down towards the right in the source illustration.
    // Ease from fixed roots to flexible tips, leaving the lamp and bell intact.
    float root_y = 0.43 + 0.12 * clamp(uv.x, 0.0, 1.0);
    float tip_weight = smoothstep(root_y, root_y + 0.35, uv.y);
    float depth = max(0.0, uv.y - root_y);
    float phase = motion_time * 2.2 + uv.x * 9.0 - depth * 4.5;
    float wave = sin(phase) * 0.8 + sin(phase * 1.37 + 0.8) * 0.2;
    uv.x -= wave * 0.042 * tip_weight * strength;
    uv.y -= sin(phase + 1.1) * 0.012 * tip_weight * strength;
    vec4 ink = texture(TEXTURE, clamp(uv, vec2(0.0), vec2(1.0)));
    float inside = step(0.0, uv.x) * step(uv.x, 1.0)
        * step(0.0, uv.y) * step(uv.y, 1.0);
    COLOR = ink * sprite_tint * inside;
}
