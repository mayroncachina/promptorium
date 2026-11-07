---
id: SPEC-041
status: aprovada
depende-de: SPEC-020, SPEC-029
---

# Radar na bandeja

## Objetivo

Hoje o ícone da bandeja só mostra ou esconde a janela. Com o app escondido, a pessoa não sabe se os agentes estão rodando, parados ou esperando uma decisão, e precisa abrir a janela para descobrir. As notificações ajudam na hora em que algo acontece, mas somem, e nada mostra o estado atual.

Esta spec transforma a bandeja em um radar: o ícone mostra o estado geral, o tooltip resume os números e o menu lista o que precisa de atenção, com um clique que leva direto ao item. É a continuação prevista na SPEC-020 ("status das sessões") e no DT-49 ("sessões aguardando no menu").

O radar só informa e leva até o lugar certo. Toda decisão continua sendo tomada na janela do app.

## Requisitos

- R1 · Enquanto o app estiver aberto no Linux com a bandeja ativa, o sistema deve mostrar no ícone um dos quatro estados abaixo, escolhendo o primeiro da lista que se aplicar:
  1. **Precisa de você** (selo âmbar): há item `approval` ou `needsAnswer` no inbox;
  2. **Problema** (selo vermelho): há item `prProblem` no inbox;
  3. **Trabalhando** (selo azul): há sessão com `busy` verdadeiro e sem aprovação pendente;
  4. **Parado** (a marca, sem selo): nenhum dos anteriores.
- R2 · Os três selos devem se distinguir pela forma, além da cor, para continuarem legíveis em 24 px e para quem não diferencia as cores: losango com exclamação (Precisa de você), quadrado com X (Problema) e círculo (Trabalhando). A marca com selo deve manter o contraste mínimo de 3:1 da SPEC-029 R1 contra painéis claros e escuros.
- R3 · O radar deve considerar todos os workspaces, não só o ativo, e não deve repetir um item que apareça em mais de um deles.
- R4 · O tooltip deve resumir o radar só com números: `Promptorium · 2 rodando · 3 precisam de você`, com `1 precisa de você` no singular. Sem nada para contar, deve ser `Promptorium`. Títulos de specs e sessões não entram no tooltip.
- R5 · O menu deve seguir esta ordem, omitindo as seções vazias:
  1. uma linha de resumo desabilitada, com o texto do tooltip sem o nome do app;
  2. a seção "Precisa de você", com todos os itens do inbox na ordem de urgência de `buildInbox`, até 6;
  3. a seção "Rodando", com as sessões do estado Trabalhando, até 3;
  4. "Abrir" e "Sair", com o comportamento da SPEC-020.
  - O que passar do limite vira uma última linha na seção ("Mais 4 em Início", "Mais 2 em Sessões"), que abre a tela correspondente no workspace do primeiro item oculto.
  - Cada rótulo é `ref · título`, cortado com `…` em 48 caracteres. Com itens de mais de um workspace no menu, o rótulo começa com o nome do workspace.
- R6 · Quando o usuário clicar em um item do menu, o sistema deve mostrar, restaurar e focar a janela, ativar o workspace do item e abrir o destino:

  | Item | Destino |
  |---|---|
  | `approval` de sessão | a sessão |
  | `approval` de conversa | a conversa, na tela Prompt |
  | `needsAnswer` | Início, onde está o botão Decidir |
  | `review`, `prProblem` | o item na tela Review |
  | `interrupted` | a sessão, sem retomá-la |
  | sessão em "Rodando" | a sessão |

  Se o item já não existir no momento do clique, o sistema deve abrir Início.
- R7 · O menu não deve executar nenhuma ação sobre o item: não aprova, não recusa, não decide e não retoma sessão.
- R8 · O radar deve refletir uma mudança de estado em até 2 segundos, com no máximo uma atualização nativa por segundo e nenhuma quando nada mudou. Isso vale com a janela escondida.
- R9 · Se a troca do ícone ou do menu falhar, o sistema deve registrar o aviso no log e manter o que estava na bandeja, sem travar o app e sem perder "Abrir" e "Sair". Sem bandeja (SPEC-020 R7) ou fora do Linux (R8), o radar não deve fazer nada.

## Design

### O que já existe

