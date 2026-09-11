#include <metal_stdlib>
using namespace metal;

// Duo lid fold: wallpaper stays mapped on a glass quad. Closing rotates
// that quad back around the bottom hinge. Outside the projected panel is
// the black bezel. Blur is a circular cap on the TOP of the picture.

struct Uniforms {
    float2 resolution;
    float progress;
    float angle;
    float time;
    float intensity;
    float2 pad;
};

struct KawaseUniforms {
    float2 texelSize;
    float offset;
    float pad;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut duo_vertex(uint vid [[vertex_id]]) {
    float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    VertexOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    float2 uv = positions[vid] * 0.5 + 0.5;
    uv.y = 1.0 - uv.y;
    out.uv = uv;
    return out;
}

fragment float4 duo_kawase(VertexOut in [[stage_in]],
                           constant KawaseUniforms &u [[buffer(0)]],
                           texture2d<float> source [[texture(0)]],
                           sampler samp [[sampler(0)]]) {
    float2 uv = in.uv;
    float2 o = u.texelSize * u.offset;
    float4 color = 0.0;
    color += source.sample(samp, uv + float2( o.x,  o.y));
    color += source.sample(samp, uv + float2( o.x, -o.y));
    color += source.sample(samp, uv + float2(-o.x,  o.y));
    color += source.sample(samp, uv + float2(-o.x, -o.y));
    return color * 0.25;
}

float sdRoundBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

fragment float4 duo_fragment(VertexOut in [[stage_in]],
                             constant Uniforms &u [[buffer(0)]],
                             texture2d<float> source [[texture(0)]],
                             texture2d<float> blurTex [[texture(1)]],
                             sampler samp [[sampler(0)]]) {
    float p = saturate(u.progress);
    float2 uv = in.uv;
    float aspect = u.resolution.x / max(u.resolution.y, 1.0);

    float depth = clamp(u.intensity, 0.7, 1.9);
    float theta = min(p * (0.86 * depth), 1.38);
    float cth = cos(theta);
    float sth = sin(theta);
    float eye = max(2.25 - depth * 0.62, 1.08);

    float sx = (uv.x - 0.5) * aspect;
    float sy = 0.5 - uv.y;

    float denom = cth * eye - sth * sy;
    if (abs(denom) < 1e-4) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }
    float t = (0.5 * sth + cth * eye) / denom;
    if (t <= 0.0) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 hit = float2(t * sx, t * sy);
    float origX = hit.x;
    float origY = abs(cth) > 0.12
        ? (hit.y + 0.5) / cth - 0.5
        : (-eye + t * eye) / max(sth, 1e-4) - 0.5;

    float2 texUV;
    texUV.x = origX / aspect + 0.5;
    texUV.y = 0.5 - origY;

    float2 fw = fwidth(texUV) + 1e-5;
    float quadMask =
        smoothstep(-fw.x, fw.x, texUV.x) *
        smoothstep(-fw.x, fw.x, 1.0 - texUV.x) *
        smoothstep(-fw.y, fw.y, texUV.y) *
        smoothstep(-fw.y, fw.y, 1.0 - texUV.y);
    if (quadMask <= 0.0) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float bezel = smoothstep(0.0, 0.22, p);
    float radius = mix(0.0, 0.048, bezel);
    float2 boxP = texUV * 2.0 - 1.0;
    float cornerR = boxP.y < 0.0 ? radius : 0.0;
    float sd = sdRoundBox(boxP, float2(1.0), cornerR);
    float panel = 1.0 - smoothstep(-0.01, 0.01, sd);
    float mask = quadMask * panel;
    if (mask <= 0.0) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 origin = float2(0.5, 0.94);
    float2 fromOrigin = (texUV - origin) * float2(aspect * 0.74, 1.0);
    float radial = length(fromOrigin);
    float2 outward = fromOrigin / max(radial, 1e-4);

