---
id: SPEC-110
status: em implementação
versao: 0.27.0
tipo: recurso
epico: 332
issue: 350
depende-de: [SPEC-082, SPEC-084, SPEC-094, SPEC-095, SPEC-096]
---

# Replay e restauração com o Codex

## Objetivo

O Replay (SPEC-082) e o ponto de restauração (SPEC-084) foram feitos sobre o Claude Code. Com os eventos neutros (SPEC-095) e as Sessões no Codex (SPEC-096), uma sessão Codex já aparece no Replay, mas pela metade, e desfazer um turno deixa a conversa do agente fora de sincronia com os arquivos.

Exemplo: a sessão "Ajustar frete" roda no Codex (`gpt-6.2-sol`) num worktree. No turno 3, o agente roda `rg "calcularFrete" lib/`, `sed -n 1,80p lib/frete/tabela.dart` e um `apply_patch` em 6 arquivos, e os testes quebram. Ao abrir o Replay:
- as leituras feitas por comando (`rg`, `sed -n`, `cat`) aparecem como "Rodar", então "Já leu" fica vazio e todas as edições ganham a marca "editou sem ler";
- "Arquivo neste ponto" diz "Não dá para reconstruir o arquivo neste ponto". O conteúdo anterior vinha do `originalFile` da transcrição do Claude, que não existe no Codex, e as edições do Codex chegam como diff unificado, não como `old_string`/`new_string`;
- "Quem escreveu esta linha?" procura no `new_string` e não acha nada.

A pessoa então clica em "Desfazer o último turno" (SPEC-084). Os arquivos voltam, mas a thread do Codex continua lembrando do turno 3. Na mensagem seguinte, o agente acha que as mudanças ainda existem. O aviso "o usuário desfez o turno" ajuda, mas o histórico do agente continua errado. O Codex 0.170 tem `thread/revert` (`beforeTurnId`), que tira o turno e os seguintes do histórico da thread.

Esta spec:
- faz o Replay entender os itens do Codex: leituras por comando, edições por diff, raciocínio, plano e turnos;
- reconstrói "Arquivo neste ponto" a partir do **ponto de restauração** do início do turno, para qualquer provedor;
- acrescenta ao "Desfazer" a opção de **voltar também a conversa** do Codex, com uma cópia da thread guardada antes para o Refazer.

## Requisitos

### Replay

- R1 · **Passos dos itens do Codex.** A função `replaySteps` (SPEC-082 R2) passa a classificar os eventos neutros vindos do Codex:
  - `commandExecution` com `commandActions` só de leitura vira **Ler**: `read` com o arquivo como alvo; `search` com o padrão e a pasta, como um `Grep`; `listFiles`, como um `LS`;
  - `commandExecution` com ação `unknown`, ou com ações misturadas (`cat a && dart test`), vira **Rodar**, com as leituras reconhecidas listadas no painel;
  - `fileChange` vira um passo **Editar** por arquivo, com o tipo (criado, alterado, apagado, movido com `move_path`) e o "+/−" contado no diff;
  - `mcpToolCall` vira **Outra**, `webSearch` vira **Web**, `collabAgentToolCall` vira **Subagente** (recolhido, SPEC-082 P7) e o item `plan` ou `turn/plan/updated` vira **Plano**;
  - `reasoning` e `agentMessage` são passos da conversa;
  - cada turno começa no `turn/started` e leva o id do turno do Codex. Um turno `interrupted` ou `failed`, uma aprovação negada e um `turn/interrupt` viram marcas.
  
  "Já leu", "Já editou" e "editou sem ler" (SPEC-082 R6) passam a contar as leituras feitas por comando.
- R2 · **Base de "Arquivo neste ponto" para qualquer provedor.** A ordem da SPEC-082 P2 ganha uma fonte nova, em primeiro lugar:
  1. o **ponto de restauração do início do turno** (`refs/promptorium/restore/<sessão>/<turno>-inicio`, SPEC-084), que tem o arquivo exato antes do turno, inclusive se ele não estava rastreado;
  2. o `originalFile` da transcrição (só no Claude);
  3. o `startSha` da etapa;
  4. a `baseBranch` da sessão.
  
  Sobre a base, o app aplica as edições do turno em ordem até o passo: `old_string`/`new_string` no Claude e os *hunks* do diff unificado no Codex. Um *hunk* que não se aplica mostra "O diff do passo 42 não se aplica sobre a base (ponto do turno 3)" e o diff do passo continua visível. O painel diz qual base foi usada: "base: ponto de restauração do turno 3".
