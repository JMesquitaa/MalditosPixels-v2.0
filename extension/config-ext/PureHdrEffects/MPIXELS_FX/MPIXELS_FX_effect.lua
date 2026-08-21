-- ============================================================================
-- MALDITOS PIXELS — SPICE HDR Effect v1.0 (Fase 12.14)
--
-- Pixels FX effects + MALDITOS PIXELS signature (Purkinje):
--   1. Luma Sharpening (ON)  — referencia: Intensity 2.5, Radius 1.0, Threshold 0.0
--   2. Unified Color Engine (ON) — Vibrance 0.25, Midtone Gamma 1.0, White Point 1.0
--   3. Clarity (OFF)         — Intensity 0.125, Radius 5.0
--   4. Chromatic Aberration (OFF) — Uniform/Lateral 0.5
--   5. Film Grain (OFF)      — Amount 1.0
--   6. GoPro Lens Distortion (OFF) — Strength 0.5, Zoom 1.25
--   7. Dashcam VHS (OFF)     — Scanline 0.075, Jitter 0.35
--   8. Vignette (OFF)        — MALDITOS PIXELS extra
--   9. Black Bars (OFF)      — Style 1/2
--  10. Purkinje (auto)       — MALDITOS PIXELS signature (CIE 1951)
--
-- Lens Dirt omitted (requires texture overlay — SPICE limitation).
-- BlendMode: Opaque
-- ============================================================================

local data = ui.ExtraCanvas(
    render.getRenderTargetSize(),
    1,
    render.TextureFormat.R16G16B16A16.Float
)

