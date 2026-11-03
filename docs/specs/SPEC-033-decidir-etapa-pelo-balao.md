---
id: SPEC-033
status: rascunho
depende-de: SPEC-030, SPEC-028
---

# Decidir a etapa que precisa de você sem abrir a sessão

## Objetivo

Quando uma etapa para em "aguardando você" (o balão âmbar da SPEC-030), clicar nele abre o `StepLiveDialog`: a linha do tempo inteira da sessão e um campo de mensagem. Para destravar a etapa, a pessoa precisa:

- ler a conversa até achar onde o agente parou e por quê;
- decidir sozinha o que fazer, sem nenhuma sugestão;
- escrever a resposta à mão ou abrir a sessão no Prompt;
- lembrar de mudar o requisito na spec, quando a decisão muda o que foi pedido. Hoje isso quase nunca acontece, e a spec deixa de bater com o código.

Esta spec troca esse caminho por um **modal de decisão**:

- ele abre com uma animação a partir do balão;
- a IA já resume o que aconteceu e propõe de 2 a 4 opções;
- a pessoa escolhe pelo mouse ou pelas teclas `1`–`4`;
- cada opção mostra como a etapa fica antes de ser escolhida;
- no fim, **Compilar** junta as escolhas, altera o requisito na spec (com o diff para revisar) e devolve a etapa ao agente.

