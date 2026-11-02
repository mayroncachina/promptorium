---
id: SPEC-025
status: concluida
depende-de: SPEC-024
---

# Spec bloqueada durante ações

## Objetivo

Hoje as ações da aba Specs rodam com o editor liberado. "Gerar design" leva minutos: ele envia o texto da spec ao planner e, ao terminar, faz `c.text = text` (`specs_screen.dart:617`). Tudo o que a pessoa escreveu nesse intervalo é sobrescrito sem aviso.

Há um segundo risco: trocar de spec durante a geração. O resultado é aplicado ao `_controller` da tela, que àquela altura já pode ser o de outra spec. "Aprovar", "Clonar" e "Gerar telas da spec" também leem ou gravam a spec enquanto ela continua editável. O `_busy` atual só desabilita os botões; não protege o texto.

Esta spec faz duas coisas:

1. Bloqueia a alteração da spec enquanto uma ação estiver em andamento.
2. Mostra o carregamento na própria página: o que está rodando, há quanto tempo e como cancelar. Ao terminar, falhar ou ser cancelada, a ação devolve a spec liberada, com um aviso claro.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/HA2AxJBRLN6oS57YHrzhTu). Cópia dos artboards e capturas em `docs/mockups/spec-025/`:

- `1-gerando-design.png`: ação longa, com a faixa de status no editor e a spec somente leitura (R1–R5);
- `2-aprovando.png`: ação curta, só com o botão em andamento (R6);
- `3-trocar-de-spec.png`: confirmação ao sair durante a geração (R7);
- `4-falha.png`: aviso de erro e spec liberada (R8);
- `5-gerando-telas.png`: a mesma regra no modo Protótipo (R9).

## Requisitos

- R1 · Enquanto "Gerar design", "Aprovar", "Clonar para alterar", "Refinar com IA" (até abrir a conversa) ou "Gerar telas da spec" estiver em andamento, o sistema deve impedir qualquer alteração no texto da spec. O editor deve ficar somente leitura, e salvar, colar, desfazer e `Ctrl+S` não devem ter efeito.
- R2 · Enquanto a ação estiver em andamento, o botão que a disparou deve mostrar um indicador de progresso com o rótulo no gerúndio ("Gerando design…", "Aprovando…", "Gerando telas…"). As outras ações e o menu "Mais ações" devem ficar desabilitados.
- R3 · Enquanto uma ação longa ("Gerar design" ou "Gerar telas da spec") estiver em andamento, o sistema deve mostrar no topo do editor uma faixa de status (`role status`, anunciada a leitores de tela). A faixa deve trazer o que está rodando ("Gerando o design de SPEC-024…"), o motivo do bloqueio ("A spec fica somente leitura até terminar, para que nada do que você escrever seja sobrescrito."), o tempo decorrido e o botão "Cancelar geração" com o atalho Esc.
- R4 · Enquanto a spec estiver bloqueada, o texto deve continuar visível e legível, no estilo somente leitura (texto em `textSecondary` sobre `panel` e cursor de bloqueado), sem véu por cima. As abas Editar, Lado a lado, Visualizar e Protótipo devem continuar funcionando.
- R5 · Quando a pessoa acionar "Cancelar geração" ou Esc, o sistema deve interromper a execução do agente, liberar a spec sem alterar o texto e mostrar "Geração cancelada. A spec não foi alterada."
- R6 · Uma ação curta ("Aprovar", "Clonar", abrir a conversa de "Refinar") não deve mostrar a faixa de status. Basta o botão em andamento e, na linha das abas, "Somente leitura enquanto aprova" (ou o verbo da ação). O indicador só aparece se a ação passar de 300 ms, para não piscar.
- R7 · Quando a pessoa escolher outra spec na lista, ou outra seção do app, durante uma ação longa, o sistema deve perguntar "Sair da <código> durante a geração?". As opções são "Continuar aqui" (padrão, botão primário) e "Cancelar geração e abrir <destino>". Com o diálogo aberto, Esc fecha o diálogo e equivale a "Continuar aqui": não cancela a geração. O resultado de uma ação nunca deve ser aplicado a uma spec diferente da que a disparou.
- R8 · Quando a ação falhar, o sistema deve liberar a spec sem alterar o texto. Também deve mostrar, no topo do editor, um aviso (`role alert`) com a causa e "A spec não foi alterada e está liberada para edição.", mais os botões "Tentar de novo" e "Fechar aviso".
- R9 · No modo Protótipo, enquanto "Gerar telas da spec" estiver em andamento, o cartão "Gerando telas da spec…" (SPEC-022) deve mostrar o tempo decorrido e "Cancelar geração", e o editor deve seguir o R1 se a pessoa trocar de aba.
- R10 · Os botões desabilitados durante o bloqueio devem usar texto `#8A93A3` sobre `#1A1E26`, com borda `border`, em vez de reduzir a opacidade. Assim o contraste fica em 4,5:1 ou mais e o estado ainda é distinto.
- R11 · O indicador de progresso deve respeitar o "reduzir movimento" do sistema: sem rotação, só o ícone parado. A ordem do Tab deve continuar na ordem visual, e o foco vai para "Cancelar geração" quando a faixa aparece por ação do teclado.

