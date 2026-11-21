---
id: SPEC-095
status: concluida
versao: 0.23.0
tipo: melhoria
epico: 332
issue: 335
depende-de: [SPEC-093, SPEC-087]
---

# Eventos neutros

## Objetivo

A timeline, os cartões de edição, as mudanças da sessão, o Replay, as Atividades e o medidor de contexto entendem um único vocabulário: o stream-json do Claude Code. O adaptador do Codex **finge** esse formato, e onde os conceitos não batem, a tela quebra em silêncio.

Exemplo concreto: numa sessão Codex, o agente altera `lib/features/cost/usage_ledger.dart`. O App Server manda um item `fileChange` com `changes: [{path, kind: {type: "update"}, diff: "@@ -12,7 +12,9 @@ …"}]`. O `CodexRun` traduz isso para um `tool_use` chamado `Edit` com `input: {changes: […]}`. Só que `edit_diff.dart`, `timeline.dart`, `session_manager.dart` e `replay_step.dart` procuram `file_path`, `old_string` e `new_string`. O resultado:

- o cartão aparece como "Edit" sem arquivo e sem diff;
- "Arquivos citados" do painel Contexto, a última ação e o "Neste turno: N arquivos" das Atividades ficam vazios;
- o Replay não sabe qual arquivo mudou naquele passo.

O mesmo vale para comandos (`commandExecution` vira um `Bash` sem `exitCode`) e para o uso de tokens, que chega como um `result` com `usage` montado à mão, sem a janela do modelo (`modelContextWindow`) que o Codex informa.

Esta spec cria **tipos neutros** para o que não bate (arquivo, comando, contexto, cota) e faz todos os consumidores lerem esses tipos. As classes atuais de `agent_event.dart` continuam como língua franca para o resto, e o histórico salvo do Claude continua sendo lido sem migração.

## Requisitos

### Tipos neutros

- R1 · **`FileChangeEvent`.** Um evento por arquivo alterado: `path`, `kind` (`add`, `update`, `delete`, `move` com `fromPath`), `unifiedDiff`, `before` e `after` quando conhecidos, `toolUseId`, `status` (proposto, aplicado, recusado, falhou) e `provider`. Do Codex, sai de cada item de `fileChange.changes[]`. Do Claude, sai de `Edit`, `MultiEdit`, `Write` e `NotebookEdit` na leitura, sem mudar o que já está salvo.
- R2 · **`CommandEvent`.** `command`, `cwd`, `exitCode`, `output` (cortado no mesmo limite de hoje), `durationMs`, `status` e `provider`. Do Codex, sai de `commandExecution`. Do Claude, de `Bash` + o `tool_result` correspondente.
- R3 · **Contexto alinhado à SPEC-087.** Um evento `ContextUsageEvent` (`tokens`, `input`, `cacheWrite`, `cacheRead`, `window`, `model`, `source`, `at`) e um `CompactionEvent` (`phase`: iniciada, concluída, falhou; `trigger`: auto ou manual; `preTokens`/`postTokens` quando informados). O `ContextTracker` passa a aceitar esses eventos além do caminho atual do Claude, e cada um vira o mesmo `ContextReading` e `ContextMarker` do contrato de medição (R1 da SPEC-087). Nada no contrato fica com nome ou campo do Claude: `ContextReading` ganha `source` (`claude-usage`, `codex-tokenUsage`) e a capacidade vem do agente (`modelContextWindow` no Codex).
- R4 · **Fórmula do Codex.** O contexto atual do Codex é calculado de `thread/tokenUsage/updated.last` com a fórmula comprovada pela SPEC-093 (R14), escrita no código com a referência ao relatório. Uma leitura substitui a anterior, como no Claude; `total` nunca vira contexto (é acumulado e vai para o ledger). `thread/compacted` vira `CompactionEvent` concluída, e a leitura corrente fica "aguardando medição" até o próximo `tokenUsage`.
- R5 · **`QuotaEvent`.** `provider`, `windows` (cada uma com `id`, rótulo, `usedPercent`, `resetsAt`, duração em minutos), `plan`, `reached` (tipo de limite atingido) e `at`. O `rate_limit_event` do Claude e o `account/rateLimits/updated` do Codex viram esse tipo. A SPEC-097 é quem lê e mostra.
- R6 · **Item desconhecido não some.** Um item do Codex sem tradução (`webSearch` com formato novo, `plan`, `hookPrompt`…) vira um `OtherItemEvent` com o tipo e um resumo de uma linha, mostrado recolhido na timeline. Hoje o adaptador descarta.

