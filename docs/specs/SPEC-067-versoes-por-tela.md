---
id: SPEC-067
status: rascunho
---

# O protótipo mostra uma versão por tela

## Objetivo

No modo Protótipo da spec, cada variação gerada vira mais uma carta no canvas. Com algumas rodadas de "Pedir variação", uma tela como R2 ocupa quatro lugares (A, B, C, D), empurra as outras para baixo, e a versão que acabou de chegar fica no fim do grupo, difícil de achar.

Esta spec deixa **uma carta por tela**. A carta mostra só a versão escolhida, com a letra após o nome e quantas versões existem (`D · 4`). Clicar nessa letra abre a aba **Versões** filtrada naquela tela, onde dá para alternar entre as versões, e a carta troca na hora.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/VQgGqnbEkAkyVoFiY3LYDp). Capturas em `docs/mockups/spec-067/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-antes.png` | Hoje: uma carta por versão; R2 ocupa quatro lugares | — |
| `2-uma-carta.png` | Uma carta por tela, a letra com o número de versões e a etiqueta "nova" | R1, R2, R5 |
| `3-versoes.png` | Clicou em `D · 4`: a aba Versões só com as versões de R2 | R3 |
| `4-alternar.png` | Escolheu B: a carta de R2 passa a mostrar B | R4, R6 |
| `5-gerando.png` | Uma versão nova sendo gerada sobre a carta da tela | R5 |

## Requisitos

- R1 · O canvas mostra **uma carta por requisito**, com a versão mostrada daquele requisito. Telas com uma versão só ficam como hoje (letra `A`, sem número).
- R2 · Com duas ou mais versões, a letra após o nome vira um botão `<letra> · <n>` (ex.: `D · 4`), com a borda das cartas empilhadas atrás da miniatura. "Aprovada" continua na carta quando a versão mostrada é a aprovada.
- R3 · Clicar no botão da letra abre a aba **Versões** do painel **filtrada naquele requisito**: o título "R2 · Login · 4 versões", o link "Todas as telas (n)", que tira o filtro, e uma lista com a miniatura, a letra, o arquivo, a hora, "Aprovada" e o botão de apagar de cada versão. A versão mostrada fica marcada. Abrir a aba Versões pelo próprio título continua mostrando todas as telas, agrupadas como hoje.
- R4 · Na lista filtrada, clicar numa versão (ou ↑/↓ com o foco na lista) a torna a **versão mostrada**, e a carta do canvas troca na hora, sem gerar nada. Esc volta para todas as telas. "Comparar as n lado a lado" abre o "Comparar variações" daquele requisito.
- R5 · Quando uma variação nova fica pronta, ela passa a ser a mostrada, com a etiqueta **"nova"** na carta e na lista até ser vista: o painel Versões aberto nela, ou outra escolha. O aviso "R2 · variação D pronta e mostrada no canvas" tem "Ver versões", que abre a lista filtrada. Enquanto gera, o aviso "Gerando variação E de R2…" fica sobre a carta da tela, sem abrir um lugar novo no canvas.
- R6 · A versão mostrada de cada requisito fica salva no `index.json` do protótipo (`mostrada`) e volta ao reabrir a spec. Sem escolha salva, mostra-se a aprovada; sem aprovada, a mais nova.
- R7 · As ações da carta valem para a versão mostrada: "Abrir no navegador", "Pedir variação", "Apagar tela…" e a seleção para "Pedir ao Claude". Ao apagar a versão mostrada, passa a ser mostrada a aprovada, senão a mais nova que restou. Apagar a última versão de um requisito deixa o lugar vazio, como hoje (SPEC-027).
- R8 · Acessibilidade: o botão da letra se anuncia como "Variação D, 4 versões: ver versões de R2"; a lista é um grupo de opções com uma marcada, operável pelo teclado.

## Fora do escopo

- Mudar como as variações são geradas ou nomeadas (`R2-login.b.html`…).
- Aprovar pela aba Versões (continua no menu da carta e em "Comparar variações").
- Agrupar telas de requisitos diferentes.

## Design

### O que já existe

- `lib/features/specs/prototype/prototype_view.dart`: `PrototypeCanvas` (uma `_ScreenCard` por arquivo, `_LetterBadge`), `PrototypePanel` (abas "Pedir ao Claude" e "Versões", `_VersionRow`), `PrototypeUiState` (`versionsTab`, `selected`, `comparing`) e `PrototypeCompare`.
- `prototype_files.dart`: `MockupScreen` (requisito, letra), `PrototypeIndex` (o `index.json`: `telas`, `historico`, `semTela`), `PrototypeState.variationsOf`.
- `prototype_service.dart`: a geração das variações e o `index.json`.

### Componentes

- **`PrototypeIndex.shown`** (novo, `mostrada` no `index.json`): requisito → arquivo mostrado.
- **`shownScreen(PrototypeState, req)`**: a escolha salva, se o arquivo ainda existe; senão a aprovada; senão a mais nova.
- **`PrototypeUiState.versionsFilter`** (novo): requisito da lista filtrada (null = todas).
- **`_VersionChip`**: o botão `<letra> · <n>` na carta, que chama `showVersionsOf(req)`.
- **Lista filtrada** em `PrototypePanel`: grupo de opções com miniatura (`_SizedThumb`), ↑/↓ e Esc.
- A geração de variação grava `mostrada` e marca a nova como "nova" (`PrototypeIndex.unseen`).

### Testes

- Canvas: uma carta por requisito; a carta mostra a escolha salva, a aprovada ou a mais nova; o botão `D · 4` só com duas ou mais.
- Clicar no botão: aba Versões filtrada, versão marcada; "Todas as telas" tira o filtro.
- Alternar por clique e por ↑/↓ troca a carta e grava `mostrada`; reabrir a spec mantém.
- Variação nova: vira a mostrada com "nova"; o aviso com "Ver versões".
- Apagar a mostrada: cai para a aprovada ou a mais nova.
- `index.json` antigo, sem `mostrada`, abre normalmente.

## Decisões

- **A nova vira a mostrada.** Quem pediu a variação quer ver o resultado; a aprovada continua aprovada e volta com um clique.
- **Filtro, não outra aba.** A aba Versões já existe; filtrar por tela evita uma terceira aba e deixa "Todas as telas" a um clique.
- **Escolha salva no `index.json`.** É do protótipo, não do app: vai junto com as telas no repositório e vale em outra máquina.
- **Mostrar não é aprovar.** Alternar não mexe em `## Protótipo` da spec. Aprovar continua uma ação explícita.

## Plano

1. **t1 · Uma carta por tela** (R1, R2, R6, R7): `shownScreen`, `mostrada` no `index.json`, a carta agrupada com o botão da letra e as ações sobre a mostrada.
2. **t2 · Versões filtradas e alternar** (R3, R4, R5, R8): a lista filtrada, alternar por clique e teclado, a etiqueta "nova", o aviso com "Ver versões" e a geração sobre a carta.

## Critérios de aceite

- [ ] O canvas mostra uma carta por tela, com a letra da versão mostrada e o número de versões.
- [ ] Clicar na letra abre a aba Versões só com as versões daquela tela.
- [ ] Escolher outra versão troca a carta na hora e a escolha volta ao reabrir a spec.
- [ ] Uma variação nova aparece na carta da tela, marcada como "nova".
