-- ============================================================================
-- MALDITOS PIXELS — SPICE LDR effect (Bloco 8)
-- Grain, vinheta, aberracao cromatica e barras. Espaco 0..1, pos-tonemap.
-- ============================================================================

local shader_main = [[
    // ------------------------------------------------------------------
    // HASH12 — ruido procedural por pixel (Quilez / Book of Shaders).
    // Monocromatico e com variacao temporal, como grao de filme real.
    // ------------------------------------------------------------------
    float hash12(float2 p) {
        float3 p3 = frac(float3(p.xyx) * 0.1031);
        p3 += dot(p3, p3.yzx + 33.33);
        return frac((p3.x + p3.y) * p3.z);
    }

    float4 main(PS_IN pin) {
        float2 uv = pin.Tex;

        // ------------------------------------------------------------------
        // 1. ABERRACAO CROMATICA — radial, com centro limpo
        // ------------------------------------------------------------------
        float3 color;
        if (uCaEnabled > 0.5) {
            float2 c = uv - 0.5;
            float  r = length(c) * 2.0;
            float  k = pow(saturate(r), uCaFalloff) * uCaStrength;
            float2 dir = (r > 1e-5) ? (c / max(length(c), 1e-5)) : float2(0, 0);
            // margem de seguranca nas bordas evita sangramento
            float2 uvR = clamp(uv + dir * k,        0.001, 0.999);
            float2 uvB = clamp(uv - dir * k,        0.001, 0.999);
            color.r = txInput.SampleLevel(samLinear, uvR, 0).r;
            color.g = txInput.SampleLevel(samLinear, uv,  0).g;
            color.b = txInput.SampleLevel(samLinear, uvB, 0).b;
        } else {
            color = txInput.SampleLevel(samLinear, uv, 0).rgb;
        }

        float luma = dot(color, float3(0.2126, 0.7152, 0.0722));

        // ------------------------------------------------------------------
        // 2. FILM GRAIN — mascarado por luminancia nos dois extremos.
        // Sem grao no preto (senao levanta a sombra) e reduzido no highlight
        // (senao ferve com upscaler temporal).
        // ------------------------------------------------------------------
        if (uGrainEnabled > 0.5) {
            float2 gp = uv * uScreenSize / max(uGrainSize, 0.01);
            // variacao temporal quantizada: muda por frame, nao por micro-segundo
            float  t  = floor(uTime * 24.0);
            float  n  = hash12(gp + t * 17.31) - 0.5;

            float shadowMask    = smoothstep(0.0, uGrainShadowLift, luma);
            float highlightMask = 1.0 - smoothstep(uGrainHighlightCut, 1.0, luma);
            float mask = shadowMask * highlightMask;

            color += n * uGrainIntensity * mask;
        }

        // ------------------------------------------------------------------
        // 3. VINHETA
        // ------------------------------------------------------------------
        if (uVigEnabled > 0.5) {
            float2 c = uv - 0.5;
            c.x *= lerp(1.0, uScreenSize.x / max(uScreenSize.y, 1.0), saturate(uVigRoundness));
            float d = saturate(length(c) * 1.4142);
            float v = 1.0 - pow(d, uVigFalloff) * uVigStrength;
            color *= max(v, 0.0);
        }

        // ------------------------------------------------------------------
        // 4. BARRAS
        // ------------------------------------------------------------------
        if (uBarsEnabled > 0.5) {
            if (pin.Tex.y < uBarsSize || pin.Tex.y > (1.0 - uBarsSize)) {
                color = float3(0, 0, 0);
            }
        }

        return float4(max(color, 0.0), 1.0);
    }
]]

local shader_table = {
    -- OBRIGATORIO: o loop LDR do Pure chama shader.p2:set(size) todo frame.
    -- Sem p1/p2 declarados como vec2, isso estoura e derruba a cadeia LDR
    -- inteira — tela preta em jogo (na pausa a cadeia nao roda, por isso
    -- a imagem "voltava").
    p1 = vec2(),
    p2 = vec2(),
    blendMode = render.BlendMode.Opaque,
    textures = {
        txInput = 'dynamic::screen',
    },
    values = {
        uScreenSize        = vec2(render.getRenderTargetSize().x, render.getRenderTargetSize().y),
        uTime              = 0,
        -- grain
        uGrainEnabled      = 0,
        uGrainIntensity    = 0.030,
        uGrainSize         = 1.0,
        uGrainShadowLift   = 0.12,
        uGrainHighlightCut = 0.85,
        -- vinheta
        uVigEnabled        = 0,
        uVigStrength       = 0.30,
        uVigFalloff        = 2.5,
        uVigRoundness      = 1.0,
        -- aberracao cromatica
        uCaEnabled         = 0,
        uCaStrength        = 0.0015,
        uCaFalloff         = 2.0,
        -- barras
        uBarsEnabled       = 0,
        uBarsSize          = 0.10,
    },
    shader = shader_main,
}

local function MPIXELS_LDR_init(folder)
end

local function MPIXELS_LDR_update(dt, ctrl_tbl, input)
    -- O contrato do Pure e update(dt, ctrl_tbl, input) e a leitura dos
    -- controles e por ctrl_tbl["<nome>_<chave>"], nao por pure.pp.get.
    local function C(k, def)
        local v = ctrl_tbl and ctrl_tbl["MPIXELS_LDR_" .. k]
        if v == nil then return def end
        return v
    end

    local active = C("active", false)
    if not active then return false end

    -- BUG 2: sem ligar o input, txInput fica no placeholder e sai preto.
    if input ~= nil then shader_table.textures.txInput = input end

    local v = shader_table.values
    v.uScreenSize = vec2(render.getRenderTargetSize().x, render.getRenderTargetSize().y)
    v.uTime = os.preciseClock()

    v.uGrainEnabled      = C("GrainEnabled", false) and 1 or 0
    v.uGrainIntensity    = C("GrainIntensity", 0.030)
    v.uGrainSize         = C("GrainSize", 1.0)
    v.uGrainShadowLift   = C("GrainShadowLift", 0.12)
    v.uGrainHighlightCut = C("GrainHighlightCut", 0.85)

    v.uVigEnabled   = C("VigEnabled", false) and 1 or 0
    v.uVigStrength  = C("VigStrength", 0.30)
    v.uVigFalloff   = C("VigFalloff", 2.5)
    v.uVigRoundness = C("VigRoundness", 1.0)

    v.uCaEnabled  = C("CaEnabled", false) and 1 or 0
    v.uCaStrength = C("CaStrength", 0.0015)
    v.uCaFalloff  = C("CaFalloff", 2.0)

    v.uBarsEnabled = C("BarsEnabled", false) and 1 or 0
    v.uBarsSize    = C("BarsSize", 0.10)

    return active
end

SPICE_LDR__addFilter("MPIXELS_LDR", shader_table, MPIXELS_LDR_init, MPIXELS_LDR_update, true)
