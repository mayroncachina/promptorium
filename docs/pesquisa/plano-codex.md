# Plano: Codex CLI ao lado do Claude Code no Promptorium

> Análise de planejamento, 20/11/2026. Base: `origin/main` 0.21.1 (`fad5d6a`), lida em `promptorium-wt/review-021`. CLI instalado: `codex-cli 0.170.0` (`~/.local/bin/codex`). Só usei `--help`, `codex features list` e `codex app-server generate-json-schema`. Nenhum prompt pago foi enviado, e nenhum arquivo do repositório foi alterado.


> **Numeração atualizada em 20/11/2026.** Este plano foi escrito com as specs 098–108 sendo as ondas 2 a 4. Depois entraram a SPEC-098 (Memória com ai-memory) e a SPEC-099 (Passar o trabalho entre agentes), e as demais andaram dois números (098 → 100 … 108 → 110). Os títulos seguem o épico [#332](https://github.com/mayroncachina/promptorium/issues/332).

## Decisões tomadas (épico #332, 20/11/2026)

As decisões da §5 foram fechadas assim. Elas valem sobre as recomendações da §5 quando divergem.

1. **Paridade:** liberar fluxo por fluxo; onde o Codex não funcionar, a tela mostra "Só Claude Code".
2. **Comunicação:** App Server do Codex; `codex exec --json` só como plano B.
3. **Modos:** Perguntar/Planejar = só leitura · Editar = escreve com confirmação · YOLO só em worktree.
4. **Provedor:** seletor no rodapé e também por tipo de execução; nunca troca no meio de uma execução.
5. **Custo:** só tokens e cota do plano do Codex; nunca US$.
6. **Instruções:** `CLAUDE.md` é a fonte; se o Codex não o ler, o app gera `AGENTS.md` na criação do projeto.
7. **Agentes `.claude/agents`:** só no Claude por enquanto.
8. **MCP:** configuração por provedor + botão "copiar para o Codex".
9. **Sondagem paga:** ~10 turnos curtos do Codex e teste do ai-memory num repositório temporário.
10. **Versão mínima:** Codex ≥ 0.170.
11. **Versões:** 0.22 = base + MVP; 0.23–0.25 = ondas 2 a 4.
12. **Specs antigas:** 002 e 005 substituídas; 003 absorvida pela 096; 004 arquivada como referência; 006 e 007 mantidas e revalidadas.
13. **ai-memory (#83):** integração opcional, não motor; specs 098 e 099 abrindo a onda 2.

> **Versão do MVP atualizada em 20/11/2026.** A 0.22.0 saiu só com a SPEC-087; a base e o MVP do Codex (093–097) passam para a **0.23.0**. A distribuição das ondas seguintes fica com o épico [#332](https://github.com/mayroncachina/promptorium/issues/332) e os *milestones*.

| Versão | Specs |
|---|---|
| 0.23.0 (era 0.22.0) · Base e MVP | 093 Sondagem do Codex 0.170 · 094 Capacidades e opções por provedor · 095 Eventos neutros · 096 Codex no Prompt e nas Sessões · 097 Cota do Codex no rodapé |
| 0.23.0 · Memória e fluxo de specs | 098 Memória com ai-memory · 099 Passar o trabalho entre agentes · 100 Execuções estruturadas em qualquer provedor · 101 Executar spec com o Codex · 102 Review automático com o Codex · 103 Hooks gerenciados nos dois provedores |
| 0.24.0 · Ecossistema do provedor | 104 Instruções (AGENTS.md) e skills · 105 MCP por provedor · 106 Agentes no Codex · 107 Contexto e compactação no Codex |
| 0.25.0 · Multi-provedor | 108 Comparar Claude × Codex · 109 Orquestrador multi-provedor · 110 Replay e restauração com o Codex |

---

## 1. Por que o Codex foi desligado e o que dá para reaproveitar

### 1.1 Histórico

- **`9fa64a6` (20/10/2026).** Registrou as SPEC-002 a SPEC-007 e a sondagem `docs/pesquisa/codex-yolo.md`, feita no codex 0.163.0.
- **`d251f38` (22/10/2026), "desligar o Codex e focar no Claude Code".** O motivo foi **decisão de escopo**: o foco passou a ser o Claude Code. A auditoria registrada em `docs/debito-tecnico.md` (DT-56) explica por que não dava para manter ligado:
  - **Bloqueios práticos.** Projeto, design, skills e review automático mandam `maxBudgetUsd`, e o revisor também manda `agent` e um modelo Claude. O `CodexProvider.validateOptions` recusa essas opções e a execução nem começa. Nova sessão e Executar spec aplicavam modelo e esforço do Claude com o Codex selecionado. Imagens eram recusadas com o modelo `inherit`.
  - **Garantias enfraquecidas.** Os hooks gerenciados não rodam no Codex. Custo ausente virava US$ 0. `dontAsk` virava "executar sem perguntar".
  - **SPEC-002 incompleta.** Interromper o turno não tinha ligação na UI. Cancelamento ficava gravado como falha. Os processos filhos não tinham grupo de processos. O fork não tinha vínculo estruturado com a sessão pai. Faltava "aprovar no escopo" e faltavam testes de aprovação, deltas e erro JSON-RPC.
  - **SPEC-003, 004 e 005 abertas.** Faltavam o padrão global e o override por projeto na UI, preferências de modelo do Codex, o provedor nas listas e notificações, a matriz de paridade (orçamento, turnos, agentes, skills, MCP, ferramentas, modo auto) sem equivalente comprovado, duelo com provedor por lado, provedor próprio do revisor, limpeza de `codex app-server` órfão e escritor único no `SessionManager`.
- **O que o commit mudou.** Criou o interruptor `codexEnabledProvider = false` em `lib/core/providers/agent_registry.dart`, que faz o Codex aparecer como `ComingSoonProvider` ("em breve"). Os seletores de Nova sessão, Executar spec e rodapé passaram a esconder o Codex. Um padrão `codex` salvo passa a resolver para `claude`. Sessões Codex salvas falham com mensagem explícita. **Nada foi apagado**: o adaptador e os testes continuam, e os testes ligam o interruptor.
- **Lição.** A SPEC-004 exigia paridade total ("uma lacuna explícita não satisfaz a conclusão"). Esse critério de tudo-ou-nada, somado a uma superfície Claude que cresceu muito depois disso (0.18 a 0.21), deixou a integração parada. Este plano troca a paridade total por **capacidades declaradas por provedor**, com o Codex entrando por fatias.

### 1.2 O que sobrou e dá para reaproveitar

| Arquivo | O que é | Estado / reaproveitamento |
|---|---|---|
| `lib/core/codex/codex_provider.dart` (704 l.) | `CodexProvider` + `CodexRun`: cliente do **App Server** (JSON-RPC por stdio). Faz `initialize`, `account/read` (exige login), `model/list` paginado (com esforços e modalidades), `thread/start\|resume\|fork`, `turn/start`, `turn/interrupt`, aprovações (`commandExecution`, `fileChange`, `requestUserInput`), uso de tokens e tradução para eventos com **vocabulário Claude** | **Reaproveitar como base.** Revalidar contra o schema do 0.170 (o protocolo cresceu muito desde o 0.163) |
| `lib/core/codex/codex_rpc.dart` (166 l.) | Transporte JSON-RPC, `redactJson` (tira credenciais antes de persistir) | Reaproveitar |
| `lib/core/codex/codex_cli.dart` | Detecção do executável (`codex`, `~/.local/bin/codex`) | Reaproveitar. Falta checar versão mínima |
| `lib/core/codex/codex_command.dart` | Argumentos do terminal embutido (`codex resume/fork`, `--yolo`, `--sandbox`, `--ask-for-approval`) | **Corrigir.** O `-a` do 0.170 só lista `on-request` e `never`. O `untrusted` que o app passa no modo padrão sumiu do `--help` da CLI. Continua só no enum do App Server |
| `lib/core/providers/agent_provider.dart` | Contrato `AgentProvider`, `AgentRun`, `ManagedAgentRun`, `AgentStartOptions`, `PromptMode` | Evoluir (ver §3). Hoje mistura intenção do app com flags Claude |
| `lib/core/providers/agent_event.dart` (488 l.) | Modelo de eventos *sealed*. `ClaudeEvent` é só um `typedef` dele (`claude_event.dart`) | É o modelo normalizado de fato, mas no formato stream-json. Evoluir |
| `lib/core/providers/agent_registry.dart` | Registro e interruptor `codexEnabledProvider` | Reaproveitar. O interruptor vira *feature flag* por fluxo |
| `lib/core/providers/permission_policy.dart` | `codexPermissionPolicy` (modo para sandbox + aprovação), rótulos e aviso de YOLO | Reaproveitar e revisar o `untrusted` |
| `lib/core/providers/provider_availability.dart`, `provider_preferences.dart` | Disponibilidade por provedor. Chaves `agent.provider.default`, `agent.provider.workspace.<id>`, `<provider>.model.<kind>`, `<provider>.effort.<kind>` | Reaproveitar. A persistência da SPEC-003 já existe |
| `lib/core/providers/acp_provider.dart` | Provedor ACP genérico (Gemini CLI etc.) | Alternativa de transporte (D2) |
| `lib/ui/shell/status_footer.dart`, `footer_stats.dart` | Seletor de provedor no rodapé (SPEC-006), rótulo "Codex" | Pronto. Esconde o Codex enquanto o interruptor estiver desligado |
| `lib/features/sessions/session_manager.dart` | Ramos por provedor: colunas `provider`/`externalId`, retomada de `CodexRun`, "YOLO exige worktree", troca de permissão parada, recusa de retomar Claude no Codex, fallback do vigia de segredos | Reaproveitar |
| `lib/core/claude/readonly_run.dart` | Já roteia provedor diferente de `claude` para `AgentProvider.start` | Reaproveitar, mas repassa `maxBudgetUsd` e `agent` (bloqueio do DT-56) |
| `lib/features/prompt/conversation_manager.dart` | Provedor por conversa, `settingsFile` só para Claude | Reaproveitar |
| `lib/features/sessions/widgets/composer.dart`, `picked_elements.dart`, `timeline.dart` | Modalidade de imagem do Codex, rótulo de permissão Codex | Reaproveitar |
| `lib/core/git/agent_trailer.dart` (SPEC-048) | Variável `PROMPTORIUM_AGENTE` no ambiente, que vale para qualquer provedor | Conferir se o sandbox do Codex repassa o ambiente (§6) |
| Testes | `test/core/codex/{fake_codex,codex_yolo_test,codex_redact_test}.dart`, `test/core/codex_rpc_test.dart`, `test/features/sessions/{codex_session_test,codex_permissions_ui_test}.dart`, `test/core/provider_selection_test.dart`, `provider_auxiliary_test.dart`, `test/ui/provider_footer_test.dart` | Reaproveitar. O `fake_codex` é a base dos testes novos |
| Docs | `docs/pesquisa/codex-yolo.md`, DT-56 e DT-08 em `docs/debito-tecnico.md`, `docs/specs/README.md` (seção Codex) | Atualizar |

---

## 2. Mapa de acoplamento: Claude → equivalente no Codex → lacuna e risco

Legenda de lacuna: **0** = equivalente direto ou já feito · **1** = adaptação pequena · **2** = adaptação grande ou só parcial · **3** = sem equivalente.

| # | Área | Hoje (Claude) | Codex 0.170 | Lacuna | Risco / observação |
|---|---|---|---|---|---|
| 1 | Processo / protocolo | `claude -p --output-format stream-json --input-format stream-json`, NDJSON (`core/claude/claude_process.dart`, `claude_code_provider.dart`) | `codex app-server` (JSON-RPC 2.0 por stdio; `thread/*`, `turn/*`, `item/*`). Alternativas: `codex exec --json` (JSONL, uma rodada) e ACP | 1 | O App Server está marcado **[experimental]**. Entre 0.163 e 0.170 o protocolo foi de cerca de 40 para 109 *requests*. Precisa de versão mínima e de conferência do schema na partida |
| 2 | Modelo de eventos / timeline | `AgentEvent` = stream-json (`assistant`, `user/tool_result`, `control_request`, `result`, `rate_limit_event`) | `item/started\|completed` (agentMessage, commandExecution, fileChange, mcpToolCall, webSearch, reasoning, collabAgentToolCall), deltas, `turn/completed`, `thread/tokenUsage/updated`, `turn/diff/updated`, `turn/plan/updated` | 2 | O adaptador **finge** JSON Claude. `fileChange` vira `Edit` com `input.changes`, mas `edit_diff.dart`, `timeline.dart`, `session_changes`, `replay_step.dart` e `session_manager.dart` leem `file_path`/`old_string`/`new_string`. Os cartões de edição, as mudanças da sessão e o replay quebram |
| 3 | Continuidade / ids | `--session-id`, `--resume`, `--fork-session`; id Claude = UUID local | `thread/start/resume/fork` com id externo (já em `externalId`) | 0 | `conversations.claudeSessionId` tem nome Claude, mas guarda a thread. Vale renomear (migração) ou só documentar |
| 4 | Arquivos de sessão | `~/.claude/projects/<cwd>/<id>.jsonl` (`transcript_reader.dart`, usado no replay para `originalFile`) | `~/.codex/sessions/AAAA/MM/DD/rollout-*.jsonl` (`session_meta`, `response_item`, `event_msg`…), mais `thread/read`, `thread/turns/list` e `thread/items/list` pela RPC | 1 | Usar a **RPC**, não o arquivo: o formato `rollout` é interno e há `migrate-rollouts`. O replay pode reconstruir o "antes" pelo diff do `fileChange` |
| 5 | Terminal embutido | `claude --resume <id>` no PTY (`session_terminal.dart`) | `codex resume <id>` / `codex fork <id>` (`codex_command.dart`) | 1 | Escritor único: o Codex tem `~/.codex/thread-writer-locks`. Conferir o comportamento com App Server e TUI na mesma thread |
| 6 | Modos de permissão | `default`, `acceptEdits`, `plan`, `auto`, `dontAsk`, `bypassPermissions` mais `--disallowedTools`/`--tools` no Perguntar (`claude_args.dart`, DT-25) | sandbox `read-only\|workspace-write\|danger-full-access` × aprovação `untrusted\|on-request\|never\|granular{…}`, `approvalsReviewer` (revisão automática, parecida com o `auto`), `--approve-for-me`, `permissionProfile/list`; aprovação e sandbox **por turno** no `turn/start` | 1 | O Perguntar fica **mais forte** no Codex (sandbox `read-only` imposto pelo runtime, sem lista de ferramentas). Não há modo `plan` nem `ExitPlanMode` (`collaboration_modes` foi removido): Planejar = read-only + instrução. `untrusted` sumiu da CLI |
| 7 | Aprovações e perguntas | `control_request can_use_tool`, "Sempre permitir" (`updatedPermissions`), `AskUserQuestion` (`question_card.dart`, `global_approvals.dart`) | *Server requests*: `item/commandExecution/requestApproval`, `item/fileChange/requestApproval`, `item/permissions/requestApproval`, `item/tool/requestUserInput`, `mcpServer/elicitation/request`; decisão `acceptForSession` | 0–1 | O adaptador já trata as três principais. Faltam `permissions/requestApproval`, elicitação de MCP e o "aprovar no escopo" (DT-56) |
| 8 | Hooks gerenciados | `--settings` temporário com hooks Python: bloquear comandos, `formatar:`, `SessionEnd`, vigia de segredos (`managed_hooks.dart`, 944 l.) | **Hooks estáveis** no 0.170 (`hooks` = true): `preToolUse`, `postToolUse`, `permissionRequest`, `sessionStart/End`, `stop`, `userPromptSubmit`, `pre/postCompact`, `hooks/list`. Exigem *trust* (`--dangerously-bypass-hook-trust`). Execpolicy `.rules` (`~/.codex/rules/default.rules`) bloqueia comandos | 2 | Mudou desde o desligamento, quando "hooks não rodam no Codex". Falta sondar como injetar hooks **sem gravar no `~/.codex`** (via `-c` ou `CODEX_HOME` temporário?) e o formato da resposta de *deny*. Enquanto isso, o fallback pós-turno da SPEC-085 continua |
| 9 | Plugins/MCP desligados nas execuções do app | `--settings` com `enabledPlugins:false` e `deniedMcpServers` (`run_extensions.dart`, SPEC-017) | `-c mcp_servers={}` (já usado), `disabledPluginIds` em `turn/start`, `--ignore-user-config` | 1 | `--ignore-user-config` também ignora modelo e projetos confiáveis. Melhor usar overrides pontuais |
| 10 | Configuração de MCP (tela MCP) | `claude mcp list/add/remove`, `~/.claude.json`, `.mcp.json` (`features/mcp/*`, DT-45 a 48) | `codex mcp list/get/add/remove/login`, `[mcp_servers.*]` no `~/.codex/config.toml`, `mcpServerStatus/list`, `config/mcpServer/reload`, `mcpServer/oauth/login` | 2 | São dois arquivos de configuração e dois inventários. Precisa de abas por provedor e decidir se o app espelha servidores entre eles (D10) |
| 11 | MCP do próprio app (SPEC-052) | `--mcp-config` + `appAllowedTools` | `-c mcp_servers.promptorium={command=…,args=…}` e, por servidor, `enabled_tools`/`disabled_tools` (a sondar) | 1 | Hoje o `validateOptions` recusa `mcpConfigs` |
| 12 | Instruções do projeto | `CLAUDE.md` (criação de projeto em `create_step.dart`, `repo_setup.dart`) | `AGENTS.md` (hierárquico); `project_doc_fallback_filenames` pode incluir `CLAUDE.md` (a sondar) | 1 | Decidir a fonte única (D5) |
| 13 | Skills | `~/.claude/skills`, `<repo>/.claude/skills` (`skill_repository.dart`, `workspace_watcher.dart`, `catalog_view.dart`, `skill_writer.dart`) | Skills nativas (`~/.codex/skills`, pastas do repo a sondar), `skills/list` com caminho, escopo e erros, `skills/extraRoots/set` | 1–2 | O formato SKILL.md é parecido. `skills/extraRoots/set` pode apontar o Codex para `.claude/skills` **sem copiar nada**. Vale sondar |
| 14 | Agentes / subagentes | `.claude/agents/*.md`, `--agent`, `--agents` JSON, `maxTurns`, `mcpServers` (`features/agents`, `agent_names.dart`, DT-31) | Não há agentes definidos em arquivo. Há `developerInstructions`/`baseInstructions` no `thread/start`, perfis `-p` e `multi_agent_v2` (desligado) | 3 | Mapear agente para instruções + modelo + sandbox, ou deixar só no Claude (D9) |
| 15 | Slash commands e `@arquivos` | `/comandos` e skills do Claude no composer | Prompts/skills do Codex; `fuzzyFileSearch` pela RPC | 2 | Fora do MVP |
| 16 | Saída estruturada | `--json-schema` → `structured_output` (`structuredOutput()` em `readonly_run.dart`) | `turn/start.outputSchema`; `codex exec --output-schema <arq>` | 1 | 16 serviços passam por `runReadOnlyClaude` (planner, specs, design, verificador, decisão de etapa, classificador, projeto, skill, vibe, revisor…) |
| 17 | Orçamento e turnos | `--max-budget-usd`, `--max-turns` | Nenhum equivalente | 3 | Origem do bloqueio principal. A solução é **não enviar** essas opções (capacidade) e aplicar limite do lado do app (tempo/turnos + `turn/interrupt`) |
| 18 | Modelos e esforço | Aliases `sonnet/opus/haiku`, `--effort low…max` (`run_prefs.dart`, Configurações → Consumo) | `model/list` (ex.: `gpt-6.2-sol`, `gpt-6.1-terra`, `gpt-6-luna`… com esforço `low…ultra` e modalidades) e `effort` por turno | 1 | As chaves `<provider>.model.<kind>` existem, mas a UI de Consumo é só Claude. Não reaproveitar aliases entre provedores |
| 19 | Contexto e compactação (SPEC-087, **em paralelo**) | `--autocompact`, uso por chamada, `system/status` compactando | `ThreadTokenUsage{last,total,modelContextWindow}`, `thread/compacted`, `pre/postCompact` (hooks), **`thread/compact/start`** ("Compactar agora" de verdade), `model_auto_compact_token_limit` (config, a sondar) | 1 | **Sobreposição.** A SPEC-087 diz que não implementa provedores, mas define o "contrato único de medição" (R1). Pedir que o contrato tenha `origem/provedor` e janela vinda do agente, sem campos Claude. O Codex entrega a janela do modelo melhor que o Claude |
| 20 | Cota do plano | `claude -p "/usage"` (`usage_poller.dart`), `rate_limit_event` (`usage_tracker.dart`), régua no rodapé | **`account/rateLimits/read`** + `account/rateLimits/updated`: janelas `primary/secondary`, `planType`, créditos, `rateLimitsByLimitId`; `account/usage/read` | 0–1 | Paridade boa. O rodapé precisa mostrar a cota **do provedor ativo** (ou das duas) |
| 21 | Custo (SPEC-017/081, `usage_ledger.dart`, `spec_cost.dart`) | `total_cost_usd` (estimativa) | Só tokens (com `reasoningOutputTokens` e `cachedInputTokens`) | 2 | Mostrar tokens e "custo indisponível", nunca US$ 0 (D8) |
| 22 | Streaming / *thinking* | `stream_event` (`text_delta`, `thinking_delta`) | `item/agentMessage/delta`, `item/reasoning/summaryTextDelta`, `item/reasoning/textDelta` | 0 | — |
| 23 | Mensagem no meio do turno / interromper / trocar permissão ao vivo (DT-41, DT-19) | Só após o `result`. Interrupt por control | `turn/steer` (ativo por padrão), `turn/interrupt`, política por turno | 0 | Aqui o Codex está **à frente** do Claude |
| 24 | Imagens / prints (SPEC-051, 083) | Blocos `image` | `UserInput{type:image,url}` (data URL?) e modalidades por modelo | 1 | O composer já checa a modalidade. Falta conferir se data URL ou arquivo local funcionam |
| 25 | Sessões e worktrees | `SessionManager` + `ClaudeProcess` direto | `CodexRun` no `SessionManager` (já existe um ramo) | 1–2 | **Risco do sandbox:** em `workspace-write` só o cwd é gravável. Num worktree, `git commit` grava em `<repo>/.git/worktrees/…` e nos objetos da raiz, que ficam **fora** do cwd. É preciso `--add-dir` / `writable_roots` com o *git common dir*. Sondar |
| 26 | Executar spec / Quadro / gates / autopilot / retomadas | Sessões Claude por etapa, continuação por limiar de contexto (SPEC-017 R4) | Mesmo fluxo com `CodexRun` + `ThreadTokenUsage` | 2 | Provedor fixo por execução. Limpar `app-server` órfão. Grupo de processos |
| 27 | Orquestrador (SPEC-035) | Escada de modelos Claude; D5 deixou o Codex de fora | Degraus com modelos Codex; trocar de provedor quando a cota acabar (`rateLimitReachedType`) | 2 | Recurso diferencial, fica para a onda 4 |
| 28 | Review automático (`auto_reviewer.dart`) | `runReadOnlyClaude` com agente revisor | **`review/start`** nativo (alvos `uncommittedChanges`, `baseBranch`, `commit`) e `codex review` | 1 | Pode ficar melhor que o atual. O formato dos achados precisa ser normalizado |
| 29 | Resolução de conflito (SPEC-092) / merge | Sessão Claude | Sessão Codex | 1 | Sai de graça quando as sessões funcionarem |
| 30 | Comparar (SPEC-079) | Dois lados, mesmo provedor; "Claude × Codex" ficou fora do escopo | Um lado por provedor | 1 | Recurso de vitrine. As métricas comparam tokens e tempo, não US$ |
| 31 | Replay (SPEC-082) | `session_events` + transcrição (`originalFile`) | `session_events` do adaptador + diff do `fileChange` + `thread/items/list` | 1–2 | Depende do item 2 |
| 32 | Pontos de restauração (SPEC-084) | Snapshot git feito pelo app (já cobre Claude e Codex, P5) | O mesmo, mais `thread/revert` (volta também a conversa) | 0–1 | Opcional: "restaurar arquivos **e** conversa" no Codex |
| 33 | Marcar commits (SPEC-048) | `PROMPTORIUM_AGENTE` no ambiente + hook git | O mesmo | 1 | O sandbox pode filtrar o ambiente (`shell_environment_policy`). Sondar. O modelo `inherit` vira "codex" |
| 34 | Vigia de segredos (SPEC-085) | Hook `PreToolUse` | Fallback pós-turno já previsto (R2); hook nativo possível na SPEC-103 | 1 | — |
| 35 | Notificações / robô (SPEC-086), Home, Atividades | Eventos `PermissionRequest`/`Result` | Os mesmos, via adaptador | 0–1 | Mostrar o provedor no alerta |
| 36 | Protótipo de telas (SPEC-022) | `--tools` + `allowedTools` restringem a escrita a uma pasta | Só `writable_roots`, sem granularidade por ferramenta | 2 | Rodar numa pasta temporária isolada, ou manter só no Claude |
| 37 | Detecção, login, splash | `detectClaudeCli`, splash | `codex --version`, `account/read`, `codex login`, `codex doctor` | 0–1 | Falta versão mínima e orientação de login |
| 38 | Segredos do Codex | — | `~/.codex/auth.json`; `redactJson` já existe | 0 | Nunca ler o `auth.json` |
| 39 | Arquivos globais do usuário | Princípio: nada vai para `~/.claude/settings.json` | O Codex grava *trust* no `config.toml` (`--trust`, `[projects."…"] trust_level`) | 1 | Usar só `-c` e nunca `--trust`. Projeto não confiável pode desligar o MCP e os hooks do projeto |

Contagem que dá ideia do tamanho: 31 comparações `== 'claude'` / `!= 'claude'` em `lib/`, 23 arquivos usando `ClaudeOptions`, 36 usando `claude_args`/`ClaudePermissionMode` e 16 serviços chamando `runReadOnlyClaude`.

---

## 3. Arquitetura proposta

**Objetivo:** as features falam com **intenções do app** e **capacidades**, não com flags Claude. Cada adaptador traduz as intenções para o seu provedor.

```
lib/core/providers/            ← camada neutra (features só importam daqui)
  agent_provider.dart          AgentProvider / AgentRun / ManagedAgentRun (evoluídos)
  agent_event.dart             modelo normalizado (evolução do atual)
  capabilities.dart     NOVO   ProviderCapabilities
  run_intent.dart       NOVO   AgentStartOptions dividido em intenção + extras
  structured_run.dart   NOVO   runStructured() (substitui runReadOnlyClaude)
  provider_resolver.dart       resolve o provedor da execução (já existe em provider_preferences)
  quota_source.dart     NOVO   cota/uso por provedor (Claude /usage | Codex rateLimits)
  workspace_assets.dart NOVO   instruções, skills, MCP e agentes por provedor
lib/core/claude/               adaptador Claude (claude_args, process, hooks, usage_poller…)
lib/core/codex/                adaptador Codex (App Server) + codex_hooks/codex_config NOVOS
```

1. **`ProviderCapabilities`** (por provedor e modelo, preenchido a partir do `model/list` e da versão): `images`, `structuredOutput`, `budgetUsd`, `maxTurns`, `planMode`, `readOnlyEnforced`, `managedHooks`, `subagents`, `agentFiles`, `mcpConfig`, `appMcpServer`, `compactNow`, `steerMidTurn`, `liveApprovalChange`, `quotaSource`, `costUsd`, `nativeReview`, `revertConversation`. A UI esconde ou desabilita com a etiqueta "Só Claude Code"/"Só Codex", e os serviços **não montam** opções sem suporte. Isso resolve os bloqueios do DT-56 e elimina os `provider == 'claude'` espalhados.
2. **Divisão do `AgentStartOptions`.** Ficam como **intenção** do app: `cwd`, `mode` (`PromptMode`), `access` (perguntar/editar/YOLO), `model`, `effort`, `resume`/`fork`, `instructions`, `outputSchema`, `images`, `env`, `appMcp`. Vão para **extras por provedor**: `ClaudeExtras` (`maxBudgetUsd`, `maxTurns`, `agent`, `agentsJson`, `settingsFile`, `tools`, regras MCP, `autocompact`) e `CodexExtras` (`sandbox`, `approval`, `writableRoots`, `configOverrides`, `autoCompactLimit`). A tabela `permission_policy` vira a função `access → (sandbox, approval)` do adaptador Codex.
3. **Modelo de eventos.** Manter as classes *sealed* de `agent_event.dart` como língua franca: a timeline já depende delas e o histórico salvo em `session_events` está nesse formato. A mudança é **parar de fingir JSON Claude para conceitos que não batem** e acrescentar tipos neutros:
   - `FileChangeEvent{path, kind(add/update/delete), unifiedDiff, before?, after?}`, consumido por `edit_diff`, timeline, mudanças da sessão e replay. O Claude também emite esse tipo a partir de `Edit`/`Write`/`MultiEdit`.
   - `CommandEvent{command, cwd, exitCode, output}` (hoje é o `Bash` disfarçado).
   - `ContextReading{used, window, source, at}` e `CompactionEvent{state}`, **a combinar com o contrato da SPEC-087**.
   - `QuotaSnapshot` (substitui o `RateLimit` só Claude).
   - Cada evento persistido leva `provider` + JSON bruto sanitizado (já é assim). Eventos antigos do Claude continuam sendo lidos pelo caminho atual, e o adaptador Claude converte para os tipos neutros na leitura (sem migrar dados).
4. **Transporte do Codex:** App Server, **um processo por execução**, como hoje. Isso dá isolamento de cwd, ambiente (`PROMPTORIUM_AGENTE`) e grupo de processos. O daemon compartilhado (`app-server daemon`) fica para depois.
5. **`runStructured()`** neutro substitui o `runReadOnlyClaude`. Recebe a intenção (somente leitura, schema, prompt, imagens) e o provedor resolvido. No Claude usa `--json-schema`, no Codex `outputSchema` com sandbox `read-only` e aprovação `never`. Mantém o ledger de uso (tokens; custo só quando `costUsd`).
6. **Resolução do provedor** (já parcialmente na SPEC-003): provedor vinculado à execução > escolha explícita > padrão por tipo de execução (D7) > projeto > global > `claude`. Nunca cair para outro provedor em silêncio.
7. **Conferência de versão:** na partida, `codex --version` ≥ mínimo. Opcionalmente, `generate-json-schema` em cache por versão para conferir se os métodos usados existem. Se faltar algum, o Codex fica "incompatível" no rodapé com a orientação de atualizar.

---

## 4. Divisão em specs (numeração do épico #332)

Tamanho: **P** ≈ 1–2 dias, **M** ≈ 3–5, **G** ≈ 1–2 semanas (com testes e e2e). Pelas memórias do projeto: uma spec por PR, specs grandes com branch pai e filhos, e PR para a main com "Closes #N".

### Onda 0 — Fundação (sem mudança visível para quem usa Claude)

| Spec | Objetivo | Escopo | Depende | Tam. | Destrava |
|---|---|---|---|---|---|
| **SPEC-093 · Sondagem do Codex 0.170** | Trocar suposições por evidência registrada | `docs/pesquisa/codex-0170.md`: *handshake* do App Server; diff entre o schema e o adaptador; `untrusted` na CLI; **commit num worktree com `workspace-write`** (*writable roots*); repasse de ambiente no sandbox; `project_doc_fallback_filenames` com `CLAUDE.md`; injeção de hooks sem tocar no `~/.codex`; pastas de skills e `skills/extraRoots/set`; `account/rateLimits/read`; imagens por data URL; `outputSchema`; `thread/compact/start`. Atualizar o `fake_codex` com *fixtures* reais | — | P–M | Tudo (decide D2, D5, os hooks e a viabilidade de worktree) |
| **SPEC-094 · Capacidades e opções por provedor** | Fim dos `== 'claude'` e dos bloqueios do DT-56 | `ProviderCapabilities`; dividir `AgentStartOptions` em intenção + extras; `runStructured`/`readonly_run` só manda o que o provedor suporta; modelo e esforço por provedor (chaves já existentes); versão mínima e estado "incompatível" | 093 | M | MVP, 100 |
| **SPEC-095 · Eventos neutros** (arquivo, comando e uso) | A timeline entende edições e comandos de qualquer provedor | `FileChangeEvent`, `CommandEvent`, `ContextReading` / `QuotaSnapshot`; `edit_diff`, timeline, mudanças da sessão e replay consomem os tipos neutros; o Claude converte na leitura. **Combinar com a SPEC-087** (contrato de medição) | 093 (e acordo com a 087) | M | MVP (cartões de edição), 107, 110 |

### Onda 1 — MVP "usar o Codex no Promptorium" (0.23; proposta original 0.22)

O menor recorte útil: **conversar no Prompt (Perguntar/Planejar/Editar) e abrir Sessões em worktree com o Codex**, com aprovações, interromper, retomar, terminal e cota no rodapé. Os demais fluxos continuam no Claude, com a etiqueta "Só Claude Code" quando o Codex estiver selecionado.

| Spec | Objetivo | Escopo | Depende | Tam. | Destrava |
|---|---|---|---|---|---|
| **SPEC-096 · Codex no Prompt e nas Sessões** | Religar o Codex nos dois fluxos interativos | Interruptor por fluxo (substitui o `codexEnabledProvider` global); Nova sessão, Prompt e rodapé mostram o Codex; modelos do `model/list`; interromper ligado na UI; cancelado ≠ falha; grupo de processos e limpeza de órfãos; retomar e bifurcar (com vínculo ao pai); `codex resume` no terminal (corrigir o `untrusted`); `writableRoots` do worktree; YOLO só em worktree (SPEC-007); aprovar no escopo; detecção e login; e2e com xdotool | 094, 095 | G (pai + filhos) | Uso diário; base das ondas 2–4 |
| **SPEC-097 · Cota do Codex no rodapé** | Saber quanto resta do plano ChatGPT | `account/rateLimits/read` na abertura e por intervalo, `account/rateLimits/updated` durante as execuções, régua por provedor ativo, "custo indisponível" no lugar de US$ 0 no ledger e no custo por spec | 094 | P | Orquestrador por cota (109) |

### Onda 2 — Memória e fluxo de specs (0.23)

| Spec | Objetivo | Escopo | Depende | Tam. | Destrava |
|---|---|---|---|---|---|
| **SPEC-098 · Memória com ai-memory** | Memória do projeto compartilhada entre Claude e Codex (#83) | Integração **opcional** com o [ai-memory](https://github.com/akitaonrails/ai-memory): detectar, ligar por workspace, usar nos dois provedores; o app não vira motor de memória (decisão 13) | 093, 096 | M | 099 |
| **SPEC-099 · Passar o trabalho entre agentes** | Trocar de provedor sem perder o fio | Transferência explícita entre Claude e Codex (nova sessão com resumo/memória), já que nunca se troca no meio de uma execução (decisão 4) | 096, 098 | M | 101, 109 |
| **SPEC-100 · Execuções estruturadas em qualquer provedor** | Planner e assistentes de spec rodando no Codex | Migrar os 16 chamadores de `runReadOnlyClaude` para `runStructured` (planner, spec_planner, split_specs, design, answers, verifier, decisão/classificação de etapa, projeto, custom_stack, auto planner, skill_writer, vibe_guard); provedor por tipo de execução em Configurações → Consumo (D7); protótipo de telas só Claude, ou em pasta isolada | 094 | M–G | 101, 102 |
| **SPEC-101 · Executar spec com o Codex** | Quadro e autopilot ponta a ponta com o Codex | Provedor fixo por execução da spec; etapas, lotes, retomadas, correções automáticas, gates, continuação por limiar de contexto com `ThreadTokenUsage`; marcar commits (SPEC-048) e vigia pós-turno (SPEC-085 R2); notificações e Atividades com o provedor; sessão de conflito (SPEC-092) | 096, 100 | G | Fluxo completo |
| **SPEC-102 · Review automático com o Codex** | Revisor por provedor | Provedor próprio do revisor (herda da execução); `review/start` alvo `baseBranch` **ou** `runStructured` com o schema atual de achados; normalização para os comentários do diff (SPEC-009) | 100 | M | Duelo e Comparar no review |
| **SPEC-103 · Hooks gerenciados nos dois provedores** | Bloqueio de comandos, formatador, vigia e fim de sessão também no Codex | Traduzir `managed_hooks` para hooks do Codex (`preToolUse`/`postToolUse`/`sessionEnd`) via override temporário, conforme o que a 093 provar; execpolicy `.rules` temporária como alternativa; *trust* sem gravar no global; fallback atual quando não suportado | 093, 096 | M | Paridade de segurança |

### Onda 3 — Ecossistema do provedor (0.24)

| Spec | Objetivo | Escopo | Depende | Tam. |
|---|---|---|---|---|
| **SPEC-104 · Instruções (AGENTS.md) e skills** | `CLAUDE.md`/`AGENTS.md` e skills sem duplicação | Fonte única de instruções (D5); criação de projeto oferece `AGENTS.md`; tela Skills lista as do Codex via `skills/list`; `extraRoots` apontando para `.claude/skills` (se a 093 confirmar) | 093 | M |
| **SPEC-105 · MCP por provedor** | Tela MCP com abas Claude e Codex | `codex mcp list/add/remove`, `mcpServerStatus/list`, OAuth; MCP do app (SPEC-052) injetado por `-c`; regras permitir/bloquear por ferramenta (se houver suporte); espelhar servidor entre provedores (D10) | 094 | M–G |
| **SPEC-106 · Agentes no Codex** | Usar `.claude/agents` com o Codex | Mapear prompt de sistema → `developerInstructions`, `model` → modelo Codex equivalente (tabela editável), `tools` → sandbox/aprovação; etiqueta do que não se aplica (subagentes, `maxTurns`) | 094, D9 | M |
| **SPEC-107 · Contexto e compactação no Codex** | SPEC-087 com dados do Codex | `ContextReading` a partir de `ThreadTokenUsage`; marcadores `thread/compacted`; **"Compactar agora"** via `thread/compact/start`; limiar via `model_auto_compact_token_limit` | 095, SPEC-087 | P–M |

### Onda 4 — Diferenciais multi-provedor (0.25)

| Spec | Objetivo | Depende | Tam. |
|---|---|---|---|
| **SPEC-108 · Comparar Claude × Codex** (amplia a SPEC-079): um provedor por lado, métricas de tokens/tempo/diff, "ficar com este lado" | 096, 097 | M |
| **SPEC-109 · Orquestrador multi-provedor** (amplia a SPEC-035): degraus com modelos Codex, regras por provedor, desvio para o outro provedor quando a cota acaba | 097, 101 | M |
| **SPEC-110 · Replay e restauração com o Codex**: replay pelos itens da thread e diffs; restaurar arquivos **e** conversa (`thread/revert`) | 095, 096 | P–M |

**Caminho crítico do MVP:** 093 → 094 ∥ 095 → 096 → 097 (cerca de 3 a 4 semanas). Depois disso, 100 → 101 é o que entrega "fazer uma spec inteira só com o Codex".

---

## 5. Decisões que você precisa tomar

| # | Decisão | Opções | Recomendação |
|---|---|---|---|
| D1 | **Meta de paridade** | (a) paridade total antes de ligar (como na SPEC-004); (b) liberar por fluxo, com capacidades e etiquetas | **(b).** O critério (a) travou a integração da outra vez |
| D2 | **Transporte** | (a) App Server; (b) `codex exec --json` por rodada; (c) ACP (`codex-acp` + `AcpProvider` atual) | **(a)**: é o único com aprovações, retomada, cota, compactação, review e skills. (b) só como plano B para execuções estruturadas. (c) perde cota, compactação e review |
| D3 | **Modelo de eventos** | (a) continuar fingindo JSON Claude; (b) reescrever tudo neutro; (c) manter as classes atuais + tipos neutros onde não bate (arquivo, comando, uso) | **(c)**: menor risco para o histórico salvo, e conserta o que de fato quebra |
| D4 | **Processo do App Server** | (a) um por execução; (b) daemon compartilhado | **(a)** agora (isolamento de cwd, ambiente e limpeza). Reavaliar (b) se a memória pesar |
| D5 | **Instruções do projeto** | (a) `CLAUDE.md` como fonte + *fallback* no Codex; (b) `AGENTS.md` como fonte + `CLAUDE.md` que o importa; (c) os dois mantidos separados | **(a)** se a SPEC-093 confirmar o `project_doc_fallback_filenames` por `-c` (nada muda nos repositórios). Senão, (b) na criação de projeto |
| D6 | **Semântica dos modos no Codex** | Perguntar/Planejar = `read-only` + `never`; Editar = `workspace-write` + `on-request`; Refinar = `workspace-write` + aprovação de cada edição; YOLO = `danger-full-access` + `never`, só em worktree | **Aceitar** esse mapeamento. Planejar sem `ExitPlanMode`: "Executar plano" abre um turno novo em Editar |
| D7 | **Granularidade da escolha** | (a) padrão global/projeto + escolha por execução (já existe); (b) também por tipo de execução (ex.: planner no Claude, sessões no Codex) | **(b)** na SPEC-098. Por execução nunca troca no meio: trocar de provedor = nova sessão com transferência explícita |
| D8 | **Custo com o Codex** | (a) só tokens, "custo indisponível"; (b) estimar US$ pela tabela da API | **(a)**: você usa assinatura, e uma estimativa em US$ seria enganosa (mesma lógica do plano Max) |
| D9 | **Agentes `.claude/agents` no Codex** | (a) só Claude, com etiqueta; (b) mapear (SPEC-106) | **(a)** no MVP e na onda 2. (b) na onda 3, se você usar agentes com frequência |
| D10 | **MCP entre provedores** | (a) cada provedor com a própria configuração; (b) o app espelha servidores nos dois | **(a)** com abas, mais um botão "copiar para o Codex" opcional. Nunca sincronizar automaticamente arquivos globais |
| D11 | **Sondagens pagas** | Permitir alguns turnos reais (plano ChatGPT) na SPEC-093? | **Sim**, com orçamento curto e listado (cerca de 10 turnos), num repositório temporário |
| D12 | **Versão mínima do Codex** | Fixar ≥ 0.170 e bloquear abaixo? Avisar quando o schema mudar? | **Sim.** Bloquear abaixo do mínimo e avisar (sem bloquear) acima da última versão testada |
| D13 | **Release do MVP** | 0.22 (logo depois da 0.21 e da 087) ou mais tarde | **0.22** com 093–097. A SPEC-087 deve fechar antes da 095, ou junto com ela, para não brigarem em `agent_event.dart` |
| D14 | **Nome da coluna `claudeSessionId`** | Renomear (migração Drift) ou manter | **Manter** e documentar. A migração não traz ganho para o usuário |

---

## 6. Riscos e o destino das specs antigas

### 6.1 Riscos

1. **Protocolo experimental que muda rápido.** O App Server é `[experimental]` e mudou muito entre 0.163 e 0.170 (o `untrusted` sumiu da CLI). *Mitigação:* versão mínima, conferência de schema, `fake_codex` alimentado por *fixtures* reais e e2e a cada atualização do CLI.
2. **Sandbox × worktrees.** Com `workspace-write`, o `git commit` num worktree escreve no `.git` da raiz, fora do cwd. Sem *writable roots*, as etapas não conseguem commitar. *Mitigação:* incluir o *git common dir*. É bloqueador e a SPEC-093 precisa provar a solução.
3. **Ambiente filtrado** (`shell_environment_policy`) pode tirar o `PROMPTORIUM_AGENTE` e quebrar a SPEC-048 sem aviso.
4. **Arquivos globais do usuário.** O Codex tende a gravar *trust* e configuração no `~/.codex/config.toml`. O app deve usar só `-c` e nunca `--trust`. Hooks podem exigir *trust*.
5. **Hooks.** Formato e injeção ainda não comprovados. Até lá, o vigia de segredos e o bloqueio de comandos só funcionam pós-turno no Codex (garantia menor). Isso precisa aparecer na UI.
6. **Semântica de permissão diferente.** Um "Editar" do Codex não é igual ao `acceptEdits` do Claude. Aviso por provedor e testes de garantia (Perguntar nunca escreve).
7. **Sobreposição com a SPEC-087** em `agent_event.dart`, no contrato de uso e no painel de contexto. *Mitigação:* combinar o contrato neutro agora (um comentário na spec ou issue da 087) e fazer a 095 depois do merge da 087.
8. **Matriz de testes dobrada e custo de manutenção.** Cada recurso novo passa a precisar de "e no Codex?". *Mitigação:* capacidades + etiqueta "Só Claude Code" como resposta aceitável, e um checklist no template de spec.
9. **Cota do plano ChatGPT e modelos** (`gpt-6.x-sol/terra/luna`, esforço até `ultra`) com nomes e limites que mudam. Nunca fixar no código, sempre ler do `model/list`.
10. **Processos órfãos do `codex app-server`** (o DT-56 já apontava). Grupo de processos e limpeza na saída (`app_shutdown.dart`).
11. **Credenciais.** `auth.json` e *tokens* em payloads. Manter o `redactJson` e nunca ler o `auth.json`.
12. **Escopo crescendo.** Já foi o motivo do desligamento. *Mitigação:* o MVP tem fim claro (Prompt + Sessões + cota) e cada onda é entregável sozinha.

### 6.2 Specs antigas 002–007

| Spec | Status | Destino recomendado |
|---|---|---|
| SPEC-002 (adaptador e contrato) | rascunho | **Substituir** pela 094 + 095 + 096. Os requisitos R1–R6 viram checklist de aceite dessas specs. Mudar o status para `substituida` com links |
| SPEC-003 (seleção e persistência) | rascunho | **Fechar como absorvida.** A maior parte já existe (chaves, colunas, rodapé). O que falta (padrão global na UI, provedor nas listas e notificações, transferência ao trocar) entra na 096, e o padrão por tipo de execução na 100 |
| SPEC-004 (paridade de opções) | rascunho | **Arquivar como referência.** A matriz serve de insumo, mas o critério "lacuna não satisfaz" sai. Substituída pelas capacidades (094) e pelas 104–107 |
| SPEC-005 (Codex em todos os fluxos) | rascunho | **Substituir** pela 100, 101, 102, 108 e 109 |
| SPEC-006 (seletor no rodapé) | concluída | **Manter.** Revalidar com o Codex ligado como critério da 096 e tirar a nota "inativa" quando o MVP sair |
| SPEC-007 (YOLO do Codex) | concluída | **Manter.** Revalidar flags e políticas no 0.170 (`codex --yolo --help` e `codex resume --yolo --help` ainda passam no 0.170; o resto entra na SPEC-093) e tirar a nota "inativa" no MVP |
| DT-56 / DT-08 | aberto | Fechar o DT-56 quando o MVP sair. Atualizar o DT-08 para apontar para esta série |

Sugestão de registro (quando for criar as specs): uma issue-mãe "Codex ao lado do Claude Code" com as ondas, como na #268/#278, e `docs/specs/README.md` com a seção Codex reescrita apontando 002–005 para as substitutas.
