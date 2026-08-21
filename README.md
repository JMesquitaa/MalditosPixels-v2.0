# Malditos Pixels v2.0.2

PPFilter para Assetto Corsa (CSP + Pure). Feito pelos Malditos Rachadores,
focado em corrida de rua e noite urbana.

---

## Requisitos

- Custom Shaders Patch (CSP) — build 3650+
- Pure 3.0+
- SPICE precisa estar ativo no Pure (Settings > Pure > SPICE > Enable)

---

## Variantes

| Nome | Perfil |
|------|--------|
| Malditos Pixels | Base. Equilibrio entre realismo e identidade visual. |
| Malditos Pixels Cinema | Contraste e saturacao altos, sombras frias. |
| Malditos Pixels Puro | Grade minima, fidelidade documental. |
| Malditos Pixels Vivo | Saturacao maxima com soft-clip de gamut. |
| Malditos Pixels Madrugada | Noturno. Purkinje pronunciado, temperatura fria. |

---

## Instalacao

Rode no PowerShell:

```powershell
.\install.ps1
```

O script acha o Assetto Corsa sozinho pelo registro do Steam.

Para quem preferir copiar manualmente:

| Origem | Destino |
|--------|---------|
| `system\cfg\ppfilters\` | `<AC>\system\cfg\ppfilters\` |
| `extension\textures\color_grading\` | `<AC>\extension\textures\color_grading\` |
| `extension\config-ext\PureHdrEffects\MPIXELS_FX\` | `<AC>\extension\config-ext\PureHdrEffects\MPIXELS_FX\` |
| `extension\config-ext\PureLdrEffects\MPIXELS_FX_LDR\` | `<AC>\extension\config-ext\PureLdrEffects\MPIXELS_FX_LDR\` |

Selecione a variante em Content Manager > Video > Post-Processing Filter.

---

## A pasta color_grading nao e opcional

Os `.ini` referenciam 5 PNGs com `[EXT_COLOR_GRADING] ENABLED=1`. Se nao
forem copiados, **a cor quebra sem nenhum aviso no jogo**: ceu chapado de
dia com a noite parecendo normal.

Para confirmar que e isso: abra o `.ini` da variante ativa, ache a secao
`[EXT_COLOR_GRADING]` e troque `ENABLED=1` por `ENABLED=0`. Se normalizar,
era LUT faltando.

Arquivos que precisam existir em `<AC>\extension\textures\color_grading\`:

    mpixels_rachadores.png
    mpixels_cinema.png
    mpixels_puro.png
    mpixels_vivo.png
    mpixels_madrugada.png

---

## Se algo parecer quebrado

No log do CSP, procure por `[MPIXELS]`. Deve aparecer:

    [MPIXELS] INIT completo | v44 ...
    [MPIXELS] update FIM ok | frame=<n>

A segunda linha repete a cada 120 frames. Se sumir, alguma secao morreu —
procure por `SECOES MORTAS` no log, que ele diz qual.

O campo "Script execution time" do app Pure PP e indicador quebrado. Marca
0.000ms com tudo rodando. Ignorar.

Os nomes dos arquivos sao acoplados: `<nome>.ini`, `pure_scripts\<nome>.lua`
e `pure_scripts\<nome>_ui\<nome>.ui` precisam ter exatamente o mesmo nome.
Renomear um sem os outros quebra o filtro.

---

## Skydomes (opcional)

5 texturas DDS (~292 MB) na aba Releases. Extraia em:

    <AC>\system\cfg\ppfilters\pure_scripts\textures\

Sem elas o filtro roda normal. So nao ative os presets da pagina Ceu.

---

## Ajudando na calibracao

Ordem de calibracao: Exposicao, Tonemap, Cor, Atmosfera, Bloom. A cadeia
tem dependencia — fora de ordem voce compensa um problema com outro.

Uma coisa por vez, sempre na mesma cena. Mexer em tres sliders e dizer que
melhorou nao ensina nada.

Config que arruma um cenario e estraga outro nao esta pronta: teste noite,
dia, chuva e tunel antes de dar veredito.

A pergunta que decide: "isso faria sentido se a imagem tivesse sido
capturada por uma camera de verdade instalada num carro durante um racha?"
Se nao, o parametro esta errado, mesmo que a screenshot tenha ficado bonita.

Um reporte util tem: variante, pista, horario, clima, seco ou molhado,
print sem HUD, e o slider mexido com valor antes e depois.

---

Malditos Rachadores — 2026

Uso pessoal e da comunidade liberado. Revenda proibida. Ver LICENSE.
