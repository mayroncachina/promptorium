---
id: SPEC-020
status: aprovada
---

# Ícone na bandeja do sistema (Linux)

## Objetivo

Adicionar ao Promptorium, no Linux, um ícone na bandeja do sistema (*tray icon*) para abrir e esconder o app rapidamente, sem passar pela barra de tarefas nem pelo botão de fechar. Hoje a janela só some ao ser fechada, o que encerra as sessões do Claude Code.

Nesta primeira versão o ícone faz só isso: clicar mostra a janela (ou a esconde se já estiver em foco) e um menu mínimo oferece "Abrir" e "Sair". Ações adicionais (status das sessões, atalhos, notificações) ficam para specs futuras.

- Fora do escopo: macOS e Windows, novas ações no menu, badge ou contador no ícone, iniciar com o sistema.
- O pacote `tray_manager` já está no `pubspec.yaml`, mas ainda não é usado em `lib/`.

## Requisitos

- R1 · Quando o app iniciar no Linux, o sistema deve exibir na bandeja um ícone do Promptorium (`assets/icon`) com o tooltip "Promptorium".
- R2 · Quando o usuário clicar no ícone da bandeja com a janela escondida ou minimizada, o sistema deve mostrar a janela, restaurá-la e dar foco a ela.
- R3 · Quando o usuário clicar no ícone da bandeja com a janela visível e em foco, o sistema deve esconder a janela.
- R4 · O sistema deve oferecer, no menu do ícone, os itens "Abrir" (mesmo efeito de R2) e "Sair", para os desktops em que o clique simples não é entregue.
- R5 · Enquanto a janela estiver escondida pelo ícone, o sistema deve manter as sessões, os terminais e os agendamentos em andamento, sem encerrar nenhum processo `claude`.
- R6 · Quando o usuário escolher "Sair" no menu, o sistema deve encerrar o app pelo mesmo caminho do fechamento da janela (parar sessões, PTYs e conversas, depois destruir a janela), sem deixar processos órfãos.
- R7 · Se a bandeja não estiver disponível (biblioteca ausente ou desktop sem suporte), o sistema deve registrar o aviso no log e continuar funcionando normalmente, sem ícone e sem travar a inicialização.
- R8 · Fora do Linux, o sistema não deve criar o ícone nem mudar o comportamento atual.

## Design

### O que já existe
- `lib/main.dart`: `windowManager` (window_manager 0.5.2) com `setPreventClose(true)` e o `_CloseHandler`, que no `onWindowClose` mata os PTYs (`sessionTerminalsProvider`, `worktreeTerminalsProvider`), para as sessões e as conversas (`shutdown()`, até 4 s) e chama `windowManager.destroy()`.
- `tray_manager` 0.8.0 no `pubspec.yaml`. A 0.8 é construída sobre o `nativeapi` (FFI, biblioteca `libcnativeapi.so` compilada pelo *build hook* do `cnativeapi`): no Linux o ícone é um StatusNotifierItem publicado direto no D-Bus, **sem** `libayatana-appindicator3`. O build precisa de GTK 3, X11 e Xi (`libgtk-3-dev`, `libx11-dev`, `libxi-dev`).

### Componentes
- `lib/core/tray_service.dart` — `TrayService`, sem dependência nativa, testável:
  - recebe `isLinux`, uma fábrica de `TrayBackend`, uma `TrayWindow` e `onQuit` (e um `log`, `debugPrint` por padrão);
  - `start()`: fora do Linux não chama a fábrica (R8); no Linux cria o ícone (`assets/icon/icon-64.png`, tooltip "Promptorium", menu "Abrir" e "Sair") (R1, R4). Qualquer exceção da fábrica ou do backend vira um aviso "bandeja indisponível, seguindo sem o ícone" no log e `false`; nunca lança (R7);
  - `toggle()` (clique no ícone): visível, não minimizada e em foco → `hide()` (R3); senão `show()`, `restore()` se minimizada, `focus()` (R2). Esconder não toca em sessões nem processos (R5);
  - `open()` ("Abrir"): sempre traz a janela para a frente (R2, R4);
  - `quit()` ("Sair"): remove o ícone e chama `onQuit` uma única vez (R6).
