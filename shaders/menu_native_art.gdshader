shader_type canvas_item;
render_mode unshaded;
// Native PNG sampling. Motion geometry and neon timing match the original render tools.
// The caller supplies phase; never use TIME, so focus loss and static mode truly pause.
uniform vec3 motion_angles = vec3(0.0);
uniform vec2 light_gains = vec2(0.0);
uniform vec2 sign_gains = vec2(1.0);
const vec2 SOURCE_SIZE = vec2(1672.0, 941.0);

float cup_weight(vec2 p) {
    if (p.x < 383.0 || p.x > 465.0 || p.y < 334.0 || p.y > 466.0) return 0.0;
    const vec2 points[10] = vec2[10](vec2(401.0, 341.0), vec2(449.0, 341.0), vec2(458.0, 381.0), vec2(448.0, 411.0), vec2(435.0, 449.0), vec2(416.0, 459.0), vec2(401.0, 440.0), vec2(396.0, 414.0), vec2(391.0, 389.0), vec2(390.0, 362.0));
    bool inside = false;
    float distance_squared = 1e10;
    for (int i = 0; i < 10; i++) {
        vec2 a = points[(i + 10-1) % 10], b = points[i];
        vec2 edge = b - a;
        if ((a.y > p.y) != (b.y > p.y)) {
            if (p.x < (b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x) inside = !inside;
        }
        vec2 d = p - (a + clamp(dot(p-a, edge)/dot(edge, edge), 0.0, 1.0)*edge);
        distance_squared = min(distance_squared, dot(d, d));
    }
    float weight = smoothstep(-7.0, 7.0, (inside ? 1.0 : -1.0)*sqrt(distance_squared));
    return weight;
}

float front_boot_weight(vec2 p) {
    if (p.x < 302.0 || p.x > 477.0 || p.y < 567.0 || p.y > 816.0) return 0.0;
    const vec2 points[14] = vec2[14](vec2(440.0, 575.0), vec2(469.0, 583.0), vec2(451.0, 638.0), vec2(435.0, 684.0), vec2(422.0, 731.0), vec2(407.0, 778.0), vec2(388.0, 808.0), vec2(318.0, 802.0), vec2(310.0, 778.0), vec2(332.0, 749.0), vec2(355.0, 723.0), vec2(367.0, 684.0), vec2(389.0, 635.0), vec2(416.0, 596.0));
    bool inside = false;
    float distance_squared = 1e10;
    for (int i = 0; i < 14; i++) {
        vec2 a = points[(i + 14-1) % 14], b = points[i];
        vec2 edge = b - a;
        if ((a.y > p.y) != (b.y > p.y)) {
            if (p.x < (b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x) inside = !inside;
        }
        vec2 d = p - (a + clamp(dot(p-a, edge)/dot(edge, edge), 0.0, 1.0)*edge);
        distance_squared = min(distance_squared, dot(d, d));
    }
    float weight = smoothstep(-8.0, 8.0, (inside ? 1.0 : -1.0)*sqrt(distance_squared));
    weight *= smoothstep(574.0, 631.0, p.y);
    return weight;
}

float lower_boot_weight(vec2 p) {
    if (p.x < 433.0 || p.x > 525.0 || p.y < 570.0 || p.y > 867.0) return 0.0;
    const vec2 points[15] = vec2[15](vec2(477.0, 577.0), vec2(504.0, 581.0), vec2(513.0, 619.0), vec2(509.0, 683.0), vec2(511.0, 724.0), vec2(518.0, 778.0), vec2(511.0, 820.0), vec2(505.0, 856.0), vec2(452.0, 860.0), vec2(440.0, 840.0), vec2(451.0, 803.0), vec2(459.0, 773.0), vec2(458.0, 724.0), vec2(460.0, 682.0), vec2(464.0, 629.0));
    bool inside = false;
    float distance_squared = 1e10;
    for (int i = 0; i < 15; i++) {
        vec2 a = points[(i + 15-1) % 15], b = points[i];
        vec2 edge = b - a;
        if ((a.y > p.y) != (b.y > p.y)) {
            if (p.x < (b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x) inside = !inside;
        }
        vec2 d = p - (a + clamp(dot(p-a, edge)/dot(edge, edge), 0.0, 1.0)*edge);
        distance_squared = min(distance_squared, dot(d, d));
    }
    float weight = smoothstep(-7.0, 7.0, (inside ? 1.0 : -1.0)*sqrt(distance_squared));
    weight *= smoothstep(592.0, 650.0, p.y);
    return weight;
}

float left_sign_weight(vec2 p) {
    if (p.x < 740.0 || p.x > 795.0 || p.y < 353.0 || p.y > 502.0) return 0.0;
    const vec2 points[4] = vec2[4](vec2(741.0, 353.0), vec2(788.0, 364.0), vec2(795.0, 494.0), vec2(740.0, 502.0));
    bool inside = false;
    float distance_squared = 1e10;
    for (int i = 0; i < 4; i++) {
        vec2 a = points[(i + 4-1) % 4], b = points[i];
        vec2 edge = b - a;
        if ((a.y > p.y) != (b.y > p.y)) {
            if (p.x < (b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x) inside = !inside;
        }
        vec2 d = p - (a + clamp(dot(p-a, edge)/dot(edge, edge), 0.0, 1.0)*edge);
        distance_squared = min(distance_squared, dot(d, d));
    }
    return inside ? 1.0 : 0.0;
}

float right_sign_weight(vec2 p) {
    if (p.x < 1510.0 || p.x > 1585.0 || p.y < 264.0 || p.y > 415.0) return 0.0;
    const vec2 points[4] = vec2[4](vec2(1510.0, 270.0), vec2(1572.0, 264.0), vec2(1585.0, 401.0), vec2(1521.0, 415.0));
    bool inside = false;
    float distance_squared = 1e10;
    for (int i = 0; i < 4; i++) {
        vec2 a = points[(i + 4-1) % 4], b = points[i];
        vec2 edge = b - a;
        if ((a.y > p.y) != (b.y > p.y)) {
            if (p.x < (b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x) inside = !inside;
        }
        vec2 d = p - (a + clamp(dot(p-a, edge)/dot(edge, edge), 0.0, 1.0)*edge);
        distance_squared = min(distance_squared, dot(d, d));
    }
    return inside ? 1.0 : 0.0;
}

vec2 displacement(vec2 p, vec2 pivot, float angle) {
    vec2 q = p - pivot;
    float c = cos(angle), s = sin(angle);
    return vec2(q.x*c + q.y*s, -q.x*s + q.y*c) - q;
}
float glow(vec2 p, vec2 center, vec2 radius) {
    vec2 q = (p-center)/radius;
    float d = dot(q, q);
    return d > 5.0 ? 0.0 : exp(-d*2.0);
}
void fragment() {
    vec2 p = UV*SOURCE_SIZE;
    vec2 offset = displacement(p, vec2(426.0,437.0), motion_angles.x)*cup_weight(p);
    offset += displacement(p, vec2(459.0,568.0), motion_angles.y)*front_boot_weight(p);
    offset += displacement(p, vec2(490.0,577.0), motion_angles.z)*lower_boot_weight(p);
    vec4 artwork = texture(TEXTURE, clamp(UV+offset/SOURCE_SIZE, TEXTURE_PIXEL_SIZE*0.5, vec2(1.0)-TEXTURE_PIXEL_SIZE*0.5));
    float warm = max(glow(p,vec2(115.0,62.0),vec2(110.0,95.0)),glow(p,vec2(352.0,121.0),vec2(118.0,100.0)));
    warm = max(warm,glow(p,vec2(646.0,247.0),vec2(95.0)));
    warm = max(warm,glow(p,vec2(512.0,363.0),vec2(130.0,185.0))*0.35);
    warm = max(warm,glow(p,vec2(1470.0,675.0),vec2(90.0,110.0)));
    float neon = max(glow(p,vec2(768.0,409.0),vec2(37.0,110.0)),glow(p,vec2(1544.0,334.0),vec2(36.0,115.0)));
    neon = max(neon,glow(p,vec2(944.0,512.0),vec2(134.0,64.0)));
    artwork.rgb = clamp(artwork.rgb*(1.0+warm*light_gains.x+neon*light_gains.y),vec3(0.0),vec3(1.0));
    if (artwork.r > 65.0/255.0 && artwork.b > 35.0/255.0) {
        artwork.rgb *= mix(1.0,sign_gains.x,left_sign_weight(p));
        artwork.rgb *= mix(1.0,sign_gains.y,right_sign_weight(p));
    }
    COLOR = artwork;
}
