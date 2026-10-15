# Débito técnico — Promptorium

Itens identificados durante o desenho dos mockups (2026-10-14) que **não** entram no MVP inicial,
mas são necessários para o Promptorium ser uma IDE robusta.

Mockups: https://claude.ai/artifact/SjkEe4XHWMvccd1VaQGAua

| # | Item | Prioridade | Observações |
|---|------|-----------|-------------|
| DT-01 | **Painel Git** — status, stage, commit, branches, histórico | Alta | Hoje só existe o Review no fim do fluxo |
| DT-02 | **Busca global e substituição** (Ctrl+Shift+F) | Alta | Buscar em todos os arquivos do worktree |
| DT-03 | **Tela de Configurações** | Alta | Engrenagem já existe na barra lateral, sem tela. Caminho do CLI, tema, atalhos, provedores, orçamento padrão |
| DT-04 | **Diagnósticos via LSP** (erros e avisos no editor, aba "Problemas") | Média | No MVP pode ser só `flutter analyze` |
| DT-05 | **Central de notificações** e **folha de atalhos** | Média | Histórico de "sessão terminou", "aprovação pendente" |
| DT-06 | **Checkpoints** — voltar o worktree para antes de uma alteração do agente | Média | |
| ~~DT-07~~ | ~~Uso do plano (5h / semanal) no rodapé~~ | — | **Resolvido na pesquisa:** vem no evento `rate_limit_event` do stream-json. Entra na Fase 5 |
| DT-08 | **Múltiplos provedores** (Codex, Gemini CLI) | Baixa | Fase 6: interface `AgentProvider` + registro com Codex/Gemini CLI como "em breve" (desabilitados); ícone do botão segue o provedor ativo. Falta a implementação: cada provedor precisa traduzir sua saída para `ClaudeEvent` (vocabulário da timeline) e ter sua própria noção de modo somente leitura |
| DT-09 | **Ícone: arte vetorial / bordas** | Baixa | Fase 1 gerou os PNGs recortando `icon.webp` (1254px) com máscara de cantos arredondados aproximada via ffmpeg (raio ≈ 200px). Ideal: SVG de origem + ícone simbólico para o painel |
| DT-10 | **Instalação desktop** (`.desktop` + ícones hicolor) | Média | `linux/promptorium.desktop` existe (`Exec=promptorium`, `Icon=promptorium`, `StartupWMClass=dev.promptorium.promptorium`), mas ainda não é instalado; previsto na Fase 12 |
| DT-11 | **Splash em janela própria** (720×440, sem decoração) | Baixa | Fase 2 desenha o cartão 720×440 dentro da janela 1440×900. Redimensionar via `window_manager` (`setSize`/`setTitleBarStyle`) exige mexer também no runner GTK, que já abre em 1440×900 |
| DT-12 | **Paleta de comandos real** (Ctrl+K) e busca de arquivos (Ctrl+P na tela Código) | Média | Fase 2 só tem um stub com "Ir para …" de cada tela |
| ~~DT-13~~ | ~~Persistir zoom por editor e última tela ativa~~ | — | **Resolvido na Fase 3:** `app_settings` (`editor.zoom.<editor>`, `ui.lastSection`) |
| ~~DT-14~~ | ~~Seletor de workspace na barra de título~~ | — | **Resolvido na Fase 3:** lista/seleciona/remove/adiciona pasta git; ativo em `app_settings` (`workspace.active`). Branch atual no botão: Fase 4 |
| DT-15 | **Seletor de pasta nativo** ao adicionar workspace | Baixa | Fase 3 usa campo de texto com caminho (sem pacote de file picker). Avaliar `file_selector` (registrar na tabela 0.4) |
| DT-16 | **Migrações do banco** | Média | Fase 5 subiu para v2 e a Fase 6 para v3 com `onUpgrade` manual (`addColumn`/`createTable`) + testes v1→v3 e v2→v3 com SQL escrito à mão. Falta `drift_dev schema dump` + `stepByStep` e testes gerados |
| DT-17 | **Terminal interativo fora da timeline** | Média | O que acontece em `claude --resume` no PTY não vira `session_events` (só seria visível lendo a transcrição `.jsonl`, formato interno — anti-padrão 0.5). Custo/tokens dessa parte não entram no banco |
| DT-18 | **Fork sem alterações não commitadas** | Média | Fork cria worktree a partir da branch do pai; arquivos sujos do pai não são copiados (a conversa do fork "acha" que estão lá). Avaliar `git stash create` + `stash apply` no novo worktree |
| DT-19 | **Mudar modo de permissão com a sessão viva** | Baixa | Hoje só vale ao retomar. Verificar se o stream-json aceita `control_request` `set_permission_mode` (não listado na 0.2) |
| DT-20 | **Thinking e deltas no log** | Baixa | `stream_event` não é gravado; blocos `thinking` não aparecem na timeline (só no log bruto, quando vêm no `assistant`) |
| DT-21 | **Excluir sessão / limpar worktrees** | Média | Sem ação de excluir sessão nem remover worktree/branch `pr/<slug>` (merge + limpeza é Fase 9) |
| DT-22 | **Composer: anexar spec, `/comandos`, `@arquivos`** | Média | Fase 6 fez `@`/`/` no composer do **Prompt**; o composer de Sessões ainda não tem (extrair o seletor para reuso) e "anexar spec" é Fase 8 |
| ~~DT-23~~ | ~~Configurações por agente na sessão~~ | — | **Resolvido na Fase 7:** `SessionManager` passa `--max-budget-usd` (`agent_settings.budgetUsd` do escopo efetivo) e `--max-turns` (`maxTurns` do frontmatter) em create, `--resume` e fork; a Nova sessão pré-seleciona o `permissionMode` do agente. MCPs do agente ficam no frontmatter (`mcpServers`) — efeito com `--agent` não verificado (DT-31) |
| DT-24 | **Notificações: conferência manual** | Baixa | Clique da notificação depende do servidor de notificações (libnotify/GNOME); verificar no desktop real. Sem agrupamento/histórico (ver DT-05) |
| DT-25 | **Modo Perguntar: lista fixa de ferramentas bloqueadas** | Média | `--disallowedTools` com 10 nomes da 2.1.300 (4 testados ao vivo). Ferramentas novas de versões futuras do CLI e ferramentas **MCP** não são bloqueadas (MCP passa por aprovação inline). Reavaliar a cada atualização do CLI; alternativa: lista de permitidas com `--tools Read,Glob,Grep,…` (precisa entrar na 0.2 e ser testada) e/ou `--strict-mcp-config` no Perguntar |
| DT-26 | **Planejar não é somente leitura** | Média | `--permission-mode plan` grava o plano em `~/.claude/plans/` sem pedir e, se o usuário aprovar `ExitPlanMode`, sai do modo plano e pode editar. Avaliar negar `ExitPlanMode` automaticamente no Planejar (ou trocar o modo da conversa para Editar ao aprovar) |
| DT-27 | **Conversas: gestão e avisos** | Baixa | Sem renomear/excluir/buscar conversa; aprovações pendentes da conversa não geram notificação nativa nem aparecem na fila de Sessões; mudar modo/modelo reinicia o processo (`--resume`) no próximo envio |
| DT-28 | **"Transformar em spec" sem resumo por IA** | Baixa | O corpo é a conversa cortada (600/1500 caracteres por mensagem) + seções vazias. Gerar com o planner (`--json-schema`) na Fase 8 |
| DT-29 | **"Continuar como sessão" — conferência manual** | Baixa | Coberto por teste com CLI falso; o fork de uma sessão iniciada na raiz para um worktree (`--resume` de outro cwd) só foi sondado separadamente na Fase 5 |
| DT-30 | **Editor de agentes: prompt sem editor de código** | Baixa | Prompt de sistema é `TextField` multilinha mono (sem realce Markdown, busca ou zoom). Trocar por `re_editor` quando o editor da Fase 10 existir. Sem “Adicionar” MCP manual (só chips dos nomes configurados) e sem `disallowedTools`/`color`/`effort` na UI (preservados no arquivo) |
| DT-31 | **Frontmatter com `--agent`: o que o CLI aplica** | Média | Sondado sem custo (2.1.300): `tools` e `model` aplicados; `permissionMode` **não** (o app passa `--permission-mode`). `maxTurns` e `mcpServers` não verificáveis sem chamar o modelo — `maxTurns` é repassado como `--max-turns`; `mcpServers` não é repassado. Semântica de `--max-budget-usd` no `--resume` (custo cumulativo da linhagem?) também não verificada. `claude agents --json` lista sessões, não definições |

## Requisitos de UX já decididos

### Editor (Specs e Código)
O editor usado para criar e editar specs — e o editor da tela de Código — precisa ser um editor de código de verdade:

- Realce de sintaxe (Markdown nas specs, Dart/YAML/JSON no código)
- Números de linha, busca e substituição no arquivo (Ctrl+F / Ctrl+H)
- **Zoom in / out**: Ctrl+= aumenta, Ctrl+- diminui, Ctrl+0 volta ao padrão; controle visível no topo do editor (− 100% +)
- Zoom salvo por editor (specs e código podem ter tamanhos diferentes)
- Modo dividido (fonte + visualização) nas specs
