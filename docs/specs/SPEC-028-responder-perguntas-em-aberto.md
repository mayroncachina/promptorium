---
id: SPEC-028
status: rascunho
depende-de: SPEC-023
---

# Responder as perguntas em aberto da spec

## Objetivo

A SPEC-023 trouxe a seção "Perguntas em aberto" e o diálogo que aparece ao aprovar uma spec com perguntas. Na prática, esse fluxo não funciona por dois motivos.

**1. O aprovador não entende o formato da seção.**

- O refino e o agente escrevem cada sugestão como um item próprio da lista, por exemplo "2. Sugestão: …". `SpecDocument.openQuestions` (`spec_file.dart:254`) conta todo item como pergunta.
- No caso real, uma spec com 4 perguntas abriu o diálogo "A spec tem 8 perguntas em aberto", com as sugestões numeradas como perguntas.
- "Aprovar assumindo premissas" levaria as 8 linhas para "Premissas", inclusive as sugestões.

**2. Não há onde responder as perguntas.**

- "Refinar com IA", no diálogo, abre uma conversa sobre a spec inteira.
- As respostas ficam espalhadas no chat. Nada registra qual pergunta foi respondida, com o quê, nem leva a resposta para os requisitos.
- A pessoa acaba aprovando com as perguntas abertas ou assumindo tudo como premissa.

Esta spec cria:

- um formato fixo para as perguntas, que o app interpreta;
- uma **sessão guiada** para responder, uma pergunta por vez, com opções;
- a aplicação das respostas à spec, com revisão do que muda antes de salvar.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/34u61ZSh51CmZtgncnaVHv). Cópia dos artboards e capturas em `docs/mockups/spec-028/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-aprovar-com-perguntas.png` | Diálogo de aprovação com as 4 perguntas e a sugestão de cada uma | R4, R5 |
| `2-sessao-uma-pergunta.png` | Sessão: uma pergunta por vez, com opções e resposta livre | R6–R8 |
| `3-revisar-respostas.png` | Revisão das respostas antes de aplicar | R9 |
| `4-o-que-muda-na-spec.png` | Diff das alterações na spec, antes de salvar | R10, R11 |
| `5-formato-antigo.png` | Aviso de sugestões contadas como perguntas, com "Corrigir formato" | R2, R3 |

## Requisitos

- R1 · A seção `## Perguntas em aberto` deve ter um formato fixo, que o modelo de spec (`specTemplate`), o prompt de refino (`refineSpecPrompt`) e o prompt `/spec` (`prompt_actions.dart:277`) passam a pedir:
  - cada pergunta é um item de primeiro nível `- P<n> · <pergunta>`;
  - a sugestão, quando houver, é um subitem `  - Sugestão: <texto>`;
  - o texto pode continuar em linhas recuadas.
- R2 · O sistema deve interpretar como pergunta só os itens de primeiro nível que não comecem com "Sugestão:", "Resposta:" ou "Opções:".
  - Quando um item de primeiro nível começar com "Sugestão:", ele deve ser lido como sugestão da pergunta anterior, sem ser contado.
  - No editor, as linhas que o R3 aponta ficam marcadas (fundo e fio âmbar à esquerda).
  - Perguntas sem o prefixo `P<n>` recebem um número pela ordem.
- R3 · Quando a seção não seguir o R1, o sistema deve mostrar o aviso "Em 'Perguntas em aberto', <N> itens são sugestões, não perguntas. A spec tem <M> perguntas, não <N+M>." com os botões:
  - "Corrigir formato" (secundário, para não competir com "Aprovar"), que reescreve a seção no formato do R1 sem mudar o texto das perguntas nem das sugestões;
  - "Responder perguntas".
- R4 · O diálogo de aprovação (SPEC-023 R6) deve ter:
  - o título "A <código> tem <M> perguntas em aberto", com a contagem do R2;
  - a lista com o número, o texto e a sugestão de cada pergunta;
  - os avisos de estrutura citados pelo nome (por exemplo, "R7 sem critério de aceite"), não só pela contagem;
  - os botões "Cancelar" (Esc), "Aprovar com as sugestões" e "Responder perguntas" (primário).
  - "Refinar com IA" sai deste diálogo.
- R5 · Quando a pessoa escolher "Aprovar com as sugestões", o sistema deve mover cada pergunta para `## Premissas`:
  - com sugestão: `- (assumida em <data>) P<n> · <pergunta> → <sugestão>`;
  - sem sugestão: `- (sem resposta, aceita em <data>) P<n> · <pergunta>`, como hoje.
- R6 · Quando a pessoa acionar "Responder perguntas" (no diálogo, no aviso do R3 ou no menu "Mais ações"), o sistema deve abrir ao lado do editor o painel "Responder perguntas". Ele mostra:
  - uma pergunta por vez;
  - uma trilha com P1, P2… e o estado de cada uma (respondida, atual, pendente ou para depois), sem depender só da cor: ícone de check para respondida e de relógio com borda tracejada para "para depois";
  - "Anterior", "Deixar para depois" e "Próxima".
