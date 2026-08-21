-- ============================================================================
-- MRACHADORES MALDITOS PIXELS — SPICE HDR Loader v1.0 (Fase 12.14)
--
-- Pixels FX: Luma Sharpening + Color Engine ON, resto OFF
-- + MALDITOS PIXELS extras: Purkinje + Vignette
-- Defaults per-variant (grain/vig only)
-- ============================================================================

-- Detect variant for FX defaults
local _mp_fx_variant = "Rachadores"
do
    local fn = ac.getPpFilter() or ""
    fn = fn:gsub("%.[Ii][Nn][Ii]$", "")          -- alguns builds retornam com .ini
    local m = fn:match("^Malditos Pixels%s+(%a+)$")
    _mp_fx_variant = m or "Rachadores"
end

-- FX defaults por variante (12.26 — recalculados a partir do Core)
-- Core: sharpening+color engine ON, resto OFF (Pixels spec)
-- Variantes: grain/vignette ajustados pela intencao
-- BUG FIX (Bloco 7): a tabela usava os nomes antigos (Core/Cine/Natural/
-- Vivid/Night). Depois do rename as variantes viraram Rachadores/Cinema/
-- Puro/Vivo/Madrugada — nenhuma batia, e TODAS caiam no fallback.
local _fx_defaults = {
    Rachadores = { vig_on=false, vig_str=0.30, grain_on=false, grain_amt=1.0 },
    Cinema     = { vig_on=true,  vig_str=0.40, grain_on=true,  grain_amt=1.2 },
    Puro       = { vig_on=false, vig_str=0.00, grain_on=false, grain_amt=0.5 },
    Vivo       = { vig_on=false, vig_str=0.25, grain_on=false, grain_amt=0.8 },
    Madrugada  = { vig_on=true,  vig_str=0.35, grain_on=true,  grain_amt=1.0 },
}
local _fd = _fx_defaults[_mp_fx_variant] or _fx_defaults.Rachadores

pure.pp.spice.addHDRFilter(
    "MPIXELS_FX",
    pure.pp.spice.getGlobalHdrEffectsFolder() .. "/MPIXELS_FX/MPIXELS_FX_effect.lua",
    nil
)

-- ============================================================================
-- Header
-- ============================================================================
pure.pp.spice.addText("MPIXELS_FX", "MALDITOS PIXELS — FX")
pure.pp.spice.addText("MPIXELS_FX", "v1.0 | " .. _mp_fx_variant)
pure.pp.spice.addSeparator("MPIXELS_FX")

-- ============================================================================
-- Luma Sharpening (ON by default — Pixels spec)
-- ============================================================================
pure.pp.spice.addText("MPIXELS_FX", "Luma Sharpening")
pure.pp.spice.addCheckbox("MPIXELS_FX", "SharpEnabled", true, "Ativar Sharpening")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "SharpIntensity", 2.5, 0.0, 5.0, "Intensity")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "SharpRadius", 1.0, 0.5, 3.0, "Radius")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "SharpThreshold", 0.0, 0.0, 0.5, "Threshold")
pure.pp.spice.addSeparator("MPIXELS_FX")

-- ============================================================================
-- Unified Color Engine (ON by default — Pixels spec)
-- ============================================================================
pure.pp.spice.addText("MPIXELS_FX", "Unified Color Engine")
pure.pp.spice.addCheckbox("MPIXELS_FX", "ColorEnabled", true, "Ativar Color Engine")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "Vibrance", 0.25, -1.0, 1.0, "Master Vibrance")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "MidtoneGamma", 1.0, 0.5, 2.0, "Midtone Gamma")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "WhitePoint", 1.0, 0.5, 2.0, "White Point")
pure.pp.spice.addSeparator("MPIXELS_FX")

-- ============================================================================
-- Clarity (OFF by default)
-- ============================================================================
pure.pp.spice.addText("MPIXELS_FX", "Clarity")
pure.pp.spice.addCheckbox("MPIXELS_FX", "ClarityEnabled", false, "Ativar Clarity")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "ClarityIntensity", 0.125, 0.0, 1.0, "Intensity")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "ClarityRadius", 5.0, 1.0, 10.0, "Radius")
pure.pp.spice.addSeparator("MPIXELS_FX")