- `lib/core/tray_service.dart`: `TrayService` e a interface `TrayBackend`. Hoje `show()` recebe ícone, tooltip e menu uma única vez.
- `lib/core/tray_backend_native.dart`: monta o menu com `tray.Menu` e `tray.MenuItem`.
- `nativeapi` 0.5.10: `TrayIcon` tem `icon`, `setTooltip` e `setContextMenu`; `Menu` tem `clear`, `addItem` e `addSeparator`; `MenuItem` tem `label` e `isEnabled`.
- `lib/features/home/home_inbox.dart`: `buildInbox` é puro e já ordena por urgência. O `inboxProvider` cobre só o workspace ativo.
- `lib/features/home/home_screen.dart`: as ações de cada item estão em `_actions`, presas a `WidgetRef` e `BuildContext`. O Decidir usa `openStep`, que precisa de contexto, por isso o menu leva a Início nesse caso.
- `lib/features/board/board_screen.dart`: `openSessionIn(container, id)` já navega sem widget.
- `lib/main.dart`: o `ProviderContainer` e o `TrayService` são criados juntos, em `main`.

### Componentes

- `lib/features/home/home_inbox.dart`:
  - extrair o corpo do `inboxProvider` para `workspaceInboxProvider`, uma família por `workspaceId`;
  - o `inboxProvider` passa a delegar para a família, sem mudar o que a tela de Início e as badges mostram.
- `lib/core/tray_service.dart`:
  - `TrayState` (`attention`, `problem`, `working`, `idle`), com o asset de cada um;
  - `TrayStatus` (estado, tooltip e `TrayRow`s), um valor imutável com igualdade;
  - `TrayService.update(TrayStatus)`: compara com o último aplicado, limita a frequência (R8) e trata falhas (R9). Depois de uma falha, só tenta de novo na próxima mudança;
  - `TrayMenuEntry` passa a aceitar separador e item desabilitado;
  - `_` nos rótulos vira `__`, porque no DBusMenu o sublinhado sozinho marca um atalho e some.
- `TrayBackend` ganha `update({iconAsset, tooltip, menu})`. No `NativeTrayBackend`, o menu novo é montado e ligado com `setContextMenu` antes de liberar o anterior.
- `lib/features/home/tray_radar.dart` (novo):
  - `buildTrayRadar(...)`, função pura que recebe os inboxes e as sessões rodando de cada workspace e devolve o `TrayStatus` e o destino de cada item (R1, R3, R4, R5);
  - `trayRadarProvider`, que junta os dados de todos os workspaces. Os PRs observados são globais, então cada um conta só no workspace da sua sessão;
  - `openRadarItem(container, id)`, que troca o workspace por `workspaceActionsProvider` e navega (R6).
- `lib/main.dart`: `container.listen(trayRadarProvider, ...)` chama `_tray.update`, depois do `start()`. O `listen` mantém os providers `autoDispose` vivos com a janela escondida (R8).

### Ícones

- Novos arquivos `assets/icon/tray/tray-idle-24.png`, `tray-working-24.png`, `tray-problem-24.png` e `tray-attention-24.png`, gerados a partir de `assets/icon/mark/mark-small.svg`, com os vetores guardados na mesma pasta. Os desenhos propostos estão em `docs/mockups/spec-041/icones/`.
- O selo fica no canto inferior direito, com anel escuro `#14100A`, que o separa do frasco e de painéis claros. Um triângulo âmbar foi descartado: em 24 px ele se misturava ao contorno do frasco e borrava a exclamação.
- As cores são mais vivas que os tokens do app, para aparecerem em 24 px: `#FFD84D` (âmbar), `#F2564A` (vermelho) e `#8EC5FF` (azul).
- O estado Parado ganha `tray-idle-24.png`. Como o selo avança além da marca, os quatro ícones usam uma área de 26 unidades, e o frasco fica no mesmo tamanho e posição em todos, sem pular na troca de estado. `assets/icon/mark/mark-24.png` continua como ícone de reserva (SPEC-029 R6).
- `pubspec.yaml`: adicionar `assets/icon/tray/`, porque a declaração de pasta não inclui subpastas.

### Mockups