- R3 · **Quem escreveu esta linha.** No Codex, a busca (SPEC-082 R8) olha as linhas adicionadas (`+`) dos diffs de `fileChange` do arquivo, do fim para o começo. Uma linha que nenhuma edição escreveu continua com "veio de um comando" e leva ao último `commandExecution` do tipo Rodar antes da mudança aparecer.
- R4 · **De onde vem o histórico.** Os passos continuam saindo de `session_events` (SPEC-082 P1), que já guarda os eventos do adaptador Codex. Quando falta a saída de um comando (cortada ou guardada à parte), o painel oferece "Buscar a saída completa". Esse botão lê o item pela RPC (`thread/items/list` com `turnId`, sob demanda), sem chamar o modelo e sem custo de cota. O app nunca lê nem escreve os arquivos `rollout-*.jsonl` de `~/.codex/sessions`, que são um formato interno. Sem o Codex instalado, o botão fica desabilitado com o motivo e o resto do Replay funciona.
- R5 · **Contexto neste ponto.** No Codex, a seção Contexto do "Estado neste ponto" (SPEC-082 R6) usa a leitura de contexto do ponto (`thread/tokenUsage/updated` → leitura neutra da SPEC-095), com a janela do modelo quando informada, e as compactações (`thread/compacted`) até ali. Sem leitura, mostra "aguardando medição", nunca 0.

### Restauração

- R6 · **Ponto ligado ao turno do Codex.** Cada ponto de restauração (SPEC-084 R1) de uma sessão Codex fica associado ao id do turno do Codex que ele abriu. O id vem do `turn/started` que segue a mensagem do ponto em `session_events` (`eventSeq`). Um ponto sem turno identificado (processo que morreu antes do `turn/started`) só permite desfazer os arquivos.
- R7 · **Voltar também a conversa.** Numa sessão Codex, a janela de desfazer (SPEC-084 R6) ganha a seção **Conversa do agente**, com a caixa "Voltar também a conversa do Codex para antes do turno 3", marcada por padrão (P2). O texto diz o efeito: "O Codex esquece os turnos 3 a 5. A timeline do app continua mostrando os turnos, marcados como revertidos." Em "Voltar a antes deste turno…" (SPEC-084 R9), o `beforeTurnId` é o turno mais antigo da faixa. Numa sessão Claude, a caixa aparece desabilitada com "Só Codex: o Claude Code não volta a conversa no modo do app; o agente recebe o aviso", porque a capacidade `revertConversation` da SPEC-094 é falsa no Claude.
- R8 · **Ordem e falha.** Ao confirmar, o app:
  1. desfaz os arquivos como na SPEC-084 R8, de forma atômica;
  2. guarda uma **cópia da conversa** com `thread/fork` (sem `ephemeral`), cujo id fica no ponto "antes de desfazer" (P3);
  3. chama `thread/revert` com `threadId` e `beforeTurnId`. Se o processo da sessão não está vivo, o app abre o App Server, retoma a thread (`thread/resume`) sem começar turno, reverte e fecha;
  4. quando a conversa voltou, não manda o aviso "o usuário desfez o turno" (o agente já não conhece aquele turno). A timeline ganha "Turno 3 desfeito: 6 arquivos e a conversa do Codex. Refazer".
  
  Se o `thread/revert` falhar, os arquivos continuam desfeitos, a timeline mostra "A conversa do Codex não voltou: <motivo>" e o app manda o aviso da SPEC-084 como hoje. Nada fica meio desfeito nos arquivos. Com um turno em andamento, desfazer continua bloqueado (SPEC-084 P3).
