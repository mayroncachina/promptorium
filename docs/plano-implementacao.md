# Plano de implementação — Promptorium

IDE desktop (Flutter, Linux) para gerenciar sessões, tarefas, specs e agentes do **Claude Code CLI**.

- Mockups (9 telas): https://claude.ai/artifact/SjkEe4XHWMvccd1VaQGAua
- Débito técnico: [`debito-tecnico.md`](debito-tecnico.md)
- Material de pesquisa: [`pesquisa/`](pesquisa/)

**Como usar este plano:** cada fase é autocontida e pode ser executada numa conversa nova.
Antes de cada fase, leia a seção **Fase 0 — APIs permitidas** e as referências citadas na fase.
Não invente métodos nem flags: se algo não estiver listado aqui ou na documentação citada, verifique antes.

---

## Fase 0 — Descoberta de documentação (CONCLUÍDA em 2026-10-14)

### 0.1 Ambiente

| Item | Situação |
|---|---|
| Flutter local | **3.32.8 / Dart 3.8.1 — desatualizado.** Estável atual: 3.47.7 / Dart 3.13.5 |
| Toolchain Linux | OK (clang 18, cmake 3.28, ninja, GTK3, libsqlite3-dev) |
| Faltam | `libayatana-appindicator3-dev` (tray), `libnotify-dev` (notificações) |
| Claude Code CLI | 2.1.300 em `~/.local/bin/claude` |

**Decisão:** atualizar o Flutter (`flutter upgrade`) antes da Fase 1. Muitos pacotes atuais exigem Dart ≥ 3.10.

### 0.2 Claude Code CLI — APIs permitidas

Fontes: `claude --help` (v2.1.300), code.claude.com/docs/en/{cli-reference, headless, sub-agents, mcp, statusline, sessions, agent-sdk/typescript, agent-sdk/user-input}. Exemplo real de saída: [`pesquisa/stream-json-exemplo.jsonl`](pesquisa/stream-json-exemplo.jsonl).

**Comando base de uma sessão:**
```
claude -p --input-format stream-json --output-format stream-json --verbose
       --include-partial-messages
       --session-id <uuid>            # nova sessão (UUID válido)
       | --resume <uuid>              # retomar (repassar de novo --mcp-config/--settings/--add-dir)
       [--fork-session]               # com --resume: cria novo id (aceita --session-id <uuid> junto — testado)
       --model <opus|sonnet|haiku|fable|inherit|id>
       --agent <nome>                 # thread principal roda como o subagente (Fase 5; listado no --help)
       --permission-mode <default|acceptEdits|plan|auto|dontAsk>
       --permission-prompt-tool stdio # aprovações pela própria stdin/stdout
       --allowedTools "Read" "Bash(git *)"   --disallowedTools ...
       --append-system-prompt <txt>   (ou --append-system-prompt-file)
       --mcp-config <arquivo|json> --strict-mcp-config
       --agents <json|arquivo>
       --max-budget-usd <n>  --max-turns <n>   # --max-turns existe, mas não aparece no --help
       --json-schema <schema>         # saída estruturada (usar em "gerar tarefas")
```

**Entrada (stdin, NDJSON, uma linha por mensagem):**
```json
{"type":"user","message":{"role":"user","content":"texto"},"parent_tool_use_id":null}
```
⚠ A stdin **deve continuar aberta** enquanto a sessão estiver viva (senão: "Tool permission stream closed before response received").

**Saída (stdout, NDJSON) — tipos de evento:**

| `type` / `subtype` | Uso no app |
|---|---|
| `system/init` | `session_id`, `model`, `tools[]`, `mcp_servers[{name,status}]`, `agents[]`, `permissionMode` |
| `system/status`, `system/api_retry`, `system/permission_denied`, `system/hook_*` | status / ignorar desconhecidos |
| `stream_event` | `event.type` = message_start / content_block_start / content_block_delta (`text_delta`, `thinking_delta`) / …_stop — texto ao vivo |
| `assistant` | **uma linha por bloco de conteúdo** (text, thinking, tool_use), mesmo `message.id` |
| `user` com `tool_result` | resultado de ferramenta; `parent_tool_use_id != null` ⇒ mensagem de **subagente** |
| `rate_limit_event` | `rate_limit_info.unifiedWindows.five_hour.utilization` (0–1), `.seven_day`, `resetsAt` (epoch) → rodapé |
| `control_request` (`subtype: can_use_tool`) | pedido de aprovação (ver 0.3) |
| `result` | `subtype` (success / error_max_turns / error_max_budget_usd / error_during_execution), `total_cost_usd`, `usage{input_tokens, output_tokens, cache_*}`, `num_turns`, `duration_ms`, `permission_denials[]` |

**Arquivos do Claude Code:**

| O quê | Onde |
|---|---|
| Subagentes globais / projeto | `~/.claude/agents/*.md` / `<repo>/.claude/agents/*.md` — frontmatter YAML: `name`, `description` (obrigatórios), `tools`, `disallowedTools`, `model`, `permissionMode`, `maxTurns`, `mcpServers`, `color`, … corpo = prompt. Precedência: `--agents` > projeto > usuário |
| MCP usuário / local / projeto | `~/.claude.json` (`mcpServers` no topo / `projects["/abs"].mcpServers`) / `<repo>/.mcp.json`. Tipos: `stdio`(command,args,env), `http`(url,headers), `sse`(obsoleto) |
| Transcrições | `~/.claude/projects/<cwd com não-alfanuméricos → '-'>/<session-id>.jsonl` — **formato interno, pode mudar** |
| Listar agentes | ⚠ `claude agents --json` (2.1.300) lista **sessões ativas** (`pid`, `cwd`, `kind`, `sessionId`, `name`, `status`), não definições. Para conferir definições sem custo: `system/init.agents` de um `claude -p` com `--model` inválido (ver Fase 7) |

### 0.3 Aprovações — decisão revista

**Usar `--permission-prompt-tool stdio`** (testado ao vivo na v2.1.300). Não é preciso servidor MCP interno — é o mesmo caminho do Agent SDK.
Exemplo funcional (Python, ~15 linhas): [`pesquisa/permissao-stdio-responder.py`](pesquisa/permissao-stdio-responder.py).

CLI → app (stdout):
```json
{"type":"control_request","request_id":"…","request":{"subtype":"can_use_tool","tool_name":"Bash","display_name":"Bash","input":{"command":"…"},"description":"…","permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"…"}],"behavior":"allow","destination":"localSettings"}],"decision_reason":"…","tool_use_id":"toolu_…"}}
```
App → CLI (stdin):
```json
{"type":"control_response","response":{"subtype":"success","request_id":"<mesmo id>","response":{"behavior":"allow","updatedInput":{…}}}}
{"type":"control_response","response":{"subtype":"success","request_id":"<mesmo id>","response":{"behavior":"deny","message":"motivo"}}}
```
"Sempre permitir" = allow + `"updatedPermissions":[<uma das permission_suggestions>]`.
Só chegam ao app as chamadas que nenhuma regra resolveu (`acceptEdits`/allow rules resolvem antes). Tratar `control_cancel_request` fechando o card.

> Consequência: o servidor "promptorium-approvals" do mockup MCP deixa de existir.

### 0.4 Pacotes Flutter — versões alvo (após `flutter upgrade`)

| Necessidade | Pacote | Versão | Notas |
|---|---|---|---|
| Estado | `flutter_riverpod` | ^3.4 | **sem** riverpod_generator; `Notifier`/`AsyncNotifier` + `NotifierProvider` |
| Banco | `drift` ^2.35, `drift_flutter` ^0.3, dev: `drift_dev`, `build_runner` | | `driftDatabase(name:, native: DriftNativeOptions(databaseDirectory: …))`; sqlite embutido no build (não usar `sqlite3_flutter_libs`) |
| Terminal | `xterm` 4.0.0 + `flutter_pty` 0.4.2 | | copiar fiação de `~/.pub-cache/hosted/pub.dev/xterm-4.0.0/example/lib/main.dart` |
| Painéis | `multi_split_view` ^3.6 | | `MultiSplitView(initialAreas: [Area(size:…), Area(flex:1)], builder:)` |
| Editor | `re_editor` 0.10 + `re_highlight` | | `CodeEditor(controller: CodeLineEditingController(), style: CodeEditorStyle(fontSize:…))`; busca: copiar `example/lib/find.dart`; **zoom = reconstruir com outro `fontSize`** |
| Markdown | `flutter_markdown_plus` | ^1.0 | `flutter_markdown` foi **descontinuado** |
| Janela | `window_manager` | ^0.5 | `ensureInitialized()` + `waitUntilReadyToShow` |
| Notificações | `local_notifier` | 0.1.6 | precisa `libnotify-dev` |
| Bandeja (opcional) | `tray_manager` | ^0.8 | precisa `libayatana-appindicator3-dev`; API mudou na 0.8 — conferir README |
| Utilidades | `path_provider`, `uuid` ^4.6, `yaml` (frontmatter) | | |
| Diff | — | | parsear `git diff --unified` manualmente |

### 0.5 Anti-padrões (valem para todas as fases)

- ❌ `flutter_markdown`, `riverpod_generator`, `sqlite3_flutter_libs` (com sqlite3 3.x)
- ❌ Ler stdout do CLI sem `LineSplitter` (cada linha = 1 JSON); ❌ quebrar em tipos desconhecidos — **ignorar** `type`/`subtype` que não conhecer
- ❌ Fechar a stdin da sessão enquanto ela está viva
- ❌ `--dangerously-skip-permissions` / `bypassPermissions`
- ❌ Editar `~/.claude.json` na mão — usar `claude mcp add/remove/list`
- ❌ Depender do formato dos `.jsonl` de transcrição para lógica — só exibição, com parse tolerante
- ❌ Inventar flags; conferir em `cli-reference` (lembrar: `--help` não lista tudo)

---

## Fase 1 — Ambiente e esqueleto do projeto

**Implementar**
1. `flutter upgrade` (alvo 3.47.x) e `sudo apt install libnotify-dev libayatana-appindicator3-dev`.
2. `flutter create --platforms=linux --org dev.promptorium --project-name promptorium .` na raiz do repositório; `git init`.
3. Adicionar dependências da tabela 0.4 (`flutter pub add …`).
4. Estrutura:
   ```
   lib/
     main.dart  app.dart
     core/      claude/ (processo, eventos)  git/  fs/  config/
     data/      db/ (drift)  repos/
     features/  splash/ sessions/ prompt/ specs/ tasks/ agents/ review/ code/ mcp/ settings/
     ui/        theme/ (tokens)  shell/ (barra lateral, rodapé, título)  widgets/
   test/  fixtures/ (copiar docs/pesquisa/stream-json-exemplo.jsonl)
   ```
5. Tokens de tema copiados dos mockups: fundo `#0E1014`, painel `#14171D`, borda `#252B35`, texto `#E7E9EE`, secundário `#A0A8B6`, âmbar `#F2A541`, verde-água `#4FD1B5`, azul `#8EA4C8`, vermelho `#F27A6E`, lilás `#C79BF2`; fontes IBM Plex Sans + JetBrains Mono (empacotar em `assets/fonts`).
6. `window_manager`: tamanho inicial 1440×900, mínimo 1100×700, título "Promptorium".
7. Ícone: recortar a imagem do canvas, gerar 512/256/128/64/48/32 em `assets/icon/`; arquivo `.desktop` em `linux/`.