Quem quiser conduzir a etapa junto com o agente continua tendo **Abrir sessão** (pair programming), a qualquer momento.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/J3VVoyZe3SzbZLN7MvSuTo). Cópia dos artboards, capturas e o relatório da validação (`relatorio-validacao-decidir-etapa-pelo-balao-2026-11-03.html`) em `docs/mockups/spec-033/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `0-hoje.png` | Clique no balão abre a linha do tempo da sessão | — |
| `1-abrindo.png` | Quatro quadros da abertura: o modal cresce a partir do balão, os tempos e uma demonstração em laço | R2, R13 |
| `1b-abertura-quadros.png` | O modal real aos 40, 120, 200, 300 e 460 ms: opções e prévia entram em sequência | R2 |
| `2-decidir.png` | Resumo, 4 opções numeradas (uma sugerida) e a prévia da etapa | R3–R7 |
| `3-reestruturar.png` | Opção "Dividir a etapa" em foco: R3 vira R3a e R3b na prévia | R6, R7 |
| `4-compilar.png` | Revisão das decisões, diff do requisito e mensagem ao agente | R9–R11 |
| `5-estados.png` | Gerando opções, falha ao gerar e verificação que falhou | R4, R8, R14 |
| `6-pair.png` | "Abrir sessão": o Prompt com a sessão e as decisões já tomadas | R12 |

## Requisitos

- R1 · O modal de decisão deve abrir quando a pessoa aciona uma etapa em `needsInput` (status "aguardando você") por qualquer destes pontos:
  - o balão da etapa no quadro em grafo (`CanvasStepDot`);
  - o segmento da etapa na vista Colunas;
  - a etapa no painel de etapas (`SpecStepsPanel`);
  - o item da caixa de entrada da tela inicial (`home_inbox.dart`).
  - Etapas em outros status continuam abrindo o `StepLiveDialog`. A comparação A/B pronta (`duelReady`) continua abrindo o diálogo de duelo.
- R2 · O modal deve abrir com uma animação que parte do balão:
  - o fundo escurece (opacidade 0 → 0,6) em 160 ms;
  - o modal cresce de escala 0,92 e opacidade 0 até 1, em 220 ms, com a curva de desaceleração (`Cubic(.2, .8, .2, 1)`) e a origem da transformação no ponto do balão;
  - o conteúdo entra em sequência, sem esperar o modal parar:
    - cada linha de opção sobe 6 px e aparece em 160 ms;
    - a primeira começa a 120 ms e as seguintes, 40 ms depois da anterior;
    - a prévia (R7) entra a 260 ms, do mesmo jeito;
  - o balão do cabeçalho do modal pulsa uma vez (o mesmo pulso da SPEC-030) quando a animação termina;
  - ao fechar, o caminho inverso dura 150 ms;
  - a animação não bloqueia o teclado: uma tecla apertada durante a abertura já vale.
- R3 · O cabeçalho do modal deve mostrar:
  - o balão, o código da spec e "Etapa <n> · aguardando você";
  - o texto do requisito da etapa, em até duas linhas;
  - "Fechar" (`Esc`).
  - Abaixo do cabeçalho, a seção **O que aconteceu**: um resumo de até 3 linhas, feito pela IA, do motivo da parada. Ele vem da última mensagem do agente, do relatório da verificação (`GateReport`) ou do erro da sessão.
- R4 · A IA deve propor de 2 a 4 opções por decisão, numa execução somente leitura (`runReadOnlyClaude` com `--json-schema`) que recebe a spec, o requisito da etapa, o resumo do R3 e o fim da sessão. Cada opção tem:
  - um título curto, com a ação em si (no máximo 8 palavras);
  - o tipo: **Responder** (só a mensagem ao agente), **Ajustar o requisito**, **Dividir a etapa** ou **Adiar a etapa**;
  - a consequência, numa frase;
  - a mudança proposta no requisito, quando o tipo a exige;
  - a marca **Sugerida** em no máximo uma opção.
  - A geração começa assim que a etapa entra em `needsInput`, sem esperar o clique, e fica guardada por (sessão, etapa, última mensagem) enquanto o app estiver aberto.
- R5 · As opções devem aparecer numa lista vertical numerada de 1 a 4:
  - cada linha tem o número (`kbd`), o título, o rótulo do tipo e a consequência;
  - a opção sugerida vem primeiro, com o selo "Sugerida";
  - depois da última vem **Outra resposta**, com a tecla `5`, que abre um campo de texto livre;
  - uma escolha não depende só da cor: a linha escolhida ganha o ícone de confirmação e o texto "Escolhida".
- R6 · O modal deve funcionar pelo teclado:
  - `1`–`4` escolhem a opção do número;
  - `5` abre "Outra resposta";
  - `↑`/`↓` movem o foco entre as opções e `Enter` escolhe a que está em foco;
  - `Backspace` volta à decisão anterior;
  - `Ctrl+Enter` aciona **Compilar** quando todas as decisões estão respondidas;
  - `Esc` fecha;
  - as teclas de número não valem enquanto o foco estiver num campo de texto.
  - A barra inferior mostra essas teclas.
- R7 · Ao lado das opções, o painel **Como a etapa fica** deve mostrar a prévia da opção em foco (ou da escolhida):
  - **Ajustar o requisito**: o texto do requisito com as trocas marcadas;
  - **Dividir a etapa**: a etapa trocada por duas (por exemplo, `R3` vira `R3a` e `R3b`), cada uma com o texto e os critérios dela, e a fila de etapas do card com uma bolinha a mais;
  - **Adiar a etapa**: a etapa vai para o fim da fila, com o status "pendente";
  - **Responder**: a mensagem que o agente vai receber, e "o requisito não muda".
  - A troca de prévia é uma transição cruzada de 120 ms.
- R8 · Quando a parada traz mais de uma pergunta (o agente perguntou duas coisas, ou duas etapas da mesma sessão esperam), o modal deve mostrar uma decisão por vez, com "Decisão <i> de <n>" e uma barra de progresso.
  - Escolher uma opção avança para a próxima depois de 250 ms, tempo para ver a confirmação.
  - As escolhas ficam guardadas por etapa enquanto o app estiver aberto. Fechar e reabrir o modal não as perde.
- R9 · Depois da última decisão, o modal deve mostrar **Compilar**, com:
  - a lista das decisões, cada uma com o título escolhido e "Mudar" (volta para ela);
  - o diff da spec, no mesmo componente da SPEC-026 (número de linha e rótulos acessíveis "Linha adicionada" e "Linha removida"). Ele é gerado por uma execução somente leitura que aplica as escolhas aos requisitos e aos critérios, no mesmo formato da `SpecAnswerApplier` da SPEC-028;
  - a mensagem que o agente vai receber, editável;
  - os botões "Voltar", "Só alterar a spec" e **Compilar e continuar** (primário, `Ctrl+Enter`).
- R10 · **Compilar e continuar** deve, nesta ordem:
  1. gravar a spec com o diff aprovado, sem mudar o status;
  2. reestruturar a etapa conforme o tipo escolhido:
     - em **Dividir**, criar as etapas novas no lugar da original;
     - em **Adiar**, mover a etapa para o fim e marcá-la "pendente";
     - nos demais tipos, manter a etapa;
  3. retomar a etapa:
     - com a sessão viva, enviar a mensagem a ela e marcar a etapa "em execução";
     - com a sessão encerrada, iniciar a próxima sessão da etapa (`runNext`) com a mensagem como contexto;
  4. fechar o modal e mostrar o aviso "SPEC-<n>: etapa <id> retomada · requisito alterado", com "Desfazer" por 8 s. "Desfazer" restaura o arquivo e a fila de etapas enquanto o agente não tiver começado.
  - "Só alterar a spec" faz só o passo 1 e deixa a etapa em "aguardando você".
- R11 · Se a spec tiver mudado no disco desde a abertura do modal, **Compilar e continuar** não deve gravar nada. O modal mostra "A spec mudou enquanto você decidia" com os botões "Recompilar" e "Abrir no editor".
- R12 · O modal deve ter **Abrir sessão** (tecla `S` quando o foco não está num campo) em todas as fases, para quem quer fazer pair programming com o agente.
  - Ele fecha o modal, abre a sessão da etapa no Prompt (`openSession`) e coloca no campo de mensagem um rascunho com as decisões já tomadas. O rascunho não é enviado sozinho.
  - Com a sessão encerrada, ele retoma a sessão (`--resume`) no modo interativo.
  - A etapa continua em "aguardando você" até o agente concluí-la.
- R13 · Com a animação desligada no sistema (`MediaQuery.disableAnimations`), o modal deve abrir e fechar sem escala nem deslizamento, só com o fundo (opacidade, 0 ms). As opções aparecem todas juntas e a prévia troca sem transição.
- R14 · O modal deve tratar os estados de espera e de erro sem prender a pessoa:
  - **Gerando opções**: o resumo e as linhas de opção aparecem como esqueletos, com "A IA está lendo a sessão…". "Outra resposta" e "Abrir sessão" já funcionam;
  - **Falha ao gerar**: "Não consegui propor opções: <motivo curto>", com "Tentar de novo", "Outra resposta" e "Abrir sessão";
  - **Verificação falhou** (o `GateReport` esgotou as tentativas): o resumo mostra o comando e as últimas linhas da saída, e as opções incluem, quando fizer sentido, "Corrigir o teste" e "Marcar o critério como manual" (tipo **Ajustar o requisito**).
- R15 · Leitores de tela devem ouvir:
  - o modal como diálogo, com o título "Decidir a etapa <n> da <código>";
  - cada opção como item de um grupo de rádio, com "Opção <n> de <total>: <título>. <tipo>. <consequência>", e "sugerida" quando for o caso;
  - a mudança de decisão ("Decisão 2 de 2") num aviso polido, sem mover o foco para fora da lista;
  - o foco preso no modal enquanto ele estiver aberto, e devolvido ao balão quando ele fechar.

## Fora do escopo

- Aprovação da spec (`waitingApproval`) e perguntas em aberto da spec: continuam com o fluxo da SPEC-023/SPEC-028.
- Comparação A/B (`duelReady`), falha ao preparar o worktree e spec alterada no disco.
- Responder pelo modal a várias specs em sequência ("próxima que precisa de você"). O botão "Atenção" da SPEC-030 continua sendo o caminho.
- Gerar opções com um modelo diferente do configurado para o planner.
- Atalhos globais para abrir o modal de fora do quadro.

## Design

### O que já existe

- `lib/features/board/widgets/spec_canvas.dart`:
  - `CanvasStepDot` com o balão (`StepDotShape.bubble`);
  - o `onTap` em l.833, que chama `showStepLiveDialog`;
  - o relógio de atenção compartilhado (`pulse`) da SPEC-030.
- `lib/features/board/widgets/step_live_dialog.dart`: `showStepLiveDialog` e `StepLiveDialog`, com a linha do tempo, a mensagem direta à sessão e "Corrigir" (`fixGate`).
- `lib/features/board/board_screen.dart`:
  - `openSession` (l.1519);
  - `boardAttentionReason`;
  - o segmento da etapa nas Colunas (l.1316).
- `lib/features/board/spec_runner.dart`:
  - os quatro pontos que marcam `needsInput`: duelo (l.1010), agente parou sem marcar a etapa (l.1456), verificação esgotada (l.1683) e sessão encerrada com erro (l.1882);
  - `runNext`.
- `lib/features/specs/spec_answers.dart`:
  - `SpecQuestionOptions`, com o cache por (spec, pergunta, texto) e o `runReadOnlyClaude` com `--json-schema`;
  - `SpecAnswerApplier` e `answeredSpecText`, que aplicam as respostas à spec;
  - `SpecAnswers` (Notifier), com as respostas por spec enquanto o app está aberto.
- `lib/ui/widgets/diff_view.dart`: `DiffView`, o diff da SPEC-026 usado na revisão da SPEC-028.
- `lib/features/board/board_rules.dart`: `stepsOf`, que monta a fila de etapas na ordem dos requisitos da spec (`spec.requirements`), mais as etapas de correção `REV<n>`.
- `lib/core/claude/readonly_run.dart`: `runReadOnlyClaude`.
- `lib/features/board/step_gate.dart`: `GateReport`.

### R1–R2, R13 · Abertura

- O novo `showStepDecision(context, spec, step, origin: Rect)` fica em `lib/features/board/widgets/step_decision_dialog.dart`.
- Os quatro pontos do R1 passam a chamar `openStep(context, spec, step, origin)`, que escolhe entre o `showStepDecision` e o `showStepLiveDialog` conforme o status.
- A abertura usa `showGeneralDialog` com `transitionBuilder`:
  - um `FadeTransition` no fundo (160 ms);
  - um `ScaleTransition` com `alignment` calculado a partir do centro de `origin` em relação à tela, e `Cubic(.2, .8, .2, 1)`;
  - a duração da volta é de 150 ms (`reverseTransitionDuration`).
- Com `MediaQuery.disableAnimationsOf(context)`, as durações são `Duration.zero` e não há `ScaleTransition`.
- A entrada em sequência usa o mesmo controller da abertura, com 420 ms: cada opção é um `FadeTransition` e um `SlideTransition` (de `Offset(0, 6 px)`) com `Interval` próprio (`start = (120 + 40·i) / 420`, 160 ms de duração). A prévia usa `Interval(260/420, 1)`.
- O balão do cabeçalho recebe um `AnimationController` próprio, de 1,8 s, que roda uma vez (`forward`) e só existe quando a animação está ligada.

### R3–R5, R14 · Opções

- `StepDecisionOptions` (em `lib/features/board/step_decision.dart`) segue o modelo da `SpecQuestionOptions`:
  - o schema tem `summary` (string), `decisions[]` com `question` e `options[]` (`title`, `kind` ∈ {`answer`, `amend`, `split`, `defer`}, `consequence`, `change`, `split[]`, `suggested`) e no máximo 4 opções por decisão;
  - `parseStepDecisions` descarta títulos vazios, limita a 4 opções e mantém só a primeira `suggested`.
- O cache usa a chave (sessionId, step, hash da última mensagem do agente). Um `ref.listen` em `specStepsProvider` dispara a geração quando uma etapa passa a `needsInput`, com no máximo uma execução por spec ao mesmo tempo.
- O contexto da sessão é limitado aos últimos 12 mil caracteres da linha do tempo. Com a verificação esgotada, o contexto inclui o `GateReport` (o comando e as últimas 40 linhas).
- Os erros nunca terminam o provider em erro, para o Riverpod 3 não agendar novas tentativas: o resultado é `StepDecisionResult(error:)`.

### R6–R8 · Decisões e prévia

- `StepDecisionDialog` (`ConsumerStatefulWidget`), com as fases `decidindo(i)` → `compilando` → `compilado` (ou `conflito`, no caso do R11).
- `Shortcuts` e `Actions` com `SingleActivator` para `digit1`…`digit5`, `arrowUp`/`arrowDown`, `enter`, `backspace`, `keyS`, `ctrl+enter` e `escape`. Um `FocusScope` prende o foco no modal. As teclas de número e o `S` são ignoradas quando o foco primário é um `EditableText`.
- As escolhas ficam em `stepDecisionChoicesProvider` (`Notifier<Map<(String sessionId, String step), List<Choice>>>`).
- O avanço automático do R8 usa um `Timer` de 250 ms, cancelado se a pessoa apertar outra tecla antes.
- A prévia é `StepDecisionPreview(option)`, com `AnimatedSwitcher` de 120 ms (zero com a animação desligada).
  - O texto alterado do requisito usa o diff por palavra já usado no realce de alterações.
  - A fila do card é desenhada com `CanvasStepDot(animate: false)`.

### R9–R11 · Compilar

- `StepDecisionCompiler.compile(spec, step, choices)` roda o `runReadOnlyClaude` com o prompt da `SpecAnswerApplier`, mais as instruções de divisão (`R3a`, `R3b`, critérios com `[R3a]` e `[R3b]`) e de adiamento. Ele devolve o texto novo da spec e a mensagem ao agente.
- **Compilar e continuar** compara o `mtime` e o hash do arquivo com os da abertura (R11) antes de gravar.
- A fila de etapas vem da ordem dos requisitos (`stepsOf`), então a reestruturação acontece no texto da spec:
  - em **Dividir**, o compilador troca o `R3` por `R3a` e `R3b`, e a linha de `spec_steps` do `R3` é removida (`specStepsRepoProvider`). As novas etapas nascem pendentes;
  - em **Adiar**, o compilador move o item do requisito para o fim de `## Requisitos`, sem mudar o id, e a etapa volta para `pending`.
