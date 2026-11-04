---
id: SPEC-034
status: rascunho
---

# Motion e fluidez na interface

## Objetivo

O app quase não tem movimento fora do splash, da marca na barra de título e do Canvas do Quadro. Nas telas de Specs, Sessões e Review, tudo muda de uma vez:

- trocar de seção substitui a tela inteira sem transição;
- o card que muda de coluna some de um lugar e reaparece em outro, sem mostrar para onde foi;
- os 66 `showDialog` e os 44 snackbars usam o padrão do Material, sem o ritmo do app;
- não há durações nem curvas compartilhadas, então cada animação define as suas.

Esta spec cria uma base de motion e a aplica nos pontos em que o movimento explica o que aconteceu. O Promptorium é uma ferramenta usada por horas, então o tom é sóbrio: sem bounce, sem pulso contínuo novo e sem listas inteiras entrando em cascata.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/NYfLh5R43xnTq8LTB8UGDK). Cada artboard é um protótipo interativo com o seletor **Hoje / Proposta / 4× mais lento**. Cópia dos artboards, capturas (`0-ritmo.png` a `6-skeleton.png`) e o relatório da validação (`relatorio-validacao-motion-e-fluidez-2026-11-04.html`) em `docs/mockups/spec-034/`:

| Artboard | O que mostra | Requisitos |
|---|---|---|
| `Main.dc.html` | As quatro durações e as duas curvas | R1 |
| `Navegacao.dc.html` | Tela nova na direção do movimento e destaque da barra lateral | R2, R3 |
| `Dialogos.dc.html` | Diálogo de confirmação e aviso com Desfazer | R4, R5 |
| `Hover.dc.html` | Hover, press e foco em cards, linhas, botões e barra lateral | R6 |
| `Quadro.dc.html` | Card que desliza até a coluna nova e contagem da coluna | R7 |
| `Sessao.dc.html` | Evento novo, rajada de eventos e status das etapas | R8, R9 |
| `Carregando.dc.html` | Skeleton ao abrir uma spec, só acima de 300 ms | R10 |

## Requisitos

- R1 · O app deve ter tokens de motion em `AppMotion`, usados por toda animação nova:

  | Token | Entrada | Saída | Uso |
  |---|---|---|---|
  | `quick` | 120 ms | 80 ms | hover, press, foco |
  | `base` | 160 ms | 110 ms | toast, fundo do diálogo, evento novo, status da etapa |
  | `emphasis` | 220 ms | 150 ms | diálogo, card que muda de coluna |
  | `section` | 640 ms | na hora | troca de seção, destaque da barra lateral |

  - A curva de entrada é `Cubic(.2, .8, .2, 1)` e a de saída é `Cubic(.4, 0, 1, 1)`.
  - Os valores de `emphasis` e do fundo do diálogo são os mesmos da SPEC-033 R2.
- R2 · Ao trocar de seção, a tela nova deve entrar com fade e deslocamento de 8 px em `section`:
  - ela vem de baixo quando o item escolhido está abaixo do atual na barra lateral, e de cima quando está acima;
  - a tela anterior sai na hora, sem ficar sobreposta à nova;
  - a barra de título e a barra lateral não animam com a tela.
- R3 · O destaque do item ativo da barra lateral deve deslizar até o item novo em `section`.
- R4 · Os diálogos do app devem abrir pelo helper `showAppDialog`:
  - o fundo escurece em `base`;
  - o diálogo cresce de escala 0,96 e opacidade 0 até 1, em `emphasis`;
  - ao fechar, ele vai até escala 0,98 e opacidade 0, com a duração de saída de `emphasis`;
  - `Esc`, clique no fundo, foco inicial e o valor retornado funcionam como no `showDialog`;
  - o foco entra no diálogo ao abrir, fica preso nele e volta ao elemento que o abriu ao fechar.
- R5 · Toasts e snackbars devem subir 8 px com fade em `base` e sair pelo caminho inverso com a duração de saída. O `PrototypeUndoToast` segue a mesma regra.
- R6 · Cards do Quadro, linhas de lista, `SmallButton`, botões principais e itens da barra lateral devem ter:
  - transição de cor, borda e sombra em `quick` no hover;
  - escala 0,98 enquanto pressionados, sem mudar o layout;
  - o mesmo anel de foco de hoje, sem atraso.
- R7 · No Quadro, um card que muda de coluna deve deslizar até o destino em `emphasis`:
  - vale para o arraste, a partir do ponto em que o card foi solto, e para a mudança feita pelo agente;
  - os cards vizinhos fecham o espaço em `emphasis`;
  - a contagem das duas colunas troca com fade em `base`;
  - no máximo 3 cards animam ao mesmo tempo; os demais vão direto ao destino;
  - um card fora da área visível vai direto ao destino.
- R8 · Na timeline da sessão, um evento novo deve subir 6 px com fade em `base`:
  - o histórico carregado ao abrir a sessão não anima;
  - mais de 3 eventos em 300 ms entram sem animação;
  - a animação não muda a posição da rolagem.