- R7 · Para cada pergunta, o painel deve oferecer as opções em grupo de rádio:
  - uma nota curta, logo abaixo da pergunta, dizendo de onde vem cada opção;
  - a "Sugestão da spec" (quando houver), pré-selecionada;
  - até duas alternativas geradas pelo Claude a partir da spec, numa execução somente leitura, com o título e a consequência de cada uma;
  - "Outra resposta", com campo de texto.
  - Enquanto as alternativas são geradas, a sugestão e "Outra resposta" já podem ser usadas.
- R8 · As respostas dadas na sessão devem ficar guardadas por spec enquanto o app estiver aberto, para que fechar e reabrir o painel não as perca. Nada é gravado no arquivo antes do R11.
- R9 · Depois da última pergunta, o painel deve mostrar "Revise antes de aplicar", com:
  - para cada pergunta, o texto curto da pergunta e a resposta dada, com o selo "Para depois" nas não respondidas;
  - o botão "Mudar" em cada uma;
  - a caixa "Atualizar requisitos e critérios com as respostas" (marcada por padrão);
  - o botão "Aplicar <N> respostas".
- R10 · Ao aplicar, o sistema deve:
  - registrar cada resposta em `## Decisões` como `- P<n> · <resumo da resposta> (<data>)`;
  - tirar as perguntas respondidas de "Perguntas em aberto" e manter as deixadas para depois;
  - com a caixa do R9 marcada, rodar o Claude editando só esta spec para refletir as respostas nos requisitos e critérios de aceite.
  - Durante a execução, a spec segue o bloqueio da SPEC-025.
- R11 · Antes de salvar, o sistema deve mostrar o diff das alterações (o mesmo componente da SPEC-026, com número de linha e rótulo acessível "Linha adicionada"/"Linha removida") com um resumo em uma linha e os botões "Descartar", "Voltar às respostas" e "Salvar na spec" (primário). Só "Salvar na spec" grava o arquivo, sem mudar o status.
- R12 · O painel deve funcionar por teclado:
  - setas no grupo de rádio, Enter para "Próxima";
  - Esc fecha o painel, mantendo as respostas do R8;
  - foco visível;
  - anúncio de "Pergunta <n> de <M>" ao trocar de pergunta.

## Fora do escopo

- Responder perguntas por uma conversa livre no chat (o caminho de "Refinar com IA" continua existindo pelo cabeçalho).
- Perguntas em outras seções da spec ou em comentários.
- Votação ou respostas de mais de uma pessoa.
- Gerar perguntas novas: a sessão só trata as que estão na spec.

## Design

### O que já existe

- `lib/features/specs/spec_file.dart`:
  - `openQuestions` (l.254) junta itens `-` e numerados, mais as linhas que continuam o item anterior;
  - `withAssumptions(questions, at)` (l.275) esvazia a seção e escreve em `## Premissas`;
  - `specTemplate` (l.653) traz o comentário "Dúvidas sem resposta, uma por item".
- `lib/features/specs/specs_screen.dart`:
  - `showApproveChecksDialog` (l.190), com o enum `ApproveCheck { cancel, showWarnings, refine, assume, approve }`;
  - `_approve` (l.509);
  - `refineSpecPrompt` (l.54).
- `lib/features/specs/spec_lint.dart`: `SpecWarning` e `lintSpec`, que alimentam a faixa de avisos `SpecWarningsBar`.
- `lib/core/claude/readonly_run.dart`: `runReadOnlyClaude`, com `--json-schema` e `structuredOutput`, como em `SpecDesigner`.
- SPEC-025: `SpecActionState` para o bloqueio. SPEC-026: `DiffView` e `lineDiff`.

### R1–R3 · Formato e leitura

- **Modelo `OpenQuestion`** (`id`, `text`, `suggestion?`): `openQuestions` passa a devolver `List<OpenQuestion>`.
  - O parser usa o recuo para separar pergunta e subitens.
  - "Sugestão:" no primeiro nível vai para a pergunta anterior (R2).
- **Aviso:** `lintSpec` ganha `SpecWarning(kind: openQuestionsFormat)` quando houver sugestão de primeiro nível ou item sem `P<n>`.
- **"Corrigir formato":** `SpecDocument.withOpenQuestions(List<OpenQuestion>)` reescreve a seção.
- **Prompts e modelo:** `specTemplate` muda o comentário para mostrar o formato. `refineSpecPrompt` e o prompt `/spec` pedem "cada pergunta como `- P<n> · …`, com a sugestão num subitem `- Sugestão: …`".

### R4–R5 · Diálogo de aprovação

- `showApproveChecksDialog` recebe `List<OpenQuestion>`. `ApproveCheck.refine` é trocado por `ApproveCheck.answer`.
- `withAssumptions` aceita `OpenQuestion` e escreve a forma com sugestão do R5.