- A retomada usa `sessionManagerProvider.notifier.send` quando a sessão está viva e, quando não está, `specRunnerProvider.runNext(specId, context: message)`. Este é um parâmetro novo: o texto entra no prompt da etapa.
- O "Desfazer" guarda o texto anterior e as linhas de `spec_steps` em memória e só vale enquanto a sessão não tiver emitido nenhum evento novo.

### R12 · Abrir sessão

- `openSession(ref, sessionId, draft: …)`: um parâmetro novo, que preenche o campo de mensagem da sessão (um `sessionComposerDraftProvider` novo, por sessão).
- Com a sessão encerrada, `sessionManager.resume(sessionId, interactive: true)`.

### R15 · Acessibilidade

- `Semantics(scopesRoute: true, namesRoute: true, label: 'Decidir a etapa …')` no modal.
- As opções formam um `RadioGroup`, com `Semantics(inMutuallyExclusiveGroup: true, checked:)` em cada uma.
- `SemanticsService.sendAnnouncement` na troca de decisão.
- Ao fechar, `FocusNode.requestFocus` devolve o foco ao nó do balão (`origin`).

### Testes

- `test/features/board/step_decision_test.dart` (novo), testes puros:
  - `parseStepDecisions`: limite de 4 opções, uma só sugerida e títulos vazios descartados;
  - a chave do cache;
  - a reestruturação da fila: com o texto compilado, `stepsOf` devolve `R3a` e `R3b` no lugar do `R3`, e o requisito adiado vai para o fim.
