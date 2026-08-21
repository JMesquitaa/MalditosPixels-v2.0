# Calibracao — Malditos Pixels v2.0.2

Leia antes de mexer em qualquer slider. Leia antes de abrir qualquer issue.

---

## Regra numero um

Uma coisa por vez, sempre na mesma cena. Mexer em tres sliders e dizer que
melhorou nao ensina nada. Mude um parametro, observe, anote, reverta se nao
serviu.

---

## Ordem de calibracao

Tem dependencia. Fora de ordem voce compensa um problema com outro e nunca
chega num resultado limpo.

1. **Exposicao** — acertar o brilho base antes de tudo
2. **Tonemap** — acertar a curva de contraste com o brilho ja estavel
3. **Cor** — acertar saturacao, temperatura e LUT com contraste ja definido
4. **Atmosfera** — acertar fog e profundidade com a cor ja calibrada
5. **Bloom** — acertar o brilho do glare por ultimo, em cima de tudo

---

## A pergunta que decide cada ajuste

> Isso faria sentido se esta imagem tivesse sido capturada por uma camera
> cinematografica real instalada num carro durante um racha?

Se nao, o parametro esta errado, mesmo que a screenshot tenha ficado bonita.

---

## Matriz de teste

Teste cada ajuste cruzando os cenarios abaixo. Config que arruma um cenario
e estraga outro nao esta pronta.

### Horario

- [ ] Noite limpa
- [ ] Noite chuvosa
- [ ] Madrugada
- [ ] Amanhecer
- [ ] Dia
- [ ] Por do sol

### Ambiente

- [ ] Cidade
- [ ] Rodovia
- [ ] Area industrial
- [ ] Tunel: entrada
- [ ] Tunel: interior
- [ ] Tunel: saida
- [ ] Ambiente extremamente escuro
- [ ] Iluminacao intensa de posto e neon

### Pista

- [ ] Seco
- [ ] Molhado
- [ ] Chuva caindo

### Situacao

- [ ] Alta velocidade
- [ ] Drift
- [ ] Trafego intenso
- [ ] Farois de carro proximo
- [ ] Multiplas fontes de luz
- [ ] Sessao de 30+ minutos

---

## Checklist de 21 pontos

Observe cada ponto na sua screenshot. Se algum falhar, anote o numero e
reporte.

1. Preto continua preto
2. Sombra tem informacao dentro
3. Area sem poste continua escura
4. Farol tem volume, nao disco chapado
5. Neon e letreiro tem cor, nao estouram
6. Ceu de dia tem gradiente
7. Reflexo no capo preserva forma
8. Sem halo gigante em fonte de luz
9. Sem franja colorida no glare
10. Luz intensa por luminancia, nao por efeito
11. Vermelho de lanterna nao domina
12. Sombra sem contaminacao verde ou azul
13. Pintura e pele com cor crivel
14. Nao parece filtro generico
15. Entrada de tunel com adaptacao coerente
16. Saida de tunel idem
17. Da pra perceber a diferenca ao passar por poste
18. Exposicao nao pulsa em luz salpicada
19. Distancia com separacao entre perto e longe
20. Asfalto molhado com profundidade, nao espelho
21. Alta velocidade continua legivel

---

## Como reportar

Abra uma issue usando o template "Reporte de calibracao". O minimo util e:

- Variante (Rachadores, Cinema, Puro, Vivo, Madrugada)
- Cenario (pista, horario, clima, seco ou molhado)
- Numero do ponto do checklist que falhou
- Screenshot sem HUD
- Slider mexido com valor antes e depois

"Ficou estranho" nao vira conserto. Exemplo de reporte bom:

> **Variante:** Cinema
> **Cenario:** Shutoko, noite chuvosa, asfalto molhado
> **Ponto:** 8 (halo gigante em fonte de luz)
> **Screenshot:** [imagem]
> **Controle:** Glare Luminance: 0.50 -> 0.35 (melhora, mas perde brilho em farol)

---

## Diagnostico antes de abrir issue

### (a) LUTs de color grading

Confira que os cinco arquivos existem em
`<AC>\extension\textures\color_grading\`:

    mpixels_rachadores.png
    mpixels_cinema.png
    mpixels_puro.png
    mpixels_vivo.png
    mpixels_madrugada.png

Se faltar, a cor quebra sem aviso. Sintoma tipico: ceu chapado de dia com
noite normal. Para confirmar, troque `ENABLED=1` por `ENABLED=0` em
`[EXT_COLOR_GRADING]` do .ini da variante ativa. Se normalizar, era LUT
faltando.

### (b) Log do CSP

Confira no log as linhas:

    [MPIXELS] INIT completo | v44 ...
    [MPIXELS] update FIM ok | frame=<n>

A segunda repete a cada 120 frames. Se sumir, alguma secao morreu. Procure
por `SECOES MORTAS:` no log — ele diz qual secao quebrou. Cole essa parte
na issue.

O campo "Script execution time" do app Pure PP e indicador quebrado. Marca
0.000ms com tudo rodando. Nao serve pra nada.

---

## Nomes acoplados

Os nomes dos arquivos sao acoplados: `<nome>.ini`,
`pure_scripts\<nome>.lua` e `pure_scripts\<nome>_ui\<nome>.ui` precisam
ter exatamente o mesmo nome. Renomear um sem os outros quebra o filtro
silenciosamente.
