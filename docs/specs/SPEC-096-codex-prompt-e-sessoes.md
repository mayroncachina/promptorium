---
id: SPEC-096
status: concluida
versao: 0.23.0
tipo: funcionalidade
epico: 332
issue: 343
depende-de: [SPEC-093, SPEC-094, SPEC-095]
---

# Codex no Prompt e nas Sessões

## Objetivo

Religar o Codex nos dois fluxos interativos do app: **conversar no Prompt** (Perguntar, Planejar, Editar) e **abrir Sessões em worktree**. É o MVP do épico: o menor recorte em que dá para usar o Codex de verdade no dia a dia, com aprovações, interromper, retomar, bifurcar e o terminal embutido. Os outros fluxos continuam no Claude Code e mostram "Só Claude Code" quando o Codex estiver selecionado (decisão 1).

Exemplo concreto de hoje: a pessoa escolhe o Codex no rodapé, abre o Prompt e pede "explique o `usage_ledger.dart`". O seletor do Prompt nem oferece o Codex, porque o interruptor global `codexEnabledProvider` está desligado desde `d251f38`. Uma sessão Codex salva antes disso abre com "Codex desligado". E, mesmo com o interruptor ligado em teste, sobravam os furos do DT-56:

- "Interromper" não tinha ligação na tela, e um turno cancelado ficava gravado como **falha**;
- o `codex app-server` não tinha grupo de processos e ficava órfão quando o app fechava;
- bifurcar uma sessão não guardava o vínculo com a sessão pai;
- não havia "aprovar nesta sessão" para comandos repetidos;
- o terminal embutido mandava `-a untrusted`, que sumiu do `--help` do 0.170;
- numa sessão em worktree, o sandbox não deixava o `git commit` gravar no `.git` da raiz.

Esta spec fecha esses furos para Prompt e Sessões, usando as capacidades (SPEC-094) e os eventos neutros (SPEC-095), e absorve o que faltava da SPEC-003 nesses dois fluxos.

## Requisitos

### Religar e detectar

- R1 · **Liberar Prompt e Sessões.** O `providerFlows` da SPEC-094 passa a liberar o Codex em Prompt e Sessões. Os demais fluxos (Executar spec, Review automático, Projeto e outras execuções estruturadas, Comparar, Protótipo) mostram "Codex · Só Claude Code por enquanto" no seletor do fluxo. O seletor do rodapé (SPEC-006) volta a oferecer o Codex; um padrão `codex` salvo deixa de virar `claude`.
- R2 · **Detecção e login.** O rodapé e Configurações → Provedores mostram o estado do Codex: não encontrado, incompatível (versão), login pendente, conectado. Login pendente orienta "rode `codex login` no terminal" com o botão "Abrir terminal"; o app nunca faz login nem lê `~/.codex/auth.json`. `account/read` confirma a conta ao abrir a primeira execução.
- R3 · **Provedor visível.** A lista de conversas, a lista de sessões, o cabeçalho, as notificações, o Início e as Atividades mostram o provedor e o modelo ("Codex · gpt-6.2-sol"). Sessões do Claude e do Codex convivem na mesma lista.

### Prompt

- R4 · **Conversa com o Codex.** O seletor do composer oferece Claude Code e Codex. O modelo e o esforço vêm das preferências do Codex (SPEC-094 R8) e podem ser trocados para o próximo turno. Trocar de provedor numa conversa com histórico abre uma **conversa nova** com aviso ("o Codex não continua uma conversa do Claude"); nunca troca no meio (decisão 4).
- R5 · **Modos.** Perguntar e Planejar rodam em só leitura imposta pelo sandbox; Editar escreve com confirmação (decisão 3, via SPEC-094 R7). Planejar não tem `ExitPlanMode` no Codex: quando o turno termina, o botão "Executar plano" abre um turno novo em Editar com o plano como mensagem, na mesma conversa.
- R6 · **Aprovações e perguntas.** Pedidos de comando e de arquivo do Codex aparecem no cartão de aprovação atual, com **Aprovar**, **Aprovar nesta conversa** (`acceptForSession`) e **Recusar**, e com o comando ou o diff (eventos neutros). `requestUserInput` usa o cartão de perguntas atual. `item/permissions/requestApproval` mostra o que o agente quer liberar (rede, pasta) e só aceita para o turno. Pedidos pendentes aparecem no painel global de aprovações.
- R7 · **Interromper e mensagem no meio do turno.** "Interromper" manda `turn/interrupt`; o turno fica como **interrompido**, nunca como falha. Uma mensagem enviada com o turno rodando vai como `turn/steer` (direcionar) quando a SPEC-093 comprovar o método; senão, entra na fila como hoje.
- R8 · **Imagens.** Prints e imagens anexadas vão como `UserInput` de imagem no formato que a SPEC-093 provou (data URL ou caminho). Um modelo sem a modalidade de imagem desabilita o anexo com o motivo (já existe para o Codex no composer).