- `test/features/board/step_decision_dialog_test.dart` (novo), testes de widget com `ProviderContainer(retry: (_, _) => null)`:
  - o balão abre o modal e as outras etapas abrem o `StepLiveDialog`;
  - as teclas `1`–`5`, as setas, `Enter`, `Backspace`, `S`, `Ctrl+Enter` e `Esc`;
  - os números não valem dentro do campo de texto;
  - "Decisão 1 de 2" avança depois de 250 ms;
  - a prévia de cada tipo;
  - Compilar mostra o diff;
  - Compilar e continuar grava a spec, reestrutura a fila e envia a mensagem;
  - o conflito no disco (R11);
  - Abrir sessão com o rascunho;
  - os estados de espera e de erro;
  - com `disableAnimations`, as durações são zero;
  - os rótulos semânticos.

## Critérios de aceite

- [ ] O balão da etapa em "aguardando você" abre o modal de decisão; as demais etapas abrem o `StepLiveDialog` [R1] verificar: flutter test test/features/board/step_decision_dialog_test.dart
- [ ] O modal abre com fundo em 160 ms e escala 0,92 → 1 em 220 ms a partir do balão, e as opções entram em sequência a cada 40 ms; sem animação, as durações são zero [R2] [R13] verificar: flutter test test/features/board/step_decision_dialog_test.dart
- [ ] O cabeçalho mostra a etapa, o requisito e o resumo de "O que aconteceu" [R3] verificar: flutter test test/features/board/step_decision_dialog_test.dart
- [ ] As opções da IA são lidas com no máximo 4 por decisão e uma só sugerida, e ficam em cache por (sessão, etapa, última mensagem) [R4] verificar: flutter test test/features/board/step_decision_test.dart
- [ ] As opções aparecem numeradas, com tipo, consequência e "Outra resposta" em 5; a escolhida tem ícone e "Escolhida" [R5] verificar: flutter test test/features/board/step_decision_dialog_test.dart
- [ ] As teclas 1–5, setas, Enter, Backspace, S, Ctrl+Enter e Esc funcionam, e os números não valem dentro do campo de texto [R6] [R12] verificar: flutter test test/features/board/step_decision_dialog_test.dart
- [ ] A prévia mostra o requisito alterado, a etapa dividida em duas, a etapa adiada ou a mensagem, conforme o tipo [R7] verificar: flutter test test/features/board/step_decision_dialog_test.dart
- [ ] Com duas decisões, o modal mostra "Decisão 1 de 2" e avança 250 ms depois da escolha; reabrir mantém as escolhas [R8] verificar: flutter test test/features/board/step_decision_dialog_test.dart
- [ ] Compilar mostra a lista das decisões, o diff da spec e a mensagem editável [R9] verificar: flutter test test/features/board/step_decision_dialog_test.dart
- [ ] Compilar e continuar grava a spec, divide ou adia a etapa, envia a mensagem (ou inicia a próxima sessão) e oferece Desfazer [R10] verificar: flutter test test/features/board/step_decision_dialog_test.dart
- [ ] A reestruturação da fila divide R3 em R3a e R3b e adia a etapa para o fim [R10] verificar: flutter test test/features/board/step_decision_test.dart
- [ ] Com a spec alterada no disco, nada é gravado e aparece "A spec mudou enquanto você decidia" [R11] verificar: flutter test test/features/board/step_decision_dialog_test.dart
- [ ] Abrir sessão fecha o modal e abre a sessão com o rascunho das decisões, sem enviar [R12] verificar: flutter test test/features/board/step_decision_dialog_test.dart
- [ ] Gerando, falha ao gerar e verificação que falhou mostram os textos e as ações do R14 [R14] verificar: flutter test test/features/board/step_decision_dialog_test.dart
- [ ] O modal, as opções e a troca de decisão têm os rótulos semânticos, e o foco volta ao balão ao fechar [R15] verificar: flutter test test/features/board/step_decision_dialog_test.dart
- [ ] Os testes atuais do quadro continuam passando [R1] verificar: flutter test test/features/board
- [ ] A análise estática passa sem avisos novos [R1] [R2] [R3] [R4] [R5] [R6] [R7] [R8] [R9] [R10] [R11] [R12] [R13] [R14] [R15] verificar: flutter analyze
- [ ] Numa sessão real que parou com uma pergunta, as opções fazem sentido e Compilar e continuar retoma a etapa com o requisito alterado [R4] [R10] (manual)

