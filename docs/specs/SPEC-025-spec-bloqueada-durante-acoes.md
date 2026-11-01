---
id: SPEC-025
status: rascunho
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

- [ ] Com "Gerar design" em andamento, digitar, colar e `Ctrl+S` não alteram o texto nem o arquivo [R1] verificar: flutter test test/features/specs/spec_action_lock_test.dart
- [ ] Durante qualquer ação, o botão dela mostra o rótulo no gerúndio com spinner, e as demais ações e o menu ficam desabilitados [R2] verificar: flutter test test/features/specs/spec_action_lock_test.dart
- [ ] A faixa de status aparece só nas ações longas, com título, motivo, tempo decorrido e "Cancelar geração" [R3] [R6] verificar: flutter test test/features/specs/spec_action_banner_test.dart
- [ ] Com a spec bloqueada, as abas continuam trocando de modo e o texto continua visível, sem véu [R4] verificar: flutter test test/features/specs/spec_action_lock_test.dart
- [ ] "Cancelar geração" e Esc completam o `cancelled` do `runReadOnlyClaude`, liberam a spec e mantêm o texto igual ao de antes [R5] verificar: flutter test test/features/specs/spec_design_test.dart test/features/specs/spec_action_lock_test.dart
- [ ] Uma ação de menos de 300 ms não mostra spinner [R6] verificar: flutter test test/features/specs/spec_action_lock_test.dart
- [ ] Escolher outra spec durante "Gerar design" abre a confirmação; "Continuar aqui" mantém a spec atual; a outra opção cancela e abre a escolhida [R7] verificar: flutter test test/features/specs/specs_screen_test.dart
- [ ] O resultado de uma geração que termina depois da troca de spec não é aplicado à spec nova [R7] verificar: flutter test test/features/specs/spec_action_lock_test.dart
- [ ] Uma falha mostra o aviso com a causa, libera a spec sem mudar o texto, e "Tentar de novo" repete a ação [R8] verificar: flutter test test/features/specs/spec_action_banner_test.dart
- [ ] No modo Protótipo, o cartão de geração mostra o tempo e "Cancelar geração", e cancelar interrompe o agente [R9] verificar: flutter test test/features/specs/prototype_view_test.dart test/features/specs/prototype_service_test.dart
- [ ] Os botões desabilitados têm contraste de 4,5:1 ou mais e não usam opacidade [R10] verificar: flutter test test/features/specs/spec_action_lock_test.dart
- [ ] Com `disableAnimations`, o spinner fica parado; a faixa é anunciada como região viva; o Tab segue a ordem visual [R11] verificar: flutter test test/features/specs/spec_action_banner_test.dart
- [ ] Os testes atuais de specs e do protótipo continuam passando [R1] [R2] [R9] verificar: flutter test test/features/specs
- [ ] A análise estática passa sem avisos novos [R1] [R2] [R3] [R4] [R5] [R6] [R7] [R8] [R9] [R10] [R11] verificar: flutter analyze

## Perguntas em aberto

- Durante "Refinar com IA", o bloqueio vale só até a conversa abrir (como no R1), ou até a conversa terminar?
- A SPEC-024 (R10) diz que ações indisponíveis ficam com opacidade de cerca de 45 %. Ajustar a SPEC-024 para o estilo do R10 desta spec, para valer em todo o cabeçalho?
