extern number time;
extern vec2 texel_size;

vec4 effect(vec4 color, Image texture, vec2 uv, vec2 screen_position)
{
    // Waves travel through the lettering while the silhouette stays legible.
    uv.x += sin(uv.y * 12.0 + time * 1.4) * 0.004;
    uv.y += sin(uv.x * 11.0 - time * 1.8) * 0.004;
    float mask = Texel(texture, uv).a;
    float upper_edge = max(0.0, mask - Texel(texture, uv - texel_size * vec2(0.0, 2.0)).a);
    float lower_edge = max(0.0, mask - Texel(texture, uv + texel_size * vec2(0.0, 3.0)).a);
    float gradient = smoothstep(0.12, 0.94, uv.y);
    vec3 ink = mix(vec3(0.79, 1.0, 0.53), vec3(0.14, 0.83, 0.79), gradient);
    float sheen = pow(max(0.0, sin(uv.x * 5.0 + uv.y * 3.0 - time * 0.8)), 18.0);
    ink = mix(ink, vec3(0.95, 1.0, 0.88), sheen * 0.55 + upper_edge * 0.75);
    ink *= 1.0 - lower_edge * 0.35;
    return vec4(ink * color.rgb, mask * color.a);
}
