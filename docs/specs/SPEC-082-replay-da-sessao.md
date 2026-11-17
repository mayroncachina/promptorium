---
id: SPEC-082
status: aprovada
versão: 0.19.0
tipo: recurso
issue: 275
---

# Replay da sessão

## Objetivo

Quando uma etapa termina mal, a pessoa quer saber **por quê**. Um caso real: a SPEC-073 t2 terminou com o gate verde, mas o revisor reprovou porque o `ci_fixer.dart` passou a engolir o erro do `gh`. Para descobrir de onde veio isso, hoje a pessoa abre a sessão, rola a Timeline de 180 itens para cima e para baixo, abre os cards de ferramenta um a um e tenta lembrar qual `Edit` mexeu no `catch`, se o agente tinha lido o teste antes de editar, e se o `flutter test` que rodou no meio já falhava. A Timeline mostra tudo, mas como um chat: não dá para ver a sessão inteira de uma vez, nem pular "para a edição que escreveu esta linha", nem ver como o arquivo estava naquele momento.

Esta spec cria o **Replay**: uma aba nova da sessão encerrada, com:
- uma **linha do tempo que se arrasta**, com uma faixa para o que o agente **leu**, **editou** e **rodou** e outra para a conversa, os turnos marcados e os erros em destaque;
- o **painel do passo** sob o cursor: o diff da edição, o trecho que ele leu, o comando com a saída;
- o **estado naquele ponto**: o que ele já tinha lido, o que tinha editado, o último teste e o resultado;
- o caminho **do resultado para a causa**: escolher um arquivo do resultado filtra os passos que o tocaram, e clicar numa linha do diff final leva ao passo que a escreveu.

O histórico vem do **banco** (`session_events`), que o app já grava e que é a única fonte com tudo; o jsonl do Claude Code entra só como complemento, para o conteúdo dos arquivos antes da edição (P1).

