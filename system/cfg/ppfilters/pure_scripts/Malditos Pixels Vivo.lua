-- ============================================================================
--  MALDITOS PIXELS v1.0 (Fase 12.15)
--
--  Tonemapping: 3 modos (GT7-Blend / Pixels-Tone / GT-Film)
--  Exposicao: estrutura calibrada (Dia/Noite/Tunel)
--  Color: dia/noite (sat/gamma/temp/sepia/vignette) + LUT
--  Bloom: Camera style (dia/noite Glarefunc) + Ghost
--  World: Clouds (brightness/contrast) + Stellar (sun/moon/stars) + Rainbow
--  Reflections: Pixels Spec (fresnel/CPL/level/saturation)
--  FX: SPICE MPIXELS_FX (10 efeitos) + Purkinje
--  Skydome: Off default
--
--  Zero valor morto. Cada param → API documentada.
-- ============================================================================

-- ============================================================================
-- DETECCAO DE VARIANTE
-- ============================================================================
local MP_VERSION = "1.0"
local MP_VARIANT = "Rachadores"

do
    local filter_name = ac.getPpFilter() or ""
    -- BUG FIX (14.0): ac.getPpFilter() retorna o nome COM ".ini"
    -- (SDK ac_pp_filters: "Returns name of current PP filter with .ini").
    -- O padrao antigo exigia terminar em letra (%a+$) -> match sempre nil
    -- -> TODAS as variantes rodavam como "Rachadores".
    filter_name = filter_name:gsub("%.[Ii][Nn][Ii]$", "")
    local mode = filter_name:match("^Malditos Pixels%s+(%a+)$")
    local detected = mode or "Rachadores"
    local valid = { Rachadores=true, Cinema=true, Puro=true, Vivo=true, Madrugada=true }
    if valid[detected] then
        MP_VARIANT = detected
    end
end

ac.log("[MPIXELS] MALDITOS PIXELS " .. MP_VERSION .. " | variante=" .. MP_VARIANT
    .. " | ppfilter=" .. tostring(ac.getPpFilter()))

-- ============================================================================
-- DELTAS POR VARIANTE
-- ============================================================================
local VARIANT_DELTAS = {
    -- ══════════════════════════════════════════════════════════════════════
    -- ANCORA: Core (12.25). Todas as variantes = Core + delta deliberado.
    -- Doc 07 atualizado. LUTs: mpixels_rachadores/cinema/puro/vivo/madrugada.png
    -- ══════════════════════════════════════════════════════════════════════
    --
    -- CORE — equilibrio referencia+identidade. Ancora de tudo.
    Rachadores = {
        sat=1.10,  temp=6500, contrast_post=1.09, night_shift=250,
        soft_clip=0.95, lut_int=0.80,
        purk_int=0.12, purk_thr=0.12, purk_mult=1.0,
        skip_extras=false,
    },
    --
    -- CINE — drama cinematografico
    -- Deltas: +contrast, +night_shift (sombras mais frias), +lut (grade mais presente),
    --         temp mais quente (highlights dourados), purk sutil.
    Cinema  = {
        sat=1.08,  temp=6600, contrast_post=1.20, night_shift=350,
        soft_clip=0.93, lut_int=0.90,
        purk_int=0.10, purk_thr=0.12, purk_mult=1.0,
        skip_extras=false,
    },
    --
    -- NATURAL — fidelidade documental
    -- Deltas: -sat, -contrast (flat), -night_shift (noite neutra), -lut (grade minima),
    --         soft_clip aberto (mais headroom), purk reduzido.
    Puro    = {
        sat=0.98,  temp=6500, contrast_post=1.02, night_shift=100,
        soft_clip=1.00, lut_int=0.40,
        purk_int=0.06, purk_thr=0.12, purk_mult=0.5,
        skip_extras=false,
    },
    --
    -- VIVID — impacto visual
    -- Deltas: +sat (com soft_clip mais agressivo pra nao clipar), +lut,
    --         resto proximo do Core.
    Vivo    = {
        sat=1.28,  temp=6500, contrast_post=1.09, night_shift=250,
        soft_clip=0.85, lut_int=0.85,
        purk_int=0.12, purk_thr=0.12, purk_mult=1.0,
        skip_extras=false,
    },
    --
    -- NIGHT — noturno/assinatura MALDITOS PIXELS
    -- Deltas: -sat (noite desaturada), temp fria, +contrast leve (separacao),
    --         +night_shift (sombras mais frias), -lut (grade sutil), Purkinje
    --         PRONUNCIADO (purk_mult 2.0, int 0.25, thr baixo), purk ON por padrao.
    Madrugada= {
        sat=0.95,  temp=6200, contrast_post=1.12, night_shift=400,
        soft_clip=0.95, lut_int=0.65,
        purk_int=0.25, purk_thr=0.10, purk_mult=2.0,
        skip_extras=false,
    },
}

local D = VARIANT_DELTAS[MP_VARIANT] or VARIANT_DELTAS.Rachadores

-- ============================================================================
-- SCALING FACTORS (derivados da captura referencia API)
-- referencia UI → Pure API: documentado para calibracao
--
-- CAPTURA (dia, n=0.000):
--   handleExposure(2, {target=1, mix=1, method=5, fixedexposure=0.5,
--                      minimumexposure=0.035, superexposure=0.75})
--   CBE limits: 0.035, 0.75
--   CBE speeds: 10, 10
--   CBE target: 0.82 (constante por frame)
--
-- referencia UI (dia):
--   Target Exposure=0.075, Sensitivity=3.0, AE Target=3.0, AE Mix=0.85
--
-- SCALES:
--   AE Target → CBE Target: 3.0 → 0.82 → scale = 0.2733
--   Sensitivity → CBE max: 3.0 → 0.75 → scale = 0.25
--   Sensitivity → CBE speed: 3.0 → 10 → scale = 3.333
--   Target Exp → fixedexposure: 0.075 → 0.5 → scale = 6.667
-- ============================================================================
-- (scaling factors removidos — exposicao agora e adaptativa, 13.2)

-- ============================================================================
-- STATE
-- ============================================================================
-- (mp_prevExposure removido — flash gate substituido por adaptacao assimetrica 13.2)
local mp_cover = nil
local mp_skydomePaths = {
    "system/cfg/ppfilters/pure_scripts/textures/mpixels_milkyway.dds",
    "system/cfg/ppfilters/pure_scripts/textures/mpixels_aurora.dds",
    "system/cfg/ppfilters/pure_scripts/textures/mpixels_twilight.dds",
    "system/cfg/ppfilters/pure_scripts/textures/mpixels_starfield.dds",
    "system/cfg/ppfilters/pure_scripts/textures/mpixels_overcast.dds",
}
local mp_currentSkydome = -1
local mp_frameCount = 0

-- Bloom state (written by update, read by Glarefunc callback)
_mp_bloom = nil

-- ============================================================================
-- MOTOR DE COR CSP (Bloco 3)
-- Pilha de correcao de cor NATIVA do CSP, abaixo do estagio de PP.
-- Sete nos registrados uma vez no init e modulados por frame.
-- Cada linha de perfil: { r, g, b, r1, g1, b1, temp, lum, contraste, sepia,
--                         matiz, saturacao, fade }
-- ============================================================================
local mp_cc = nil   -- preenchido no init

-- ============================================================================
-- GLARE POR PERFIL, SEPARADO DIA/NOITE (Bloco 6)
-- Portado da referencia licenciada. Os dois conjuntos SOMAM, cada um pesado
-- pela sua compensacao — de dia o bloco noturno vale zero e vice-versa.
-- Perfil 1 (Sobrio) e o unico com ghost e halo praticamente zerados: e o que
-- respeita o checklist anti-arco-iris. O perfil 2 e o chamativo.
-- Campos: thresh, lum, gamma, bloomLum, starSoft, gaussR, starLum,
--         starLen, starLen2, streaks, ghost, halo, distort, sharp, disp
-- ============================================================================
local MP_GLARE_DIA = {
    -- 1 Sobrio
    { thresh=0.30, lum=3.00, gamma=1.478, bloomLum=0.183, starSoft=0.500,
      gaussR=0.95, starLum=0.000, starLen=0.21, starLen2=1.00, streaks=7,
      ghost=0.000, halo=0.0033, distort=0, sharp=0.00, disp=0.03 },
    -- 2 Cinematico
    { thresh=0.20, lum=0.60, gamma=1.000, bloomLum=0.600, starSoft=0.000,
      gaussR=1.20, starLum=0.680, starLen=0.05, starLen2=0.05, streaks=2,
      ghost=0.116, halo=0.0010, distort=0, sharp=0.08, disp=0.30 },
    -- 3 Difuso
    { thresh=0.06, lum=3.00, gamma=1.000, bloomLum=0.400, starSoft=0.645,
      gaussR=1.25, starLum=0.300, starLen=0.34, starLen2=1.20, streaks=8,
      ghost=0.000, halo=0.0000, distort=7, sharp=0.00, disp=0.10 },
    -- 4 Solar (limiar altissimo: quase nada dispara)
    { thresh=75.0, lum=0.10, gamma=0.900, bloomLum=3.000, starSoft=2.000,
      gaussR=3.00, starLum=1.946, starLen=0.00, starLen2=0.08, streaks=4,
      ghost=0.000, halo=0.0000, distort=7, sharp=0.00, disp=0.00 },
    -- 5 Suave
    { thresh=0.60, lum=7.00, gamma=1.290, bloomLum=0.060, starSoft=0.500,
      gaussR=0.95, starLum=0.000, starLen=0.00, starLen2=0.00, streaks=7,
      ghost=0.000, halo=0.0000, distort=0, sharp=0.00, disp=0.03 },
    -- 6 Denso
    { thresh=1.50, lum=5.00, gamma=1.000, bloomLum=0.300, starSoft=0.500,
      gaussR=1.20, starLum=2.300, starLen=0.10, starLen2=0.10, streaks=7,
      ghost=0.000, halo=0.0000, distort=7, sharp=0.00, disp=0.20 },
    -- 7 Estelar
    { thresh=1.50, lum=6.00, gamma=1.000, bloomLum=0.330, starSoft=0.050,
      gaussR=1.20, starLum=6.000, starLen=0.20, starLen2=0.22, streaks=2,
      ghost=0.000, halo=0.0000, distort=7, sharp=0.00, disp=0.10 },
    -- 8 Intenso
    { thresh=1.50, lum=8.00, gamma=1.000, bloomLum=0.200, starSoft=0.050,
      gaussR=1.20, starLum=5.000, starLen=0.12, starLen2=0.10, streaks=6,
      ghost=0.000, halo=0.0000, distort=7, sharp=0.00, disp=0.10 },
}

local MP_GLARE_NOITE = {
    -- 1 Sobrio
    { thresh=0.25, lum=2.50, gamma=2.688, bloomLum=0.1167, starSoft=0.500,
      gaussR=0.95, starLum=0.000, starLen=0.21, starLen2=1.00, streaks=7,
      ghost=0.000, halo=0.0033, distort=0, sharp=0.00, disp=0.03 },
    -- 2 Cinematico
    { thresh=0.30, lum=1.00, gamma=2.200, bloomLum=0.6000, starSoft=0.300,
      gaussR=1.30, starLum=0.680, starLen=0.05, starLen2=0.05, streaks=2,
      ghost=0.360, halo=1.0000, distort=0.1, sharp=0.08, disp=0.30 },
    -- 3 Difuso
    { thresh=0.30, lum=0.34, gamma=2.300, bloomLum=3.0000, starSoft=0.645,
      gaussR=2.50, starLum=0.010, starLen=0.14, starLen2=0.30, streaks=4,
      ghost=0.010, halo=0.0100, distort=7, sharp=0.00, disp=0.10 },
    -- 4 Solar
    { thresh=0.85, lum=0.50, gamma=1.920, bloomLum=3.0000, starSoft=0.000,
      gaussR=1.00, starLum=2.150, starLen=0.20, starLen2=0.00, streaks=2,
      ghost=0.000, halo=0.0000, distort=0, sharp=0.00, disp=0.30 },
    -- 5 Suave
    { thresh=0.40, lum=1.50, gamma=2.500, bloomLum=0.2000, starSoft=0.000,
      gaussR=2.00, starLum=0.500, starLen=0.20, starLen2=0.20, streaks=4,
      ghost=0.000, halo=0.0000, distort=5, sharp=0.00, disp=0.30 },
    -- 6 Denso
    { thresh=0.80, lum=3.00, gamma=2.800, bloomLum=0.0700, starSoft=0.500,
      gaussR=1.10, starLum=0.000, starLen=0.00, starLen2=0.00, streaks=7,
      ghost=0.000, halo=0.0000, distort=0, sharp=0.00, disp=0.03 },
    -- 7 Estelar
    { thresh=1.20, lum=1.00, gamma=2.000, bloomLum=1.0000, starSoft=0.500,
      gaussR=1.25, starLum=1.680, starLen=0.13, starLen2=0.14, streaks=4,
      ghost=0.000, halo=0.0000, distort=0, sharp=0.00, disp=0.03 },
    -- 8 Intenso
    { thresh=2.20, lum=2.12, gamma=1.615, bloomLum=0.3300, starSoft=0.050,
      gaussR=1.20, starLum=1.200, starLen=0.10, starLen2=0.10, streaks=6,
      ghost=0.000, halo=0.0100, distort=7, sharp=0.00, disp=0.10 },
}

-- ============================================================================
-- MISTURA DE COR DO FOG LEGADO (Bloco 17)
-- A referencia faz math.lerp(rgb, rgb, t) / escalar direto. Aqui e feito
-- componente a componente: nao depende de sobrecarga de operador em rgb e
-- fica obvio no diff o que esta acontecendo.
-- ============================================================================
local function mp_fogMix(a, b, t, div)
    div = (div == nil or div == 0) and 1 or div
    return rgb((a.r + (b.r - a.r) * t) / div,
               (a.g + (b.g - a.g) * t) / div,
               (a.b + (b.b - a.b) * t) / div)
end

-- Estado do glare, escrito pelo update e lido pelo callback Glarefunc
_mp_glare = nil

-- Multiplicador anamorfico (Bloco 16). 1 = desligado, 3 = ativo.
-- Lido por Glarefunc; mesma mecanica da referencia (anamorphmod).
_mp_anamorph = 1

-- ============================================================================
-- ESTADOS PERSISTENTES DA EXPOSICAO (Bloco 11)
-- A cadeia de crossover da referencia tem realimentacao entre frames:
-- exposureAdjustment consome o FinalTarget do frame ANTERIOR.
-- ============================================================================
local mp_CbeThreshold = 0
local mp_FinalTarget  = 1
local mp_occluded     = 1
-- Memo de resolucao de sombra (Bloco 16): evita rechamar a API todo frame
local mp_shadowRes = nil
local MP_OCC_X1  = vec3(1, 0, 0)
local MP_OCC_X_1 = vec3(-1, 0, 0)

