---
id: SPEC-042
status: aprovada
depende-de: SPEC-036
---

# Sprints no Quadro

## Objetivo

O Quadro mostra todas as specs do workspace ao mesmo tempo. Com dezenas delas, as colunas viram listas longas, o Grafo fica cheio e a pasta do Foco exige rolagem. A pessoa perde de vista o que está planejado para agora.

Esta spec agrupa as specs em **sprints**. Um seletor no Quadro escolhe a sprint, e Colunas, Grafo e Foco mostram só as specs dela. Por padrão, o Quadro abre na sprint ativa.

A sprint aqui é um agrupamento de trabalho, sem prazo obrigatório. Ela separa as specs, mas nunca esconde o que precisa de atenção: pendências de outras sprints continuam visíveis em Início, na bandeja e em um aviso no próprio Quadro.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/N298EZ3f2z3VizDZ18sM31). Cópia dos quadros e capturas em `docs/mockups/spec-042/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-colunas.png` | Colunas na sprint ativa, com o aviso de pendências | R2, R6, R9 |
| `2-seletor.png` | Seletor aberto, com progresso e ações | R2, R3, R4 |
| `3-grafo.png` | Ondas da sprint e dependências de outras sprints | R7, R11 |
| `4-foco.png` | Pasta e palco na sprint | R8 |
| `5-foco-todas.png` | Pasta em "Todas", com seções recolhíveis | R8 |
| `6-organizar.png` | Mover várias specs, com o aviso de dependência | R5, R12 |
| `7-concluir.png` | Concluir sprint | R10 |
| `8-primeira-sprint.png` | Criar a primeira sprint | R4, R13 |
| `9-busca-sem-resultado.png` | Busca sem resultado na sprint, com "Buscar em todas" | R8 |
| `10-mover-para-sprint.png` | "Mover para sprint" no menu do card | R5 |
| `11-desfazer.png` | Aviso com "Desfazer" depois de mover a spec | R5 |

## Requisitos

- R1 · O workspace deve poder ter sprints:
  - cada sprint tem nome, objetivo opcional e posição na lista;
  - o estado é **Planejada**, **Ativa** ou **Concluída**;
  - cada workspace tem no máximo uma sprint Ativa;
  - uma spec pertence a uma sprint ou a nenhuma ("Sem sprint").
  - uma spec recém-aprovada entra em "Sem sprint".
- R2 · O cabeçalho do Quadro deve ganhar um seletor de sprint, que vale para Colunas, Grafo e Foco:
  - as opções são as sprints Ativa e Planejadas, depois "Sem sprint" e "Todas";
  - as sprints Concluídas ficam em um submenu no fim da lista;
  - a escolha fica salva por workspace, como `board.hideDone`;
  - sem escolha salva, o Quadro abre na sprint Ativa e, sem ela, em "Todas";
  - se a sprint salva não existir mais, o Quadro abre na sprint Ativa ou em "Todas".
- R3 · Cada opção do seletor deve mostrar o progresso da sprint:
  - specs feitas e total: `5 de 8`;
  - quantas estão em execução;
  - quantas aguardam a pessoa, com o balão da SPEC-030.
- R4 · O seletor deve oferecer "Nova sprint", e cada sprint deve poder ser editada e excluída:
  - o nome sugerido é o próximo número livre: `Sprint 4`;
  - criar a primeira sprint a torna Ativa; as seguintes nascem Planejadas;
  - "Ativar" em uma sprint Planejada troca a Ativa, que volta a Planejada;
  - excluir pede confirmação, informa quantas specs serão afetadas e deixa essas specs em "Sem sprint", sem apagar nenhuma.
- R5 · A pessoa deve poder mover specs entre sprints:
  - o menu do card ganha "Mover para sprint", com as sprints não concluídas e "Sem sprint", e a sprint atual aparece desabilitada;
  - "Organizar sprints", no seletor, abre um diálogo com a lista de specs, busca, seleção múltipla e destino, para distribuir muitas specs de uma vez. `/` e `Ctrl+F` focam a busca do diálogo;
  - mover não altera coluna, etapas nem execução da spec;
  - uma spec que acabou de sair da sprint visível some da tela com um aviso que tem "Desfazer".
- R6 · A visão **Colunas** deve mostrar só as specs da sprint escolhida. Em "Todas", ela fica como hoje.
- R7 · A visão **Grafo** deve calcular as ondas só com as specs da sprint escolhida:
  - uma dependência em outra sprint aparece como um nó esmaecido, com código e nome da sprint, ligado por seta tracejada;
  - clicar nesse nó troca o seletor para a sprint dele e seleciona a spec;
  - em "Todas", o Grafo fica como hoje.
- R8 · A visão **Foco** deve mostrar na pasta só as specs da sprint escolhida:
  - o cabeçalho da pasta conta as specs da sprint;
  - em "Todas", a pasta agrupa as specs em seções recolhíveis, na ordem do seletor: Ativa, Planejadas, "Sem sprint" e Concluídas;
  - o palco mostra as dependentes de outras sprints com o nome da sprint no card;
  - uma busca sem resultado na sprint mostra quantas specs casam em outras sprints e oferece "Buscar em todas", também por `Enter`;
  - `/` e `Ctrl+F` continuam focando a busca (SPEC-036 R6), e o campo mostra `/`;
  - os atalhos novos entram na folha de atalhos (`Ctrl+/`).
