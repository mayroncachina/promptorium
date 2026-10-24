---
id: SPEC-020
status: rascunho
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

<!-- Como implementar: componentes, arquivos e decisões. Use "Gerar design". -->

## Critérios de aceite

- [ ] [R1] Ao abrir o app no Linux, o ícone do Promptorium aparece na bandeja com o tooltip "Promptorium" (verificação manual).
- [ ] [R2] Com a janela escondida ou minimizada, clicar no ícone mostra a janela com foco (verificação manual).
- [ ] [R3] Com a janela visível e em foco, clicar no ícone a esconde (verificação manual).
- [ ] [R4] O menu do ícone tem "Abrir" e "Sair", e "Abrir" traz a janela de volta (verificação manual).
- [ ] [R5] Com uma sessão em execução, esconder a janela pelo ícone e reabri-la mantém a sessão rodando e o `claude` vivo (verificação manual: `pgrep -a claude` antes e depois).
- [ ] [R6] "Sair" encerra o app sem processos `claude` restantes (verificação manual: `pgrep -a claude` vazio).
- [ ] [R7] Sem a biblioteca de bandeja, o app inicia, mostra o aviso no log e não exibe o ícone. verificar: `flutter test test/core/tray_service_test.dart`
- [ ] [R8] A lógica do ícone só é ativada no Linux. verificar: `flutter test test/core/tray_service_test.dart`
- [ ] [R1–R8] O projeto compila e a análise estática passa. verificar: `flutter analyze`

## Perguntas em aberto

- O botão de fechar da janela deve esconder o app na bandeja (mantendo as sessões) ou continuar encerrando, como hoje? Isso muda R5 e R6.
- O app deve poder iniciar já escondido na bandeja?
- No GNOME a bandeja só aparece com a extensão AppIndicator. Basta o fallback de R7 ou o app deve avisar o usuário?
- O Flatpak precisa da permissão de StatusNotifier (`--talk-name=org.kde.StatusNotifierWatcher`) e da `libayatana-appindicator3` no runtime. Já está disponível no manifesto?
- O ícone deve ter variante monocromática para temas escuros e claros?