## Fora do escopo

- Mudar o que cada ação produz (design, aprovação, clone, telas).
- Fila de ações ou mais de uma ação ao mesmo tempo na mesma spec.
- Bloquear a spec para outras janelas ou para edições feitas fora do app (por exemplo, no editor de texto).
- Progresso em porcentagem: o agente não informa quanto falta.
- Rodar ações em segundo plano enquanto a pessoa edita outra cópia da spec.

## Design

### O que já existe

- **Estado:** `_busy` em `_SpecsScreenState` (`specs_screen.dart:313`) é ligado em `_approve`, `_clone`, `_design` e `_refine`, e só serve para desabilitar os botões (`specs_screen.dart:834–860`).
- **Editor:** `readOnly: locked` em `specs_screen.dart:933`, onde `locked` vem do estágio da spec, não de uma ação em andamento.
- **Gerar design:** `SpecDesigner.generate` em `lib/features/specs/spec_design.dart:86` chama `runReadOnlyClaude`, que já aceita `Future<void>? cancelled` (`lib/core/claude/readonly_run.dart:68`). O `SpecDesigner` não repassa esse parâmetro.
- **Telas:** `_generateScreens` (`specs_screen.dart:662`) não usa `_busy`. Os jobs ficam em `prototypeJobsProvider` (SPEC-022).
- **Troca de spec:** `_select` (`specs_screen.dart:455`) só confirma quando há alteração não salva.
- **Cabeçalho:** `SpecHeader` da SPEC-024.

### R1–R2 · Estado da ação

- Novo `SpecActionState` (`lib/features/specs/spec_action.dart`): `{SpecAction kind, String specId, DateTime startedAt, Completer<void> cancel}`. Fica num `StateProvider` por workspace e substitui o `_busy`.
- `bool specLocked(spec) => spec.stage != backlog || action?.specId == spec.id`. O editor recebe `readOnly: specLocked`, e o atalho `Ctrl+S` e o salvar checam a mesma função.
- O `SpecHeader` recebe a ação atual. O botão dela vira `ProgressButton` (spinner de 14 px e o rótulo do R2); os demais recebem `onTap: null`.

### R3–R5 · Faixa de status e cancelamento

- `SpecActionBanner` (`lib/features/specs/widgets/spec_action_banner.dart`) fica acima do editor. Ele tem fundo `amberTint`, borda `approvalBorder`, spinner âmbar, título, texto e tempo (`Ticker` a cada segundo, `JetBrains Mono` com `tabular figures`), além do `SmallButton` "Cancelar geração" com `Kbd('Esc')`. Usa `Semantics(liveRegion: true)`.
- Somente leitura: o `CodeLineEditingController` mostra o texto com o estilo `textSecondary` e o fundo `panel`, e o `MouseRegion` usa `SystemMouseCursors.forbidden`.
- `SpecDesigner.generate(ws, text, {Future<void>? cancelled})` repassa o parâmetro ao `runReadOnlyClaude`. Ao cancelar, `generate` lança `SpecActionCancelled`, e a tela mostra o snack do R5.
- O Esc é um `Shortcuts` local ao editor enquanto a faixa existe; não é um atalho global.