- R9 · Separar não pode esconder pendências:
  - havendo specs de outras sprints aguardando a pessoa, o Quadro mostra um aviso com a quantidade, como `2 em outras sprints precisam de você`;
  - clicar no aviso abre "Todas" com o filtro de atenção ligado;
  - Início, a bandeja e as notificações continuam mostrando tudo, sem filtro de sprint;
  - abrir uma spec de outra sprint por qualquer caminho (Início, paleta, notificação, bandeja) troca o seletor para a sprint dela, para que a spec apareça.
- R10 · A sprint Ativa deve poder ser concluída por "Concluir sprint":
  - o diálogo resume specs feitas e não feitas;
  - as não feitas vão para o destino escolhido, com a próxima Planejada sugerida, ou para "Sem sprint";
  - specs em execução são movidas sem interromper a execução;
  - a sprint concluída mantém as specs feitas e pode ser consultada, sem aceitar novas specs;
  - a próxima sprint Planejada não é ativada sozinha: o diálogo oferece "Ativar a próxima".
- R11 · Com uma sprint Ativa, o Autopilot deve iniciar apenas specs dela:
  - uma dependência fora da sprint e ainda não feita bloqueia a spec, e o motivo aparece no card;
  - o Autopilot nunca puxa uma spec de outra sprint para destravar a Ativa;
  - sem sprint Ativa, ele se comporta como hoje;
  - executar uma spec manualmente continua possível em qualquer sprint.
- R12 · Mover uma spec para uma sprint anterior às suas dependências não feitas deve mostrar um aviso, sem impedir a mudança: `SPEC-012 depende de SPEC-030, na Sprint 5`.
- R13 · Quem não usa sprints não deve notar diferença:
  - depois da migração, toda spec fica em "Sem sprint";
  - sem nenhuma sprint, o Quadro abre em "Todas" e o seletor mostra só "Sprints" e "Nova sprint";
  - os filtros atuais (atenção, fase, agente) e "Ocultar concluídas" se somam ao seletor.

## Fora do escopo

- Datas, duração, velocidade e gráfico de burndown.
- Raias de sprint dentro das Colunas.
- Arrastar card para trocar de sprint.
- Sprint em mais de um workspace.
- Sprints criadas pelo planejador do Projeto ou a partir de `fase`.
- Filtro de sprint em Início, Review, Sessões e na bandeja.

## Design

### O que já existe

- `lib/features/board/board_screen.dart`: a lista `visible` alimenta as três visões (`_Board`, `SpecCanvas`, `SpecFocusView`), depois dos filtros de atenção, fase, agente e `boardHideDoneProvider`. É nesse ponto que o filtro entra.
- `_Header` (mesmo arquivo) tem os filtros e a troca de visão. `_CardMenu` é o menu do card.
- `SpecFocusView` já recebe `cards` e `all`, e `SpecFolder` recebe a lista de cards.
- `SpecCanvas` desenha setas a partir de `dependsOn` e já convive com specs ocultas por "Ocultar concluídas".
- `lib/features/board/autopilot.dart` lê todas as specs do workspace em `specs.watchByWorkspace`.
- `Specs` guarda `fase` (`phase`), que vem do frontmatter. Fase e sprint são independentes.
- `AppSettingKeys.boardHideDone(workspaceId)` é o modelo para salvar a escolha por workspace.

### Dados

- Nova tabela `Sprints`: `id`, `workspaceId` (cascade), `name`, `goal` (nullable), `state`, `position`, `closedAt` (nullable).
- `Specs.sprintId`: nullable, referencia `Sprints` com `onDelete: setNull`.
- Migração para o próximo `appSchemaVersion`, com o backup `.bak-v<N>` de sempre.
- A regra de "no máximo uma Ativa" fica em uma transação do `SprintsRepo`.
- A leitura do arquivo da spec atualiza a linha sem tocar em `sprintId`.

### Componentes

- `lib/features/board/sprint_rules.dart` (novo): funções puras para filtrar por seleção, calcular progresso, dependências fora da sprint e destino padrão ao concluir.
- `lib/data/repos/sprints_repo.dart` (novo), com `sprintsProvider(workspaceId)`.
- `boardSprintProvider`, no modelo de `boardHideDoneProvider`. A seleção é uma sprint, "Sem sprint" ou "Todas".
- `lib/features/board/widgets/sprint_selector.dart` (novo), no `_Header`.
- `lib/features/board/widgets/sprint_dialogs.dart` (novo): criar e editar, organizar, concluir.
- `SpecCanvas` recebe as specs de outras sprints para desenhar os nós esmaecidos (R7).
- `SpecFolder` ganha seções por sprint em "Todas" (R8).
- `Autopilot`: o filtro entra logo depois de `watchByWorkspace` (R11).
- `boardSelectedSpecProvider`: ao selecionar uma spec fora da sprint visível, o seletor acompanha (R9).