- R9 · **Refazer com a conversa.** O Refazer (SPEC-084 R11) volta os arquivos e, quando a conversa foi revertida, passa a sessão para a **cópia** guardada no passo 2 do R8: o `externalId` da sessão vira o id do fork. A timeline registra "Refeito: arquivos e conversa (cópia de 14:20)". Sem cópia (falha no fork), o Refazer volta só os arquivos e avisa que a conversa não volta. Um turno novo depois do desfazer tira o Refazer, como hoje, e a cópia fica órfã. O app arquiva a cópia (`thread/archive`) na limpeza dos pontos (SPEC-084 R13).
- R10 · **Timeline e Replay depois de reverter.** Os eventos dos turnos revertidos continuam em `session_events`. A timeline e o Replay mostram esses turnos esmaecidos, com o selo "fora da conversa do agente · revertido às 14:20", e o Replay marca "Conversa revertida para antes do turno 3" na faixa das marcas. O terminal (`codex resume`) mostra o histórico revertido, coerente com o agente.

### Acessibilidade

- R11 · A caixa da conversa tem rótulo completo e a dica do motivo quando está desabilitada. Os turnos revertidos são anunciados como "revertido" pelo leitor de tela, não só pela cor. O passo Ler vindo de comando anuncia o comando de origem ("Ler tabela.dart, pelo comando sed").

## Fora do escopo

- Voltar a conversa do Claude Code. A SPEC-084 mantém o aviso ao agente.
- "Continuar daqui": abrir uma sessão nova a partir de um passo do Replay com `thread/fork` + `lastTurnId` (P5).
- Pontos dentro de um turno, por chamada de ferramenta.
- Ler ou importar os arquivos `rollout-*.jsonl` do Codex, ou sessões feitas fora do app.
- Replay de conversas do Prompt e de VIBEs (SPEC-082 P3).
- Desfazer efeitos fora do worktree (SPEC-084, fora do escopo).

## Decisões

- P1 · **Onde guardar o id do turno do Codex.** (a) Derivar de `session_events`, pelo `turn/started` depois do `eventSeq` do ponto; (b) uma coluna nova `restore_points.agent_turn_id`. **Decidido:** (a), sem migração. O ponto já guarda o `eventSeq` da mensagem, e o evento do turno vem logo depois. Se a SPEC-095 já gravar o id do turno num evento neutro, a busca fica direta.
- P2 · **Caixa "voltar também a conversa" marcada por padrão.** **Decidido:** marcada. O motivo de desfazer é voltar a um estado coerente, e arquivos voltados com uma conversa que lembra do turno é justamente a incoerência do problema. Quem quer manter a conversa desmarca.
- P3 · **Cópia da conversa antes de reverter.** (a) `thread/fork` antes do `thread/revert`, para o Refazer; (b) sem cópia, com o Refazer voltando só os arquivos. **Decidido:** (a). O fork não chama o modelo, então não gasta cota. Sem ele, o `thread/revert` é irreversível e o Refazer fica pela metade.
- P4 · **Complemento pela RPC.** **Decidido:** sim, sob demanda e só por `thread/items/list`. O banco continua sendo a fonte. O formato `rollout` é interno e muda entre versões (existe até `migrate-rollouts`).
- P5 · **"Continuar daqui" com `thread/fork` + `lastTurnId`.** **Decidido:** fora desta spec. É um recurso novo (sessão a partir de um passo, com o worktree no ponto do fim daquele turno). Combina com os pontos de restauração, mas pede tela e fluxo próprios. Fica para uma spec futura, se o Replay for usado para isso.
- P6 · **Ponto de restauração como primeira base também no Claude.** **Decidido:** sim. O ponto é exato para os dois provedores, enquanto a transcrição do Claude some depois de 30 dias e não tem os arquivos que o `Bash` criou. O `originalFile` vira a segunda opção.

## Design

### O que já existe