local mp_shader = {
    blendMode = render.BlendMode.Opaque,

    textures = {
        txScreen = 'dynamic::screen',
        txDepth  = 'dynamic::depth',
        txLens1  = 'mpixels_lens1.png',
        txLens2  = 'mpixels_lens2.png',
        txDirt   = 'mpixels_dirt1.png',
    },

    values = {
        uScreenSize       = vec2(render.getRenderTargetSize().x, render.getRenderTargetSize().y),
        -- Luma Sharpening
        uSharpEnabled     = 1,
        uSharpIntensity   = 2.5,
        uSharpRadius      = 1.0,
        uSharpThreshold   = 0.0,
        -- Unified Color Engine
        uColorEnabled     = 1,
        uVibrance         = 0.25,
        uMidtoneGamma     = 1.0,
        uWhitePoint       = 1.0,
        -- Clarity
        uClarityEnabled   = 0,
        uClarityIntensity = 0.125,
        uClarityRadius    = 5.0,
        -- Chromatic Aberration
        uChromaEnabled    = 0,
        uChromaUniformX   = 0.5,
        uChromaUniformY   = 0.5,
        uChromaLateralX   = 0.5,
        uChromaLateralY   = 0.5,
        -- Film Grain
        uGrainEnabled     = 0,
        uGrainAmount      = 1.0,
        -- GoPro Lens Distortion
        uLensDistEnabled  = 0,
        uLensDistStrength = 0.5,
        uLensDistZoom     = 1.25,
        -- Dashcam VHS
        uVhsEnabled       = 0,
        uVhsScanline      = 0.075,
        uVhsJitter        = 0.35,
        -- Vignette (MALDITOS PIXELS extra)
        uVignetteEnabled  = 0,
        uVignetteStrength = 0.30,
        uVignetteFalloff  = 2.5,
        -- Black Bars
        uBlackBarsEnabled = 0,
        uBlackBarsStyle   = 0,
        -- Purkinje (MALDITOS PIXELS signature)
        uPurkinjeGlobalDrive = 0,
        uPurkinjeIntensity = 0.15,
        uPurkinjeThreshold = 0.12,
        -- Halation (13.6 — assinatura exclusiva)
        uHalationEnabled  = 0,
        uHalationIntensity = 0.15,
        uHalationRadius   = 3.0,
        uHalationWarmth   = 0.7,
        uHalationThreshold = 0.8,
        -- Depth sharpening
        uDepthSharpEnabled = 0,
        -- Lens Flare (Bloco 7)
        uFlareEnabled     = 0,
        uFlareIntensity   = 0.35,
        uFlareThreshold   = 0.85,
        uFlareMix         = 0.5,
        -- Lens Dirt (Bloco 7) — so em highlight, aditivo
        uDirtEnabled      = 0,
        uDirtIntensity    = 0.30,
        uDirtThreshold    = 0.75,
        -- VHS / Glitch (Bloco 15)
        uVhsMaster        = 0,
        uVhsCurvature     = 0.0,
        uVhsScanline      = 0.25,
        uVhsChromaSep     = 0.30,
        uVhsChromaSmear   = 0.50,
        uVhsRandomLines   = 0.30,
        uVhsHGlitch       = 0.30,
        uVhsGrain         = 0.015,
        uGlitchMaster     = 0,
        uGlitchRate       = 0.50,
        uGlitchRGB        = 0.30,
        uGlitchBlock      = 0.02,
        uGlitchDistort    = 0.10,
        -- Velocidade (Bloco 7)
        uSpeedZoom        = 1.0,
        uSpeedShakeX      = 0.0,
        uSpeedShakeY      = 0.0,
        -- Time
        uTime             = 0,
    },

    shader = [[
    float4 main(PS_IN pin) {
        float2 uv = pin.Tex;
        float2 texel = 1.0 / uScreenSize;

        // ================================================================
        // 0. VELOCIDADE — zoom radial e trepidacao (Bloco 7)
        // Sensacao de movimento sem borrar: so desloca UV, nao adiciona blur.
        // ================================================================
        if (uSpeedZoom != 1.0 || uSpeedShakeX != 0.0 || uSpeedShakeY != 0.0) {
            uv = (uv - 0.5) / max(uSpeedZoom, 0.01) + 0.5;
            uv += float2(uSpeedShakeX, uSpeedShakeY);
            uv = clamp(uv, 0.0, 1.0);
        }

        // ================================================================
        // GoPro Lens Distortion (before sampling — warps UVs)
        // ================================================================
        if (uLensDistEnabled > 0) {
            float2 centered = (uv - 0.5) * 2.0;
            float r2 = dot(centered, centered);
            float distortion = 1.0 + uLensDistStrength * r2;
            float2 distorted = centered * distortion;
            uv = distorted / (2.0 * uLensDistZoom) + 0.5;
            uv = clamp(uv, 0.0, 1.0);
        }

        float4 screenColor = txScreen.SampleLevel(samPoint, uv, 0);
        float3 color = screenColor.rgb;
        float3 baseColor = color;
        float luma = dot(color, float3(0.2126, 0.7152, 0.0722));

        // Anti-halo HDR damper
        float high_tone_damper = exp(-luma * 0.01);

        // Depth (for depth-aware sharpening — 13.6 P5)
        float depth = txDepth.SampleLevel(samPoint, uv, 0).r;
        float depthMask = (uDepthSharpEnabled > 0)
            ? smoothstep(0.998, 0.990, depth)   // 1.0 perto, 0.0 no ceu/infinito
            : 1.0;                               // fallback: sem mascara

        // ================================================================
        // 1. LUMA SHARPENING (referencia: Intensity 2.5, Radius 1.0, Threshold 0.0)
        // ================================================================
        if (uSharpEnabled > 0 && uSharpIntensity > 0) {
            float2 off = texel * uSharpRadius;
            float4 n = txScreen.SampleLevel(samPoint, uv + float2(0, -off.y), 0);
            float4 e = txScreen.SampleLevel(samPoint, uv + float2(off.x, 0), 0);
            float4 s = txScreen.SampleLevel(samPoint, uv + float2(0, off.y), 0);
            float4 w = txScreen.SampleLevel(samPoint, uv + float2(-off.x, 0), 0);

            // Luma-only sharpening (preserves color)
            float lumaN = dot(n.rgb, float3(0.2126, 0.7152, 0.0722));
            float lumaE = dot(e.rgb, float3(0.2126, 0.7152, 0.0722));
            float lumaS = dot(s.rgb, float3(0.2126, 0.7152, 0.0722));
            float lumaW = dot(w.rgb, float3(0.2126, 0.7152, 0.0722));

            float lumaEdge = lumaN + lumaE + lumaS + lumaW - 4.0 * luma;

            // Threshold gate
            float edgeMag = abs(lumaEdge);
            float mask = smoothstep(uSharpThreshold, uSharpThreshold + 0.05, edgeMag);

            // Apply to luma, recompose
            float sharpLuma = luma - lumaEdge * uSharpIntensity * 0.1 * mask * high_tone_damper * depthMask;
            if (luma > 0.001) {
                color *= clamp(sharpLuma / luma, 0.5, 2.0);
            }
        }

        // ================================================================
        // 2. CLARITY (referencia: Intensity 0.125, Radius 5.0, default OFF)
        // ================================================================
        if (uClarityEnabled > 0 && uClarityIntensity > 0) {
            float2 coff = texel * uClarityRadius;
            float blurLuma = 0;
            float tw = 0;
            for (int dx = -1; dx <= 1; dx++) {
                for (int dy = -1; dy <= 1; dy++) {
                    float d = length(float2(dx, dy));
                    float wt = exp(-d * 0.8);
                    float2 suv = clamp(uv + float2(dx, dy) * coff, 0.0, 1.0);
                    blurLuma += dot(txScreen.SampleLevel(samPoint, suv, 0).rgb,
                                   float3(0.2126, 0.7152, 0.0722)) * wt;
                    tw += wt;
                }
            }
            blurLuma /= tw;
            float clarityDelta = (luma - blurLuma) * uClarityIntensity;
            float newLuma = luma + clarityDelta;
            if (luma > 0.005) {
                color *= clamp(newLuma / luma, 0.5, 2.0);
            }
            color = lerp(baseColor, color, high_tone_damper);
        }

        // ================================================================
        // 3. UNIFIED COLOR ENGINE (Vibrance + Midtone Gamma + White Point)
        // ================================================================
        if (uColorEnabled > 0) {
            // Vibrance (saturation boost weighted by inverse saturation)
            float maxC = max(color.r, max(color.g, color.b));
            float minC = min(color.r, min(color.g, color.b));
            float sat = (maxC > 0.001) ? (maxC - minC) / maxC : 0.0;
            float vibWeight = 1.0 - sat;  // boost desaturated more
            float vibFactor = 1.0 + uVibrance * vibWeight;
            float cLuma = dot(color, float3(0.2126, 0.7152, 0.0722));
            color = lerp(float3(cLuma, cLuma, cLuma), color, vibFactor);

            // Midtone gamma
            if (abs(uMidtoneGamma - 1.0) > 0.01) {
                color = pow(max(color, 0.0), 1.0 / uMidtoneGamma);
            }

            // White point scaling
            color *= uWhitePoint;
        }

        // ================================================================
        // 4. CHROMATIC ABERRATION (Uniform + Lateral)
        // ================================================================
        if (uChromaEnabled > 0) {
            float2 center = float2(0.5, 0.5);
            float2 dir = uv - center;
            float r2 = dot(dir, dir);
            // Uniform: constant shift
            float2 uniformOff = float2(uChromaUniformX, uChromaUniformY) * 0.002;
            // Lateral: radial, scales with r²
            float2 lateralOff = dir * r2 * float2(uChromaLateralX, uChromaLateralY) * 0.01;
            float2 totalOff = uniformOff + lateralOff;
            color.r = txScreen.SampleLevel(samPoint, uv + totalOff, 0).r;
            color.b = txScreen.SampleLevel(samPoint, uv - totalOff, 0).b;
        }

        // ================================================================
        // 5. DASHCAM VHS (scanlines + horizontal jitter)
        // ================================================================
        if (uVhsEnabled > 0) {
            // Scanlines
            float scanline = sin(uv.y * uScreenSize.y * 3.14159) * 0.5 + 0.5;
            color *= 1.0 - uVhsScanline * (1.0 - scanline);

            // Horizontal jitter
            float jitterNoise = frac(sin(floor(uv.y * uScreenSize.y) + uTime * 7.3) * 43758.5453);
            float2 jitterUV = uv;
            jitterUV.x += (jitterNoise - 0.5) * uVhsJitter * 0.005;
            jitterUV.x = clamp(jitterUV.x, 0.0, 1.0);
            float3 jittered = txScreen.SampleLevel(samPoint, jitterUV, 0).rgb;
            color = lerp(color, jittered, 0.5);
        }

        // ================================================================
        // 6. PURKINJE — MALDITOS PIXELS signature (CIE 1951 scotopic)
        // ================================================================
        if (uPurkinjeGlobalDrive > 0.001) {
            float purk_luma = dot(color, float3(0.2126, 0.7152, 0.0722));
            float localActivation = smoothstep(
                uPurkinjeThreshold + 0.15,
                uPurkinjeThreshold - 0.05,
                purk_luma);
            float finalActivation = uPurkinjeGlobalDrive * localActivation * uPurkinjeIntensity;
            if (finalActivation > 0.001) {
                float scotopicLuma = dot(color, float3(0.062, 0.608, 0.330));
                float3 scotopicColor = scotopicLuma * float3(0.4, 0.6, 1.0);
                color = lerp(color, scotopicColor, finalActivation);
            }
        }

        // ================================================================
        // 7. VIGNETTE (MALDITOS PIXELS extra)
        // ================================================================
        if (uVignetteEnabled > 0) {
            float2 vUV = (uv - 0.5) * 2.0;
            float r = length(vUV);
            float vignette = 1.0 - uVignetteStrength * pow(r, uVignetteFalloff);
            color *= max(vignette, 0.0);
        }

        // ================================================================
        // 8. FILM GRAIN — triangular-PDF (13.6 P4)
        // Distribuicao triangular = padrao de industria (DaVinci, Unreal).
        // Le como filme, nao como ruido digital (hash uniforme anterior).
        // ================================================================
        if (uGrainEnabled > 0) {
            float gLuma = dot(color, float3(0.2126, 0.7152, 0.0722));
            // Dois hashes independentes → triangular via soma
            float h1 = frac(sin(dot(uv + frac(uTime * 0.1),
                                    float2(12.9898, 78.233))) * 43758.5453);
            float h2 = frac(sin(dot(uv + frac(uTime * 0.37),
                                    float2(63.7264, 10.873))) * 28001.8135);
            float triNoise = h1 + h2 - 1.0;  // [-1, 1] triangular
            float grainMask = smoothstep(0.9, 0.3, gLuma);
            color += triNoise * uGrainAmount * 0.012 * grainMask;
        }

        // ================================================================
        // 8.5 HALATION — sangramento quente em highlights (13.6 P3)
        // Assinatura exclusiva. Nenhum concorrente tem.
        // Amostragem em espiral ao redor de pixels acima do limiar.
        // Difuso e quente (nao ghost com separacao cromatica).
        // ================================================================
        if (uHalationEnabled > 0) {
            float3 halation = float3(0, 0, 0);
            float samples = 0;
            float2 halOff = texel * uHalationRadius;
            // Espiral de 8 pontos (Fibonacci-like)
            for (int i = 0; i < 8; i++) {
                float angle = i * 2.399;  // golden angle
                float r = (float(i) + 0.5) / 8.0;
                float2 offset = float2(cos(angle), sin(angle)) * r * halOff;
                float3 s = txScreen.SampleLevel(samPoint, clamp(uv + offset, 0.0, 1.0), 0).rgb;
                float sLuma = dot(s, float3(0.2126, 0.7152, 0.0722));
                float weight = smoothstep(uHalationThreshold, uHalationThreshold + 0.3, sLuma);
                halation += s * weight;
                samples += weight;
            }
            if (samples > 0.01) {
                halation /= samples;
                // Tint quente (warmth 0=neutro, 1=vermelho puro)
                float3 warmTint = lerp(float3(1,1,1), float3(1.2, 0.85, 0.6), uHalationWarmth);
                color += halation * warmTint * uHalationIntensity;
            }
        }

        // ================================================================
        // 8a. VHS (Bloco 15)
        // Reimplementacao compacta: mesma superficie de controle da
        // referencia (curvatura, scanline, separacao de croma, smear,
        // linhas aleatorias, glitch horizontal, grain) em ~50 linhas
        // em vez de 465. Menos codigo, menos superficie de falha.
        // ================================================================
        if (uVhsMaster > 0.5) {
            const float PI = 3.14159265;
            float2 vuv = pin.Tex;

            // Curvatura de tela com zoom compensatorio
            if (uVhsCurvature > 0.001) {
                float c = uVhsCurvature * 0.065;
                vuv.x -= sin(vuv.y * PI) * c * (vuv.x - 0.5);
                vuv.y -= sin(vuv.x * PI) * c * (vuv.y - 0.5);
                vuv = 0.5 + (vuv - 0.5) * (1.0 + 1.3 * c);
            }

            // Linha de varredura que percorre a tela
            float scan = frac(uTime * 0.35);
            if (uVhsScanline > 0.001 && abs(vuv.y - scan) < 0.06) {
                vuv.x -= sin((scan - vuv.y) * 20.0) * 0.012 * uVhsScanline;
            }

            // Glitch horizontal por faixas
            if (uVhsHGlitch > 0.001) {
                float band = floor(vuv.y * 60.0);
                float r    = frac(sin(band * 91.3 + floor(uTime * 8.0) * 13.7) * 43758.5);
                if (r > 0.93) vuv.x += (r - 0.965) * 0.15 * uVhsHGlitch;
            }
            vuv = clamp(vuv, 0.001, 0.999);

            // Separacao de croma: R e B deslocados na horizontal
            float sep = uVhsChromaSep * 0.012;
            float3 v;
            v.r = txScreen.SampleLevel(samLinear, clamp(vuv + float2( sep, 0), 0.001, 0.999), 0).r;
            v.g = txScreen.SampleLevel(samLinear, vuv, 0).g;
            v.b = txScreen.SampleLevel(samLinear, clamp(vuv - float2( sep, 0), 0.001, 0.999), 0).b;

            // Chroma smear: arrasta croma pra direita, luma intacto
            if (uVhsChromaSmear > 0.001) {
                float3 sm = txScreen.SampleLevel(samLinear,
                    clamp(vuv - float2(0.010 * uVhsChromaSmear, 0), 0.001, 0.999), 0).rgb;
                float lv = dot(v,  float3(0.2126, 0.7152, 0.0722));
                float ls = dot(sm, float3(0.2126, 0.7152, 0.0722));
                v = lerp(v, sm - ls + lv, uVhsChromaSmear * 0.6);
            }

            // Linhas claras aleatorias
            if (uVhsRandomLines > 0.001) {
                float ln = frac(sin(floor(vuv.y * 200.0) * 12.9 + floor(uTime * 12.0)) * 43758.5);
                if (ln > 0.995) v += 0.08 * uVhsRandomLines;
            }

            // Grain de fita
            if (uVhsGrain > 0.001) {
                float g = frac(sin(dot(vuv * uScreenSize + uTime, float2(12.9898, 78.233))) * 43758.5);
                v += (g - 0.5) * uVhsGrain;
            }

            color = max(v, 0.0);
        }

        // ================================================================
        // 8a2. GLITCH DIGITAL (Bloco 15)
        // ================================================================
        if (uGlitchMaster > 0.5) {
            float slot = floor(uTime * 6.0);
            float fire = frac(sin(slot * 45.7) * 43758.5);
            if (fire < uGlitchRate) {
                float bs   = max(uGlitchBlock, 0.002);
                float2 blk = floor(pin.Tex / bs);
                float  br  = frac(sin(dot(blk, float2(31.7, 57.1)) + slot) * 43758.5);
                if (br > 0.7) {
                    float2 guv = clamp(pin.Tex + float2((br - 0.85) * uGlitchDistort, 0), 0.001, 0.999);
                    float  o   = uGlitchRGB * 0.02;
                    float3 g;
                    g.r = txScreen.SampleLevel(samLinear, clamp(guv + float2(o, 0), 0.001, 0.999), 0).r;
                    g.g = txScreen.SampleLevel(samLinear, guv, 0).g;
                    g.b = txScreen.SampleLevel(samLinear, clamp(guv - float2(o, 0), 0.001, 0.999), 0).b;
                    color = max(g, 0.0);
                }
            }
        }

        // ================================================================
        // 8b. LENS FLARE (Bloco 7)
        // Duas camadas de textura moduladas pelo brilho da cena, espelhadas
        // em torno do centro — e assim que a referencia posiciona o ghost.
        // ================================================================
        if (uFlareEnabled > 0) {
            float lum = dot(color, float3(0.2126, 0.7152, 0.0722));
            float drive = saturate((lum - uFlareThreshold) / max(1.0 - uFlareThreshold, 0.001));
            if (drive > 0.001) {
                float2 mirrored = 1.0 - pin.Tex;
                float3 f1 = txLens1.SampleLevel(samLinear, pin.Tex, 0).rgb;
                float3 f2 = txLens2.SampleLevel(samLinear, mirrored, 0).rgb;
                float3 flare = lerp(f1, f2, saturate(uFlareMix));
                color += flare * drive * uFlareIntensity;
            }
        }

        // ================================================================
        // 8c. LENS DIRT (Bloco 7)
        // Aditivo e SO onde a imagem e brilhante (ceu, farol, neon).
        // Tecnica documentada pela referencia: sujeira de lente real so
        // aparece contra highlight, nunca em sombra.
        // ================================================================
        if (uDirtEnabled > 0) {
            float lum = dot(color, float3(0.2126, 0.7152, 0.0722));
            float mask = saturate((lum - uDirtThreshold) / max(1.0 - uDirtThreshold, 0.001));
            if (mask > 0.001) {
                float3 dirt = txDirt.SampleLevel(samLinear, pin.Tex, 0).rgb;
                color += dirt * mask * uDirtIntensity;
            }
        }

        // ================================================================
        // 9. BLACK BARS
        // ================================================================
        if (uBlackBarsEnabled > 0) {
            float barSize = (uBlackBarsStyle < 0.5) ? 0.12 : 0.06;  // Style1=cinematic, Style2=subtle
            if (pin.Tex.y < barSize || pin.Tex.y > (1.0 - barSize)) {
                color = float3(0, 0, 0);
            }
        }

        return float4(max(color, 0.0), 1.0);
    }
    ]]
}

