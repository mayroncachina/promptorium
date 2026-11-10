---
id: SPEC-054
status: rascunho
depende-de: SPEC-030, SPEC-049
---

# Card que precisa de você treme de tempos em tempos

## Objetivo

Hoje, um card que precisa de revisão humana tem a borda âmbar, o selo "Precisa de você" e, nas visões Grafo e Foco, um halo que pulsa devagar (SPEC-030). Com uma spec rodando há meia hora, o pulso vira paisagem: a pessoa olha para o Quadro e não percebe que um agente parou esperando por ela.

Esta spec dá ao card um **tremor curto, de tempos em tempos**, nas três visões do Quadro (Colunas, Grafo e Foco). O tremor é o mesmo gesto de "não" de um campo errado: pequeno, rápido e raro. Ele acontece:
- quando a spec passa a precisar de você;
- depois, a cada 5 s, um card de cada vez.

O tremor para quando a pessoa já viu o card, e não roda com movimento reduzido nem quando a opção está desligada.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/6TGxoQimCoyUp7RsnJvLmQ), validado com `/validar-layouts` (nota média de 83 para 88, "Pronto para entregar"; detalhes na issue). Capturas em `docs/mockups/spec-054/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-colunas.png` | Colunas com dois cards esperando: um no meio do tremor, o outro na vez seguinte, 5 s depois | R1, R2, R4 |
| `2-grafo.png` | Grafo com o card tremendo dentro do halo da SPEC-030 | R1, R5 |
| `3-foco.png` | Foco com o card de uma dependência tremendo no palco | R1, R5 |
| `4-movimento.png` | O tremor quadro a quadro, o ritmo de 5 s com dois cards, as pausas e o movimento reduzido | R1–R8 |
| `5-aparencia.png` | Configurações › Aparência com "Tremer cards que precisam de você" | R7 |

## Requisitos

- R1 · Quando um card do Quadro precisar de revisão humana (o mesmo critério do filtro "Precisam de mim"), ele deve tremer:
  - deslocamento horizontal de até 3 px, ida e volta, mais um giro de até 0,6°;
  - em 420 ms, com 3 oscilações que vão diminuindo (−3, +3, −2, +2, −1, 0 px);
  - só com transformação: nada em volta muda de lugar e o texto não se move dentro do card.
- R2 · O primeiro tremor acontece assim que a spec passa a precisar de você. Depois disso, **um card treme a cada 5 s**:
  - com mais de um card esperando, eles se revezam (um por vez), na ordem da fila de atenção da SPEC-030 R8 (onda e depois código);
  - nunca há dois cards tremendo ao mesmo tempo;
  - o halo e o brilho da SPEC-030 continuam como estão.
- R3 · Cada card treme no máximo **6 vezes seguidas**. Depois, ele para e fica só com o halo ou brilho fixo da SPEC-030, até um destes acontecer:
  - o motivo mudar (por exemplo, uma nova etapa esperando);
  - a pessoa voltar ao Quadro vindo de outra tela.
- R4 · O card não treme enquanto:
  - o mouse está sobre ele, ele tem o foco do teclado ou está selecionado no Quadro;
  - a pessoa arrasta um card, ou um diálogo, menu ou a paleta está aberto;
  - a janela do app não está em foco.

  Passar o mouse sobre o card ou focá-lo conta como "visto": ele sai do revezamento até o motivo mudar.
- R5 · O tremor vale nas três visões:
  - **Colunas:** o cartão da coluna;
  - **Grafo:** o nó, junto com o halo;
  - **Foco:** o cartão no palco, tanto a spec central quanto as dependências.

  Uma spec dentro de uma pasta recolhida do Canvas não treme. A pasta mostra a contagem de "precisa de você", como hoje.
- R6 · Com movimento reduzido (sistema ou app), nenhum card treme. O card fica com o brilho fixo da SPEC-030 R6.
- R7 · Configurações › Aparência ganha a opção **"Tremer cards que precisam de você"** (Ligado/Desligado, padrão Ligado). Desligada, nenhum card treme e o resto da SPEC-030 continua. É o mecanismo de parar da WCAG 2.2.2.
- R8 · Desempenho:
  - entre um tremor e outro o Quadro não pede nenhum quadro, porque a espera é um `Timer`;
  - na média, isso dá cerca de 5 quadros/s a mais (25 quadros de 420 ms a cada 5 s), além do halo;
  - cada tremor usa o vsync normal só durante os 420 ms;
  - o tremor redesenha só o card (`RepaintBoundary`).