### Sessões

- R9 · **Nova sessão com o Codex.** A Nova sessão oferece o Codex com o modelo, o esforço e o acesso do Codex (Perguntar, Editar, YOLO). Agente, orçamento e o que mais não se aplica ficam com "Só Claude Code" (SPEC-094 R11).
- R10 · **Worktree que commita.** Numa sessão em worktree com sandbox, a thread começa em `read-only` e o sandbox sobe por `turn/start` (assim o App Server não grava confiança no `~/.codex/config.toml`), e as raízes graváveis recebem só o recorte do *git common dir* (`worktrees/<wt>`, `objects`, `refs`, `logs`), para `git add` e `git commit` funcionarem em `workspace-write`. Nada fora do worktree e desse recorte fica gravável. **Reserva, e caminho fixo sem sandbox:** o app commita no fim do turno o que o Codex deixou sem commit (mensagem do agente como corpo, trailer da SPEC-048).
- R10a · **Sem sandbox na máquina (decisão 15).** Quando a SPEC-094 R7a detecta que o sandbox não sobe: Prompt e Nova sessão sem worktree mostram "Codex · Sandbox do Codex indisponível" com o comando para liberar; Nova sessão com worktree oferece o Codex só em acesso total (`danger-full-access` + `never`), com o aviso de que ele pode escrever fora da pasta da worktree, e o app commita no fim do turno. Nada roda na raiz do projeto sem sandbox.
- R11 · **YOLO só em worktree.** O acesso YOLO (`danger-full-access` + `never`) só é oferecido com worktree ligado, com o aviso da SPEC-007 (`bypassWarning`). Uma sessão sem worktree não aceita YOLO, nem ao trocar a permissão parada.
- R12 · **Interromper, retomar, bifurcar.** "Interromper" manda `turn/interrupt` e a sessão fica **interrompida** (o `SessionStatus.interrupted` que já existe, não `failed`). "Retomar" usa `thread/resume` com a thread guardada em `externalId`. "Fork" usa `thread/fork` e grava o vínculo com a sessão pai (coluna nova, R16), mostrado no painel ("bifurcada de …"). Retomar uma sessão do Claude no Codex, ou o contrário, continua recusado com mensagem.
- R13 · **Terminal embutido.** A aba Terminal abre `codex resume <thread>` (ou `codex fork <thread>`) com as flags que a SPEC-093 confirmou para o 0.170; o `untrusted` sai. Um escritor só por thread: com a sessão rodando no app, o terminal abre em modo leitura ou pede para pausar o turno, conforme o comportamento dos `thread-writer-locks` que a sondagem registrar.
- R14 · **Trocar permissão parada.** Com o turno parado, a troca de acesso vale para o próximo `turn/start` (o Codex aceita política por turno). Com o turno rodando, a troca continua bloqueada com a mensagem atual.

### Processos

- R15 · **Grupo de processos e órfãos.** Cada `codex app-server` sobe no seu grupo de processos. Fechar o app, encerrar uma sessão ou trocar de workspace termina o grupo. Na partida, `orphans.dart` também reconhece e encerra `codex app-server` órfãos das sessões gravadas (hoje só reconhece `claude`).
- R16 · **Vínculo com a sessão pai.** `sessions` ganha `parentSessionId` (nulo para sessões que não vieram de fork). Vale para Claude e Codex.