**Referências:** tabela 0.4; README do window_manager 0.5.

**Verificação**
- [x] `flutter --version` ≥ 3.47 (3.47.7 / Dart 3.13.5)
- [x] `flutter analyze` sem problemas
- [x] `flutter run -d linux` abre janela escura com título correto (bundle debug executado sem erros; conferência visual pendente)
- [x] `grep -r "flutter_markdown:" pubspec.yaml` não retorna nada

**Anti-padrões:** não adicionar pacotes fora da tabela sem registrar aqui.

**Notas da execução (2026-10-14):**
- `cupertino_icons` (padrão do `flutter create`) removido — fora da tabela 0.4.
- `tray_manager` 0.8.0 resolveu sem conflito e foi adicionado.
- `sqlite3_flutter_libs 0.6.0+eol` e `sqlcipher_flutter_libs 0.7.0+eol` aparecem como **transitivas** de `drift_flutter`; são shims vazios do sqlite3 3.x (não violam o anti-padrão 0.5, que trata de dependência direta).
- IBM Plex Sans: o Google Fonts só publica a versão variável; os TTF estáticos vieram de `IBM/plex/packages/plex-sans/fonts/complete/ttf`.
- Ícone da janela: definido no runner GTK (`linux/runner/my_application.cc`, `gtk_window_set_icon_from_file`), pois `windowManager.setIcon` é documentado como só Windows. O runner também usa título "Promptorium", 1440×900 e fundo `#0E1014`.

---

## Fase 2 — Shell da IDE + Splash

**Implementar**
1. `AppShell`: barra de título (logo, seletor de workspace, busca Ctrl+K, botão de ação contextual), barra lateral com 9 itens + engrenagem (ordem dos mockups: Sessões, Prompt, Specs, Tarefas, Agentes, Review, Código, MCP), área de conteúdo, **rodapé fixo** (CLI conectado, sessões, subagentes, MCP, tokens hoje, uso 5h, semana).
2. Navegação entre telas (placeholders) — sem scroll de página: cada tela ocupa a janela; só painéis internos rolam.
3. Atalhos globais (`Shortcuts`/`Actions`): Ctrl+K (paleta — stub), Ctrl+=, Ctrl+-, Ctrl+0 (zoom do editor focado).
4. **Splash** (`CustomPainter` + `AnimationController`, sem pacote): contorno do frasco desenhando, líquido subindo com onda, bolhas, nós conectando, cursor `_` piscando; barra de progresso ligada a passos reais de inicialização: verificar `claude --version` → abrir banco → carregar workspaces → ler MCPs → restaurar sessões. Erro em um passo = mensagem clara (ex.: "Claude Code CLI não encontrado").

**Referências:** mockups 0 · Splash, 1 · Sessões (shell); tokens da Fase 1.

**Verificação**
- [x] Clicar em cada ícone troca a tela; o ícone ativo fica em âmbar (widget test)
- [x] Redimensionar para 1100×700 não gera scroll de página (widget test sem overflow em 1100×700)
- [x] Renomear temporariamente o binário `claude` → splash mostra erro do primeiro passo (coberto por teste com runner injetado e caminho inexistente; teste manual pendente)
- [x] Widget test: `AppShell` renderiza 8 itens de navegação + engrenagem (9 `SideBarItem`)

**Notas da execução (2026-10-14):**
- Nenhum pacote novo. Ícones e splash desenhados com `CustomPainter` a partir dos paths SVG dos mockups (`lib/ui/widgets/svg_path.dart`: parser mínimo M/L/H/V/C/S/Q/T/A/Z).
- "9 itens" do plano = 8 seções + engrenagem (Configurações).
- Splash: a intro do mockup (laço de 7 s) toca uma vez a 1,75× (≈2,6 s, duração mínima); só onda, bolhas, cursor e brilho continuam em laço. Respeita `disableAnimations`.
- Splash desenhado como cartão 720×440 centralizado na janela 1440×900 (a janela não é redimensionada — ver DT-11).
- Detecção do CLI tenta `claude` no PATH e depois `~/.local/bin/claude` (atalhos de desktop costumam não ter `~/.local/bin` no PATH).
- `StartupController` (`lib/features/splash/startup_controller.dart`): passos em `startupStepsProvider`; banco, workspaces, MCP e sessões são `StubStep` com TODO da fase responsável.
- `footerStatsProvider`: só o status do CLI é real; o resto mostra "—" até a Fase 5.
- Zoom: `editorZoomProvider('specs'|'code')`, 70–200 %, passo 10; Ctrl+=/-/0 agem no editor da tela ativa. Ainda não persiste (Fase 3).
- `version` do pubspec passou para `0.1.0+1` (igual ao mockup; `AppInfo.version`).

---

## Fase 3 — Camada de dados (drift)

**Implementar** tabelas:
`workspaces(id, path, name)`, `specs(id, workspaceId, code, title, status, path)`, `tasks(id, specId, code, title, status, agentName, dependsOn)`, `sessions(id uuid, workspaceId, taskId?, agentName, worktreePath, branch, status, model, costUsd, tokensIn, tokensOut, startedAt, endedAt)`, `session_events(id, sessionId, seq, type, json)`, `conversations(id, workspaceId, title, provider, model, sessionId)`, `saved_prompts(id, command, description, body, uses)`, `agent_settings(agentName, scope, permissionMode, budgetUsd, maxTurns, mcpServers)`, `mcp_tool_rules(server, tool, rule)`.
Repositórios + providers Riverpod (`AsyncNotifier`).

**Referências:** drift docs (getting started / Flutter setup), `driftDatabase(...)` em 0.4.

**Verificação**
- [x] `dart run build_runner build` sem erros
- [x] Testes de repositório com banco em memória (CRUD de cada tabela)
- [x] Banco criado em `~/.local/share/promptorium/` (via `path_provider`) — conferido executando o bundle debug: `promptorium.sqlite` com as 10 tabelas, `user_version = 1`

**Anti-padrões:** não guardar segredos (tokens de MCP) no banco.

**Notas da execução (2026-10-14):**
- Nenhum pacote novo. Código gerado (`lib/data/db/app_database.g.dart`) é **versionado** — o build funciona sem rodar o build_runner; regenerar após mudar tabelas. Obs.: o build_runner 2.16 ignora (com aviso) `--delete-conflicting-outputs`.
- Esquema final (`lib/data/db/app_database.dart`, `schemaVersion = 1`, `PRAGMA foreign_keys = ON` no `beforeOpen`):
  - `workspaces(id, path UNIQUE, name, created_at)`
  - `specs(id, workspace_id→workspaces CASCADE, code, title, status textEnum<SpecStatus> = draft, path)`, UNIQUE(workspace_id, code)
  - `tasks(id, spec_id?→specs SET NULL, workspace_id→workspaces CASCADE, code, title, status textEnum<TaskStatus> = backlog, agent_name?, depends_on JSON '[]' (List<String>), created_at)`, UNIQUE(workspace_id, code)
  - `sessions(id TEXT PK uuid, workspace_id→CASCADE, task_id?→tasks SET NULL, agent_name?, worktree_path, branch, status textEnum<SessionStatus> = running, model, cost_usd 0, tokens_in 0, tokens_out 0, started_at, ended_at?)`
  - `session_events(id, session_id→sessions CASCADE, seq, type, json, created_at)`, UNIQUE(session_id, seq)
  - `conversations(id, workspace_id→CASCADE, title, provider = 'claude', model, session_id?→sessions SET NULL, created_at)`
  - `saved_prompts(id, command UNIQUE, description = '', body, uses 0)`
  - `agent_settings(agent_name, scope textEnum<AgentScope>, permission_mode?, budget_usd?, max_turns?, mcp_servers JSON '[]')`, PK(agent_name, scope)
  - `mcp_tool_rules(server, tool, rule textEnum<McpRule>)`, PK(server, tool)
  - `app_settings(key PK, value)` — chaves em `AppSettingKeys`: `workspace.active`, `ui.lastSection`, `editor.zoom.<editor>`
- Enums (`lib/data/db/enums.dart`) gravados pelo `name` — renomear valor = migração. `permission_mode` ficou texto livre (o valor `default` do CLI é palavra reservada em Dart).
- Local do banco: pai de `getApplicationSupportDirectory()` (no Linux `$XDG_DATA_HOME/dev.promptorium.promptorium`) + `promptorium/` → `~/.local/share/promptorium/promptorium.sqlite`.
- Repositórios (`lib/data/repos/`, um por agregado; eventos de sessão ficam no `SessionsRepo`) e providers em `lib/data/providers.dart`: `Provider` para banco/repos, `StreamProvider`(`.family`) para as listas. `appSettingsProvider` (`Notifier<Map>`) é uma cópia em memória de `app_settings` carregada no splash, para leitura síncrona no `build` dos notifiers; gravações vão ao banco em segundo plano. `SessionsRepo.markLiveAsInterrupted()` já existe para a Fase 5 (ainda não chamado).
- Splash: "Abrindo banco local…" = `OpenDatabaseStep` (abre/migra + carrega `app_settings`); "Carregando workspaces…" = `LoadWorkspacesStep` (seleção inválida cai no primeiro workspace ou é limpa). Worktrees ficam para a Fase 4.
- Seletor de workspace (barra de título → diálogo `lib/ui/shell/workspace_picker.dart`): lista, seleciona, remove (só o registro) e "Adicionar pasta…" com campo de caminho (aceita `~`), validado por `git -C <p> rev-parse --show-toplevel` (`lib/core/git/git_root.dart`); registra a raiz do repositório. Sem file picker (nenhum pacote disponível). Branch atual no botão: Fase 4.
- Zoom por editor e última tela persistem em `app_settings` (DT-13/DT-14 resolvidos).
- Testes de widget: `NativeDatabase.memory()` funciona sob FakeAsync, mas o drift cancela streams com um `Timer` zero — desmontar a árvore e `pump(Duration.zero)` no fim; IO real (Directory/Process) não roda sob FakeAsync, por isso `gitRootResolverProvider` é injetável.

---

## Fase 4 — Núcleo: ClaudeProcess, eventos, Git

**Implementar**
1. `sealed class ClaudeEvent` com `fromJson` para cada linha da tabela 0.2 + `UnknownEvent` (fallback).
2. `ClaudeProcess`: `Process.start('claude', args, workingDirectory:)`; stdout → `utf8.decoder` → `LineSplitter` → `jsonDecode` → `ClaudeEvent`; `send(String)` escreve a linha de entrada; `respondPermission(requestId, allow|deny, …)`; `stop()` (SIGTERM); stderr para log.
3. `ClaudeArgsBuilder`: monta args a partir de agente + configurações (flags da 0.2).
4. `GitService`: `worktree add -b pr/<slug> ~/.promptorium/worktrees/<slug>`, `worktree remove`, `diff --unified`, `status --porcelain`, `merge`, `log`.
5. `DiffParser` (hunks `@@`, linhas `+`/`-`/espaço).
6. `UsageTracker`: soma `result.usage` por dia; guarda o último `rate_limit_event`.