### Testes

- `test/features/board/sprint_rules_test.dart`: filtro, progresso, dependências, destino.
- `test/data/sprints_repo_test.dart`: uma Ativa só, exclusão com `setNull`, migração.
- `test/features/board/sprint_selector_test.dart`: seletor, padrão, persistência, aviso de pendências.
- Testes das três visões e do Autopilot com sprints.

## Decisões

- **Sprint não tem prazo.** O pedido é separar as specs; datas e métricas trariam regras que ninguém pediu.
- **Quadro em filtro único.** Um seletor compartilhado evita três formas de agrupar e mantém o que a pessoa escolheu ao trocar de visão.
- **O Autopilot segue a sprint Ativa, não a sprint visível.** Olhar outra sprint não pode mudar o que roda.
- **Pendências atravessam a separação.** Início, bandeja e notificações ignoram o seletor.
- **Sprints no banco local.** Mover uma spec é instantâneo e não gera mudança no git nem conflito com worktrees em execução. O custo aceito é não acompanhar o repositório em outra máquina.
- **Spec recém-aprovada entra em "Sem sprint".** A sprint não cresce sem planejamento, e o seletor mostra a contagem para ela não passar despercebida.
- **Atalhos da busca só no Foco.** Colunas e Grafo não têm campo de busca, e levar a pessoa ao Foco por um atalho mudaria a tela de repente.
- **Conclusão não ativa a próxima sozinha.** Ativar pode iniciar o Autopilot em outro lote de specs, então a escolha é explícita.

## Plano

1. Validar o mockup (tabela no início da spec).
2. Dados: tabela, migração, repositório e regras.
3. Seletor, criação e movimentação, com Colunas filtrada.
4. Grafo e Foco.
5. Concluir sprint, Autopilot e aviso de pendências.
6. Guia e `docs/debito-tecnico.md`, se sobrar algum item.

## Critérios de aceite

- [ ] Um workspace não fica com duas sprints Ativas [R1] verificar: flutter test test/data/sprints_repo_test.dart
- [ ] O seletor filtra Colunas, Grafo e Foco, e a escolha sobrevive a reabrir o app [R2, R6] verificar: flutter test test/features/board/sprint_selector_test.dart
- [ ] Sem escolha salva, o Quadro abre na Ativa; sprint salva que sumiu cai na Ativa ou em "Todas" [R2] verificar: flutter test test/features/board/sprint_selector_test.dart
- [ ] O seletor mostra feitas, total, em execução e aguardando [R3] verificar: flutter test test/features/board/sprint_rules_test.dart
- [ ] A primeira sprint nasce Ativa e as seguintes, Planejadas [R4] verificar: flutter test test/data/sprints_repo_test.dart
- [ ] Excluir uma sprint deixa as specs em "Sem sprint", sem apagar nenhuma [R4] verificar: flutter test test/data/sprints_repo_test.dart
- [ ] Mover uma spec não altera coluna, etapas nem execução, e "Desfazer" devolve [R5] verificar: flutter test test/features/board/sprint_selector_test.dart
- [ ] "Organizar sprints" move várias specs de uma vez, e `/` e `Ctrl+F` focam a busca dele [R5] verificar: flutter test test/features/board/sprint_selector_test.dart
- [ ] O Grafo calcula as ondas só com a sprint e mostra a dependência externa esmaecida [R7] verificar: flutter test test/features/board/canvas_view_test.dart
- [ ] Clicar no nó externo troca a sprint e seleciona a spec [R7] verificar: flutter test test/features/board/canvas_view_test.dart
- [ ] A pasta do Foco mostra a sprint e, em "Todas", seções recolhíveis [R8] verificar: flutter test test/features/board/spec_folder_test.dart
- [ ] Busca sem resultado oferece "Buscar em todas", também por `Enter` [R8] verificar: flutter test test/features/board/spec_folder_test.dart
- [ ] Pendência de outra sprint gera o aviso, e o clique abre "Todas" com o filtro de atenção [R9] verificar: flutter test test/features/board/sprint_selector_test.dart
- [ ] Início e a bandeja ignoram o seletor [R9] verificar: flutter test test/features/home
- [ ] Abrir uma spec de outra sprint troca o seletor [R9] verificar: flutter test test/features/board/sprint_selector_test.dart
- [ ] Concluir move as não feitas sem parar execução e não ativa a próxima sozinha [R10] verificar: flutter test test/features/board/sprint_rules_test.dart
- [ ] Com sprint Ativa, o Autopilot só inicia specs dela e mostra o motivo do bloqueio [R11] verificar: flutter test test/features/board/autopilot_test.dart
- [ ] Mover antes de uma dependência não feita mostra o aviso e permite a mudança [R12] verificar: flutter test test/features/board/sprint_rules_test.dart
- [ ] Workspace sem sprints abre em "Todas", sem mudança nas visões [R13] verificar: flutter test test/features/board
- [ ] A migração preserva as specs e deixa todas em "Sem sprint" [R13] verificar: flutter test test/data/sprints_repo_test.dart
- [ ] O projeto compila e a análise estática passa [R1–R13] verificar: flutter analyze