- R9 · O status de uma etapa deve mudar com transição de cor em `base`. Ao concluir, o check da etapa se desenha uma vez, também em `base`.
- R10 · Ao abrir uma spec, o `CircularProgressIndicator` de `specs_screen.dart` deve dar lugar a um skeleton com a forma do documento:
  - nos primeiros 300 ms de espera, o documento atual continua na tela, sem piscar;
  - depois disso, o skeleton entra no lugar dele;
  - o texto entra com fade em `base`;
  - se a spec não abrir, a área mostra o motivo e "Tentar de novo";
  - os demais spinners do app indicam atividade em andamento, não conteúdo carregando, e continuam como estão.
- R11 · Com `MediaQuery.disableAnimationsOf(context)` ligado, todas as animações desta spec devem ter duração zero e mostrar o estado final. O brilho do skeleton fica parado.
- R12 · Nenhuma animação pode bloquear clique ou teclado:
  - uma tecla ou um clique durante a transição já vale;
  - uma nova mudança interrompe a animação em curso e parte do estado atual;
  - o estado final nunca depende do fim de uma animação.
- R13 · As animações devem usar só opacidade e transformação, sem refazer o layout a cada quadro. Com o app parado, só o que já se move hoje continua se movendo.

## Fora do escopo

- Splash, marca da barra de título e Canvas do Quadro, que já têm motion próprio.
- O modal da SPEC-033: ele usa os tokens do R1, mas a animação dele é definida naquela spec.
- Pacotes novos de animação.
- Tema claro.
- Transições entre as abas internas de cada tela.

## Design

### O que já existe

- `lib/ui/theme/tokens.dart`: cores e fontes, sem tokens de motion.
- `lib/ui/shell/app_shell.dart:391`: `KeyedSubtree` com `ValueKey('screen-${section.name}')`, que troca a tela sem transição.
- `lib/ui/shell/side_bar.dart`: item da barra lateral com `Material` colorido quando ativo (l.82).
- `lib/ui/shell/navigation.dart`: `AppSection.navItems`, a ordem da barra lateral.
- `lib/features/sessions/widgets/session_style.dart:83`: `SmallButton`.
- `lib/features/board/board_screen.dart`: `DragTarget` da coluna (l.958), `Draggable` do card (l.1079) e contagem `board-column-count-*` (l.994).
- `lib/features/sessions/widgets/timeline_view.dart:117`: `ListView.builder` com `reverse: true`.
- `lib/features/specs/specs_screen.dart:1601`: spinner enquanto a spec carrega.
- `lib/features/specs/prototype/prototype_delete.dart`: `PrototypeUndoToast`.
- Reduced motion já é respeitado em `title_bar.dart`, `spec_canvas.dart` e `splash_painter.dart`.

### R1, R11 · Base

- `lib/ui/theme/motion.dart` com `AppMotion`: as durações, as curvas e `AppMotion.duration(context, d)`, que devolve `Duration.zero` quando `MediaQuery.disableAnimationsOf(context)` está ligado.
- Os testes de widget que não tratam de motion rodam com animações desligadas, por um `MediaQuery` no helper de montagem. Assim os 15 arquivos com `pumpAndSettle` e os testes com número fixo de `pump` não mudam de comportamento.

### R2, R3 · Navegação

- Um widget `SectionTransition` em volta do `KeyedSubtree`. Ele só anima a entrada, com `FadeTransition` e `SlideTransition`, porque manter as duas telas montadas duplicaria providers, foco e chaves durante a troca.
- A direção vem da comparação dos índices em `AppSection.navItems`.
- O destaque sai do `Material` de cada item e vira um único elemento em `Stack`, posicionado com `AnimatedSlide`.

### R4, R5 · Diálogos e toasts

- `showAppDialog<T>` em `lib/ui/widgets/app_dialog.dart`, com a mesma assinatura usada hoje do `showDialog` e implementado com `showGeneralDialog`.
- Os 66 `showDialog` são trocados de forma mecânica.
- Snackbars: tema único em `AppTheme`, com o estilo de animação do `ScaffoldMessenger`. Se a API não permitir o deslocamento de 8 px, o helper `showAppToast` substitui as 44 chamadas.

### R6 · Hover e press

- `AppPressable` em `lib/ui/widgets/app_pressable.dart`: `MouseRegion`, escala e estado de hover. `SmallButton` e os cards passam a usá-lo.

### R7 · Quadro

- Cada card guarda sua posição por `GlobalKey`. Quando a etapa do card muda, um `OverlayEntry` leva uma cópia da posição antiga até a nova com `Transform`, e o card real fica invisível até o fim, sem sair do layout.
- Os vizinhos usam a mesma técnica, com deslocamento relativo.
- A contagem usa `AnimatedSwitcher`.

### R8, R9 · Sessão

