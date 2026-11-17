---
id: SPEC-086
status: aprovada
versão: 0.19.0
tipo: melhoria
depende-de: SPEC-076
issue: 276
---

# Notificação com o robô

## Objetivo

Com o Autopilot e várias sessões rodando, a pessoa deixa o Promptorium atrás do editor ou minimizado na bandeja e vai fazer outra coisa. Quando um agente para e espera por ela (uma aprovação, uma pergunta, um plano pronto), o app manda uma notificação do sistema genérica: "Aprovação pendente · SPEC-031 · Pagamento: Bash flutter test". Ela não diz qual agente pediu. Cinco pedidos viram cinco balões iguais. E, no Linux, **clicar não faz nada**.

Este último ponto é um defeito, não falta de recurso. O `local_notifier` 0.1.6 cria a notificação com `notify_notification_new(title, body, 0)`, sem ícone e sem imagem, e registra só os botões de ação. A ação `default` (o clique no corpo) não é registrada, então o `onClick` do `LocalAppNotifier` nunca é chamado no Linux, e o `windowManager.focus()` dentro dele também não.

Exemplo: às 15:20, com o Promptorium minimizado, o agente da SPEC-031 (o robô Ada, laranja, redondo) pede para rodar `flutter test`. No mesmo minuto, o agente da SPEC-033 (Bruno) tem um plano pronto, e o da SPEC-034 (Caio) faz uma pergunta. Chegam três notificações quase iguais. A pessoa clica na primeira, nada acontece, e ela precisa achar a janela, trocar de workspace e procurar a sessão.

Esta spec:
- troca a notificação do Linux por uma **feita direto no DBus** (`org.freedesktop.Notifications`), com imagem, clique e ações que funcionam;
- quando um agente **precisa de você** e a janela está em segundo plano, a notificação mostra **o robô daquele agente acenando** (SPEC-076), como imagem estática, e o nome dele no título;
- o **clique traz o app para a frente e abre direto no pedido**: o workspace certo, a tela certa, o cartão do pedido em foco;
- tem **regras contra spam**: uma notificação por agente, que se atualiza; um resumo quando vários pedem juntos; nada com a janela em foco; e a notificação some quando o pedido é respondido.

