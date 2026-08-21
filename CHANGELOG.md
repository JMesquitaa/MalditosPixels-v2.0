# CHANGELOG — MALDITOS PIXELS

## v2.0.2 (script interno v44, Blocos 18 e 19)

### Bloco 19 — Aba "Sobre" sobreposta

O .ui desenhava o manifesto na pagina "Sobre" com PURE_PP_UI_drawText, que
posiciona por x/y absoluto e ignora o fluxo de widgets; o .lua registrava
30 addText na mesma pagina. Os dois desenhavam no mesmo espaco e o texto
saia ilegivel. Separado: "Sobre" agora so contem o manifesto do .ui (vazia
do lado Lua, mesmo modelo da aba "Info"), e uma aba "Guia" nova com o texto
tecnico. Cores de aba para Guia, Luz e Chuva.

---

### Bloco 18 — Turbidez do ceu (Sky V2)

O init chamava ac.setSkyV2Turbidity(3, 14). A chamada estava correta —
assinatura e (regiao, valor) — mas era codigo morto: o Pure escreve
ac.setSkyV2Turbidity(ac.SkyRegion.All, 10) dentro de __PURE__create_sky(dt),
que roda todo frame e sobrescreve o init. Movida pra escrita por frame na
secao 8, com TurbidezAtiva (checkbox, ligado) e TurbidezValor (slider 1-20,
default 10.0) na pagina World. Com 10.0 a imagem e identica as versoes
anteriores.

---

## v2.0 (script interno v42, Blocos 0 a 17)

Historico de desenvolvimento por bloco, em ordem de adicao ao script.

---

### Bloco 0 — Blindagem por Secao (fase 14.6)

Introducao do sistema de isolamento de erros por secao. Cada modulo do
update_pure_script() roda dentro de `mp_sec()`: se uma secao quebrar, ela
vira secao morta em silencio (um log por secao, nao por frame), sem derrubar
o filtro inteiro.

---

### Bloco 1 — Exposicao: Nucleo CBE

Implementacao do nucleo de exposicao baseada em CBE (Computed Base Exposure)
com handleExposure method 5. Dia/noite com targets, limites e velocidades
separados. Base para todos os modos de exposicao subsequentes.

---

### Bloco 2 — Tonemapping: 3 Modos

Shader HLSL inline com tres curvas de tonemapping selecionaveis:
- GT7-Blend: ICtCp (BT.2100) + Uchimura com chroma rolloff e protecao de
  emissivos vermelhos (taillight mask).
- Pixels-Tone: curva piecewise propria (px_curve) com matrizes de cor.
- GT-Film: Uchimura + compressao de highlights de filme (k=1.35) + print curve.

Registro via `ac.setPpTonemapFunction()` com cacheKey fixo.

---

### Bloco 3 — Motor de Cor CSP (7 nos)

Pilha de correcao de cor nativa do CSP, abaixo do estagio de PP. Sete nos
registrados uma vez no init e modulados por frame com perfis dia/noite
(r/g/b, temperatura, luminancia, contraste, sepia, matiz, saturacao, fade).

---

### Bloco 4 — Fog por Angulo Solar

Sistema de fog dinamico mapeado ao angulo solar: cada faixa de elevacao do
sol tem densidade, distancia e cor de fog proprios. Inclui fog legado (Bloco 17)
como camada de sombra adicional em condicoes de clima severo.

---

### Bloco 5 — Ceu, Estrelas e NLP

Controle de sol (tamanho, brilho), lua (tamanho, brilho, luz refletida),
estrelas noturnas e NLP (night light pollution). Modulacao separada para
condicoes de overcast.

---

### Bloco 6 — Glare por Perfil Dia/Noite

Dois conjuntos de parametros de glare (Sobrio e Chamativo) com pesagem
separada para dia e noite. Os conjuntos SOMAM, cada um pesado pela sua
compensacao: de dia o bloco noturno vale zero e vice-versa. Inclui ghost,
halo, distortion, sharpness, streaks e multiplicador anamorfico (Bloco 16).
Checklist anti-arco-iris embutido no perfil Sobrio.

---

### Bloco 7 — Reflections (Pixels Spec)

Controle de reflexos via fresnel gamma dinamico, CPL (polarizing filter),
level dia/noite, saturacao de reflexo, emissive boost e sun speculars.
Modulado por velocidade e condicao de molhado.

---

### Bloco 8 — Emissives e Bounce Light

Multiplicadores de emissive e luz rebatida (bounce) separados para dia e
noite. Track glow e camera gain configurados no init.

---

### Bloco 9 — Clima: Overcast e Atmosfera

Mapeamento dos cinco climas atmosfericos (nublado leve a tempestade) com
fator de dia aplicado a nebulosidade. Variaveis de overcast (cobertura de
nuvens, umidade, badness) lidas e suavizadas por frame.

---

### Bloco 10 — LUT e Color Grading

Sistema de LUT PNG 1024x32 por variante (mpixels_rachadores, cinema, puro,
vivo, madrugada). Saturacao, temperatura, sepia e vignette modulados
separadamente para dia e noite com soft-clip de gamut configuravel.

---

### Bloco 11 — Cadeia de Crossover Completa

Implementacao da cadeia de crossover dia/noite: transicao suave entre todos
os parametros de exposicao, cor e bloom ao longo do ciclo solar. Estados
persistentes entre frames (suavizacao de primeira ordem com constante
assimetrica subida/descida).

---

### Bloco 12 — Godrays

Configuracao de godrays via API CSP (length, glare ratio, angle attenuation,
noise mask, depth threshold). Sunblinding com iris, star style e star blur.

---

### Bloco 13 — Modos de Exposicao (5 modos)

Cinco modos de exposicao selecionaveis na UI: Adaptativo, Fixo, Tunel,
Noite Fechada, Override Manual. Cada modo configura targets e speeds
diferentes no handleExposure.

---

### Bloco 14 — Skydome

Cinco presets de skydome DDS (Via Lactea, Aurora, Twilight, Starfield,
Overcast) com selecao automatica por condicao (nightness, fog, overcast)
ou manual. Controle de brilho, contraste, rotacao, altura e animacao.
Change-gate para evitar trocas desnecessarias.

---

### Bloco 15 — World: Nuvens e Rainbow

Controle de brilho e contraste de nuvens separado para dia e noite.
Rainbow via `ac.setSkyV2Rainbow()` com chave de habilitacao.

---

### Bloco 16 — Luz Solar, Sombras e Adaptacao de Tunel

Sol, sombras e adaptacao de tunel via API de luz solar CSP. Multiplicador
anamorfico para glare (1 = desligado, 3 = ativo). Memo de resolucao de
sombra para evitar rechamar a API todo frame.

---

### Bloco 17 — Fog Legado e Sombras de Clima

Quatro sistemas de fog unificados na UI: Desligado, Simples, Dinamico (LUT
por angulo solar) e Legado. Sombras falsas de clima (cloud shadow multiplier)
aplicadas em qualquer modo de fog ativo. Mistura de cor do fog legado por
temperatura do momento do dia.

---

*Script v42 — versao publica: Malditos Pixels v2.0*