-- ============================================================================
-- FOG POR ANGULO SOLAR (Bloco 4)
-- LUT interpolada linearmente por elevacao do sol (-5 a 90 graus).
-- A arquitetura e MULTIPLICATIVA: pega a tabela que o Pure ja calculou e
-- escala por cima. Tentativas anteriores usavam valor absoluto e geravam
-- cast marrom — nao brigar com o Pure e o ponto todo.
-- ============================================================================
local function mp_fogLUT(dados, ang)
    if not dados or #dados == 0 then return 1 end
    if #dados == 1 then return dados[1][2] or 1 end
    if ang <= dados[1][1] then return dados[1][2] or 1 end
    for i = 1, #dados - 1 do
        local a, b = dados[i], dados[i + 1]
        if ang >= a[1] and ang <= b[1] then
            local t = (ang - a[1]) / math.max(b[1] - a[1], 0.001)
            return (a[2] or 1) * (1 - t) + (b[2] or 1) * t
        end
    end
    return dados[#dados][2] or 1
end

local MP_FOG = {
    densidade  = { {-5, 1.75}, {15, 1.65}, {60, 1.55}, {90, 1.55} },
    distancia  = { {-5, 1.00}, {15, 1.00}, {60, 1.00}, {90, 1.00} },
    blend      = { {-5, 0.65}, {15, 0.75}, {60, 0.85}, {90, 0.85} },
    expoente   = { {-5, 0.65}, {15, 0.80}, {60, 0.95}, {90, 0.95} },
    contraluz  = { {-5, 1.25}, {15, 1.15}, {60, 1.05}, {90, 1.05} },
    saturacao  = { {-5, 1.00}, {15, 1.00}, {60, 1.00}, {90, 1.00} },
}

local MP_COR_DIA = {
    { 1,   1,    1,    1,     1,     1,     6500, 1,    1,    0,     0,    1,      0     },
    { 1,   1,    1,    1,     1,     1,     5200, 1,    1,    0.10,  0,    1.150,  0.001 },
    { 1,   1,    1,    1,     1.01,  1,     7600, 1,    1,    0,     0,    1.125,  0     },
    { 1,   1,    1,    1,     1,     1,     6700, 1,    1,    0,     3,    1.010,  0     },
    { 1,   1,    1,    1,     1,     1,     6800, 1,    1,    0.20,  3,    1.1745, 0     },
    { 1,   1,    1,    0.888, 0.95,  0.9,   8700, 1,    1,    0.26,  3.8,  1.177,  0     },
    { 0.8, 1,    0.78, 0.8,   1,     0.78,  9750, 1,    0.95, 0.25,  3.75, 0.875,  0.01  },
    { 1,   1.01, 1,    1,     1,     1,     6700, 1,    1,    0.30,  0,    1,      0.01  },
    { 1,   1,    1,    0.99,  1,     0.904, 7499, 1,    1,    0.12,  0,    1,      0     },
    { 1,   1,    1,    1,     1,     1,     6700, 1,    1,    0,     0,    1,      0     },
    { 1,   1,    1,    1,     1,     1,     6500, 1,    1,    0.20,  3,    1,      0     },
}

local MP_COR_NOITE = {
    { 1,   1,    1,    1,     1,     1,     6500, 1,    1,    0,     0,    1,      0     },
    { 1,   1,    1,    1,     1,     1,     5200, 1,    1,    0.15,  0,    1.10,   0.001 },
    { 1,   1,    1,    1,     1.01,  1,     7600, 1,    1,    0.15,  0,    1,      0     },
    { 1,   1,    1,    1,     1,     1,     6700, 1,    1,    0.15,  3,    1,      0     },
    { 1,   1,    1,    1,     1,     1,     6700, 1,    1,    0.15,  3,    1,      0     },
    { 1,   1,    1,    1,     1.01,  1,     6800, 1,    1,    0.15,  3,    1,      0     },
    { 1,   1,    1,    0.888, 0.95,  0.9,   8700, 1,    1,    0.26,  3.8,  1.05,   0     },
    { 1,   1,    1,    0.7,   1,     0.775, 9600, 1,    0.97, 0.30,  3,    0.90,   0     },
    { 1,   1,    1,    1,     1,     1,     6700, 1,    1,    0.30,  0,    1,      0.01  },
    { 1,   1,    1,    0.99,  1,     0.904, 7499, 1,    1,    0.12,  0,    1,      0     },
    { 1,   1,    1,    1,     1,     1,     6700, 1,    1,    0.15,  0,    1,      0     },
}

-- ============================================================================
-- SUAVIZACAO TEMPORAL (13.3 — nosso diferencial sobre a referencia)
-- Filtro de 1a ordem com constante assimetrica (subida vs descida)
-- ============================================================================
local function lagAsym(atual, alvo, tauSubida, tauDescida, dt)
    local tau = (alvo > atual) and tauSubida or tauDescida
    local k = math.max(0, math.min(1, dt / math.max(tau, 0.0001)))
    return atual + (alvo - atual) * k
end

-- ============================================================================
-- BLINDAGEM POR SECAO (14.6 — Bloco 0)
-- Uma secao que quebra vira uma secao morta, nao um filtro morto.
-- O erro e logado UMA VEZ por secao, nao por frame.
-- ============================================================================
local mp_secErr = {}
local function mp_sec(nome, fn)
    local ok, err = pcall(fn)
    if not ok and not mp_secErr[nome] then
        mp_secErr[nome] = true
        ac.log("[MPIXELS] *** ERRO na secao " .. nome .. " *** " .. tostring(err))
        ac.log("[MPIXELS] *** log desta secao suprimido a partir daqui ***")
    end
    return ok
end


-- Estados suavizados (escopo de modulo — persistem entre frames)
local mp_smooth_occlusion = 1.0    -- tunel/viaduto
local mp_smooth_rain      = 0.0    -- chuva intensidade
local mp_smooth_wetness   = 0.0    -- superficie molhada
local mp_smooth_water     = 0.0    -- pocas
local mp_smooth_badness   = 0.0    -- clima ruim
local mp_smooth_glare_f   = 1.0    -- fator de glare
local mp_smooth_speed     = 0.0    -- velocidade suavizada
local mp_isNight          = false  -- histerese dia/noite

-- ============================================================================
-- SHADER HLSL — 3 MODOS (GT7-Blend / Pixels-Tone / GT-Film) (GT7-Blend / referencia-Tone / GT-Film)
-- Source: runtime capture (405 linhas)
-- ============================================================================
local MPIXELS_TONEMAP_SHADER = [[
    float frameBufferValueToPhysicalValue(float fbValue) { return fbValue * REF_LUMINANCE; }
    float physicalValueToFrameBufferValue(float physical) { return physical / REF_LUMINANCE; }

    float smoothStep_GT(float x, float edge0, float edge1) {
        float diff = edge1 - edge0;
        if (abs(diff) < 1e-6) return step(edge0, x);
        float t = clamp((x - edge0) / diff, 0.0, 1.0);
        return t * t * (3.0 - 2.0 * t);
    }
    float chromaCurve(float x, float a, float b) {
        return 1.0 - smoothStep_GT(x, a, b);
    }

    float3 apply_post_scurve(float3 x, float amount) {
        float3 low = saturate(x);
        float3 high = max(x - 1.0, 0.0);
        float3 curve = low * low * (3.0 - 2.0 * low);
        return lerp(low, curve, amount) + high;
    }
    float3 apply_post_gamma(float3 color, float g) {
        if (abs(g - 1.0) < 0.01) return color;
        return pow(max(color, 0.0), 1.0/g);
    }
    float3 apply_post_sat(float3 color, float s) {
        float luma = dot(color, float3(0.2126, 0.7152, 0.0722));
        return lerp(luma, color, s);
    }

    // Highlight compression (standard, k=0.65)
    float3 compress_highlights(float3 color) {
        float luma = dot(color, float3(0.2126, 0.7152, 0.0722));
        if (luma <= 1.0) return color;
        float t = luma - 1.0;
        float k = 0.65;
        float compressed = 1.0 + (t / (1.0 + k * t));
        return color * (compressed / luma);
    }

    // Highlight compression (film, k=1.35 — stronger)
    float3 compress_highlights_film(float3 color) {
        float luma = dot(color, float3(0.2126, 0.7152, 0.0722));
        if (luma <= 1.0) return color;
        float t = luma - 1.0;
        float k = 1.35;
        float compressed = 1.0 + (t / (1.0 + k * t));
        return color * (compressed / luma);
    }

    // ST-2084 (PQ)
    float inverseEotfSt2084(float v) {
        const float m1 = 0.1593017578125; const float m2 = 78.84375;
        const float c1 = 0.8359375; const float c2 = 18.8515625; const float c3 = 18.6875;
        const float pqC = 10000.0;
        float physical = frameBufferValueToPhysicalValue(v);
        float y = physical / pqC;
        float ym = pow(max(y, 1e-6), m1);
        return pow(2.0, m2 * (log2(c1 + c2 * ym) - log2(1.0 + c3 * ym)));
    }
    float eotfSt2084(float n) {
        const float m1 = 0.1593017578125; const float m2 = 78.84375;
        const float c1 = 0.8359375; const float c2 = 18.8515625; const float c3 = 18.6875;
        const float pqC = 10000.0;
        float np = pow(max(n, 0.0), 1.0/m2);
        float l = max(np - c1, 0.0);
        l = l / (c2 - c3 * np);
        l = pow(max(l, 0.0), 1.0/m1);
        return physicalValueToFrameBufferValue(l * pqC);
    }

    // ICtCp (BT.2100)
    float3 rgbToICtCp(float3 rgb) {
        float l = (rgb.r * 1688.0 + rgb.g * 2146.0 + rgb.b * 262.0) / 4096.0;
        float m = (rgb.r * 683.0 + rgb.g * 2951.0 + rgb.b * 462.0) / 4096.0;
        float s = (rgb.r * 99.0 + rgb.g * 309.0 + rgb.b * 3688.0) / 4096.0;
        float lPQ = inverseEotfSt2084(l); float mPQ = inverseEotfSt2084(m); float sPQ = inverseEotfSt2084(s);
        float I = (2048.0 * lPQ + 2048.0 * mPQ) / 4096.0;
        float Ct = (6610.0 * lPQ - 13613.0 * mPQ + 7003.0 * sPQ) / 4096.0;
        float Cp = (17933.0 * lPQ - 17390.0 * mPQ - 543.0 * sPQ) / 4096.0;
        return float3(I, Ct, Cp);
    }
    float3 iCtCpToRgb(float3 ictcp) {
        float I = ictcp.x; float Ct = ictcp.y; float Cp = ictcp.z;
        float l = I + 0.00860904 * Ct + 0.11103 * Cp;
        float m = I - 0.00860904 * Ct - 0.11103 * Cp;
        float s = I + 0.560031 * Ct - 0.320627 * Cp;
        float lLin = eotfSt2084(l); float mLin = eotfSt2084(m); float sLin = eotfSt2084(s);
        float r = max(3.43661 * lLin - 2.50645 * mLin + 0.0698454 * sLin, 0.0);
        float g = max(-0.79133 * lLin + 1.9836 * mLin - 0.192271 * sLin, 0.0);
        float b = max(-0.0259499 * lLin - 0.0989137 * mLin + 1.12486 * sLin, 0.0);
        return float3(r, g, b);
    }

    // Uchimura curve (used by GT7-Blend and GT-Film)
    float uchimura(float x, float P, float a, float m, float l, float c, float b) {
        float l0 = ((P - m) * l) / a;
        float S0 = m + l0;
        float S1 = m + a * l0;
        float C2 = (a * P) / (P - S1);
        float CP = -C2 / P;
        float w0 = 1.0 - smoothstep(0.0, m, x);
        float w2 = step(m + l0, x);
        float w1 = 1.0 - w0 - w2;
        float T = m * pow(max(x / m, 0.0), c) + b;
        float L = m + a * (x - m);
        float S = P - (P - S1) * exp(CP * (x - S0));
        return T * w0 + L * w1 + S * w2;
    }

    // ================================================================
    // MODE 0: GT7-Blend (ICtCp + Uchimura + chroma + red emissive)
    // ================================================================
    float3 Logic_GT7_Hybrid(float3 rgb) {
        rgb *= gt7_white;
        float fbTarget = gt7_P;
        float3 ucs = rgbToICtCp(rgb);
        float3 skewedRgb;
        skewedRgb.r = uchimura(rgb.r, gt7_P, gt7_a, gt7_m, gt7_l, gt7_c, gt7_b);
        skewedRgb.g = uchimura(rgb.g, gt7_P, gt7_a, gt7_m, gt7_l, gt7_c, gt7_b);
        skewedRgb.b = uchimura(rgb.b, gt7_P, gt7_a, gt7_m, gt7_l, gt7_c, gt7_b);
        float3 skewedUcs = rgbToICtCp(skewedRgb);
        float3 targetRgb = float3(fbTarget, fbTarget, fbTarget);
        float3 targetUcsVec = rgbToICtCp(targetRgb);
        float fbTargetUcs = targetUcsVec.x;
        float ucsRatio = (fbTargetUcs > 0.0001) ? (ucs.x / fbTargetUcs) : 0.0;
        float chromaScale = chromaCurve(ucsRatio, gt7_fade_start, 1.16);
        float3 scaledUcs = float3(skewedUcs.x, ucs.y * chromaScale, ucs.z * chromaScale);
        float3 scaledRgb = iCtCpToRgb(scaledUcs);
        float lumaIn = dot(rgb, float3(0.2126, 0.7152, 0.0722));
        float redMask = saturate((rgb.r - max(rgb.g, rgb.b)) * 3.0) * smoothstep(0.05, 0.80, rgb.r);
        float taillightMask = redMask * smoothstep(0.02, 0.35, lumaIn);
        float highlightMask = smoothstep(0.80, 1.25, lumaIn);
        float blendFactor = gt7_blend * (1.0 - 0.35 * taillightMask) * (1.0 - 0.25 * highlightMask);
        float3 result = lerp(skewedRgb, scaledRgb, saturate(blendFactor));
        result = apply_post_scurve(result, gt7_s_curve);
        result = apply_post_gamma(result, gt7_gamma);
        result = apply_post_sat(result, gt7_sat);
        float tailLuma = dot(result, float3(0.2126, 0.7152, 0.0722));
        float tailMaskStrong = saturate(taillightMask * smoothstep(0.10, 0.90, rgb.r) * 1.35);
        float3 tailNeutral = float3(tailLuma, tailLuma, tailLuma);
        result = lerp(result, tailNeutral, 0.32 * tailMaskStrong);
        result *= (1.0 + 0.28 * tailMaskStrong);
        return result;
    }

    // ================================================================
    // MODE 1: referencia-Tone (custom curve + color matrices)
    // ================================================================
    float3 adjust_shadow_density(float3 color, float strength) {
        float luma = dot(color, float3(0.2126, 0.7152, 0.0722));
        float mask = 1.0 - smoothstep(0.0, 0.8, luma);
        return pow(max(color, 0.0), 1.0 + (strength * mask));
    }
    float px_curve(float x) {
        float toeExp = max(px_c * 0.5, 0.01);
        float midExp = px_a * max(px_e, 0.01);
        float num = pow(abs(x + px_f), px_a) + pow(abs(x + px_f), midExp) * (x) - px_i;
        float midTerm = px_d * pow(abs(x + px_f), midExp) * px_e;
        float toeTerm = px_d * pow(abs(x + px_f), toeExp) * px_c;
        float den = midTerm * toeTerm + px_f;
        return num / max(den, 1e-6);
    }
    float3 Logic_PixelsTone(float3 color) {
        float3x3 mS = {0.900,0.020,-0.018, 0.020,0.900,-0.013, 0.000,0.010,0.900};
        float3x3 mR = {1.000,-0.024,0.018, -0.020,1.000,0.004, 0.000,-0.003,1.000};
        color = mul(mS, color);
        color = float3(px_curve(color.x), px_curve(color.y), px_curve(color.z));
        color = mul(mR, color);
        if (abs(px_shadows) > 0.001) color = adjust_shadow_density(color, px_shadows);
        color = apply_post_scurve(color, px_s_curve);
        color = apply_post_sat(color, px_sat);
        if (abs(px_post_gamma - 1.0) > 0.01) color = pow(max(color, 0.0), 1.0 / px_post_gamma);
        return saturate(color);
    }

    // ================================================================
    // MODE 2: GT-Film (Uchimura + film print curve)
    // ================================================================
    float3 film_print_curve(float3 c) {
        float luma = dot(c, float3(0.2126, 0.7152, 0.0722));
        float lumaOut = luma;
        if (luma > 0.7) {
            float t = (luma - 0.7) / 0.3;
            float rolloff = 0.7 + 0.18 * (1.0 - (1.0 - t) * (1.0 - t));
            lumaOut = lerp(luma, rolloff, saturate(t * 1.5));
        }
        return c * (lumaOut / max(luma, 1e-5));
    }
    float3 Logic_GT_Film(float3 color) {
        color = compress_highlights_film(color);
        float3 mapped;
        mapped.r = uchimura(color.r, film_P, film_a, film_m, film_l, film_c, film_b);
        mapped.g = uchimura(color.g, film_P, film_a, film_m, film_l, film_c, film_b);
        mapped.b = uchimura(color.b, film_P, film_a, film_m, film_l, film_c, film_b);
        mapped = film_print_curve(mapped);
        mapped = apply_post_scurve(mapped, film_s_curve);
        mapped = apply_post_sat(mapped, film_sat);
        if (abs(film_gamma - 1.0) > 0.01) mapped = pow(max(mapped, 0.0), 1.0 / film_gamma);
        return saturate(mapped);
    }

    // ================================================================
    // MODO 3 — AgX + Uchimura  (Bloco 2, calibracao de referencia)
    // AgX: transform de entrada, encoding log2, sigmoide de contraste,
    // look (slope/power/sat) e EOTF inverso. Misturado com Uchimura por
    // agx_mix, ponderado por luminancia (agx_mix_exp).
    // ================================================================
    float3 agx_contrast_approx(float3 x) {
        float3 x2 = x * x;
        float3 x4 = x2 * x2;
        return  + 15.5    * x4 * x2
                - 40.14   * x4 * x
                + 31.96   * x4
                - 6.868   * x2 * x
                + 0.4298  * x2
                + 0.1191  * x
                - 0.00232;
    }
    float3 agx_encode(float3 val) {
        float3x3 m = float3x3(
            0.842479062253094,  0.0423282422610123, 0.0423756549057051,
            0.0784335999999992, 0.878468636469772,  0.0784336,
            0.0792237451477643, 0.0791661274605434, 0.879142973793104);
        float min_ev = -12.47393;
        float max_ev =   4.026069;
        val = mul(m, val);
        val = max(val, 1e-10);            // guarda: log2 de negativo vira NaN
        val = clamp(log2(val), min_ev, max_ev);
        val = (val - min_ev) / (max_ev - min_ev);
        return agx_contrast_approx(val);
    }
    float3 agx_eotf(float3 val) {
        float3x3 mi = float3x3(
             1.19687900512017,   -0.0528968517574562, -0.0529716355144438,
            -0.0980208811401368,  1.15190312990417,   -0.0980434501171241,
            -0.0990297440797205, -0.0989611768448433,  1.15107367264116);
        return mul(mi, val);
    }
    float3 agx_look(float3 val) {
        float luma = dot(val, float3(0.2126, 0.7152, 0.0722));
        float3 slope = float3(agx_slope, agx_slope, agx_slope);
        float3 power = float3(agx_power, agx_power, agx_power);
        val = pow(max(0, val * slope), power);
        return luma + agx_sat * (val - luma);
    }
    float uchimura_agx(float x) {
        float l0 = ((agx_P - agx_m) * agx_l) / agx_a;
        float S0 = agx_m + l0;
        float S1 = agx_m + agx_a * l0;
        float C2 = (agx_a * agx_P) / (agx_P - S1);
        float CP = -C2 / agx_P;
        float w0 = 1.0 - smoothstep(0.0, agx_m, x);
        float w2 = step(agx_m + l0, x);
        float w1 = 1.0 - w0 - w2;
        float T = agx_m * pow(abs(x / agx_m), agx_c) + agx_b;
        float S = agx_P - (agx_P - S1) * exp(CP * (x - S0));
        float L = agx_m + agx_a * (x - agx_m);
        return T * w0 + L * w1 + S * w2;
    }
    float3 Logic_AgX_Uchimura(float3 x) {
        float luma = saturate(dot(x, float3(0.2126, 0.7152, 0.0722)));
        float3 col = agx_encode(x);
        col = agx_look(col);
        col = agx_eotf(col);
        x = lerp(x, col, agx_mix * pow(max(luma, 1e-6), agx_mix_exp));
        x *= agx_gain;
        x = float3(uchimura_agx(x.r), uchimura_agx(x.g), uchimura_agx(x.b));

        // Midtones: curva de potencia com peso em sino na faixa media
        if (abs(agx_midtones - 1.0) > 0.001) {
            float lm   = dot(x, float3(0.2126, 0.7152, 0.0722));
            float midW = smoothstep(0.0, 0.4, lm) * (1.0 - smoothstep(0.6, 1.0, lm));
            float midA = pow(abs(lm + 1e-10), 1.0 / agx_midtones);
            float newL = lerp(lm, midA, midW);
            x = x * (newL / (lm + 1e-10));
        }
        x = x + agx_black;
        return saturate(x);
    }

    // ================================================================
    // DISPATCHER
    // ================================================================
    float3 main(float3 color) {
        color = compress_highlights(color);
        if (mode_selector < 0.5) return Logic_GT7_Hybrid(color);
        if (mode_selector < 1.5) return Logic_PixelsTone(color);
        if (mode_selector < 2.5) return Logic_GT_Film(color);
        return Logic_AgX_Uchimura(color);
    }
]]

-- ============================================================================
-- INIT
-- ============================================================================
function init_pure_script()

    pure.script.setVersion(44.0)
    pure.script.setAuthor("MRACHADORES")
    pure.script.resetSettingsWithNewVersion()

    -- ================================================================
    -- EXPOSURE INIT — calibrada
    -- ================================================================
    -- Init-time values derived from UI defaults via scaling factors.
    -- Per-frame modulation in update_pure_script().
    -- Exposicao adaptativa (13.2): CBE + setBypass no update.
    -- handleExposure NO INIT (correcao dos modos de exposicao).
    -- Pure separa setup de execucao: handleExposure() so registra
    -- _l_init_func e _l_update_func. Quem CHAMA o _l_init_func e o
    -- __PURE__scripttools_exposure_init(), que roda UMA VEZ, logo depois
    -- do nosso init_pure_script(). Chamar handleExposure so no update
    -- instalava o _update_CameraFocused sobre um estado nunca inicializado:
    -- ele agia um frame e depois ficava inerte. E o "piscou e parou".
    -- A referencia faz exatamente isto no init dela (linha 932).
    pure.script.tools.handleExposure(2, {
        method = 4, target = 2.5, mix = 1, fixedexposure = 0.20,
        minimumexposure = 0.05, superexposure = 1, show_ui = false })
    pure.exposure.useCBE(true)
    pure.exposure.cbe.setLimits(0.03, 10)           -- semeadura: (0.03, getMaximum)
    pure.exposure.cbe.setAdaptionSpeeds(30, 10)     -- init; update modula por oclusao
    pure.exposure.yebis.setAdaptionSpeeds(10, 1)
    pure.exposure.cbe.setSensitivity(0.5)
    pure.exposure.setCBEMix(1)

    pure.light.setLambertGamma(1.6)  -- referencia usa 1.6 (API log LAM:1.6); semeadura era 2.2

    -- TURBIDEZ: removida daqui (Bloco 18).
    -- A linha era `ac.setSkyV2Turbidity(3, 14)`, copiada da semeadura, e
    -- estava MORTA. Assinatura e (regiao, valor), entao (3, 14) significa
    -- SkyRegion.All com turbidez 14 — pares validos, nao havia erro de
    -- chamada. O problema era outro: o Pure escreve
    -- `ac.setSkyV2Turbidity(ac.SkyRegion.All, 10)` dentro de
    -- __PURE__create_sky(dt), que roda TODO FRAME (pure/world/world_sky.lua
    -- linha 252). Qualquer valor escrito no init e sobrescrito no frame
    -- seguinte e nunca aparece na tela.
    -- Outro filtro tem a mesma linha no init e ela e igualmente inerte.
    -- Quem quiser turbidez de verdade precisa escrever POR FRAME. Agora e
    -- isso que a secao 8 faz, com controle na pagina World.
    -- light.ambient_model_V2 REMOVIDO (13.7): deixar default do Pure

    -- ================================================================
    -- MOTOR DE COR CSP — registro dos 7 nos (Bloco 3)
    -- ================================================================
    if ac.weatherColorCorrections then
        local function mp_ccPush(node)
            if ac.weatherColorCorrections.push then
                ac.weatherColorCorrections:push(node)
            else
                ac.weatherColorCorrections[#ac.weatherColorCorrections + 1] = node
            end
            return node
        end
        mp_cc = {
            fade  = mp_ccPush(ac.ColorCorrectionFadeRgb      { color = rgb(0,0,0), effectRatio = 1 }),
            contr = mp_ccPush(ac.ColorCorrectionContrast     { value = 1 }),
            sat   = mp_ccPush(ac.ColorCorrectionSaturation   { value = 1 }),
            sepia = mp_ccPush(ac.ColorCorrectionSepiaTone    { value = 0 }),
            wb    = mp_ccPush(ac.ColorCorrectionTemperature  { temperature = 6500, luminance = 1 }),
            hue   = mp_ccPush(ac.ColorCorrectionHue          { hue = 0, keepLuminance = true }),
            tint  = mp_ccPush(ac.ColorCorrectionModulationRgb{ color = rgb(1,1,1) }),
        }
        ac.log("[MPIXELS] motor de cor CSP registrado (7 nos)")
    else
        ac.log("[MPIXELS] AVISO: ac.weatherColorCorrections indisponivel — motor de cor CSP off")
    end

    -- ================================================================
    -- SKYDOME INIT
    -- ================================================================
    -- 14.2: instrumentado. O log provou que a secao 11 do update nunca
    -- registra nada, e nao ha erro de Lua — logo o guard "if mp_cover then"
    -- esta falso, ou seja ac.SkyCloudsCover() devolveu nil. Confirmar aqui.
    if ac.SkyCloudsCover then
        mp_cover = ac.SkyCloudsCover()
    end
    ac.log("[MPIXELS] SKYDOME INIT"
        .. " | ac.SkyCloudsCover=" .. tostring(ac.SkyCloudsCover ~= nil)
        .. " | cover=" .. tostring(mp_cover)
        .. " | ac.addWeatherCloudCover=" .. tostring(ac.addWeatherCloudCover ~= nil)
        .. " | ac.weatherCloudsCovers=" .. tostring(ac.weatherCloudsCovers ~= nil))
    if mp_cover then
        -- ac.addWeatherCloudCover nao existe em SDK nenhum (a referencia usa mesmo
        -- assim). A API documentada e ac.weatherCloudsCovers:push. Tentar as duas.
        if ac.addWeatherCloudCover then
            ac.addWeatherCloudCover(mp_cover)
            ac.log("[MPIXELS] SKYDOME registrado via ac.addWeatherCloudCover")
        elseif ac.weatherCloudsCovers and ac.weatherCloudsCovers.push then
            ac.weatherCloudsCovers:push(mp_cover)
            ac.log("[MPIXELS] SKYDOME registrado via ac.weatherCloudsCovers:push")
        else
            ac.log("[MPIXELS] SKYDOME ERRO: nenhuma API de registro disponivel")
        end
    else
        ac.log("[MPIXELS] SKYDOME ERRO: ac.SkyCloudsCover() devolveu nil")
    end

    -- ================================================================
    -- 29 WEATHER TYPES
    -- ================================================================
    -- Bloco 9: variaveis de overcast que faltavam na nossa semeadura
    pure.script.weather.addVariable("Overcastcontrast", 0)
    pure.script.weather.addVariable("overbr", 0)
    pure.script.weather.setVariable("overbr", "OvercastClouds", 0.5)
    pure.script.weather.setVariable("Overcastcontrast", "OvercastClouds", 1.30)

    pure.script.weather.addVariable("sunmod", 0.3)
    pure.script.weather.setVariable("sunmod", "NoClouds", 0.31)
    pure.script.weather.setVariable("sunmod", "FewClouds", 0.30)
    pure.script.weather.setVariable("sunmod", "ScatteredClouds", 0.30)
    pure.script.weather.setVariable("sunmod", "BrokenClouds", 0.10)
    pure.script.weather.setVariable("sunmod", "OvercastClouds", 0.07)
    pure.script.weather.setVariable("sunmod", "Fog", 0.01)
    pure.script.weather.setVariable("sunmod", "Mist", 0.10)
    pure.script.weather.setVariable("sunmod", "Haze", 0.10)
    pure.script.weather.setVariable("sunmod", "Sand", 0.10)
    pure.script.weather.setVariable("sunmod", "Dust", 0.10)
    pure.script.weather.setVariable("sunmod", "Smoke", -0.45)
    pure.script.weather.setVariable("sunmod", "LightDrizzle", -0.20)
    pure.script.weather.setVariable("sunmod", "Drizzle", -0.15)
    pure.script.weather.setVariable("sunmod", "HeavyDrizzle", -0.22)
    pure.script.weather.setVariable("sunmod", "LightRain", -0.22)
    pure.script.weather.setVariable("sunmod", "Rain", -0.20)
    pure.script.weather.setVariable("sunmod", "HeavyRain", -0.40)
    pure.script.weather.setVariable("sunmod", "LightSnow", -0.37)
    pure.script.weather.setVariable("sunmod", "Snow", -0.45)
    pure.script.weather.setVariable("sunmod", "HeavySnow", -0.35)
    pure.script.weather.setVariable("sunmod", "LightSleet", -0.24)
    pure.script.weather.setVariable("sunmod", "Sleet", -0.50)
    pure.script.weather.setVariable("sunmod", "HeavySleet", -0.35)
    pure.script.weather.setVariable("sunmod", "LightThunderstorm", -0.30)
    pure.script.weather.setVariable("sunmod", "Thunderstorm", -0.50)
    pure.script.weather.setVariable("sunmod", "HeavyThunderstorm", -0.22)
    pure.script.weather.setVariable("sunmod", "Squalls", -0.25)
    pure.script.weather.setVariable("sunmod", "Tornado", -0.48)
    pure.script.weather.setVariable("sunmod", "Hurricane", -0.35)
    pure.script.weather.setVariable("sunmod", "Cold", 0.30)

    pure.script.weather.setVariable("sunmod", "Windy", 0.30)

    pure.script.weather.addVariable("sunmod2", 1)
    pure.script.weather.setVariable("sunmod2", "ScatteredClouds", 1.02)
    pure.script.weather.setVariable("sunmod2", "BrokenClouds", 1.02)
    pure.script.weather.setVariable("sunmod2", "OvercastClouds", 0.56)
    -- Bloco 9: os cinco climas atmosfericos levam um fator de dia na
    -- referencia. NAO copiamos a chamada dela literalmente: ela avalia
    -- pure.mod.dayCurve DENTRO do init, ou seja congela o valor no horario
    -- em que o filtro carregou. Usamos o valor de dia (fator 1.0), que e o
    -- caso dominante, e deixamos o slider de fog cuidar da modulacao.
    local MP_ATM = 1.0
    pure.script.weather.setVariable("sunmod2", "Fog",  0.67 * MP_ATM)
    pure.script.weather.setVariable("sunmod2", "Mist", 0.80 * MP_ATM)
    pure.script.weather.setVariable("sunmod2", "Haze", 0.80 * MP_ATM)
    pure.script.weather.setVariable("sunmod2", "Sand", 0.80 * MP_ATM)
    pure.script.weather.setVariable("sunmod2", "Dust", 0.80 * MP_ATM)
    pure.script.weather.setVariable("sunmod2", "Smoke", 0.70)
    pure.script.weather.setVariable("sunmod2", "LightDrizzle", 0.73)
    pure.script.weather.setVariable("sunmod2", "Drizzle", 0.55)
    pure.script.weather.setVariable("sunmod2", "HeavyDrizzle", 0.55)
    pure.script.weather.setVariable("sunmod2", "LightRain", 0.55)
    pure.script.weather.setVariable("sunmod2", "Rain", 0.50)
    pure.script.weather.setVariable("sunmod2", "HeavyRain", 0.55)
    pure.script.weather.setVariable("sunmod2", "LightSnow", 0.60)
    pure.script.weather.setVariable("sunmod2", "Snow", 0.56)
    pure.script.weather.setVariable("sunmod2", "HeavySnow", 0.50)
    pure.script.weather.setVariable("sunmod2", "LightSleet", 0.67)
    pure.script.weather.setVariable("sunmod2", "Sleet", 0.67)
    pure.script.weather.setVariable("sunmod2", "HeavySleet", 0.50)
    pure.script.weather.setVariable("sunmod2", "LightThunderstorm", 0.65)
    pure.script.weather.setVariable("sunmod2", "Thunderstorm", 0.40)
    pure.script.weather.setVariable("sunmod2", "HeavyThunderstorm", 0.55)
    pure.script.weather.setVariable("sunmod2", "Squalls", 0.55)
    pure.script.weather.setVariable("sunmod2", "Tornado", 0.40)
    pure.script.weather.setVariable("sunmod2", "Hurricane", 0.55)
    pure.script.weather.setVariable("sunmod2", "Windy", 0.95)

    -- ================================================================
    -- UI — PAGINAS
    -- ================================================================
    pure.script.ui.addPage("Info")
    -- ================================================================
    -- SOBRE — pagina do MANIFESTO, desenhada pelo arquivo .ui
    --
    -- Bloco 19: esta pagina fica DELIBERADAMENTE vazia do lado do Lua.
    -- O .ui escreve nela com PURE_PP_UI_drawText, que posiciona por x/y
    -- absoluto e ignora o fluxo dos widgets. Enquanto o Lua tambem
    -- registrava addText aqui, os dois desenhavam no mesmo espaco e o
    -- texto saia sobreposto. A pagina "Info" ja funcionava assim (so o
    -- logo do .ui, nada de Lua) — e o modelo que estamos seguindo.
    -- O conteudo tecnico que morava aqui foi para a pagina "Guia".
    -- ================================================================
    pure.script.ui.addPage("Sobre")

    -- ================================================================
    -- GUIA — o que era o texto tecnico da aba Sobre (Bloco 19)
    -- ================================================================
    pure.script.ui.addPage("Guia")
    pure.script.ui.addText("MALDITOS PIXELS")
    pure.script.ui.addText("PPFilter dos Malditos Rachadores")
    pure.script.ui.addSeparator()
    pure.script.ui.addText("Variante ativa: " .. MP_VARIANT)
    pure.script.ui.addText("Versao " .. MP_VERSION)
    pure.script.ui.addSeparator()
    pure.script.ui.addText("Cinco variantes: Rachadores, Cinema, Puro, Vivo, Madrugada.")
    pure.script.ui.addSeparator()
    pure.script.ui.addText("O QUE ELE FAZ")
    pure.script.ui.addText("Exposicao adaptativa com cinco modos e resposta a tunel.")
    pure.script.ui.addText("Quatro curvas de tonemap, entre elas AgX e GT7-Blend.")
    pure.script.ui.addText("Motor de cor em dois estagios com 22 perfis dia e noite.")
    pure.script.ui.addText("Fog por angulo solar com controle de cor noturna.")
    pure.script.ui.addText("Oito perfis de glare para o dia e oito para a noite.")
    pure.script.ui.addText("Ceu, estrelas e poluicao luminosa ajustaveis.")
    pure.script.ui.addText("Chuva, asfalto molhado e suavizacao temporal propria.")
    pure.script.ui.addSeparator()
    pure.script.ui.addText("COMO CALIBRAR")
    pure.script.ui.addText("Comece pela Exposicao. Todo o resto se apoia nela.")
    pure.script.ui.addText("Depois Tonemap, depois Cor, depois Atmosfera.")
    pure.script.ui.addText("Uma coisa por vez, sempre na mesma cena.")
    pure.script.ui.addText("Config que arruma um cenario e estraga outro nao esta pronta.")
    pure.script.ui.addSeparator()
    pure.script.ui.addText("DIAGNOSTICO")
    pure.script.ui.addText("O log do CSP traz [MPIXELS] update FIM ok a cada 120 frames.")
    pure.script.ui.addText("Se listar SECOES MORTAS, alguma parte falhou e foi isolada.")
    pure.script.ui.addText("O resto do filtro continua funcionando.")
    pure.script.ui.addSeparator()
    pure.script.ui.addText("Malditos Rachadores")
    pure.script.ui.addText("Uso conforme a licenca acordada.")

    -- ================================================================
    -- UI — EXPOSICAO (estrutura referencia)
    -- ================================================================
    pure.script.ui.addPage("Exposicao")

    pure.script.ui.addText("Exposicao Adaptativa")
    pure.script.ui.addSeparator()
    pure.script.ui.addSliderFloat("AETargetSlider", 1.0, 0.5, 2.0,
        "Auto-Exposure Target (multiplicador global)")
    pure.script.ui.addRadioButtons("ModoExposicao", 5,
        "Classico, Hibrido, Filmico, Alternativo, Adaptativo")
    pure.script.ui.addSliderFloat("CalibracaoTelaNoite", 1.0, 0.2, 2.0,
        "Calibracao de tela (noite)")
    pure.script.ui.addSliderFloat("AlvoExposicaoDia", 1.0, 0.3, 2.5, "Alvo de exposicao (dia)")
    pure.script.ui.addSliderFloat("AlvoExposicaoNoite", 1.0, 0.3, 3.0, "Alvo de exposicao (noite)")
    pure.script.ui.addSliderFloat("AlvoInterior", 1.0, 0.5, 2.0, "Alvo no interior")
    pure.script.ui.addSliderFloat("AdaptSpeed", 1.0, 0.5, 2.0,
        "Velocidade de Adaptacao (0.5=lento, 2.0=rapido)")
    pure.script.ui.addSeparator()

    pure.script.ui.addText("Readouts")
    pure.script.ui.addStateFloat("ExposureFinal", 0)
    pure.script.ui.addStateFloat("CBETarget", 0)
    pure.script.ui.addStateFloat("CBEValue", 0)
    pure.script.ui.addStateFloat("Nightness", 0)
    pure.script.ui.addStateFloat("OcclusionRaw", 0)
    pure.script.ui.addStateFloat("OcclusionSmooth", 0)

    -- ================================================================
    -- UI — TONEMAP (3 modos referencia)
    -- ================================================================
    pure.script.ui.addPage("Tonemap")

    pure.script.ui.addText("Modo de Tonemapping")
    pure.script.ui.addSeparator()
    pure.script.ui.addRadioButtons("TonemapMode", 1,
        "GT7-Blend, Pixels-Tone, GT-Film, AgX")
    pure.script.ui.addSeparator()

    -- GT7-Blend params (mode 0, default)
    pure.script.ui.addText("GT7-Blend")
    pure.script.ui.addSliderFloat("GT7White", 0.800, 0.2, 2.0, "Highlights Max (gt7_white)")
    pure.script.ui.addSliderFloat("GT7a", 1.200, 0.3, 3.0, "Linear Slope (gt7_a)")
    pure.script.ui.addSliderFloat("GT7l", 0.250, 0.01, 1.0, "Highlight Rolloff (gt7_l)")
    pure.script.ui.addSliderFloat("GT7c", 1.000, 0.1, 3.0, "Shadow Toe (gt7_c)")
    pure.script.ui.addSliderFloat("GT7P", 1.000, 0.3, 3.0, "Peak Brightness (gt7_P)")
    pure.script.ui.addSliderFloat("GT7m", 0.120, 0.01, 0.5, "Linear Start (gt7_m)")
    pure.script.ui.addSliderFloat("GT7Blend", 0.650, 0.0, 1.0, "Color Volume (gt7_blend)")
    pure.script.ui.addSliderFloat("GT7SCurve", 0.250, 0.0, 0.8, "S-Curve Strength (gt7_s_curve)")
    pure.script.ui.addSliderFloat("GT7Sat", 1.200, 0.3, 2.5, "Saturation (gt7_sat)")
    pure.script.ui.addSliderFloat("GT7Gamma", 1.000, 0.5, 2.0, "Gamma (gt7_gamma)")
    pure.script.ui.addSliderFloat("GT7FadeStart", 0.980, 0.5, 1.5, "Chroma Fade Start")
    pure.script.ui.addSliderFloat("GT7b", 0.006, 0.0, 0.05, "Black Offset (gt7_b)")
    pure.script.ui.addSeparator()

    -- referencia-Tone params (mode 1)
    pure.script.ui.addText("Pixels-Tone")
    pure.script.ui.addSliderFloat("PxD", 2.100, 0.5, 5.0, "Highlights (px_d)")
    pure.script.ui.addSliderFloat("PxA", 2.700, 0.5, 5.0, "Contrast Power (px_a)")
    pure.script.ui.addSliderFloat("PxC", 0.850, 0.1, 2.0, "Curve Shoulder (px_c)")
    pure.script.ui.addSliderFloat("PxE", 0.600, 0.01, 2.0, "Shoulder Rolloff (px_e)")
    pure.script.ui.addSliderFloat("PxF", 0.065, 0.0, 0.3, "Black Level (px_f)")
    pure.script.ui.addSliderFloat("PxShadows", 0.000, 0.0, 1.0, "Shadow Density (px_shadows)")
    pure.script.ui.addSliderFloat("PxSCurve", 0.300, 0.0, 0.8, "S-Curve (px_s_curve)")
    pure.script.ui.addSliderFloat("PxGamma", 1.000, 0.5, 2.0, "Global Gamma (px_post_gamma)")
    pure.script.ui.addSliderFloat("PxSat", 1.150, 0.3, 2.5, "Saturation (px_sat)")
    pure.script.ui.addSeparator()

    -- GT-Film params (mode 2)
    pure.script.ui.addText("GT-Film")
    pure.script.ui.addSliderFloat("FilmP", 1.250, 0.3, 3.0, "HL Max (film_P)")
    pure.script.ui.addSliderFloat("FilmA", 0.950, 0.3, 3.0, "Slope (film_a)")
    pure.script.ui.addSliderFloat("FilmL", 0.150, 0.01, 1.0, "HL Rolloff (film_l)")
    pure.script.ui.addSliderFloat("FilmC", 1.200, 0.1, 3.0, "Shadow Toe (film_c)")
    pure.script.ui.addSliderFloat("FilmM", 0.125, 0.01, 0.5, "Linear Start (film_m)")
    pure.script.ui.addSliderFloat("FilmB", 0.010, 0.0, 0.05, "Black Offset (film_b)")
    pure.script.ui.addSliderFloat("FilmSCurve", 0.250, 0.0, 0.8, "S-Curve (film_s_curve)")
    pure.script.ui.addSliderFloat("FilmGamma", 0.850, 0.5, 2.0, "Gamma (film_gamma)")
    pure.script.ui.addSliderFloat("FilmSat", 0.950, 0.3, 2.5, "Saturation (film_sat)")

    pure.script.ui.addSeparator()
    pure.script.ui.addText("AgX (modo 4) — calibracao de referencia")
    pure.script.ui.addSliderFloat("AgxP",        2.000, 0.5, 4.0,  "Brilho maximo (P)")
    pure.script.ui.addSliderFloat("AgxA",        1.000, 0.1, 3.0,  "Contraste (a)")
    pure.script.ui.addSliderFloat("AgxM",        0.290, 0.05, 0.8, "Inicio do trecho linear (m)")
    pure.script.ui.addSliderFloat("AgxL",        0.400, 0.0, 1.0,  "Comprimento do linear (l)")
    pure.script.ui.addSliderFloat("AgxC",        1.000, 0.5, 3.0,  "Contraste de sombra (c)")
    pure.script.ui.addSliderFloat("AgxB",        0.000, -0.1, 0.3, "Pedestal (b)")
    pure.script.ui.addSeparator()
    pure.script.ui.addSliderFloat("AgxGain",     1.000, 0.2, 3.0,  "Ganho")
    pure.script.ui.addSliderFloat("AgxBlack",    0.000, -0.1, 0.2, "Nivel de preto")
    pure.script.ui.addSliderFloat("AgxMidtones", 1.000, 0.3, 3.0,  "Meios-tons")
    pure.script.ui.addSeparator()
    pure.script.ui.addSliderFloat("AgxMix",      1.000, 0.0, 1.0,  "Mistura AgX")
    pure.script.ui.addSliderFloat("AgxMixExp",   0.000, 0.0, 4.0,  "Expoente da mistura")
    pure.script.ui.addSliderFloat("AgxSlope",    1.250, 0.5, 3.0,  "Slope do look")
    pure.script.ui.addSliderFloat("AgxPower",    1.750, 0.5, 4.0,  "Power do look")
    pure.script.ui.addSliderFloat("AgxSat",      1.000, 0.0, 2.5,  "Saturacao do look")

    -- ================================================================
    -- UI — COLOR (referencia grading spec)
    -- ================================================================
    pure.script.ui.addPage("Cor")

    pure.script.ui.addText("Motor de Cor")
    pure.script.ui.addSeparator()
    pure.script.ui.addRadioButtons("MotorCor", 2,
        "Malditos (pp), CSP Nodes (referencia)")
    pure.script.ui.addText("CSP Nodes: pilha nativa de 7 nos, abaixo do PP.")
    pure.script.ui.addText("Os dois nao somam — um desliga o outro.")
    pure.script.ui.addSeparator()
    pure.script.ui.addRadioButtons("PerfilCorDia", 1,
        "Neutro, Quente, Frio, Filmico, Filmico+, Cinema, Teal-Laranja, Suave, Sutil, Puro, Vibrante")
    pure.script.ui.addRadioButtons("PerfilCorNoite", 1,
        "Neutro, Quente, Frio, Filmico, Filmico+, Cinema, Teal-Laranja, Noturno, Suave, Sutil, Puro")
    pure.script.ui.addSeparator()
    pure.script.ui.addSliderFloat("CorTemperatura", 1.0, 0.5, 1.6, "Temperatura")
    pure.script.ui.addSliderFloat("CorLuminosidade", 1.0, 0.0, 2.0, "Luminosidade")
    pure.script.ui.addSliderFloat("CorContraste", 1.0, 0.5, 2.0, "Contraste filmico")
    pure.script.ui.addSliderFloat("CorSepia", 1.0, 0.0, 3.0, "Sepia")
    pure.script.ui.addSliderFloat("CorMatiz", 1.0, 0.0, 3.0, "Matiz")
    pure.script.ui.addSliderFloat("CorSaturacao", 1.0, 0.0, 2.0, "Saturacao")
    pure.script.ui.addSliderFloat("CorFade", 1.0, 0.0, 2.0, "Fade")
    pure.script.ui.addSeparator()
    pure.script.ui.addSliderFloat("CorTintR", 1.0, 0.5, 1.5, "Tint vermelho")
    pure.script.ui.addSliderFloat("CorTintG", 1.0, 0.5, 1.5, "Tint verde")
    pure.script.ui.addSliderFloat("CorTintB", 1.0, 0.5, 1.5, "Tint azul")
    pure.script.ui.addSeparator()
    pure.script.ui.addStateFloat("CorTempEstado", 0)
    pure.script.ui.addStateFloat("CorSatEstado", 0)
    pure.script.ui.addSeparator()

    pure.script.ui.addText("Color Grade")
    pure.script.ui.addSeparator()
    pure.script.ui.addSliderFloat("LUTIntensidade", D.lut_int, 0.0, 1.0,
        "CG Intensity (→ ac.setPpColorGradingIntensity)")
    pure.script.ui.addSeparator()

    pure.script.ui.addText("Dia")
    pure.script.ui.addSliderFloat("Saturacao", D.sat, 0.5, 1.5, "Saturation dia")
    pure.script.ui.addSliderFloat("GammaDia", 1.0, 0.5, 2.0, "Gamma dia (→ pp.gamma)")
    pure.script.ui.addSliderFloat("Temperatura", D.temp, 4000, 9000, "Temperature dia (K)")
    pure.script.ui.addSliderFloat("SepiaDia", 1.0, 0.0, 2.0, "Sepia dia (0=B&W, 1=normal)")
    pure.script.ui.addSliderFloat("VignettePPDia", 0.0, 0.0, 1.0,
        "Vignette dia (→ pp.vignette_str) [ref=0]")
    pure.script.ui.addSeparator()

    pure.script.ui.addText("Noite")
    pure.script.ui.addSliderFloat("SatNoite", 1.0, 0.5, 1.5, "Saturation noite")
    pure.script.ui.addSliderFloat("GammaNoite", 1.0, 0.5, 2.0, "Gamma noite")
    pure.script.ui.addSliderFloat("ShiftNoturno", D.night_shift, 0, 600, "Night Temp Shift (K)")
    pure.script.ui.addSliderFloat("SepiaNoite", 1.0, 0.0, 2.0, "Sepia noite")
    pure.script.ui.addSliderFloat("VignettePPNoite", 0.0, 0.0, 1.0, "Vignette noite [ref=0]")
    pure.script.ui.addSeparator()
    pure.script.ui.addSliderFloat("ContrastePos", D.contrast_post, 0.7, 1.4, "Contraste pos-tonemap")
    pure.script.ui.addSeparator()
    pure.script.ui.addText("Ambiente (13.5)")
    pure.script.ui.addSliderFloat("AmbientSunTint", 0.5, 0.0, 1.0,
        "Tinta solar no ambiente (0=neutro, 1=colorido pelo sol)")

    -- ================================================================
    -- UI — BLOOM (referencia Camera style)
    -- ================================================================
    pure.script.ui.addPage("Bloom")

    pure.script.ui.addText("Bloom — Camera Style")
    pure.script.ui.addSeparator()
    pure.script.ui.addText("Perfil de Glare (Bloco 6)")
    pure.script.ui.addRadioButtons("GlarePerfilDia", 1,
        "Sobrio, Cinematico, Difuso, Solar, Suave, Denso, Estelar, Intenso")
    pure.script.ui.addRadioButtons("GlarePerfilNoite", 1,
        "Sobrio, Cinematico, Difuso, Solar, Suave, Denso, Estelar, Intenso")
    pure.script.ui.addSliderFloat("GlareIntensidade", 1.0, 0.0, 3.0, "Intensidade geral")
    pure.script.ui.addSliderFloat("GlareLimiar", 1.0, 0.1, 5.0, "Limiar")
    pure.script.ui.addCheckbox("GlareAntiArcoIris", true,
        "Protecao anti-arco-iris (forca ghost e dispersao a zero)")
    pure.script.ui.addText("Anamorfico (alonga o bloom no eixo horizontal)")
    pure.script.ui.addRadioButtons("GlareAnamorfico", 1, "Desligado, Ativo")
    pure.script.ui.addSeparator()
    pure.script.ui.addText("Dia")
    pure.script.ui.addSliderFloat("BloomGammaDia", 1.5, 0.5, 4.0,
        "Bloom Gamma dia (→ glareBloomLuminanceGamma)")
    pure.script.ui.addSliderFloat("GlareAmountDia", 0.75, 0.0, 3.0,
        "Glare Amount dia (→ glareLuminance)")
    pure.script.ui.addSliderFloat("GlareLumDia", 0.65, 0.0, 3.0,
        "Glare Luminance dia")
    pure.script.ui.addSliderFloat("BloomLumDia", 0.65, 0.0, 3.0,
        "Bloom Luminance dia (→ glareShapeBloomLuminance)")
    pure.script.ui.addSliderFloat("StarLumDia", 0.5, 0.0, 3.0,
        "Star Luminance dia (→ glareShapeStarLuminance)")
    pure.script.ui.addSliderFloat("StarLengthDia", 0.15, 0.0, 1.0,
        "Star Length dia (→ glareShapeStarLength)")
    pure.script.ui.addSliderFloat("GlareThreshDia", 1.0, 0.0, 5.0,
        "Glare Threshold dia (→ glareThreshold)")
    pure.script.ui.addSeparator()

    pure.script.ui.addText("Noite")
    pure.script.ui.addSliderFloat("BloomGammaNoite", 1.35, 0.5, 4.0, "Bloom Gamma noite")
    pure.script.ui.addSliderFloat("GlareAmountNoite", 0.75, 0.0, 3.0, "Glare Amount noite")
    pure.script.ui.addSliderFloat("GlareLumNoite", 0.75, 0.0, 3.0, "Glare Luminance noite")
    pure.script.ui.addSliderFloat("BloomLumNoite", 0.75, 0.0, 3.0, "Bloom Luminance noite")
    pure.script.ui.addSliderFloat("StarLumNoite", 0.75, 0.0, 3.0, "Star Luminance noite")
    pure.script.ui.addSliderFloat("StarLengthNoite", 0.15, 0.0, 1.0, "Star Length noite")
    pure.script.ui.addSliderFloat("GlareThreshNoite", 1.0, 0.0, 5.0, "Glare Threshold noite")
    pure.script.ui.addSeparator()

    pure.script.ui.addText("Ghost / Extras")
    pure.script.ui.addCheckbox("GhostEnabled", false, "Lens Ghosting")
    pure.script.ui.addSliderFloat("GhostLum", 0.75, 0.0, 3.0, "Ghost Luminance")
    pure.script.ui.addSliderFloat("GhostDist", 0.5, 0.0, 2.0, "Ghost Distortion")

    -- ================================================================
    -- UI — WORLD (Clouds / Stellar / Rainbow)
    -- ================================================================
    pure.script.ui.addPage("World")

    pure.script.ui.addText("Clouds")
    pure.script.ui.addSeparator()
    pure.script.ui.addSliderFloat("CloudBrightDay", 1.0, 0.0, 5.0,
        "Day Brightness (→ clouds2D.brightness)")
    pure.script.ui.addSliderFloat("CloudContrastDay", 1.0, 0.0, 5.0,
        "Day Contrast (→ clouds2D.contrast)")
    pure.script.ui.addSliderFloat("CloudBrightNight", 1.0, 0.0, 5.0, "Night Brightness")
    pure.script.ui.addSliderFloat("CloudContrastNight", 1.5, 0.0, 5.0, "Night Contrast")
    pure.script.ui.addSeparator()

    pure.script.ui.addText("Stellar")
    pure.script.ui.addSeparator()
    pure.script.ui.addSliderFloat("SunSize", 0.5, 0.0, 3.0,
        "Sun Size (→ ac.setSkySunMoonSizeMultiplier)")
    pure.script.ui.addSliderFloat("MoonSize", 7.5, 0.0, 30.0, "Moon Size")
    pure.script.ui.addSliderFloat("MoonBright", 0.275, 0.0, 3.0,
        "Moon Brightness (→ moon.appearance)")
    pure.script.ui.addSliderFloat("MoonLight", 0.3, 0.0, 3.0,
        "Moon Light (→ moon.light)")
    pure.script.ui.addSliderFloat("NightStars", 150, 0, 500,
        "Night Stars (→ shaders.sunblinding.star_opacity)")
    pure.script.ui.addSeparator()
    pure.script.ui.addCheckbox("RainbowEnabled", false,
        "Rainbow (→ ac.setSkyV2Rainbow)")
    pure.script.ui.addSeparator()

    -- Bloco 18: turbidez do ceu procedural (Sky V2).
    -- Controla o espalhamento atmosferico do modelo de ceu. Valor baixo =
    -- ar limpo, azul profundo, horizonte definido. Valor alto = bruma,
    -- horizonte lavado, sol difuso. So age de DIA — a noite o ceu vem de
    -- estrelas, lua e skydome, e a turbidez quase nao participa.
    -- O Pure escreve 10 todo frame; 10 aqui = imagem identica a de sempre.
    pure.script.ui.addText("Turbidez do ceu (Sky V2)")
    pure.script.ui.addText("Baixo = ar limpo. Alto = bruma. So age de dia.")
    pure.script.ui.addCheckbox("TurbidezAtiva", true,
        "Assumir controle da turbidez (→ ac.setSkyV2Turbidity)")
    pure.script.ui.addSliderFloat("TurbidezValor", 10.0, 1.0, 20.0,
        "Turbidez (10 = valor do Pure, sem mudanca)")

    -- ================================================================
    -- UI — GODRAYS (referencia referenciaSpec style)
    -- ================================================================
    pure.script.ui.addPage("GodRays")
    pure.script.ui.addText("GodRays — Pixels Spec")
    pure.script.ui.addSeparator()
    pure.script.ui.addSliderFloat("GodraySpread", 0.25, 0.0, 2.0,
        "Spread (→ ac.setGodraysNoiseMask)")
    pure.script.ui.addSliderFloat("GodrayIntensity", 1.25, 0.0, 5.0,
        "Intensity (→ ac.setGodraysLength)")
    pure.script.ui.addSliderFloat("GodrayLength", 1.75, 0.0, 10.0,
        "Length (multiplicador)")
    pure.script.ui.addSliderFloat("GodrayGlare", 1.25, 0.0, 5.0,
        "Glare (→ ac.setGodraysGlareRatio)")
    pure.script.ui.addSeparator()
    pure.script.ui.addCheckbox("SunblindingOn", true,
        "Sunblinding (→ shaders.sunblinding.iris)")
    pure.script.ui.addSliderFloat("GodrayAngleAtten", 7.0, 0.0, 30.0,
        "Angle Attenuation (→ ac.setGodraysAngleAttenuation)")

    -- ================================================================
    -- UI — LUZ (Bloco 16: sol, sombras, adaptacao de tunel)
    -- ================================================================
    pure.script.ui.addPage("Luz")
    pure.script.ui.addText("Sol, Sombras e Adaptacao de Tunel")
    pure.script.ui.addSeparator()
    pure.script.ui.addText("Nivel do sol")
    pure.script.ui.addCheckbox("SolNivelAtivo", true,
        "Nivel do sol dirigido pelo clima (→ light.sun.level)")
    pure.script.ui.addSliderFloat("SolNivelMult", 1.0, 0.0, 3.0,
        "Multiplicador do nivel do sol")
    pure.script.ui.addCheckbox("SolOverdrive", false,
        "Sol intenso (soma dayCurve 1.1 / 1.2)")
    pure.script.ui.addSliderFloat("LuzDiaMult", 1.0, 0.0, 3.0,
        "Luz do dia (→ light.daylight_multiplier)")
    pure.script.ui.addSeparator()
    pure.script.ui.addText("Adaptacao de tunel")
    pure.script.ui.addText("Cinematica compensa a queda de luz sob cobertura.")
    pure.script.ui.addRadioButtons("TunelAdaptacao", 2, "Cinematica, Neutra")
    pure.script.ui.addSliderFloat("TunelAdaptForca", 25, 0, 40,
        "Forca da compensacao dentro do tunel")
    pure.script.ui.addStateFloat("OclusaoCam", 0)
    pure.script.ui.addSeparator()
    pure.script.ui.addText("Sombras")
    pure.script.ui.addCheckbox("SombrasOtimizadas", false,
        "Sombras em 8192 (→ ac.setShadowsResolution)")
    pure.script.ui.addCheckbox("SombrasNuvens", false,
        "Sombras de nuvens (→ ac.setCloudShadowScalingFactor)")
    pure.script.ui.addSliderFloat("SombrasNuvensBlur", 1.0, 0.0, 2.0,
        "Desfoque das sombras de nuvens (→ clouds_render.shadows_blur)")

    -- ================================================================
    -- UI — EMISSIVES: REMOVIDA (14.0 — conclusao da reversao 13.7)
    -- ================================================================
    -- A referencia (log de API descompilado) NAO chama csp_lights.bounce,
    -- csp_lights.emissive, ac.setGlowBrightness nem ac.setEmissiveCameraGain.
    -- A pagina existia so pra alimentar essas chamadas. Removida junto com elas.

    -- ================================================================
    -- UI — EFEITOS / NOTURNO / CEU / ATMOSFERA / AVANCADO
    -- ================================================================
    pure.script.ui.addPage("Efeitos")
    pure.script.ui.addText("SPICE: MPIXELS_FX (Sharpening, Halation, etc)")
    pure.script.ui.addSeparator()
    pure.script.ui.addText("SpeedTunnel")
    pure.script.ui.addCheckbox("SpeedTunnelOn", false, "Blur radial por velocidade")
    pure.script.ui.addSliderFloat("SpeedTunnelInt", 0.5, 0.1, 2.0, "Intensidade")
    pure.script.ui.addSliderFloat("SpeedTunnelThresh", 80, 20, 200, "Limiar de velocidade (km/h)")
    pure.script.ui.addSeparator()
    pure.script.ui.addText("MagicBloom (ambient glow)")
    pure.script.ui.addCheckbox("MagicBloomOn", false, "Glow complementar (cuidado: bloom duplo)")
    pure.script.ui.addSliderFloat("MagicBloomStr", 0.3, 0.0, 1.0, "Intensidade")

    -- ================================================================
    -- UI — REFLEXOS (referencia Reflections spec)
    -- ================================================================
    pure.script.ui.addPage("Reflexos")
    pure.script.ui.addText("Reflections — Pixels Spec")
    pure.script.ui.addSeparator()
    pure.script.ui.addSliderFloat("ReflDayLevel", 2.5, 0.5, 5.0,
        "Day Reflections (→ reflections.level dia)")
    pure.script.ui.addSliderFloat("ReflNightLevel", 4.0, 0.5, 8.0,
        "Night Reflections (→ reflections.level noite)")
    pure.script.ui.addSliderFloat("ReflSatMult", 0.85, 0.0, 2.0,
        "Overall Saturation Mult (→ reflections.saturation)")
    pure.script.ui.addSeparator()
    pure.script.ui.addText("Advanced")
    pure.script.ui.addSliderFloat("ReflFresnel", 0.85, 0.1, 2.0,
        "Dynamic Fresnel (→ ac.setFresnelGamma)")
    pure.script.ui.addSliderFloat("ReflPolarizer", 0.25, 0.0, 1.0,
        "Polarizing Filter (→ pure.camera.setCPL)")
    pure.script.ui.addSliderFloat("ReflSkyLum", 1.25, 0.0, 3.0,
        "Sky Luminance Refl (→ ac.setReflectedSkyTweaks)")
    pure.script.ui.addSliderFloat("ReflSkySat", 0.95, 0.0, 2.0,
        "Sky Saturation Refl (→ reflections.saturation sky)")
    pure.script.ui.addSliderFloat("ReflSkyGamma", 1.05, 0.5, 2.0,
        "Sky Gamma Refl (combinado com Fresnel)")
    pure.script.ui.addSeparator()
    pure.script.ui.addSliderFloat("ReflEmissiveBoost", 1.0, 0.0, 5.0,
        "Emissive in Reflections (→ reflections.emissive_boost)")
    pure.script.ui.addSliderFloat("ReflSunSpecular", 2.0, 0.0, 5.0,
        "Sun Specular (→ light.sun.speculars)")

    pure.script.ui.addPage("Noturno")
    pure.script.ui.addText("Purkinje — Visao Noturna (CIE 1951)")
    pure.script.ui.addSeparator()
    pure.script.ui.addCheckbox("PurkinjeAtivo", MP_VARIANT == "Madrugada",
        "Ativar Purkinje (shift escotopico)")
    pure.script.ui.addSliderFloat("PurkinjeInt", D.purk_int, 0.0, 0.40, "Intensidade")
    pure.script.ui.addSliderFloat("PurkinjeThr", D.purk_thr, 0.05, 0.30, "Limiar local")
    pure.script.ui.addSeparator()
    pure.script.ui.addStateFloat("PurkinjeGlobalDrive", 0)

    pure.script.ui.addPage("Ceu")
    pure.script.ui.addText("Skydome MALDITOS PIXELS")
    pure.script.ui.addSeparator()
    pure.script.ui.addRadioButtons("SkydomePreset", 1,
        "Desligado, Auto, Via Lactea, Aurora Boreal, Crepusculo, Estrelado, Nublado")
    pure.script.ui.addSeparator()
    pure.script.ui.addSliderFloat("CeuBrilho", 1.0, 0.0, 3.0, "Brilho do ceu")
    pure.script.ui.addSliderFloat("CeuOpacidade", 1.0, 0.0, 1.0, "Opacidade do ceu")
    pure.script.ui.addSliderFloat("CeuOpacDia", 0.15, 0.0, 1.0, "Opacidade de dia")
    pure.script.ui.addCheckbox("CeuDeDia", false, "Skydome de dia")
    pure.script.ui.addCheckbox("CeuNoPorSol", true, "Skydome no por do sol")
    pure.script.ui.addSliderFloat("CeuContraste", 1.0, 0.2, 4.0, "Contraste do ceu")
    pure.script.ui.addSliderFloat("CeuRotacao", 0.0, 0.0, 1.0, "Rotacao")
    pure.script.ui.addSliderFloat("CeuAltura", 1.0, 0.5, 2.0, "Altura")
    pure.script.ui.addCheckbox("CeuAnimar", false, "Rotacao animada")
    pure.script.ui.addSliderFloat("CeuVelocidade", 0.5, 0.1, 2.0, "Velocidade animacao")

    pure.script.ui.addSeparator()
    pure.script.ui.addText("Estrelas")
    pure.script.ui.addRadioButtons("EstrelasTipo", 2, "Discretas, Normais, Densas")
    pure.script.ui.addSliderFloat("EstrelasBrilho", 1.0, 0.0, 5.0, "Brilho")
    pure.script.ui.addSliderFloat("EstrelasExpoente", 0.0, -4.0, 6.0, "Expoente")
    pure.script.ui.addSliderFloat("EstrelasSaturacao", 1.0, 0.0, 3.0, "Saturacao")
    pure.script.ui.addCheckbox("EstrelasDia", false, "Visiveis de dia")
    pure.script.ui.addCheckbox("EstrelasDinamicas", true,
        "Adaptacao dinamica (→ stars.dynamic_adaption)")
    pure.script.ui.addSeparator()
    pure.script.ui.addText("Sol, Lua e Reflexo")
    pure.script.ui.addSliderFloat("SolLuaTamanho", 1.5, 0.5, 4.0, "Tamanho do sol/lua")
    pure.script.ui.addSliderFloat("ReflexoCeu", 1.0, 0.0, 2.0, "Reflexo do ceu")
    pure.script.ui.addSeparator()
    pure.script.ui.addText("Poluicao luminosa (NLP da pista)")
    pure.script.ui.addText("E daqui que vem o ambar noturno urbano.")
    pure.script.ui.addSliderFloat("NlpNivel", 0.50, 0.0, 2.0, "Nivel")
    pure.script.ui.addSliderFloat("NlpDensidade", 0.50, 0.0, 2.0, "Densidade")
    pure.script.ui.addSliderFloat("NlpAmbienteMin", 1.0, 0.0, 5.0, "Ambiente minimo")
    pure.script.ui.addSliderFloat("NlpAmbienteV2", 1.0, 0.0, 2.0, "Peso no ambiente V2")
    pure.script.ui.addSeparator()
    pure.script.ui.addText("Luz ambiente avancada")
    pure.script.ui.addSliderFloat("AmbAvancado", 1.0, 0.0, 2.0, "Geral")
    pure.script.ui.addSliderFloat("AmbFog", 1.23, 0.0, 3.0, "Peso do fog")
    pure.script.ui.addSliderFloat("AmbVaoExp", 1.70, 0.0, 3.0, "Expoente VAO")
    pure.script.ui.addSliderFloat("AmbSkydome", 1.0, 0.0, 2.0, "Peso do skydome")

    pure.script.ui.addPage("Atmosfera")
    pure.script.ui.addText("Fog e Profundidade Atmosferica")
    pure.script.ui.addSeparator()
    pure.script.ui.addSliderFloat("FogDensidade", 1.0, 0.0, 3.0, "Densidade")
    pure.script.ui.addSliderFloat("FogDistancia", 1.0, 0.3, 3.0, "Distancia")
    pure.script.ui.addSliderFloat("FogAtmosfera", 1.0, 0.0, 3.0, "Atmosfera")
    pure.script.ui.addSliderFloat("FogBacklit", 1.0, 0.0, 3.0, "Contraluz")
    pure.script.ui.addSliderFloat("FogSaturacao", 1.0, 0.0, 2.0, "Saturacao do fog")
    pure.script.ui.addSeparator()
    pure.script.ui.addSliderFloat("FogNoiteMult", 0.60, 0.0, 1.0,
        "Intensidade da cor a noite (0.6 = referencia)")
    pure.script.ui.addSeparator()

    -- Bloco 17: os quatro sistemas de fog. "Dinamico" e o LUT por angulo
    -- solar (secao 12 original). Os outros tres sao o sistema legado da
    -- referencia, que la so roda quando o dinamico esta desligado.
    pure.script.ui.addText("Sistema de fog")
    pure.script.ui.addRadioButtons("FogSistema", 1,
        "Dinamico, Imersivo, Realista, Denso")
    pure.script.ui.addText("Dinamico = LUT por angulo solar (padrao).")
    pure.script.ui.addText("Os tres seguintes usam os ajustes abaixo.")
    pure.script.ui.addSeparator()
    pure.script.ui.addText("Ajustes do sistema legado")
    pure.script.ui.addSliderFloat("FogQuantidade", 0.025, -5.0, 5.0, "Quantidade")
    pure.script.ui.addSliderFloat("FogEspessura", 0.005, -0.09, 0.09, "Espessura")
    pure.script.ui.addSliderFloat("FogMisturaCor", 0.5, -2.0, 2.0,
        "Mistura de cor (ceu <-> fog)")
    pure.script.ui.addSliderFloat("FogDistLegacy", 0.0, -3.0, 3.0, "Distancia")
    pure.script.ui.addSliderFloat("FogContraluzLeg", 1.0, 0.0, 10.0, "Contraluz")
    pure.script.ui.addSeparator()
    pure.script.ui.addText("Sombras falsas do clima")
    pure.script.ui.addSliderFloat("SombraFalsaOpac", 1.0, 0.0, 2.0,
        "Opacidade (→ ac.setWeatherFakeShadowOpacity)")

    -- ================================================================
    -- UI — CHUVA (13.4)
    -- ================================================================
    pure.script.ui.addPage("Chuva")
    pure.script.ui.addText("Asfalto Molhado e Chuva")
    pure.script.ui.addSeparator()
    pure.script.ui.addText("Readouts (ao vivo)")
    pure.script.ui.addStateFloat("Wetness", 0)
    pure.script.ui.addStateFloat("RainIntensity", 0)
    pure.script.ui.addStateFloat("WaterLevel", 0)

    pure.script.ui.addPage("Avancado")
    pure.script.ui.addText("v" .. MP_VERSION .. " | " .. MP_VARIANT)
    pure.script.ui.addSeparator()
    pure.script.ui.addText("Core = referencia por padrao")
    pure.script.ui.addText("Variantes (Signature/Cine/etc) ativam MALDITOS PIXELS layer")
    pure.script.ui.addSeparator()
    pure.script.ui.addText("Exposicao: adaptativa (13.2)")
    pure.script.ui.addText("Tecnicas: emissivo inverso, CBE ambient,")
    pure.script.ui.addText("tunel assimetrico, piso dinamico")

    ac.log("[MPIXELS] INIT completo | v44 Bloco 19 | " .. MP_VARIANT)
end

-- ============================================================================
-- UPDATE
-- ============================================================================
function update_pure_script(dt)

    mp_frameCount = mp_frameCount + 1
    if mp_frameCount % 120 == 0 then
        ac.log("[MPIXELS] alive | " .. MP_VARIANT .. " | " .. MP_VERSION)
    end

    -- ================================================================
    -- 0. CLONE EXATO (override pra comparacao com referencia)
    -- ================================================================
    -- 0. MODULOS EXTRAS (controlados por D.skip_extras)
    -- Core: skip_extras=true → so tonemap + exposure + INI (= referencia)
    -- Signature/Cine/Natural/Vivid/Night: skip_extras=false → MALDITOS PIXELS features ativas
    local CE = {}
    if D.skip_extras then
        CE.skip_reflections = true
        CE.skip_godrays = true
        CE.skip_world = true
        CE.skip_bloom_override = true
        CE.brightness = 1.0      -- pp.brightness neutro
    end

    -- Motor de cor ativo? (Bloco 3) — 2 = CSP Nodes
    local mp_ccOn = (mp_cc ~= nil) and ((pure.script.ui.getValue("MotorCor") or 2) == 2)

    -- ================================================================
    -- 1. EXPOSURE ADAPTATIVA (semeadura secoes 2-3, tecnicas 1-5)
    -- ================================================================
    local nightness = pure.mod.dayCurve(1.0, 0.0, 1)
    local night01   = pure.mod.night(0)
    local ae_slider = pure.script.ui.getValue("AETargetSlider") or 1.0
    local adapt_speed = pure.script.ui.getValue("AdaptSpeed") or 1.0

    -- ================================================================
    -- 0.1 SUAVIZACAO TEMPORAL (13.3)
    -- Filtra sinais criticos ANTES de usar. Constantes assimetricas:
    -- rapido para escurecer, lento para clarear (camera real).
    -- NAO suaviza nightness/twilight (ja sao continuos do Pure).
    -- ================================================================
    local occ_raw     = pure.camera.getOcclusion()
    -- BUG FIX (14.4) — CAUSA RAIZ REAL.
    -- Era: sim.rainIntensity or 0
    -- "sim" nunca foi definido: nem local, nem global do Pure/CSP (o Pure usa
    -- __AC_SIM). Auditoria de bytecode + fonte confirmou que era o UNICO global
    -- indefinido do script inteiro. Indexar nil estoura, e o "or 0" nao protege
    -- (o erro acontece no indice, antes do or). update_pure_script morria aqui
    -- TODO FRAME desde a 13.4, e nada da linha ~855 pra baixo jamais executou.
    -- Acessor nativo do Pure, irmao dos dois de baixo: getRainFX_Intensity.
    local rain_raw    = pure.world.getRainFX_Intensity
        and pure.world.getRainFX_Intensity() or 0
    local wet_raw     = pure.world.getRainFX_Wetness and pure.world.getRainFX_Wetness() or 0
    local water_raw   = pure.world.getRainFX_Water and pure.world.getRainFX_Water() or 0
    local bad_raw     = pure.world.getBadness() or 0

    -- Taus escalados pelo multiplicador do usuario
    mp_smooth_occlusion = lagAsym(mp_smooth_occlusion, occ_raw,
        0.25 / adapt_speed, 0.80 / adapt_speed, dt)
    mp_smooth_rain = lagAsym(mp_smooth_rain, rain_raw,
        1.5 / adapt_speed, 3.0 / adapt_speed, dt)
    mp_smooth_wetness = lagAsym(mp_smooth_wetness, wet_raw,
        2.0 / adapt_speed, 5.0 / adapt_speed, dt)          -- molha rapido, seca devagar
    mp_smooth_water = lagAsym(mp_smooth_water, water_raw,
        3.0 / adapt_speed, 8.0 / adapt_speed, dt)          -- pocas: forma lento, some MUITO lento
    mp_smooth_badness = lagAsym(mp_smooth_badness, bad_raw,
        2.0 / adapt_speed, 4.0 / adapt_speed, dt)
    local speed_raw = pure.camera.getSpeed and pure.camera.getSpeed() or 0
    mp_smooth_speed = lagAsym(mp_smooth_speed, speed_raw,
        0.4 / adapt_speed, 1.0 / adapt_speed, dt)

    -- occlusion suavizada e o sinal que todos os modulos usam
    local occlusion = mp_smooth_occlusion

    -- Histerese dia/noite (banda morta 0.45–0.55, evita ping-pong)
    local twilight = pure.mod.twilight(0) or 0.5
    if mp_isNight then
        mp_isNight = (twilight < 0.55)
    else
        mp_isNight = (twilight < 0.45)
    end

    -- ================================================================
    -- 0.5 SUNBLINDING (mantido do 13.1 — parte do checklist anti-arco-iris)
    -- ================================================================
    -- REVERTIDO (13.7): camada de luz artificial REMOVIDA.
    -- A referencia NAO chama nlp, csp_lights, light.ambient, light.sky,
    -- light.distant_ambient, light.advanced_ambient, AI_headlights.
    -- A iluminacao boa dos postes vem do DEFAULT do Pure/CSP.
    -- Valores anteriores sufocavam iluminacao urbana.
    pure.config.set("shaders.sunblinding.star_opacity", 2.025, true)
    pure.config.set("shaders.sunblinding.star_style", 2, true)
    pure.config.set("shaders.sunblinding.iris", 0, true)
    pure.config.set("shaders.sunblinding.cover", 0, true)
    pure.config.set("shaders.sunblinding.blinding", 0, true)
    pure.config.set("shaders.sunblinding.star_blur", 0, true)

    -- ================================================================
    -- 1a. EMISSIVOS INVERSOS A EXPOSICAO (tecnica 1)
    -- Quando AE abre (cena escura), emissivos sao atenuados.
    -- Resolve halo de farol SEM tocar em bloom.
    -- ================================================================
    -- FIX (14.1) — correcao valida, mas NAO era a causa raiz (ver 14.4).
    -- Era: pure.sun.getElevation and pure.sun.getElevation() or 45
    -- "pure.sun" nao existe no SDK do Pure; a API correta e
    -- pure.stellar.getSunElevation() (SDK linha 478). Mesma classe de erro do
    -- "sim": indexar tabela nil, com guard que so cobre o metodo.
    local sunElevation = (pure.stellar and pure.stellar.getSunElevation)
        and pure.stellar.getSunElevation() or 45
    -- LUT emissivo: {-5, 1}, {0, 6}, {90, 8.75}
    local emissiveLUT
    if sunElevation <= -5 then emissiveLUT = 1
    elseif sunElevation <= 0 then emissiveLUT = math.lerp(1, 6, (sunElevation + 5) / 5)
    else emissiveLUT = math.lerp(6, 8.75, math.min(sunElevation, 90) / 90) end
    -- LUT clamp: {-5, 1}, {12.3, 0}, {90, 0}
    local clampLUT
    if sunElevation <= -5 then clampLUT = 1
    elseif sunElevation <= 12.3 then clampLUT = math.lerp(1, 0, (sunElevation + 5) / 17.3)
    else clampLUT = 0 end
    local currentExposure = pure.exposure.getValue() or 0.5
    local emissiveK = math.lerp(0.4, 1, clampLUT) / math.max(currentExposure * emissiveLUT, 0.01)
    -- Piso (13.7): impede supressao total dos emissivos em cena escura.
    -- Sem piso, AE abre → divisor cresce → postes encolhem (laco auto-reforcante).
    emissiveK = math.max(emissiveK, 0.5)
    ac.setAdaptiveEmissiveMultiplier(emissiveK, 1)                          -- → API

    -- ================================================================
    -- 1b. EXPOSICAO — NUCLEO (Bloco 1)
    -- ================================================================
    -- Portado da referencia licenciada (perfil de exposicao mais recente
    -- deles, "method 5"). Mecanismo completo, nao valores soltos:
    --   CBE com analise (0, 0.25, 1.5), mix modulado por oclusao,
    --   YEBIS com alvo por noite/nuvem/sol-de-frente,
    --   limites de CBE por curva de dia com resposta a chuva,
    --   velocidades de adaptacao por oclusao e nebulosidade,
    --   area de medicao separada interior/exterior.
    -- Nossa suavizacao temporal (lagAsym) continua por cima — a referencia
    -- nao tem equivalente.
    -- ================================================================
    local mp_day   = day_compensate   and day_compensate(0)   or (1 - nightness)
    local mp_night = night_compensate and night_compensate(0) or nightness

    local overcast    = pure.world.getOvercast() or 0
    local cloudShadow = pure.world.getCloudShadow and pure.world.getCloudShadow() or 0
    local cloud_shadow = math.max(overcast, cloudShadow)
    local rainNorm    = math.min((mp_smooth_rain or 0) * 5, 1)

    -- Camera olhando pro sol (0 = de costas, 1 = de frente).
    -- A referencia usa internals do Pure; aqui so API documentada.
    local camSun = 0
    do
        local fov  = math.max(pure.camera.getFOV() or 60, 0.1)
        local hori = math.abs(pure.utils.angleDifference(
            pure.stellar.getSunHeading() or 0, pure.camera.getHeading() or 0))
        local vert = math.abs(pure.utils.angleDifference(
            pure.stellar.getSunElevation() or 0, pure.camera.getElevation() or 0))
        camSun = math.pow(math.max(0, 1 - hori / fov), 0.5)
               * math.pow(math.max(0, 1 - vert / fov), 0.5)
    end

    -- ================================================================
    -- CADEIA DE CROSSOVER COMPLETA (Bloco 11 — 1:1 com a referencia)
    -- Nao e so normalizar a exposicao: e uma malha com realimentacao entre
    -- frames. O exposureAdjustment consome o FinalTarget do frame anterior,
    -- e o CbeThreshold e suavizado por applyLag com fator dependente do
    -- brilho maximo do cubemap.
    -- ================================================================
    local expLimMin, expLimMax = 0.02, 0.9
    local Yebismin, Yebismax   = 0.1, 1.0
    local modulatedAe1         = 1

    local interiorbr = ac.isInteriorView()
        and (pure.script.ui.getValue("AlvoInterior") or 1.0) or 1.0

    local FinalEXP = (pure.exposure.getCalculatedValue and pure.exposure.getCalculatedValue())
                     or pure.exposure.getValue() or 0.5

    -- Oclusao com lag, medida nos dois eixos laterais como a referencia
    mp_occluded = math.applyLag(mp_occluded,
        ((ac.getCameraOcclusion(MP_OCC_X1) or 0) + (ac.getCameraOcclusion(MP_OCC_X_1) or 0)) / 2,
        0.95, dt)

    local expMaxCross    = expLimMax * modulatedAe1
    local cbeLevel       = FinalEXP - expLimMin
    local cbeRange       = math.max(expLimMax - expLimMin, 0.001)
    local crossoverRange = math.max(expMaxCross - expLimMin, 0.001)

    -- Normalizacao logistica (suavidade perceptual)
    local function mp_logistic(x, k) return 1 / (1 + math.exp(-k * (x - 0.5))) end
    local cbeNormalized = mp_logistic(cbeLevel / cbeRange, 6)
    local crossoverN    = math.clampN(cbeLevel / crossoverRange, 0.001, 1)

    -- Posicao da AE do YEBIS em relacao ao ponto medio
    local midpointYebis = 0.25 + 0.05 * crossoverN
    local aeYebis       = ac.getAutoExposure() or midpointYebis
    local yebisDistance = (aeYebis < midpointYebis)
        and (midpointYebis - Yebismin) or (Yebismax - midpointYebis)
    local aeNormalized  = (aeYebis - midpointYebis) / math.max(yebisDistance, 0.001)

    local dayTarget   = (pure.script.ui.getValue("AlvoExposicaoDia") or 1.0)
                        * mp_day * pure.mod.dayCurve(1.2, 1.06, 0.5)
    local nightTarget = (pure.script.ui.getValue("AlvoExposicaoNoite") or 1.0)
                        * 0.5 * mp_night
    local sunCurve    = pure.mod.dayCurve(1, 1.2, 0.5)

    local fogW2       = pure.world.getFog() or 0
    local envSeverity = math.max(fogW2, mp_smooth_badness or 0)

    local occlusionBlend  = math.lerp(math.pow(mp_occluded, 2), 1,
                                      math.saturateN(-aeNormalized))
    -- A referencia usa amb:getLuminance(). Esse metodo NAO existe: o SDK
    -- expoe rgb:luminance() e o Pure ja da o valor pronto em
    -- pure.light.getAmbientLuminance(). Usamos o acessor direto.
    local ambLum          = pure.light.getAmbientLuminance() or 1
    local ambientLuminance = (ambLum * occlusionBlend) / math.max(sunCurve, 0.001)

    local maxCubeBright  = math.max(1, ac.getCubemap360BrightnessEstimationMaximum() or 1)
    local brightDelta    = math.abs(maxCubeBright - 15)
    local smoothingF     = math.clamp(1 - (brightDelta / 30), 0.92, 0.99)
    mp_CbeThreshold = math.applyLag(mp_CbeThreshold,
        math.clamp((maxCubeBright - 15) / 5, 0, 1), smoothingF, dt)

    local exposureAdjustment = math.lerp(
        0.1 * mp_CbeThreshold,
        math.clamp(0.5 * mp_FinalTarget, 0, 0.2),
        cbeNormalized)
    local exposureDelta = exposureAdjustment * aeNormalized

    local ambientRatio = math.min(ambientLuminance, 20) / 20
    local ambientBoost = math.pow(1 - ambientRatio, 2)
                       * (1.5 + math.clamp(aeNormalized, -1, 0))

    local exposureTarget = (dayTarget + nightTarget) * interiorbr
    local minExposure    = exposureTarget - exposureAdjustment
    local maxExposure    = exposureTarget + exposureAdjustment
    local clampedExp     = math.clamp(exposureTarget + exposureDelta + 0.1 * envSeverity,
                                      minExposure, maxExposure)
    mp_FinalTarget = math.clamp(clampedExp + ambientBoost, minExposure, 3)

    local ybTarget     = 0.25 - 0.18 * crossoverN
    local AEcrossover  = (2 * mp_day + 0.8 * mp_night) * modulatedAe1

    -- Tunel: nativo do Pure, no lugar da nossa aproximacao por oclusao.
    local inTunnel = pure.utils.CamIsInTunnel and pure.utils.CamIsInTunnel() or 0

    -- Alvo do usuario (nossos sliders continuam mandando)
    local ambientLuminance = math.min(pure.light.getAmbientLuminance() or 1, 25)
    local ambientOffset    = math.clampN(0.5 / math.max(ambientLuminance, 0.01), 0, 1)
    local AETarget         = 2.5 * ae_slider

    -- ================================================================
    -- MODOS DE EXPOSICAO (Bloco 13 — os 5 da referencia)
    -- 1 Classico | 2 Hibrido | 3 Filmico | 4 Alternativo | 5 Adaptativo
    -- O 5 e o default e o mais recente deles.
    -- ================================================================
    local expoModo = math.floor(math.clamp(pure.script.ui.getValue("ModoExposicao") or 5, 1, 5))
    local calibNoite = pure.script.ui.getValue("CalibracaoTelaNoite") or 1.0
    local expNorm = math.lerpInvSat(FinalEXP, expLimMin, expLimMax)

    if expoModo == 1 then
        -- CLASSICO: sem handleExposure, alvo montado a mao
        pure.script.tools.handleExposure(0)
        ac.setAutoExposureTarget(ybTarget * mp_FinalTarget * exposureTarget)
        ac.setAutoExposureLimits(Yebismin, Yebismax)
        pure.config.set("pp.brightness",
            math.lerp(0.90, 1, crossoverN) * mp_day
          + math.lerp(0.85, 1, crossoverN) * mp_night, true)
        pure.exposure.cbe.setTarget(mp_FinalTarget + 1 * mp_night)
        ac.setPpBrightness(0.8 * calibNoite)
        pure.exposure.cbe.setLimits(expLimMin, expLimMax)
        pure.exposure.setCBEMix(0.9)
        pure.exposure.cbe.setAdaptionSpeeds(10 * adapt_speed, 1 * adapt_speed)
        pure.exposure.yebis.setAdaptionSpeeds(10, 10)
        pure.exposure.setBypass(math.min(FinalEXP, AEcrossover))

    elseif expoModo == 2 then
        -- HIBRIDO: handleExposure method 4
        pure.script.tools.handleExposure(2, { method = 4, target = 2, mix = 0.75,
            fixedexposure = 0.5, minimumexposure = 0.05, superexposure = 1, show_ui = false })
        pure.config.set("pp.brightness",
            math.lerp(0.85, 1, crossoverN) * mp_day
          + math.lerp(0.73, 1.1, crossoverN) * mp_night, true)
        pure.script.tools.handleExposure_setParameter("target_mod",
            exposureTarget + (2 * mp_night) + (1 * mp_day))
        pure.script.tools.handleExposure_setParameter("mix_mod", 0.5)
        pure.script.tools.handleExposure_setParameter("method_mod", 4)
        ac.setPpBrightness(1.0 * calibNoite)
        -- Modo 2 entrega o controle ao handleExposure: sem bypass, sem
        -- sobrescrever limites. E essa a diferenca de caracter dele.
        pure.exposure.cbe.setLimits(expLimMin, expLimMax)
        pure.exposure.cbe.setAdaptionSpeeds(8 * adapt_speed, 3 * adapt_speed)

    elseif expoModo == 3 then
        -- FILMICO: handleExposure method 5
        pure.script.tools.handleExposure(2, { method = 5, target = 2, mix = 1.0,
            fixedexposure = 0.20, superexposure = 0.50, fixedmixmulti = 1.0, show_ui = false })
        pure.config.set("pp.brightness",
            math.lerp(0.86, 1, crossoverN) * mp_day
          + math.lerp(0.76, 1.1, crossoverN) * mp_night, true)
        pure.script.tools.handleExposure_setParameter("mix_mod", 1)
        pure.script.tools.handleExposure_setParameter("target_mod",
            (exposureTarget + (0.3 * mp_night)) * 0.8)
        pure.script.tools.handleExposure_setParameter("method_mod", 5)
        ac.setPpBrightness((0.95 + 0.05 * mp_night) * calibNoite)
        pure.exposure.cbe.setLimits(expLimMin, expLimMax)
        pure.exposure.cbe.setAdaptionSpeeds(12 * adapt_speed, 2 * adapt_speed)

    elseif expoModo == 4 then
        -- ALTERNATIVO: area de medicao "photo realistic" + AE alternativa do YEBIS
        -- Desliga o tool do Pure: quem manda aqui e o YEBIS direto.
        pure.script.tools.handleExposure(0)
        ac.setPpBrightness((0.95 + 0.05 * mp_night) * calibNoite)
        pure.exposure.cbe.setAnalysis(0, 0.24, 1.5)
        local pr   = 0.5
        local mod  = math.pow(pr, 1.5)
        local inte = ac.isInteriorView()
        ac.setAutoExposureMeasuringArea(
            vec2(0.0, 0.18 - 0.11 * mod),
            vec2(0.6 - 0.4 * mod, 0.55 - 0.30 * mod))
        pure.exposure.yebis.useAlternativeAutoexposure()
        -- A referencia usa _l_Exposure_lut[4] (LUT interna do Pure, inacessivel).
        -- Substituido pela exposicao normalizada, que e o mesmo eixo.
        local boost = mod * (inte and 0.5 or 0.75) * (1 - expNorm)
        pure.exposure.yebis.setTarget(pure.exposure.yebis.getTarget() * (1 + boost))
        pure.exposure.yebis.setLimits(pure.exposure.yebis.getLowLimit(),
                                      pure.exposure.yebis.getHighLimit() * (1 + boost))
        pure.exposure.cbe.setLimits(expLimMin + 0.02, expLimMax + 0.01)
        pure.exposure.cbe.setAdaptionSpeeds(10 * adapt_speed, 4 * adapt_speed)
        pure.exposure.setCBEMix(1.0)

    else
        -- ADAPTATIVO (default): o perfil mais recente da referencia.
        -- Desliga o tool do Pure — se ficasse instalado de uma troca de modo
        -- anterior, ele continuaria rodando e brigando com o nosso setBypass.
        pure.script.tools.handleExposure(0)
        pure.light.setSpectrumAdaption(false)
        pure.light.setVAOAdaption(false)
        pure.exposure.cbe.setAnalysis(0, 0.25, 1.5)
        pure.exposure.setCBEMix(math.lerp(0.86, 0.5, occlusion))
        pure.config.set("pp.brightness",
            ((1.00) * (1 - crossoverN) + crossoverN) * mp_day
          + (0.94   * (1 - crossoverN) + 1.10 * crossoverN) * mp_night, true)
        pure.config.set("ui.white_reference_point", 10, true)
        ac.setAutoExposureTarget(0.4)
        ac.setAutoExposureLimits(1/50, 2)
        if ac.isInteriorView() then
            ac.setAutoExposureMeasuringArea(vec2(0, -0.05), vec2(0.40, 0.35))
        else
            ac.setAutoExposureMeasuringArea(vec2(0, -3/40), vec2(0.60, 13/20))
        end
    end

    -- Metering por FOV (nosso — a referencia nao tem)
    local fovNow = pure.camera.getFOV() or 60
    ac.useCubemapBrightnessEstimation(math.clamp(1 - (fovNow / 100), 0, 0.9), 2, 10.5)

    -- ================================================================
    mp_sec("1c", function()
    -- ================================================================
    -- 1c. YEBIS + LIMITES + VELOCIDADES — SOMENTE MODO 5
    -- ================================================================
    -- CORRECAO: antes esta secao rodava sempre e apagava tudo que os modos
    -- 1 a 4 tinham acabado de configurar em 1b. O corpo daqui e a cauda do
    -- modo 5; na referencia ele vive DENTRO do ramo, nao depois do if.
    if expoModo ~= 5 then return end

    pure.exposure.yebis.setLimits(1/50, 2)
    local yebisTarget = (0.4 + 0.6 * mp_night) * (1 - 0.1 * math.clamp(cloud_shadow, 0, 1))
                      + 0.4 * camSun * (pure.mod.twilight(0) + 0.5 * mp_day) * (1 - 0.5 * overcast)
    pure.exposure.yebis.setTarget(yebisTarget)
    pure.exposure.yebis.setAdaptionSpeeds(10, 1)

    -- Piso do CBE por curva de dia, com resposta a chuva.
    -- E o que impede a noite de ser levantada artificialmente.
    local curveMin = pure.mod.dayCurve(0.06 * pure.mod.day(4.5),
                                       0.2 - 0.15 * rainNorm * pure.mod.sun(0), 4.0)
    curveMin = math.clamp(curveMin, 0.12 * mp_night, 0.30)
    pure.exposure.cbe.setLimits(curveMin, 10)
    pure.exposure.cbe.setTarget(AETarget + ambientOffset)

    -- Velocidades: escurecer rapido, clarear conforme nebulosidade.
    -- Tunel nativo acelera a descida. adapt_speed e o nosso slider.
    local darkAdapt   = ((occlusion > 0.5) or (inTunnel > 0.5)) and 6 or 4
    local brightAdapt = math.max(14 - 8 * overcast, 7)
    pure.exposure.cbe.setAdaptionSpeeds(brightAdapt * adapt_speed, darkAdapt * adapt_speed)
    end)

    mp_sec("1d", function()
    -- ================================================================
    -- 1d. BYPASS FINAL — SOMENTE MODO 5
    -- ================================================================
    -- Os modos 1 a 4 fazem (ou dispensam) o proprio bypass em 1b.
    if expoModo ~= 5 then return end
    pure.exposure.setBypass(math.min(FinalEXP, AEcrossover))
    end)

    local currentExposure = pure.exposure.getValue() or FinalEXP

    -- Readouts
    pure.script.ui.setValue("ExposureFinal", FinalEXP)
    pure.script.ui.setValue("CBETarget", AETarget + ambientOffset)
    pure.script.ui.setValue("CBEValue", currentExposure)
    pure.script.ui.setValue("Nightness", nightness)
    pure.script.ui.setValue("OcclusionRaw", occ_raw)
    pure.script.ui.setValue("OcclusionSmooth", occlusion)
    pure.script.ui.setValue("Wetness", mp_smooth_wetness)
    pure.script.ui.setValue("RainIntensity", mp_smooth_rain)
    pure.script.ui.setValue("WaterLevel", mp_smooth_water)

    mp_sec("3", function()
    -- 3. TONEMAP — 3 modos referencia
    -- ================================================================
    local tm_mode_radio = pure.script.ui.getValue("TonemapMode") or 1
    local mode_selector = tm_mode_radio - 1  -- radio 1-based → shader 0-based

    -- GT7-Blend params (mode 0)
    local v_gt7_white  = pure.script.ui.getValue("GT7White") or 0.800
    local v_gt7_a      = pure.script.ui.getValue("GT7a") or 1.200
    local v_gt7_l      = pure.script.ui.getValue("GT7l") or 0.250
    local v_gt7_c      = pure.script.ui.getValue("GT7c") or 1.000
    local v_gt7_P      = pure.script.ui.getValue("GT7P") or 1.000
    local v_gt7_m      = pure.script.ui.getValue("GT7m") or 0.120
    local v_gt7_blend  = pure.script.ui.getValue("GT7Blend") or 0.650
    local v_gt7_scurve = pure.script.ui.getValue("GT7SCurve") or 0.250
    local v_gt7_sat    = pure.script.ui.getValue("GT7Sat") or 1.200
    local v_gt7_gamma  = pure.script.ui.getValue("GT7Gamma") or 1.000
    local v_gt7_fade   = pure.script.ui.getValue("GT7FadeStart") or 0.980
    local v_gt7_b      = pure.script.ui.getValue("GT7b") or 0.006

    -- referencia-Tone params (mode 1)
    local v_px_d       = pure.script.ui.getValue("PxD") or 2.100
    local v_px_a       = pure.script.ui.getValue("PxA") or 2.700
    local v_px_c       = pure.script.ui.getValue("PxC") or 0.850
    local v_px_e       = pure.script.ui.getValue("PxE") or 0.600
    local v_px_f       = pure.script.ui.getValue("PxF") or 0.065
    local v_px_shadows = pure.script.ui.getValue("PxShadows") or 0.000
    local v_px_scurve  = pure.script.ui.getValue("PxSCurve") or 0.300
    local v_px_gamma   = pure.script.ui.getValue("PxGamma") or 1.000
    local v_px_sat     = pure.script.ui.getValue("PxSat") or 1.150

    -- GT-Film params (mode 2)
    local v_film_P      = pure.script.ui.getValue("FilmP") or 1.250
    local v_film_a      = pure.script.ui.getValue("FilmA") or 0.950
    local v_film_l      = pure.script.ui.getValue("FilmL") or 0.150
    local v_film_c      = pure.script.ui.getValue("FilmC") or 1.200
    local v_film_m      = pure.script.ui.getValue("FilmM") or 0.125
    local v_film_b      = pure.script.ui.getValue("FilmB") or 0.010
    local v_film_scurve = pure.script.ui.getValue("FilmSCurve") or 0.250
    local v_film_gamma  = pure.script.ui.getValue("FilmGamma") or 0.850
    local v_film_sat    = pure.script.ui.getValue("FilmSat") or 0.950

    -- AgX params (mode 3)
    local v_agx_P     = pure.script.ui.getValue("AgxP") or 2.000
    local v_agx_a     = pure.script.ui.getValue("AgxA") or 1.000
    local v_agx_m     = pure.script.ui.getValue("AgxM") or 0.290
    local v_agx_l     = pure.script.ui.getValue("AgxL") or 0.400
    local v_agx_c     = pure.script.ui.getValue("AgxC") or 1.000
    local v_agx_b     = pure.script.ui.getValue("AgxB") or 0.000
    local v_agx_gain  = pure.script.ui.getValue("AgxGain") or 1.000
    local v_agx_black = pure.script.ui.getValue("AgxBlack") or 0.000
    local v_agx_mid   = pure.script.ui.getValue("AgxMidtones") or 1.000
    local v_agx_mix   = pure.script.ui.getValue("AgxMix") or 1.000
    local v_agx_mixe  = pure.script.ui.getValue("AgxMixExp") or 0.000
    local v_agx_slope = pure.script.ui.getValue("AgxSlope") or 1.250
    local v_agx_power = pure.script.ui.getValue("AgxPower") or 1.750
    local v_agx_sat   = pure.script.ui.getValue("AgxSat") or 1.000

    -- → API: ac.setPpTonemapFunction() — ALL values reach shader uniforms
    ac.setPpTonemapFunction({
        defines = { TONEMAP_FN = 0 },
        cacheKey = 200,
        values = {
            REF_LUMINANCE  = 100.0,
            mode_selector  = mode_selector,
            -- GT7-Blend (mode 0)
            gt7_white      = v_gt7_white,
            gt7_P          = v_gt7_P,
            gt7_a          = v_gt7_a,
            gt7_m          = v_gt7_m,
            gt7_l          = v_gt7_l,
            gt7_c          = v_gt7_c,
            gt7_b          = v_gt7_b,
            gt7_blend      = v_gt7_blend,
            gt7_fade_start = v_gt7_fade,
            gt7_s_curve    = v_gt7_scurve,
            gt7_sat        = v_gt7_sat,
            gt7_gamma      = v_gt7_gamma,
            -- referencia-Tone (mode 1)
            px_d         = v_px_d,
            px_a         = v_px_a,
            px_c         = v_px_c,
            px_e         = v_px_e,
            px_f         = v_px_f,
            px_i         = 0,
            px_shadows   = v_px_shadows,
            px_s_curve   = v_px_scurve,
            px_post_gamma = v_px_gamma,
            px_sat       = v_px_sat,
            px_b         = 0.15,
            -- GT-Film (mode 2)
            film_P         = v_film_P,
            film_a         = v_film_a,
            film_m         = v_film_m,
            film_l         = v_film_l,
            film_c         = v_film_c,
            film_b         = v_film_b,
            film_s_curve   = v_film_scurve,
            film_gamma     = v_film_gamma,
            film_sat       = v_film_sat,
            -- AgX + Uchimura (mode 3)
            agx_P          = v_agx_P,
            agx_a          = v_agx_a,
            agx_m          = v_agx_m,
            agx_l          = v_agx_l,
            agx_c          = v_agx_c,
            agx_b          = v_agx_b,
            agx_gain       = v_agx_gain,
            agx_black      = v_agx_black,
            agx_midtones   = v_agx_mid,
            agx_mix        = v_agx_mix,
            agx_mix_exp    = v_agx_mixe,
            agx_slope      = v_agx_slope,
            agx_power      = v_agx_power,
            agx_sat        = v_agx_sat,
        },
        shader = MPIXELS_TONEMAP_SHADER
    })
    ac.setPpTonemapUseHdrSpace(true)

    -- ================================================================
    end)
    -- 4. PURKINJE — gate global + SPICE
    -- ================================================================
    local purk_ativo = pure.script.ui.getValue("PurkinjeAtivo") or false
    local purk_int   = pure.script.ui.getValue("PurkinjeInt") or D.purk_int
    local purk_thr   = pure.script.ui.getValue("PurkinjeThr") or D.purk_thr
    local purk_global_drive = 0
    if purk_ativo then
        purk_global_drive = nightness * D.purk_mult
    end
    -- → API: pure.pp.set → SPICE shader
    pure.pp.set("schdr.MPIXELS_FX.PurkinjeGlobalDrive", purk_global_drive)
    pure.pp.set("schdr.MPIXELS_FX.PurkinjeIntensity", purk_int)
    pure.pp.set("schdr.MPIXELS_FX.PurkinjeThreshold", purk_thr)
    pure.script.ui.setValue("PurkinjeGlobalDrive", purk_global_drive)

    -- ================================================================
    mp_sec("5", function()
    -- 5. REFLECTIONS (Pixels spec — skipped in Clone-Exato)
    -- ================================================================
    if not CE.skip_reflections then
        local refl_day   = pure.script.ui.getValue("ReflDayLevel") or 2.5
        local refl_night = pure.script.ui.getValue("ReflNightLevel") or 4.0
        local refl_sat   = pure.script.ui.getValue("ReflSatMult") or 0.85
        local refl_fres  = pure.script.ui.getValue("ReflFresnel") or 0.85
        local refl_polar = pure.script.ui.getValue("ReflPolarizer") or 0.25
        local refl_sky   = pure.script.ui.getValue("ReflSkyLum") or 1.25
        local refl_ssat  = pure.script.ui.getValue("ReflSkySat") or 0.95
        local refl_sgam  = pure.script.ui.getValue("ReflSkyGamma") or 1.05
        local refl_emis  = pure.script.ui.getValue("ReflEmissiveBoost") or 1.0
        local refl_spec  = pure.script.ui.getValue("ReflSunSpecular") or 2.0

        pure.config.set("reflections.level", pure.mod.dayCurve(refl_night, refl_day, 1), true)
        pure.config.set("reflections.saturation", refl_sat * refl_ssat, true)
        ac.setFresnelGamma(refl_fres * refl_sgam)
        pure.camera.setCPL(refl_polar, 0, 0)
        ac.setReflectedSkyTweaks(refl_sky)
        pure.config.set("reflections.emissive_boost", refl_emis, true)
        pure.config.set("light.sun.speculars", refl_spec, true)
    end

    -- ================================================================
    -- 5.5 CHUVA E ASFALTO MOLHADO (13.4 — diferencial exclusivo)
    -- Nenhum filtro analisado usa as 3 APIs de chuva do Pure.
    -- ================================================================
    -- Normalizar com joelhos diferentes (cor troca mais devagar que geometria)
    local rainGeom     = math.clampN(mp_smooth_rain / 0.02, 0, 1)    -- geometria: satura em 2%
    local rainColor    = math.clampN(mp_smooth_rain / 0.05, 0, 1)    -- cor: satura em 5%
    local rainLighting = math.clampN(mp_smooth_rain / 0.6, 0, 1)     -- lighting: satura em 60%
    local wetness      = mp_smooth_wetness                            -- 0-1 ja suavizado
    local waterLevel   = mp_smooth_water                              -- pocas 0-1

    -- WETNESS -> reflexos (lerp entre modelo seco e molhado)
    if not CE.skip_reflections and wetness > 0.001 then
        local refl_level_base = pure.mod.dayCurve(
            pure.script.ui.getValue("ReflNightLevel") or 4.0,
            pure.script.ui.getValue("ReflDayLevel") or 2.5, 1)
        local refl_sat_base   = (pure.script.ui.getValue("ReflSatMult") or 0.85)
                              * (pure.script.ui.getValue("ReflSkySat") or 0.95)
        local cpl_base        = pure.script.ui.getValue("ReflPolarizer") or 0.25

        -- Modelo molhado (semeadura preset 3: level 3.25, sat 0.584, CPL 0.55)
        local refl_level_wet  = math.min(refl_level_base * 1.55, 3.5)  -- teto: nao virar espelho
        local refl_sat_wet    = refl_sat_base * 0.77                   -- molhado dessatura
        local cpl_wet         = cpl_base + 0.15                        -- mais polarizador

        -- Lerp seco->molhado pelo wetness
        local refl_level_now = math.lerp(refl_level_base, refl_level_wet, wetness)
        local refl_sat_now   = math.lerp(refl_sat_base, refl_sat_wet, wetness)
        local cpl_now        = math.lerp(cpl_base, cpl_wet, wetness)

        pure.config.set("reflections.level", refl_level_now, true)      -- → API (sobrescreve seco)
        pure.config.set("reflections.saturation", refl_sat_now, true)
        pure.camera.setCPL(cpl_now, 0, 0)
    end

    -- WATER (pocas) -> especular sutil
    if waterLevel > 0.001 then
        local spec_boost = 1.0 + waterLevel * 0.5   -- max +50%
        pure.config.set("light.sun.speculars",
            (pure.script.ui.getValue("ReflSunSpecular") or 2.0) * spec_boost, true)
    end

    -- INTENSITY -> rainhaze (nao chove dentro do tunel)
    if rainGeom > 0.001 then
        pure.config.set("shaders.rainhaze.gain", occlusion * rainGeom, true)  -- → API
    end

    -- INTENSITY -> daylight boost (so de dia — o lerp externo anula a noite)
    -- Tecnica: confinar efeito a um regime sem branch
    if rainLighting > 0.001 then
        local rainDaylightBoost = math.lerp(1, math.lerp(1, 3.51, rainLighting), twilight)
        -- Aplicar via multiplicador no sun level (nao na exposicao — ja e adaptativa)
        pure.config.set("sky.sun_disk.level", 0.35 * rainDaylightBoost, true)
    end

    -- ================================================================
    end)
    -- 6. COLOR GRADING (Pixels spec — dia/noite)
    -- ================================================================
    local anti_dobra = 1.0 - purk_global_drive * 0.5

    local saturacao    = pure.script.ui.getValue("Saturacao") or D.sat
    local sat_noite    = pure.script.ui.getValue("SatNoite") or 1.0
    local gamma_dia    = pure.script.ui.getValue("GammaDia") or 1.0
    local gamma_noite  = pure.script.ui.getValue("GammaNoite") or 1.0
    local temperatura  = pure.script.ui.getValue("Temperatura") or D.temp
    local sepia_dia    = pure.script.ui.getValue("SepiaDia") or 1.0
    local sepia_noite  = pure.script.ui.getValue("SepiaNoite") or 1.0
    local vig_pp_dia   = pure.script.ui.getValue("VignettePPDia") or 0.0
    local vig_pp_noite = pure.script.ui.getValue("VignettePPNoite") or 0.0
    local contraste    = pure.script.ui.getValue("ContrastePos") or D.contrast_post
    local night_shift  = pure.script.ui.getValue("ShiftNoturno") or D.night_shift
    local lut_int      = pure.script.ui.getValue("LUTIntensidade") or D.lut_int

    -- Saturacao dia/noite com soft-clip
    local sat_clamped_dia = math.min(saturacao, D.soft_clip * 1.4)
    local sat_now = pure.mod.dayCurve(sat_noite, sat_clamped_dia, 1)
    if not mp_ccOn then
        pure.pp.set("pp.saturation", sat_now, true)                        -- → API
    end

    -- Temperatura: pp.color_temperature e MULTIPLICADOR (~1.0 = neutro), NAO Kelvin!
    -- referencia nao chama pp.color_temperature (fica neutro = sem tint).
    -- MALDITOS PIXELS layer: UI em Kelvin, convertido pra multiplicador: K / 6500.
    -- night_shift em Kelvin: subtrai do multiplicador. Ex: shift=250 → -0.038
    -- FIX 12.17: antes mandava 6500 (Kelvin bruto) → azul extremo.
    local temp_mult_dia = temperatura / 6500.0              -- 6500/6500=1.0 (neutro)
    local shift_mult = (night_shift / 6500.0) * anti_dobra  -- 250/6500=0.038
    local temp_now = pure.mod.dayCurve(temp_mult_dia - shift_mult, temp_mult_dia, 1)
    if not mp_ccOn then
        pure.pp.set("pp.color_temperature", temp_now, true)                 -- → API
    end

    -- Contraste (noite × 0.92 so quando variante ativa MALDITOS PIXELS layer)
    local contrast_night = D.skip_extras and contraste or (contraste * 0.92)
    if not mp_ccOn then
        pure.pp.set("pp.contrast",                                          -- → API
            pure.mod.dayCurve(contrast_night, contraste, 1), true)
    end

    -- Gamma dia/noite (guard anti-pop: CSP pula o estagio se gama==1.0 exato)
    local gamma_val = pure.mod.dayCurve(gamma_noite, gamma_dia, 1)
    if gamma_val > 0.9999 and gamma_val < 1.0001 then gamma_val = 0.9999 end
    pure.pp.set("pp.gamma", gamma_val, true)                                -- → API

    -- Sepia (1.0 = normal color, 0.0 = grayscale, >1 = warm)
    if not mp_ccOn then
        pure.pp.set("pp.sepia",                                             -- → API
            pure.mod.dayCurve(sepia_noite, sepia_dia, 1), true)
    end

    -- PP Vignette (Pure native, separate from SPICE vignette)
    -- referencia nao usa pp.vignette_str — este e MALDITOS PIXELS addition.
    pure.pp.set("pp.vignette_str",                                          -- → API
        pure.mod.dayCurve(vig_pp_noite, vig_pp_dia, 1), true)

    -- ================================================================
    mp_sec("6b", function()
    -- 6b. LUT 3D DINAMICA POR ALTITUDE SOLAR (13.5)
    -- LUT de filme DESLIGADA entre -10° e +0.5° — e onde ela quebra o
    -- gradiente do ceu. Decisao de engenharia, nao estetica.
    -- ================================================================
    -- LUT: {-12, 0.5}, {-10, 0}, {0.5, 0}, {4, 0.32}, {90, 0.32}
    local cgFilmic
    if sunElevation <= -12 then cgFilmic = 0.5
    elseif sunElevation <= -10 then cgFilmic = math.lerp(0.5, 0, (sunElevation + 12) / 2)
    elseif sunElevation <= 0.5 then cgFilmic = 0
    elseif sunElevation <= 4 then cgFilmic = math.lerp(0, 0.32, (sunElevation - 0.5) / 3.5)
    else cgFilmic = 0.32 end
    -- Escalar pelo slider do usuario (lut_int e o multiplicador de identidade)
    ac.setPpColorGradingIntensity(cgFilmic * lut_int / 0.32)                -- → API

    end)
    -- 6c. AMBIENTE CONDICIONAL — REMOVIDO (13.7)
    -- light.ambient.saturation revertida ao default do Pure.
    -- A referencia NAO chama light.ambient.saturation.
    -- A tinta solar condicional (13.5) sobrescrevia o default e sufocava
    -- a cor dos postes em cena urbana noturna.

    mp_sec("6d", function()
    -- ================================================================
    -- 6d. MOTOR DE COR CSP — modulacao por frame (Bloco 3)
    -- ================================================================
    if not mp_cc then return end

    if not mp_ccOn then
        -- Motor desligado: nos em neutro para nao somar com o estagio de PP.
        mp_cc.fade.color        = rgb(0, 0, 0)
        mp_cc.fade.effectRatio  = 0
        mp_cc.contr.value       = 1
        mp_cc.sat.value         = 1
        mp_cc.sepia.value       = 0
        mp_cc.wb.temperature    = 6500
        mp_cc.wb.luminance      = 0
        mp_cc.hue.hue           = 0
        mp_cc.tint.color        = rgb(1, 1, 1)
        return
    end

    local dc, nc = mp_day, mp_night
    local iDia   = math.floor(math.clamp(pure.script.ui.getValue("PerfilCorDia")   or 1, 1, #MP_COR_DIA))
    local iNoite = math.floor(math.clamp(pure.script.ui.getValue("PerfilCorNoite") or 1, 1, #MP_COR_NOITE))
    local d, n = MP_COR_DIA[iDia], MP_COR_NOITE[iNoite]

    local uTemp = pure.script.ui.getValue("CorTemperatura")  or 1.0
    local uLum  = pure.script.ui.getValue("CorLuminosidade") or 1.0
    local uCon  = pure.script.ui.getValue("CorContraste")    or 1.0
    local uSep  = pure.script.ui.getValue("CorSepia")        or 1.0
    local uHue  = pure.script.ui.getValue("CorMatiz")        or 1.0
    local uSat  = pure.script.ui.getValue("CorSaturacao")    or 1.0
    local uFade = pure.script.ui.getValue("CorFade")         or 1.0
    local tR    = pure.script.ui.getValue("CorTintR")        or 1.0
    local tG    = pure.script.ui.getValue("CorTintG")        or 1.0
    local tB    = pure.script.ui.getValue("CorTintB")        or 1.0

    -- Mistura dia/noite: cada perfil pesa pela sua compensacao.
    mp_cc.fade.color       = rgb(d[1]*dc + n[1]*nc, d[2]*dc + n[2]*nc, d[3]*dc + n[3]*nc)
    mp_cc.fade.effectRatio = (d[13]*dc + n[13]*nc) * uFade
    mp_cc.tint.color       = rgb((d[4]*dc + n[4]*nc) * tR,
                                 (d[5]*dc + n[5]*nc) * tG,
                                 (d[6]*dc + n[6]*nc) * tB)
    mp_cc.wb.temperature   = (d[7]*dc + n[7]*nc) * uTemp
    mp_cc.wb.luminance     = (d[8]*dc + n[8]*nc) * uLum
    mp_cc.contr.value      = (d[9]*dc + n[9]*nc) * uCon
    mp_cc.sepia.value      = (d[10]*dc + n[10]*nc) * uSep * pure.mod.dayCurve(1.3, 1, 0.67)
    mp_cc.hue.hue          = (d[11]*dc + n[11]*nc) * uHue
    mp_cc.sat.value        = (d[12]*dc + n[12]*nc) * uSat

    pure.script.ui.setValue("CorTempEstado", mp_cc.wb.temperature)
    pure.script.ui.setValue("CorSatEstado", mp_cc.sat.value)
    end)

    -- ================================================================
    mp_sec("7", function()
    -- ---- Glare por perfil dia/noite (Bloco 6) ----
    do
        local iD = math.floor(math.clamp(pure.script.ui.getValue("GlarePerfilDia") or 1, 1, #MP_GLARE_DIA))
        local iN = math.floor(math.clamp(pure.script.ui.getValue("GlarePerfilNoite") or 1, 1, #MP_GLARE_NOITE))
        local gD, gN = MP_GLARE_DIA[iD], MP_GLARE_NOITE[iN]
        local kI = pure.script.ui.getValue("GlareIntensidade") or 1.0
        local kT = pure.script.ui.getValue("GlareLimiar") or 1.0
        local d, n = mp_day, mp_night
        _mp_glare = {
            thresh   = (gD.thresh*d   + gN.thresh*n) * kT,
            lum      = (gD.lum*d      + gN.lum*n) * kI,
            gamma    =  gD.gamma*d    + gN.gamma*n,
            bloomLum = (gD.bloomLum*d + gN.bloomLum*n) * kI,
            starSoft =  gD.starSoft*d + gN.starSoft*n,
            gaussR   =  gD.gaussR*d   + gN.gaussR*n,
            starLum  = (gD.starLum*d  + gN.starLum*n) * kI,
            starLen  =  gD.starLen*d  + gN.starLen*n,
            starLen2 =  gD.starLen2*d + gN.starLen2*n,
            streaks  =  gD.streaks*d  + gN.streaks*n,
            ghost    =  gD.ghost*d    + gN.ghost*n,
            halo     =  gD.halo*d     + gN.halo*n,
            distort  =  gD.distort*d  + gN.distort*n,
            sharp    =  gD.sharp*d    + gN.sharp*n,
            disp     =  gD.disp*d     + gN.disp*n,
            antiRB   =  pure.script.ui.getValue("GlareAntiArcoIris") ~= false,
        }
        -- Anamorfico (Bloco 16): radio 1=desligado, 2=ativo.
        -- A referencia usa o mesmo valor como multiplicador do bloom
        -- secundario, e nao so como flag no YEBIS.
        _mp_anamorph = (math.floor(pure.script.ui.getValue("GlareAnamorfico") or 1) > 1)
            and 3 or 1
    end

    -- 7. BLOOM (skipped in Clone-Exato — INI estático prevalece)
    -- ================================================================
    if not CE.skip_bloom_override then
        local bg_dia   = pure.script.ui.getValue("BloomGammaDia") or 1.5
        local bg_noite = pure.script.ui.getValue("BloomGammaNoite") or 1.35
        local ga_dia   = pure.script.ui.getValue("GlareAmountDia") or 0.75
        local ga_noite = pure.script.ui.getValue("GlareAmountNoite") or 0.75
        local gl_dia   = pure.script.ui.getValue("GlareLumDia") or 0.65
        local gl_noite = pure.script.ui.getValue("GlareLumNoite") or 0.75
        local bl_dia   = pure.script.ui.getValue("BloomLumDia") or 0.65
        local bl_noite = pure.script.ui.getValue("BloomLumNoite") or 0.75
        local sl_dia   = pure.script.ui.getValue("StarLumDia") or 0.5
        local sl_noite = pure.script.ui.getValue("StarLumNoite") or 0.75
        local slen_dia = pure.script.ui.getValue("StarLengthDia") or 0.15
        local slen_noite = pure.script.ui.getValue("StarLengthNoite") or 0.15
        local gt_dia   = pure.script.ui.getValue("GlareThreshDia") or 1.0
        local gt_noite = pure.script.ui.getValue("GlareThreshNoite") or 1.0
        local ghost_on = pure.script.ui.getValue("GhostEnabled") or false
        local ghost_lum = pure.script.ui.getValue("GhostLum") or 0.75
        local ghost_dist = pure.script.ui.getValue("GhostDist") or 0.5

        -- Suavizar fator de glare (13.3): evita pulsar em luz salpicada
        local raw_glare_f = pure.mod.dayCurve(ga_noite * gl_noite, ga_dia * gl_dia, 1)
        mp_smooth_glare_f = lagAsym(mp_smooth_glare_f, raw_glare_f,
            0.30 / adapt_speed, 0.60 / adapt_speed, dt)

        _mp_bloom = {
            bloomGamma   = pure.mod.dayCurve(bg_noite, bg_dia, 1),
            glareLum     = mp_smooth_glare_f,  -- suavizado (13.3)
            bloomLum     = pure.mod.dayCurve(bl_noite, bl_dia, 1),
            starLum      = pure.mod.dayCurve(sl_noite, sl_dia, 1),
            starLength   = pure.mod.dayCurve(slen_noite, slen_dia, 1),
            threshold    = pure.mod.dayCurve(gt_noite, gt_dia, 1),
            ghostLum     = ghost_on and ghost_lum or 0,
            ghostDist    = ghost_on and ghost_dist or 0,
        }
    else
        _mp_bloom = nil  -- Glarefunc fica inerte, INI estático prevalece
    end

    -- ================================================================
    end)
    mp_sec("8", function()
    -- 8. WORLD (skipped in Clone-Exato)
    -- ================================================================
    if not CE.skip_world then
        local cb_day   = pure.script.ui.getValue("CloudBrightDay") or 1.0
        local cc_day   = pure.script.ui.getValue("CloudContrastDay") or 1.0
        local cb_night = pure.script.ui.getValue("CloudBrightNight") or 1.0
        local cc_night = pure.script.ui.getValue("CloudContrastNight") or 1.5

        pure.config.set("clouds2D.brightness", pure.mod.dayCurve(cb_night, cb_day, 1), true)
        pure.config.set("clouds2D.contrast", pure.mod.dayCurve(cc_night, cc_day, 1), true)

        local sun_size    = pure.script.ui.getValue("SunSize") or 0.5
        local moon_size   = pure.script.ui.getValue("MoonSize") or 7.5
        local moon_bright = pure.script.ui.getValue("MoonBright") or 0.275
        local moon_light  = pure.script.ui.getValue("MoonLight") or 0.3
        local night_stars = pure.script.ui.getValue("NightStars") or 150

        ac.setSkySunMoonSizeMultiplier(1.5 + sun_size + moon_size * nightness)
        pure.config.set("moon.appearance", moon_bright, true)
        pure.config.set("moon.light", moon_light, true)
        pure.stellar.setStarsBrightness(night_stars / 150.0 * nightness)

        local rainbow_on = pure.script.ui.getValue("RainbowEnabled") or false
        ac.setSkyV2Rainbow(rainbow_on and 1 or 0)

        -- Turbidez POR FRAME (Bloco 18). Tem que ser aqui e nao no init:
        -- o Pure reescreve 10 todo frame em __PURE__create_sky(dt).
        if pure.script.ui.getValue("TurbidezAtiva") ~= false then
            local regiaoAll = (ac.SkyRegion and ac.SkyRegion.All) or 3
            local turb = pure.script.ui.getValue("TurbidezValor") or 10.0
            ac.setSkyV2Turbidity(regiaoAll, math.clamp(turb, 0.1, 40))
        end
    end

    -- ================================================================
    end)
    mp_sec("8b", function()
    -- ================================================================
    -- 8b. CEU, ESTRELAS, NLP E AMBIENTE (Bloco 5)
    -- Portado da referencia licenciada.
    -- O NLP (poluicao luminosa) e autorado PELA PISTA — a referencia corta
    -- nivel e densidade pela metade (0.5). Nos nunca tocamos nisso: ficava
    -- no default 1.0, e e a origem do ambar noturno em cena urbana.
    -- ================================================================
    local nOver = pure.world.getOvercast() or 0

    -- ---------- ESTRELAS ----------
    local eTipo  = math.floor(pure.script.ui.getValue("EstrelasTipo") or 2)
    local eMult  = pure.script.ui.getValue("EstrelasBrilho") or 1.0
    local eExpU  = pure.script.ui.getValue("EstrelasExpoente") or 0.0
    local eSat   = pure.script.ui.getValue("EstrelasSaturacao") or 1.0
    local eDia   = pure.script.ui.getValue("EstrelasDia") or false

    -- Visibilidade de dia: a referencia soma um termo de dia quando ligado
    local diaFator = eDia and (4 * mp_day + (1 - (pure.mod.twilight(0) or 0.5)))
                          or (1 - (pure.mod.twilight(0) or 0.5))

    local eBright, eExp
    if eTipo <= 1 then
        eBright, eExp = 10000, 7 + eExpU
        pure.stellar.setStarsBrightness(eBright * (eMult * 0.1) * diaFator)
    elseif eTipo <= 2 then
        eBright, eExp = 100000, 7 + eExpU
        pure.stellar.setStarsBrightness(eBright * eMult * diaFator)
    else
        eBright = math.clamp(pure.mod.nightCurve(100000, 0.5, 0.01), 0, 10000)
        eExp    = 2 + eExpU
        pure.stellar.setStarsBrightness(eBright * (eMult * 5) * diaFator)
    end
    ac.setSkyStarsExponent(eExp)
    ac.setSkyStarsSaturation(1.5 * eSat * mp_night)

    -- ---------- SOL, LUA, REFLEXO ----------
    ac.setSkySunMoonSizeMultiplier(pure.script.ui.getValue("SolLuaTamanho") or 1.5)
    if ac.setReflectedSkyTweaks then
        ac.setReflectedSkyTweaks(pure.script.ui.getValue("ReflexoCeu") or 1.0)
    end

    -- ---------- NLP ----------
    pure.config.set("nlp.level",          pure.script.ui.getValue("NlpNivel") or 0.5, true)
    pure.config.set("nlp.density",        pure.script.ui.getValue("NlpDensidade") or 0.5, true)
    pure.config.set("nlp.lowest_ambient", 3 * (pure.script.ui.getValue("NlpAmbienteMin") or 1.0), true)

    -- ---------- AMBIENTE AVANCADO ----------
    local ambU = pure.script.ui.getValue("AmbAvancado") or 1.0
    pure.config.set("light.advanced_ambient_light",
        math.clamp(pure.mod.dayCurve(1.5, 0.75, 0.8) - 0.1 * nOver, 0.2, 1.6) * ambU, true)
    pure.config.set("light.advanced_ambient_lightV2_skydomes",
        pure.mod.dayCurve(1, 1.15, 0.67) * (pure.script.ui.getValue("AmbSkydome") or 1.0), true)
    pure.config.set("light.advanced_ambient_lightV2_nlp",
        pure.script.ui.getValue("NlpAmbienteV2") or 1.0, true)
    pure.config.set("light.advanced_ambient_lightV2_fog",
        pure.script.ui.getValue("AmbFog") or 1.23, true)
    pure.config.set("light.advanced_ambient_light_vao_exp",
        pure.script.ui.getValue("AmbVaoExp") or 1.70, true)
    end)

    mp_sec("8c", function()
    -- ================================================================
    -- 8c. LUZ SOLAR, SOMBRAS E ADAPTACAO DE TUNEL (Bloco 16)
    --
    -- Mecanismo da referencia licenciada: light.sun.level nao e fixo, e
    -- dirigido pela variavel de clima sunmod2 e recebe dois somadores:
    --   overdrive -> dayCurve(1.1, 1.2, 0.2)
    --   tunel     -> lerp(forca, 0, oclusao)
    -- Ate aqui o nosso filtro registrava sunmod/sunmod2 e nunca lia nenhum
    -- dos dois: o nivel do sol ficava no default do Pure e o tunel escurecia
    -- sem compensacao alguma.
    --
    -- mp_occluded vem da secao 11 (um frame de atraso, irrelevante com lag).
    -- Convencao: 1 = ceu aberto, 0 = totalmente coberto.
    -- ================================================================
    if not CE.skip_world then
        if pure.script.ui.getValue("SolNivelAtivo") ~= false then
            local sunmod2 = pure.script.weather.getVariable("sunmod2") or 1
            local kSun    = pure.script.ui.getValue("SolNivelMult") or 1.0
            local base    = sunmod2 * 1.2 * kSun

            local over = 0
            if pure.script.ui.getValue("SolOverdrive") then
                over = pure.mod.dayCurve(1.1, 1.2, 0.2)
            end

            local tun = 0
            if math.floor(pure.script.ui.getValue("TunelAdaptacao") or 2) < 2 then
                local forca = pure.script.ui.getValue("TunelAdaptForca") or 25
                tun = math.lerp(forca, 0, math.saturateN(mp_occluded))
            end

            -- Com skydome de dia ligado o sol e zerado, do mesmo jeito que a
            -- secao 11 zera daylight_multiplier: o ceu nao pode competir.
            local nivel = pure.script.ui.getValue("CeuDeDia")
                and 0 or math.clamp(base + over + tun, 0, 10)
            pure.config.set("light.sun.level", nivel, true)
        end

        local kDay = pure.script.ui.getValue("LuzDiaMult") or 1.0
        if math.abs(kDay - 1.0) > 0.001 then
            pure.config.set("light.daylight_multiplier", kDay, true)
        end

        pure.config.set("stars.dynamic_adaption",
            pure.script.ui.getValue("EstrelasDinamicas") ~= false, true)
    end

    -- Sombras: ajuste de render, fora do gate de calibracao de cena.
    -- Memo para nao rechamar a API de resolucao todo frame.
    local resAlvo = pure.script.ui.getValue("SombrasOtimizadas") and 8192 or 0
    if resAlvo ~= mp_shadowRes then
        mp_shadowRes = resAlvo
        if resAlvo > 0 then
            ac.setShadowsResolution(8192)
        else
            ac.resetShadowsResolution()
        end
    end

    if pure.script.ui.getValue("SombrasNuvens") then
        ac.setCloudShadowScalingFactor(1)
        pure.config.set("clouds_render.shadows_blur",
            pure.script.ui.getValue("SombrasNuvensBlur") or 1.0, true)
    else
        ac.setCloudShadowScalingFactor(0)
    end

    pure.script.ui.setValue("OclusaoCam", mp_occluded)

    -- ================================================================
    end)
    mp_sec("9", function()
    -- 9. GODRAYS (skipped in Clone-Exato — INI prevalece)
    -- ================================================================
    if not CE.skip_godrays then
        local gr_spread   = pure.script.ui.getValue("GodraySpread") or 0.25
        local gr_int      = pure.script.ui.getValue("GodrayIntensity") or 1.25
        local gr_length   = pure.script.ui.getValue("GodrayLength") or 1.75
        local gr_glare    = pure.script.ui.getValue("GodrayGlare") or 1.25
        local gr_sunblind = pure.script.ui.getValue("SunblindingOn") or true
        local gr_angle    = pure.script.ui.getValue("GodrayAngleAtten") or 7.0

        ac.setGodraysLength(gr_int * gr_length)
        ac.setGodraysGlareRatio(gr_glare * 0.04)
        ac.setGodraysAngleAttenuation(gr_angle)
        ac.setGodraysNoiseMask(gr_spread)
        ac.setGodraysNoiseFrequency(0.8)
        ac.setGodraysDepthMapThreshold(0.99999)

        if gr_sunblind then
            local iris = pure.mod.dayCurve(0.1, 0.1, 0.3)
            pure.config.set("shaders.sunblinding.iris", iris, true)
            pure.config.set("shaders.sunblinding.star_style", 2, true)
            pure.config.set("shaders.sunblinding.star_blur", 0.1, true)
        else
            pure.config.set("shaders.sunblinding.iris", 0, true)
        end
    end

    -- ================================================================
    end)
    mp_sec("10", function()
    -- 10. EMISSIVES (skipped in Clone-Exato)
    -- ================================================================
    -- REMOVIDO (14.0): conclusao da reversao 13.7, que ficou pela metade.
    -- Os comentarios das linhas ~871 e ~1241 ja diziam "removido", mas as
    -- chamadas continuavam aqui e rodavam todo frame (skip_extras=false em
    -- todas as variantes) — era a camada que sufocava a iluminacao dos postes.
    -- A referencia nao chama nenhuma destas: csp_lights.bounce,
    -- csp_lights.emissive, ac.setGlowBrightness, ac.setEmissiveCameraGain.
    -- Iluminacao de emissivos volta ao default do Pure/CSP.

    -- ================================================================
    -- 10.5 SPEEDTUNNEL + MAGICBLOOM (13.6)
    -- ================================================================
    -- SpeedTunnel: blur radial por velocidade (SPICE built-in)
    local st_enabled = pure.script.ui.getValue("SpeedTunnelOn") or false
    if st_enabled then
        local st_int   = pure.script.ui.getValue("SpeedTunnelInt") or 0.5
        local st_thresh = pure.script.ui.getValue("SpeedTunnelThresh") or 80
        local speedFactor = math.clampN((mp_smooth_speed - st_thresh) / 100, 0, 1)
        local blur = speedFactor * st_int * 10
        pure.pp.set("spice.SpeedTunnel.active", true)
        pure.pp.set("spice.SpeedTunnel.strength", math.min(10, blur))
    else
        pure.pp.set("spice.SpeedTunnel.active", false)
    end

    -- MagicBloom: DESLIGADO por padrao (decisao: evitar bloom duplo com YEBIS)
    -- Se ativado: papel de "ambient glow" complementar, strength sutil
    local mb_enabled = pure.script.ui.getValue("MagicBloomOn") or false
    if mb_enabled then
        local mb_str = pure.script.ui.getValue("MagicBloomStr") or 0.3
        pure.pp.set("spice.MagicBloom.active", true)
        pure.pp.set("spice.MagicBloom.strength", mb_str)
        pure.pp.set("spice.MagicBloom.threshold", 0.5)
    else
        pure.pp.set("spice.MagicBloom.active", false)
    end

    -- ================================================================
    end)
    mp_sec("11", function()
    -- 11. SKYDOME
    -- ================================================================
    local sky_preset = pure.script.ui.getValue("SkydomePreset") or 1
    local sky_brilho = pure.script.ui.getValue("CeuBrilho") or 1.0
    local sky_rotacao = pure.script.ui.getValue("CeuRotacao") or 0.0
    local sky_altura = pure.script.ui.getValue("CeuAltura") or 1.0
    local sky_animar = pure.script.ui.getValue("CeuAnimar") or false
    local sky_velocidade = pure.script.ui.getValue("CeuVelocidade") or 0.5

    local sky_opac = pure.script.ui.getValue("CeuOpacidade") or 1.0
    local sky_opdia = pure.script.ui.getValue("CeuOpacDia") or 0.15

    -- BUG FIX (14.0): era "if not mp_cover then return end" — um return aqui
    -- abortava a update_pure_script INTEIRA, matando a secao 12 (Atmosfera/Fog)
    -- todo frame quando o cover nao existisse. Agora e so um guard de bloco.
    if mp_cover then
        mp_cover.shadowRadius = 100000
        mp_cover.shadowOpacityMultiplier = 0.00

        local sky_idx = 0
        if sky_preset == 1 then
            sky_idx = 0
        elseif sky_preset == 2 then
            local sky_n = pure.mod.dayCurve(1.0, 0.0, 1)
            local dd = pure.mod.duskdawn(0)
            local fw = pure.world.getFog() or 0
            local ow = pure.world.getOvercast and pure.world.getOvercast() or 0
            if sky_n > 0.7 and fw < 0.3 then sky_idx = 2
            elseif sky_n > 0.5 and fw < 0.5 then sky_idx = 4
            elseif dd > 0.3 then sky_idx = 3
            elseif sky_n < 0.3 and (fw > 0.3 or ow > 0.5) then sky_idx = 5
            else sky_idx = 0 end
        elseif sky_preset >= 3 and sky_preset <= 7 then
            sky_idx = sky_preset - 2
        end

        if sky_idx ~= mp_currentSkydome then
            if sky_idx > 0 and sky_idx <= #mp_skydomePaths then
                mp_cover:setTexture(mp_skydomePaths[sky_idx])
            else
                mp_cover:setTexture()
            end
            mp_currentSkydome = sky_idx
            ac.log("[MPIXELS] skydome preset=" .. tostring(sky_preset)
                .. " idx=" .. tostring(sky_idx)
                .. " tex=" .. tostring(mp_skydomePaths[sky_idx] or "nenhuma"))
        end

        if sky_idx > 0 and sky_idx <= #mp_skydomePaths then
            mp_cover.texRemapY = sky_altura
            if sky_animar then
                mp_cover.texOffsetX = (os.clock() / (50 / math.max(sky_velocidade, 0.01))) % 1
            else
                mp_cover.texOffsetX = sky_rotacao * 1.5
            end
            -- ========================================================
            -- BRILHO / CONTRASTE / OPACIDADE (Bloco 14 — da referencia)
            -- Cada textura tem seu proprio par brilho/expoente porque foram
            -- autoradas com exposicoes diferentes.
            -- ========================================================
            local sbt = { 8, 10, 7, 7, 10 }            -- brilho por textura
            local set = { 2.0, 1.2, 1.25, 3.2, 1.0 }   -- expoente por textura

            local duskdawn = pure.mod.duskdawn(0) or 0
            local noPorSol = pure.script.ui.getValue("CeuNoPorSol")
            if noPorSol == nil then noPorSol = true end
            -- Reforco no crepusculo: e quando o ceu tem mais desenho
            local opacPorSol = (noPorSol and duskdawn > 0.1) and 1 or 0

            local ceuDeDia = pure.script.ui.getValue("CeuDeDia") or false
            local ceuContr = pure.script.ui.getValue("CeuContraste") or 1.0

            local brilho = sky_brilho * (sbt[sky_idx] or 8)
            if duskdawn > 0.1 then
                brilho = brilho + opacPorSol * pure.mod.dayCurve(1, 10, 0.1)
            end
            local expo = (set[sky_idx] or 1.5) * ceuContr

            mp_cover.colorMultiplier = rgb(brilho, brilho, brilho)
            mp_cover.colorExponent   = rgb(expo, expo, expo)

            -- Opacidade: noite cheia, dia so com o toggle, crepusculo +50%.
            -- Com ceu de dia ligado a referencia zera o multiplicador de luz
            -- do dia, para o skydome nao competir com o sol.
            local opacDia = ceuDeDia and 1 or (sky_opdia or 0.15)
            mp_cover.opacityMultiplier = sky_opac
                * (1.0 * mp_night + opacDia * mp_day + opacPorSol * 0.5)
            if ceuDeDia then
                pure.config.set("light.daylight_multiplier", 0, true)
            end
        else
            mp_cover.opacityMultiplier = 0.0
        end
    end

    -- ================================================================
    end)
    mp_sec("12", function()
    -- 12. ATMOSFERA / FOG (Bloco 4 — portado da referencia licenciada)
    -- ================================================================
    -- Arquitetura MULTIPLICATIVA: le a tabela de fog que o Pure ja calculou
    -- (getPureGammaFogTable) e a cor que o Pure ja resolveu (light.getFog),
    -- e escala por cima. Nunca valor absoluto — foi o que gerou o cast
    -- marrom nas tentativas anteriores.
    -- A reducao de intensidade noturna (0.6) e o que mata o ambar da
    -- distancia em cena urbana.
    -- ================================================================
    local fogSistema = math.floor(pure.script.ui.getValue("FogSistema") or 1)

    if not D.skip_extras and fogSistema <= 1 then
        local u_dens = pure.script.ui.getValue("FogDensidade") or 1.0
        local u_dist = pure.script.ui.getValue("FogDistancia") or 1.0
        local u_atmo = pure.script.ui.getValue("FogAtmosfera") or 1.0
        local u_back = pure.script.ui.getValue("FogBacklit") or 1.0
        local u_noit = pure.script.ui.getValue("FogNoiteMult") or 0.60
        local u_sat  = pure.script.ui.getValue("FogSaturacao") or 1.0

        -- Angulo solar aproximado (-5 a 60) para indexar as LUTs
        local sunCurve = pure.mod.dayCurve(1, 0, 0.67) or 0.5
        local sunAng   = -5 + (sunCurve * 65)

        local L_dens = mp_fogLUT(MP_FOG.densidade, sunAng)
        local L_dist = mp_fogLUT(MP_FOG.distancia, sunAng)
        local L_blen = mp_fogLUT(MP_FOG.blend,     sunAng)
        local L_expo = mp_fogLUT(MP_FOG.expoente,  sunAng)
        local L_back = mp_fogLUT(MP_FOG.contraluz, sunAng)
        local L_sat  = mp_fogLUT(MP_FOG.saturacao, sunAng)

        -- Tunel reduz o fog (a referencia usa 0.3..1.0 por oclusao)
        local tunBright = math.clampN((mp_smooth_occlusion or 1) / 0.97, 0, 1)
        local tunFog    = math.lerp(0.3, 1.0, tunBright)

        local fDens = L_dens * (u_dens * 5) * tunFog
        local fDist = L_dist * (u_dist * 5)
        local fBlen = L_blen
        local fExpo = L_expo
        local fBack = L_back * u_back
        local fSat  = L_sat  * u_sat

        -- Base do Pure, com fallback se a tabela vier invalida
        local T = pure.world.getPureGammaFogTable()
        if not T or not T.density or not T.distance or not T.blend or not T.height then
            T = { density = 1, distance = 1, blend = 1, height = 1 }
        end

        local fogW = pure.world.getFog() or 0

        ac.setFogDensity(T.density * fDens * 3.7)
        ac.setFogDistance((T.distance * 4.5 / math.max(fDist * 0.4, 0.01) * 1.25) + 2 * fogW)
        ac.setFogBlend(T.blend * fBlen * 1.5)
        ac.setFogExponent(math.max(fExpo * 1.6, 0.45))
        ac.setFogHeight(T.height)

        -- COR: a que o Pure calculou, atenuada a noite.
        local corPure = pure.light.getFog()
        if corPure then
            local k = (1 - mp_night) + mp_night * u_noit
            ac.setFogColor(rgb(corPure.r * k * fSat, corPure.g * k * fSat, corPure.b * k * fSat))
        end

        -- Contraluz: dia e noite com pesos proprios
        local diaF   = pure.mod.twilight(0) or 0.5
        local backMix = (0.65 * diaF) + (0.75 * (1 - diaF))
        ac.setFogBacklitMultiplier(backMix * fBack * 0.25)
        local backExp = math.clampN((pure.world.getMist and pure.world.getMist() or 0) / 0.06, 0, 1)
        ac.setFogBacklitExponent(math.lerp(1.78, 5, backExp))

        ac.setFogAtmosphere(0.15 * u_atmo)

        -- Horizonte e ceu com multiplicadores separados
        ac.setHorizonFogMultiplier(0.705, 1, 1)
        if T.sky then
            ac.setSkyFogMultiplier(T.sky * (pure.mod.dayCurve(1.4, 2.0, 1.0) or 1.4))
        end

    elseif not D.skip_extras then
        -- ============================================================
        -- 12b. FOG LEGADO (Bloco 17)
        --
        -- Os tres perfis fechados da referencia. Nao sao um "fallback":
        -- sao curvas de fog com caracter proprio, escritas com valores
        -- absolutos (o dinamico e multiplicativo sobre o Pure). Rodam no
        -- lugar do dinamico, nunca junto — sobrescrever um com o outro
        -- e o que produzia o cast marrom nas tentativas antigas.
        --
        -- Divergencias deliberadas em relacao a referencia:
        --   1. ac.setFogDistance recebe 1 argumento (assinatura do SDK).
        --      A referencia passa 3 nos perfis 2 e 3; o 2o e o 3o sao
        --      descartados pelo Lua e nunca fizeram nada.
        --   2. A referencia chama setFogHeight duas vezes nos perfis 2 e 3
        --      (1120/1913 e depois 1120/1213). So a segunda vale. Aqui so
        --      a segunda existe.
        --   3. A referencia le ac.getSim().rainIntensity no perfil 4.
        --      Esse e exatamente o acesso que matou o update inteiro da
        --      13.4 pra baixo. Usamos pure.world.getRainFX_Intensity().
        --   4. A cor do fog vem de pure.light.getFog() e o ambiente de
        --      pure.light.getAmbient(), ambos do SDK publico, no lugar do
        --      __PURE__world__fog_get() interno.
        -- ============================================================
        local uAmount = pure.script.ui.getValue("FogQuantidade") or 0.025
        local uThick  = pure.script.ui.getValue("FogEspessura") or 0.005
        local uMixer  = pure.script.ui.getValue("FogMisturaCor") or 0.5
        local uDistL  = pure.script.ui.getValue("FogDistLegacy") or 0.0
        local uBackL  = pure.script.ui.getValue("FogContraluzLeg") or 1.0
        local uSatL   = pure.script.ui.getValue("FogSaturacao") or 1.0

        local d, n = mp_day, mp_night
        local fogW  = pure.world.getFog() or 0
        local hum   = pure.world.getHumidity() or 0
        local smog  = (pure.world.getSmog and pure.world.getSmog()) or 0
        local T     = pure.world.getPureGammaFogTable() or {}
        local Tdens = T.density or 1

        -- Espessura: peso diferente de dia e de noite, depois cortada 85%
        -- a noite e realimentada pela cobertura de nuvens.
        local esp = (uThick * 0.75 * d) + (uThick * 1.14 * n)
        esp = (esp - esp * 0.85 * n) + (0.25 * esp) * (pure.world.getCloudCoverage() or 0)

        local daycurvefog = pure.mod.dayCurve(1.0, 1.06, 0.6)
        local mixermult   = uMixer * pure.mod.dayCurve(2, 1, 1)
        local colorblend  = pure.mod.dayCurve(
            mixermult * d + mixermult * n - 1.2,
            mixermult * d + mixermult * 2 * n, 0.67)

        -- Cor de referencia do fog: a do Pure, com o realce de valor por
        -- clima ruim (equivalente ao hsv.v * (1 + 8*badness) da referencia)
        -- e saturacao ajustada em torno da propria luminancia.
        local cf   = pure.light.getFog() or rgb(1, 1, 1)
        local vB   = 1 + 8 * (mp_smooth_badness or 0)
        local lumF = (cf.r + cf.g + cf.b) / 3
        local corFog = rgb((lumF + (cf.r - lumF) * uSatL) * vB,
                           (lumF + (cf.g - lumF) * uSatL) * vB,
                           (lumF + (cf.b - lumF) * uSatL) * vB)

        local amb = pure.light.getAmbient() or rgb(1, 1, 1)
        local corCeu = rgb(amb.r * 0.65, amb.g * 0.65, amb.b * 0.65)

        ac.setHorizonFogMultiplier(0.705, 1, 1)

        if fogSistema == 2 or fogSistema == 3 then
            -- Imersivo (2) e Realista (3) sao a mesma curva; mudam a
            -- dayCurve da densidade e o peso da densidade do Pure no blend.
            local kDens  = (fogSistema == 2) and 2 or 1
            local kBlend = (fogSistema == 2) and 0.8 or 1.5

            ac.setFogDensity(pure.mod.dayCurve(kDens, kDens, 0.07)
                * (500 * (uAmount + fogW)))
            ac.setFogBacklitMultiplier(pure.mod.dayCurve(0.20, 0.04, 0.67) * uBackL)
            ac.setFogColor(mp_fogMix(corCeu, corFog, colorblend, daycurvefog))
            ac.setFogBlend(25.502 * esp + Tdens * kBlend)
            ac.setFogExponent(0.7510)
            ac.setFogHeight(pure.mod.dayCurve(1120, 1213, 0.67))
            ac.setFogDistance(550000 * (uDistL + 0.6))

        elseif fogSistema >= 4 then
            -- Denso: o unico perfil legado que responde a umidade, chuva,
            -- smog e ao ajuste de forma de fog da pista.
            local rainI = (pure.world.getRainFX_Intensity
                and pure.world.getRainFX_Intensity()) or 0
            local overc = (pure.script.weather.getVariable("Overcastcontrast")) or 0

            ac.setFogDensity(pure.mod.dayCurve(3 - fogW, 3 - fogW, 0.07)
                * (400 * (uAmount - 0.025 + fogW * 0.05 + overc * 0.01))
                + smog * 0.1)
            ac.setFogHeight(pure.mod.dayCurve(1120, 1913, 0.67) * 0.001)
            ac.setFogColor(mp_fogMix(corCeu, corFog,
                colorblend - fogW + pure.mod.dayCurve(1, 0.1, 0.65), daycurvefog))
            ac.setFogBlend(esp * 500
                * math.clamp(0.6 + fogW + 0.2 * hum, 0.05, 1.0)
                + 1.1 * fogW)
            ac.setFogExponent(math.clamp(1.2 - 0.4 * hum - 0.3 * fogW, 0.7, 1.3))

            -- Ajuste de forma de fog da pista: global interno do Pure, fora
            -- do SDK publico. rawget evita quebrar se a build nao expuser.
            local fnShape = rawget(_G, "PURE__getTrackAdjustment_FOG_SHAPE")
            local fShape  = (fnShape and fnShape()) or 0

            ac.setFogDistance(math.clamp(
                6 * math.lerp(70000, 25000,
                    math.saturateN(hum * 0.8 + rainI * 0.5))
                / (1 + fShape / 10)
                * (0.1 + uDistL + 0.4 * fogW), 6000, 100000))
            ac.setFogBacklitMultiplier(pure.mod.dayCurve(0.20, 0.04, 0.67)
                * (0.6 + 0.4 * hum + 0.3 * fogW))
        end
    end

    -- Sombras falsas do clima (Bloco 17) — valem para qualquer sistema.
    -- A referencia passa 3 argumentos em setWeatherFakeShadowConcentration;
    -- o SDK declara 1. Os dois extras sao descartados pelo Lua.
    if not D.skip_extras then
        ac.setWeatherFakeShadowOpacity(
            pure.mod.dayCurve(0.965, 0.65, 0.65)
            * (pure.script.ui.getValue("SombraFalsaOpac") or 1.0))
        ac.setWeatherFakeShadowConcentration(0.6)
    end

    end)

    -- Health check: prova de que o update chega ao FIM.
    -- Fica FORA do pcall de proposito — tem que disparar mesmo com secao quebrada.
    if mp_frameCount % 120 == 0 then
        local mortas = ""
        for nome, _ in pairs(mp_secErr) do mortas = mortas .. nome .. " " end
        if mortas == "" then
            ac.log("[MPIXELS] update FIM ok | frame=" .. tostring(mp_frameCount))
        else
            ac.log("[MPIXELS] update FIM ok | frame=" .. tostring(mp_frameCount)
                .. " | SECOES MORTAS: " .. mortas)
        end
    end
end

-- ============================================================================
-- GLAREFUNC — perfil "eyelike" (semeadura seção 4 + checklist playbook Parte 0)
--
-- GEOMETRIA (constante — propriedade da lente):
--   shape=7, levels=16, rangeScale=4, streaks=8, incAngle=3.99
-- INTENSIDADE (varia dia/noite):
--   glareLuminance, glareThreshold, starLuminance
--
-- Checklist arco-íris (todos enforced):
--   1. starDispersion = 0 ← CRITICO
--   2. starForceDispersion = false ← CRITICO
--   3. bloomDispersionBaseLevel = 10 (de 16)
--   4. ghost/ghostActive = false
--   5. ghostLuminance = 0
--   6. threshold efetivo 8-13 (dia ~8.8, noite ~11)
--   7. afterimageLuminance = 0
--   8. Floors math.max(x, 0.01) em todos os thresholds
-- ============================================================================
function Glarefunc(yebis)
    local nightness = pure.mod.dayCurve(1.0, 0.0, 1)

    -- Fator de interior: threshold MAIOR no cockpit (AE levanta em interior)
    local GlareThresF = ac.isInteriorView() and 1.2 or 1

    -- GEOMETRIA (constante)
    yebis.glareShape                        = 7
    yebis.glareQuality                      = 5
    yebis.glarePrecision                    = 0
    yebis.glareBrightPass                   = 0
    yebis.glareAnamorphic                   = (_mp_anamorph or 1) > 1
    yebis.glareUseCustomShape               = true
    yebis.glareAfterImage                   = false
    yebis.glareBloomLevels                  = 16
    yebis.glareGenerationRangeScale         = 4
    yebis.glareStarLengthFOVDependence      = 0
    yebis.glareShapeStarStreaks             = (_mp_glare and _mp_glare.streaks) or 8
    yebis.glareShapeStarInclinationAngle   = 3.99
    yebis.glareShapeStarRotation           = true
    yebis.glareShapeStarSecondaryLength    = 0
    yebis.glareShapeBloomDispersion        = 0.2
    yebis.glareShapeBloomDispersionBaseLevel = 10   -- checklist #3

    -- CHECKLIST ARCO-IRIS — mantido, mas agora com chave (Bloco 6)
    local g = _mp_glare
    local antiRB = (g == nil) or g.antiRB
    if antiRB then
        yebis.glareShapeStarDispersion       = 0      -- checklist #1 CRITICO
        yebis.glareShapeStarForceDispersion  = false  -- checklist #2 CRITICO
        yebis.glareGhost                     = false  -- checklist #4
        yebis.glareShapeGhostLuminance       = 0      -- checklist #5
        yebis.glareShapeGhostHaloLuminance   = 0
        yebis.glareShapeGhostDistortion      = 0
        yebis.glareShapeGhostSharpeness      = false
        yebis.glareShapeAfterimageLuminance  = 0      -- checklist #7
        yebis.glareShapeAfterimageLength     = 0
    else
        -- Perfil da referencia sem trava: ghost e halo passam a existir.
        yebis.glareShapeStarDispersion       = 0
        yebis.glareShapeStarForceDispersion  = false
        yebis.glareGhost                     = (g.ghost > 0.001)
        yebis.glareShapeGhostLuminance       = g.ghost * 1.5
        yebis.glareShapeGhostHaloLuminance   = g.halo * 1.5
        yebis.glareShapeGhostDistortion      = g.distort
        yebis.glareShapeGhostSharpeness      = g.sharp > 0.001
        yebis.glareShapeAfterimageLuminance  = 0
        yebis.glareShapeAfterimageLength     = 0.110
    end
    yebis.glareGhostConcentricDistortion   = 0.64

    -- INTENSIDADE — perfil de glare da referencia (Bloco 6) tem prioridade;
    -- se ausente, cai no caminho antigo baseado em _mp_bloom.
    if g then
        yebis.glareLuminance                = g.lum
        yebis.glareShapeLuminance           = g.bloomLum * 2
        yebis.glareShapeBloomLuminance      = g.bloomLum * (_mp_anamorph or 1)
        yebis.glareBloomLuminanceGamma      = g.gamma
        yebis.glareShapeBloomDispersion     = g.disp
        yebis.glareBloomGaussianRadiusScale = g.gaussR
        yebis.glareStarSoftness             = g.starSoft
        yebis.glareShapeStarLuminance       = g.starLum
        yebis.glareShapeStarLength          = g.starLen
        yebis.glareShapeStarSecondaryLength = g.starLen2
        yebis.glareBloomFilterThreshold     = 0.001
        yebis.glareStarFilterThreshold      = 0.0001
        yebis.glareThreshold                = math.max(g.thresh * GlareThresF, 0.01)
        return
    end

    local b = _mp_bloom
    if b then
        -- Luminancias com multiplicadores do UI
        yebis.glareLuminance                = b.glareLum * 0.625   -- base × multiplier
        yebis.glareShapeLuminance           = b.bloomLum * 1.0     -- shape luminance
        yebis.glareShapeBloomLuminance      = b.bloomLum * 0.5     -- bloom luminance
        yebis.glareBloomLuminanceGamma      = b.bloomGamma * 1.0
        yebis.glareBloomGaussianRadiusScale = 2
        yebis.glareBloomFilterThreshold     = math.max(0.001, 0.01)  -- floor #8
        yebis.glareStarFilterThreshold      = math.max(0.0001, 0.01) -- floor #8
        yebis.glareStarSoftness             = 0

        -- Stars
        yebis.glareShapeStarLuminance       = b.starLum * 28.029  -- semeadura: 28.029 com threshold seletivo
        yebis.glareShapeStarLength          = b.starLength * 0.03 / 0.15  -- escalar do slider (0.15 default) pro semeadura (0.03)

        -- Threshold: dia ~8.8, noite ~11, interior ×1.2 — checklist #6 + floor #8
        local threshBase = pure.mod.dayCurve(11 * b.threshold, 8.8 * b.threshold, 1)
        yebis.glareThreshold                = math.max(threshBase * GlareThresF, 0.01)  -- floor #8
    else
        -- Fallback se _mp_bloom nil (skip_extras=true): threshold alto, lum baixo
        yebis.glareLuminance                = 0.625
        yebis.glareShapeLuminance           = 1
        yebis.glareShapeBloomLuminance      = 0.5
        yebis.glareBloomLuminanceGamma      = 1
        yebis.glareBloomGaussianRadiusScale = 2
        yebis.glareBloomFilterThreshold     = 0.001
        yebis.glareStarFilterThreshold      = 0.0001
        yebis.glareStarSoftness             = 0
        yebis.glareShapeStarLuminance       = 28.029
        yebis.glareShapeStarLength          = 0.03
        yebis.glareThreshold                = math.max(8.8 * GlareThresF, 0.01)
    end
end
