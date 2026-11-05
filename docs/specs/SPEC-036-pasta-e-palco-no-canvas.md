---
id: SPEC-036
status: rascunho
depende-de: SPEC-008, SPEC-034
---

# Pasta de specs e palco no Canvas do Quadro

## Objetivo

O Canvas do Quadro mostra todas as specs de uma vez, em ondas da esquerda para a direita. Isso dá uma visão geral, mas fica difícil de usar conforme o projeto cresce:

- com dezenas de specs, é preciso arrastar e dar zoom para achar uma;
- as dependências de uma spec se perdem no meio das outras;
- não há busca;
- para ver o que está rodando agora, é preciso procurar os cards pelo Canvas.

Esta spec cria uma visão com **foco**. As specs ficam numa **pasta** à esquerda, que pode ser recolhida. Clicar numa spec leva a spec para o **palco**, no centro, com as specs que dependem dela ligadas abaixo por setas. Um botão mostra as specs em execução, e uma busca com atalho acha qualquer spec.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/4BTHA99gBd9kY4aokfZpiK). Cópia dos artboards e capturas em `docs/mockups/spec-036/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-pasta.png` | A pasta com o palco vazio | R1–R3 |
| `2-hover.png` | A spec cresce ao passar o mouse | R4 |
| `3-busca.png` | Busca filtrando as specs | R6, R7 |
| `4-aberta.png` | Spec no palco, com as dependentes e as setas | R8–R11 |
| `5-recolhida.png` | Pasta recolhida, só com os números | R5 |
| `6-executando.png` | Specs em execução no palco | R12, R13 |

## Requisitos

- R1 · O Quadro deve ganhar a visão **Foco**, ao lado das atuais: **Colunas · Grafo · Foco**. O Canvas de ondas continua como está, e a escolha fica salva como hoje. O Foco tem a pasta `specs/` à esquerda e o palco ocupando o resto da tela:
  - a pasta lista as specs do workspace, da mais nova para a mais antiga;
  - cada linha mostra o ícone de status, o número e o título;
  - o título cortado termina em reticências e aparece inteiro no hover (R4);
  - o cabeçalho da pasta mostra quantas specs há;
  - "Ocultar concluídas" (SPEC-019) vale também para a pasta.
- R2 · O ícone de status de cada linha não pode depender só da cor:
  - **Feito**: check verde;
  - **Em execução**: loading amarelo girando;
  - **Review**: ponto rosa;
  - **Backlog**: círculo vazio;
  - **Aguardando você**: o balão âmbar da SPEC-030, com prioridade sobre os outros;
  - cada ícone tem o nome do status como rótulo acessível.
- R3 · A pasta deve ter altura limitada e rolagem:
  - mostra até 15 linhas e, em janela menor, as que couberem;
  - rola pela roda do mouse, com a ponteira sobre a pasta;
  - rola pelas setas no topo e na base da pasta, 4 linhas por clique, que ficam desabilitadas nas pontas;
  - rola pelas setas do teclado, 1 linha por vez, com o foco na pasta;
  - mostra a posição numa barra fina, e as bordas esmaecem quando há mais itens naquela direção;
  - o foco por `Tab` numa linha fora da área visível rola até ela;
  - sobra um respiro no fim da lista, para a última linha crescer sem ser cortada.
- R4 · Ao passar o mouse ou focar uma linha, a spec deve crescer e virar um card completo, com código, status, título e etapas:
  - as linhas de baixo descem para abrir espaço, sem cobrir nenhuma linha;
  - a transição usa `AppMotion.base`;
  - a linha continua no lugar: nada se move sob o ponteiro.
- R5 · A pasta deve poder ser recolhida:
  - a seta no cabeçalho alterna entre aberta e recolhida, com transição de largura;
  - recolhida, ela mostra só o ícone de status e o número;
  - o palco se recentraliza e usa o espaço liberado;
  - o hover continua mostrando o card completo, por cima do palco;
  - o estado fica salvo por workspace, como `board.hideDone`.
- R6 · A pasta deve ter uma busca:
  - `/` ou `Ctrl+F` focam o campo quando o foco está no Quadro, fora de um campo de texto;
  - com a pasta recolhida, uma lupa ocupa o lugar do campo, e clicar nela ou usar o atalho abre a pasta e foca a busca;
  - os atalhos entram na folha de atalhos (`Ctrl+/`).
