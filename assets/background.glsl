// Original marbled ink field: a radial twist, then layered domain warping.
// Chunky color bands and a slow spin evoke a psychedelic card-table backdrop.
extern number time;
extern vec2 resolution;

mat2 rotation(float angle)
{
    float sine = sin(angle);
    float cosine = cos(angle);
    return mat2(cosine, -sine, sine, cosine);
}

vec4 effect(vec4 color, Image texture, vec2 uv, vec2 screen_position)
{
    vec2 pixel = floor(screen_position / 2.0) * 2.0;
    vec2 point = (pixel - resolution * 0.5) / resolution.y;
    float radius = length(point);
    float clock = time * 0.13;
    point = rotation(3.8 * exp(-radius * 1.5) - clock * 0.35) * point * 3.2;

    // Repeatedly bend the coordinates, rather than scrolling a static texture.
    for (int layer = 0; layer < 4; layer++)
    {
        float frequency = 1.6 + float(layer) * 0.7;
        point += vec2(sin(point.y * frequency + clock),
                      cos(point.x * frequency - clock * 0.8)) * 0.30;
    }
    float ink = sin(point.x * 3.0 + point.y * 2.0 + clock);
    ink += 0.40 * sin(point.y * 4.0 - point.x * 1.6);
    float bands = sin(ink * 4.5 + radius * 3.0);

    vec3 navy = vec3(0.020, 0.045, 0.076);
    vec3 teal = vec3(0.075, 0.30, 0.31);
    vec3 coral = vec3(0.39, 0.12, 0.15);
    vec3 paint = mix(navy, teal, smoothstep(-0.35, 0.50, bands));
    paint = mix(paint, coral, smoothstep(0.55, 0.88, bands));
    paint += vec3(0.08, 0.055, 0.025) * (1.0 - smoothstep(0.015, 0.075, abs(bands - 0.55)));

    float vignette = 1.0 - smoothstep(0.30, 0.90, radius) * 0.5;
    float scanline = 0.98 + 0.02 * sin(screen_position.y * 3.14159);
    return vec4(paint * vignette * scanline, 1.0) * color;
}
