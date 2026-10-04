// UVs follow the spring mesh, so lighting stretches with the actual jelly.
extern number time;
extern number seed;

float rounded_box(vec2 point, vec2 half_size, float radius)
{
    vec2 corner = abs(point) - half_size + radius;
    return length(max(corner, 0.0)) + min(max(corner.x, corner.y), 0.0) - radius;
}

vec4 effect(vec4 color, Image texture, vec2 uv, vec2 screen_position)
{
    vec2 point = uv * 2.0 - 1.0;
    float distance_to_edge = rounded_box(point, vec2(0.97), 0.30);
    float alpha = 1.0 - smoothstep(-0.025, 0.015, distance_to_edge);

    // A domed surface, a darker rolled edge, and two broad wet highlights.
    float dome = sqrt(max(0.0, 1.0 - dot(point * 0.65, point * 0.65)));
    vec3 normal = normalize(vec3(point * 0.7, dome));
    vec3 light = normalize(vec3(-0.45, -0.65, 1.0));
    float diffuse = max(0.0, dot(normal, light));
    float rim = 1.0 - smoothstep(0.025, 0.19, -distance_to_edge);
    vec3 jelly = color.rgb * (0.64 + diffuse * 0.42);
    jelly = mix(jelly, color.rgb * 0.45, rim * 0.58);

    vec2 highlight = (point - vec2(-0.30, -0.47)) * vec2(2.8, 6.5);
    float gloss = exp(-dot(highlight, highlight)) * 0.67;
    float edge_light = exp(-pow((distance_to_edge + 0.105) * 45.0, 2.0));
    edge_light *= (1.0 - smoothstep(-0.80, 0.40, point.y)) * 0.28;
    jelly = mix(jelly, vec3(0.94, 1.0, 0.99), gloss + edge_light);
    jelly += color.rgb * pow(max(0.0, point.y), 3.0) * 0.16;

    // Two trapped air bubbles. Slow drift makes even a sleeping body feel alive.
    vec2 bubble_center = vec2(0.47, 0.33 + sin(time * 1.2 + seed) * 0.055);
    float bubble = length(point - bubble_center);
    float bubble_rim = exp(-pow((bubble - 0.105) * 75.0, 2.0));
    jelly += vec3(0.15, 0.20, 0.17) * bubble_rim;
    float tiny_bubble = length(point - vec2(0.20, 0.58));
    jelly += vec3(0.10) * exp(-pow((tiny_bubble - 0.043) * 100.0, 2.0));

    return vec4(jelly, alpha * color.a);
}