Mockup: [canvas do Claude Design](https://claude.ai/artifact/YGDGPkpgnDGFVQe3f3utRL). Capturas em `docs/mockups/spec-082/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-replay.png` | A aba Replay numa edição: a linha do tempo com as faixas, a lista de passos, o diff do passo e o estado neste ponto | R1–R6 |
| `2-comando.png` | O cursor num `flutter test` que falhou: o comando, a saída e "próximo erro"; o filtro "Comandos" | R4, R5, R9 |
| `3-causa.png` | Do resultado para a causa: o arquivo escolhido destaca os passos que o tocaram, "Quem escreveu esta linha" e o arquivo neste ponto | R7, R8 |
| `4-estados.png` | Sessão ainda viva, sem o conteúdo anterior, subagente aberto na faixa e a dica do cursor | R1, R3, R7, R10 |

## Requisitos

### A aba

- R1 · **Aba Replay.** O painel da sessão (Sessões) ganha a aba **Replay**, depois de "Timeline". Ela abre com o cursor no último passo. Numa sessão viva (processo rodando), a aba aparece desabilitada com a dica "O replay fica disponível quando a sessão terminar"; quando o processo termina, ela habilita sem recarregar a tela. Uma sessão interrompida, que falhou ou foi retomada depois conta como encerrada até ser retomada. A aba vale para qualquer sessão, de etapa, Corrigir CI, solta ou fork.

### Os passos

- R2 · **Os passos.** O Replay transforma a Timeline da sessão (a mesma `Timeline` que a aba Timeline usa) numa lista de passos, uma função pura (`replaySteps`):
  - cada chamada de ferramenta é um passo, do tipo **Ler** (`Read`, `Grep`, `Glob`, `LS`), **Editar** (`Edit`, `MultiEdit`, `Write`, `NotebookEdit`), **Rodar** (`Bash`), **Web** (`WebFetch`, `WebSearch`), **Subagente** (`Task`, `Agent`), **Plano** (`TodoWrite`, `ExitPlanMode`) ou **Outra** (MCP e o resto);
  - a mensagem da pessoa, o texto do Claude e o raciocínio (`thinking`) são passos da conversa;
  - os avisos do app são marcas: erro da sessão, aprovação negada, gate (aprovado ou reprovado), compactação do contexto, retomada.
  
  Cada passo tem a hora, a duração (até o resultado ou até o passo seguinte), o resultado (ok, erro, negado, sem resposta), o alvo (arquivo, padrão ou comando) e o turno. Um turno começa em cada mensagem da pessoa (ou do app, como o pedido do gate e do Corrigir CI).

### A linha do tempo

- R3 · **Linha do tempo arrastável.** No topo da aba, uma faixa com toda a sessão:
  - quatro faixas, com rótulo e ícone: **Ler** (azul), **Editar** (âmbar), **Rodar** (teal) e **Conversa** (você, Claude e raciocínio, em cinza claro). Cada passo é uma marca na sua faixa; erro em vermelho com um "×", negado com um traço, e a cor nunca é o único sinal;
  - os turnos como separadores verticais com o número ("T3") e, na dica, o começo da mensagem que abriu o turno;
  - as marcas do app (gate, compactação, retomada) como bandeirinhas acima das faixas;
  - o **cursor** (uma linha âmbar com a alça), que se arrasta com o mouse; clicar em qualquer ponto leva o cursor para o passo mais próximo; a roda do mouse com Ctrl dá zoom e a barra embaixo mostra o trecho visível;
  - a dica sob o mouse mostra "42 · Edit lib/features/review/ci_fixer.dart +6 −2 · 14:32".
  
  O eixo é **por passo** (cada passo ocupa a mesma largura), com as horas como marcas embaixo; uma pausa longa (esperando aprovação, sessão parada) aparece como um corte "⋯ 2 h" (P4).
- R4 · **Teclado e reprodução.** ← e → movem um passo; Shift+← e Shift+→ movem um turno; Home e End vão ao início e ao fim; Espaço toca e pausa. Tocar avança um passo por segundo, com a velocidade 1×, 2× ou 4×, e para no fim ou num erro. Os botões "erro anterior" e "próximo erro" pulam entre os passos com erro, gate reprovado ou negado. A posição do cursor fica na URL interna da sessão enquanto a aba está aberta (voltar à aba volta ao mesmo passo).

### O painel do passo

- R5 · **O passo sob o cursor**, no centro, conforme o tipo:
  - **Editar**: o diff do passo (o mesmo `EditDiff` dos cards, SPEC-026), com o arquivo, a seção e "+6 −2"; numa `Write` sem conteúdo anterior, a nota "Conteúdo anterior desconhecido";
  - **Ler**: o arquivo, o trecho lido (`offset` e `limit`) e o conteúdo devolvido, com os números de linha; `Grep` e `Glob` mostram o padrão e os resultados;
  - **Rodar**: o comando, a descrição, a saída (as últimas 200 linhas, com "ver tudo"), o código de saída e a duração; um teste que falhou destaca as linhas de falha;
  - **Conversa**: o texto inteiro (markdown, com o `AppMarkdown` da SPEC-077), e o raciocínio aberto;
  - **Subagente**: o pedido, o resultado e a lista dos passos dele, que se abrem na faixa (R3) sem sair do Replay;
  - **Marca**: o texto do aviso (o relatório do gate, a mensagem de erro).
  
  Em cima do painel: "Passo 42 de 180 · T3 · 14:32 · 4 s", e "Abrir na Timeline", que troca para a aba Timeline com o card do passo em foco.
- R6 · **Estado neste ponto**, à direita, recalculado a cada passo:
  - **Já leu**: os arquivos lidos até aqui, com quantas vezes;
  - **Já editou**: os arquivos editados até aqui, com o "+/−" acumulado; um arquivo editado sem ter sido lido antes na sessão ganha a marca "editou sem ler";
  - **Último comando**: o último `Bash` antes do cursor, com o resultado (ok ou erro) e há quantos passos foi;
  - **Contexto**: os tokens de contexto da última resposta antes do cursor e as compactações até aqui.

### Do resultado para a causa

- R7 · **O arquivo neste ponto.** No passo de edição, o botão "Arquivo neste ponto" mostra o arquivo inteiro como estava logo depois daquele passo, com as linhas daquele passo destacadas. A base vem, em ordem (P2): o `originalFile` do jsonl do Claude Code na primeira edição do arquivo; o arquivo no commit em que a etapa começou (`spec_steps.startSha`, com `git show`); o arquivo no commit da `baseBranch` da sessão. As edições da sessão são aplicadas em ordem sobre a base. Quando nenhuma base existe, ou uma edição não se aplica (o `old_string` não está lá), o botão mostra "Não dá para reconstruir o arquivo neste ponto" com o motivo, e o diff do passo continua.
- R8 · **Do resultado para a causa.** A lateral tem a aba **Resultado**: os arquivos alterados pela sessão (o diff do fim da sessão contra a base). Escolher um arquivo:
  - destaca na linha do tempo só os passos que o tocaram (leram ou editaram), apagando os outros, e "← →" passam a andar só por eles;
  - abre o diff final do arquivo, em que cada linha adicionada tem "Quem escreveu?": leva o cursor ao passo de edição cujo texto novo contém aquela linha (o último, se houver vários). Uma linha que nenhuma edição da sessão escreveu (gerada por um comando, como `dart format`) mostra "veio de um comando" e leva ao último `Bash` antes da mudança aparecer, quando a sessão tem um.
- R9 · **Filtros.** Acima da lista de passos: Tudo · Edições · Comandos · Leituras · Erros, e a busca por arquivo ou comando. Um filtro apaga na linha do tempo os passos de fora e a lista mostra só os de dentro; o cursor anda pelos de dentro.

### A fonte

- R10 · **De onde vem o histórico (P1).** Os passos saem de `session_events`, as linhas do stream-json que o app grava, com a hora de cada uma e os eventos que só o app tem (a mensagem da pessoa, as notas, a aprovação negada). O jsonl do Claude Code (`~/.claude/projects/<pasta codificada>/<externalId>.jsonl`) é lido **só para o `toolUseResult.originalFile`** das edições (R7), sob demanda, ao abrir "Arquivo neste ponto", e nunca é escrito. Se o arquivo não existe (o Claude Code apaga as transcrições antigas, outro computador, sessão de outro provedor), nada quebra: o R7 cai para o git. O Replay não chama o `claude` nem o `git` ao abrir; o `git show` só roda no R7 e no diff final do R8.
- R11 · **Desempenho.** Os passos são calculados uma vez por sessão, a partir da Timeline já carregada. A linha do tempo é desenhada com `CustomPainter` e a lista de passos é preguiçosa. Uma sessão com 5.000 eventos abre a aba em menos de 1 s e o cursor acompanha o arrasto sem travar.

### Entradas e acessibilidade

- R12 · **Outras entradas.** "Ver replay" no rastro da etapa na tela Specs (`step_trace_panel.dart`), no menu da etapa do card do Quadro e na linha de uma sessão encerrada da lista de Sessões (menu de contexto). Todos abrem a sessão na aba Replay, com o cursor no último passo.
- R13 · **Acessibilidade.** A linha do tempo é um controle deslizante: o leitor de tela anuncia "Passo 42 de 180, Editar ci_fixer.dart, mais 6 menos 2, 14:32"; ↑/↓ na lista de passos também move o cursor; as faixas têm rótulo de texto e cada tipo tem ícone, além da cor. Com "reduzir movimento", tocar troca de passo sem animar o cursor.

## Fora do escopo

- Replay de uma sessão viva, ao vivo (a aba Timeline já é isso).
- Voltar os arquivos a um passo ou abrir uma sessão nova a partir de um passo ("fork daqui"). Restaurar é a SPEC-084.
- Conversas do Prompt e VIBEs (a timeline é a mesma; fica para depois, se o Replay for usado).
- Comparar duas sessões lado a lado.
- Exportar o replay como vídeo ou GIF.
- Ler o jsonl para qualquer coisa além do conteúdo anterior dos arquivos, ou importar sessões feitas fora do app.
- Explicar automaticamente "por que deu errado" com o Claude.

## Decisões

- P1 · **De onde vem o histórico.** (a) O banco (`session_events`); (b) o jsonl do Claude Code; (c) o banco, com o jsonl só para o conteúdo anterior dos arquivos. **Recomendação: (c).** O banco já tem todas as sessões do app, com a hora de cada evento e o que só o app sabe (a mensagem digitada, que o CLI não ecoa no stdin; a aprovação negada; as notas do gate). O jsonl some quando o Claude Code limpa as transcrições antigas (30 dias por padrão), muda de formato entre versões e não existe para outros provedores. Mas ele tem uma coisa que o banco não tem: o `originalFile` de cada edição, o arquivo inteiro antes dela. Por isso entra só para isso, sob demanda, e a falta dele não quebra nada. **Decidido:** (c) o banco (`session_events`), com o jsonl do Claude Code só para o conteúdo anterior dos arquivos, sob demanda.
- P2 · **Base do "arquivo neste ponto".** jsonl, depois `startSha` da etapa, depois `baseBranch`. **Recomendação:** essa ordem. O jsonl é exato; o `startSha` é exato para sessões de etapa; a `baseBranch` pode estar desatualizada se a pessoa mexeu no worktree, e por isso é a última. **Decidido:** a ordem jsonl, depois `startSha` da etapa, depois `baseBranch`.
- P3 · **Só sessões ou também conversas.** **Recomendação:** só sessões nesta spec. É onde está o trabalho das specs (etapas, Corrigir CI, correções do revisor). As conversas usam a mesma `Timeline` e entram depois sem mudar o componente. **Decidido:** só sessões nesta spec; as conversas entram depois sem mudar o componente.
- P4 · **Eixo da linha do tempo.** Por passo (cada passo a mesma largura) ou pelo tempo real. **Recomendação: por passo**, com as horas como marcas e as pausas longas cortadas. No tempo real, uma espera de 2 h por aprovação esmaga a sessão inteira num canto, e 30 leituras seguidas de 1 s viram um borrão. **Decidido:** por passo, com as horas como marcas e as pausas longas cortadas.
- P5 · **"Quem escreveu esta linha?" nesta spec.** **Recomendação: entra.** É o atalho que responde "de onde veio isto" e custa pouco: procurar a linha no `new_string` das edições do arquivo, do fim para o começo. O caso que não acha (linha gerada por um comando) tem a resposta "veio de um comando". **Decidido:** entra; a linha que nenhuma edição escreveu mostra "veio de um comando".
- P6 · **Velocidade do "tocar".** **Recomendação:** um passo por segundo, com 1×, 2× e 4×, e parar num erro. Tocar é para assistir a sequência; quem quer ir rápido arrasta. **Decidido:** um passo por segundo, com 1×, 2× e 4×, e parar num erro.
- P7 · **Subagentes.** Na faixa principal, recolhidos numa marca só, ou abertos. **Recomendação:** recolhidos numa marca "Subagente · 23 passos" que se abre numa faixa embaixo, só dele. Abertos por padrão, um subagente grande esconde o que o agente principal fez. **Decidido:** recolhidos numa marca "Subagente · N passos", que se abre numa faixa embaixo, só dele.

## Design

Canvas para validar: [Replay da sessão](https://claude.ai/artifact/YGDGPkpgnDGFVQe3f3utRL). Quatro artboards: a aba numa edição, um comando que falhou, do resultado para a causa e os estados.

### O que já existe

- `lib/features/sessions/timeline.dart`: o `Timeline` (redutor dos eventos), `ToolItem` (nome, entrada, resultado, erro, negado, filhos de subagente, `at`, `doneAt`), `UserItem`, `AssistantTextItem`, `ThinkingItem`, `NoticeItem` e `AppEventTypes` (mensagem, nota, negado). É a base dos passos (R2).
- `lib/features/sessions/timeline_provider.dart`: `StoredTimelineNotifier` (carrega as linhas de `session_events` com a hora) e o `sessionTimelineProvider`.
- `lib/features/sessions/edit_diff.dart`: `EditDiff`, `isEditTool`, `editFilePath`, o diff de `Edit`/`MultiEdit`/`Write` com a seção (R5). Ganha a aplicação das edições em ordem sobre uma base (R7).
- `lib/features/sessions/widgets/timeline_view.dart`: os cards de ferramenta e o diff da edição (`DiffView`), reaproveitados no painel do passo.
- `lib/features/sessions/session_changes.dart` e `widgets/diff_raw_views.dart`: o diff do worktree (`SessionDiffView`), base do "Resultado" (R8).
- `lib/features/sessions/sessions_screen.dart`: `SessionTab` (timeline, terminal, diff, preview, raw) e as abas do painel.
- `lib/data/db/app_database.dart`: `sessions.externalId` (o id da sessão no Claude Code, para achar o jsonl), `sessions.worktreePath`, `sessions.baseBranch`; `spec_steps.startSha`.
- `lib/features/specs/widgets/step_trace_panel.dart`: o rastro da etapa, onde entra "Ver replay".

### Componentes

- **`lib/features/sessions/replay/replay_step.dart`**: `ReplayStep` (índice, tipo, alvo, hora, duração, resultado, turno, item da Timeline, passos do subagente) e `replaySteps(List<TimelineItem>)`, função pura (R2).
- **`lib/features/sessions/replay/replay_state.dart`**: `replayStateAt(steps, index)` (já leu, já editou, editou sem ler, último comando, contexto), função pura (R6); `ReplayCursor` (o passo, o filtro, o arquivo escolhido) por sessão.
- **`lib/features/sessions/replay/file_at_step.dart`**: `fileAtStep(base, edits, index)` e `whoWroteLine(...)`, funções puras (R7, R8); `FileBaseResolver` (jsonl → `startSha` → `baseBranch`).
- **`lib/core/claude/transcript_reader.dart`**: acha o jsonl pela pasta e pelo `externalId` e lê o `originalFile` de um `tool_use_id`, só leitura (R10).
- **`lib/features/sessions/replay/replay_view.dart`** e `widgets/`: `ReplayScrubber` (`CustomPainter`, R3, R13), `ReplayStepList` (R9), `ReplayStepPanel` (R5), `ReplaySidePanel` com "Neste ponto" e "Resultado" (R6, R8).

### Arquivos tocados

- `lib/features/sessions/sessions_screen.dart` (`SessionTab.replay` e a aba).
- `lib/features/sessions/edit_diff.dart` (aplicar edições sobre uma base).
- `lib/features/sessions/widgets/timeline_view.dart` (expor o `DiffView` e o card para o painel do passo; "Abrir na Timeline" com foco).
- `lib/features/sessions/widgets/session_list_panel.dart` (menu "Ver replay").
- `lib/features/specs/widgets/step_trace_panel.dart` e `lib/features/board/widgets/spec_steps_panel.dart` ("Ver replay").
- `lib/core/git/git_service.dart` (`show(sha, path)`, se ainda não existir).
- Novos em `lib/features/sessions/replay/` e `lib/core/claude/transcript_reader.dart`; testes em `test/features/sessions/replay/`.

### Migração

Não. Tudo sai de `session_events`, `sessions` e `spec_steps`, que já existem. A posição do cursor fica em memória.

### Testes

- `replaySteps`: tipos de cada ferramenta, turnos pela mensagem da pessoa e do app, duração, erro e negado, marcas do gate e da compactação, subagente com os filhos.
- `replayStateAt`: já leu, já editou com "+/−", "editou sem ler", último comando.
- `fileAtStep`: `Edit`, `MultiEdit` e `Write` em ordem sobre a base; `old_string` que não se aplica dá o motivo; `whoWroteLine` acha o último passo e cai em "veio de um comando".
- `TranscriptReader`: acha o `originalFile` pelo `tool_use_id`; arquivo ausente ou linha inválida não quebra.
- Widgets: a aba desabilitada com a sessão viva; arrastar e clicar movem o cursor; ← → Shift Home End e Espaço; "próximo erro"; filtros; arquivo escolhido destaca os passos; "Quem escreveu?" leva ao passo; o anúncio do leitor de tela.

## Critérios de aceite

- [ ] A aba Replay aparece nas sessões encerradas, desabilitada nas vivas, e habilita quando o processo termina [R1] verificar: flutter test test/features/sessions/replay/replay_view_test.dart
- [ ] A Timeline vira passos com o tipo, o alvo, a duração, o resultado e o turno, e as marcas do app [R2] verificar: flutter test test/features/sessions/replay/replay_step_test.dart
- [ ] O cursor se arrasta, pula com clique, anda pelo teclado, toca em 1×/2×/4× e para no erro [R3, R4, R13] verificar: flutter test test/features/sessions/replay/replay_scrubber_test.dart
- [ ] O painel mostra o diff da edição, o trecho lido, o comando com a saída e o texto, conforme o passo [R5] verificar: flutter test test/features/sessions/replay/replay_view_test.dart
- [ ] O estado neste ponto lista o que já leu e editou, "editou sem ler" e o último comando [R6] verificar: flutter test test/features/sessions/replay/replay_state_test.dart
- [ ] O arquivo neste ponto é reconstruído do jsonl, do `startSha` ou da `baseBranch`, e diz o motivo quando não dá [R7, R10] verificar: flutter test test/features/sessions/replay/file_at_step_test.dart
- [ ] Escolher um arquivo do resultado destaca os passos que o tocaram, e "Quem escreveu?" leva ao passo certo [R8] verificar: flutter test test/features/sessions/replay/file_at_step_test.dart
- [ ] Os filtros e a busca reduzem a lista e a linha do tempo [R9] verificar: flutter test test/features/sessions/replay/replay_view_test.dart
- [ ] Uma sessão com 5.000 eventos abre a aba em menos de 1 s [R11] verificar: flutter test test/features/sessions/replay/replay_perf_test.dart
- [ ] "Ver replay" no rastro da etapa, no card e na lista abre a aba [R12] verificar: flutter test test/features/sessions/replay/replay_entry_test.dart
- [ ] No app, o replay de uma etapa real que terminou mal leva, pelo "Quem escreveu?", à edição que causou o problema, com o arquivo naquele ponto [R1–R10] verificar: manual (app isolado com `XDG_DATA_HOME`, prints em `docs/mockups/spec-082/app/`)
- [ ] O projeto compila e a análise estática passa [R1–R13] verificar: flutter analyze