**Referências:** 0.2, 0.3; `pesquisa/stream-json-exemplo.jsonl`; `pesquisa/permissao-stdio-responder.py` (portar para Dart).

**Verificação**
- [x] Teste: parse do fixture gera `init → stream_event… → assistant → rate_limit_event → result` sem `UnknownEvent` (exceto `system/hook_*`, que viram `SystemOther`)
- [x] Teste de integração manual (`--model haiku --max-budget-usd 0.05`): pedido de Bash gera `control_request`; responder allow → comando roda (2026-10-15: `success`, 2 turnos, US$ 0,0028, 0 eventos desconhecidos)
- [x] Teste do `DiffParser` com diff real (inclui `git apply -R --check` de um hunk isolado)
- [x] Teste do `GitService` num repositório temporário (criar/remover worktree, status, diff, merge, log)

**Anti-padrões:** 0.5 inteiro; não usar `Process.run` para sessões longas.

**Notas da execução (2026-10-15):**
- Nenhum pacote novo. Arquivos: `lib/core/claude/{claude_event,claude_args,claude_process,usage_tracker}.dart`, `lib/core/git/{git_service,diff_parser}.dart`; testes em `test/core/{claude,git}/` e `test/integration/`.
- `ClaudeEvent` (sealed): `SystemInit`, `SystemStatus`, `SystemOther`, `StreamDelta` (text/thinking), `StreamOther` (demais `stream_event`), `AssistantMessage` (blocos `TextBlock`/`ThinkingBlock`/`ToolUseBlock`/`OtherBlock`), `ToolResult`, `RateLimit`, `PermissionRequest`, `ControlCancel`, `Result` (+ `Usage`), `UnknownEvent` (`raw` = linha inválida). `fromJson` nunca lança; `ClaudeEvent.expand` gera um `ToolResult` por bloco quando uma linha `user` traz vários; `parseLine` decodifica a linha. Cuidado: em subclasses, `json` resolve para o `json` de `dart:convert` se ele for importado sem `show` (escopo léxico vence o membro herdado).
- `ClaudeOptions` (imutável, `toArgs()`) no lugar de um builder; `ClaudePermissionMode` não tem `bypassPermissions`. Flags variádicas (`--allowedTools`, `--disallowedTools`) saem no fim, um valor por argv; `--mcp-config` repetido por arquivo.
- `ClaudeProcess.allow` sem `updatedInput` reenvia o `input` original do pedido (guardado até a resposta / `control_cancel_request`), igual ao responder Python. Escritas na stdin são serializadas (IOSink não aceita escrita durante `flush`); eventos emitidos antes do primeiro ouvinte ficam em buffer. Escrita após a saída do processo é descartada com aviso em `logs`.
- Executável: `ClaudeCliStep` grava o CLI detectado em `resolvedClaudeCliProvider`; `claudeExecutableProvider` devolve esse caminho (ou o primeiro candidato).
- `GitService`: diretório base dos worktrees configurável (`worktreesBase`, padrão `~/.promptorium/worktrees`) — testes usam pasta temporária. Worktree = `<base>/<repoName>-<slug>`, branch `pr/<slug>`, slug validado (`[a-z0-9_][a-z0-9._-]*`). `status` usa `--porcelain=v1 -z -uall` (renomeações com `origPath`). Extras: `deleteBranch`, `mergeAbort`, `git(args)` genérico. `GitException` guarda stderr **e** stdout (conflito de merge sai no stdout).
- `DiffParser`: fim do hunk decidido pelos contadores do cabeçalho (uma linha removida `-- x` aparece como `--- x`); trata `\ No newline at end of file`, caminhos entre aspas (escapes octais UTF-8), renomeação sem hunk, binário. `hunkPatch(file, hunk)` = cabeçalho do arquivo + um hunk.
- `UsageTracker` (`usageTrackerProvider.handle(event)`): `dailyUsageProvider` (soma por dia local, `app_settings` chave `usage.<yyyy-mm-dd>` em JSON) e `rateLimitProvider` (último `rate_limit_event`, só em memória). Fase 5 chama `handle` para cada evento e liga o rodapé.
- Barra de título: branch atual (`currentBranchProvider(path)`, `FutureProvider.family`) ao lado do nome do workspace; recarrega ao abrir o seletor. Widget tests sobrescrevem o provider (sem git real sob FakeAsync).
- Teste de integração real: `test/integration/claude_permission_test.dart`, tag `integration` com `skip` em `dart_test.yaml` → fora do `flutter test` padrão. Rodar: `flutter test --run-skipped -t integration test/integration`.

---

## Fase 5 — Tela de Sessões

**Implementar**
1. Lista de sessões (status, agente, custo, tempo) com filtros.
2. Timeline: balões do usuário/Claude, cards de ferramenta (Read/Edit/Bash com resultado), texto ao vivo via `text_delta`, mensagens de subagente agrupadas (`parent_tool_use_id`).
3. Composer → `send()`; seletor de modo de permissão.
4. **Fila de aprovações** de todas as sessões (`control_request`) com Aprovar / Negar / Sempre permitir; notificação nativa (`local_notifier`) quando algo aguarda.
5. Detalhes: spec, duração, tokens, custo, session id, arquivos alterados (git status do worktree).
6. Ações: abrir terminal (PTY com `claude --resume <id>`), Fork (`--resume --fork-session`), Parar.
7. Rodapé alimentado por `UsageTracker` e contagem de sessões/subagentes.
8. Ao reabrir o app: sessões "executando" viram "interrompidas" com botão Retomar (`--resume`).

**Referências:** mockup 1 · Sessões; Fase 4.

**Verificação**
- [x] Criar sessão → worktree criado, timeline mostra eventos em tempo real (teste com CLI falso + integração real `test/integration/session_manager_integration_test.dart`, 2026-10-15: worktree criado, 1 aprovação, `out.txt` gravado, `success`, US$ 0,0035)
- [x] Pedido de permissão aparece na fila e na notificação; negar gera mensagem de recusa na timeline (testes: fila, `deny` grava `control_response`; o `tool_result` de erro vira card "erro". Notificação nativa: conferência visual pendente)
- [x] Fechar e reabrir o app → retomar mantém o histórico (timeline é reconstruída de `session_events`; `RestoreSessionsStep` marca interrompidas; Retomar/enviar usa `--resume`. Teste manual no app pendente)
- [x] Rodapé mostra % de 5h/semana após a primeira resposta (teste do `footerStatsProvider` com o `rate_limit_event` do fixture)

**Notas da execução (2026-10-15):**
- Nenhum pacote novo (usa `xterm`, `flutter_pty`, `local_notifier`, `yaml`, `uuid`, `flutter_markdown_plus` já listados). Arquivos: `lib/features/sessions/{session_manager,timeline,timeline_provider,session_changes,agent_names,app_notifier,new_session_dialog,sessions_screen}.dart` e `widgets/{session_list_panel,timeline_view,composer,side_panel,diff_raw_views,session_terminal,session_style}.dart`; testes em `test/features/sessions/`, `test/data/migration_test.dart`, `test/integration/session_manager_integration_test.dart`.
- **Sondagem do CLI 2.1.300 (haiku, ~US$ 0,015):** (a) `total_cost_usd` do `result` é **cumulativo na linhagem da sessão** (inclui turnos anteriores, `--resume` e o pai de um fork); `usage` é **por turno**. → `sessions.cost_usd` = último `total_cost_usd`; tokens somados; `UsageTracker.handle(e, costDelta:)` recebe só o delta (antes somava o cumulativo — corrigido). (b) `system/init` só sai depois da 1ª mensagem (e de novo a cada turno). (c) `--resume` funciona de outro worktree do mesmo repositório. (d) `--resume X --fork-session --session-id Y` cria a sessão Y. (e) `--agent <nome>` funciona com agentes de `<repo>/.claude/agents`.
- **Decisão — agente:** `--agent <nome>` (novo campo `ClaudeOptions.agent`), não `--append-system-prompt` + `--allowedTools`. Motivo: `--allowedTools` **auto-aprova** ferramentas (não restringe), então mapear `tools:` do frontmatter para ele pularia aprovações; `--agent` aplica prompt, `tools` (restrição) e `model` do próprio agente, como o CLI define. Repassado em todo `--resume`. A lista do diálogo lê só `name:`/`description:` do frontmatter (`yaml`) de `~/.claude/agents` e `<workspace>/.claude/agents` (projeto sobrescreve global). `inherit` = não passar `--model`.
- **Decisão — fork:** nova linha em `sessions` com novo UUID, `--resume <pai> --fork-session --session-id <novo>` (por isso `ClaudeOptions` aceita `sessionId`+`resumeId` quando `forkSession`), num **novo worktree** criado a partir da branch do pai (`addWorktree(slug, baseBranch: pai.branch)`). Alterações não commitadas do pai não vão junto (avisado no diálogo). Pai sem worktree ⇒ fork na raiz. O custo do fork começa com o do pai (o CLI soma).
- **Esquema v2** (`schemaVersion = 2`, `onUpgrade` com `addColumn`): `sessions.title`, `sessions.permission_mode` (texto do CLI). Teste de migração v1→v2. Repositório: `recordResult`, `setPermissionMode`, `watchAll`; `insert` aceita `title`/`permissionMode`/`costUsd`.
- **Status:** `running` → `waitingApproval` (há `control_request` pendente) → `running` (respondido/cancelado) → `completed` (`result` success; com processo vivo a UI mostra **"Ociosa"**) / `failed` (`result` de erro ou processo morreu sozinho) / `stopped` (Parar) / `interrupted` (app fechado; `markLiveAsInterrupted` no passo "Restaurando sessões…" do splash). Rótulos/cores em `SessionLook`.
- **Persistência:** uma linha de `session_events` por linha do stdout (`type` = `type/subtype`), **exceto `stream_event`** (deltas ao vivo, consolidados pelo `assistant` — gravá-los geraria centenas de linhas por turno). Eventos do app: `promptorium_user` (mensagem enviada; o CLI não ecoa a stdin), `promptorium_note` (retomada, encerramento, falhas), `invalid_line`. Fila por sessão serializa gravação → timeline (ordem garantida).
- **Timeline:** `Timeline` (redutor puro) + `sessionTimelineProvider(id)` (carrega `session_events`, depois aplica eventos ao vivo; descarta duplicados por `seq`). Texto ao vivo via `StreamDelta` (cursor ▍) substituído pelo `TextBlock` final; cards Read/Edit/Write/Bash/Glob/Grep/outros com alvo relativo ao worktree e resumo (linhas, +/−, erro, executando, aguardando aprovação); clique expande o resultado (40 linhas); mensagens com `parent_tool_use_id` aninhadas no card Task/Agent (borda lilás); `ListView(reverse: true)` mantém o fim visível. Thinking não é exibido.
- **Composer:** Ctrl+Enter / Enviar → `SessionManager.send` (sem processo vivo ⇒ `--resume` com modelo/agente/modo salvos, mesmo worktree). "Permissão: …" troca o modo salvo — vale no próximo (re)início (não há API listada para mudar o processo vivo). "Anexar spec" ficou de fora (Fase 8). Retomar: sessão interrompida/falha envia "Continue de onde parou."; parada/concluída só reabre o processo.
- **Aprovações:** painel direito agrega todas as sessões (ordem de chegada); Negar / Aprovar / "Sempre permitir <regra> <destino>" (= `updatedPermissions: [primeira permission_suggestion]`); `control_cancel_request` remove o card. Notificações (`local_notifier`, `setup` no `main`, falha só loga): aprovação pendente, sessão concluída/falhou; clique foca a janela (`window_manager`), seleciona a sessão e vai para Sessões.
- **Terminal:** aba com `xterm` + `flutter_pty` rodando `claude --resume <id>` (+ `--model/--agent/--permission-mode`) no worktree; mantido por sessão em `sessionTerminalsProvider`. Com o processo headless vivo, pede para parar antes (dois processos na mesma sessão conflitam); o composer recusa enviar com o terminal aberto.
- **Diff / Detalhes:** `sessionChangesProvider(id)` = `git status` + `git diff --numstat HEAD` + `git diff HEAD` (`DiffParser`), invalidado a cada `result`; aba "Diff · n" simples (Review completo é Fase 9). Detalhes: spec/tarefa (se `taskId`), duração (tique de 1 s enquanto roda), tokens, custo, session id (copiar).
- **Splash:** novos passos `ListWorktreesStep` ("Listando worktrees…", `workspaceWorktreesProvider`, nunca falha) e `RestoreSessionsStep`; total 6 passos.
- **Rodapé:** `footerStatsProvider` agora é derivado (CLI em `cliStatusProvider`; `setCli` mantido): sessões ativas/total do workspace ativo, sessões aguardando, subagentes = `tool_use` Task/Agent sem resultado, tokens do dia (`dailyUsageProvider`), 5h/semana do último `rate_limit_event`, MCP do último `system/init`.
- Atalho **Ctrl+N** e botão "Nova sessão" abrem o diálogo (vai para Sessões).
- **Encerramento (revisão):** `main` usa `UncontrolledProviderScope` + `windowManager.setPreventClose(true)`; ao fechar a janela, `SessionTerminals.killAll()` e `SessionManager.shutdown()` (SIGTERM → SIGKILL após 2 s, limite total 4 s) e então `windowManager.destroy()` — nenhum `claude` fica órfão. O status não é alterado no encerramento (o splash seguinte marca como interrompidas). `resume` concorrente (dois envios rápidos) reutiliza o mesmo início. Cores do mockup de Sessões (`SessionColors`) movidas para `ui/theme/tokens.dart`.

