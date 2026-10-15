# Promptorium

> O laboratório de onde operam os comandos dos seus agentes.

IDE desktop para Linux, feita em Flutter, para gerenciar sessões, tarefas, specs e agentes do
**Claude Code CLI**. O app não fala com a API diretamente: cada sessão é um processo
`claude -p --input-format stream-json --output-format stream-json`, com aprovações de ferramenta
pela própria stdin/stdout (`--permission-prompt-tool stdio`). Cada sessão de tarefa roda num
`git worktree` próprio (`~/.promptorium/worktrees/<repo>-<slug>`, branch `pr/<slug>`).

- Plano de implementação (fases, decisões, sondagens do CLI): [`docs/plano-implementacao.md`](docs/plano-implementacao.md)
- Débito técnico e pendências de conferência manual: [`docs/debito-tecnico.md`](docs/debito-tecnico.md)
- Mockups: https://claude.ai/artifact/SjkEe4XHWMvccd1VaQGAua (fontes em [`docs/mockups/`](docs/mockups/))
- Pesquisa (exemplos reais de stream-json, sondas): [`docs/pesquisa/`](docs/pesquisa/)
- Vídeo de demonstração: `docs/demo/promptorium-demo.mp4` (local, fora do git)

## Funcionalidades

| Tela | O que faz |
|---|---|
| **Projeto** | Planejamento de um projeto com o planner, em etapas: **Visão** (conversa; o plano — resumo, público, MVP, fora do escopo, dúvidas — é atualizado a cada resposta), **Stack e convenções** (uma escolha por área com alternativas clicáveis + `CLAUDE.md` editável), **Roadmap** (specs da Fundação e do MVP, tarefas com dependências, ordem de execução; tudo editável à mão: specs — título, fase, objetivo, requisitos, critérios —, tarefas — título, descrição, spec, requisito, dependências —, adicionar/excluir e ideias para depois — clicar numa ideia a traz para o roadmap como spec gerada pelo planner, com tarefas, ou vazia; regerar pede confirmação se houver edições) e **Revisar e criar** (grava `CLAUDE.md` e `specs/`, cria as tarefas, commita na branch atual e abre a sessão da 1ª tarefa). O planner é somente leitura (`claude -p --json-schema`, a Visão continua com `--resume`); o rascunho fica em `project_plans`. **Novo projeto…** (seletor de workspace ou barra de título) cria a pasta, roda `git init` e abre o planejamento. **Apagar projeto** (confirmação digitando o nome): para sessões e conversas, remove os worktrees, manda a pasta para a lixeira (`gio trash`) e apaga tudo o que o app guarda do workspace; recusa `/`, a home e pastas acima dela |
| **Splash** | Animação do frasco com progresso ligado aos passos reais: `claude --version`, banco, workspaces, worktrees, sessões. Erro claro se o CLI não for encontrado |
| **Sessões** | Lista com filtros; timeline ao vivo (texto em streaming, cards de Read/Edit/Bash…, subagentes aninhados); composer (Ctrl+Enter, anexar spec); **fila de aprovações** de todas as sessões (Aprovar / Negar / Sempre permitir) + notificação nativa; detalhes (tokens, custo, session id, arquivos alterados, diff); terminal `claude --resume` embutido; Fork, Parar, Retomar (sessões vivas viram "interrompidas" ao reabrir o app) |
| **Prompt** | Conversa livre na raiz do workspace (sem worktree). Modos **Perguntar** (somente leitura), **Planejar** (`plan`), **Editar** (`acceptEdits`); `@arquivo` e `/prompt-salvo`; ações Copiar, Criar tarefa, Salvar como prompt, Transformar em spec, Continuar como sessão |
| **Specs** | Arquivos `specs/SPEC-NNN-*.md` com frontmatter (`id`, `status`); editor de código (realce, números de linha, Ctrl+F/Ctrl+H, zoom salvo), modos Editar / Dividido / Visualizar; Refinar com IA, Aprovar spec, **Gerar tarefas com o planner** (`--json-schema`); rastreabilidade requisito → tarefa → sessão → merge |
| **Tarefas** | Kanban Backlog / Em execução / Review / Feito ligado ao status das sessões; dependências bloqueiam; arrastar muda o status; "Executar com agente" cria a sessão |
| **Agentes** | `~/.claude/agents` e `<repo>/.claude/agents` (Global / Projeto, "sobrescreve o global"); editor com prévia ao vivo do `.md` (preserva campos desconhecidos e comentários), orçamento e máx. de turnos aplicados às sessões; Testar em sessão |
| **Skills** | **Instaladas**: skills de projeto (`.claude/skills/<nome>/SKILL.md`) e globais (`~/.claude/skills`), editor do `SKILL.md` (name, description com contador, `allowed-tools`, instruções com prévia; campos desconhecidos preservados), arquivos, origem, uso nas sessões, Testar em sessão, Copiar para Global/Projeto, Remover; skills de plugins e embutidas listadas só para leitura (do `system/init`). **Catálogo** (somente leitura): repositórios GitHub com uma pasta por skill, `<nome>/SKILL.md` na raiz ou em `skills/<nome>/SKILL.md` (padrão `mayroncachina/promptorium-skills`, outros podem ser adicionados), clonados em `~/.promptorium/catalogs/` e sincronizados com git; Instalar no projeto ou global (registra origem e hash em `.promptorium-origin.json`), aviso de versão nova e de mudança local, Atualizar. **Nova skill**: escrever com o Claude (descrição ou a partir de uma sessão, `claude -p --json-schema` somente leitura) ou em branco |
| **Review** | Sessões aguardando review; diff contra o merge-base (commits + não commitados + não rastreados); rejeitar hunk (`git apply -R`); comentários por linha enviados ao agente; Criar PR (`git push` + `gh pr create`, se `gh` existir); Fazer merge (`--no-ff`, remove worktree e branch, tarefa → Feito) |
| **Código** | Seletor de worktree (raiz + sessões); árvore respeitando `.gitignore` com marcas A/M/D; editor em abas (Ctrl+S, Ctrl+W, Ctrl+P), marcas na margem (alterado pelo agente × edição não salva); aviso/“Pausar agente” quando há sessão ativa e aviso automático ao agente ao salvar; terminal do `$SHELL` no worktree |
| **MCP** | Servidores por escopo (Global / Local / Projeto, sobrescritos), status (`claude mcp list` / `system/init`), detalhes com segredos mascarados; regra por ferramenta Permitido / Pedir / Bloqueado (`--allowedTools` / `--disallowedTools`); adicionar/remover via `claude mcp add/remove`; testar conexão; log recente |