- R7 · A busca deve filtrar enquanto a pessoa digita:
  - compara número e título, sem diferenciar maiúsculas nem acentos;
  - o cabeçalho mostra "<n> de <total>";
  - o primeiro resultado fica ativo, expandido como no R4;
  - `↑`/`↓` mudam o resultado ativo, `Enter` abre no palco e `Esc` limpa a busca;
  - sem resultado, aparece `Nenhuma spec com "<texto>"`.
- R8 · Clicar numa spec deve levar a spec para o palco:
  - ela voa da pasta para o centro, crescendo até o card central, em `AppMotion.stage` (420 ms);
  - a spec que estava no centro volta para a pasta;
  - as linhas restantes fecham o espaço;
  - clicar numa dependente faz dela o novo centro.
- R9 · O palco deve mostrar abaixo da spec central todas as specs que dependem dela, direta ou indiretamente:
  - cada spec fica no nível do caminho mais longo a partir do centro;
  - os níveis descem de cima para baixo, com as specs do mesmo nível lado a lado;
  - as dependentes voam da pasta em cascata: 90 ms por nível e 45 ms por card;
  - sem dependentes, o palco mostra "Nenhuma spec depende de <código>".
- R10 · Cada dependência deve virar uma seta para baixo:
  - a linha se desenha depois que o card chega, e a ponta aparece no fim;
  - seta que liga níveis vizinhos é âmbar;
  - seta que pula um nível é cinza e contorna os cards do meio, sem passar por trás deles.
- R11 · O palco deve manter o que o Canvas tem hoje:
  - arrastar e dar zoom;
  - "Ajustar" enquadra o que está no palco;
  - quando os cards não couberem na janela, o palco enquadra todos ao abrir;
  - "Voltar à pasta" e `Esc` esvaziam o palco e devolvem as specs à pasta; com o painel de detalhes aberto (R18), `Esc` fecha primeiro o painel;
  - os cards do palco mantêm os balões das etapas, que abrem a etapa como hoje (SPEC-033), e o halo de "Precisa de você" (SPEC-030).
- R12 · O botão **Executando · <n>** deve mostrar as specs em execução no palco, lado a lado:
  - `<n>` conta as specs que têm uma sessão rodando ou uma etapa em andamento;
  - sem nenhuma, o botão fica desabilitado, com o aviso "Nenhuma spec em execução";
  - clicar de novo, "Voltar à pasta" ou `Esc` devolvem as specs à pasta;
  - clicar numa spec abre a spec no palco, com as dependentes.
- R13 · Cada card de **Executando** deve mostrar a etapa atual e atualizar sozinho:
  - "Etapa <n> de <total> · rodando", com a barra de atividade;
  - em "aguardando você", o card mostra o balão, e a barra para;
  - quando a spec sai de execução, o card volta para a pasta e a contagem cai.
- R17 · Acima do card central, o palco deve mostrar de quem a spec depende:
  - uma linha com "Depende de SPEC-030, SPEC-028", em que cada código é clicável e leva aquela spec ao centro;
  - sem dependências, a linha não aparece;
  - a árvore para cima não é desenhada: o palco continua mostrando só as dependentes.
- R18 · Clicar na spec que já está no centro deve abrir o painel lateral de detalhes que o Canvas já tem, com as mesmas ações. O palco se recentraliza no espaço que sobra.
- R14 · Com animações desligadas (`MediaQuery.disableAnimations`), tudo vai direto ao estado final: sem voo, sem desenho das setas, com o loading e a barra de atividade parados.
- R15 · As animações seguem a SPEC-034: só opacidade e transformação nos cards, sem bloquear clique ou teclado. Uma nova escolha interrompe a anterior e parte do estado atual.
- R16 · A visão deve funcionar no tamanho mínimo da janela (1100×700), sem estouro de layout.

## Fora do escopo

- Reordenar ou agrupar specs na pasta.
- Filtros por status além da busca e de "Executando".
- Mudar as Colunas do Quadro.
- Executar ou aprovar specs a partir da pasta.

## Design

### O que já existe