---

## Fase 6 — Tela de Prompt (conversa livre)

**Implementar**
1. Interface `AgentProvider` (start/send/stop/eventos); implementação `ClaudeCodeProvider` (reusa `ClaudeProcess`). Codex/Gemini = DT-08.
2. Conversas sem tarefa, rodando na pasta do workspace (sem worktree). Modos: **Perguntar** = somente leitura (ver notas), **Planejar** = `plan`, **Editar** = `acceptEdits`.
3. Histórico de conversas; `@arquivo` anexa contexto; `/comando` insere prompt salvo.
4. Ações: Copiar, Criar tarefa, Salvar como prompt, Transformar em spec, Continuar como sessão.
5. Ícone do botão de provedor vem do provedor ativo.

**Verificação**
- [x] No modo Perguntar, pedir para editar um arquivo não altera nada no disco (CLI real, ver notas; args cobertos por teste)
- [x] `/testes` insere o corpo do prompt salvo (widget test; também incrementa `uses`)
- [x] "Continuar como sessão" cria sessão com worktree e o histórico como contexto (teste com CLI falso: worktree novo + `--session-id <nova> --resume <conversa> --fork-session`; contexto via fork já sondado na Fase 5 (c)(d). Conferência manual no app pendente)

**Notas da execução (2026-10-15):**
- Nenhum pacote novo. Arquivos: `lib/core/providers/{agent_provider,claude_code_provider,agent_registry}.dart`; `lib/features/prompt/{conversation_manager,prompt_actions,prompt_screen}.dart` e `widgets/{conversation_list,prompt_composer,prompt_side_panel,prompt_dialogs}.dart`; testes em `test/features/prompt/`. `docs/pesquisa/perguntar-somente-leitura.py` = sonda do modo Perguntar.
- **Decisão — modo Perguntar** (sonda real, CLI 2.1.300, haiku, `--max-budget-usd 0.05`, diretório temporário com `a.txt`; pedido: "mude a.txt e crie b.txt"; o responder **aprovava todo** `control_request`, simulando um usuário que clica Aprovar):
  - **Opção A `--permission-mode plan` — reprovada.** O modelo gravou um arquivo de plano em `~/.claude/plans/…md` **sem pedir aprovação** (fora do workspace; removido após o teste) e foi buscar `ExitPlanMode`, cuja aprovação sai do modo plano e libera edições. Estourou o orçamento (US$ 0,056, `error_max_budget_usd`) antes de editar. Não é somente leitura.
  - **Opção B `--permission-mode default --disallowedTools Edit Write NotebookEdit Bash` — aprovada.** `system/init.tools` já vem sem as quatro; o modelo tentou `Write` ×2 e `Bash` e recebeu `No such tool available: Write. Write is disabled for this session, in subagents as well as here.` 0 pedidos de aprovação, `a.txt` intacto, nenhum `b.txt`. US$ 0,0061, `success`, 5 turnos. Confirma a semântica da 0.2: nome puro em `--disallowedTools` **remove** a ferramenta (também nos subagentes).
  - Custo total da sondagem: ≈ US$ 0,062.
  - Lista final (`ClaudeCodeProvider.readOnlyDisallowedTools`): as 4 testadas + `Monitor` (roda comandos), `EnterWorktree` (cria worktree), `CronCreate`, `CronDelete`, `RemoteTrigger`, `Workflow` — todas presentes em `system/init.tools` da 2.1.300. MCP continua passando por aprovação (DT-25).
- **Planejar** = `--permission-mode plan` (aviso: grava plano em `~/.claude/plans` e "ExitPlanMode" aprovado libera edições — DT-26). **Editar** = `acceptEdits`. Nenhum modo usa `bypassPermissions`.
- **`AgentProvider`** (`core/providers`): `id`, `displayName`, `icon` (`AppIconData`), `enabled`, `models`, `start(AgentStartOptions) → AgentRun` (`events`/`logs`/`send`/`approve`/`deny`/`stop`/`exitCode`). Eventos no vocabulário `ClaudeEvent` (o que a timeline entende) — outros provedores terão de traduzir (DT-08). Registro `agentProvidersProvider`: Claude Code ativo; Codex e Gemini CLI = `ComingSoonProvider` (desabilitados, "em breve" no menu). `claudeProcessStarterProvider` mudou para `core/claude/claude_cli.dart` (reexportado por `session_manager.dart`).
- **Esquema v3** (`onUpgrade`): `conversations` + `claude_session_id`, `mode` (`ask|plan|edit`), `tokens_in/out`, `cost_usd`, `message_count`, `updated_at`; nova tabela `conversation_events` (mesmo formato de `session_events`); `tasks.body`. `conversations.session_id` (FK para `sessions`) passou a significar "sessão criada por Continuar como sessão". Testes de migração v1→v3 e v2→v3.
- **`ConversationManager`** (`conversationManagerProvider`): um processo por conversa viva, cwd = raiz do workspace. 1º início com `--session-id <uuid>`; o id só é gravado em `claude_session_id` ao chegar o `system/init` (se o processo morrer antes, o próximo início usa outro UUID em vez de um `--resume` inválido); depois sempre `--resume`. Mudar modo/modelo com o processo vivo ⇒ no próximo envio para o processo e reinicia com `--resume` (nota na timeline). Persistência igual às sessões (sem `stream_event`); custo = último `total_cost_usd` cumulativo, tokens somados, `UsageTracker` recebe o delta. Encerrado junto com as sessões ao fechar a janela.
- **Reuso da timeline:** `StoredTimelineNotifier` (base de `SessionTimelineNotifier` e `ConversationTimelineNotifier`); `TimelineListView` extraído de `TimelineView` (com `footer`, `maxWidth` 760, `assistantName` "Claude Code · Modelo"). Aprovações chegam **inline** no rodapé da conversa com o mesmo `ApprovalCard` (agora aceita `onApprove`/`onDeny`/`onOpen`); não entram na fila da tela de Sessões.
- **Composer:** `@` (início de palavra) abre a lista de `git ls-files --cached --others --exclude-standard` filtrada (nome do arquivo primeiro); escolher insere `@caminho ` e vira chip (removível). `/` só no início de linha (para não confundir com caminhos) lista `saved_prompts`; escolher troca `/consulta` pelo corpo e incrementa `uses`. ↑/↓, Enter/Tab escolhem, Esc fecha. Ctrl+Enter envia. Menu de provedor (ícone do provedor ativo), modelo (`inherit/opus/sonnet/haiku/fable`), modo com dica do mockup; "Parar" enquanto responde.
- **Ações:** Copiar (clipboard); Criar tarefa = `tasks` (`T-NNN` seguinte, backlog, título = 1ª linha da resposta sem Markdown, ≤ 70, corpo = resposta); Salvar como prompt = diálogo comando/descrição/corpo (corpo = última pergunta; comando `[a-z0-9-]`); Transformar em spec = `specs/SPEC-NNN-<slug>.md` (NNN = maior entre `specs` e arquivos `specs/SPEC-*`) com frontmatter `id`/`status: rascunho` e corpo = objetivo + conversa resumida (cada mensagem cortada, ferramentas omitidas — DT-28) + seções vazias; registra em `specs` (`draft`). Continuar como sessão = diálogo (título + 1ª mensagem pedindo um resumo) → `SessionManager.create(NewSessionRequest(resumeFrom:, origin:))` com worktree novo; liga `conversations.session_id`, seleciona a sessão e vai para Sessões. Modo da sessão: Perguntar→`default`, Planejar→`plan`, Editar→`acceptEdits`.
- **Painel direito:** Pasta, Acesso (pelo modo), Tokens (entrada com cache + saída), chips dos `@arquivos` citados; Prompts salvos com `/comando`, usos, descrição, "Novo" e clique que insere no cursor.
- **Seed:** `seedSavedPrompts` no passo "Abrindo banco local…" (falha só loga); flag `prompts.seeded` em `app_settings` (apagar um padrão não o recria). `savedPromptsProvider` virou `autoDispose` (stream do drift não fica aberto fora da tela).
- Botão "Nova conversa" da barra de título limpa a seleção (rascunho); a conversa é criada no primeiro envio (título = 1ª linha).
- Widget tests: as fontes de teste têm glifos largos, por isso os botões do topo são `Flexible` (reticências) e os chips limitam o texto.

---

## Fase 7 — Tela de Agentes

**Implementar**
1. Ler agentes de `~/.claude/agents` e `<repo>/.claude/agents` (pacote `yaml`), mostrar grupos Global / Projeto e marcar "sobrescreve global".
2. Editor: nome, quando usar (`description`), modelo, escopo, prompt (corpo), ferramentas (`tools`), modo de permissão, orçamento, máx. de turnos (`maxTurns` no frontmatter e `--max-turns`), MCPs.
3. Salvar = escrever o `.md` (prévia ao vivo). Campos que não existem no frontmatter ficam em `agent_settings`.
4. "Testar em sessão".