- `lib/features/sessions/replay/replay_step.dart`: `ReplayKind`, `ReplayLane`, `ReplayStep` e o mapeamento por nome de ferramenta do Claude (`Read`, `Edit`, `Bash`…).
- `lib/features/sessions/replay/file_at_step.dart`: bases `transcript`, `startSha` e `baseBranch`, aplicação de `old_string`/`new_string`.
- `lib/features/sessions/replay/replay_data.dart` (`transcript_reader.dart`, só no Claude), `replay_state.dart`, `replay_view.dart`.
- `lib/features/sessions/restore/restore_point.dart`, `restore_service.dart` (`start`, `end`, `plan`, `redoPlan`, `undo`), `lib/features/sessions/widgets/undo_dialog.dart`, `restore_points_section.dart`.
- `lib/data/db/app_database.dart`: `restore_points` (`sessionId`, `turn`, `eventSeq`, `startSha`, `endSha`…).
- `lib/core/codex/codex_provider.dart`: `turn/started`, `turn/completed`, `thread/tokenUsage/updated`; `fileChange` ainda disfarçado de `Edit` até a SPEC-095.
- Codex 0.170 (`codex app-server generate-json-schema`): `thread/revert {threadId, beforeTurnId}` (devolve a thread sem os turnos e emite `thread/reverted`), `thread/fork {threadId, lastTurnId?, ephemeral}`, `thread/items/list {threadId, turnId, cursor, deferOutput}`, `thread/archive`, `CommandAction` (`read`, `listFiles`, `search`, `unknown`) e `FileUpdateChange {path, kind, diff}`.

### Componentes

- `replay_step.dart`: `replaySteps` consome `CommandEvent` (com as ações) e `FileChangeEvent` da SPEC-095, e o turno ganha `agentTurnId`.
- `file_at_step.dart`: nova base `FileBaseSource.restorePoint` (`git show <startSha>:<caminho>` do ponto do turno) e `applyUnifiedDiff(base, hunks)`, uma função pura com o erro do *hunk* que falhou.
- `replay_data.dart`: `ReplaySource` neutro. A transcrição fica no adaptador Claude, e o adaptador Codex ganha `fetchItemOutput(threadId, turnId, itemId)` por `thread/items/list`.
- `lib/core/codex/codex_thread_ops.dart` (novo): `revertThread`, `forkThread`, `archiveThread` com o App Server de curta duração quando a sessão não está viva.
- `restore_service.dart`: `undo(..., revertConversation: bool)` com a ordem do R8; `redo` adota a cópia; `prune` arquiva cópias órfãs. A busca do turno do Codex pelo `eventSeq` (P1) entra aqui.
- `undo_dialog.dart`: seção "Conversa do agente" com a caixa e o estado "Só Codex". `timeline.dart` e `replay_view.dart` mostram os turnos revertidos pelo evento do app `conversation_reverted` (JSON com `beforeTurnId`, hora e id da cópia).

### Migração

Não (P1). O vínculo entre ponto e turno vem de `session_events`. A cópia da conversa e o "revertido" ficam num evento do app em `session_events` (`type = 'conversation_reverted'`), e o Refazer troca o `externalId` da sessão, que já existe.

### Dependências

- SPEC-082 (Replay) e SPEC-084 (ponto de restauração), que esta spec amplia.
- SPEC-094 (capacidades): `revertConversation`.
- SPEC-095 (eventos neutros): `FileChangeEvent`, `CommandEvent` com as ações e a leitura de contexto.
- SPEC-096 (Codex nas Sessões): sessões Codex com pontos de restauração e App Server por execução.

### Arquivos tocados

- `lib/features/sessions/replay/` (`replay_step.dart`, `file_at_step.dart`, `replay_data.dart`, `replay_view.dart`, `widgets/`)
- `lib/features/sessions/restore/restore_service.dart`, `restore_point.dart`, `lib/features/sessions/widgets/undo_dialog.dart`, `restore_points_section.dart`
- `lib/features/sessions/timeline.dart`, `widgets/timeline_view.dart`
- `lib/core/codex/codex_thread_ops.dart` (novo), `codex_provider.dart`
- `test/features/sessions/replay/`, `test/features/sessions/restore/`, `test/core/codex/`

## Tarefas

- T1 · Passos do Codex no Replay: classificação por `commandActions`, `fileChange` por arquivo, turnos com id e marcas [R1, R11].
- T2 · Base pelo ponto de restauração e aplicação de diff unificado; "Quem escreveu" pelos diffs [R2, R3].
- T3 · Complemento pela RPC e contexto do ponto [R4, R5].
- T4 · Conversa no desfazer: turno do ponto, fork de cópia, `thread/revert`, falha e Refazer [R6–R9].
- T5 · Turnos revertidos na timeline e no Replay; e2e no app isolado com o `fake_codex` e um turno real curto (orçamento da decisão 9) [R10, R11].

## Critérios de aceite

