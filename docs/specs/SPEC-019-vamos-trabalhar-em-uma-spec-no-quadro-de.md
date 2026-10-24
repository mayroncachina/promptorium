---
id: SPEC-019
status: concluida
depende-de: [SPEC-015]
---

# Ocultar specs concluídas e marcar spec como finalizada (Quadro/Canvas)

> Rascunho gerado a partir de uma conversa do Prompt em 2026-10-22.

## Objetivo

No Quadro (views Colunas e Canvas), as specs concluídas continuam ocupando espaço e atrapalham a leitura do que ainda está em andamento. Além disso, não existe um jeito manual de marcar uma spec como finalizada: hoje `setStage`/`setStatus` só alteram o banco, e o `sync` reverte a mudança ou avisa.

Esta spec entrega:

1. um controle para ocultar as specs concluídas, lembrado por projeto e válido nas duas views;
2. uma ação no inspetor do canvas para marcar uma spec como finalizada e para reabri-la, sem que o `sync` desfaça a escolha.

## Conversa (resumo)

**Resposta:**

# Plano — Ocultar specs concluídas e marcar spec como finalizada (Quadro/Canvas)

## Context
No Quadro (views Colunas e Canvas) as specs em Feito/concluídas continuam ocupando espaço. Queremos (1) um botão para ocultá-las, lembrado por projeto, e (2) uma ação no inspetor do canvas para marcar uma spec como finalizada (e reabrir). Hoje não há "marcar concluída" manual: `setStage`/`setStatus` só mexem no banco e o `sync` reverte ou avisa. Deve virar uma nova spec (SPEC-019) em `docs/specs/` + implementação.

Trabalhar na branch `teste` (nunca na main); commits sem Co-Authored-By.

## Parte A — Ocultar concluídas
- `lib/data/repos/app_settings_repo.dart`: nova chave em `AppSettingKeys`, por projeto (`board.hideDone.<workspaceId>`).
- `lib/features/board/board_screen.dart`:
  - novo `BoardHideDone` notifier persistido (padrão de `lib/ui/shell/editor_zoom.dart`: lê `appSettingsProvider` no `build`, grava com `.set`), observando o workspace ativo.
  - em `visible` (~:263) acrescentar `(!hideDone || d.spec.stage != SpecStage.done)`; vale para Colunas e Canvas, pois ambos recebem `visible`.
  - chip "Ocultar concluídas · N" em `_Header` (~:420, helper `chip`, `ValueKey('board-filter-hide-done')`); N = quantas estão ocultas.
  - estado vazio: quando só restam concluídas ocultas, mensagem própria com ação "Mostrar concluídas" (hoje: "Nenhum cartão passa pelos filtros.").