### Revalidação

- R17 · **SPEC-006 e SPEC-007.** Com o Codex ligado, conferir os critérios das duas specs (seletor no rodapé; YOLO do Codex) e tirar delas a nota "inativa".
- R18 · **E2E.** Um roteiro com o app compilado, dados isolados (`XDG_DATA_HOME`) e xdotool cobre: Prompt em Perguntar e Editar com uma aprovação; Sessão em worktree com commit; interromper; retomar; fork; terminal. Com o Codex real, poucos turnos curtos e listados.

## Fora do escopo

- Codex em Executar spec, Quadro, Autopilot, gates e retomadas automáticas (SPEC-101).
- Execuções estruturadas (Projeto, Gerar tarefas, Nova skill, planner) e provedor por tipo de execução (SPEC-100).
- Passar uma conversa ou sessão de um provedor para o outro com resumo (SPEC-099); aqui, trocar = conversa nova.
- Hooks gerenciados no Codex (SPEC-103). O vigia de segredos continua pós-turno no Codex (SPEC-085 R2), e a tela diz isso.
- MCP do app e `.claude/agents` no Codex (SPEC-105, SPEC-106).
- Cota no rodapé (SPEC-097) e "Compactar agora" no Codex (SPEC-107).
- Daemon compartilhado do App Server: continua um processo por execução.

## Decisões em aberto

- P1 · **Interruptor de emergência.** Manter uma chave em `app_settings` que desliga o Codex em todos os fluxos sem nova versão? **Decidido:** sim, escondida em Configurações → Provedores ("Desligar o Codex"), porque o App Server é experimental.
- P2 · **"Aprovar nesta conversa" e o painel global.** Uma aprovação por conversa vale só até o processo terminar ou também ao retomar? **Decidido:** só até o processo terminar, que é o que o `acceptForSession` do Codex garante; ao retomar, pede de novo.
- P3 · **Interrompida por você × app fechado.** O `SessionStatus.interrupted` hoje significa "o app fechou com a sessão rodando". Distinguir os dois? **Decidido:** reaproveitar o mesmo status (os dois podem ser retomados, e o Início e as Atividades já tratam assim, SPEC-080) e guardar o motivo no evento de fim de turno, mostrado como "interrompida por você" ou "interrompida: o app fechou".
- P4 · **Terminal com a sessão viva.** **Decidido:** abrir o terminal só com o turno parado e mostrar "pare o turno para abrir o terminal" com o botão Interromper, a menos que a SPEC-093 mostre que o App Server e a TUI convivem na mesma thread.
- ~~P5 · Commit em worktree se `writableRoots` falhar.~~ **Decidido em 21/11 (decisão 15):** o app commita no fim do turno, como reserva com sandbox e como caminho fixo sem sandbox (R10, R10a).

## Design

### O que já existe

- `lib/core/codex/codex_provider.dart` (`CodexRun`): `initialize`, `account/read`, `model/list`, `thread/start|resume|fork`, `turn/start|interrupt`, aprovações e perguntas, uso de tokens.
- `lib/core/codex/codex_command.dart`: argumentos do terminal (`resume`, `fork`, `--yolo`, `--sandbox`, `--ask-for-approval`).
- `lib/features/sessions/session_manager.dart`: ramos por provedor (`externalId`, "YOLO exige worktree", recusa de retomar Claude no Codex, fallback do vigia).
- `lib/features/prompt/conversation_manager.dart`: provedor por conversa.
- `lib/features/sessions/widgets/composer.dart`: modalidade de imagem do Codex.
- `lib/ui/shell/status_footer.dart`: seletor de provedor (SPEC-006), hoje escondendo o Codex.
- `lib/core/process/orphans.dart`: limpeza de `claude` órfão.
- Testes: `test/core/codex/fake_codex.dart`, `codex_session_test.dart`, `codex_permissions_ui_test.dart`, `provider_footer_test.dart`.

### Arquivos tocados