- `lib/features/board/widgets/spec_canvas.dart`: `SpecCanvas`, com `InteractiveViewer`, ondas (`dependencyWaves`, `nextWave`), `_SpecNode`, referências de agentes e skills da spec selecionada, botão "Atenção", "Ajustar" (`fitSelection`) e painel lateral (`_panelWidth`).
- `lib/features/board/board_screen.dart`: `boardGraphViewProvider` (Colunas ou Canvas), `boardHideDoneProvider` e `selectedSpecProvider`.
- `spec.dependsOn`: os códigos de que a spec depende.
- `lib/features/board/widgets/board_card_flight.dart`: o voo de card da SPEC-034.
- `lib/ui/theme/motion.dart`: `AppMotion`.
- `lib/ui/shell/shortcut_sheet.dart`: a folha de atalhos.
- `Ctrl+K` é a paleta de comandos, por isso a busca usa `/` e `Ctrl+F`, que hoje só valem nos editores.

### R1–R5 · Pasta

- `lib/features/board/widgets/spec_folder.dart`: `SpecFolder`. A lista é preguiçosa e usa `Scrollable`; o hover muda a altura do item com `AnimatedSize` só na lista da pasta, onde a mudança de layout é o próprio efeito.
- O card expandido reusa o conteúdo de `_SpecNode`, extraído para um widget próprio.
- Recolhida, o hover usa um `OverlayEntry` para o card passar por cima do palco.
- `boardFolderCollapsedProvider`, como `BoardHideDone`.
- `boardGraphViewProvider` hoje é um booleano e passa a ser um `enum` com colunas, grafo e foco, lendo o valor salvo antigo.

### R6, R7 · Busca

- `spec_folder_search.dart`: normaliza o texto sem acentos, com a mesma função da busca da paleta, se ela servir.
- O atalho é registrado no `Shortcuts` do Quadro e ignorado quando o foco primário é um `EditableText`.

### R8–R11 · Palco

- `lib/features/board/widgets/spec_stage.dart`: calcula as posições a partir de `dependsOn`, com a função pura `stageLayout(root, specs)` em `board_rules.dart`.
- `AppMotion.stage` (420 ms) é um token novo, para trajetos longos entre a pasta e o palco.
- O voo reusa a técnica de `board_card_flight.dart`, numa camada acima da pasta e do palco.
- As setas são um `CustomPainter` com `PathMetric.extractPath`, e o progresso vem de um `AnimationController`.

### R12, R13 · Executando

- A contagem vem das sessões vivas e de `spec_steps`, os mesmos dados do "3 agentes rodando" do Quadro.

### Branches

A branch pai é `spec/036-pasta-e-palco`. Cada tarefa tem sua branch e vira um PR com base na pai.

| Tarefa | Branch | Requisitos | Depende de |
|---|---|---|---|
| T1 · Visão Foco e pasta | `spec/036-t1-pasta` | R1–R5, R16 | — |
| T2 · Busca | `spec/036-t2-busca` | R6, R7 | T1 |
| T3 · Palco | `spec/036-t3-palco` | R8–R11, R14, R15, R17, R18 | T1 |
| T4 · Executando | `spec/036-t4-executando` | R12, R13 | T3 |

## Critérios de aceite