Issue: [#276](https://github.com/mayroncachina/promptorium/issues/276) (sub-issue de [#268](https://github.com/mayroncachina/promptorium/issues/268))

Mockup: [canvas do Claude Design](https://claude.ai/artifact/TT6sHU1TBgjjn1B8vF5uGe). Capturas em `docs/mockups/spec-086/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-notificacao.png` | A área de trabalho com o app atrás: a notificação com o robô acenando, a mesma notificação atualizada com "2 pedidos" e o resumo de três agentes | R1–R5, R9, R10, R16 |
| `2-abre-no-pedido.png` | Depois do clique: o app na frente, no workspace e na sessão certos, com o cartão de aprovação em foco | R6–R8 |
| `3-contra-spam.png` | A linha do tempo das regras contra spam: espera, troca, resumo, fechar ao responder e o lembrete | R9–R14 |
| `4-configuracoes.png` | Configurações › Notificações, com a prévia e "Testar notificação" | R15 |

## Requisitos

### Quando notifica

- R1 · **"Precisa de você".** A notificação com o robô sai quando um agente entra num estado que precisa da pessoa, o mesmo "precisa de você" da Atividades (SPEC-076 R2):
  - aprovação pendente (`can_use_tool`) de uma sessão ou de uma conversa do Prompt ou da VIBE;
  - pergunta do agente (`AskUserQuestion`);
  - plano pronto;
  - etapa de spec parada em "precisa de resposta" (`needs_input`);
  - segredo encontrado (SPEC-085), quando ela existir.
  
  As outras notificações (sessão concluída, sessão falhou, release, PR, Autopilot, revisor automático) continuam sem robô, como hoje, com o ícone do app. Elas passam pelo mesmo transporte (R4), e o clique delas passa a funcionar.
- R2 · **Só em segundo plano.** A notificação do sistema sai só quando a janela não está em primeiro plano: minimizada, escondida na bandeja, sem foco (outra janela na frente) ou em outra área de trabalho. Com a janela em foco, vale só o aviso que já existe dentro do app (o cartão flutuante de aprovação e os selos). Se a janela ganha foco com notificações abertas, o app as fecha (R12).

### O robô na notificação

- R3 · **A imagem.** A imagem é o robô do agente (`RobotIdentity.of(seed)`, com a semente da SPEC-076 R5) na pose `wave`, num quadro fixo com o braço levantado, sem animação. Ele é desenhado pelo mesmo `RobotPainter`, a 128 × 128 px, sobre fundo transparente e com o anel âmbar de "precisa de você". O título leva o nome do robô e o pedido: "Ada precisa de você". O corpo diz o que é e onde, em até duas linhas: "SPEC-031 · Pagamento com Stripe — quer executar `flutter test`". A imagem é só decoração: o texto diz tudo sem ela (R16).
- R4 · **Transporte: DBus direto.** O app fala com `org.freedesktop.Notifications` pelo pacote `dbus` (Dart puro, que já está no `pubspec.lock` como dependência transitiva e passa a ser direta):
  - `Notify` com `app_name` "Promptorium", `app_icon` `dev.promptorium.promptorium`;
  - as dicas `image-data` (os pixels RGBA do robô, R3), `desktop-entry` `dev.promptorium.promptorium`, `urgency` 1 (normal) e `category` `im.received`;
  - as ações `default` (o clique) e `abrir` (R7);
  - `replaces_id` para atualizar (R10).
  
  O app escuta `ActionInvoked`, `ActivationToken` e `NotificationClosed`. A imagem vai em `image-data`, e não num arquivo (`image-path`), porque no Flatpak o servidor de notificações não lê os arquivos do app. Assim também não sobram arquivos temporários. O `local_notifier` sai do projeto.
- R5 · **Servidores diferentes.** No começo, o app lê `GetCapabilities` uma vez:
  - sem `actions`: a notificação sai sem botão, e o corpo termina com "Abra o Promptorium para responder";
  - sem `body-images` e sem suporte a `image-data` (alguns servidores mínimos): a notificação sai com o ícone do app;
  - sem servidor de notificações (sem DBus de sessão): nada sai, o app registra uma vez "notificações do sistema indisponíveis" e o ícone da bandeja (SPEC-041) continua contando os pedidos.
  
  O GNOME (Shell), o KDE (Plasma), o `dunst` e o `mako` estão na lista de teste manual.

### O clique

- R6 · **Trazer para a frente.** O clique (ação `default`) traz a janela de volta: tira da bandeja ou do minimizado, põe na frente e dá o foco. No Wayland, o foco depende do token de ativação: o app guarda o token do sinal `ActivationToken` e o passa à janela por um canal nativo novo no `my_application.cc`, com `gtk_window_set_startup_id(token)` e `gtk_window_present`. No X11, usa `gtk_window_present_with_time` com o tempo do evento. Sem token, cai no `windowManager.show()` e `focus()` de hoje.
- R7 · **Direto no pedido.** Depois de trazer a janela, o app abre o pedido:
  1. troca o workspace ativo se o agente for de outro;
  2. abre a tela do pedido: Sessões para uma sessão ou etapa, Prompt para uma conversa ou VIBE, e o painel da etapa no Quadro para `needs_input`;
  3. seleciona a sessão ou a conversa e rola até o cartão do pedido (aprovação, pergunta, plano ou segredo);
  4. põe o foco do teclado no botão principal do cartão (Aprovar, Responder, Ver plano) e o destaca com um anel âmbar por 1,5 s.
  
  O leitor de tela anuncia "Ada, SPEC-031: quer executar flutter test". Se o pedido já foi respondido (pelo app ou por outra regra), o app abre a sessão e mostra o aviso "Esse pedido já foi respondido". O botão **Abrir** faz o mesmo que o clique.
- R8 · **Sem aprovar pela notificação.** A notificação **não** tem "Aprovar" nem "Negar" (P1). Para aprovar, a pessoa precisa ver o comando inteiro, o diff e o contexto, e a notificação corta o texto. No GNOME, as ações ainda ficam escondidas atrás de uma seta. O único botão é **Abrir**.

### Contra spam

- R9 · **Uma por agente.** Cada agente (semente) tem no máximo uma notificação aberta. Um pedido novo do mesmo agente **atualiza** a que já existe (`replaces_id`), em vez de criar outra: "Ada precisa de você · 2 pedidos", com o mais recente no corpo. O clique vai para o mais antigo ainda pendente.
- R10 · **Resumo quando vários pedem juntos.** Se três ou mais agentes passam a precisar de você em até 15 s, sai **uma** notificação de resumo: "3 agentes precisam de você", com até três robôs lado a lado na imagem (e "+2" se houver mais) e os nomes no corpo ("Ada, Bruno e Caio"). As notificações individuais desses agentes não saem. O clique abre a Atividades na aba "Precisa de você" (SPEC-076 R17).
- R11 · **Espera curta.** O app espera 3 s antes de mostrar a notificação. Se o pedido for respondido nesse tempo (uma regra "Sempre permitir", outra janela, o Autopilot), nada sai. Isso evita notificações que piscam e somem.
- R12 · **Some quando não serve mais.** O app fecha a notificação (`CloseNotification`) quando o pedido é respondido, quando a sessão para ou quando a janela ganha foco. Notificação velha não fica na central do sistema apontando para um pedido que não existe mais.
- R13 · **Um lembrete só.** Se o pedido continua pendente 15 min depois e a janela segue em segundo plano, o app mostra a notificação de novo, uma única vez, com "ainda esperando · há 15 min". Depois disso, não insiste.
- R14 · **Respeita o sistema.** O "Não perturbe" do sistema vale, porque quem decide é o servidor de notificações. O app nunca usa urgência `critical`.

### Configurações e acessibilidade

- R15 · **Configurações › Notificações** (seção nova, que também recebe as preferências de notificação que já existem):
  - "Avisar quando um agente precisa de você" (ligado);
  - "Mostrar o robô do agente" (ligado; desligado, sai o ícone do app);
  - "Lembrar uma vez depois de 15 min" (ligado);
  - "Avisar também quando uma sessão termina ou falha" (ligado, como hoje);
  - uma prévia da notificação com o robô de um agente aberto, e o botão **"Testar notificação"**, que manda uma notificação de verdade e conta se o clique voltou ("Clique recebido: tudo certo").
  
  Tudo fica em `app_settings`.
- R16 · **Acessível.** O título e o corpo dizem tudo: quem (nome do robô), o quê (o pedido) e onde (spec ou sessão). A imagem não carrega informação que o texto não tenha. O texto não leva marcação HTML (alguns servidores não aceitam), só texto puro, e no máximo 120 caracteres no corpo. Um segredo da SPEC-085 aparece só mascarado.

## Fora do escopo

- Aprovar, negar ou responder pela notificação (P1).
- Robô animado na notificação. Os servidores do Linux não animam `image-data`, e um GIF seria só a primeira imagem.
- Notificações no macOS e no Windows (o app é só Linux).
- Som próprio e horários de silêncio do app (o "Não perturbe" do sistema já cobre).
- Robôs nas outras notificações (concluída, falhou, release, PR).
- Notificação no celular ou por e-mail.

## Design

Canvas para validar: [Notificação com o robô](https://claude.ai/artifact/TT6sHU1TBgjjn1B8vF5uGe). Ele tem quatro artboards: a notificação na área de trabalho, o app aberto no pedido, as regras contra spam e as configurações.

### O que já existe

- `lib/features/sessions/app_notifier.dart`: `AppNotifier`, `LocalAppNotifier` (`local_notifier` 0.1.6) e `appNotifierProvider`. No Linux, `onClick` nunca é chamado (o plugin não registra a ação `default`).
- `lib/main.dart`: `localNotifier.setup(appName: 'Promptorium')`.
- `lib/features/sessions/session_manager.dart`: `_notify` (grava em `notifications` e chama o `AppNotifier`), com as chamadas em `PermissionRequest` ("Aprovação pendente") e em `Result` ("Sessão concluída" / "falhou"). Também `_origins` e `selectedSessionProvider`.
- `lib/features/prompt/conversation_manager.dart`: aprovações e "plano pronto" das conversas do Prompt e das VIBEs.
- `lib/features/home/home_inbox.dart`: `InboxKind` e `InboxItem`, os pedidos de cada workspace. `lib/features/activities/activity.dart`: `Activity.needsYou`, `seed`, `specSeed`.
- `lib/features/activities/widgets/robot_avatar.dart`: `RobotIdentity.of(seed)` (forma, cor, nome), `RobotPainter` e `ActivityPose.wave`.
- `lib/core/tray_service.dart` e `lib/features/home/tray_radar.dart`: a bandeja e o radar dos pedidos (SPEC-020, SPEC-041).
- `linux/runner/my_application.cc`: a janela GTK. `linux/flatpak/dev.promptorium.promptorium.yml` já tem `--talk-name=org.freedesktop.Notifications`.
- Outras chamadas do `appNotifierProvider`: `autopilot.dart`, `spec_runner.dart`, `release_dispatcher.dart`, `pr_babysitter.dart`, `auto_reviewer.dart` e `conflict_resolution.dart`.

### Componentes

- **`lib/core/system/desktop_notifications.dart`**: `DesktopNotifications`, o cliente DBus (`Notify`, `CloseNotification`, `GetCapabilities` e os sinais). Os métodos são `show(DesktopNotification)` → id, `close(id)` e o fluxo `events` (ação, token, fechada) (R4, R5).
- **`AppNotifier`** ganha `show(..., {image, replaces, actions})` → id e `close(id)`. A implementação nova é `DbusAppNotifier`, que substitui o `LocalAppNotifier`. As chamadas que existem continuam funcionando sem mudança (R1).
- **`lib/features/activities/widgets/robot_snapshot.dart`**: `robotSnapshot(seed, pose: wave, size: 128)` → RGBA, com cache por semente, e `robotGroupSnapshot(seeds)` para o resumo (R3, R10).
- **`lib/features/notifications/agent_alerts.dart`**: `AgentAlerts` (Notifier), que observa o `activitiesProvider` e as janelas. O plano é uma **função pura**, `planAlerts(previous, pending, now, windowActive, settings)`, que devolve as ações (mostrar, atualizar, resumir, fechar, lembrar) segundo R2 e R9–R13.
- **`lib/features/notifications/alert_target.dart`**: `AlertTarget` (workspace, sessão ou conversa, id do pedido, tipo) e `openAlertTarget(ref, target)`, que troca o workspace, navega, seleciona, rola e dá o foco (R7).
- **`lib/core/system/window_activation.dart`** e o canal `promptorium/window` no `my_application.cc`: `present(token)` (R6).
- `session_manager.dart`: o `_notify` de aprovação passa a ser do `AgentAlerts` (o de concluída e falhou continua). Os cartões de aprovação, pergunta e plano ganham uma `GlobalKey` e `focusRequest` para o R7.
- Configurações: a seção **"Notificações"** em `settings_sections.dart` (R15).
- `pubspec.yaml`: `dbus` passa a dependência direta, e o `local_notifier` sai. `main.dart`: sai o `localNotifier.setup`.

### Migração

**Sem migração.** O alvo de cada notificação (`AlertTarget`) fica em memória, enquanto ela está aberta. A tabela `notifications` (a central do sino) continua como está. As preferências ficam em `app_settings`.

### Testes

- `planAlerts`: um pedido com a janela em segundo plano gera "mostrar" depois de 3 s. Respondido antes de 3 s, nada sai. Janela em foco, nada sai. Segundo pedido do mesmo agente gera "atualizar" (2 pedidos). Três agentes em 15 s geram "resumir". Pedido respondido gera "fechar", e a janela focada fecha tudo. O lembrete sai uma vez aos 15 min e nunca mais.
- `DesktopNotifications` (servidor DBus falso em teste): `Notify` com `image-data` 128 × 128, `desktop-entry` e ações. `ActionInvoked` `default` chama o alvo. Sem `actions` no `GetCapabilities`, sai sem botão e com o texto do R5. Sem servidor, nada quebra.
- `robotSnapshot`: a mesma semente dá os mesmos pixels. A pose `wave` tem o braço levantado. O resumo tem até três robôs.
- `openAlertTarget`: troca de workspace, abre Sessões ou Prompt, seleciona e dá foco ao botão Aprovar. Pedido já respondido mostra o aviso.
- Regressão: o clique de "Sessão concluída" vai à tela de origem (hoje não funciona no Linux).

## Critérios de aceite

- [ ] Um pedido de agente com a janela em segundo plano gera uma notificação com o robô acenando e o nome dele, e com a janela em foco não gera [R1–R3] verificar: flutter test test/features/notifications/agent_alerts_test.dart
- [ ] A notificação sai pelo DBus com `image-data`, `desktop-entry` e a ação `default`, e se adapta a servidores sem ações ou sem servidor [R4, R5] verificar: flutter test test/core/system/desktop_notifications_test.dart
- [ ] O clique traz a janela e abre o pedido no workspace, na tela e no cartão certos, com o foco no botão principal [R6, R7] verificar: flutter test test/features/notifications/alert_target_test.dart
- [ ] Uma notificação por agente, atualizada; resumo com três ou mais; espera de 3 s; fecha ao responder; um lembrete só [R9–R13] verificar: flutter test test/features/notifications/agent_alerts_test.dart
- [ ] O robô da notificação é o mesmo da Atividades e do Quadro para a mesma semente [R3] verificar: flutter test test/features/activities/robot_snapshot_test.dart
- [ ] No app, com a janela minimizada, um pedido real mostra a notificação com o robô no GNOME (Wayland) e no KDE ou `dunst`, e o clique abre o cartão de aprovação com o foco no Aprovar [R1–R8] verificar: manual (app isolado com `XDG_DATA_HOME`, prints em `docs/mockups/spec-086/app/`)
- [ ] O projeto compila e a análise estática passa [R1–R16] verificar: flutter analyze

## Decisões

- P1 · **Ações na notificação (Aprovar, Abrir).** **Decidido:** **só "Abrir"** (mais o clique). Aprovar às cegas, sem ver o comando inteiro, o diff e o contexto, anula o motivo de existir a aprovação. Com o Autopilot, seria fácil aprovar o pedido errado de outro agente. Se pedirem depois, um "Aprovar" pode entrar só para ferramentas de leitura (Read, Grep, Glob), atrás de uma opção desligada por padrão.
- P2 · **Como evitar spam.** **Decidido:** as cinco regras juntas (R9–R13): uma por agente com `replaces_id`, resumo com três ou mais em 15 s, espera de 3 s, fechar quando não serve mais e um único lembrete aos 15 min. Nenhuma depende de configuração para funcionar bem. O limite de "três" para o resumo deixa dois pedidos ainda individuais, com o robô de cada um.
- P3 · **Biblioteca: `local_notifier` ou DBus direto.** **Decidido:** **DBus direto** com o pacote `dbus`. O `local_notifier` 0.1.6 não manda imagem, não registra o clique (`default`) no Linux, não tem `replaces_id` nem token de ativação, e trocar o plugin C++ dele daria mais trabalho que falar o protocolo, que é pequeno e estável (Desktop Notifications Specification 1.2).
- P4 · **Imagem: `image-data` ou arquivo.** **Decidido:** **`image-data`** (pixels na própria mensagem). Funciona no Flatpak, onde o servidor não enxerga os arquivos do app, e não deixa arquivos temporários. Custa cerca de 64 KB por notificação a 128 × 128, o que é irrelevante.
- P5 · **Quais notificações levam o robô.** **Decidido:** **só as de "precisa de você"**, com o robô acenando, que é o único estado que acena (SPEC-076 R10). Robô também em "concluída" e "falhou" diluiria o sinal: o aceno passaria a ser ruído.
- P6 · **Foco no Wayland.** **Decidido:** usar o **token de ativação** (`ActivationToken`, `xdg-activation`). Sem ele, o GNOME no Wayland só pisca o ícone na barra e não traz a janela, e o "abrir direto no pedido" falharia justamente na sessão padrão do Ubuntu.