Canvas: [Promptorium · Radar na bandeja](https://claude.ai/artifact/6Arzm8c9fWkywTDqUSrhed). Capturas em `docs/mockups/spec-041/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-estados-do-icone.png` | Os 4 estados em 8× e em 24 px sobre preto, escuro, claro e cinza | R1, R2 |
| `2-menu-e-tooltip.png` | O menu aberto na barra e os textos do tooltip | R4, R5 |
| `3-variacoes-do-menu.png` | Menu vazio, só rodando, sem urgência e cheio com dois workspaces | R3, R5 |
| `4-destino-de-cada-clique.png` | O que cada item abre e o que não faz | R6, R7 |

### Testes

- `test/core/tray_service_test.dart`: `update`, frequência, igualdade e falhas, com o `_FakeBackend` estendido.
- `test/features/home/tray_radar_test.dart` (novo): prioridade dos estados, tooltip, limites, corte dos rótulos, vários workspaces e destinos de `openRadarItem`.

## Fora do escopo

- Ações rápidas no menu (nova spec, ditar, pausar agendamentos, não perturbe): ficam para uma spec própria.
- Fechar a janela para a bandeja: o botão de fechar continua encerrando o app, como decidido na SPEC-020.
- Aprovar ou decidir pelo menu.
- Número ou contador desenhado no ícone.
- Animação no ícone.
- Custo, tokens, lista de projetos e histórico.
- Conversas do Prompt em "Rodando" e no estado Trabalhando: ficam para uma próxima versão.
- Mudanças nas notificações existentes.
- macOS e Windows.

## Decisões

- **`review` e `interrupted` aparecem no menu, mas não mudam o ícone.** Um review pode ficar parado por dias e uma sessão interrompida aparece a cada reabertura do app. Com selo, o ícone ficaria sempre aceso e deixaria de avisar.
- **Precisa de você vem antes de Problema.** Um agente parado esperando resposta é o que dá para destravar agora. Um check quebrado pode ficar aberto por horas e esconderia novas aprovações.
- **"Trabalhando" usa `busy`, não `isAlive`.** Uma sessão ociosa mantém o processo vivo até o `closeIdle`, e não está trabalhando. Uma sessão esperando aprovação continua em `busy`, mas já aparece em "Precisa de você", por isso fica fora de "Rodando".
- **Todos os workspaces.** Um ícone Parado com um agente esperando em outro workspace seria uma informação errada.
- **Sessões apenas em "Rodando".** Conversas do Prompt não contam como Trabalhando nesta versão, mas as aprovações delas entram no inbox. Elas passam a contar em uma próxima versão, em spec própria.
- **Menu aberto.** Se o painel não atualizar um menu aberto, basta a mudança aparecer na próxima abertura. O ícone e o tooltip continuam seguindo o prazo de R8.

## Plano

1. **Sondagem** registrada em [docs/pesquisa/bandeja-dbus.md](../pesquisa/bandeja-dbus.md): feita no GNOME; falta o KDE e o menu aberto.
2. **Validar o mockup** (seção Mockups) antes de implementar.
3. `TrayBackend.update` e `TrayService.update`, com os testes.
4. `workspaceInboxProvider`, `tray_radar.dart` e a ligação em `main.dart`.
5. Ícones e verificação manual nos dois desktops.
6. Atualizar o guia, o `DT-49` e o CHANGELOG.

## Critérios de aceite

- [x] O ícone mostra o estado certo e respeita a prioridade quando há mais de um [R1] verificar: flutter test test/features/home/tray_radar_test.dart
- [x] `review` e `interrupted` sozinhos não mudam o ícone, mas aparecem no menu [R1, R5] verificar: flutter test test/features/home/tray_radar_test.dart
- [x] Uma sessão viva e ociosa não conta como Trabalhando [R1] verificar: flutter test test/features/home/tray_radar_test.dart
- [x] Os três selos são distinguíveis em 24 px e em escala de cinza, sobre painel claro e escuro [R2] verificar: manual (`docs/mockups/spec-041/`)
- [x] Um item de outro workspace muda o ícone e entra no menu, sem repetição [R3] verificar: flutter test test/features/home/tray_radar_test.dart
- [x] O tooltip mostra só números e volta a `Promptorium` sem nada para contar [R4] verificar: flutter test test/features/home/tray_radar_test.dart
- [x] O menu respeita a ordem, os limites, a linha "Mais N" e o corte em 48 caracteres [R5] verificar: flutter test test/features/home/tray_radar_test.dart
- [x] Cada tipo de item abre o destino da tabela, no workspace certo [R6] verificar: flutter test test/features/home/tray_radar_test.dart
- [x] Um item que já saiu do inbox abre Início [R6] verificar: flutter test test/features/home/tray_radar_test.dart
- [ ] Clicar em um item com a janela escondida traz a janela para a frente no destino [R6] verificar: manual (GNOME e KDE)
- [x] Clicar em um item não aprova, não decide e não retoma nada [R7] verificar: flutter test test/features/home/tray_radar_test.dart
- [x] Mudanças em sequência geram no máximo uma atualização por segundo, e um estado igual não gera nenhuma [R8] verificar: flutter test test/core/tray_service_test.dart
- [ ] Com a janela escondida, uma nova aprovação muda o ícone em até 2 segundos [R8] verificar: manual (GNOME e KDE)
- [x] Uma falha na troca mantém o ícone e o menu anteriores e registra o aviso [R9] verificar: flutter test test/core/tray_service_test.dart
- [x] Sem bandeja ou fora do Linux, `update` não chama o backend [R9] verificar: flutter test test/core/tray_service_test.dart
- [x] A tela de Início e as badges continuam iguais depois da extração do provider [R3] verificar: flutter test test/features/home
- [x] O projeto compila e a análise estática passa [R1–R9] verificar: flutter analyze