Rodapé fixo: CLI, sessões ativas/aguardando, subagentes, MCP, tokens do dia, uso 5h / semana (do
`rate_limit_event`).

O app nunca usa `bypassPermissions` / `--dangerously-skip-permissions` e nunca escreve
`~/.claude.json` ou `.mcp.json` diretamente (só via `claude mcp …`).

## Atalhos de teclado

| Atalho | Ação |
|---|---|
| Ctrl+1 … Ctrl+9 | Ir para Sessões, Prompt, Specs, Tarefas, Agentes, Review, Código, MCP, Projeto |
| Ctrl+K | Paleta de comandos ("Ir para …"; ainda stub — DT-12) |
| Ctrl+N | Nova sessão |
| Ctrl+= / Ctrl+- / Ctrl+0 | Zoom do editor da tela ativa (Specs e Código têm zoom próprio) |
| Ctrl+Enter | Enviar mensagem (Sessões, Prompt) |
| Ctrl+F / Ctrl+H | Buscar / substituir no editor (Esc fecha) |
| Ctrl+S | Salvar (Specs, Código) |
| Ctrl+W | Fechar aba (Código) |
| Ctrl+P | Ir para arquivo (Código) |
| ↑ / ↓, Enter / Tab, Esc | Navegar, escolher e fechar as listas de `@arquivo` e `/prompt` |