| Arquivo | Mudança |
|---|---|
| `lib/core/providers/capabilities.dart` | Prompt e Sessões liberados para o Codex |
| `lib/core/codex/codex_provider.dart` | Interromper → interrompido, `turn/steer`, `permissions/requestApproval`, `writableRoots`, grupo de processos |
| `lib/core/codex/codex_command.dart` | Flags do 0.170, sem `untrusted` |
| `lib/core/process/orphans.dart`, `lib/core/app_shutdown.dart` | Órfãos e encerramento do `codex app-server` |
| `lib/features/prompt/` (composer, conversation_manager, prompt_screen) | Codex no seletor, conversa nova ao trocar, "Executar plano" |
| `lib/features/sessions/new_session_dialog.dart`, `session_manager.dart`, `widgets/session_terminal.dart`, `widgets/side_panel.dart` | Codex na Nova sessão, worktree, YOLO, retomar, fork, terminal |
| `lib/ui/shell/global_approvals.dart`, `lib/features/sessions/widgets/question_card.dart` | "Aprovar nesta conversa", pedido de permissão |
| `lib/ui/shell/status_footer.dart`, `lib/features/settings/` (Provedores) | Estado, login, interruptor de emergência |
| `lib/data/db/app_database.dart` | `sessions.parentSessionId` |
| `docs/specs/SPEC-006-*.md`, `SPEC-007-*.md` | Tirar a nota "inativa" (R17) |

**Migração do banco:** sim. `sessions.parentSessionId` (texto, nulo, referência a `sessions` com `set null`), na próxima versão do schema. O status "interrompida" já existe.

### Dependências

- SPEC-093 (worktree, `untrusted`, interrupt/steer, imagens, locks do terminal), SPEC-094 (fluxos, acesso, modelos, etiqueta) e SPEC-095 (cartões de arquivo e comando, contexto).
- Destrava as ondas 2 a 4: SPEC-098, SPEC-099, SPEC-101, SPEC-108, SPEC-110.
- A SPEC-097 (cota) pode sair na mesma versão sem depender desta.

## Tarefas

Spec grande: branch pai `spec/096-codex-prompt-e-sessoes` e uma branch por tarefa, cada uma com PR para a pai. O canvas é validado antes da T1.

| Tarefa | Entrega | Requisitos | Branch | Depende |
|---|---|---|---|---|
| T1 · Religar e detectar | `providerFlows` com Prompt e Sessões, rodapé e Provedores com estado e login, provedor nas listas, notificações e Atividades, interruptor de emergência | R1–R3 | `spec/096-t1-religar` | — |
| T2 · Prompt | Codex no composer, conversa nova ao trocar, modos, "Executar plano", aprovações e perguntas, interromper e direcionar, imagens | R4–R8 | `spec/096-t2-prompt` | T1 |
| T3 · Sessões | Nova sessão, worktree que commita, YOLO só em worktree, interromper/retomar/fork com vínculo, terminal, troca de permissão parada, migração | R9–R14, R16 | `spec/096-t3-sessoes` | T1 |
| T4 · Processos, revalidação e e2e | Grupo de processos, órfãos, encerramento; SPEC-006 e SPEC-007 revalidadas; roteiro e2e com xdotool e capturas reais | R15, R17, R18 | `spec/096-t4-processos-e2e` | T2, T3 |

T2 e T3 correm em paralelo depois da T1.

## Critérios de aceite

