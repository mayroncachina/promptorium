# Desenvolvimento

## Requisitos do sistema (Linux)

| Requisito | Versão | Para quê |
|---|---|---|
| Flutter SDK | 3.47.7 (Dart ≥ 3.13.5), a usada na CI | Build do app |
| Claude Code CLI (`claude`) | ≥ 2.1.300 | Sessões, agentes e testes de integração |
| git | recente | Worktrees, diff, merge |
| clang, cmake, ninja, pkg-config | — | Toolchain Linux do Flutter |
| `libgtk-3-dev` | — | Janela |
| `libsqlite3-dev` | — | Banco local |
| `libnotify-dev` | — | Notificações nativas |
| `libx11-dev`, `libxi-dev` | — | Ícone na bandeja (`tray_manager` 0.8, por D-Bus, sem AppIndicator) |
| `gh` | opcional | PRs no Review |
| `python3` | opcional | Hooks gerenciados (Configurações › Automações) |

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev \
  libsqlite3-dev libnotify-dev libx11-dev libxi-dev
```

## Rodar

```bash
flutter pub get
flutter run -d linux
```

## Pacotes

| Pacote | Uso |
|---|---|
| `flutter_riverpod` | Estado (sem gerador de código) |
| `drift`, `drift_flutter` | Banco local SQLite |
| `multi_split_view` | Painéis redimensionáveis |
| `re_editor`, `re_highlight` | Editor de código e specs, realce |
| `flutter_markdown_plus` | Visualização de Markdown |
| `xterm`, `flutter_pty` | Terminal embutido |
| `window_manager` | Janela |
| `tray_manager` | Ícone na bandeja |
| `local_notifier` | Notificações nativas |
| `file_selector`, `desktop_drop` | Seletor de pastas e arrastar arquivos |
| `package_info_plus` | Versão do app (splash, Sobre, atualizador) |
| `crypto` | Hashes (catálogo de skills, `.sha256` das releases) |
| `path`, `path_provider`, `uuid`, `yaml` | Utilitários |
| `drift_dev`, `build_runner` (dev) | Geração de código do drift |
| `flutter_lints` (dev) | Lints |

As versões estão no `pubspec.yaml` e no `pubspec.lock`.

## Assets

| Asset | Fonte | Licença |
|---|---|---|
| IBM Plex Sans | github.com/IBM/plex | OFL 1.1 (`assets/fonts/OFL-IBMPlexSans.txt`) |
| JetBrains Mono 2.304 | github.com/JetBrains/JetBrainsMono | OFL 1.1 (`assets/fonts/OFL-JetBrainsMono.txt`) |
| Ícone 32 a 512 px | `docs/mockups/icon.webp` recortado | — |

## Banco e migrações

O código gerado pelo drift (`lib/data/db/*.g.dart`) é versionado. A versão do schema fica em `appSchemaVersion` (`lib/data/db/app_database.dart`). Para alterar tabelas:

1. Mude as tabelas e suba `appSchemaVersion`.
2. `dart run drift_dev schema dump lib/data/db/app_database.dart drift_schemas/`.
3. `dart run drift_dev schema steps drift_schemas/ lib/data/db/schema_versions.dart` e `dart run build_runner build`.
4. `dart run drift_dev schema generate drift_schemas/ test/generated_migrations/`; `test/data/generated_migration_test.dart` confere o caminho de todas as versões.

## Testes

```bash
flutter analyze
dart format --output=none --set-exit-if-changed lib test
flutter test
```

A suíte tem cerca de 750 testes, em `test/` espelhando `lib/`, com fixtures reais do CLI em `test/fixtures/`.

Os testes de **integração** (`test/integration/`) chamam o Claude Code CLI de verdade e gastam alguns centavos (modelo `haiku`, orçamento baixo). Por isso ficam pulados no `flutter test` padrão (tag `integration` em `dart_test.yaml`):

```bash
flutter test --run-skipped -t integration test/integration
```

## Build e pacotes

```bash
flutter build linux --release
scripts/package.sh 0.3.0          # .deb e .tar.gz em dist/
```

Instalação local a partir do código: [Instalação](instalacao.md#a-partir-do-código).

## CI e release

- `.github/workflows/ci.yml`: `flutter analyze` e `flutter test` em todo PR e push na `main`.
- `.github/workflows/release.yml`: ao publicar uma release com tag `vX.Y.Z`, roda analyze e testes, compila com a versão da tag, empacota com `scripts/package.sh` e anexa `.deb` e `.tar.gz` (e um `.zip` do Windows, experimental). As notas saem do `git cliff`.
- `.github/workflows/windows.yml`: build manual do Windows. O repositório não tem a pasta `windows/`; o build a cria com `flutter create --platforms=windows`. Não há suporte oficial a Windows nem macOS.

Para publicar: no GitHub, **Releases → Draft a new release**, crie a tag `vX.Y.Z` na `main` e publique.

## Estrutura

```
lib/
  main.dart, app.dart       janela, bandeja e encerramento (para processos claude/PTY ao fechar)
  core/
    claude/                 eventos stream-json, processo, argumentos, uso, execuções somente leitura,
                            settings por execução (plugins/MCP desligados)
    codex/                  integração Codex (desligada)
    providers/              AgentProvider, Claude Code, ACP, registro e preferências
    git/                    worktrees, diff, merge
    process/, fs/           comandos curtos, arquivos
    update/                 verificação e instalação de versões
    config/                 informações do app
    tray_service.dart       ícone na bandeja
  data/
    db/                     drift: tabelas, enums, migrações, código gerado
    repos/                  repositórios por agregado
    providers.dart          providers Riverpod do banco e dos repos
  features/                 home, project, specs, board, tasks, sessions, review, code, prompt,
                            agents, skills, mcp, settings, splash
  ui/
    theme/                  tokens de cor e tipografia
    shell/                  barra de título, barra lateral, rodapé, paleta, atalhos, notificações
    widgets/                componentes (editor de código, ícones, SVG…)
test/                       espelha lib/; fixtures/, generated_migrations/, integration/
drift_schemas/              dumps do schema por versão
scripts/                    install.sh, uninstall.sh, package.sh
linux/                      runner GTK, .desktop, flatpak/
docs/                       guia, specs, planos, pesquisa, mockups
```
