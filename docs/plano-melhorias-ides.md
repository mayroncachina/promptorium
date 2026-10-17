# Plano — melhorias vindas da análise das IDEs

> Status: proposto (2026-10-16). Fonte: [`docs/analise-ides/`](analise-ides/00-README.md) (partes
> [02](analise-ides/02-fluxo-specs-e-quadro.md), [03](analise-ides/03-sessoes-e-agentes.md),
> [04](analise-ides/04-review-e-qualidade.md), [05](analise-ides/05-plataforma-e-robustez.md) e o
> [roteiro em 06](analise-ides/06-roadmap-sugerido.md)). Itens DT-nn: [`debito-tecnico.md`](debito-tecnico.md).
> **Implementado em 2026-10-17 na branch `teste`** (F1–F18, um commit por fase; schema v9 → v14). Ver
> [Execução](#execução-2026-10-17) no fim para o que mudou em relação ao plano.
> Uma **fase** ≈ um PR do tamanho dos de `feat/specs-no-quadro` ([plano](plano-specs-no-quadro.md)). Cada fase termina com `flutter analyze`
> limpo, testes passando e entrada no CHANGELOG.

## Por quê

O ciclo planner → spec → etapas em worktree → Review → merge funciona, mas **não se protege**: a etapa
vira "feita" só porque o agente escreveu `ETAPA CONCLUÍDA: Rn`; não há como voltar uma etapa; o Autopilot
e o rascunho do Review somem ao fechar o app; o worktree nasce sem `.env` nem dependências; e só o
humano revisa. Este plano fecha essas lacunas primeiro e deixa a expansão para o fim.

## Decisões

1. **Ordem por risco**: primeiro rede de segurança (Onda 1), depois qualidade (Onda 2), spec e Quadro
   (Onda 3), plataforma (Onda 4), expansão (Onda 5). Uma onda só começa com a anterior mergeada.
2. **Tudo novo é desligável por projeto** em `.promptorium/config.yml`. Valores padrão conservadores
   (gate ligado só se houver `testes:`; revisor automático desligado até a Onda 2 estabilizar).
3. **O app verifica, não pede**: gate, formatação e bloqueio de comandos rodam pelo app (processo próprio
   ou hook do CLI), sem gastar turno do agente quando possível.
4. **Um arquivo de spec** (sem os três arquivos do Kiro). A seção `## Design` entra no mesmo arquivo.
5. **Nada no `~/.claude/settings.json` do usuário**: hooks do app vão num `settings.json` temporário por
   sessão (`--settings`), somados aos do usuário.
6. **Sonda antes de depender de comportamento do CLI** (hooks em `stream-json`, `set_permission_mode`,
   mensagem no meio do turno). Resultado anotado em [`docs/pesquisa/`](pesquisa/), como as sondas anteriores (ex.: [`permissao-stdio-responder.py`](pesquisa/permissao-stdio-responder.py)).
7. **Schema do banco**: uma versão por onda que precisar (v9 na Onda 1, v10 na Onda 2…), sempre com
   teste de migração a partir da v8. A partir da Onda 4, migrações geradas (`drift_dev schema dump`).

## `config.yml` ao fim do plano

Chaves novas (todas opcionais; ausentes = comportamento de hoje):

```yaml
testes: flutter test            # já existe
lint: flutter analyze           # Onda 1 (gate) e Onda 4 (aba Problemas)
build: flutter build linux      # Onda 1 (gate, opcional)
formatar: dart format {arquivo} # Onda 1 (hook PostToolUse)
verificacao:                    # Onda 1
  tentativas: 1                 # reenvios automáticos ao agente antes de pedir o humano
  timeout: 600                  # segundos por comando
  exigir-commit: true
  exigir-arvore-limpa: true
bloquear-comandos:              # Onda 1 (hook PreToolUse em Bash), soma à lista embutida
  - "git push --force*"
worktree:                       # Onda 2
  copiar: [.env, .env.local]
  preparar: flutter pub get
  porta-base: 4000
revisor:                        # Onda 2
  ligado: true
  modelo: haiku
  orcamento: 0.30
  rodadas: 2
autopilot:                      # Onda 3
  paralelo: 3
  orcamento-dia: 10
```

`ProjectConfig` ([`project_config.dart`](../lib/features/project/project_config.dart)) ganha os campos, `parse`/`toYaml`, e a tela
[`project_config_view.dart`](../lib/features/project/widgets/project_config_view.dart) ganha as seções correspondentes à medida que cada onda entra.

---

## Onda 1 — Rede de segurança

Resultado: etapa só fica "feita" se compilar, testar e commitar; dá para voltar; nada se perde ao fechar
o app. **Schema v9.**

### F1 · Gate de verificação por etapa ([02 §2.1](analise-ides/02-fluxo-specs-e-quadro.md#21-gate-de-verificação-por-etapa-prioridade-máxima) · DT-33)

**Comportamento**

- No início de cada sessão de etapa, [`SpecRunner.runNext`](../lib/features/board/spec_runner.dart#L220) grava o `HEAD` do worktree (`start_sha`) na
  `spec_steps` das etapas da sessão.
- Em [`SpecRunner.onResult`](../lib/features/board/spec_runner.dart#L428), quando o marcador traz etapas, **antes** de marcá-las `done` o app roda o
  checklist no worktree, fora do processo do agente:
  1. há commit novo desde `start_sha` cuja mensagem começa com `SPEC-003 R2` (ou `R2, R3`);
  2. `git status --porcelain` vazio (se não: falha "arquivos não commitados" com a lista);
  3. `testes:` com código 0; depois `lint:` e `build:` se definidos. Timeout por comando com
     `SIGTERM` → `SIGKILL` (mesmo padrão do MCP). Saída guardada (últimos 64 KB por comando).
- Passou → etapas `done`, fluxo de hoje (próxima etapa / Review).
- Falhou e ainda há tentativa → etapas `verifying` → o app envia à **mesma sessão** uma mensagem curta
  ("A verificação falhou: testes, 3 erros. Saída: …(cortada)… Corrija, faça commit e repita a linha
  `ETAPA CONCLUÍDA`."). Conta a tentativa.
- Falhou sem tentativas → `needs_input` com o motivo; o Autopilot não avança essa spec.
- Sem `testes:`/`lint:`/`build:` e com `exigir-commit` desligado = comportamento de hoje.
- Botão "Commitar o que sobrou" quando a única falha é árvore suja (commit com a mensagem da etapa).

**Código**

- Novo `lib/features/board/step_gate.dart`: `StepGate.run(worktree, spec, steps, startSha, config)
  → GateReport {checks: [GateCheck{nome, ok, saida, duracao}], ok}`. Puro em relação ao Riverpod;
  recebe [`ProcessRunner`](../lib/core/process/process_runner.dart) e [`GitService`](../lib/core/git/git_service.dart) para testar com falsos.
- [`GitService`](../lib/core/git/git_service.dart): `headSha()`, `commitsSince(sha)` (mensagens), `statusPorcelain()`.
- [`SpecRunner.onResult`](../lib/features/board/spec_runner.dart#L428): chama o gate; nova `StepStatus.verifying`.
- [`SessionManager`](../lib/features/sessions/session_manager.dart): nenhum envio novo de API; o reenvio usa `send()`.
- [`spec_steps_panel.dart`](../lib/features/board/widgets/spec_steps_panel.dart) / cartão do Quadro ([`board_screen.dart`](../lib/features/board/board_screen.dart)): chips `✓ testes · ✓ commit · ✗ lint`, botão
  "Ver saída da verificação" (diálogo com a saída de cada comando).

**Dados (v9)** — `spec_steps` ([`app_database.dart`](../lib/data/db/app_database.dart#L130)): + `start_sha`, + `gate_report` (JSON), + `gate_attempts`.

**Testes** — `step_gate_test.dart` (repositório git temporário: sem commit, commit com prefixo errado,
árvore suja, teste falhando, timeout); `spec_runner_test.dart` (reenvio 1×, depois `needs_input`;
passa → `done`; sem config → igual a hoje); migração v8→v9.

**Aceite** — etapa com teste quebrado nunca chega a `done`; o agente recebe a falha uma vez sozinho.

### F2 · Hooks gerenciados pelo app ([03 §3.1](analise-ides/03-sessoes-e-agentes.md#31-hooks-gerenciados-pelo-app) · DT-25)

**Sonda primeiro** (`docs/pesquisa/hooks-settings-stream-json.md` + script): `claude -p --input-format
stream-json --settings <arquivo>` com `PreToolUse` (bloquear), `PostToolUse` (rodar comando) e `Stop`
(devolver `decision: block` com motivo) — confirmar que disparam, que a saída do hook chega ao agente e
como aparecem no stream (`system/hook_*`?). Se `Stop` funcionar, o gate da F1 passa a rodar **dentro** do
turno (sem gastar turno extra); se não, fica como na F1.

**Comportamento**

- Para cada sessão o app gera `~/.promptorium/run/<sessão>/settings.json` e passa `--settings`. Os hooks
  chamam um executável pequeno do próprio app (`promptorium-hook`, script Dart compilado junto ou
  `bash` gerado) que lê o JSON do evento no stdin e responde:
  - `PreToolUse` (Bash): bloqueia a lista embutida (`git push --force`, `rm -rf /`, `git -C <raiz>`,
    `git worktree remove`, `git checkout` fora do worktree) + `bloquear-comandos:`; mensagem ao agente
    com o motivo.
  - `PostToolUse` (Edit/Write/MultiEdit): roda `formatar:` com `{arquivo}` substituído.
  - `Stop` (só sessões de etapa, se a sonda confirmar): roda o gate da F1.
  - `SessionEnd`: grava custo/tokens finais num arquivo que o app lê ao reabrir.
- Hooks do usuário continuam valendo (o CLI soma as fontes; confirmar na sonda).
- Configurações → **Automações**: lista dos hooks, liga/desliga cada um, "último resultado".
- Timeline: card "hook bloqueou `git push --force`" e "formatado: lib/x.dart".

**Código** — `lib/core/claude/managed_hooks.dart` (gera o JSON), `ClaudeOptions.settingsFile`
([`claude_args.dart`](../lib/core/claude/claude_args.dart)) → `--settings`; `bin/promptorium_hook.dart` (ou script gerado);
[`SessionManager._start`](../lib/features/sessions/session_manager.dart) escreve o arquivo
e apaga ao encerrar; tela `features/settings/automations_view.dart`.

**Testes** — geração do JSON; o executável do hook com stdin de exemplo (bloqueia / deixa passar /
formata); `ClaudeOptions.toArgs` com `--settings`; CLI falso com roteiro "hook bloqueou".

### F3 · Checkpoint por etapa e estado durável ([02 §2.4](analise-ides/02-fluxo-specs-e-quadro.md#24-checkpoint-por-etapa-e-voltar), [05 §5.1](analise-ides/05-plataforma-e-robustez.md#51-estado-durável) · DT-06, DT-36)

**Checkpoint**

- Início de cada sessão de etapa: `git update-ref refs/promptorium/SPEC-003/R3-inicio HEAD` e, se a
  árvore estiver suja, `git stash create` guardado em `spec_steps.start_stash`.
- Cartão / painel de etapas:
  - **"Voltar ao início da etapa"** — confirmação com a lista do que será descartado; para a sessão viva;
    `reset --hard <ref>` + `stash apply` (se houver); etapa volta a `pending`.
  - **"Refazer etapa"** — voltar + `runNext` com um bloco "Tentativa anterior: <resumo/último result e
    saída do gate>" anexado ao prompt.
- Limpeza das refs ao mergear/arquivar a spec ([`_closeSpec`](../lib/features/review/review_service.dart#L682)).

**Estado durável (v9)**

- `autopilot_state` (workspace_id, ligado, desde): [`Autopilot`](../lib/features/board/autopilot.dart) lê no build e grava em start/stop; no
  splash, workspaces com Autopilot ligado fazem `tick`.
- `review_drafts` (session_id, comentários JSON, hunks aceitos/rejeitados): [`ReviewDraftNotifier`](../lib/features/review/review_service.dart#L851) passa a
  persistir (debounce 500 ms) e restaurar.
- `pending_notices` (session_id, texto): fila de avisos ao agente do [`SessionManager._notices`](../lib/features/sessions/session_manager.dart#L224).

**Testes** — checkpoint num repositório temporário (voltar com e sem stash); persistência do Autopilot e
do rascunho do Review sobrevivendo a um "reabrir" (novo container Riverpod no mesmo banco); migração.

**Fecha a Onda 1** — rodar a spec de 2 etapas com haiku (como a fase 8 do [plano anterior](plano-specs-no-quadro.md)) com um teste
quebrado de propósito na R2: espera-se reenvio automático, correção e `done`.

---

## Onda 2 — Qualidade e worktree pronto (schema v10)

### F4 · Worktree pronto para rodar ([02 §2.2](analise-ides/02-fluxo-specs-e-quadro.md#22-worktree-pronto-para-rodar) · DT-18)

- `config.yml` `worktree: {copiar, preparar, porta-base}`.
- Ao criar o worktree da spec ([`SpecRunner._worktree`](../lib/features/board/spec_runner.dart#L356)) e no Fork/`useWorktree` do [`SessionManager.create`](../lib/features/sessions/session_manager.dart#L250):
  copiar os arquivos listados (só se existirem na raiz e forem ignorados pelo git), rodar `preparar` com
  timeout e saída visível no cartão ("Preparando worktree…"); a sessão só abre depois. Falha → cartão
  com erro + "Tentar de novo".
- Índice do worktree (menor livre entre os ativos do workspace, guardado em `specs.worktree_index`) →
  `PROMPTORIUM_PORT = porta-base + índice`. Ambiente da sessão e do terminal embutido:
  `PROMPTORIUM_PORT`, `PROMPTORIUM_WORKTREE`, `PROMPTORIUM_SPEC`, `PROMPTORIUM_ROOT`.
- Fork: `git stash create` no pai + `stash apply` no novo worktree (DT-18).
- Código: `lib/core/git/worktree_setup.dart`; [`claude_process.dart`](../lib/core/claude/claude_process.dart) já aceita `environment`.

### F5 · Revisor automático da spec ([04 §4.1](analise-ides/04-review-e-qualidade.md#41-review-automático-antes-do-humano) · [03 §3.3](analise-ides/03-sessoes-e-agentes.md#33-subagentes-usar-o-isolamento-do-cli))

- Sub-estado `preReview` na coluna Review (`specs.review_phase`: `auto` / `human`; `review_rounds`).
- Última etapa `done` + `revisor.ligado` → [`readonly_run`](../lib/core/claude/readonly_run.dart) com agente `spec-reviewer` embutido
  (sobrescrevível em `.claude/agents/spec-reviewer.md`), modelo/orçamento do config, `--json-schema`:
  `{veredito: "aprovar"|"corrigir", comentarios: [{arquivo, linha, texto, severidade, requisito}]}`.
  Entrada: spec, diff da branch contra a base, últimos relatórios do gate, `memoria.md` (quando existir).
- `corrigir` e rodadas < limite → etapa virtual `REV1` (linha em `spec_steps`) com os comentários como
  prompt; spec volta para Em execução; passa pelo gate da F1; volta ao revisor.
- `aprovar` ou limite → Review humano; comentários do revisor na lateral marcados "revisor automático"
  (tabela `review_comments` com `autor`, `rodada`).
- Código: `lib/features/review/auto_reviewer.dart` (chamado de [`review_service.dart`](../lib/features/review/review_service.dart)), agente embutido em `assets/agents/spec-reviewer.md`.

### F6 · Review completo ([04 §4.2](analise-ides/04-review-e-qualidade.md#42-diff-e-estado-do-review), [§4.3](analise-ides/04-review-e-qualidade.md#43-pr-e-merge), [§4.4](analise-ides/04-review-e-qualidade.md#44-critérios-de-aceite-como-verdade) · DT-36)

- **Todos os arquivos numa página** ([`review_diff_view.dart`](../lib/features/review/widgets/review_diff_view.dart), [`review_screen.dart`](../lib/features/review/review_screen.dart)) com navegação lateral (lista de arquivos com +/−), realce com
  `re_highlight`, alternância unificado/lado a lado.
- **Diff por etapa**: filtro por commits `SPEC-003 Rn` (`git log --grep`, diff do intervalo).
- **Checks no topo**: último gate de cada etapa; com PR, `gh pr checks`.
- **Critérios como checklist**: critérios `- [ ] … [R2]` da spec no painel; marcados pelo gate (quando
  têm `verificar:`), pelo revisor (lendo o diff) ou pelo humano. Merge bloqueado até todos marcados,
  com "Mergear mesmo assim" + motivo registrado (`specs.merge_override`).
- **Histórico de rodadas** (auto → humano → correções) com o commit de cada uma.
- `gh auth status` antes de Criar PR; opção "PR como rascunho" (DT-38).

---

## Onda 3 — Spec mais inteligente e Quadro operável (schema v11)

### F7 · Spec em camadas ([02 §2.3](analise-ides/02-fluxo-specs-e-quadro.md#23-spec-em-três-camadas-inspirado-no-kiro-sem-copiar-o-formato))

- Formato: `## Objetivo`, `## Requisitos` (EARS sugerido pelo planner), `## Design`, `## Etapas`
  (opcional: `- R2 → arquivos · verificar: <cmd>`), `## Critérios de aceite` com `[Rn]` e
  `verificar:` opcional. `SpecDocument` ([`spec_file.dart`](../lib/features/specs/spec_file.dart)) lê e escreve as seções novas; specs antigas
  continuam válidas.
- Tela Specs ([`specs_screen.dart`](../lib/features/specs/specs_screen.dart), planner em [`project_planner.dart`](../lib/features/project/project_planner.dart)): botão **"Gerar design"** (planner somente leitura com acesso ao repositório) entre Refinar
  e Aprovar. Aprovar exige Design ou a caixa "sem design (spec trivial)".
- [`specStepPrompt`](../lib/features/board/spec_runner.dart#L59) passa a incluir só o Objetivo, o trecho do Design ligado a `Rn` (por menção a `Rn`
  ou à lista de arquivos da etapa) e os critérios `[Rn]`; a spec inteira só quando não há ligação.
- `verificar:` dos critérios entra como check extra no gate da F1.

### F8 · Memória do projeto ([03 §3.5](analise-ides/03-sessoes-e-agentes.md#35-memória-do-projeto))

- `.promptorium/memoria.md` (versionado, limite ~60 linhas, cada linha `- texto  <!-- origem, data -->`).
- Fontes: gate (tempos e comandos descobertos), marcador `APRENDIZADO: …` na resposta da etapa (o prompt
  pede no máximo um por etapa), edição humana na tela Projeto.
- Entra no prompt de toda etapa, do revisor e do planner. Tela Projeto ([`project_screen.dart`](../lib/features/project/project_screen.dart)) → aba Memória com origem/data
  por linha, excluir, "Limpar entradas com mais de 30 dias".

### F9 · Quadro operável ([02 §2.5](analise-ides/02-fluxo-specs-e-quadro.md#25-spec-grande-demais--replanejar-no-meio), [§2.6](analise-ides/02-fluxo-specs-e-quadro.md#26-quadro-o-que-falta-para-operar-10-specs) · DT-33)

- **Linha ao vivo** no cartão: última `tool_use` da sessão (`Bash · flutter test`) + tempo na etapa
  (do [`timeline_provider`](../lib/features/sessions/timeline_provider.dart), sem consulta nova ao banco).
- **Grafo de ondas**: alternância Colunas/Grafo; colunas por onda de dependência, setas simples
  (`CustomPainter`); próxima onda destacada com Autopilot ligado.
- **Autopilot**: limite `paralelo` e `orcamento-dia` (soma de `cost_usd` das sessões de spec do dia);
  ao atingir, para e notifica.
- **Falha de sessão** → etapas `needs_input` e cartão sai de "Em execução" (o [`onEnded`](../lib/features/board/spec_runner.dart#L472) já faz parte;
  conferir crash do processo e `result` com erro).
- **Sugestões da sessão**: marcador `SPEC SUGESTÃO: …` → aviso no cartão com Aplicar (edita o arquivo,
  recria etapas pendentes) / Ignorar. Tabela `spec_suggestions`.
- Ordem na coluna persistida (`specs.board_order`).

### F10 · Menus e paleta ([02 §2.7](analise-ides/02-fluxo-specs-e-quadro.md#27-sequência-de-menus-proposta), [05 §5.8](analise-ides/05-plataforma-e-robustez.md#58-ide-básica) · DT-12)

- Ordem (em [`lib/ui/shell/`](../lib/ui/shell/)): Projeto · Specs · Quadro · Sessões · Review · Código · Prompt · Ferramentas (Agentes / Skills /
  MCP como sub-abas) · Configurações. Atalhos Ctrl+1…8 renumerados; aviso único "os atalhos mudaram".
- Quadro como tela inicial quando houver spec em execução.
- **Ctrl+K real**: telas, specs por código/título, sessões, ações ("Executar SPEC-003", "Aprovar
  pendente", "Ligar Autopilot"). Busca fuzzy simples (a mesma do Ctrl+P do Código).

---

## Onda 4 — Robustez de plataforma (schema v12)

### F11 · Banco, disco e processos ([05 §5.2–5.4](analise-ides/05-plataforma-e-robustez.md#52-banco-e-migrações-dt-16) · DT-16, 32, 42, 44)

- [`app_database.dart`](../lib/data/db/app_database.dart#L416): `drift_dev schema dump` de v8 em diante + `stepByStep` + teste gerado v1→vN.
- Backup `promptorium.sqlite.bak-v<N>` antes de migrar; Configurações → "Restaurar backup".
- `FileSystemEntity.watch` (debounce) em `specs/`, `.claude/agents`, `.claude/skills`, `.promptorium/`
  e árvore do Código; remove o polling de 10 s.
- Gravação atômica no Código ([`worktree_files.dart`](../lib/features/code/worktree_files.dart)): `tmp` + `rename`, copiando o modo com `stat`/`chmod` quando diferente.
- Spec alterada no disco durante a execução → aviso no cartão e Autopilot pausa essa spec até confirmar.
- PIDs dos `claude` em `sessions.pid`; no splash, matar órfãos (conferindo `/proc/<pid>/cmdline`).

### F12 · Permissões e segredos ([05 §5.5–5.6](analise-ides/05-plataforma-e-robustez.md#55-segredos-e-segurança) · DT-25, 45, 46, 48)

- Perguntar e planner com **lista de permitidos** (`--tools Read,Glob,Grep,WebFetch,WebSearch,…`) +
  `--strict-mcp-config`; MCP sem regra = Pedir.
- "Sem perguntar" só em worktree (trava, não só aviso).
- [`mcp_cli.dart`](../lib/features/mcp/mcp_cli.dart): `claude mcp add-json` lendo de arquivo `0600` temporário; mascarar tudo que não for flag conhecida.
- `claude mcp list` em segundo plano após o splash, com cache por workspace.

### F13 · IDE básica ([05 §5.8](analise-ides/05-plataforma-e-robustez.md#58-ide-básica) · DT-01, 02, 04, 05)

- Painel Git na tela Código ([`code_screen.dart`](../lib/features/code/code_screen.dart)): status, stage/unstage por arquivo, commit, branch atual.
- Busca global Ctrl+Shift+F (`rg --json` se existir, senão Dart).
- Aba Problemas: `lint:` ao salvar, saída parseada (formato `arquivo:linha:col: mensagem`).
- Central de notificações: histórico com "ir para".

---

## Onda 5 — Expansão ([06](analise-ides/06-roadmap-sugerido.md#onda-5--expansão-quando-o-ciclo-estiver-estável))

Sem detalhe de fase ainda; cada item vira spec própria quando a Onda 4 terminar:

- **F14** Métricas de qualidade por spec na tela Projeto (rodadas, turnos de correção automática, custo,
  tempo por etapa, hunks rejeitados). *Pode ser antecipada para logo depois da Onda 1* — os dados de
  gate e rodadas já estarão no banco, e medir o efeito das ondas 1–2 desde o início vale a pena.
- **F15** Best-of-N por etapa (dois worktrees temporários, escolher A/B no Review).
- **F16** Babysit de PR (`gh pr view --json` em polling, comentários do PR viram rodada de correção);
  merge com rebase/squash; sessão "resolver conflito".
- **F17** Agendamento do Autopilot (hora + orçamento; app aberto).
- **F18** Multi-provedor via cliente ACP; Flatpak; aviso de versão nova (GitHub Releases).

## Fora do plano

- Três arquivos por spec (Kiro); execução em nuvem própria; multi-provedor antes da Onda 4.

## Testes do próprio app ([05 §5.10](analise-ides/05-plataforma-e-robustez.md#510-testes-do-próprio-promptorium))

Começa na F1 e cresce a cada fase: **CLI falso com roteiro** (`test/helpers/scripted_cli.dart`, ao lado de [`test_db.dart`](../test/helpers/test_db.dart)) que
simula marcador sem commit, gate falhando, hook bloqueando, sessão que cai no meio. Ao fim das Ondas 1
e 2, um teste de integração com o CLI real (haiku, centavos) num workflow manual do GitHub Actions.

## Validações pendentes antes de começar

| Sonda | Bloqueia | Onde anotar |
|---|---|---|
| `--settings` com hooks em `-p --input-format stream-json` (Pre/PostToolUse, Stop com `block`, SessionEnd) | F2 (e decide se o gate da F1 roda no `Stop`) | `docs/pesquisa/hooks-settings-stream-json.md` |
| `control_request set_permission_mode` com sessão viva | trocar modo sem reiniciar (03 §3.6) | idem |
| mensagem `user` no meio do turno | fila de avisos imediata (DT-41) | idem |
| `--tools` como lista de permitidos + MCP | F12 | idem |

## Sequência e branches

| Fase | Branch | Depende de |
|---|---|---|
| F1 | `feat/gate-etapa` | — |
| F2 | `feat/hooks-gerenciados` | sonda de hooks, F1 |
| F3 | `feat/checkpoint-estado-duravel` | F1 (usa `start_sha`) |
| F4–F6 | `feat/worktree-pronto`, `feat/revisor-automatico`, `feat/review-completo` | Onda 1 |
| F7–F10 | `feat/spec-camadas`, `feat/memoria`, `feat/quadro-operavel`, `feat/menus-paleta` | Onda 2 (F10 é independente e pode adiantar) |
| F11–F13 | `feat/robustez-*` | — (independentes entre si) |

Sugestão para validar o próprio fluxo: criar F1→F2→F3 como specs do Promptorium com `depende-de` e
executá-las pelo Quadro.

## Execução (2026-10-17)

| Fase | Commit | Diferenças em relação ao plano |
|---|---|---|
| F1 | `672392c` | — |
| F2 | `cdd870f` | O gate **não** foi para o `Stop` (funciona, mas precisaria de IPC com o app e prenderia o turno; ver [pesquisa](pesquisa/hooks-settings-stream-json.md)). O hook é um script Python 3 escrito por sessão: sem `python3`, os hooks ficam desligados. `SessionEnd` registra o motivo na timeline, não o custo |
| F3 | `cc73922` | Os avisos de edição ao agente também passaram a entrar no meio do turno (sondado) |
| F4 | `e38aa7d` | Índice do worktree começa em 1 (a porta base fica livre para a raiz) |
| F5 | `9a99e3d` | As instruções do revisor embutido estão no código (`builtinReviewerPrompt`), não em `assets/agents/` |
| F6 | `0e9ec43` | Estado dos critérios em `spec_criteria` (v10); comentários das rodadas em `review_comments` |
| F7 | `f7ef7a9` | "Sem design" vira `design: dispensado` no frontmatter (diálogo ao aprovar) |
| F8 | `b921aa9` | O merge ignora alterações de `.promptorium/memoria.md` na raiz |
| F9 | `89b570f` | Ordem na coluna por "Subir/Descer" no menu (sem arrastar dentro da coluna); "Aplicar" de uma sugestão abre um Refinar no Prompt |
| F10 | `c687a64` | "Ferramentas" agrupa Agentes / Skills / MCP como abas (as seções continuam existindo por baixo) |
| F11 | `f65a0cf` | Watch recursivo do Dart não vê subpastas no Linux: um watcher por pasta (até 2000) + checagem de segurança a cada 30 s |
| F12 | `79b4ad9` | `claude mcp add-json` não lê de arquivo nem do stdin (sondado): segredos continuam no argv do `claude mcp` por segundos; o mascaramento ficou mais rígido |
| F13 | `75dc5fc` | — |
| F14 | `bd9c185` | Contadores em `specs` (v13) |
| F15 | `a1a0438` | Duas tentativas (A/B), não N; tabela `spec_duels` (v14) |
| F16 | `7746f72` | Só comentários e corpo das reviews (`gh pr view --json`); comentários por linha do PR não entram. `gh` não está instalado nesta máquina: só testado com runner falso |
| F17 | `a5056ef` | Agenda em `app_settings` por workspace |
| F18 | `23a8f3e` | Cliente ACP testado só com agente falso (o `gemini` local não roda em Node 18); Flatpak escrito e não testado (sem `flatpak-builder`) |

Testes: 330 → 413 (`flutter test`), `flutter analyze` limpo, `flutter build linux --release` ok. Teste
real com haiku da Onda 1: R2 recusada pelo gate e corrigida após um reenvio (US$ 0,01).
