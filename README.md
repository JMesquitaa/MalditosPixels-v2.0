# Malditos Pixels v2.0.2

PPFilter para Assetto Corsa (CSP/Pure). Desenvolvido pelos Malditos Rachadores.

Cinco variantes: Rachadores (base), Cinema, Puro, Vivo, Madrugada.

---

## Ajude na calibracao

O filtro esta em calibracao aberta. Antes de reportar qualquer coisa, leia
[docs/CALIBRACAO.md](docs/CALIBRACAO.md) — la tem a ordem de calibracao, o
checklist de 21 pontos e o formato de reporte. Issues vao pelo template
"Reporte de calibracao". Reporte sem o minimo descrito no template sera
fechado.

---

## Requisitos

- Assetto Corsa com Content Manager
- Custom Shaders Patch (CSP) — build recomendada: 3650+
- Pure — versao 3.0+

---

## Instalacao rapida (PowerShell)

```powershell
.\install.ps1
```

O script localiza o Assetto Corsa automaticamente via registro do Steam e
copia todos os arquivos para os diretorios corretos. Nao modifica nenhum
outro arquivo do jogo.

---

## Instalacao manual

Copie o conteudo de cada pasta para o diretorio correspondente dentro da
instalacao do Assetto Corsa:

| Origem | Destino |
|--------|---------|
| `system\cfg\ppfilters\` | `<AC>\system\cfg\ppfilters\` |
| `system\cfg\ppfilters\pure_scripts\` | `<AC>\system\cfg\ppfilters\pure_scripts\` |
| `extension\config-ext\PureHdrEffects\MPIXELS_FX\` | `<AC>\extension\config-ext\PureHdrEffects\MPIXELS_FX\` |
| `extension\config-ext\PureLdrEffects\MPIXELS_FX_LDR\` | `<AC>\extension\config-ext\PureLdrEffects\MPIXELS_FX_LDR\` |
| `extension\textures\color_grading\` | `<AC>\extension\textures\color_grading\` |

Apos copiar, selecione "Malditos Pixels" (ou qualquer variante) no Content
Manager > Video > Post-Processing Filter.

---

## Passos manuais

### Preset CSP

O filtro foi calibrado com um preset especifico de CSP que liga SSGI,
cubemaps locais de pista e carro, HBAO, ASSAO qualidade 3. Sem ele o filtro
funciona, mas a iluminacao e os reflexos nao vao bater com a calibracao.

Para aplicar: arraste `csp-preset\MALDITOS PIXELS.ini` para dentro do
Content Manager em Settings > Custom Shaders Patch > Presets.

### Skydomes (opcional)

Os cinco arquivos DDS (~292 MB) ficam em Releases por causa do tamanho.
Baixe o zip `mpixels-skydomes.zip` da release v2.0.2 e extraia em:

    <AC>\system\cfg\ppfilters\pure_scripts\textures\

Sem eles o filtro roda normalmente — so nao ative a pagina "Ceu" na UI.

---

## Se a cor sair errada

**Sintoma:** ceu chapado/lavado de dia, noite aparentemente normal.

**Causa:** os cinco arquivos de LUT de color grading nao foram copiados.
Os `.ini` do filtro referenciam `extension/textures/color_grading/mpixels_*.png`
com `EXT_COLOR_GRADING ENABLED=1`. Se os PNGs nao existirem, o jogo aplica
color grading apontando para arquivo inexistente e a cor quebra sem aviso.

**Arquivos que precisam existir em `<AC>\extension\textures\color_grading\`:**

    mpixels_rachadores.png
    mpixels_cinema.png
    mpixels_puro.png
    mpixels_vivo.png
    mpixels_madrugada.png

**Teste de isolamento:** abra o `.ini` da variante ativa e troque
`ENABLED=1` por `ENABLED=0` na secao `[EXT_COLOR_GRADING]`. Se a cor
normalizar, era LUT faltando — rode `install.ps1` novamente ou copie a
pasta `extension\textures\color_grading\` manualmente.

---

## Diagnostico

O filtro loga `[MPIXELS] update FIM ok | frame=<n>` a cada 120 frames no
log do CSP. Se essa mensagem sumir, alguma secao morreu — procure no log
por `SECOES MORTAS:` que ele diz qual secao quebrou.

O campo "Script execution time" do app Pure PP e indicador quebrado
(marca 0.000ms com tudo rodando). Nao serve para diagnostico.

Os nomes dos arquivos sao acoplados: `<nome>.ini`, `pure_scripts\<nome>.lua`
e `pure_scripts\<nome>_ui\<nome>.ui` precisam ter o mesmo nome. Renomear
um sem os outros quebra o filtro silenciosamente.

---

## Variantes

| Nome | Perfil |
|------|--------|
| Malditos Pixels | Base. Equilibrio entre realismo e identidade visual. |
| Malditos Pixels Cinema | Drama cinematografico. Contraste e saturacao elevados, sombras frias. |
| Malditos Pixels Puro | Fidelidade documental. Grade minima, contraste reduzido. |
| Malditos Pixels Vivo | Impacto visual. Saturacao maxima com soft-clip de gamut. |
| Malditos Pixels Madrugada | Noturno. Purkinje pronunciado (CIE 1951 scotopico), temperatura fria. |

---

## O que tem dentro

- Tonemapping: 3 modos (GT7-Blend / Pixels-Tone / GT-Film)
- Exposicao adaptativa: CBE + YEBIS AE, dia/noite/tunel, 5 modos
- Motor de cor CSP: 7 nos nativos modulados por frame
- Color grading: LUT PNG 1024x32 por variante + soft-clip de gamut
- Bloom: Glarefunc dia/noite com dois perfis (Sobrio / Chamativo)
- Atmosfera: fog dinamico por angulo solar + fog legado
- Skydome: 5 presets DDS (Via Lactea, Aurora, Twilight, Starfield, Overcast)
- SPICE FX: 10 efeitos (sharpening, clarity, CA, VHS, grain, vignette, etc.)
- Purkinje: shift scotopico CIE 1951 (exclusivo na variante Madrugada)
- GodRays, reflections, emissives, rainbow, sombras de clima

---

## Licenca

Uso pessoal e compartilhamento gratuito permitidos. Revenda proibida.
Leia LICENSE para os termos completos.

---

*Malditos Rachadores — 2026*