- [ ] O Quadro oferece Colunas, Grafo e Foco, e o Canvas de ondas não muda; a pasta lista as specs da mais nova para a mais antiga e respeita "Ocultar concluídas" [R1] verificar: flutter test test/features/board/spec_folder_test.dart
- [ ] Cada status tem o ícone e o rótulo acessível, e o balão tem prioridade [R2] verificar: flutter test test/features/board/spec_folder_test.dart
- [ ] A pasta mostra até 15 linhas e rola pela roda, pelas setas e pelo teclado; as setas desabilitam nas pontas; o foco rola até a linha [R3] verificar: flutter test test/features/board/spec_folder_test.dart
- [ ] O hover expande a linha sem cobrir as outras, inclusive a última [R4] verificar: flutter test test/features/board/spec_folder_test.dart
- [ ] Recolher mostra só ícone e número, recentraliza o palco e fica salvo por workspace [R5] verificar: flutter test test/features/board/spec_folder_test.dart
- [ ] `/` e `Ctrl+F` focam a busca, abrem a pasta recolhida e não valem dentro de um campo de texto [R6] verificar: flutter test test/features/board/spec_folder_search_test.dart
- [ ] A busca ignora acentos e maiúsculas, mostra "<n> de <total>", navega com as setas, abre com `Enter` e limpa com `Esc` [R7] verificar: flutter test test/features/board/spec_folder_search_test.dart
- [ ] Clicar leva a spec ao centro e devolve a anterior à pasta [R8] verificar: flutter test test/features/board/spec_stage_test.dart
- [ ] `stageLayout` põe cada dependente no nível do caminho mais longo, inclusive com dependência que pula um nível [R9] verificar: flutter test test/features/board/spec_stage_test.dart
- [ ] As setas ligam cada dependência, e a que pula um nível contorna os cards do meio [R10] verificar: flutter test test/features/board/spec_stage_test.dart
- [ ] Zoom, Ajustar, Esc, balões das etapas e halo continuam funcionando no palco [R11] verificar: flutter test test/features/board/spec_stage_test.dart
- [ ] "Executando" mostra as specs em execução, com a contagem certa, e fica desabilitado sem nenhuma [R12] verificar: flutter test test/features/board/spec_stage_running_test.dart
- [ ] O card atualiza a etapa, mostra o balão ao aguardar e volta à pasta ao sair de execução [R13] verificar: flutter test test/features/board/spec_stage_running_test.dart
- [ ] A linha "Depende de" lista as dependências, cada código leva a spec ao centro, e ela some sem dependências [R17] verificar: flutter test test/features/board/spec_stage_test.dart
- [ ] Clicar na spec central abre o painel de detalhes, e `Esc` fecha o painel antes do palco [R18] [R11] verificar: flutter test test/features/board/spec_stage_test.dart
- [ ] Com animações desligadas, tudo vai direto ao estado final [R14] verificar: flutter test test/features/board/spec_stage_test.dart
- [ ] Clique e teclado valem durante o voo, e uma nova escolha parte do estado atual [R15] verificar: flutter test test/features/board/spec_stage_test.dart
- [ ] Em 1100×700 não há estouro de layout [R16] verificar: flutter test test/features/board/spec_stage_test.dart
- [ ] Os testes atuais do quadro continuam passando [R11] verificar: flutter test test/features/board

## Decisões

- D1 · O protótipo usa uma altura fixa de 15 linhas, mas a janela mínima do app tem 700 px. A pasta mostra até 15 linhas e, em janela menor, as que couberem (R3).
- D2 · A busca usa `/` e `Ctrl+F` porque `Ctrl+K` já é a paleta de comandos.
- D3 · No hover, a linha sempre cresce para baixo e empurra as vizinhas. Crescer para cima, testado no protótipo, cobria as linhas de baixo e impedia de alcançá-las.
- D5 · O Foco convive com o Canvas de ondas, como terceira opção: **Colunas · Grafo · Foco**. O Canvas é a única visão de todas as specs juntas e mostra agentes e skills da spec selecionada. Se o Foco for mais usado, ele pode virar o padrão depois (P1).
- D6 · O palco mostra de quem a spec depende numa linha clicável acima do card central, sem desenhar a árvore para cima, para não tirar o foco e o espaço das dependentes (P2).
- D7 · Clicar na spec central abre o painel lateral que o Canvas já tem. O protótipo não mostra esse painel nem a linha do D6 (P3).
- D4 · No app, o texto "Em execução" hoje é laranja; o protótipo usa amarelo. Esta spec segue o protótipo só no ícone de loading da pasta e nos cards do palco.

- D8 · A escolha da visão fica em memória durante a sessão, como já era: não havia valor salvo para ler, e a visão volta a Colunas ao reabrir o app (R1).
- D9 · O widget do palco se chama `FocusStage`, porque `SpecStage` já é o enum das colunas. O arquivo continua `spec_stage.dart`.
- D10 · O card da pasta recolhida usa `OverlayPortal`, como `CanvasDetailCard`, em vez de um `OverlayEntry` manual (R5).
- D11 · O botão "Canvas" do Quadro passa a se chamar "Grafo", como no R1.
- D12 · As setas de rolagem da pasta ficam fora da ordem do `Tab`: o teclado já rola com `↑`/`↓`, e a parada na seta interrompia a passagem pelas linhas (R3).

## Perguntas em aberto

Nenhuma.
