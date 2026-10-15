# Promptorium

> O laboratório de onde operam os comandos dos seus agentes.

IDE desktop para Linux, feita em Flutter, para gerenciar sessões, tarefas, specs e agentes do **Claude Code CLI**.

- Plano de implementação: [`docs/plano-implementacao.md`](docs/plano-implementacao.md)
- Débito técnico: [`docs/debito-tecnico.md`](docs/debito-tecnico.md)
- Mockups: https://claude.ai/artifact/SjkEe4XHWMvccd1VaQGAua

## Requisitos

### Sistema (Linux)

| Requisito | Versão | Para quê |
|---|---|---|
| Flutter SDK | ≥ 3.47 (Dart ≥ 3.13) | Build do app |
| Claude Code CLI (`claude`) | ≥ 2.1.300 | Motor das sessões e agentes |
| git | qualquer recente | Worktrees, diff, merge |
| clang, cmake, ninja, pkg-config | — | Toolchain Linux do Flutter |
| `libgtk-3-dev` | — | Janela (Flutter Linux) |
| `libsqlite3-dev` | — | Banco local |
| `libnotify-dev` | — | Notificações nativas (`local_notifier`) |
| `libayatana-appindicator3-dev` | — | Ícone na bandeja (`tray_manager`, opcional) |
| `gh` (GitHub CLI) | opcional | Botão "Criar PR" no Review |

Instalação no Ubuntu/Debian:

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev \
  libsqlite3-dev libnotify-dev libayatana-appindicator3-dev
```

### Pacotes Flutter

Versões **instaladas** (resolvidas no `pubspec.lock`):

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
| `tray_manager` | ^0.8.0 | 0.8.0 | Bandeja (opcional) |
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

> Versões confirmadas em 2026-10-14. Detalhes, APIs e o que **não** usar: Fase 0 do plano.

## Rodando

```bash
flutter pub get
flutter run -d linux
```

O código gerado pelo drift (`lib/data/db/*.g.dart`) é versionado. Depois de alterar tabelas
em `lib/data/db/app_database.dart`, regenere com `dart run build_runner build`.

Dados locais: `~/.local/share/promptorium/promptorium.sqlite` (workspaces, specs, tarefas,
sessões, preferências). Nenhum segredo (tokens de MCP) é gravado no banco.