**Verificação**
- [x] Agente salvo aparece ~~em `claude agents --json`~~ no `system/init.agents` (ver notas: `agents --json` lista sessões, não definições)
- [x] Mesmo nome no projeto sobrescreve o global (conferido no `system/init` com `--agent`: modelo do arquivo de projeto; teste do `AgentRepository`)
- [x] Teste de round-trip do frontmatter (ler → salvar → ler igual; byte a byte quando nada muda, incluindo campos desconhecidos, comentários e bloco `|`)

**Anti-padrões:** não apagar campos desconhecidos do frontmatter ao salvar.

**Notas da execução (2026-10-15):**
- Nenhum pacote novo (`yaml` já listado). Arquivos: `lib/features/agents/{agent_file,agent_repository,agents_screen}.dart`, `widgets/{agent_editor,agent_style}.dart`; `features/sessions/agent_names.dart` agora deriva de `agentEntriesProvider`; testes em `test/features/agents/` e `test/features/sessions/session_agent_limits_test.dart`.
- **`AgentFile`**: lê com `yaml`, guarda cada chave de topo com o **texto original** (linha da chave + continuação + comentários/linhas em branco acima). Chave não alterada é regravada igual; alterada é escrita à mão (escalar puro só quando o `yaml` relê a mesma string, senão aspas duplas; listas/mapas em bloco); novas chaves vão para o fim; remover mantém o comentário acima. `tools`/`disallowedTools`: string com vírgulas (estilo da doc, também para campo novo) ou lista YAML, conforme o original; vírgulas dentro de parênteses (`Bash(git a, b)`) não separam. `mcpServers`: nomes (strings) editáveis, definições inline preservadas. CRLF/BOM normalizados para LF.
- **`AgentRepository`** (`home` injetável via `agentHomeProvider`): lista `~/.claude/agents` e `<workspace>/.claude/agents`, marca `overridesGlobal`/`overriddenByProject`; `save` grava `<name>.md` (temporário + rename), nome `[a-z0-9-]`, description obrigatória, recusa sobrescrever outro arquivo; renomear/mover = grava o novo e apaga o antigo (UI confirma o mover); arquivo cujo nome difere de `<name>.md` mantém o caminho; `delete` (UI confirma). Arquivo inválido é ignorado na lista. `readMcpServerNames`: só **nomes** de `~/.claude.json` (`mcpServers` + `projects[ws].mcpServers`) e `.mcp.json`.
- **Tela**: lista Globais / Projeto (“sobrescreve o global” em âmbar; global sobrescrito = “sobrescrito no projeto”); editor com Identidade (nome, quando usar, modelo Opus/Sonnet/Haiku/Fable/Herdar → `opus/sonnet/haiku/fable/inherit` — Herdar/`default` não criam a chave se ela não existia; id de modelo desconhecido aparece como pílula extra), escopo, prompt (TextField multilinha mono — re_editor ficou para a Fase 10), ferramentas (8 pílulas + campo “Outras”; nenhuma = herda todas), execução (modo com dica, orçamento, máx. de turnos, chips MCP), **prévia ao vivo** = exatamente o texto que será gravado + caminho. Cabeçalho com sessões/concluídas/custo médio do agente no workspace. Salvar / Excluir / Testar em sessão (salva se houver mudanças e abre a Nova sessão com o agente e o modo dele pré-selecionados; se a sessão for criada, vai para Sessões). “Novo agente” da barra de título abre rascunho.
- **`agent_settings`**: `budgetUsd` é o único dado próprio; `permissionMode`, `maxTurns` e `mcpServers` são espelhos do frontmatter (o arquivo é a fonte). Renomear/mover move a linha.
- **DT-23 resolvido**: `SessionManager` (create, `--resume` e fork) acha a definição efetiva do agente (projeto > global) e passa `--max-budget-usd` (de `agent_settings` do escopo efetivo; `NewSessionRequest.maxBudgetUsd` explícito vence) e `--max-turns` (de `maxTurns` do frontmatter, **passado explicitamente**: não dá para verificar sem custo se `--agent` aplica `maxTurns` à thread principal). Erro de leitura = sem limites.
- **Sondagem do CLI 2.1.300 (custo US$ 0):** `claude -p … --model modelo-inexistente-xyz` emite `system/init` (com `agents`, `tools`, `permissionMode`) e um `result` `success` com `total_cost_usd: 0` sem chamar a API. Num repositório temporário com `.claude/agents/teste-promptorium.md` **gravado pelo `AgentRepository`**: (a) `claude agents --json` → 2 itens com `pid/cwd/kind/startedAt/sessionId/name/status` (sessões ativas), sem o agente; (b) `system/init.agents` = `[claude, Explore, general-purpose, Plan, statusline-setup, teste-promptorium]` ✓; (c) com `--agent teste-promptorium`: `tools` = `[Read, Grep]` (restrição aplicada) e `model` = o do arquivo; (d) override: com `CLAUDE_CONFIG_DIR` temporário contendo um global de mesmo nome (modelo diferente), o `model` do init é o do **projeto** ✓; (e) `permissionMode: plan` (ou `acceptEdits`) no frontmatter **não** muda o `permissionMode` do init com `--agent` → a Nova sessão pré-seleciona o modo do agente e o app passa `--permission-mode`; (f) num `git worktree` do repositório, o agente de projeto **não commitado** da raiz também aparece. Nada foi criado em `~/.claude/agents`; transcrições das sondas removidas.

---

## Fase 8 — Specs e Tarefas

**Implementar**
1. **Editor de specs** com `re_editor`: realce Markdown, números de linha, busca/substituição (copiar `find.dart` do exemplo), **zoom Ctrl+= / Ctrl+- / Ctrl+0 + controle `− 100% +`** (salvo por editor), modos Editar / Dividido / Visualizar (`flutter_markdown_plus`).
2. Specs são arquivos `specs/SPEC-NNN-*.md` no repositório com frontmatter (`id`, `status`).
3. "Gerar tarefas com o planner": `claude -p --agents planner … --json-schema <schema de tarefas>` → tarefas com dependências.
4. "Refinar com IA" e "Aprovar spec".
5. Kanban (Backlog / Em execução / Review / Feito) ligado ao status das sessões; dependências bloqueiam; "Executar com agente" cria sessão (Fase 5).
6. Rastreabilidade requisito → tarefa → sessão → commit.

**Verificação**
- [x] Zoom muda o tamanho da fonte e persiste ao reabrir (`test/ui/widgets/code_editor_test.dart`: `CodeEditorStyle.fontSize` = 12 × zoom; novo container sobre o mesmo banco relê `editor.zoom.specs`; atalhos Ctrl+=/-/0 já cobertos em `app_shell_test`/`preferences_test`)
- [x] Ctrl+F encontra e substitui (`CodeFindController` real: 2 ocorrências, "substituir todos"; Ctrl+H ligado a `replace`. Conferência no app: pendente)
- [x] Gerar tarefas cria registros válidos (schema respeitado) (chamada real única + fixture `test/fixtures/planner-result.json`; ver notas)
- [x] Sessão concluída move o card para Review (`test/features/tasks/task_rules_test.dart` com `SessionManager` e CLI falso)