- R9 · O tremor não é anunciado ao leitor de tela, para não repetir a cada 5 s. O card continua anunciando "precisa de você: <motivo>" (SPEC-030 R10).

## Fora do escopo

- Som, notificação do sistema ou ícone pulando na barra de tarefas.
- Tremer a barra lateral, o selo "Precisa de você" ou o botão "Atenção".
- Mudar o halo, o balão ou o motivo da SPEC-030.

## Design

### O que já existe

- `board_screen.dart`:
  - `attention(SpecCardData d)` decide quem precisa da pessoa;
  - `attentionCount` alimenta "Precisam de mim · n";
  - `boardAttentionReason` dá o motivo.
- `spec_canvas.dart`:
  - `AttentionHalo` e o relógio `_pulse` (`attentionPulsePeriod`, 1,8 s, no relógio de ambiente da SPEC-049);
  - os nós do Grafo ficam dentro de `RepaintBoundary`.
- `spec_stage.dart`: o palco do Foco, com `AttentionHalo` e o próprio `_pulse`.
- `settings_sections.dart` e `settings_screen.dart`: a seção Aparência (SPEC-049 R6).

### Componentes

- **`AttentionShakeScheduler`** (novo, `lib/features/board/attention_shake.dart`):
  - um Notifier com a fila de atenção, um `Timer` de 5 s, o contador de tremores por spec (no máximo 6) e as specs "vistas";
  - expõe `shakeTick` (spec id + número), que muda só quando algum card deve tremer;
  - pausa com o foco da janela, diálogos e arraste (R4).
- **`AttentionShake`** (novo widget): envolve o card em `RepaintBoundary` + `Transform`. Ao receber um `shakeTick` com o seu id, toca um `AnimationController` de 420 ms (vsync normal) com a curva de R1. Com movimento reduzido ou a opção desligada, é só o filho.
- **Colunas, Grafo e Foco**: os três envolvem o card com `AttentionShake(specId: …)`. O hover e o foco chamam `scheduler.seen(specId)`.
- **Aparência**: a chave `aparencia.tremor` ('false' desliga), ao lado de `aparencia.vidro`.

### Testes

- **Scheduler:**
  - com dois cards, um tremor a cada 5 s, alternando;
  - para no 6.º tremor;
  - volta quando o motivo muda;
  - `seen` tira o card do revezamento;
  - não dispara sem foco da janela nem com um diálogo aberto.
- **`AttentionShake`:**
  - o deslocamento máximo é 3 px;
  - acaba em 420 ms;
  - `hasRunningAnimations` fica falso entre os tremores;
  - com movimento reduzido, nada se move.
- **Visões:** o card certo treme nas três, e uma spec numa pasta recolhida não treme.
- **Configuração:** desligada, nenhum card treme e o halo continua.

## Plano

1. `AttentionShakeScheduler` e `AttentionShake`, com os testes (R1–R4, R6, R8).
2. Ligar nas Colunas, no Grafo e no Foco (R5), com o hover e o foco marcando "visto".
3. A opção em Aparência (R7) e o guia (`docs/guia/quadro.md` e `configuracoes.md`).
4. Medir com `PROMPTORIUM_QUADROS`: com um card esperando, até cerca de 5 quadros/s em média além do halo; capturas do app em `docs/mockups/spec-054/app/`.

## Critérios de aceite

- [ ] Um card que passa a precisar de você treme na hora, nas três visões.
- [ ] Com dois cards esperando, eles se revezam a cada 5 s e nunca tremem juntos.
- [ ] Depois de 6 tremores o card para e fica com o halo; volta a tremer quando o motivo muda.
- [ ] Passar o mouse ou focar o card para o tremor dele.
- [ ] Com movimento reduzido ou a opção desligada, nada treme.
- [ ] Entre tremores, o Quadro parado não pede quadros além do halo.
- [ ] O leitor de tela não anuncia o tremor.

## Perguntas em aberto

- P1 · O intervalo de 5 s deve ser configurável? Sugestão: não, porque a opção liga/desliga já cobre quem se incomoda.
