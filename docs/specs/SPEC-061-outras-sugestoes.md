---
id: SPEC-061
status: rascunho
depende-de: SPEC-059
---

# Três sugestões do Claude e "Outras sugestões"

## Objetivo

Em "Responder perguntas" (SPEC-028, no centro desde a SPEC-059), cada pergunta mostra a sugestão da spec e **até duas** propostas do Claude. Quando nenhuma serve, o único caminho é escrever em "Outra resposta", mesmo quando a pessoa só queria ver outras ideias.

Esta spec faz o Claude propor **três** respostas por padrão e põe um botão **Outras sugestões** (Ctrl+R) que pede um conjunto novo, sem repetir as que já apareceram.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/XykDZbCWv2qbkgdYHRwD8C). Capturas em `docs/mockups/spec-061/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-antes.png` | Hoje: a sugestão da spec e duas propostas do Claude | — |
| `2-tres-sugestoes.png` | Três propostas e o botão "Outras sugestões · Ctrl+R" | R1, R2 |
| `3-gerando.png` | Gerando outras: o botão desabilitado e as três propostas em espera | R3 |
| `4-novas.png` | Novas propostas, com a escolhida mantida no lugar | R4 |
| `5-erro.png` | Falha ao gerar: as anteriores continuam | R5 |
| `6-estreito.png` | 1100×700 com cinco opções | R6 |

## Requisitos

- R1 · O Claude propõe **três** respostas por pergunta (hoje, até duas), diferentes da sugestão da spec. As opções ficam: a sugestão da spec (quando há), as três propostas e "Outra resposta", com as teclas 1 a 5. Sem sugestão na spec, as propostas começam no 1.
- R2 · Acima das opções, a linha "RESPOSTAS" tem o botão **Outras sugestões**, com a tecla Ctrl+R:
  - Ctrl+R funciona em toda a pergunta, inclusive com o foco no campo de "Outra resposta";
  - o botão só aparece nas perguntas, não na revisão nem no diff.
- R3 · Ao pedir outras:
  - o botão fica desabilitado com "Gerando outras…", e Ctrl+R não faz nada até terminar;
  - as três propostas viram cartões em espera (sem texto e fora da navegação por teclado); a sugestão da spec e "Outra resposta" continuam escolhíveis;
  - ao chegar, o leitor de tela ouve "3 novas sugestões".
- R4 · As novas propostas:
  - não repetem nenhuma proposta que já apareceu nesta pergunta (o pedido leva as anteriores ao Claude);
  - se uma proposta do Claude estava escolhida, ela fica no mesmo lugar com o selo "mantida", e só as outras duas são trocadas (marcadas "nova");
  - as novas valem até fechar o app: voltar à pergunta mostra o último conjunto.
- R5 · Se falhar, aparece "Não deu para gerar outras sugestões. As anteriores continuam aqui." com **Tentar de novo**, e as propostas anteriores voltam como estavam.
- R6 · Em 1100×700, as cinco opções rolam, e o cabeçalho e o rodapé ficam fixos (SPEC-059 R9).

## Fora do escopo

- Mudar a sugestão da spec ou o formato de "Perguntas em aberto".
- As perguntas do planner em "Conte a ideia" (Nova spec) e no Projeto.
- Guardar no disco as propostas do Claude.

## Design

### O que já existe

- `lib/features/specs/spec_answers.dart`: `questionOptionsPrompt` ("até duas respostas"), `questionOptionsSchema` (`maxItems: 2`), `parseQuestionOptions` (`take(2)`) e `SpecQuestionOptions.forQuestion` com cache por pergunta.
- `lib/features/specs/widgets/spec_questions_panel.dart`: `_alternatives(q)`, `_optionsOf(q)`, o teclado das perguntas (`_onKey`, teclas 1–9) e `_questionView`.
- `lib/features/specs/widgets/spec_questions_focus.dart`: `QuestionOptionCard`.

### Componentes

- **`SpecQuestionOptions`:** três propostas no prompt, no schema e no parse; `more(ws, specId, specText, q, {shown, keep})` pede um conjunto novo com as propostas já mostradas no prompt ("não repita estas") e troca o cache da pergunta.
- **`SpecQuestionsPanel`:** a linha "RESPOSTAS" com o botão, Ctrl+R no `_onKey`, os cartões em espera, a proposta mantida e a mensagem de erro.

### Testes

- Três propostas: o parse aceita três; o prompt e o schema pedem três; teclas 1–5.
- Ctrl+R: pede outras com as anteriores no pedido; funciona no campo de texto; desabilitado enquanto gera.
- Mantida: a escolhida fica no lugar e continua marcada; as outras duas são trocadas.
- Falha: a mensagem, "Tentar de novo" e as anteriores de volta.
- Voltar à pergunta mostra o último conjunto.
- Os testes da SPEC-028 e da SPEC-059 continuam passando.

## Decisões

- **"Randomizar" é pedir outras ao Claude.** Embaralhar as mesmas três não traz ideia nova; o que falta quando nenhuma serve é outro conjunto. O botão se chama "Outras sugestões" para dizer isso.
- **A escolhida fica.** Trocar tudo jogaria fora uma resposta que a pessoa já tinha marcado só para ver alternativas.
- **Ctrl+R.** Está livre no app, e não é atalho de edição de texto, então vale também no campo de "Outra resposta".
- **Sem limite de pedidos.** Cada pedido usa o mesmo orçamento da proposta inicial (`budgetUsd`); o botão desabilitado enquanto gera evita pedidos em fila.

## Plano

1. **t1 · Três sugestões e Outras sugestões** (R1–R6): prompt, schema e parse com três; `more` no `SpecQuestionOptions`; o botão, Ctrl+R, os cartões em espera, a mantida, o erro e os testes.

## Critérios de aceite

- [ ] Cada pergunta mostra três propostas do Claude, além da sugestão da spec.
- [ ] "Outras sugestões" (Ctrl+R) traz três propostas novas, sem repetir as anteriores.
- [ ] A resposta escolhida continua no lugar quando as outras são trocadas.
- [ ] Se falhar, as propostas anteriores continuam e dá para tentar de novo.
