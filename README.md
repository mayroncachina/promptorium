# Promptorium

> O laboratório de onde operam os comandos dos seus agentes.

IDE desktop para Linux, feita em Flutter, para gerenciar sessões, specs (o quadro) e agentes do
**Claude Code CLI**. O app não fala com a API diretamente: cada sessão é um processo
`claude -p --input-format stream-json --output-format stream-json`, com aprovações de ferramenta
pela própria stdin/stdout (`--permission-prompt-tool stdio`). Cada spec roda num
`git worktree` próprio (`~/.promptorium/worktrees/<repo>-<slug>`, branch `pr/<slug>`).

- Plano de implementação (fases, decisões, sondagens do CLI): [`docs/plano-implementacao.md`](docs/plano-implementacao.md)
- Débito técnico e pendências de conferência manual: [`docs/debito-tecnico.md`](docs/debito-tecnico.md)
- Mockups: https://claude.ai/artifact/SjkEe4XHWMvccd1VaQGAua (fontes em [`docs/mockups/`](docs/mockups/))
- Pesquisa (exemplos reais de stream-json, sondas): [`docs/pesquisa/`](docs/pesquisa/)
- Vídeo de demonstração: `docs/demo/promptorium-demo.mp4` (local, fora do git)

## Funcionalidades

| Tela | O que faz |
|---|---|
| **Projeto** | Planejamento de um projeto com o planner, em etapas: **Visão** (conversa; o plano — resumo, público, MVP, fora do escopo, dúvidas — é atualizado a cada resposta), **Stack e convenções** (uma escolha por área com alternativas clicáveis + `CLAUDE.md` editável), **Roadmap** (specs da Fundação e do MVP com código, requisitos — as etapas — e dependências entre specs; no máximo 6 requisitos por spec, o planner divide o que passar; ordem de execução em ondas; tudo editável à mão: specs — título, fase, objetivo, requisitos, critérios, "depende de" —, adicionar/excluir e ideias para depois — clicar numa ideia a traz para o roadmap como spec gerada pelo planner ou vazia; regerar pede confirmação se houver edições) e **Revisar e criar** (grava `CLAUDE.md` e `specs/` com `depende-de`, coloca as specs no Quadro, commita na branch atual e abre a sessão da 1ª etapa da 1ª spec). O planner é somente leitura (`claude -p --json-schema`, a Visão continua com `--resume`); o rascunho fica em `project_plans`. **Novo projeto…** (seletor de workspace ou barra de título) cria a pasta, roda `git init` e abre o planejamento. **Apagar projeto** (confirmação digitando o nome): para sessões e conversas, remove os worktrees, manda a pasta para a lixeira (`gio trash`) e apaga tudo o que o app guarda do workspace; recusa `/`, a home e pastas acima dela |
| **Splash** | Animação do frasco com progresso ligado aos passos reais: `claude --version`, banco, workspaces, worktrees, sessões. Erro claro se o CLI não for encontrado |
| **Sessões** | Lista com filtros; timeline ao vivo (texto em streaming, cards de Read/Edit/Bash…, subagentes aninhados); composer (Ctrl+Enter, anexar spec); **fila de aprovações** de todas as sessões (Aprovar / Negar / Sempre permitir) + notificação nativa; detalhes (tokens, custo, session id, arquivos alterados, diff); terminal `claude --resume` embutido; Fork, Parar, Retomar (sessões vivas viram "interrompidas" ao reabrir o app) |
| **Prompt** | Conversa livre na raiz do workspace (sem worktree). Modos **Perguntar** (somente leitura), **Planejar** (`plan`), **Editar** (`acceptEdits`); `@arquivo` e `/prompt-salvo`; ações Copiar, Salvar como prompt, Transformar em spec, Continuar como sessão |
| **Specs** | Arquivos `specs/SPEC-NNN-*.md` com frontmatter (`id`, `status`); editor de código (realce, números de linha, Ctrl+F/Ctrl+H, zoom salvo), modos Editar / Dividido / Visualizar; Refinar com IA, Aprovar spec; o painel **Etapas** lista os requisitos com estado, sessão de cada um e Executar/Continuar; frontmatter também com `fase` e `depende-de` |
| **Quadro** | Um cartão por spec aprovada (Backlog / Em execução / Review / Feito): progresso das etapas ("3/7"), etapa atual, bloqueio por dependência (`depende-de`), agente, custo e a ação do momento. **Executar** cria o worktree da spec (`pr/spec-NNN-…`) e abre uma sessão por etapa, com contexto limpo (spec embutida no prompt, etapas feitas, a de agora; pede commit `SPEC-003 R2: …` e a linha `ETAPA CONCLUÍDA: R2`). Sem a linha, a etapa espera por você ("Responder na sessão"); com avanço automático (por spec) a próxima abre sozinha; todas feitas → Review. Spec com até 3 etapas (configurável) roda inteira numa sessão. Uma sessão por spec de cada vez; specs diferentes em paralelo. Tarefas antigas sem spec: aviso com *Virar spec* / *Descartar* |
| **Agentes** | `~/.claude/agents` e `<repo>/.claude/agents` (Global / Projeto, "sobrescreve o global"); editor com prévia ao vivo do `.md` (preserva campos desconhecidos e comentários), orçamento, máx. de turnos e esforço (`effort`) aplicados às sessões; Testar em sessão |
| **Skills** | **Instaladas**: skills de projeto (`.claude/skills/<nome>/SKILL.md`) e globais (`~/.claude/skills`), editor do `SKILL.md` (name, description com contador, `allowed-tools`, instruções com prévia; campos desconhecidos preservados), arquivos, origem, uso nas sessões, Testar em sessão, Copiar para Global/Projeto, Remover; skills de plugins e embutidas listadas só para leitura (do `system/init`). **Catálogo** (somente leitura): repositórios GitHub com uma pasta por skill, `<nome>/SKILL.md` na raiz ou em `skills/<nome>/SKILL.md` (padrão `mayroncachina/promptorium-skills`, outros podem ser adicionados), clonados em `~/.promptorium/catalogs/` e sincronizados com git; Instalar no projeto ou global (registra origem e hash em `.promptorium-origin.json`), aviso de versão nova e de mudança local, Atualizar. **Nova skill**: escrever com o Claude (descrição ou a partir de uma sessão, `claude -p --json-schema` somente leitura) ou em branco |
| **Review** | Sessões aguardando review; diff contra o merge-base (commits + não commitados + não rastreados); rejeitar hunk (`git apply -R`); comentários por linha enviados ao agente; Criar PR (`git push` + `gh pr create`, se `gh` existir); Fazer merge (`--no-ff`, remove worktree e branch; spec → Feito, etapas concluídas e `status: concluida` commitado à parte). Um item por spec, com o PR listando as etapas |
| **Código** | Seletor de worktree (raiz + sessões); árvore respeitando `.gitignore` com marcas A/M/D; editor em abas (Ctrl+S, Ctrl+W, Ctrl+P), marcas na margem (alterado pelo agente × edição não salva); aviso/“Pausar agente” quando há sessão ativa e aviso automático ao agente ao salvar; terminal do `$SHELL` no worktree |
| **Configurações** | **Consumo**: modelo e esforço (`--effort`) padrão para Sessões (Sonnet · medium), Conversas do Prompt (Sonnet · medium) e Planner (padrão do CLI · medium), e compactação automática (`--autocompact`, padrão 200k) para todas as execuções; Restaurar padrões. Nova sessão começa com esses valores (um agente com `model`/`effort` usa os dele) |
| **MCP** | Servidores por escopo (Global / Local / Projeto, sobrescritos), status (`claude mcp list` / `system/init`), detalhes com segredos mascarados; regra por ferramenta Permitido / Pedir / Bloqueado (`--allowedTools` / `--disallowedTools`); adicionar/remover via `claude mcp add/remove`; testar conexão; log recente |