    float topArc = pow(smoothstep(0.22, 0.86, radial), 0.85);
    float topOnly = 1.0 - smoothstep(0.52, 0.86, texUV.y);
    float glassAmt = p * topArc * topOnly;

    float bend = glassAmt * 0.058;
    float2 glassUV = texUV + outward * bend / float2(aspect, 1.0);

    float defocus = glassAmt * mix(0.004, 0.034, topArc);
    float3 sharp = source.sample(samp, texUV).rgb;
    float3 bokeh = source.sample(samp, glassUV).rgb;
    const int taps = 16;
    for (int i = 0; i < taps; i++) {
        float a = (float(i) + 0.5) * 6.2831853 / float(taps);
        float2 disc = float2(cos(a), sin(a));
        float2 tap = disc * defocus + outward * defocus * 0.5;
        tap.x /= aspect;
        bokeh += source.sample(samp, glassUV + tap).rgb;
        bokeh += source.sample(samp, glassUV + tap * 0.42).rgb;
    }
    bokeh /= float(taps * 2 + 1);

    float milk = glassAmt * smoothstep(0.2, 0.78, radial);
    float3 heavy = blurTex.sample(samp, glassUV + outward * glassAmt * 0.035 / float2(aspect, 1.0)).rgb;
    float3 color = mix(sharp, mix(bokeh, heavy, milk * 0.5), saturate(glassAmt * 1.35));

    float fresnel = pow(saturate(topArc), 2.2) * glassAmt;
    color += fresnel * 0.06 * float3(0.88, 0.92, 1.0);

    return float4(color * mask, 1.0);
}

// Duo+: inverse-homography sample of a live picture, with height-based
// mip blur and dimming. Adapted from Mac Duo by Makito (Apache-2.0):
// https://github.com/sumimakito/Mac-Duo

struct PlusUniforms {
    float4 column0;
    float4 column1;
    float4 column2;
    float4 screenAndScale;
    float4 blur;
    float4 light;
};

fragment float4 duo_plus_fragment(VertexOut in [[stage_in]],
                                 constant PlusUniforms &u [[buffer(0)]],
                                 texture2d<float> picture [[texture(0)]],
                                 sampler samp [[sampler(0)]]) {
    float2 screenSize = u.screenAndScale.xy;
    float pixelScale = u.screenAndScale.z;
    float strength = u.screenAndScale.w;
    float maxRadius = u.blur.x;
    float blurFloor = u.blur.y;
    float maxDim = u.blur.z;
    float dimReach = u.blur.w;
    float dimFloor = u.light.x;
    float dimStrength = u.light.y;
    float maxLevel = u.light.z;

    float2 screenPoint = float2(in.position.x / pixelScale,
                                screenSize.y - in.position.y / pixelScale);
    float3x3 screenToPicture = float3x3(u.column0.xyz, u.column1.xyz, u.column2.xyz);
    float3 mapped = screenToPicture * float3(screenPoint, 1.0);
    if (abs(mapped.z) < 1e-6) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }
    float2 picturePoint = mapped.xy / mapped.z;
    if (picturePoint.x < 0.0 || picturePoint.x > screenSize.x ||
        picturePoint.y < 0.0 || picturePoint.y > screenSize.y) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    float2 texCoord = float2(picturePoint.x / max(screenSize.x, 1.0),
                             1.0 - picturePoint.y / max(screenSize.y, 1.0));
    float height = clamp(picturePoint.y / max(screenSize.y, 1.0), 0.0, 1.0);
    float blurAmt = strength * (blurFloor + (1.0 - blurFloor) * height);
    float mipLevel = clamp(log2(max(blurAmt * maxRadius, 1.0)), 0.0, maxLevel);
    float4 colour = picture.sample(samp, texCoord, level(mipLevel));
    float spread = smoothstep(0.0, max(dimReach, 0.02), height);
    float fade = dimStrength * (dimFloor + (1.0 - dimFloor) * spread);
    colour.rgb *= pow(1.0 - maxDim * fade, 2.2);
    return float4(colour.rgb, 1.0);
}