- [x] Com o Codex escolhido no rodapé, Prompt e Nova sessão oferecem o Codex; Executar spec, Review, Projeto e Comparar mostram "Só Claude Code por enquanto" [R1] verificar: `flutter test test/core/providers/provider_flows_test.dart` e testes de widget dos seletores.
- [x] Codex ausente, incompatível, sem login e conectado aparecem no rodapé e em Provedores com a orientação certa, sem o app tocar no `auth.json` [R2] verificar: teste de `inspectProvider` e do rodapé.
- [x] Listas, cabeçalho, notificações e Atividades mostram provedor e modelo [R3] verificar: testes de widget.
- [x] Conversa do Prompt com o Codex em Perguntar não escreve; em Editar, uma edição pede aprovação e "Aprovar nesta conversa" não pede de novo no mesmo processo [R4–R6] verificar: `flutter test test/features/prompt/codex_prompt_test.dart` com o `fake_codex`.
- [x] Trocar de provedor com histórico abre conversa nova com aviso [R4] verificar: teste de widget.
- [x] "Executar plano" depois de Planejar abre um turno em Editar com o plano [R5] verificar: teste do `conversation_manager`.
- [x] Interromper deixa o turno e a sessão como interrompidos, nunca como falha [R7, R12] verificar: `codex_session_test.dart`.
- [x] Uma sessão Codex em worktree faz `git commit` dentro do sandbox, ou o app commita no fim do turno o que sobrou; a thread começa em `read-only` e o `~/.codex/config.toml` não muda (hash antes e depois) [R10] verificar: e2e com o Codex real.
- [x] Sem sandbox, o Codex não roda fora de worktree, aparece só em acesso total com aviso, e o app commita no fim do turno [R10a] verificar: teste de widget com `osSandbox` falso e e2e neste Ubuntu.
- [x] YOLO só aparece com worktree e mostra o aviso [R11] verificar: `codex_permissions_ui_test.dart`.
- [x] Retomar usa a thread guardada; fork grava `parentSessionId` e o painel mostra "bifurcada de …" [R12, R16] verificar: teste do `session_manager` e da migração.
- [x] O terminal abre `codex resume` sem `untrusted` e respeita o escritor único [R13] verificar: teste de `codexCommandArgs` e e2e.
- [x] Fechar o app não deixa `codex app-server` vivo; na partida, órfãos de sessões gravadas são encerrados [R15] verificar: teste de `orphans.dart` e `pgrep -f "codex app-server"` no e2e.
- [x] SPEC-006 e SPEC-007 conferidas com o Codex ligado e sem a nota "inativa" [R17] verificar: leitura das specs e e2e.
- [x] Roteiro e2e com capturas reais em `docs/mockups/spec-096/app/` [R18] verificar: manual (app isolado com `XDG_DATA_HOME`).

## Como ficou

- **Thread em `read-only`:** a política real vai em cada `turn/start` (SPEC-093 D1). Nenhum `thread/*` grava confiança no `~/.codex/config.toml`.
- **Commit em worktree:** `writableRoots` leva só o recorte `worktrees/<wt>`, `objects`, `refs` e `logs`, lido dos arquivos do git (`lib/core/git/worktree_roots.dart`). No fim de cada turno de escrita, o app commita no worktree o que sobrou, com sandbox ou sem. Nunca roda na raiz nem em Perguntar ou Planejar.
- **Sem sandbox (R10a):** a Nova sessão só aceita YOLO em worktree, e o `SessionManager` recusa o resto antes de iniciar, removendo o worktree criado. O Prompt mostra "Sandbox do Codex indisponível" no seletor e recusa a conversa.
- **"Aprovar nesta conversa":** responde `acceptForSession` e só aparece onde o App Server oferece. Nunca sob `untrusted` e nunca em pedido de permissões, que valem só para o turno (P2).
- **Interrompida por você (P3):** o motivo fica no `runConfig` da sessão até ela iniciar de novo, e no evento `result` (`interrupt_reason`).
- **Terminal (P4):** com o turno rodando, a aba Terminal pede para interromper primeiro (um escritor por thread).
- **Grupo de processos (R15):** o `codex app-server` real sobe com `setsid`, e parar o processo encerra o grupo. Na partida, `orphans.dart` reconhece `codex app-server` pelo PID gravado.
- **Migração:** v35 (`sessions.parentSessionId`). A v34 fica reservada, sem mudança, para a SPEC-097.
- **E2E:** feito com um `codex` falso no `PATH` (`XDG_DATA_HOME` isolado, Xephyr :7), sem turno pago e sem tocar no `~/.codex`.
- **Codex real, 1 turno pago (21/11):** `gpt-5.6-luna`, esforço `low`, sessão em worktree num repositório temporário, pelo `CodexRun` real com o `HOME` padrão. O turno respondeu "ok" (`success`, 5 tokens de saída), com a política `workspace-write`/`on-request` e as `writableRoots` do recorte no turno. O `sha256` do `~/.codex/config.toml` ficou igual antes e depois (`3f1bcc8c…74843`), então nada foi gravado e não houve o que restaurar.
- **Ao trocar de workspace (R15):** os processos ociosos do Codex do workspace deixado (sessões e conversas) são encerrados. Um turno em andamento continua, e os outros workspaces ficam intactos. "Retomar" retoma a thread.
- **Primeira mensagem duplicada:** a timeline aplicava de novo um evento ao vivo cuja linha a carga já tinha lido, quando a linha era gravada enquanto a carga rodava. Agora ignora eventos com `seq` até o maior lido do banco.