### Adaptadores

- R7 · **O Codex para de fingir.** O `CodexRun` emite os tipos neutros para arquivo, comando, contexto, compactação e cota, e não emite mais `tool_use` chamado `Edit` ou `Bash`. Mensagens, raciocínio, MCP e pedidos de aprovação continuam no vocabulário atual, porque já batem.
- R8 · **O Claude converte na leitura.** Um conversor único (`claude_neutral.dart`) transforma `Edit`/`Write`/`MultiEdit`/`NotebookEdit`/`Bash` e o `usage` das chamadas nos tipos neutros, ao vivo e ao reabrir. O formato gravado do Claude não muda.

### Consumidores

- R9 · **Quem passa a ler os tipos neutros:** `edit_diff.dart` e os cartões de edição da timeline; `timeline.dart` (rótulos e contagens); `session_manager.dart` (chamadas e arquivos do turno, SPEC-076 R3; o painel "Arquivos alterados" continua vindo do git e não muda); `replay_step.dart` e `file_at_step.dart` (o "antes" do Codex sai do diff, sem ler arquivo de sessão do Codex); `context_sources.dart` (arquivos citados ou lidos); `activities/activity.dart` (última ação e pose do robô); `home_inbox.dart`; `managed_hooks` e o vigia de segredos pós-turno, quando inspecionam o comando.
- R10 · **Mesma tela para o Claude.** Para uma sessão do Claude, a timeline, o Replay e as Atividades ficam idênticos às de hoje. Os testes de widget atuais passam sem ajuste de expectativa.

### Persistência

- R11 · **Sem migração.** `session_events` continua guardando o JSON de cada evento com o `provider`. Os eventos neutros do Codex são gravados como eventos do app versionados (`{"type":"promptorium_file_change","v":1,…}`, idem `command`, `context_usage`, `compaction`, `quota`), sanitizados pelo `redactJson`. Eventos antigos do Codex gravados no formato fingido (só existiram em testes e no período antes do desligamento) continuam abrindo pelo caminho atual.
- R12 · **Diff grande.** Um `unifiedDiff` acima de um limite (P3) é gravado cortado com a marca "diff cortado: N linhas", e o cartão oferece abrir o arquivo. O Replay usa o diff inteiro enquanto a sessão estiver viva e o cortado ao reabrir.

## Fora do escopo

- Religar o Codex em alguma tela (SPEC-096). Esta spec é testada com as fixtures da SPEC-093 e o `fake_codex`.
- Mostrar a cota no rodapé (SPEC-097) e o "Compactar agora" do Codex (SPEC-107).
- Reescrever todo o `agent_event.dart` em formato neutro (decisão do plano: só onde não bate).
- Ler os arquivos `~/.codex/sessions/*/rollout-*.jsonl`. O que faltar vem pela RPC (`thread/items/list`) na SPEC-110.
- Renomear a coluna `conversations.claudeSessionId`.

## Decisões em aberto