## Perguntas em aberto

- P1 · As opções devem ser geradas assim que a etapa entra em "aguardando você" (custa uma execução do planner por parada, mesmo que a pessoa nunca abra o modal) ou só ao abrir o modal (espera de 10 a 30 s)?
  - Sugestão: gerar na hora da parada, como no R4. O modal abre pronto, e o custo é pequeno perto da sessão que parou.
- P2 · "Dividir a etapa" deve criar requisitos novos na spec (`R3a`, `R3b`) ou só etapas novas na fila, mantendo o R3 único na spec?
  - Sugestão: criar `R3a` e `R3b` na spec, como no R7, para a spec continuar sendo a fonte do que foi pedido e os critérios apontarem para cada parte.
- P3 · Quando a escolha é do tipo **Responder** (o requisito não muda), Compilar ainda deve passar pela tela de diff?
  - Sugestão: não. Sem mudança na spec, Compilar mostra só a mensagem ao agente e "o requisito não muda", e o botão vira "Enviar e continuar".
- P4 · "Desfazer" (R10) deve existir, sabendo que o agente pode começar a trabalhar em segundos e o desfazer só vale antes disso?
  - Sugestão: manter, com 8 s, e escondê-lo assim que a sessão emitir o primeiro evento.
- P5 · A tecla `S` para "Abrir sessão" pode conflitar com quem digita direto sem focar o campo. Usar `S` ou `Ctrl+O`?
  - Sugestão: `S`, ignorada dentro de campos de texto, como os números. Fica coerente com teclas de uma letra só e aparece na barra inferior.