## Telas

Canvas: [SPEC-096 · Codex no Prompt e nas Sessões](https://claude.ai/artifact/Fwv8ALZETB4S7aAyzyAjDS)

| PNG | O que mostra | Requisitos |
|---|---|---|
| `docs/mockups/spec-096/1-prompt-codex.png` | Prompt com o Codex em Editar: seletor Codex · gpt-6.2-sol, cartão de aprovação com o diff e "Aprovar nesta conversa", Interromper e o modo | R4–R7 |
| `docs/mockups/spec-096/2-nova-sessao.png` | Nova sessão com o Codex em worktree: modelo e esforço do Codex, acesso com YOLO só em worktree e o aviso, raízes graváveis incluindo o `.git` da raiz | R9–R11 |
| `docs/mockups/spec-096/3-sessao-codex.png` | Sessão Codex interrompida: status "Interrompida" (não falha), Retomar e Fork, painel com thread, provedor e "bifurcada de …", aba Terminal com `codex resume` | R3, R12, R13, R16 |
| `docs/mockups/spec-096/4-estados-e-fluxos.png` | Rodapé com o Codex sem login e a orientação, Configurações → Provedores com o interruptor de emergência, e Executar spec com "Só Claude Code por enquanto" | R1, R2, R15 |

Os mocks mostram o provedor com a identidade da SPEC-094 (R14, R15): logo oficial ao lado do nome no rodapé, nos seletores, nos chips de sessão e de conversa e em Configurações (Claude em argila `#D97757`; OpenAI no branco oficial para o Codex, com a porcelana `#E8E4DA` só na borda do chip e nos glifos); glifo próprio nos pontos pequenos. Nunca como estado.

### No app (E2E)

| PNG | O que mostra |
|---|---|
| `docs/mockups/spec-096/app/1-prompt-codex-aprovacao.png` | Prompt com o Codex em Editar: cartão com o diff, "Aprovar nesta conversa", Interromper e Direcionar |
| `docs/mockups/spec-096/app/2-nova-sessao-codex.png` | Nova sessão com o Codex: modelo, esforço, editar e as raízes graváveis |
| `docs/mockups/spec-096/app/3-sessao-commit-do-app.png` | Fim do turno em worktree: "O app commitou o que o Codex deixou no worktree" |
| `docs/mockups/spec-096/app/4-sessao-interrompida.png` | "Interrompida por você" (não falha), "Interrompido por você · dá para continuar" e Retomar |
| `docs/mockups/spec-096/app/5-fork-bifurcada-de.png` | Fork com "Bifurcada de Ledger com provedor" |
| `docs/mockups/spec-096/app/6-terminal-escritor-unico.png` | Terminal com o turno rodando: "um escritor por thread" e Interromper |
| `docs/mockups/spec-096/app/7-bifurcacoes.png` | Painel da sessão pai com as bifurcações |
| `docs/mockups/spec-096/app/8-terminal-codex-resume.png` | Terminal com `codex resume` sem `untrusted` |
| `docs/mockups/spec-096/app/9-provedores.png` | Provedores: fluxos liberados e "Desligar o Codex" |
| `docs/mockups/spec-096/app/10-login-pendente.png` | Login pendente em Provedores e no rodapé |
| `docs/mockups/spec-096/app/11-sem-sandbox-nova-sessao.png` | Sem sandbox: a Nova sessão só aceita acesso total em worktree |