- `lib/features/board/widgets/spec_canvas.dart` (barra flutuante ~:455, junto de "Camadas"): `_BarButton` toggle `Va …

## Requisitos

- R1 · Quando "Ocultar concluídas" estiver ativo, o sistema deve excluir das views Colunas e Canvas todos os cartões cuja spec esteja em `SpecStage.done`.
- R2 · Quando "Ocultar concluídas" estiver desativado, o sistema deve exibir os cartões concluídos normalmente, respeitando os demais filtros.
- R3 · Quando o usuário alternar "Ocultar concluídas", o sistema deve gravar a preferência na chave `board.hideDone.<workspaceId>` do projeto ativo.
- R4 · Quando o app for reaberto ou o workspace ativo mudar, o sistema deve restaurar a preferência gravada para aquele projeto, sem afetar a de outros projetos; sem valor gravado, o padrão é desativado (concluídas visíveis).
- R5 · O sistema deve mostrar no cabeçalho do Quadro o chip "Ocultar concluídas · N" (`ValueKey('board-filter-hide-done')`), em que N é o número de specs concluídas ocultas depois dos demais filtros (atenção, fase, agente).
- R6 · Quando não restar nenhum cartão visível e houver concluídas ocultas pelo filtro, o sistema deve exibir uma mensagem própria com a ação "Mostrar concluídas", em vez de "Nenhum cartão passa pelos filtros.".
- R7 · O sistema deve oferecer, na barra flutuante do Canvas (junto de "Camadas"), o botão "Concluídas" (`ValueKey('canvas-hide-done')`, ícone `visibility` / `visibility_off`) que alterna o mesmo estado de "Ocultar concluídas" do cabeçalho.
- R8 · Quando o usuário acionar "Marcar como finalizada" no inspetor do canvas sobre uma spec não concluída, o sistema deve gravar `status: concluida` no frontmatter do arquivo, guardar ali o estágio e o status anteriores e passar a spec para `SpecStage.done` / `SpecStatus.done` no banco. Com critérios de aceite pendentes, o sistema deve avisar quantos faltam e pedir confirmação antes de finalizar.
- R9 · Quando o usuário acionar "Reabrir" no inspetor sobre uma spec finalizada, o sistema deve devolvê-la ao estágio e ao status guardados na finalização (sem nada guardado: primeiro estágio de trabalho, `backlog`, e `aprovada`), gravando o status no frontmatter.
- R10 · Quando o `sync` rodar depois de uma finalização ou reabertura manual, o sistema deve preservar a escolha do usuário, sem revertê-la e sem exibir aviso de divergência.

## Decisões

- **Reabrir volta ao estágio anterior.** "Marcar como finalizada" grava no frontmatter `estagio-anterior` (nome do `SpecStage`) e `status-anterior` (valor do status, ex.: `aprovada`). "Reabrir" lê esses campos, remove-os do arquivo e restaura estágio e status; sem eles, usa `backlog` e `aprovada`. Não há migração de schema: o estágio anterior fica no arquivo da spec.
- **O arquivo é a fonte da verdade.** A finalização grava `status: concluida` no frontmatter e no banco. O `sync` já trata `concluida` no arquivo como conclusão (leva a spec a Feito) e um status de trabalho com a spec fora de Feito como estado normal; como finalizar e reabrir sempre escrevem o arquivo antes de atualizar o banco, o `sync` não encontra divergência a corrigir nem a avisar. As duas ações passam pela mesma fila do `sync`, para não intercalar com uma sincronização em curso.
- **Critérios pendentes não bloqueiam.** Finalizar com critérios sem marcar mostra "N critérios sem marcar. Finalizar mesmo assim?" e só segue com a confirmação.
- **Finalizar recusa operação em andamento** (execução, revisão, worktree ou sessão ativa), como `reopen` e `archive`.
- **Padrão sem preferência gravada:** concluídas visíveis.
- **N do chip:** conta as concluídas ocultas depois dos demais filtros.
- **Escopo da ação:** finalizar/reabrir só no inspetor do canvas nesta versão (o "Reabrir" da tela Specs passa a usar o mesmo estágio guardado).
- **Botão do Canvas:** rótulo "Concluídas", ícone de olho (`visibility` quando visíveis, `visibility_off` quando ocultas), no estilo de `_BarButton` como as camadas: ativo = concluídas visíveis.
- `dependencyWaves` e `isOnBoard` não mudam: as ondas do cabeçalho continuam calculadas com todos os cartões. No Canvas, com as concluídas ocultas, as colunas de onda se reorganizam só com os cartões visíveis.
- O chip mostra "· N" só com o filtro ativo (desativado, nada está oculto).
- "Marcar como finalizada" aparece em specs no Backlog; "Reabrir" em specs em Feito. Specs rodando ou em Review não mostram nenhuma das duas (terminam pelo próprio fluxo).
- Com o chip novo, o texto "N em rascunho fora do quadro" do cabeçalho encolhe com reticências (tooltip com o texto completo) quando falta espaço.

## Critérios de aceite

- [x] [R1] Com o filtro ativo e uma spec em Feito, ela não aparece nem em Colunas nem no Canvas. verificar: `flutter test test/features/board`
- [x] [R2] Com o filtro desativado, a mesma spec volta a aparecer nas duas views. verificar: `flutter test test/features/board`
- [x] [R3] Alternar o filtro grava `board.hideDone.<workspaceId>` com o valor esperado. verificar: `flutter test test/data`
- [x] [R4] Ativar o filtro no projeto A e abrir o projeto B mostra B sem filtro; voltar para A restaura o filtro ativo. verificar: `flutter test test/features/board`
- [x] [R5] O chip exibe "Ocultar concluídas · N" com N igual ao número de concluídas ocultas, e N muda quando uma spec é finalizada ou reaberta. verificar: `flutter test test/features/board`
- [x] [R6] Com o filtro ativo e só concluídas no projeto, aparece a mensagem própria e "Mostrar concluídas" desativa o filtro. Sem concluídas ocultas, a mensagem continua "Nenhum cartão passa pelos filtros.". verificar: `flutter test test/features/board`
- [x] [R7] O botão da barra flutuante do Canvas e o chip do cabeçalho refletem o mesmo estado: alternar um atualiza o outro. verificar: `flutter test test/features/board`
- [x] [R8] "Marcar como finalizada" no inspetor grava `status: concluida`, `estagio-anterior` e `status-anterior` no arquivo, leva a spec a `done` no banco e ela aparece em Feito; com critérios pendentes, pede confirmação e cancelar não altera nada. verificar: `flutter test test/features/board test/features/specs`
- [x] [R9] "Reabrir" numa spec finalizada a devolve ao estágio e status guardados (ou `backlog`/`aprovada` sem nada guardado) e remove os campos do arquivo; a ação não aparece em specs não finalizadas. verificar: `flutter test test/features/board test/features/specs`
- [x] [R10] Rodar o `sync` após finalizar ou reabrir manualmente não altera o estágio/status escolhido e não gera aviso. verificar: `flutter test test/features/specs`
- [x] [R1–R10] A suíte completa passa e `flutter analyze` não reporta problemas novos. verificar: `flutter analyze && flutter test`