**Notas da execução (2026-10-15):**
- Nenhum pacote novo (`re_editor`, `re_highlight`, `flutter_markdown_plus`, `yaml` já listados). Arquivos: `lib/ui/widgets/code_editor/{app_code_editor,code_language,code_editor_theme,find_panel}.dart`; `lib/features/specs/{spec_file,spec_service,task_planner,specs_screen,new_spec_dialog}.dart` + `widgets/{spec_list,spec_tasks_panel}.dart`; `lib/features/tasks/{task_rules,task_actions,tasks_screen,new_task_dialog}.dart`; testes em `test/ui/widgets/`, `test/features/{specs,tasks}/`, `test/features/sessions/composer_attach_test.dart`.
- **Editor reutilizável (`AppCodeEditor`)**: `CodeEditor` com tema próprio (`promptoriumCodeTheme`, escopos highlight.js → tokens), linguagem por extensão (`CodeLanguage.forPath`: md/dart/yaml/json/plaintext), números de linha (`DefaultCodeLineNumber` com estilo mono do zoom), painel de busca adaptado de `example/lib/find.dart` (cores do app, rótulos em português). `fontSize = base × zoom/100` lido de `editorZoomProvider(editorKey)` — trocar o zoom reconstrói o estilo. Atalhos: padrão do re_editor no Linux (Ctrl+F busca, Ctrl+S salvar via `shortcutOverrideActions`, Esc fecha) + **Ctrl+H** para substituir (`AppCodeShortcuts`; o padrão Ctrl+Alt+F continua). `autofocus` do re_editor é `true` por padrão — o componente passa `false`. A busca roda num isolate do re_editor (funciona em `test()`, não sob FakeAsync).
- **Specs**: arquivo é a fonte; `SpecService.sync` lê `specs/*.md` (código = `id` do frontmatter ou `SPEC-NNN` do nome), insere/atualiza `specs` (título = 1º `# `, status do frontmatter); linhas sem arquivo ficam. `status` no frontmatter: `ideia` / `rascunho` / `em-revisao` / `aprovada` (+ `concluida`); novo valor `SpecStatus.idea` (enum gravado por nome — acrescentar não exige migração). `SpecDocument.withMeta` muda só as linhas `id:`/`status:` (resto byte a byte; cria o frontmatter se faltar). Requisitos = linhas `- R1 · texto` / `- [ ] R2: …` / `1. **R3** - …`. Numeração `SPEC-NNN` compartilhada com "Transformar em spec" (`nextSpecCode`). Salvar = temporário + rename. Modos Editar / Dividido / Visualizar (prévia `MarkdownBody` com o frontmatter como linha de status); indicador "● não salvo"; trocar de spec com alterações pede confirmação. Cabeçalho em duas linhas abaixo de 900 px (janela 1100×700).
- **Refinar com IA**: salva se preciso e cria uma conversa do Prompt (`ConversationManager.create`) no modo **Editar** com `@specs/<arquivo>` e instrução de editar só esse arquivo e manter o frontmatter; seleciona a conversa e vai para Prompt. Ao voltar, a tela relê o arquivo.
- **Gerar tarefas — sondagem real (CLI 2.1.300, haiku, `--max-budget-usd 0.05`, 1 chamada)**: diretório temporário com `specs/SPEC-001-contador.md` (3 requisitos); mesmos argumentos do app (stream-json, `--permission-mode default`, `--disallowedTools` do Perguntar, `--json-schema '{"type":"object","required":["tasks"],"properties":{"tasks":{"type":"array","items":{…code?,title,description,requirement,dependsOn[]}}}}'`). Resultado: `success`, 2 turnos, **US$ 0,0055**. Formato: `system/init.tools` ganha **`StructuredOutput`**; o modelo chama essa ferramenta (`assistant` → `tool_use` `StructuredOutput` com o objeto em `input`; `user` → `tool_result` "Structured output provided successfully", sem pedido de aprovação) e o evento **`result` traz `structured_output: {"tasks":[…]}`** (objeto) **e** `result` = o mesmo JSON como string. O schema precisa ser objeto no topo (lista dentro de `tasks`). A menção `@specs/…` na mensagem stream-json foi anexada pelo CLI (o modelo não precisou de `Read`). 7 tarefas `T1…T7` com `dependsOn` coerente. Linha `result` gravada em `test/fixtures/planner-result.json`; transcrição da sonda removida.
- **`TaskPlanner`**: `ClaudeProcess` curto na raiz do workspace com `ClaudeOptions(jsonSchema:, appendSystemPrompt: plannerSystemPrompt, permissionMode: default, disallowedTools: readOnlyDisallowedTools, maxBudgetUsd: 0.5, includePartialMessages: false)` (novo campo `ClaudeOptions.jsonSchema` → `--json-schema`); envia o pedido com `@<spec>` e a lista das tarefas já existentes da spec; nega qualquer `control_request`; espera o `result` (limite 5 min) e para o processo. `parsePlannerResult` prefere `structured_output` e cai para `jsonDecode(result)`. `savePlannedTasks` grava numa transação: `TASK-NNN` sequencial por workspace (conta também os `T-NNN` antigos), `specId`, `requirement` (nova coluna), `body` = descrição, `dependsOn` traduzido do code do planner (ou posição 1-based) para o novo código; referência a código existente do workspace é mantida; auto-referência/desconhecida descartada. Custo vai para o `UsageTracker`. **Desvio**: o plano citava `--agents planner`; usei `--append-system-prompt` (sem agente extra a manter) — se existir um agente `planner` no projeto ele **não** é usado (DT-34).
- **Esquema v4** (`onUpgrade`): `tasks.requirement`. Testes de migração atualizados (v1→v4, v2→v4). `TasksRepo.nextCode` agora devolve `TASK-NNN` (Criar tarefa do Prompt também); `maxNumber`, `codeFor`, `transaction`.
- **Kanban**: colunas Backlog / Em execução / Review / Feito (`tasksProvider`); cards com código, requisito, spec, título (3 linhas), agente, meta (pronta / bloqueada por … / status da última sessão · duração · custo / "aguardando você"), menu ⋯ (mover / excluir). Bloqueio = algum `dependsOn` existente não está em Feito (`blockersOf`; códigos inexistentes são ignorados). "Executar com agente" só em Backlog desbloqueada → Nova sessão pré-preenchida (título `TASK-NNN · título`, prompt com descrição + `@spec` + requisito + dependências, agente da tarefa) com `NewSessionRequest.taskId` (vincula `sessions.task_id`; agente escolhido grava em `tasks.agent_name`); snackbar "Ver sessão". Arrastar (`Draggable<int>`/`DragTarget<int>`) muda o status manualmente. Filtros Spec (todas / sem spec / cada uma) e Agente. "Nova tarefa" (barra de título e painel da spec). Colunas ≥ 230 px; abaixo disso rolagem horizontal.
- **Status segue a sessão** (`taskStatusForSession`, chamado pelo `SessionManager` após gravar o status): mensagem enviada / `control_request` → Em execução; `result` success → Review; falha mantém; `completed` sem `result` (retomar sem mensagem) não move; Feito nunca é desfeito por sessão. `TaskActions.markDone` existe para o merge da Fase 9.
- **Rastreabilidade** (painel da spec): requisitos da spec → tarefas (cor do status) → última sessão (`sessão 7f3a`) → `commit —` (preenchido na Fase 9 com o hash do merge); tarefas com requisito fora da spec e sem requisito em linhas próprias.
- **Anexar spec** (composer de Sessões, DT-22 parcial): menu com as specs do workspace insere `@specs/<arquivo>` no cursor; chips removíveis acima do campo (`attachedSpecs`/`insertMention`/`removeMention`).
- Testes de tela com IO real (Specs) usam `tester.runAsync` em laço até a condição (o suite roda arquivos em paralelo).

---

## Fase 9 — Review

**Implementar**
1. Lista "aguardando review"; arquivos alterados (A/M/D) do worktree vs. branch base.
2. Diff com `DiffParser`; aceitar/rejeitar hunk (rejeitar = `git apply -R` do hunk no worktree).
3. Comentário inline → vira mensagem para a sessão (`--resume`) com arquivo:linha.
4. Botões: Pedir ajustes, Criar PR (`git push` + `gh pr create`, se `gh` existir), Fazer merge (merge na branch base + remover worktree).

**Verificação**
- [x] Rejeitar hunk altera o arquivo no worktree (`test/features/review/review_service_test.dart`, repositório temporário real: hunk não commitado, hunk já commitado, arquivo não rastreado e arquivo renomeado)
- [x] Merge limpa o worktree e move a tarefa para Feito (merge limpo: worktree e branch removidos, tarefa Feito, sessão `merged` + hash; conflito: `merge --abort` e nada muda; principal sujo: bloqueia antes de tocar em qualquer coisa)
- [x] Comentário chega na timeline da sessão (uma mensagem `promptorium_user` em `session_events`, enviada com `--resume` pelo `SessionManager` com CLI falso; tarefa volta para Em execução)