-- ============================================================================
-- Chromatic Aberration (OFF by default)
-- ============================================================================
pure.pp.spice.addText("MPIXELS_FX", "Chromatic Aberration")
pure.pp.spice.addCheckbox("MPIXELS_FX", "ChromaEnabled", false, "Ativar CA")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "ChromaUniformX", 0.5, 0.0, 2.0, "Uniform X")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "ChromaUniformY", 0.5, 0.0, 2.0, "Uniform Y")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "ChromaLateralX", 0.5, 0.0, 2.0, "Lateral X")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "ChromaLateralY", 0.5, 0.0, 2.0, "Lateral Y")
pure.pp.spice.addSeparator("MPIXELS_FX")

-- ============================================================================
-- Film Grain (OFF by default)
-- ============================================================================
pure.pp.spice.addText("MPIXELS_FX", "Film Grain")
pure.pp.spice.addCheckbox("MPIXELS_FX", "GrainEnabled", _fd.grain_on, "Ativar Grain")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "GrainAmount", _fd.grain_amt, 0.0, 5.0, "Amount")
pure.pp.spice.addSeparator("MPIXELS_FX")

-- ============================================================================
-- GoPro Lens Distortion (OFF by default)
-- ============================================================================
pure.pp.spice.addText("MPIXELS_FX", "GoPro Lens Distortion")
pure.pp.spice.addText("MPIXELS_FX", "Distorcao de lente do INI (YEBIS) fica DESLIGADA.")
pure.pp.spice.addText("MPIXELS_FX", "Esta aqui e a nossa, ligavel em jogo.")
pure.pp.spice.addCheckbox("MPIXELS_FX", "LensDistEnabled", false, "Ativar distorcao de lente")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "LensDistStrength", 0.5, 0.0, 2.0, "Intensidade")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "LensDistZoom", 1.25, 0.5, 2.0, "Zoom compensatorio")
pure.pp.spice.addSeparator("MPIXELS_FX")

-- ============================================================================
-- Dashcam VHS (OFF by default)
-- ============================================================================
pure.pp.spice.addText("MPIXELS_FX", "Dashcam VHS")
pure.pp.spice.addCheckbox("MPIXELS_FX", "VhsEnabled", false, "Ativar VHS (simples)")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "VhsJitter", 0.35, 0.0, 1.0, "Jitter")

pure.pp.spice.addSeparator("MPIXELS_FX")
pure.pp.spice.addText("MPIXELS_FX", "VHS completo (Bloco 15)")
pure.pp.spice.addCheckbox("MPIXELS_FX", "VhsMaster", false, "Ativar VHS completo")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "VhsCurvature", 0.0, 0.0, 1.0, "Curvatura de tela")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "VhsScanline", 0.25, 0.0, 1.0, "Linha de varredura")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "VhsChromaSep", 0.30, 0.0, 1.0, "Separacao de croma")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "VhsChromaSmear", 0.50, 0.0, 1.0, "Arraste de croma")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "VhsRandomLines", 0.30, 0.0, 1.0, "Linhas aleatorias")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "VhsHGlitch", 0.30, 0.0, 1.0, "Glitch horizontal")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "VhsGrain", 0.015, 0.0, 0.10, "Grain de fita")

pure.pp.spice.addSeparator("MPIXELS_FX")
pure.pp.spice.addText("MPIXELS_FX", "Glitch digital")
pure.pp.spice.addCheckbox("MPIXELS_FX", "GlitchMaster", false, "Ativar glitch")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "GlitchRate", 0.50, 0.0, 1.0, "Frequencia")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "GlitchRGB", 0.30, 0.0, 1.0, "Deslocamento RGB")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "GlitchBlock", 0.02, 0.005, 0.20, "Tamanho do bloco")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "GlitchDistort", 0.10, 0.0, 0.5, "Distorcao")
pure.pp.spice.addSeparator("MPIXELS_FX")

-- ============================================================================
-- Vignette (MALDITOS PIXELS extra — per-variant default)
-- ============================================================================
pure.pp.spice.addText("MPIXELS_FX", "Vignette")
pure.pp.spice.addCheckbox("MPIXELS_FX", "VignetteEnabled", _fd.vig_on, "Ativar Vinheta")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "VignetteStrength", _fd.vig_str, 0.0, 1.0, "Intensidade")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "VignetteFalloff", 2.5, 1.5, 5.0, "Suavidade")
pure.pp.spice.addSeparator("MPIXELS_FX")