- [ ] Leituras por comando viram Ler, comandos misturados viram Rodar com as leituras listadas, `fileChange` vira um Editar por arquivo e os turnos levam o id do Codex [R1] verificar: flutter test test/features/sessions/replay/replay_step_test.dart (fixtures do Codex)
- [ ] "Já leu" conta as leituras por comando e "editou sem ler" some quando o arquivo foi lido por `sed -n` [R1] verificar: flutter test test/features/sessions/replay/replay_state_test.dart
- [ ] "Arquivo neste ponto" usa o ponto do início do turno, aplica os *hunks* do Codex e mostra a base; um *hunk* que não se aplica explica o motivo [R2] verificar: flutter test test/features/sessions/replay/file_at_step_test.dart
- [ ] "Quem escreveu esta linha" acha a edição do Codex pelo diff e cai em "veio de um comando" quando nenhuma edição escreveu a linha [R3] verificar: flutter test test/features/sessions/replay/file_at_step_test.dart
- [ ] "Buscar a saída completa" usa `thread/items/list` sob demanda e nunca lê `~/.codex/sessions` [R4] verificar: flutter test test/features/sessions/replay/replay_data_test.dart (fake_codex)
- [ ] O contexto do ponto vem da leitura do Codex e mostra "aguardando medição" sem leitura [R5] verificar: flutter test test/features/sessions/replay/replay_state_test.dart
- [ ] O ponto de uma sessão Codex acha o turno do Codex pelo `eventSeq`; sem turno, só os arquivos podem ser desfeitos [R6] verificar: flutter test test/features/sessions/restore/restore_service_test.dart
- [ ] A janela mostra a caixa da conversa marcada no Codex e desabilitada com o motivo no Claude [R7] verificar: flutter test test/features/sessions/widgets/undo_dialog_test.dart
- [ ] Desfazer volta os arquivos, faz o fork de cópia e chama `thread/revert` com o turno certo; a falha do revert mantém os arquivos desfeitos, mostra a nota e manda o aviso [R8] verificar: flutter test test/features/sessions/restore/restore_service_test.dart (fake_codex)
- [ ] Refazer volta os arquivos e adota a cópia da conversa; sem cópia, avisa; a limpeza arquiva cópias órfãs [R9] verificar: flutter test test/features/sessions/restore/restore_service_test.dart
- [ ] Turnos revertidos aparecem esmaecidos com o selo na timeline e no Replay, e o leitor de tela anuncia "revertido" [R10, R11] verificar: flutter test test/features/sessions/replay/replay_view_test.dart
- [ ] No app isolado, uma sessão Codex com leitura por `rg`/`sed`, `apply_patch` e testes quebrados mostra o Replay completo, desfaz arquivos e conversa e, no turno seguinte, o agente não lembra do turno desfeito [R1–R10] verificar: manual (xdotool, `XDG_DATA_HOME`, prints em `docs/mockups/spec-110/app/`)
- [ ] O projeto compila e a análise estática passa [R1–R11] verificar: flutter analyze

## Telas

Mockup: [canvas do Claude Design](https://claude.ai/artifact/Su8ECVaoDVd4vuqTuK8i9P). Capturas em `docs/mockups/spec-110/` (1366×768):

| PNG | O que mostra | Requisitos |
|---|---|---|
| `0-antes.png` | Hoje, com uma sessão Codex: as leituras por comando caem em Rodar, "editou sem ler" em todas as edições e "Não dá para reconstruir o arquivo neste ponto" | — |
| `1-replay-codex.png` | O Replay numa sessão Codex: `rg` e `sed -n` como Ler, o Editar com diff unificado, "Arquivo neste ponto" com "base: ponto de restauração do turno 3" e o contexto do ponto | R1, R2, R5 |
| `2-desfazer-conversa.png` | A janela de desfazer com a seção "Conversa do agente": a caixa marcada, o efeito nos turnos 3 a 5 e a cópia guardada para o Refazer | R6–R8 |
| `3-revertido.png` | Depois de desfazer: os turnos revertidos esmaecidos com o selo, a nota "arquivos e a conversa do Codex", o Refazer e a marca no Replay | R9, R10 |
| `4-estados.png` | A caixa desabilitada numa sessão Claude ("Só Codex"), a falha do `thread/revert` com o aviso e o *hunk* que não se aplica | R2, R7, R8 |