- P1 · **Onde convertem os eventos do Claude.** (a) No parse (`AgentEvent.expand` já devolve neutros); (b) num conversor chamado por quem consome. **Decidido:** (a). A conversão do Claude fica num lugar só (`claude_neutral.dart`), chamada pelo parse: o `ToolUseBlock` já traz `fileChanges`/`command`, o `AssistantMessage` traz `contextUsage` e o `RateLimit` traz `quota`. Os consumidores deixam de conhecer nomes de ferramenta do Claude.
- P2 · **Nome do tipo gravado.** `promptorium_file_change` (prefixo do app, como o `promptorium_run` da SPEC-087) ou `file_change`. **Decidido:** o prefixo `promptorium_` (`promptorium_file_change`, `promptorium_command`, `promptorium_context_usage`, `promptorium_compaction`, `promptorium_quota`, `promptorium_other_item`), para nunca colidir com um tipo futuro do Claude.
- P3 · **Limite do diff gravado.** **Decidido:** 2.000 linhas ou 256 KB por evento, o que vier antes. O mesmo limite vale para a saída de comando gravada.
- P4 · **`before`/`after` do Codex.** O Codex manda só o diff. **Decidido:** não guardar conteúdo inteiro; o Replay reconstrói o "antes" aplicando o diff ao contrário sobre o arquivo do passo seguinte, e mostra "conteúdo anterior indisponível" se o diff não aplicar.
- P5 · **Cota no stream da sessão.** `QuotaEvent` é gravado na sessão ou só repassado ao rodapé? **Decidido:** só repassado. O `QuotaEvent` não é gravado em `session_events`; a SPEC-097 persiste a última leitura em `app_settings`.

## Design

### O que já existe

- `lib/core/providers/agent_event.dart`: `AgentEvent` *sealed* (stream-json); `ClaudeEvent` é só um `typedef`.
- `lib/core/codex/codex_provider.dart`: `_item` traduz `fileChange` → `Edit`, `commandExecution` → `Bash`; `thread/tokenUsage/updated` vira um `result` com `usage` à mão; itens desconhecidos são descartados.
- `lib/features/context/` (SPEC-087): `ContextTracker`, `ContextReading`, `ContextMarker`, `ContextEventTypes.run` (`promptorium_run`, já com `provider`).
- Consumidores que leem `file_path`/`old_string`: `edit_diff.dart`, `timeline.dart`, `session_manager.dart`, `replay_step.dart`, `context_sources.dart`.

### Arquivos tocados

| Arquivo | Mudança |
|---|---|
| `lib/core/providers/agent_event.dart` | Novos: `FileChangeEvent`, `CommandEvent`, `ContextUsageEvent`, `CompactionEvent`, `QuotaEvent`, `OtherItemEvent` |
| `lib/core/claude/claude_neutral.dart` | Novo: conversor do Claude (R8) |
| `lib/core/codex/codex_provider.dart` | Emite os neutros (R7), fórmula de contexto (R4) |
| `lib/features/context/context_snapshot.dart`, `context_tracker.dart` | `source` na leitura; aceita `ContextUsageEvent`/`CompactionEvent` |
| `lib/features/sessions/edit_diff.dart`, `timeline.dart`, `widgets/timeline_view.dart`, `widgets/tool_expanded_view.dart` | Cartões de arquivo e comando |
| `lib/features/sessions/session_manager.dart` | Arquivos e chamadas do turno pelo evento neutro |
| `lib/features/sessions/replay/replay_step.dart`, `file_at_step.dart` | Passo de arquivo e "antes" pelo diff |
| `lib/features/context/context_sources.dart`, `lib/features/activities/activity.dart`, `lib/features/home/home_inbox.dart` | Leem os neutros |
| `test/core/providers/neutral_events_test.dart` | Novo: conversões Claude e Codex (fixtures da SPEC-093) |

**Migração do banco:** não (R11).

### Dependências

- Depende da SPEC-093 (payloads reais de `fileChange`, `commandExecution`, `tokenUsage`, `thread/compacted`) e da SPEC-087, já na main (contrato de medição).
- Pode correr junto da SPEC-094; as duas tocam `agent_provider.dart` em partes diferentes.
- Destrava a SPEC-096 (cartões de edição do Codex), a SPEC-097 (`QuotaEvent`), a SPEC-107 (contexto no Codex) e a SPEC-110 (Replay com o Codex).