### R6–R9 · Painel da sessão

- `SpecQuestionsPanel` (`lib/features/specs/widgets/spec_questions_panel.dart`), na mesma área do painel lateral de etapas, com largura de 440 px.
- `specAnswersProvider` (`Notifier<Map<int, Map<String, Answer>>>`, por id da spec), onde `Answer` é `{option, text, deferred}` (R8).
- **Alternativas (R7):** `QuestionOptions.generate(spec, question)` roda `runReadOnlyClaude` com o esquema `{options: [{title, consequence}] (máx. 2)}` e a spec no prompt. O resultado fica em cache por (spec, P<n>, hash do texto).

### R10–R11 · Aplicar e revisar

- **Passo determinístico:** `SpecDocument.withAnswers(answers, at)` escreve `## Decisões` (cria a seção antes de "Perguntas em aberto" se faltar) e tira as perguntas respondidas.
- **Requisitos (caixa marcada):** `SpecAnswerApplier.apply(spec, textoComDecisões, answers)` roda o Claude com permissão de editar só o arquivo da spec, numa cópia temporária, e devolve o texto final. O mesmo padrão de execução somente leitura com saída estruturada vale aqui: o texto vem em `structuredOutput.markdown`, e o app não deixa o agente gravar direto.
- O painel mostra `DiffView(lineDiff(atual, final))`. "Salvar na spec" chama `specServiceProvider.save` e atualiza o editor. Se o editor estiver sujo, segue o mesmo padrão de `_approveScreen`.

## Critérios de aceite

- [ ] O modelo de spec, o prompt de refino e o `/spec` pedem o formato `- P<n> · …` com `- Sugestão:` em subitem [R1] verificar: flutter test test/features/specs/spec_file_test.dart test/features/prompt
- [ ] Uma seção com 4 perguntas e 4 sugestões numeradas é lida como 4 perguntas com sugestão [R2] verificar: flutter test test/features/specs/spec_file_test.dart
- [ ] O formato antigo gera o aviso; "Corrigir formato" reescreve a seção sem mudar os textos [R3] verificar: flutter test test/features/specs/spec_lint_test.dart test/features/specs/spec_file_test.dart
- [ ] O diálogo de aprovação mostra "4 perguntas", a sugestão de cada uma e os botões "Cancelar", "Aprovar com as sugestões" e "Responder perguntas" [R4] verificar: flutter test test/features/specs/specs_screen_test.dart
- [ ] "Aprovar com as sugestões" grava em Premissas a pergunta com a sugestão e a data [R5] verificar: flutter test test/features/specs/spec_file_test.dart
- [ ] "Responder perguntas" abre o painel na primeira pergunta, com a trilha de estados e a navegação [R6] verificar: flutter test test/features/specs/spec_questions_panel_test.dart
- [ ] O painel mostra a sugestão pré-selecionada, até duas alternativas do Claude e "Outra resposta"; a sugestão funciona antes das alternativas chegarem [R7] verificar: flutter test test/features/specs/spec_questions_panel_test.dart
- [ ] Fechar e reabrir o painel mantém as respostas, e o arquivo não muda [R8] verificar: flutter test test/features/specs/spec_questions_panel_test.dart
- [ ] A revisão lista as respostas, permite mudar uma e mostra a caixa de atualizar requisitos [R9] verificar: flutter test test/features/specs/spec_questions_panel_test.dart
- [ ] Aplicar grava as decisões, tira só as perguntas respondidas e, com a caixa marcada, devolve o texto do Claude sem gravar [R10] verificar: flutter test test/features/specs/spec_file_test.dart test/features/specs/spec_answer_applier_test.dart
- [ ] O diff aparece antes de salvar; "Descartar" não muda o arquivo e "Salvar na spec" grava sem mudar o status [R11] verificar: flutter test test/features/specs/spec_questions_panel_test.dart
- [ ] O painel funciona por teclado e anuncia a pergunta atual [R12] verificar: flutter test test/features/specs/spec_questions_panel_test.dart
- [ ] Os testes atuais de specs continuam passando [R2] [R4] verificar: flutter test test/features/specs
- [ ] A análise estática passa sem avisos novos [R1] [R2] [R3] [R4] [R5] [R6] [R7] [R8] [R9] [R10] [R11] [R12] verificar: flutter analyze

## Perguntas em aberto

- P1 · As alternativas do Claude (R7) devem ser geradas para todas as perguntas ao abrir a sessão, ou só quando a pessoa chega em cada uma?
  - Sugestão: ao chegar em cada uma, com a próxima já em pré-carga.
- P2 · As respostas da sessão (R8) devem sobreviver a fechar o app?
  - Sugestão: não, enquanto não houver pedido; elas só valem até aplicar.
- P3 · "Aprovar com as sugestões" deve exigir que toda pergunta tenha sugestão, ou mistura sugestões e "sem resposta"?
  - Sugestão: misturar, como descrito no R5.