## Requisitos

### Sistema (Linux)

| Requisito | Versão | Para quê |
|---|---|---|
| Flutter SDK | ≥ 3.47 (Dart ≥ 3.13) — testado com 3.47.7 | Build do app |
| Claude Code CLI (`claude`) | ≥ 2.1.300 — testado com 2.1.300 | Motor das sessões e agentes (procurado no PATH e em `~/.local/bin/claude`) |
| git | qualquer recente | Worktrees, diff, merge |
| clang, cmake, ninja, pkg-config | — | Toolchain Linux do Flutter |
| `libgtk-3-dev` | — | Janela (Flutter Linux) |
| `libsqlite3-dev` | — | Banco local |
| `libnotify-dev` | — | Notificações nativas (`local_notifier`) |
| `libayatana-appindicator3-dev` | — | Ícone na bandeja (`tray_manager`; build exige o pacote, bandeja ainda não usada) |
| `gh` (GitHub CLI) | opcional | Botão "Criar PR" no Review |

Instalação no Ubuntu/Debian:

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev \
  libsqlite3-dev libnotify-dev libayatana-appindicator3-dev
```

### Pacotes Flutter

Versões **instaladas** (conferidas com o `pubspec.lock`):

| Pacote | Restrição (`pubspec.yaml`) | Instalada | Uso |
|---|---|---|---|
| `flutter_riverpod` | ^3.4.3 | 3.4.3 | Estado (sem gerador de código) |
| `drift` | ^2.35.2 | 2.35.2 | Banco local SQLite |
| `drift_flutter` | ^0.3.1 | 0.3.1 | Abertura do banco (`driftDatabase`), sqlite embutido |
| `multi_split_view` | ^3.6.2 | 3.6.2 | Painéis redimensionáveis |
| `re_editor` | ^0.10.0 | 0.10.0 | Editor de código e specs (busca, zoom) |
| `re_highlight` | ^0.0.3 | 0.0.3 | Realce de sintaxe do editor |
| `flutter_markdown_plus` | ^1.0.12 | 1.0.12 | Visualização de Markdown |
| `xterm` | ^4.0.0 | 4.0.0 | Terminal embutido (UI) |
| `flutter_pty` | ^0.4.2 | 0.4.2 | Terminal embutido (PTY) |
| `window_manager` | ^0.5.2 | 0.5.2 | Tamanho, título e fundo da janela |
| `local_notifier` | ^0.1.6 | 0.1.6 | Notificações nativas |
| `tray_manager` | ^0.8.0 | 0.8.0 | Bandeja (opcional; ainda sem uso — DT-49) |
| `file_selector` | ^1.1.0 | 1.1.0 | Seletor de pastas nativo (adicionar workspace) |
| `path_provider` | ^2.1.6 | 2.1.6 | Diretórios do sistema |
| `uuid` | ^4.6.0 | 4.6.0 | IDs de sessão |
| `yaml` | ^3.1.4 | 3.1.4 | Frontmatter de agentes/specs |
| `drift_dev` (dev) | ^2.35.1 | 2.35.1 | Geração de código do drift |
| `build_runner` (dev) | ^2.16.2 | 2.16.2 | Geração de código |
| `flutter_lints` (dev) | ^6.0.0 | 6.0.0 | Lints padrão (`flutter create`) |

Transitivas relevantes: `sqlite3` 3.7.1 (via drift); `sqlite3_flutter_libs` 0.6.0+eol e
`sqlcipher_flutter_libs` 0.7.0+eol chegam via `drift_flutter` — são *shims* vazios do sqlite3 3.x
(não fazem nada), **não** são dependências diretas.

### Assets

| Asset | Fonte | Licença |
|---|---|---|
| IBM Plex Sans (Regular, Italic, Medium, SemiBold, Bold) | github.com/IBM/plex (`packages/plex-sans/fonts/complete/ttf`) | OFL 1.1 — `assets/fonts/OFL-IBMPlexSans.txt` |
| JetBrains Mono 2.304 (Regular, Italic, Medium, Bold) | github.com/JetBrains/JetBrainsMono (release v2.304) | OFL 1.1 — `assets/fonts/OFL-JetBrainsMono.txt` |
| Ícone 512/256/128/64/48/32 | `docs/mockups/icon.webp` recortado (ffmpeg) | — |

## Desenvolvimento

```bash
flutter pub get
flutter run -d linux
```

O código gerado pelo drift (`lib/data/db/*.g.dart`) é versionado. Depois de alterar tabelas
em `lib/data/db/app_database.dart`, regenere com `dart run build_runner build`.

Dados locais: `~/.local/share/promptorium/promptorium.sqlite` (workspaces, specs, tarefas,
sessões, conversas, preferências). Nenhum segredo (tokens/variáveis de MCP) é gravado no banco.

### Testes

```bash
flutter analyze
dart format --output=none --set-exit-if-changed lib test
flutter test                      # 281 testes; os 3 de integração ficam pulados
```

Testes de **integração** chamam o Claude Code CLI de verdade e **gastam alguns centavos** do
seu plano/conta (modelo `haiku`, `--max-budget-usd` baixo) — por isso ficam fora do `flutter test`
padrão (tag `integration` em `dart_test.yaml`):

```bash
flutter test --run-skipped -t integration test/integration
```

## Build e instalação

```bash
flutter build linux --release     # bundle em build/linux/x64/release/bundle (~35 MB)
scripts/install.sh                # ou: scripts/install.sh --build
```

`scripts/install.sh` (sem sudo, idempotente) instala:

| O quê | Onde |
|---|---|
| Bundle release | `~/.local/share/promptorium/app/` |
| Link no PATH | `~/.local/bin/promptorium` |
| Atalho do menu | `~/.local/share/applications/promptorium.desktop` (`Exec` com caminho absoluto) |
| Ícones | `~/.local/share/icons/hicolor/<N>x<N>/apps/promptorium.png` (32…512) |

e atualiza `update-desktop-database` / `gtk-update-icon-cache`, se existirem. O banco
(`~/.local/share/promptorium/promptorium.sqlite`) fica fora de `app/` e **nunca** é tocado.

```bash
scripts/uninstall.sh              # remove só o que o install criou; mantém os dados
```

## Estrutura

```
lib/
  main.dart, app.dart        janela, encerramento (mata processos claude/PTY ao fechar)
  core/
    claude/                  ClaudeEvent (stream-json), ClaudeProcess, ClaudeOptions (args), UsageTracker
    git/                     GitService (worktrees, diff, merge), DiffParser
    process/                 ProcessRunner (comandos curtos)
    providers/               AgentProvider, ClaudeCodeProvider, registro de provedores
    config/                  AppInfo
  data/
    db/                      drift: tabelas, enums, migrações (schema v6), código gerado
    repos/                   repositórios por agregado
    providers.dart           providers Riverpod do banco/repos
  features/                  splash, project, sessions, prompt, specs, tasks, agents, skills, review, code, mcp, settings
  ui/
    theme/                   tokens de cor e tipografia
    shell/                   barra de título, barra lateral, rodapé, atalhos
    widgets/                 componentes (AppCodeEditor, ícones, SVG mínimo…)
test/                        espelha lib/; fixtures reais do CLI 2.1.300; integration/ (CLI real)
scripts/                     install.sh, uninstall.sh
linux/                       runner GTK, promptorium.desktop
docs/                        plano, débito técnico, mockups, pesquisa
```