-- ============================================================================
-- Black Bars (OFF by default)
-- ============================================================================
pure.pp.spice.addText("MPIXELS_FX", "Black Bars")
pure.pp.spice.addCheckbox("MPIXELS_FX", "BlackBarsEnabled", false, "Ativar Black Bars")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "BlackBarsStyle", 0, 0, 1, "Style (0=Cinematic, 1=Subtle)")
pure.pp.spice.addSeparator("MPIXELS_FX")

-- ============================================================================
-- Halation (13.6 — assinatura exclusiva)
-- ============================================================================
pure.pp.spice.addText("MPIXELS_FX", "Halation (sangramento filmico)")
pure.pp.spice.addCheckbox("MPIXELS_FX", "HalationEnabled", false, "Ativar Halation")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "HalationIntensity", 0.15, 0.0, 0.5, "Intensidade")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "HalationRadius", 3.0, 1.0, 8.0, "Raio")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "HalationWarmth", 0.7, 0.0, 1.0, "Calor (tint)")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "HalationThreshold", 0.8, 0.3, 1.5, "Limiar de brilho")
pure.pp.spice.addSeparator("MPIXELS_FX")

-- ============================================================================
-- Depth Sharpening (13.6)
-- ============================================================================
pure.pp.spice.addText("MPIXELS_FX", "Depth Sharpening")
pure.pp.spice.addCheckbox("MPIXELS_FX", "DepthSharpEnabled", true, "Mascara por profundidade (sem halo no ceu)")
pure.pp.spice.addSeparator("MPIXELS_FX")

-- ============================================================================
-- Purkinje (driven by PPFilter script — display only here)
-- ============================================================================
pure.pp.spice.addText("MPIXELS_FX", "Purkinje (Visao Noturna — auto via script)")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "PurkinjeGlobalDrive", 0, 0.0, 1.5, "Drive Global")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "PurkinjeIntensity", 0.15, 0.0, 0.40, "Intensidade")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "PurkinjeThreshold", 0.12, 0.05, 0.30, "Limiar")
pure.pp.spice.addSeparator("MPIXELS_FX")

-- ============================================================================
-- Lens Flare, Lens Dirt e Velocidade (Bloco 7)
-- ============================================================================
pure.pp.spice.addSeparator("MPIXELS_FX")
pure.pp.spice.addText("MPIXELS_FX", "Lens Flare")
pure.pp.spice.addCheckbox("MPIXELS_FX", "FlareEnabled", false, "Ativar flare")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "FlareIntensity", 0.35, 0.0, 2.0, "Intensidade")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "FlareThreshold", 0.85, 0.0, 1.0, "Limiar de brilho")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "FlareMix", 0.5, 0.0, 1.0, "Mistura das camadas")

pure.pp.spice.addSeparator("MPIXELS_FX")
pure.pp.spice.addText("MPIXELS_FX", "Sujeira de Lente")
pure.pp.spice.addText("MPIXELS_FX", "So aparece contra highlight, como lente real.")
pure.pp.spice.addCheckbox("MPIXELS_FX", "DirtEnabled", false, "Ativar sujeira")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "DirtIntensity", 0.30, 0.0, 1.5, "Intensidade")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "DirtThreshold", 0.75, 0.0, 1.0, "Limiar de brilho")

pure.pp.spice.addSeparator("MPIXELS_FX")
pure.pp.spice.addText("MPIXELS_FX", "Velocidade")
pure.pp.spice.addText("MPIXELS_FX", "Zoom e trepidacao, sem borrao.")
pure.pp.spice.addCheckbox("MPIXELS_FX", "SpeedFXEnabled", false, "Ativar")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "SpeedZoom", 0.02, 0.0, 0.15, "Zoom maximo")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "SpeedShake", 0.0005, 0.0, 0.004, "Trepidacao")
pure.pp.spice.addSliderFloat("MPIXELS_FX", "SpeedThreshold", 80, 0, 200, "Limiar (km/h)")
