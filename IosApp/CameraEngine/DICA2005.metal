#include <metal_stdlib>
using namespace metal;

float luminance(float3 c) {
    return dot(c, float3(0.299, 0.587, 0.114));
}

float3 apply_saturation(float3 c, float factor) {
    float lum = luminance(c);
    return mix(float3(lum), c, factor);
}

float rand(float2 co) {
    return fract(sin(dot(co, float2(12.9898, 78.233))) * 43758.5453);
}

float soft_clip(float x, float threshold) {
    if (x <= threshold) return x;
    float over = x - threshold;
    float range = 1.0 - threshold;
    return threshold + range * (1.0 - exp(-over / range * 2.5));
}

float3 apply_highlight_clip(float3 col) {
    float lum = luminance(col);
    float t = mix(0.82, 0.90, lum);
    return float3(
        soft_clip(col.r, t + 0.01),
        soft_clip(col.g, t + 0.02),
        soft_clip(col.b, t - 0.01)
    );
}

float3 apply_sony_cool(float3 col) {
    float lum = luminance(col);

    float shadow_w = 1.0 - smoothstep(0.0, 0.4, lum);
    col.r -= 0.018 * shadow_w;
    col.b += 0.030 * shadow_w;

    float highlight_w = smoothstep(0.65, 1.0, lum);
    col.r -= 0.010 * highlight_w;
    col.b += 0.015 * highlight_w;

    return col;
}

kernel void dica2005Filter(
    texture2d<float, access::read>    inTexture  [[texture(0)]],
    texture2d<float, access::write>   outTexture [[texture(1)]],
    texture3d<float, access::sample>  lutTexture [[texture(2)]],
    uint2 gid [[thread_position_in_grid]]
)
{
    float w = outTexture.get_width();
    float h = outTexture.get_height();
    if (gid.x >= w || gid.y >= h) return;

    float4 pixel = inTexture.read(gid);
    float3 color = pixel.rgb;

    // 1. LUT (밝기 기반 동적 강도)
    constexpr sampler lutSampler(coord::normalized,
                                  filter::linear,
                                  address::clamp_to_edge);
    float size = 64.0;
    float3 coord = color * (size - 1.0) / size + 0.5 / size;
    float3 lutColor = lutTexture.sample(lutSampler, coord).rgb;
    float lut_mix = mix(0.50, 0.65, luminance(color));
    color = mix(color, lutColor, lut_mix);

    // 2. Tone curve
    color = pow(color, float3(0.94));

    // 3. Sony 쿨톤 색 틀어짐
    color = apply_sony_cool(color);

    // 5. 채도 부스트
    color = apply_saturation(color, 1.12);

    // 6. Highlight soft clip
    color = apply_highlight_clip(color);

    // 7. CCD grain (퍼진 grain + 채널별 다르게)
    float lum = luminance(color);
    float noise_mask = 1.0 - smoothstep(0.0, 0.6, lum);
    float2 grain_uv = float2(gid) * 0.5;  // grain 크기 키움
    float n = rand(grain_uv);
    float3 grain;
    grain.r = (n - 0.5) * 0.030 * noise_mask;
    grain.g = (n - 0.5) * 0.025 * noise_mask;
    grain.b = (n - 0.5) * 0.035 * noise_mask;
    color += grain;

    color = clamp(color, 0.0, 1.0);
    pixel.rgb = color;
    outTexture.write(pixel, gid);
}

