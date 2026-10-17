# 01 — Panorama das IDEs e orquestradores de agentes (out/2026)

Agrupei por "família", porque o Promptorium compete em duas ao mesmo tempo: é um **orquestrador de
agentes** (como Conductor/Codex app) **e** uma ferramenta de **desenvolvimento dirigido por specs**
(como Kiro). Nenhum concorrente faz as duas coisas.

## Família A — Orquestradores de agentes em paralelo

| Ferramenta | Como isola | O que vale copiar | O que não tem |
|---|---|---|---|
| **Cursor 3.x (Agents Window)** | worktree por tarefa (`/worktree`), SSH, VM na nuvem; abas de agentes lado a lado/grade | `/best-of-n` (mesma tarefa em N modelos, escolher o melhor); `/multitask` (subagentes assíncronos); `/babysit` de PR; "Agent Tabs" com visão em grade | planejamento por spec, grafo de dependências, merge local |
| **Codex app (OpenAI)** | agentes locais ou na nuvem; "fila de review" quando terminam | fila de resultados prontos para revisar ("fechar o laptop e voltar"); escolha local × nuvem por tarefa | planner, quadro; usuário escolhe local/nuvem à mão |
| **Claude Code (desktop + CLI)** | worktrees automáticos por sessão no app; `--worktree` no CLI; subagentes com `isolation: worktree` | **hooks** (PreToolUse, PostToolUse, Stop, SessionStart, PermissionRequest, …); **checkpoints/`/rewind`**; tarefas agendadas; monitor de PR com auto-merge; remote control; preview do app | quadro/specs; o desktop é mais "N chats" que fluxo |
| **Conductor (Mac)** | worktree por "workspace", cada um com branch e pasta | **setup scripts** + "files to copy" (`.env`, gitignored) por workspace; `CONDUCTOR_PORT` (porta por worktree); checks (testes/erros) visíveis por workspace; roda Claude Code, Codex, Cursor, OpenCode | Linux, planner, specs |
| **Superset / Paseo** | idem, multi-CLI; Paseo é open source e roda em Linux | Paseo: Linux/mobile; Superset: muitos CLIs | o mesmo que Conductor |
| **Zed (Agent Panel + ACP)** | threads por agente externo via **Agent Client Protocol** | ACP como interface padrão para "plugar" Claude, Codex, Copilot, Cursor, OpenCode, Devin; Threads Sidebar (parar/arquivar/progresso) | quadro, specs |

## Família B — Desenvolvimento dirigido por specs

| Ferramenta | Fluxo | O que vale copiar | Limitação |
|---|---|---|---|
| **Kiro (AWS)** | prompt → `requirements.md` (EARS) → `design.md` → `tasks.md`; cada task referencia requisito e design; hooks on-save/pre-commit | separação requisito / design / tarefa; **EARS** ("Quando X, o sistema deve Y") deixa o critério verificável; hooks de evento; "steering" (regras por pasta) | não roda em paralelo com worktree, não fecha PR/merge |
| **Copilot (VS/VS Code/JetBrains)** | Plan (somente leitura, pergunta antes) → `.copilot/plans/*.md` → "Implement plan" → Agent/Autopilot; coding agent por issue abre PR; **agentic code review** gera PRs de correção | Plan que **pergunta** antes de escrever; review automático que devolve correções ao agente; Skills panel | tudo preso ao GitHub |
| **Windsurf (Cascade)** | memórias por projeto, Todo list por sessão, Turbo Mode, Codemaps | memórias automáticas (com o risco de ficarem velhas); Codemaps (mapa do código para orientar o agente) | sem worktree nativo até Wave 13 |

## Tabela "eles × nós"

Legenda: ✅ tem · ◐ parcial · ❌ não tem

