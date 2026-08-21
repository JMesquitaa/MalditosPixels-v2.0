-- ============================================================================
-- MALDITOS PIXELS — SPICE LDR (Bloco 8)
--
-- Camada LDR: roda DEPOIS do tonemap, em espaco 0..1.
-- E o lugar correto para grain, vinheta e aberracao cromatica — no HDR eles
-- se comportam de forma imprevisivel porque o range nao esta normalizado.
--
-- Tudo nasce DESLIGADO. Se voce ligar o equivalente aqui, desligue o do HDR:
-- os dois somam.
-- ============================================================================

local _mp_ldr_variant = "Rachadores"
do
    local fn = ac.getPpFilter() or ""
    fn = fn:gsub("%.[Ii][Nn][Ii]$", "")
    local m = fn:match("^Malditos Pixels%s+(%a+)$")
    _mp_ldr_variant = m or "Rachadores"
end

pure.pp.spice.addLDRFilter(
    "MPIXELS_LDR",
    pure.pp.spice.getGlobalLdrEffectsFolder() .. "/MPIXELS_FX_LDR/MPIXELS_FX_LDR_effect.lua"
)

pure.pp.spice.addText("MPIXELS_LDR", "MALDITOS PIXELS — LDR")
pure.pp.spice.addText("MPIXELS_LDR", "v1.0 | " .. _mp_ldr_variant)
pure.pp.spice.addText("MPIXELS_LDR", "Pos-tonemap. Nao ligue junto com o equivalente no HDR.")
pure.pp.spice.addSeparator("MPIXELS_LDR")

-- ---------------------------------------------------------------------------
-- Film Grain — procedural HASH12, monocromatico, mascarado por luminancia.
-- Escalado no shader para nao "ferver" com DLSS/FSR.
-- ---------------------------------------------------------------------------
pure.pp.spice.addText("MPIXELS_LDR", "Film Grain")
pure.pp.spice.addCheckbox("MPIXELS_LDR", "GrainEnabled", false, "Ativar grain")
pure.pp.spice.addSliderFloat("MPIXELS_LDR", "GrainIntensity", 0.030, 0.0, 0.15, "Intensidade")
pure.pp.spice.addSliderFloat("MPIXELS_LDR", "GrainSize", 1.0, 0.5, 3.0, "Tamanho")
pure.pp.spice.addSliderFloat("MPIXELS_LDR", "GrainShadowLift", 0.12, 0.0, 0.5, "Piso de sombra")
pure.pp.spice.addSliderFloat("MPIXELS_LDR", "GrainHighlightCut", 0.85, 0.3, 1.0, "Corte de highlight")
pure.pp.spice.addSeparator("MPIXELS_LDR")

-- ---------------------------------------------------------------------------
-- Vinheta
-- ---------------------------------------------------------------------------
pure.pp.spice.addText("MPIXELS_LDR", "Vinheta")
pure.pp.spice.addCheckbox("MPIXELS_LDR", "VigEnabled", false, "Ativar vinheta")
pure.pp.spice.addSliderFloat("MPIXELS_LDR", "VigStrength", 0.30, 0.0, 1.0, "Intensidade")
pure.pp.spice.addSliderFloat("MPIXELS_LDR", "VigFalloff", 2.5, 0.5, 6.0, "Suavidade")
pure.pp.spice.addSliderFloat("MPIXELS_LDR", "VigRoundness", 1.0, 0.0, 2.0, "Circularidade")
pure.pp.spice.addSeparator("MPIXELS_LDR")

-- ---------------------------------------------------------------------------
-- Aberracao cromatica — deslocamento radial com falloff.
-- Centro fica limpo; a dispersao cresce em direcao a borda, como lente real.
-- ---------------------------------------------------------------------------
pure.pp.spice.addText("MPIXELS_LDR", "Aberracao Cromatica")
pure.pp.spice.addCheckbox("MPIXELS_LDR", "CaEnabled", false, "Ativar")
pure.pp.spice.addSliderFloat("MPIXELS_LDR", "CaStrength", 0.0015, 0.0, 0.01, "Intensidade")
pure.pp.spice.addSliderFloat("MPIXELS_LDR", "CaFalloff", 2.0, 1.0, 5.0, "Falloff radial")
pure.pp.spice.addSeparator("MPIXELS_LDR")

-- ---------------------------------------------------------------------------
-- Barras cinematograficas
-- ---------------------------------------------------------------------------
pure.pp.spice.addText("MPIXELS_LDR", "Barras")
pure.pp.spice.addCheckbox("MPIXELS_LDR", "BarsEnabled", false, "Ativar barras")
pure.pp.spice.addSliderFloat("MPIXELS_LDR", "BarsSize", 0.10, 0.02, 0.20, "Altura")