- O `timeline_view` guarda o tamanho da lista na abertura: só itens além desse tamanho animam.
- A contagem de eventos em 300 ms decide se a entrada anima.
- O check é um `CustomPainter` com o progresso do traço.

### R10 · Skeleton

- `SpecSkeleton` em `lib/features/specs/widgets/spec_skeleton.dart`, com `Timer` de 300 ms e `AnimatedSwitcher` para o texto.

### Branches

A branch pai é `spec/034-motion`. Cada tarefa tem sua branch, criada a partir da pai, e vira um PR com base na pai. Ao fim, um PR leva a pai para a `main`.

| Tarefa | Branch | Requisitos | Depende de |
|---|---|---|---|
| T1 · Base de motion | `spec/034-t1-base` | R1, R11, R12, R13 | — |
| T2 · Navegação | `spec/034-t2-navegacao` | R2, R3 | T1 |
| T3 · Diálogos e toasts | `spec/034-t3-dialogos` | R4, R5 | T1 |
| T4 · Hover e press | `spec/034-t4-hover` | R6 | T1 |
| T5 · Quadro | `spec/034-t5-quadro` | R7 | T1, T4 |
| T6 · Sessão | `spec/034-t6-sessao` | R8, R9 | T1 |
| T7 · Skeleton | `spec/034-t7-skeleton` | R10 | T1 |

Nenhuma implementação começa antes da aprovação do canvas.

## Critérios de aceite

- [ ] `AppMotion` expõe as quatro durações, as saídas e as duas curvas; com animações desligadas, `AppMotion.duration` devolve zero [R1] [R11] verificar: flutter test test/ui/motion_test.dart
- [ ] Trocar de seção mostra só a tela nova, com fade e 8 px em 640 ms, na direção do item escolhido; trocar de novo durante a entrada já mostra a próxima tela [R2] [R12] verificar: flutter test test/ui/shell/section_transition_test.dart
- [ ] O destaque da barra lateral é um único elemento que desliza até o item ativo [R3] verificar: flutter test test/ui/shell/section_transition_test.dart
- [ ] `showAppDialog` abre com escala 0,96 e fecha com escala 0,98, mantendo `Esc`, fundo e valor retornado; o foco entra, fica preso e volta a quem abriu [R4] verificar: flutter test test/ui/widgets/app_dialog_test.dart
- [ ] Nenhum `showDialog` direto sobra em `lib/`, fora do helper [R4] verificar: test "$(grep -rn 'showDialog<\|showDialog(' lib | grep -v app_dialog.dart | wc -l)" = 0
- [ ] Toasts e o `PrototypeUndoToast` sobem 8 px e saem pelo caminho inverso [R5] verificar: flutter test test/ui/widgets/app_toast_test.dart
- [ ] Hover muda a cor em `quick`, e o press aplica escala 0,98 sem mudar o tamanho do layout [R6] verificar: flutter test test/ui/widgets/app_pressable_test.dart
- [ ] O card que muda de coluna desliza do ponto de origem ao destino; acima de 3 cards e fora da tela ele vai direto [R7] verificar: flutter test test/features/board/board_card_flight_test.dart
- [ ] Eventos novos animam; histórico e rajadas não animam, e a rolagem não muda [R8] verificar: flutter test test/features/sessions/timeline_motion_test.dart
- [ ] O status da etapa troca de cor, e o check se desenha uma vez ao concluir [R9] verificar: flutter test test/features/board/step_status_motion_test.dart
- [ ] O documento atual fica na tela nos primeiros 300 ms; depois entra o skeleton; abrir outra spec cancela a espera; a falha mostra o motivo e "Tentar de novo" [R10] verificar: flutter test test/features/specs/spec_skeleton_test.dart
- [ ] Com animações desligadas, cada tela vai direto ao estado final, e o brilho do skeleton fica parado [R11] verificar: flutter test test/ui/motion_test.dart
- [ ] Clique e teclado valem durante a transição, e uma nova mudança parte do estado atual [R12] verificar: flutter test test/ui/motion_test.dart
- [ ] Com o app parado, nenhuma animação nova fica agendando quadros [R13] verificar: flutter test test/ui/motion_test.dart

## Decisões

- D1 · A tela anterior sai na hora, sem crossfade. Duas telas montadas juntas duplicariam providers, foco e chaves.
- D2 · Sem pacote de animação: o Flutter já cobre tudo o que a spec pede.
- D4 · O ritmo das animações é aprovado no canvas, por quem usa o app: a auditoria automática não mede transições.
- D5 · Canvas aprovado em 2026-11-04. A troca de seção usa 640 ms, o ritmo de 4× escolhido pelo autor; diálogos, toasts e o restante ficam como na Proposta.
- D6 · A tarefa T3 troca todos os 66 diálogos, sem exceção (P1).
- D3 · Uma spec com branch pai e uma branch por tarefa, a pedido do autor, com o canvas aprovado antes de implementar.

## Perguntas em aberto

Nenhuma.