## Tarefas

| Tarefa | Entrega | Requisitos |
|---|---|---|
| T1 · Tipos e conversores | Tipos neutros, conversor do Claude, `CodexRun` emitindo neutros, persistência | R1–R8, R11, R12 |
| T2 · Timeline e Atividades | Cartões de arquivo e comando, arquivos do turno, Atividades, Início | R9, R10 |
| T3 · Contexto e Replay | `ContextTracker` com os neutros, fórmula do Codex, Replay pelo diff | R3, R4, R9 |

## Critérios de aceite

- [x] Cada `changes[]` de um `fileChange` real (fixture da SPEC-093) vira um `FileChangeEvent` com caminho, tipo e diff; um `Edit`/`Write`/`MultiEdit` do Claude vira o mesmo tipo [R1, R8] verificar: `flutter test test/core/providers/neutral_events_test.dart`.
- [x] `commandExecution` com saída e `exitCode` vira `CommandEvent`; o `Bash` do Claude também [R2, R8] verificar: o mesmo teste.
- [x] Uma sessão Codex reproduzida pelo `fake_codex` mostra o cartão de edição com arquivo e diff, o cartão de comando com código de saída, e as Atividades contam os arquivos do turno [R7, R9] verificar: `flutter test test/features/sessions/codex_neutral_timeline_test.dart`.
- [x] Uma sessão Claude gravada abre igual a antes: timeline, Replay e Atividades [R10] verificar: testes de widget atuais sem mudar expectativas.
- [x] O medidor de contexto de uma sessão Codex mostra a leitura do `tokenUsage.last` com a janela do modelo, substitui a anterior e fica "aguardando medição" depois de `thread/compacted` [R3, R4] verificar: `flutter test test/features/context/context_tracker_codex_test.dart`.
- [x] `rate_limit_event` e `account/rateLimits/updated` viram `QuotaEvent` com as janelas certas [R5] verificar: teste de conversão.
- [x] Um item desconhecido aparece recolhido na timeline com o tipo [R6] verificar: teste de widget.
- [x] Nenhuma migração; eventos gravados levam `provider`, `v` e passam pelo `redactJson`; diff acima do limite é cortado com a marca [R11, R12] verificar: teste de persistência.

## Telas

Canvas: [SPEC-095 · Eventos neutros](https://claude.ai/artifact/BFMnuiE8SRRALoLCSL3i7r)

| PNG | O que mostra | Requisitos |
|---|---|---|
| `docs/mockups/spec-095/0-antes.png` | Antes: sessão Codex com o cartão "Edit" sem arquivo e sem diff, "Bash" sem código de saída, "Arquivos citados" vazio e "Neste turno: 0 arquivos" | — |
| `docs/mockups/spec-095/1-timeline-neutra.png` | A mesma sessão com os tipos neutros: cartão de arquivo com caminho, tipo e diff, cartão de comando com código de saída, item desconhecido recolhido, arquivos citados e arquivos do turno preenchidos | R1, R2, R6, R9 |
| `docs/mockups/spec-095/2-replay-e-contexto.png` | Replay de um passo do Codex com o "antes" reconstruído pelo diff e o medidor de contexto vindo do `tokenUsage` com a janela do modelo e a marca de compactação | R3, R4, R9, R12 |
| `docs/mockups/spec-095/3-fluxo.png` | Diagrama: Claude e Codex → tipos neutros → consumidores | R1–R9 |

Os mocks mostram o provedor com a identidade da SPEC-094 (R14, R15): logo oficial ao lado do nome no rodapé, nos seletores, nos chips de sessão e de conversa e em Configurações (Claude em argila `#D97757`; OpenAI no branco oficial para o Codex, com a porcelana `#E8E4DA` só na borda do chip e nos glifos); glifo próprio nos pontos pequenos. Nunca como estado.
