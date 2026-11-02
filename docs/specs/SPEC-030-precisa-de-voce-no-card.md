---
id: SPEC-030
status: rascunho
depende-de: SPEC-017
---

# "Precisa de você" mais claro no card do quadro

## Objetivo

No quadro em grafo, o card de uma spec que espera a pessoa tem borda âmbar, o selo "Precisa de você" e um halo que pulsa. A etapa que espera, porém, é só um losango âmbar de 8 px, quase do tamanho de uma bolinha pendente, e é difícil de achar numa fila de 13 etapas. Além disso:

- **O losango é estático.** Só o halo do card pulsa (`_AttentionHalo`, 900 ms, ida e volta), sem ligação visual com a etapa que precisa de ação.
- **O selo não diz o quê.** O motivo ("Etapa 3 · aprovar o plano") só aparece ao abrir a spec, no painel lateral (`boardAttentionReason`).
- **O âmbar se repete.** A pílula "Em execução" é laranja (`#F08A4B`), quase o mesmo tom do âmbar de atenção (`#F2A541`), e compete com o sinal.
- **O botão "Atenção · n" não diz onde você está.** Ao percorrer a fila, não dá para saber qual delas está selecionada.

Esta spec troca o losango por um balão e dá ao card um pulso só, num ritmo lento e acessível, que continua até a etapa ser resolvida. O card também passa a mostrar o motivo em uma linha, e o botão "Atenção" mostra a posição na fila.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/An9CSFnYoZtoBZgHihHRYp). Cópia dos artboards e capturas em `docs/mockups/spec-030/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `0-hoje.png` | O card como é hoje, com o losango | — |
| `1-proposta.png` | Balão na etapa, motivo no card, status neutro e tooltip da etapa | R1–R4, R7 |
| `2-opcoes-de-icone.png` | Losango, balão (escolhido), mão e exclamação no tamanho real e ampliados | R1 |
| `3-ritmo-do-pulso.png` | Quatro quadros de um ciclo de 1,8 s e os estados "esperando", "selecionada (continua pulsando)" e "em execução" | R2, R5, R6, R9 |
| `4-quadro.png` | Quadro com quatro specs: duas esperando, as duas pulsando (uma selecionada), e "Atenção · 1 de 2" | R5, R8 |

## Requisitos

- R1 · A etapa com status `needsInput` deve ser desenhada como um **balão** âmbar cheio de 14 px, **sem reticências**, no lugar do losango de 8 px.
  - Sem os três pontos, o balão não se confunde com "o agente está digitando".
  - A forma deve ser diferente das demais (círculo cheio, círculo vazado, anel), para que o estado não dependa só da cor.
  - A legenda do canvas ("aguardando você") passa a mostrar o balão.
- R2 · Enquanto uma spec precisar da pessoa (R5), o card deve pulsar num **ciclo único de 1,8 s**:
  - o halo do card se abre de 0 a 10 px enquanto some (opacidade de 0,55 a 0);
  - o balão da etapa respira junto, de opacidade 1 a 0,55 e de volta;
  - todos os cards que precisam da pessoa pulsam, sem prioridade entre eles, e usam o mesmo relógio, então pulsam em sincronia.
- R3 · O selo "Precisa de você" deve ganhar o mesmo balão à esquerda do texto e **não pode piscar**: fica sempre com opacidade 1 (contraste do texto escuro sobre o âmbar mantido).
  - No card que precisa da pessoa, a pílula de status (por exemplo "Em execução") deve usar o tom neutro (texto secundário sobre `surfaceRaised`), para o âmbar ficar só com o sinal de atenção.
- R4 · O card deve mostrar o motivo em uma linha, entre o título e as etapas, com o texto de `boardAttentionReason` (por exemplo "Etapa 3 · aprovar o plano"), em `AppColors.text`, cortado com reticências quando não couber.
- R5 · O card deve pulsar **até a etapa ser resolvida**, isto é, até deixar de estar em `needsInput` (aprovada, respondida ou cancelada).
  - Selecionar a spec no quadro ou abri-la **não** para o pulso.
  - Não há marca de "já vista" nem ação de adiar: o pulso contínuo é o lembrete.
- R6 · Com a animação desligada no sistema (`MediaQuery.disableAnimations`), nada deve pulsar: o card que precisa da pessoa fica com um **brilho fixo** de 3 px (âmbar a 28%).
- R7 · Ao passar o mouse (ou dar foco) no balão da etapa, o sistema deve mostrar o detalhe da etapa (`CanvasDetailCard`) com:
  - o título "Etapa <n> · aguardando você" e o balão;
  - o que falta, em uma linha;
  - "Clique para abrir a etapa".
- R8 · O botão "Atenção" da barra do canvas deve ganhar o balão à esquerda do texto e não pode quebrar linha.
  - Quando a spec selecionada está na fila de atenção, o botão mostra a posição: "Atenção · <i> de <n>" (por exemplo "Atenção · 1 de 2"). Quando não está, mostra só o total: "Atenção · <n>".
  - A fila mantém a ordem de hoje: onda de dependência e depois código da spec. A posição e o total vêm da **mesma lista** ordenada.
  - Ao resolver a spec selecionada, ela sai da fila, o botão volta a mostrar só o total e o próximo clique vai para a primeira da fila.
- R9 · No quadro, só os cards que precisam da pessoa pulsam.
  - A bolinha de "em execução" continua como está.
  - Nenhuma animação de atenção pode passar de uma piscada por segundo (limite de 3 por segundo da WCAG 2.3.1).
- R10 · Leitores de tela devem ouvir o estado sem depender da animação:
  - o card anuncia "<código> · <título> · precisa de você: <motivo>";
  - a fila de etapas anuncia "aguardando você" na etapa certa.

## Fora do escopo

- A vista "Colunas", que já mostra o motivo em texto no rodapé do card.
- A caixa de entrada da tela inicial (`home_inbox.dart`).
- Adiar ou silenciar o pulso de uma spec ("lembrar depois").
- Animar a mudança de altura e a reorganização do quadro quando o motivo aparece ou some.
- Notificação do sistema ou som quando uma etapa passa a esperar.
- Mudar as cores de "em execução", "feita" e "verificando".

## Design

### O que já existe

- `lib/features/board/widgets/spec_canvas.dart`:
  - `_AttentionBadge` (l.622), o selo sem ícone;
  - `_SpecNode` (l.660), o card, com `_Pill(stage)`;
  - `CanvasStepDot` e `_DotPainter` (l.959–1100), com `StepDotShape.diamond` em `needsInput`; só `running` e `verifying` animam;
  - `_AttentionHalo` (l.1095), um `AnimationController` de 900 ms por card, que já respeita `MediaQuery.disableAnimationsOf`;
  - a legenda (l.1584), que desenha `CanvasStepDot(animate: false)` para cada status;
  - `CanvasDetailCard`, que já envolve cada bolinha com o detalhe da etapa (`_StepDetails`).
- `lib/features/board/board_screen.dart`: `boardAttentionReason` (l.196), o texto do motivo, já usado no painel lateral.
- `CanvasColors.needsInput = AppColors.amber`, `AppColors.onAmber`.

### R1 · Balão

- `StepDotShape.diamond` passa a se chamar `bubble`. `_DotPainter` desenha o balão cheio num quadro de 14×14: retângulo de cantos de 2,5 px e um rabicho embaixo à esquerda, sem pontos.
- `CanvasStepDot` passa a medir 14 px de largura quando o status é `needsInput` e 10 px nos demais, e a fila de etapas (`_SpecNode`, `fits = maxWidth ~/ 16`) conta essa largura extra.

### R2, R5, R6 · Pulso

- **Relógio único:** um `AnimationController` de 1,8 s com `repeat()`, criado no estado do canvas (`SpecCanvas`). Ele só existe enquanto houver ao menos um card que precisa da pessoa e a animação estiver ligada.
- **Card:** `_AttentionHalo` deixa de criar o próprio controller e recebe o do canvas. A curva do halo é `Cubic(.2, .6, .4, 1)`, com `spreadRadius` de 0 a 10 e alfa de 0,55 a 0 até 70% do ciclo, e 0 no resto.
- **Balão:** `CanvasStepDot` recebe o mesmo `Animation<double>` e aplica a opacidade `1 − 0,45·sin(π·t)`.
- **Até resolver:** o pulso usa só `widget.attention(d)`, que já decide a borda e o selo. Não existe estado de "visto"; a seleção (`boardSelectedSpecProvider`) não entra na conta.
  - Com a animação desligada, o card mostra o brilho fixo (`BoxShadow(color: amber.withValues(alpha: .28), spreadRadius: 3)`).
- **Desempenho:** cada card fica dentro de um `RepaintBoundary`, como hoje, e só o halo e o balão repintam a cada quadro.

### R3, R4, R8 · Selo, motivo e barra

- `_AttentionBadge` ganha o balão de 13 px (desenho invertido: corpo `onAmber`, sem pontos) antes do texto e uma borda de 3 px na cor do fundo, que o separa da borda do card.
- `_Pill` recebe `neutral: true` quando o card precisa da pessoa.
- `_SpecNode` ganha uma linha com `boardAttentionReason(d)` (12 px, peso 500, `maxLines: 1`). O tamanho do card no layout (`_cardSize`) cresce 18 px só quando há atenção; os demais cards não reservam o espaço. O quadro se reorganiza quando o motivo aparece ou some.
- `_BarButton` de "Atenção" recebe o balão como ícone e `softWrap: false`.
- O rótulo do botão passa a usar `attention.length` (a lista ordenada em `spec_canvas.dart`, l.186) em vez de `widget.attentionCount`, para que a posição e o total venham da mesma lista. `i` é `attention.indexWhere(...) + 1` quando a selecionada está na fila.

### R7, R10 · Detalhe e leitura

- `_StepDetails` ganha o cabeçalho com o balão para `needsInput`, a linha do que falta (o mesmo texto do motivo) e "Clique para abrir a etapa".
- O card ganha `Semantics(label: …)` com o motivo, e `CanvasStepDot` ganha `Semantics(label: 'Etapa <n>: aguardando você')`.

### Testes

- `test/features/board/canvas_view_test.dart`:
  - o balão em `needsInput`;
  - o selo com ícone;
  - a pílula neutra;
  - o motivo no card;
  - a legenda;
  - o rótulo semântico;
  - "Atenção · 1 de 2" com a primeira da fila selecionada, "Atenção · 2" sem seleção, e o total depois de resolver a selecionada.
- `test/features/board/attention_pulse_test.dart` (novo):
  - um só controller para dois cards;
  - o card continua pulsando com a spec selecionada e para quando a etapa sai de `needsInput`;
  - nada anima com `disableAnimations`;
  - o período é de 1,8 s.

## Critérios de aceite

- [ ] A etapa que espera a pessoa aparece como balão de 14 px sem reticências, também na legenda [R1] verificar: flutter test test/features/board/canvas_view_test.dart
- [ ] Dois cards que precisam da pessoa pulsam com o mesmo controller, num ciclo de 1,8 s, e o balão da etapa acompanha o halo [R2] [R9] verificar: flutter test test/features/board/attention_pulse_test.dart
- [ ] O selo tem o balão e não muda de opacidade; a pílula de status do card fica neutra [R3] verificar: flutter test test/features/board/canvas_view_test.dart
- [ ] O card mostra o motivo em uma linha [R4] verificar: flutter test test/features/board/canvas_view_test.dart
- [ ] Com a spec selecionada o card continua pulsando; quando a etapa deixa de esperar, o pulso para [R5] verificar: flutter test test/features/board/attention_pulse_test.dart
- [ ] Com `disableAnimations`, nenhum controller de atenção é criado e o card mostra o brilho fixo [R6] verificar: flutter test test/features/board/attention_pulse_test.dart
- [ ] O detalhe da etapa mostra "Etapa <n> · aguardando você", o que falta e "Clique para abrir a etapa" [R7] verificar: flutter test test/features/board/canvas_view_test.dart
- [ ] "Atenção" tem o balão, não quebra linha e mostra "<i> de <n>" com a selecionada na fila e só "<n>" fora dela [R8] verificar: flutter test test/features/board/canvas_view_test.dart
- [ ] O card e a etapa têm os rótulos semânticos com o motivo [R10] verificar: flutter test test/features/board/canvas_view_test.dart
- [ ] Os testes atuais do quadro continuam passando [R1] [R2] verificar: flutter test test/features/board
- [ ] A análise estática passa sem avisos novos [R1] [R2] [R3] [R4] [R5] [R6] [R7] [R8] [R9] [R10] verificar: flutter analyze

## Decisões

- (P1) Ícone: balão cheio, **sem reticências**. Com os três pontos ele se lê como "o agente está digitando", o oposto de "esperando você"; e nem toda intervenção é uma resposta (aprovar o plano, decidir após uma falha). A mão perde o desenho abaixo de 16 px e a exclamação se confunde com erro (R1, R3).
- (P2) Todos os cards que pulsam usam um relógio só, em sincronia (R2).
- (P3) Sem marca de "já vista": a pergunta deixou de existir com a decisão abaixo.
- (P5) Todas as specs que precisam da pessoa pulsam, sem prioridade de fila (R2, R9).
- O pulso continua **até a etapa ser resolvida**, mesmo com a spec selecionada ou aberta, e mesmo quando a pessoa decide adiar. O incômodo é intencional; não há "lembrar depois" (R5).
- (P4) Só os cards que precisam da pessoa crescem 18 px para o motivo. Aceito o risco: o quadro se reorganiza quando uma etapa passa a esperar ou é resolvida, e os cards abaixo mudam de lugar.
- (P6) O botão mostra "Atenção · <i> de <n>" quando a selecionada está na fila. Ordem: onda e depois código, como hoje. Depois de resolver, mostra só o total e o próximo clique vai para a primeira (R8).

## Riscos aceitos

- Pulso contínuo na visão periférica enquanto a pessoa adia uma intervenção de propósito.
- Os cards pulam de lugar sob o cursor quando o motivo aparece ou some; um clique logo após resolver pode cair no card errado. Animar essa transição fica para outra spec.
