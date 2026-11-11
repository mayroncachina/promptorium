---
id: SPEC-064
status: rascunho
issue: 178
---

# "Executar tudo" diz quem começa e quem espera

## Objetivo

"Executar tudo" (o piloto automático do Quadro) liga e começa as specs sem dizer nada. Quem roda, quem espera e quem fica de fora só se descobre olhando os cards mudarem de coluna. Quando uma dependência some, como no caso do `depende:` que a SPEC-063 resolve, ou quando a regra libera uma spec antes do esperado, ninguém percebe até ver duas specs rodando juntas.

Esta spec põe uma **prévia** antes de começar e mostra, enquanto roda, quem espera quem. Ela também deixa escolher se quem espera é liberado quando a dependência chega em **Review** (como hoje) ou só em **Feito**.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/SJ4P7HKSWjbPkzRDKzT9QT). Capturas em `docs/mockups/spec-064/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-antes.png` | Hoje: tudo começa junto, sem aviso | — |
| `2-previa.png` | A prévia: começam agora, esperam e não entram | R1, R2, R3 |
| `3-executando.png` | Cards que esperam dizem por quem; o resumo na barra | R4, R5 |
| `4-liberou.png` | O aviso quando uma spec deixa de esperar | R6 |
| `5-nada.png` | Nada pode começar: a prévia explica | R7 |

## Requisitos

- R1 · "Executar tudo" abre uma **prévia** presa ao botão, antes de ligar o piloto automático. Ela tem três grupos, cada um com código, título e motivo:
  - **Começam agora:** as specs que o piloto iniciaria neste momento, respeitando o limite de specs em paralelo (`autopilot.paralelo`); as que passam do limite aparecem em "Esperam", com "na fila: limite de N em paralelo";
  - **Esperam:** as bloqueadas por dependência, com "depois da SPEC-001 chegar em Review" (ou "em Feito") e os códigos de todas as dependências que faltam;
  - **Não entram:** as que o piloto nunca vai começar, com o motivo: "ainda não foi aprovada", "depende de SPEC-007, que está em outra sprint" ou "está fora da sprint ativa".
- R2 · O rodapé da prévia tem **Cancelar** e **Executar N specs**, em que N é quem começa agora mais quem espera. Enter executa e Esc cancela. O cabeçalho diz "Até N specs em paralelo · ajuste em Configurar projeto".
- R3 · A prévia tem a opção **Liberar quem espera quando a dependência chegar em: Review | Feito**:
  - Review é o padrão e o comportamento de hoje (a branch nova parte da branch da dependência);
  - Feito só libera depois do merge;
  - a escolha fica guardada por workspace e vale para o piloto automático e para o "Agendar".
- R4 · Com o piloto ligado, cada card que espera mostra o selo "espera SPEC-001" (ou "espera SPEC-002, SPEC-003"), com a borda tracejada em âmbar. No Grafo e no Foco, o mesmo texto aparece na dica do card.
- R5 · Com o piloto ligado, a barra do Quadro mostra "Executando · N rodando · M esperando" ao lado de **Parar**.
- R6 · Quando uma spec deixa de esperar e começa, aparece o aviso "SPEC-002 começou: a SPEC-001 chegou em Review." (ou "em Feito"), que some sozinho. Quando o piloto desliga porque não há mais nada a fazer, o aviso é "Executar tudo terminou: N specs em Review."
- R7 · Se nada pode começar, a prévia diz "Nenhuma spec pode começar agora.", lista as bloqueadas e as que não entram com os motivos, e o botão de executar fica desabilitado. O piloto não liga e desliga em seguida sem explicar, como hoje.

## Fora do escopo

- Ler variações da chave de dependência e avisar dependências inválidas (SPEC-063).
- Mudar a ordem em que o piloto escolhe as specs ou o limite de paralelo.
- A prévia no "Agendar" (o agendamento usa a mesma regra, sem prévia).

## Design

### O que já existe

- `lib/features/board/autopilot.dart`: `Autopilot.start`, `tick` (escopo da sprint, limite de paralelo, `specBlockers(…, reviewUnblocks: true)`, travas do planejamento automático) e o desligar automático.
- `lib/features/board/board_rules.dart`: `specBlockers` e `isSpecBlocked`.
- `lib/features/board/sprint_rules.dart`: `autopilotScope`.
- `lib/features/board/board_screen.dart`, por volta da linha 1137: o botão `board-autopilot` e o tooltip.
- `lib/features/project/project_config.dart`: `autopilot.parallel`.

### Componentes

- **`autopilotPlan(specs, active, {parallel, unblockAt})`** (puro, em `autopilot.dart`): devolve `start`, `wait` (com os códigos que faltam e o motivo) e `skip` (com o motivo). O `tick` passa a usar o mesmo cálculo, para a prévia e a execução nunca divergirem.
- **`AutopilotPreview`** (popover do botão): os três grupos, a opção Review/Feito e o rodapé.
- **`unblockAt`** guardado nos ajustes do workspace (`autopilot.liberar` = `review` ou `feito`); `reviewUnblocks` vira `unblockAt == review`.
- **Selo "espera"** no card das colunas e na dica do Grafo e do Foco; o resumo na barra.
- **Avisos** pelo mesmo canal dos outros avisos do Quadro.

### Testes

- `autopilotPlan`: sem dependências, com dependência em Backlog, Review e Feito (nas duas regras), limite de paralelo, sprint ativa, dependência em outra sprint, não aprovada.
- A prévia mostra os mesmos grupos que o `tick` executa (cenário do caso real: SPEC-002 depende da SPEC-001).
- Executar N, Cancelar, Enter e Esc; nada a fazer com o botão desabilitado.
- Selo "espera" e resumo na barra enquanto roda; o aviso ao liberar e ao terminar.
- "Feito" não libera em Review; a escolha fica guardada.

## Decisões

- **Prévia em vez de confirmação genérica.** Um "Tem certeza?" não teria mostrado o problema do caso real. Ver "Começam agora: SPEC-001, SPEC-002" teria.
- **Um só cálculo.** A prévia e o `tick` usam `autopilotPlan`; se a prévia diz que a SPEC-002 espera, o piloto não a começa.
- **Review continua o padrão.** Quem usa hoje não muda de comportamento. Quem quer esperar o merge escolhe Feito uma vez.

## Plano

1. **t1 · Plano e prévia** (R1–R3, R7): `autopilotPlan`, o `tick` usando o plano, a prévia, a opção Review/Feito guardada e os testes.
2. **t2 · Enquanto roda** (R4–R6): o selo "espera", o resumo na barra, os avisos de liberar e de terminar e os testes.

## Critérios de aceite

- [ ] Antes de começar, "Executar tudo" mostra quem começa agora, quem espera e quem não entra, com os motivos.
- [ ] A prévia e a execução sempre batem.
- [ ] Dá para escolher liberar em Review ou em Feito, e a escolha fica guardada.
- [ ] Enquanto roda, cada card que espera diz por quem, e a barra mostra o resumo.
- [ ] Quando nada pode começar, a prévia explica e não liga o piloto.