- `lib/core/tray_backend_native.dart`:
  - `NativeTrayBackend`: API nativa do `tray_manager` (`TrayIcon.create()`, `ImageAsset.fromAsset`, `setTooltip`, `Menu`/`MenuItem` com `MenuItemClickedEvent`). `setContextMenuTrigger(rightClicked)` expõe o menu ao painel; `TrayIconClickedEvent` (clique no KDE) e `TrayIconDoubleClickedEvent` (o GNOME/AppIndicator só chama `Activate` no duplo clique; o clique simples abre o menu) chamam `toggle`. Lança se `TrayManager.isSupported()` for falso (sem barramento de sessão) ou se o ícone/menu não puder ser criado;
  - `WindowManagerTrayWindow`: `TrayWindow` sobre o `windowManager`.
- `lib/main.dart`: o `_CloseHandler` ganhou `close()` público, usado pelo `onWindowClose` e pelo `onQuit` do `TrayService` — "Sair" é exatamente o mesmo caminho do botão de fechar (R6). O `TrayService` fica numa variável de topo durante toda a vida do app (um wrapper coletado remove o ícone).

### Empacotamento
- `.deb` (`scripts/package.sh`): `Depends` ganhou `libx11-6` e `libxi6`, ligadas diretamente pela `libcnativeapi.so` (o GTK já as puxa; ficam explícitas). Nada de AppIndicator.
- CI (`.github/actions/build-deb/action.yml`) e README: `libayatana-appindicator3-dev` trocada por `libx11-dev libxi-dev`.
- Flatpak (`linux/flatpak/dev.promptorium.promptorium.yml`): já tinha `--talk-name=org.kde.StatusNotifierWatcher`; GTK 3/X11/Xi estão no `org.freedesktop.Platform` 24.08, então não há módulo extra (anotado em `docs/flatpak.md`).
- CMake/runner Linux: sem mudança — a biblioteca nativa entra pelo *build hook* (native assets) em `bundle/lib/libcnativeapi.so`.

### Testes
`test/core/tray_service_test.dart` com backend e janela falsos: ícone/tooltip/menu (R1, R4), falha do backend ou da fábrica → aviso sem exceção (R7), nada criado fora do Linux (R8), lógica do clique (R2, R3), "Abrir" e "Sair" (R4, R6).

## Decisões

- O botão de fechar da janela continua encerrando o app, como hoje. Esconder só pelo ícone da bandeja.
- O app não inicia escondido.
- GNOME sem a extensão AppIndicator: basta o fallback de R7 (aviso no log, sem ícone, sem travar); não há aviso ao usuário.
- Flatpak: a permissão `--talk-name=org.kde.StatusNotifierWatcher` já estava no manifesto; o `tray_manager` 0.8 não usa `libayatana-appindicator3`, então o runtime não precisa dela.
- Ícone: o do app (`assets/icon/icon-64.png`); sem variante monocromática nesta versão.

## Critérios de aceite

- [ ] [R1] Ao abrir o app no Linux, o ícone do Promptorium aparece na bandeja com o tooltip "Promptorium" (verificação manual). verificar: flutter test test/core/tray_service_test.dart
- [ ] [R2] Com a janela escondida ou minimizada, clicar no ícone mostra a janela com foco (verificação manual). verificar: flutter test test/core/tray_service_test.dart
- [ ] [R3] Com a janela visível e em foco, clicar no ícone a esconde (verificação manual). verificar: flutter test test/core/tray_service_test.dart
- [ ] [R4] O menu do ícone tem "Abrir" e "Sair", e "Abrir" traz a janela de volta (verificação manual). verificar: flutter test test/core/tray_service_test.dart
- [ ] [R5] Com uma sessão em execução, esconder a janela pelo ícone e reabri-la mantém a sessão rodando e o `claude` vivo (verificação manual: `pgrep -a claude` antes e depois). verificar: manual (pgrep -a claude antes e depois de esconder e reabrir a janela)
- [ ] [R6] "Sair" encerra o app sem processos `claude` restantes (verificação manual: `pgrep -a claude` vazio). verificar: manual (pgrep -a claude vazio depois de Sair)
- [x] [R7] Sem a biblioteca de bandeja, o app inicia, mostra o aviso no log e não exibe o ícone. verificar: `flutter test test/core/tray_service_test.dart`
- [x] [R8] A lógica do ícone só é ativada no Linux. verificar: `flutter test test/core/tray_service_test.dart`
- [x] [R1–R8] O projeto compila e a análise estática passa. verificar: `flutter analyze`