**Notas da execução (2026-10-15):**
- Nenhum pacote novo. Arquivos: `lib/features/review/{review_logic,review_service,review_screen}.dart`, `widgets/{review_diff_view,review_dialogs}.dart`; testes em `test/features/review/` (+ `test/data/migration_test.dart`). Tokens novos `ReviewColors` (número de linha `#4A5260`, botão Aceitar).
- **Base do diff (decisão):** o Review compara `git diff <merge-base>` **no worktree**, isto é, `base...HEAD` (commits da branch da sessão desde que saiu da base) **+ working tree** (alterações não commitadas) num único diff (`-M`, renomeações detectadas). Arquivos não rastreados entram via `git diff --no-index -- /dev/null <arquivo>` (sai com código 1; o índice não é tocado — sem `add -N`). `merge-base` = `git merge-base <base> HEAD`. Subtítulo: `pr/x → main · n arquivos · +x −y · k commits · m não commitados`.
- **Branch base:** nova coluna `sessions.base_branch` = branch da raiz do workspace no momento de criar o worktree (o worktree nasce do HEAD da raiz); fork herda a do pai. Linhas antigas (`null`) usam a branch atual da raiz.
- **Aguardando review** (`isAwaitingReview`): sessão com worktree próprio existente, não `merged`, que não está rodando, e (tarefa em Review) **ou** (status `completed` **e** alterações: commits à frente da base ou `git status` não vazio). Mostra título, `TASK-NNN · agente`. Recalculado quando `sessions`/`tasks` mudam (git só para candidatas).
- **Rejeitar hunk (decisão):** patch do hunk (`DiffParser.hunkPatch`; em arquivo renomeado o cabeçalho é reescrito para tocar só o caminho novo, sem desfazer a renomeação) aplicado com `git apply -R` no working tree do worktree. Como o diff é contra o merge-base, o mesmo caminho serve para hunk **já commitado** na branch da sessão: o reverso fica como **alteração não commitada** (vai junto no commit pendente do PR/merge). Arquivo novo inteiro rejeitado = arquivo apagado. **Aceitar hunk** = só estado visual (`✓ Revisado`), em memória.
- **Comentários:** clicar no número da linha abre a caixa do mockup; "Comentar" acumula em `reviewDraftProvider(sessão)` (memória). "Pedir ajustes ao agente (n)" abre prévia + observação opcional e envia **uma** mensagem via `SessionManager.send` (que retoma com `--resume` se não houver processo): cabeçalho, cada comentário como `arquivo:linha — comentário` (linha removida = número antigo + "(linha removida)") seguido do trecho em bloco ``` (a linha e até 2 acima, com `+`/`-`/espaço), instrução final. Tarefa volta para Em execução (pelo `SessionManager` e explicitamente).
- **Criar PR:** disponível se `which gh` sai 0 **e** a raiz tem `git remote` (prefere `origin`); senão desabilitado com tooltip ("GitHub CLI (gh) não encontrado no PATH." / "O repositório não tem remote…"). Ação: commita pendências no worktree (`Promptorium: TASK-NNN: título`), `git push -u <remote> <branch>`, `gh pr create --head <branch> --base <base>` com `--title/--body` da tarefa (descrição + spec/requisito) ou `--fill` sem tarefa, no cwd do worktree. Link (última linha `http…` do stdout) gravado em `sessions.pr_url` e mostrado num diálogo (copiar / abrir com `xdg-open`). Runner injetável `commandRunnerProvider` (`Process.run` com `workingDirectory`). `gh` não está instalado nesta máquina: coberto só com runner falso + remote bare real.
- **Fazer merge:** diálogo de confirmação com "Apagar a branch" (padrão sim). Ordem: (1) raiz precisa estar **na branch base** (não faz checkout por você — erro claro com `git switch <base>`) e **sem alterações rastreadas** (não rastreados não bloqueiam) — nada é tocado antes disso; (2) `SessionManager.release` encerra o processo do agente sem gravar "parada"; (3) commita pendências no worktree; (4) `git merge --no-ff -m "Merge <branch>: <título>" <branch>` na raiz; em falha: lista `--diff-filter=U`, `merge --abort` (se houver `MERGE_HEAD`) e desfaz o commit do passo 3 com `reset HEAD~1` (alterações voltam a ser não commitadas) — mensagem de conflito; (5) hash = `rev-parse HEAD`, `worktree remove --force` (tudo já foi commitado e integrado; só ignorados se perdem), `branch -d`, `sessions.status = merged` + `merge_commit`, `TaskActions.markDone`. Toast "Merge concluído · <hash curto>" (+ avisos se a limpeza falhar). Sessão `merged` não pode ser retomada (`SessionException`).
- **Esquema v5** (`onUpgrade` `addColumn`): `sessions.base_branch`, `sessions.merge_commit`, `sessions.pr_url`. Novo valor `SessionStatus.merged` (rótulo "Merge feito"; enum por nome — acrescentar não exige migração). Testes de migração v4→v5 (e os antigos agora criam `sessions` na forma v2–v4 e conferem `user_version = 5`).
- **Rastreabilidade (F8):** `traceSessions` escolhe por tarefa a sessão com `merge_commit` (senão a mais recente); o último elo mostra `merge <hash curto>` (tooltip com o hash completo) em vez de `commit —`.
- "Abrir no Review" (painel de Sessões) seleciona a sessão no Review.
- **Revisão de segurança do merge:** `ReviewService.mergeGuard` recusa antes de tocar em qualquer coisa se a branch não for `pr/<slug>`, a base começar com `-`, ou o worktree não estiver dentro da pasta de worktrees (`~/.promptorium/worktrees` ou a base configurada; nunca a raiz). Em falha, o worktree volta ao `HEAD` gravado antes do commit de pendências (`reset <hash>`, só se esse commit foi criado; commits do agente ficam) e uma sessão ainda viva liberada pelo `release` vira `stopped`. `merge … -- <branch>`; refs vindas de dados (base, remote, branch no push) validadas contra `-`. Testes: conflito sem pendências mantém os commits do agente, principal em outra branch bloqueia, `mergeGuard`.

---

## Fase 10 — Código

**Implementar**
1. Seletor de worktree (main + worktrees das sessões); árvore de arquivos com marcas A/M.
2. Editor em abas (`re_editor`, mesmo componente/zoom da Fase 8), salvar Ctrl+S, marca na margem: alterado pelo agente × sua edição.
3. Aviso quando uma sessão está ativa no worktree; "Pausar agente"; ao salvar, enfileirar aviso para o agente.
4. Terminal embutido (`xterm` + `flutter_pty`, shell do usuário no worktree).

**Verificação**
- [x] Editar e salvar altera o arquivo no worktree (`test/features/code/code_model_test.dart`, repositório temporário real)
- [ ] Terminal roda `flutter run -d linux` no worktree (shell do usuário via PTY no cwd do worktree, com o ambiente completo; conferência manual no app pendente — testes não abrem PTY)
- [x] Zoom independente do editor de specs (`test/features/code/code_screen_test.dart`: `editorZoomProvider('code')` muda o `fontSize` do editor e não altera `specs`, e vice-versa; atalhos já cobertos em `app_shell_test`/`preferences_test`)

**Notas da execução (2026-10-15):**
- Nenhum pacote novo. Arquivos: `lib/features/code/{code_screen,code_model,worktree_files,worktree_terminal}.dart`, `widgets/{file_tree,code_dialogs}.dart`; testes em `test/features/code/`. Alterados: `AppCodeEditor` (`lineMarks`), `CodeLanguage` (+18 linguagens com rótulo), `session_terminal.dart` (`AppTerminalView` extraído e reutilizado; `environment` no `Pty.start`), `SessionManager` (fila de avisos), `main.dart` (encerramento), `AppIcons` (`warning`, `chevronRight`).
- **Seletor de worktree:** raiz do workspace (branch atual) + `git worktree list` (sem bare/prunable) cruzado com `sessions` por `worktree_path` (sessão ativa primeiro, senão a mais recente) → título e status (`SessionLook`). Cartão do mockup + "Outros:". Seleção em `app_settings` `code.worktree.<workspaceId>`; caminho que sumiu ⇒ raiz.
- **Árvore:** `git ls-files --cached --others --exclude-standard -z` (respeita `.gitignore`, nunca lista `.git`) + pastas criadas no app (git não lista pasta vazia); filhos calculados ao expandir (`WorktreeIndex.children`, cache por pasta). Marcas `A/M/D/?` do `GitService.status` (pasta com alteração dentro ganha um ponto). Atualiza ao entrar na tela, após cada ação e a cada 10 s. Menu (botão direito / toque longo): novo arquivo/pasta aqui, renomear/mover, excluir (confirmação; avisa se há aba suja). **Validação:** caminho relativo, sem `..`/`.`/segmento vazio/`.git`/NUL/`\`/espaço nas bordas, e o ancestral existente mais profundo resolvido (`resolveSymbolicLinks`) precisa ficar dentro do worktree — symlink para fora é recusado (a busca do ancestral não segue links, então symlink **pendente** apontando para fora também é recusado — revisão; antes `write` podia criar arquivo fora do worktree através dele). Gravação no lugar não é atômica (DT-44).
- **Editor em abas:** `AppCodeEditor` com chave de zoom `code`, uma aba por arquivo (modelo `CodeWorktreeModel` por worktree, vivo durante o app: abas sobrevivem à troca de tela/worktree). Ponto âmbar = não salvo; Ctrl+S salva (no editor e na tela), Ctrl+W fecha (Salvar / Descartar / Cancelar), Ctrl+P "Ir para arquivo" (busca fuzzy por subsequência, pontua nome do arquivo, início de palavra e sequência — DT-12 parcial). Barra inferior `Ln x, Col y · Linguagem · UTF-8 · LF|CRLF`. CRLF é preservado (`CodeLineOptions.lineBreak`). Gravação **no lugar** (`writeAsString`, mantém permissões). Binário (NUL nos primeiros 8 KB), não UTF-8 ou > 2 MB: aviso e não abre.
- **Marcas na margem (decisão):** o `indicatorBuilder` do re_editor 0.10 dá os parágrafos visíveis (`CodeIndicatorValueNotifier`) — `CodeLineMarks` pinta uma faixa de 3 px antes dos números com os mesmos offsets do `DefaultCodeLineNumber`. Verde = linhas `+` de `git diff --unified=0 <base> -- arquivo` (base = `merge-base <base_branch> HEAD` da sessão; na raiz, `HEAD`; arquivo não rastreado = todas) — legenda "alterado pelo agente" (na raiz: "alterado (git)"). Âmbar = edição não salva (prefixo/sufixo comuns entre texto salvo e buffer, recalculado 120 ms após digitar); as marcas verdes são deslocadas pelo delta de linhas da edição.
- **Banner / Pausar / aviso ao agente (decisão):** banner quando há sessão `running`/`waitingApproval` **com processo vivo** no worktree selecionado; "Pausar agente" = `SessionManager.stop` (vira Parada; retomar pela tela de Sessões), "Ver sessão" seleciona e navega. Ao salvar, cada sessão ativa ali recebe `SessionManager.notifyUserEdit(id, arquivo)` → texto "O usuário editou <arquivo> manualmente; releia antes de alterar.". **Enviar no meio do turno não está na 0.2** (não verificado se o CLI aceita/enfileira mensagem stream-json durante um turno), então: turno em andamento (`busy` desde o envio até o `result`) ou aprovação pendente ⇒ fila em memória, enviada como **uma** mensagem logo após o `result`; processo vivo e ocioso ⇒ envio imediato; sem processo (pausado) ⇒ a fila vai **antes** da próxima mensagem enviada pelo usuário (sem retomar sozinho). Avisos repetidos do mesmo arquivo são deduplicados.
- **Alteração externa:** a cada 2 s (e ao ativar uma aba / entrar na tela) compara `mtime` e tamanho de cada aba aberta; aba limpa ⇒ recarrega (mantém a linha do cursor); aba suja ⇒ banner "mudou no disco" com Recarregar / Manter as minhas (esta grava o novo `mtime` e não pergunta de novo até outra mudança; salvar sobrescreve).
- **Painel inferior:** Terminal = `$SHELL` (senão `/bin/bash`) num PTY no worktree, com o ambiente completo do app (o `flutter_pty` só copia `PATH/HOME/USER…` por padrão), um por worktree em `worktreeTerminalsProvider` (sobrevive à troca de tela; `killAll` no fechamento da janela junto com os terminais de sessão). Abre sozinho ao mostrar o painel (`codeTerminalAutoStartProvider`, desligado nos testes); recolhível. "Problemas · 0" = stub (DT-04).
- Testes: árvore × `.gitignore`/marcas; criar/renomear/excluir e 9 casos de *path traversal* (inclui symlink); binário/> 2 MB; linhas vs merge-base num worktree real; marcas da margem; fuzzy; abrir/editar/salvar; recarga automática × aviso; aviso ao agente com `SessionManager` + CLI falso (fila durante o turno → enviado após `result`; ocioso → imediato; pausado → junto da próxima mensagem); tela 1044×628 (janela 1100×700) sem overflow, Ctrl+P, banner da sessão ativa.

---

## Fase 11 — MCP

**Implementar**
1. Listar servidores: `claude mcp list` + leitura de `~/.claude.json` (usuário/local) e `.mcp.json` (projeto); status vindo de `system/init.mcp_servers`.
2. Detalhes: transporte, comando/URL, variáveis (mascaradas), escopo.
3. Ferramentas por servidor com regra Permitido / Pedir aprovação / Bloqueado → traduzidas em `--allowedTools mcp__<srv>__<tool>` / `--disallowedTools`.
4. Adicionar/remover via `claude mcp add/remove` (com `--scope`).
5. Testar conexão, log recente.

**Verificação**
- [x] Adicionar servidor pelo app aparece em `claude mcp list` (`test/integration/mcp_cli_integration_test.dart`: `McpCli.add` escopo project num diretório temporário com `CLAUDE_CONFIG_DIR` temporário → `list` mostra `⏸ Pending approval` → `remove` → some; 2026-10-15, sem modelo, US$ 0)
- [x] Ferramenta "Bloqueado" não aparece em `system/init.tools` da próxima sessão (sonda real: `--disallowedTools mcp__fake-ok__apagar` ⇒ init só com `mcp__fake-ok__echo`; args de sessão/conversa cobertos em `test/features/mcp/mcp_rules_test.dart`)
- [x] Servidor com falha aparece em vermelho no rodapé e na lista (`mcp_screen_test.dart`: status "Falhou" em `AppColors.red`, rodapé 1/4 · 3 falhou)

**Anti-padrões:** nunca escrever `~/.claude.json` diretamente; nunca exibir token sem ação explícita.

**Notas da execução (2026-10-15):**
- Nenhum pacote novo. Arquivos: `lib/features/mcp/{mcp_config,mcp_cli,mcp_rules,mcp_state,mcp_screen}.dart`, `widgets/add_server_dialog.dart`; alterados `SessionManager`, `ConversationManager`, `AgentStartOptions`/`ClaudeCodeProvider`, `McpToolRulesRepo.getAll`, `SessionsRepo.recentEventsContaining`, `footer_stats.dart`, `app_shell.dart` ("Adicionar servidor"). Testes em `test/features/mcp/` + fixtures reais `test/fixtures/mcp_{list,list_diagnostics,get}_2.1.300.txt` e `mcp_inventory_init_2.1.300.jsonl`.
- **Isolamento das sondas:** `CLAUDE_CONFIG_DIR=<tmp>` redireciona `~/.claude.json` para `<tmp>/.claude.json` (conferido: um servidor só existente no arquivo temporário apareceu no `mcp list` e nenhum real apareceu). ⚠ `claude mcp list` **também grava** o `.claude.json` (cria `firstStartTime`, `machineID`, migrações) — no app isso é o CLI cuidando do próprio arquivo. O `runner` padrão recusa rodar sob `flutter test` (`FLUTTER_TEST`); testes injetam `mcpRunnerProvider`. Obs.: antes dessa trava, uma execução do `app_shell_test` chegou a abrir a tela MCP com o runner real (pode ter rodado `claude mcp list`/inventário contra a config real, só leitura de servidores — o CLI pode ter atualizado metadados do próprio `~/.claude.json`).
- **Formato real de `claude mcp list` (2.1.300):** cabeçalho `Checking MCP server health…` + linha em branco; uma linha por servidor `<nome>: <comando args | URL (HTTP)> - <símbolo> <status>[ — <detalhe>]` (stdio sem args deixa dois espaços antes de `-`); símbolos `✔ Connected`, `✘ Failed to connect — CONNECTION_CLOSED: Connection closed` / `— ECONNREFUSED: …`, `⏸ Pending approval (run claude to approve)` (servidores de `.mcp.json` não aprovados); depois, opcional, um bloco `MCP config diagnostics ⚠` (ex.: `[Conflicting scopes]`). Saída 0 mesmo com falhas. Parser: regex com o **último** ` - <símbolo> `, para na primeira linha em branco após as entradas.
- **`claude mcp get <nome>`:** `Scope:`, `Status:`, `Issue:`, `Type:`, `Command:/Args:` ou `URL:` e **`Environment:`/`Headers:` com os valores em claro** → o app lê só `Status`/`Issue`/`Scope` e descarta o resto (nunca loga). Nome inexistente: exit 1 `No MCP server named "x"…`.
- **Flags de `claude mcp add` (`--help`):** `-s/--scope local|user|project` (padrão local), `-t/--transport stdio|sse|http`, `-e/--env <env...>`, `-H/--header <header...>` (variádicos), `--client-id/--client-secret/--callback-port` (OAuth, não usados). Forma usada: `mcp add -s <escopo> -t <tipo> [-e K=V]… [-H "K: V"]… -- <nome> <comando|url> [args…]` — tudo depois de `--` porque `-e/-H` variádicos engoliriam o nome. Testado real: grava `.mcp.json` com `type/command/args/env` ou `type/url/headers`; a resposta do http mostra headers com `[REDACTED]` só para `Authorization`. Erros: `MCP server X already exists in .mcp.json` / `Invalid name … letters, numbers, hyphens, and underscores` (exit 1). `remove <nome> -s <escopo>`; sem `-s` e com o nome em 2 escopos ⇒ exit 1 listando os escopos (o app sempre passa `-s`). Não há comando de desativar ⇒ o botão "Desativar" do mockup virou **Remover** (confirmação).
- **Registro (`McpRegistry`):** lê `<config>/.claude.json` (`mcpServers` = Global; `projects[<workspace>].mcpServers` = Local) e `<workspace>/.mcp.json` (Projeto), sem escrever. Precedência local > projeto > usuário (doc); a entrada perdedora aparece como "Sobrescrito". `type` ausente com `command` = stdio. Env/headers: **só os nomes das chaves** entram no modelo (valores nunca saem do `jsonDecode`); a UI mostra `••••` sem "mostrar" (decisão: não guardar valores). URL: valores de query e senha mascarados; args após flag com cara de segredo (`--token`, `--api-key`, `--password`…) mascarados. Observado: com um servidor de projeto **não aprovado**, `mcp list` mostra o de usuário de mesmo nome (o não aprovado não conta).
- **Status:** `mcpStatusBoardProvider` guarda a foto mais recente — `claude mcp list` (cwd = workspace, 1× por workspace/sessão do app), inventário ou qualquer `system/init` de sessão (substitui; preserva o detalhe de erro quando o estado bate). "Testar conexão" = `mcp get` (atualiza um servidor); "Reiniciar" = refaz list + inventário. Rodapé `MCP x/y · n falhou` vem dessa foto. `system/init.mcp_servers[]` traz também `source` (`user`/`project`).
- **Ferramentas (inventário sem custo):** `claude -p --output-format stream-json --verbose --model promptorium-inventario-sem-modelo --no-session-persistence --permission-mode default --max-budget-usd 0.01 --max-turns 1 -- .` (cwd = workspace) → `system/init.tools` com `mcp__<srv>__<tool>` + `result` `total_cost_usd: 0`; `--no-session-persistence` não cria transcrição. Cache por workspace durante a sessão do app; somado às ferramentas do último init de sessão. Observado: em `-p`, servidor de `.mcp.json` **não aprovado** conecta (`connected` no init) enquanto `mcp list` diz "Pending approval". Servidor no id da ferramenta: caracteres fora de `[A-Za-z0-9_-]` viram `_` (`mcpServerKey`).
- **Regras (decisão):** `mcp_tool_rules(server = chave do servidor, tool)`; sem linha = Pedir aprovação. Pílula cicla Permitido → Pedir → Bloqueado (mockup). Aplicação a cada início/`--resume`/fork de sessão e início de conversa: Permitido → `--allowedTools mcp__srv__tool`; Bloqueado → `--disallowedTools mcp__srv__tool`; Pedir → nada (aprovação via stdio). **Prompt "Perguntar" e o modo interno "Refinar" ignoram Permitido** (uma ferramenta MCP pode escrever; continua pedindo) e respeitam Bloqueado. Sessões não têm modo somente leitura ⇒ Permitido sempre vale. Regras são globais por nome de servidor (não por workspace). O planner (Fase 8) não aplica as regras.
- **Usado por:** agentes (`agentEntriesProvider`) cujo `mcpServers` do frontmatter cita o nome (global sobrescrito pelo projeto é ignorado). **Log recente:** `session_events` das sessões do workspace com `mcp__<srv>__` (LIKE escapado) → `tool_use` + `tool_result` correspondente (ok/erro, duração), `control_request` pendente = "aguardando aprovação"; 12 mais recentes, atualiza ao mudar sessões/aprovações ou em "atualizar".
- Grupo "Interno · promptorium-approvals" do mockup removido (aprovações via stdio, 0.3). Servidores vistos só no init/list (conectores claude.ai, plugins) aparecem em "Outros", sem remover/testar.
- Testes: parse das saídas reais (list, list com diagnósticos, get sem reter env), args de `mcp add/remove` + validações, `McpCli` (cwd, redação de segredos), registro com JSON temporários (precedência e **nenhum valor de env/header/token** no modelo exposto), regras → args (sessão create/resume com banco; conversa Perguntar/Refinar/Editar/Planejar), inventário do init real, tela 1044×628 / 1100×700 / 800×600 sem overflow, ciclo da regra gravado, remover com confirmação, testar com `get`, diálogo Adicionar monta os args.

---

## Fase 12 — Verificação final e empacotamento (CONCLUÍDA em 2026-10-15)

1. Rodar todas as checklists anteriores.
2. `grep` de anti-padrões: `flutter_markdown:`, `bypassPermissions`, `dangerously-skip-permissions`, `riverpod_generator`, `Process.run('claude'` em sessões.
3. `flutter test` + `flutter analyze` limpos.
4. `flutter build linux --release`; `.desktop` + ícones instalados em `~/.local/share/applications` e `~/.local/share/icons`.
5. Atualizar `debito-tecnico.md` com o que ficou de fora.

**Verificação**
- [x] Checklists F1–F11 revisadas: tudo marcado está coberto por teste ou sonda registrada; o que depende de conferência manual no app foi consolidado em `debito-tecnico.md` → "Conferência manual pendente". Único item em aberto: F10 "Terminal roda `flutter run -d linux`" (manual)
- [x] Anti-padrões: nenhum `flutter_markdown:` no pubspec, nenhum `riverpod_generator`/`riverpod_annotation`; `bypassPermissions` só no comentário de proibição (`claude_args.dart`); sessões/conversas/planner/inventário MCP usam `Process.start` (`Process.run` só para `claude --version`, `git`, `gh`, `claude mcp …` curtos); nenhuma escrita em `~/.claude.json`/`.mcp.json`; cores hex fora de `lib/ui/theme` só na paleta de sintaxe (`code_editor_theme.dart`)
- [x] `dart format --set-exit-if-changed lib test` (1 arquivo de teste formatado), `flutter analyze` sem problemas, `flutter test` 3× seguidas: 225 passaram, 3 pulados (integração), 0 falhas. "Aprovar spec" (instável 1× na F8): já usa `settleIo` (`runAsync` + `pump` em laço até a condição, limite 12 s); 6 execuções extras de specs+code+review em paralelo sem falha
- [x] `flutter build linux --release` → `build/linux/x64/release/bundle` (35 MB)
- [x] `scripts/install.sh` / `scripts/uninstall.sh` (DT-10): instalado, `desktop-file-validate` OK, segunda execução idempotente, sha256 do banco do usuário inalterado; binário instalado iniciou e rodou 6 s (`timeout`, saída 124) com `HOME`/`XDG_DATA_HOME`/`CLAUDE_CONFIG_DIR` temporários (sem tocar no banco nem na config real)
- [x] README final; `debito-tecnico.md` revisado (DT-10 resolvido, DT-48/DT-49 novos, lista de conferência manual)

**Notas da execução (2026-10-15):**
- Instalação: bundle copiado para uma pasta temporária dentro de `~/.local/share/promptorium/` e trocado por `app/` (só essa subpasta é substituída); `.desktop` = `linux/promptorium.desktop` com `Exec=<caminho absoluto>`; `gtk-update-icon-cache -f -t` (o hicolor do usuário não tem `index.theme`). O ícone da janela continua vindo do bundle (`/proc/self/exe` resolve o link). O uninstall só remove o link se apontar para a instalação e o `.desktop` se o `Exec` for o da instalação.
- O passo "Conectando servidores MCP…" do splash continua stub de propósito (DT-48); comentário `TODO(Fase 11)` trocado pela explicação. `tray_manager` está no pubspec mas sem uso (DT-49).

## Pós-F12 — Tela Projeto (planejamento de projeto novo)

Desenho aprovado no canvas "Promptorium — Novo projeto" (https://claude.ai/artifact/5JdhLWnuSytMAD2otLhp7R): Pasta e repositório → Visão → Stack e convenções → Roadmap → Revisar e criar.

- Seletor de workspace: "Procurar…" (seletor de pastas nativo, `file_selector`); pasta sem git oferece `git init` (com commit inicial, opcionalmente com `origin`) ou `git clone` (`RepoSetup`). O commit inicial é obrigatório: worktrees de sessão partem de um commit.
- "Novo projeto…" (seletor de workspace / barra de título na tela Projeto): cria `<pasta>/<nome>`, `git init` + commit vazio, workspace ativo e plano vazio.
- Planner: `runReadOnlyClaude` (extraído do `TaskPlanner`) com `--json-schema`; Visão = `--session-id` no 1º turno e `--resume` nos seguintes, devolve `{reply, plan, suggestions}`; Stack = `{decisions, claudeMd}` (escolhas do usuário ficam fixas); Roadmap = `{specs[phase foundation|mvp, requirements, acceptance, tasks], later}`, normalizado no app (Fundação primeiro, códigos únicos, dependências conhecidas, tarefa do MVP sem dependência espera toda a Fundação).
- Rascunho em `project_plans` (schema v6, uma linha por workspace, JSON em `data`).
- "Criar projeto": `CLAUDE.md` + uma spec aprovada por item do roadmap (`SpecService.create(render:)`), tarefas numa transação com dependências traduzidas para `TASK-NNN`, commit "Plano inicial do projeto" só com esses arquivos (`git commit -- <arquivos>`), depois o diálogo de nova sessão preenchido com a 1ª tarefa.
- **Sondagem real (CLI 2.1.300, haiku, `--max-budget-usd` 0,05/0,1, 3 chamadas, US$ 0,022)** com os schemas e prompts do app em stream-json: Visão turno 1 (`--session-id`) e turno 2 (`--resume`, mesmo `session_id`) → `structured_output` completo; Roadmap (schema com `enum` e objetos aninhados) → 8 specs, 29 tarefas, dependências coerentes, `later` preenchido. Transcrições não gravadas.

---

## Ordem e dependências

```
F1 → F2 → F3 → F4 ─┬─ F5 (Sessões) ─┬─ F8 (Specs/Tarefas) ─ F9 (Review)
                   ├─ F6 (Prompt)   └─ F10 (Código)
                   ├─ F7 (Agentes)
                   └─ F11 (MCP)
                                      → F12
```
MVP utilizável ao fim da **Fase 5**. Fases 6, 7, 10 e 11 podem ser feitas em qualquer ordem depois da 4.