### R6 · Ações curtas

- O `ProgressButton` só mostra o spinner depois de 300 ms (`Timer`). Antes disso, o botão fica desabilitado sem indicador.
- A linha das abas troca o `SaveState` da SPEC-024 por `LockedState('Somente leitura enquanto aprova')`.

### R7 · Troca de spec ou de seção

- `_select` e o `navigationProvider` passam a consultar `specActionProvider`. Com uma ação longa da spec atual em andamento, abrem `confirmLeaveDuringAction(context, code, destino)`, um `AlertDialog` cujo primário é "Continuar aqui".
- Ao aplicar o resultado, `_design` confere `action.specId == _loadedSpecId`. Se a spec for outra, descarta o resultado e registra o motivo no log.

### R8 · Falha

- `SpecActionError` (`role alert`, fundo `delBg` e borda `stopBorder`): ícone de alerta em `red`, título, causa (mensagem do erro, primeira linha), "Tentar de novo" (repete a ação com o texto atual) e o botão de fechar com o rótulo "Fechar aviso".

### R9 · Protótipo

- O cartão de geração em `PrototypeView` ganha o tempo decorrido e "Cancelar geração". `PrototypeService.generate` passa a aceitar `cancelled`, como o `SpecDesigner`.

### R10–R11 · Estados e acessibilidade

- Os estilos desabilitados entram como constantes `AppColors.disabledText = Color(0xFF8A93A3)` e `AppColors.disabledBg = surfaceRaised`.
- `MediaQuery.disableAnimations` troca o `CircularProgressIndicator` por um ícone parado.

## Critérios de aceite

- [x] Com "Gerar design" em andamento, digitar, colar e `Ctrl+S` não alteram o texto nem o arquivo [R1] verificar: flutter test test/features/specs/spec_action_lock_test.dart
- [x] Durante qualquer ação, o botão dela mostra o rótulo no gerúndio com spinner, e as demais ações e o menu ficam desabilitados [R2] verificar: flutter test test/features/specs/spec_action_lock_test.dart
- [x] A faixa de status aparece só nas ações longas, com título, motivo, tempo decorrido e "Cancelar geração" [R3] [R6] verificar: flutter test test/features/specs/spec_action_banner_test.dart
- [x] Com a spec bloqueada, as abas continuam trocando de modo e o texto continua visível, sem véu [R4] verificar: flutter test test/features/specs/spec_action_lock_test.dart
- [x] "Cancelar geração" e Esc completam o `cancelled` do `runReadOnlyClaude`, liberam a spec e mantêm o texto igual ao de antes [R5] verificar: flutter test test/features/specs/spec_design_test.dart test/features/specs/spec_action_lock_test.dart
- [x] Uma ação de menos de 300 ms não mostra spinner [R6] verificar: flutter test test/features/specs/spec_action_lock_test.dart
- [x] Escolher outra spec durante "Gerar design" abre a confirmação; "Continuar aqui" mantém a spec atual; a outra opção cancela e abre a escolhida [R7] verificar: flutter test test/features/specs/specs_screen_test.dart
- [x] O resultado de uma geração que termina depois da troca de spec não é aplicado à spec nova [R7] verificar: flutter test test/features/specs/spec_action_lock_test.dart
- [x] Uma falha mostra o aviso com a causa, libera a spec sem mudar o texto, e "Tentar de novo" repete a ação [R8] verificar: flutter test test/features/specs/spec_action_banner_test.dart
- [x] No modo Protótipo, o cartão de geração mostra o tempo e "Cancelar geração", e cancelar interrompe o agente [R9] verificar: flutter test test/features/specs/prototype_view_test.dart test/features/specs/prototype_service_test.dart
- [x] Os botões desabilitados têm contraste de 4,5:1 ou mais e não usam opacidade [R10] verificar: flutter test test/features/specs/spec_action_lock_test.dart
- [x] Com `disableAnimations`, o spinner fica parado; a faixa é anunciada como região viva; o Tab segue a ordem visual [R11] verificar: flutter test test/features/specs/spec_action_banner_test.dart
- [x] Os testes atuais de specs e do protótipo continuam passando [R1] [R2] [R9] verificar: flutter test test/features/specs
- [x] A análise estática passa sem avisos novos [R1] [R2] [R3] [R4] [R5] [R6] [R7] [R8] [R9] [R10] [R11] verificar: flutter analyze