| Capacidade | Promptorium | Cursor 3 | Claude Code | Codex app | Kiro | Conductor | Copilot |
|---|---|---|---|---|---|---|---|
| Planner que gera specs/roadmap com dependências | ✅ | ❌ | ❌ | ❌ | ◐ (sem grafo) | ❌ | ◐ (plan único) |
| Spec estruturada (req / design / tasks ligadas) | ◐ (req + critérios) | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ |
| Etapas em sessões de contexto limpo | ✅ | ❌ | ❌ | ❌ | ◐ | ❌ | ❌ |
| Worktree por unidade de trabalho | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ☁ |
| Setup script / cópia de `.env` / porta por worktree | ❌ | ◐ | ◐ (hook WorktreeCreate) | ❌ | ❌ | ✅ | ☁ |
| Autopilot por dependências (ondas) | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Checkpoints / rewind do agente | ❌ (DT-06) | ✅ | ✅ | ◐ | ✅ | ◐ (git) | ◐ |
| Hooks de ciclo de vida (lint/test/segurança) | ❌ | ◐ | ✅ | ◐ | ✅ | ◐ | ◐ |
| Gate de testes antes de "feito" | ❌ (só pede no prompt) | ❌ | ◐ (hook Stop) | ✅ (CI) | ◐ | ✅ (checks) | ✅ (CI) |
| Review automático por agente antes do humano | ❌ | ✅ (Bugbot) | ◐ (/code-review) | ✅ | ❌ | ❌ | ✅ |
| Fila de aprovações entre sessões + notificação | ✅ | ◐ | ◐ | ◐ | ◐ | ◐ | ◐ |
| Review local (diff, rejeitar hunk, comentar ao agente) | ✅ | ✅ | ✅ | ✅ | ◐ | ✅ | ◐ |
| Criar PR / merge local / fechar spec | ✅ | ◐ | ✅ | ✅ | ❌ | ✅ | ✅ |
| Babysit de PR (CI + comentários até mergear) | ❌ | ✅ | ✅ | ◐ | ❌ | ◐ | ✅ |
| Best-of-N (mesma tarefa, vários modelos) | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Agentes/skills/MCP com editor | ✅ | ◐ | ◐ | ◐ | ◐ | ❌ | ◐ |
| Catálogo de skills com origem e atualização | ✅ | ◐ | ◐ (plugins) | ❌ | ❌ | ❌ | ◐ |
| Memória do projeto (aprendizados entre sessões) | ❌ | ◐ | ✅ (auto-memory) | ◐ | ◐ | ❌ | ◐ |
| Uso do plano (5h / semana) no rodapé | ✅ | ◐ | ◐ | ◐ | ❌ | ❌ | ❌ |
| Multi-provedor (Codex, Gemini, OpenCode) | ❌ (DT-08) | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ |
| Execução na nuvem / fechar o laptop | ❌ | ✅ | ✅ (remote control) | ✅ | ❌ | ✅ (pago) | ✅ |
| Paleta de comandos, busca global, painel Git | ◐ (DT-01, 02, 12) | ✅ | n/a | ◐ | ✅ | ◐ | ✅ |
| Linux | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ | ✅ |

## Três leituras da tabela

1. **O diferencial do Promptorium é a coluna da esquerda da tabela** (planner → spec → etapas →
   ondas). Nada que fazemos deve diluir isso; as melhorias devem proteger esse ciclo.
2. **As três lacunas que os outros já consideram básico** são checkpoints, hooks/gate de testes e
   worktree pronto para rodar. São baratas de fazer (o CLI já entrega hooks e checkpoints) e tiram
   o risco de "etapa marcada como concluída que não compila".
3. **Review automático** é o que mais eleva a qualidade por dólar: uma sessão barata (haiku/sonnet,
   somente leitura) revisando o diff da spec antes do humano, com comentários que já voltam para a
   sessão da etapa.

## Fontes consultadas

- Cursor: [Agents Window](https://developertoolkit.ai/en/cursor-ide/build/agents-window/), [Cursor 2.0 guia](https://medium.com/towards-data-engineering/parallel-ai-agents-in-cursor-2-0-a-practical-guide-e808f89cffb9), [notas 2026](https://techsy.io/en/blog/how-to-use-cursor-more-efficiently)
- Claude Code: [desktop quickstart](https://code.claude.com/docs/en/desktop-quickstart), [hooks](https://code.claude.com/docs/en/hooks), [changelog 2.1.222](https://dev.classmethod.jp/en/articles/20260805-cc-updates-v2-1-222/), [tarefas agendadas](https://www.implicator.ai/anthropic-launches-scheduled-tasks-for-claude-code-but-your-laptop-has-to-stay-on-2)
- Codex app: [primeiras impressões](https://verdent.ai/guides/codex-app-first-impressions-2026)
- Kiro: [review 2026](https://pasqualepillitteri.it/en/news/6370/amazon-kiro-ide-spec-driven-review), [guia spec-driven](https://noqta.tn/en/blog/kiro-aws-agentic-ide-spec-driven-development-guide-2026), [Hora de Codar](https://horadecodar.com.br/kiro-spec-driven-development/)
- Conductor: [workflows](https://www.conductor.build/workflows/run-parallel-claude-codes), [vs Superset](https://www.conductor.build/compare/superset), [Paseo](https://paseo.sh/docs/alternatives/conductor)
- Copilot: [Visual Studio maio/2026](https://github.blog/changelog/2026-06-04-github-copilot-in-visual-studio-may-update), [modos (JetBrains)](https://www.jetbrains.com/help/ai-assistant/copilot-agent.html)
- Windsurf: [review](https://www.secondtalent.com/resources/windsurf-review/), [comparação](https://www.augmentcode.com/tools/antigravity-vs-windsurf-comparison)
- Zed/ACP: [external agents](https://zed.dev/docs/ai/external-agents), [Codex no Zed](https://codex.danielvaughan.com/2026/05/05/codex-cli-in-zed-parallel-agents-acp-integration-ide-workflows/)

Datas e nomes de comandos de terceiros (ex.: `/best-of-n`, Wave 13) vieram de blogs; conferir nos
changelogs oficiais antes de citar numa spec.
