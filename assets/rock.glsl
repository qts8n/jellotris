// Stable local-space sand grain, chipped bevels, and hairline cracks.
extern number seed;

float grain(vec2 point)
{
    return fract(sin(dot(point, vec2(127.1, 311.7)) + seed * 17.0) * 43758.5453);
}

vec4 effect(vec4 color, Image texture, vec2 uv, vec2 screen_position)
{
    vec2 point = abs(uv * 2.0 - 1.0);
    float edge = max(max(point.x, point.y) - 0.96, (point.x + point.y - 1.75) * 0.707);
    float alpha = 1.0 - smoothstep(-0.015, 0.015, edge);
    float sand = grain(floor(uv * 76.0));
    float flecks = grain(floor(uv * 29.0));
    float bevel = 1.0 - smoothstep(0.02, 0.14, -edge);
    float top_light = (1.0 - uv.y) * 0.20 + (1.0 - uv.x) * 0.08;
    vec3 stone = color.rgb * (0.72 + top_light + sand * 0.20);
    stone += vec3(0.16, 0.12, 0.07) * step(0.85, flecks);
    stone -= vec3(0.12, 0.09, 0.055) * step(flecks, 0.11);
    stone *= 1.0 - bevel * (uv.y > 0.5 ? 0.32 : -0.12);

    float crack_x = 0.70 + sin(uv.y * 19.0 + seed) * 0.045;
    float crack = 1.0 - smoothstep(0.009, 0.022, abs(uv.x - crack_x));
    crack *= smoothstep(0.61, 0.75, uv.y);
    stone *= 1.0 - crack * 0.42;
    return vec4(stone, alpha * color.a);
}