## Decisões

- (Pergunta 1) "Refinar com IA" bloqueia a spec só até a conversa abrir (R1); o botão mostra "Abrindo conversa…".
- (Pergunta 2) O R10 da SPEC-024 já usa o estilo desta spec. Os desabilitados reaproveitam `AppColors.textDisabled` (`#8A93A3`) sobre `AppColors.surfaceRaised` (`#1A1E26`), com borda `border`. Não foram criadas as constantes `disabledText`/`disabledBg` do Design.
- O header já tinha uma classe `SpecAction` (os botões da SPEC-024). Por isso o tipo da ação em andamento se chama `SpecActionKind`, e o estado fica em `SpecActionState` + `specActionProvider` (`lib/features/specs/spec_action.dart`). É um `Notifier` único, não por workspace: o `specId` já identifica a spec.
- Em vez de um `ProgressButton` à parte, o `SpecActionButton` ganhou o estado `busy` (fundo `amberTint`, borda `approvalBorder`, rótulo no gerúndio). O `DelayedProgress` mostra o ícone da ação nos primeiros 300 ms e depois o spinner de 14 px (R6). O estado de bloqueio da linha das abas é o `SaveState` com `lockLabel`, em vez de um `LockedState` separado. Nas ações longas o texto fica em âmbar ("Bloqueada: gerando o design", "Bloqueada: gerando as telas"), como na captura 5.
- `role status` e `role alert` já são regiões vivas. O Flutter não aceita `liveRegion: true` junto com esses papéis, então a faixa e o aviso usam só o papel. O tempo decorrido fica fora do texto anunciado, para não ser lido a cada segundo.
- O cancelamento libera a spec na hora (`Future.any` com o `cancelled`), mesmo que o agente demore a parar. Uma resposta que chega depois é descartada. Ao cancelar "Gerar telas", o histórico do protótipo registra "Geração cancelada." e os arquivos que o agente alterou são restaurados.
- O re_editor só abre ou fecha a conexão de entrada de texto quando o foco muda. Por isso o `AppCodeEditor` tira o foco e o devolve quando `readOnly` muda: um editor com foco não continua recebendo digitação (IME) depois de bloqueado. A faixa, o aviso e o atalho Esc ficam sempre na mesma árvore, para o editor não ser remontado e não perder a rolagem.
- Sair da seção (R7) passa pelo `NavigationController.request`, que consulta o `leaveGuard` da tela de Specs. Usam esse caminho a barra lateral, a paleta e os atalhos (`AppShell._go`). Navegações feitas por código (notificações, aprovações) continuam diretas; se a tela de Specs for desmontada no meio de uma geração, a geração é cancelada.
- O Esc é um `CallbackShortcuts` da tela de Specs, ativo só durante uma ação longa. Funciona com o foco no editor, na faixa ou no cartão do protótipo.
- Em teste, o re_editor usa o caminho de teclado de celular (Enter insere linha mesmo somente leitura) porque a plataforma padrão do teste é Android. Os testes de bloqueio rodam com `TargetPlatform.linux`, a plataforma do app.