-- ============================================================================
-- RENDER
-- ============================================================================
local function MPIXELS_FX_render(params, exposure, mainPass, updateExponent, rtSize, input)
    mp_shader.values.uScreenSize = vec2(
        render.getRenderTargetSize().x,
        render.getRenderTargetSize().y
    )
    mp_shader.textures.txScreen = input
    data:updateWithShader(mp_shader)
    return data
end

-- ============================================================================
-- INIT
-- ============================================================================
local mp_filterFolder = ""
local function MPIXELS_FX_init(folder)
    mp_filterFolder = folder
    -- Texturas com caminho absoluto da pasta do efeito (Bloco 7)
    mp_shader.textures.txLens1 = folder .. "mpixels_lens1.png"
    mp_shader.textures.txLens2 = folder .. "mpixels_lens2.png"
    mp_shader.textures.txDirt  = folder .. "mpixels_dirt1.png"
end

-- ============================================================================
-- UPDATE — read all SPICE params, pass to shader
-- ============================================================================
local function MPIXELS_FX_update(dt, ctrl_tbl)
    local active = pure.pp.get("schdr.MPIXELS_FX.active")
    if not active then return false end

    -- Luma Sharpening
    mp_shader.values.uSharpEnabled =
        (pure.pp.get("schdr.MPIXELS_FX.SharpEnabled") and 1 or 0)
    mp_shader.values.uSharpIntensity =
        pure.pp.get("schdr.MPIXELS_FX.SharpIntensity") or 2.5
    mp_shader.values.uSharpRadius =
        pure.pp.get("schdr.MPIXELS_FX.SharpRadius") or 1.0
    mp_shader.values.uSharpThreshold =
        pure.pp.get("schdr.MPIXELS_FX.SharpThreshold") or 0.0

    -- Unified Color Engine
    mp_shader.values.uColorEnabled =
        (pure.pp.get("schdr.MPIXELS_FX.ColorEnabled") and 1 or 0)
    mp_shader.values.uVibrance =
        pure.pp.get("schdr.MPIXELS_FX.Vibrance") or 0.25
    mp_shader.values.uMidtoneGamma =
        pure.pp.get("schdr.MPIXELS_FX.MidtoneGamma") or 1.0
    mp_shader.values.uWhitePoint =
        pure.pp.get("schdr.MPIXELS_FX.WhitePoint") or 1.0

    -- Clarity
    mp_shader.values.uClarityEnabled =
        (pure.pp.get("schdr.MPIXELS_FX.ClarityEnabled") and 1 or 0)
    mp_shader.values.uClarityIntensity =
        pure.pp.get("schdr.MPIXELS_FX.ClarityIntensity") or 0.125
    mp_shader.values.uClarityRadius =
        pure.pp.get("schdr.MPIXELS_FX.ClarityRadius") or 5.0

    -- Chromatic Aberration
    mp_shader.values.uChromaEnabled =
        (pure.pp.get("schdr.MPIXELS_FX.ChromaEnabled") and 1 or 0)
    mp_shader.values.uChromaUniformX =
        pure.pp.get("schdr.MPIXELS_FX.ChromaUniformX") or 0.5
    mp_shader.values.uChromaUniformY =
        pure.pp.get("schdr.MPIXELS_FX.ChromaUniformY") or 0.5
    mp_shader.values.uChromaLateralX =
        pure.pp.get("schdr.MPIXELS_FX.ChromaLateralX") or 0.5
    mp_shader.values.uChromaLateralY =
        pure.pp.get("schdr.MPIXELS_FX.ChromaLateralY") or 0.5

    -- Film Grain
    mp_shader.values.uGrainEnabled =
        (pure.pp.get("schdr.MPIXELS_FX.GrainEnabled") and 1 or 0)
    mp_shader.values.uGrainAmount =
        pure.pp.get("schdr.MPIXELS_FX.GrainAmount") or 1.0

    -- GoPro Lens Distortion
    mp_shader.values.uLensDistEnabled =
        (pure.pp.get("schdr.MPIXELS_FX.LensDistEnabled") and 1 or 0)
    mp_shader.values.uLensDistStrength =
        pure.pp.get("schdr.MPIXELS_FX.LensDistStrength") or 0.5
    mp_shader.values.uLensDistZoom =
        pure.pp.get("schdr.MPIXELS_FX.LensDistZoom") or 1.25

    -- Dashcam VHS
    mp_shader.values.uVhsEnabled =
        (pure.pp.get("schdr.MPIXELS_FX.VhsEnabled") and 1 or 0)
    mp_shader.values.uVhsScanline =
        pure.pp.get("schdr.MPIXELS_FX.VhsScanline") or 0.075
    mp_shader.values.uVhsJitter =
        pure.pp.get("schdr.MPIXELS_FX.VhsJitter") or 0.35

    -- Vignette (MALDITOS PIXELS extra)
    mp_shader.values.uVignetteEnabled =
        (pure.pp.get("schdr.MPIXELS_FX.VignetteEnabled") and 1 or 0)
    mp_shader.values.uVignetteStrength =
        pure.pp.get("schdr.MPIXELS_FX.VignetteStrength") or 0.30
    mp_shader.values.uVignetteFalloff =
        pure.pp.get("schdr.MPIXELS_FX.VignetteFalloff") or 2.5

    -- Black Bars
    mp_shader.values.uBlackBarsEnabled =
        (pure.pp.get("schdr.MPIXELS_FX.BlackBarsEnabled") and 1 or 0)
    mp_shader.values.uBlackBarsStyle =
        pure.pp.get("schdr.MPIXELS_FX.BlackBarsStyle") or 0

    -- Purkinje (driven by PPFilter script)
    mp_shader.values.uPurkinjeGlobalDrive =
        pure.pp.get("schdr.MPIXELS_FX.PurkinjeGlobalDrive") or 0
    mp_shader.values.uPurkinjeIntensity =
        pure.pp.get("schdr.MPIXELS_FX.PurkinjeIntensity") or 0.15
    mp_shader.values.uPurkinjeThreshold =
        pure.pp.get("schdr.MPIXELS_FX.PurkinjeThreshold") or 0.12

    -- Halation (13.6)
    mp_shader.values.uHalationEnabled =
        (pure.pp.get("schdr.MPIXELS_FX.HalationEnabled") and 1 or 0)
    mp_shader.values.uHalationIntensity =
        pure.pp.get("schdr.MPIXELS_FX.HalationIntensity") or 0.15
    mp_shader.values.uHalationRadius =
        pure.pp.get("schdr.MPIXELS_FX.HalationRadius") or 3.0
    mp_shader.values.uHalationWarmth =
        pure.pp.get("schdr.MPIXELS_FX.HalationWarmth") or 0.7
    mp_shader.values.uHalationThreshold =
        pure.pp.get("schdr.MPIXELS_FX.HalationThreshold") or 0.8

    -- Depth sharpening
    mp_shader.values.uDepthSharpEnabled =
        (pure.pp.get("schdr.MPIXELS_FX.DepthSharpEnabled") and 1 or 0)

    -- ---- Lens Flare (Bloco 7) ----
    mp_shader.values.uFlareEnabled =
        (pure.pp.get("schdr.MPIXELS_FX.FlareEnabled") and 1 or 0)
    mp_shader.values.uFlareIntensity =
        pure.pp.get("schdr.MPIXELS_FX.FlareIntensity") or 0.35
    mp_shader.values.uFlareThreshold =
        pure.pp.get("schdr.MPIXELS_FX.FlareThreshold") or 0.85
    mp_shader.values.uFlareMix =
        pure.pp.get("schdr.MPIXELS_FX.FlareMix") or 0.5

    -- ---- Lens Dirt (Bloco 7) ----
    mp_shader.values.uDirtEnabled =
        (pure.pp.get("schdr.MPIXELS_FX.DirtEnabled") and 1 or 0)
    mp_shader.values.uDirtIntensity =
        pure.pp.get("schdr.MPIXELS_FX.DirtIntensity") or 0.30
    mp_shader.values.uDirtThreshold =
        pure.pp.get("schdr.MPIXELS_FX.DirtThreshold") or 0.75

    -- ---- VHS / Glitch (Bloco 15) ----
    mp_shader.values.uVhsMaster =
        (pure.pp.get("schdr.MPIXELS_FX.VhsMaster") and 1 or 0)
    mp_shader.values.uVhsCurvature   = pure.pp.get("schdr.MPIXELS_FX.VhsCurvature") or 0.0
    mp_shader.values.uVhsScanline    = pure.pp.get("schdr.MPIXELS_FX.VhsScanline") or 0.25
    mp_shader.values.uVhsChromaSep   = pure.pp.get("schdr.MPIXELS_FX.VhsChromaSep") or 0.30
    mp_shader.values.uVhsChromaSmear = pure.pp.get("schdr.MPIXELS_FX.VhsChromaSmear") or 0.50
    mp_shader.values.uVhsRandomLines = pure.pp.get("schdr.MPIXELS_FX.VhsRandomLines") or 0.30
    mp_shader.values.uVhsHGlitch     = pure.pp.get("schdr.MPIXELS_FX.VhsHGlitch") or 0.30
    mp_shader.values.uVhsGrain       = pure.pp.get("schdr.MPIXELS_FX.VhsGrain") or 0.015
    mp_shader.values.uGlitchMaster =
        (pure.pp.get("schdr.MPIXELS_FX.GlitchMaster") and 1 or 0)
    mp_shader.values.uGlitchRate    = pure.pp.get("schdr.MPIXELS_FX.GlitchRate") or 0.50
    mp_shader.values.uGlitchRGB     = pure.pp.get("schdr.MPIXELS_FX.GlitchRGB") or 0.30
    mp_shader.values.uGlitchBlock   = pure.pp.get("schdr.MPIXELS_FX.GlitchBlock") or 0.02
    mp_shader.values.uGlitchDistort = pure.pp.get("schdr.MPIXELS_FX.GlitchDistort") or 0.10

    -- ---- Velocidade (Bloco 7) ----
    -- Zoom e trepidacao proporcionais a velocidade, com limiar.
    local spdOn   = pure.pp.get("schdr.MPIXELS_FX.SpeedFXEnabled")
    local spdZoom = pure.pp.get("schdr.MPIXELS_FX.SpeedZoom") or 0.02
    local spdShake= pure.pp.get("schdr.MPIXELS_FX.SpeedShake") or 0.0005
    local spdMin  = pure.pp.get("schdr.MPIXELS_FX.SpeedThreshold") or 80
    if spdOn then
        local kmh = 0
        local car = ac.getCar and ac.getCar(0)
        if car and car.speedKmh then kmh = car.speedKmh end
        local f = math.max(0, math.min((kmh - spdMin) / 150, 1))
        mp_shader.values.uSpeedZoom = 1.0 + f * spdZoom
        local t = os.preciseClock()
        mp_shader.values.uSpeedShakeX = math.sin(t * 37.0) * f * spdShake
        mp_shader.values.uSpeedShakeY = math.cos(t * 31.0) * f * spdShake
    else
        mp_shader.values.uSpeedZoom = 1.0
        mp_shader.values.uSpeedShakeX = 0.0
        mp_shader.values.uSpeedShakeY = 0.0
    end

    -- Time
    mp_shader.values.uTime = os.preciseClock()

    return active
end

-- ============================================================================
-- REGISTRO
-- ============================================================================
SPICE_HDR__addFilter("MPIXELS_FX", MPIXELS_FX_render, MPIXELS_FX_init, MPIXELS_FX_update)