Rodapé fixo: CLI, sessões ativas/aguardando, subagentes, MCP e o uso do plano — janelas de 5h e da
semana com % usado, % restante e quando reiniciam (do último `rate_limit_event`, guardado entre
aberturas do app; "limite atingido · volta em …" quando o plano recusa).

O app só usa `--dangerously-skip-permissions` quando você escolhe o modo **"sem perguntar nada
(perigoso)"** em Nova sessão (desligado por padrão, com aviso; a escolha fica lembrada para a
próxima sessão; nunca é pré-selecionado por um agente). O planner, as conversas do Prompt e as
sondagens nunca usam. O app nunca escreve `~/.claude.json` ou `.mcp.json` diretamente (só via
`claude mcp …`).

## Atalhos de teclado

| Atalho | Ação |
|---|---|
| Ctrl+1 … Ctrl+9 | Ir para Sessões, Prompt, Specs, Quadro, Agentes, Review, Código, MCP, Projeto |
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
| `libx11-dev`, `libxi-dev` | — | Ícone na bandeja (`tray_manager` 0.8 / nativeapi; StatusNotifierItem por D-Bus, sem AppIndicator) |
| `gh` (GitHub CLI) | opcional | Botão "Criar PR" no Review |

Instalação no Ubuntu/Debian:

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev \
  libsqlite3-dev libnotify-dev libx11-dev libxi-dev
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
| `tray_manager` | ^0.8.0 | 0.8.0 | Ícone na bandeja no Linux (SPEC-020) |
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
flutter test                      # 284 testes; os 3 de integração ficam pulados
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

## Distribuição

Pacotes Linux x64 (Ubuntu/Debian 22.04 ou mais novo) nas **Releases** do GitHub:

| Arquivo | Uso |
|---|---|
| `promptorium_<versão>_amd64.deb` | `sudo apt install ./promptorium_<versão>_amd64.deb` — instala em `/opt/promptorium`, comando `promptorium`, atalho no menu e ícones; o apt instala `git` e as bibliotecas (GTK, libnotify, X11); `gh` é recomendado |
| `promptorium-<versão>-linux-x64.tar.gz` | portátil: extrair e rodar `./promptorium` (sem atalho) |

O **Claude Code CLI** não vem em pacote .deb. O `.deb` avisa no fim da instalação quando o
`claude` não existe, e o app mostra a mesma instrução ao abrir. Instale, com o seu usuário:

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

Os dados (`~/.local/share/promptorium/promptorium.sqlite`) ficam fora do pacote: remover ou
atualizar o `.deb` não os apaga.

### Publicar uma versão

1. No GitHub: **Releases → Draft a new release**, crie a tag `vX.Y.Z` (ex.: `v0.1.0`) apontando
   para a `main` e publique. Sem texto, as notas saem do `git cliff`.
2. O workflow `.github/workflows/release.yml` roda `flutter analyze` e `flutter test`, compila
   (`--build-name` = a versão da tag), empacota com `scripts/package.sh` e anexa o `.deb` e o
   `.tar.gz` à release. Se analyze ou testes falharem, nada é anexado.

Em todo PR e ao mergear na `main`, o workflow `ci.yml` só roda `flutter analyze` e `flutter test`:
o `.deb` é gerado apenas ao publicar uma release.

Para gerar os pacotes localmente: `flutter build linux --release && scripts/package.sh 0.1.0`
(saída em `dist/`).

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
