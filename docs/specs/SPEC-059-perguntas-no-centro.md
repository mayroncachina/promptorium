---
id: SPEC-059
status: aprovada
depende-de: SPEC-028
issue: 146
---

# Perguntas da spec no centro

## Objetivo

"Responder perguntas" (SPEC-028) abre num painel de 430 px à direita do editor. Por isso:
- a pergunta fica espremida em várias linhas;
- as opções ficam com o texto apertado, e "Outra resposta" some abaixo da dobra;
- o texto da spec aparece cortado atrás do painel e não ajuda a responder.

Esta spec leva a sessão de perguntas para o **centro da tela**, numa coluna de 720 px que ocupa a área toda. A pergunta fica grande, as opções têm espaço, o teclado responde, e o trecho da spec aparece só quando a pessoa pede. O comportamento de responder, revisar e aplicar continua o da SPEC-028.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/4RYhjRD9hT3WdV16uQf7sQ). Capturas em `docs/mockups/spec-059/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-antes.png` | O painel à direita de hoje | — |
| `2-no-centro.png` | A pergunta no centro, com as opções e o rodapé | R1–R5 |
| `3-outra-resposta.png` | "Outra resposta" com o campo crescendo e o ditado | R6 |
| `4-ver-na-spec.png` | O trecho da spec aberto junto da pergunta | R7 |
| `5-revisar.png` | Revisão das respostas no centro | R8 |
| `6-estreito.png` | 1100×700 | R9 |

## Requisitos

- R1 · "Responder perguntas" (do diálogo de aprovação, do aviso de formato ou do cabeçalho da spec) abre a **sessão de perguntas** no centro:
  - ela cobre a área à direita da barra lateral, sobre a lista de specs e o editor;
  - o cabeçalho mostra "Responder perguntas", "<código> · <título> · pergunta x de n", "salvo automaticamente" e **Fechar** (Esc).
- R2 · O conteúdo fica numa coluna de 720 px, centralizada:
  - as etapas P1…Pn no topo (respondida com ✓ em teal, deixada para depois com relógio e borda tracejada, atual em âmbar), que podem ser clicadas;
  - a pergunta em 22 px, peso 600, com o número em âmbar;
  - abaixo, a linha "A primeira opção é a sugestão escrita na spec; as outras foram propostas pelo Claude." e o link **Ver na spec**.
- R3 · As opções são cartões largos com rádio, título (14,5 px), descrição e a tecla (1, 2, 3…):
  - a sugestão da spec leva o selo "Sugestão da spec";
  - a última opção é sempre **Outra resposta**, com o campo dentro do cartão.
- R4 · O rodapé fica fixo na base da área, alinhado à coluna: **Anterior**, **Deixar para depois** e **Próxima** (primário, Enter). Na última pergunta, o primário vira **Revisar respostas**.
- R5 · Teclado:
  - 1…9 escolhem a opção (fora do campo de texto);
  - Enter vai para a próxima;
  - ←/→ ou Alt+←/→ trocam de pergunta;
  - Esc fecha, e as respostas continuam salvas como hoje.

  O foco começa na opção marcada.
- R6 · Outra resposta:
  - escolher a opção põe o foco no campo, que cresce até 6 linhas e depois rola;
  - o botão **Ditar** usa o ditado por voz da SPEC-040;
  - Enter quebra a linha dentro do campo, e Ctrl+Enter vai para a próxima.
- R7 · Ver na spec:
  - abre, entre a pergunta e as opções, o trecho da seção "Perguntas em aberto" em volta da pergunta, com as linhas dela destacadas (fio âmbar à esquerda) e o número das linhas;
  - **Esconder trecho** fecha;
  - a escolha vale para as próximas perguntas até fechar a sessão.
- R8 · As telas seguintes da SPEC-028, revisar as respostas e ver o que muda na spec, também abrem na coluna central:
  - a revisão mostra cada pergunta com a resposta e **Editar**;
  - o diff ocupa a largura da área (até 1100 px).
- R9 · Em janelas estreitas, a coluna usa a largura disponível menos 32 px de cada lado, até 720 px. As opções rolam, e o cabeçalho e o rodapé ficam fixos.
- R10 · Movimento e acessibilidade:
  - a sessão entra com fade e um leve deslocamento (180 ms) e troca de pergunta com crossfade (120 ms); com movimento reduzido, a troca é direta;
  - a sessão é um diálogo com rótulo e foco preso;
  - as opções formam um grupo de rádio;
  - a troca de pergunta é anunciada ("Pergunta 3 de 4").

## Fora do escopo

- Mudar as perguntas, o formato da seção ou o que "Aplicar respostas" faz (SPEC-028).
- As perguntas do planner em "Conte a ideia" (Nova spec) e no Projeto.

## Design

### O que já existe

- `lib/features/specs/widgets/spec_questions_panel.dart`: `SpecQuestionsPanel`, com as etapas, as opções, "Outra resposta", Anterior/Deixar para depois/Próxima, revisar e aplicar.
- `lib/features/specs/specs_screen.dart`, por volta da linha 1889: onde o painel entra ao lado do editor.
- `lib/features/specs/spec_answers.dart`: `Answer` e a gravação das respostas.
- `lib/features/specs/spec_file.dart`: `OpenQuestion` e as linhas de cada pergunta.
- O ditado da SPEC-040 (botão de microfone do composer).

### Componentes

- **`SpecQuestionsFocus`** (novo, `lib/features/specs/widgets/spec_questions_focus.dart`): a moldura em tela cheia (cabeçalho, coluna, rodapé fixo, `FocusScope`, atalhos). Hospeda o conteúdo atual do painel.
- **`SpecQuestionsPanel`:** o conteúdo é separado em partes reaproveitáveis (`QuestionSteps`, `QuestionOptions`, `QuestionFooter`, `AnswersReview` e `AnswersDiff`) com tamanhos e tipografia do R2 e R3. O estado e a gravação não mudam.
- **`QuestionExcerpt`** (novo): o trecho da spec a partir das linhas da `OpenQuestion`.
- **`specs_screen.dart`:** em vez do painel lateral, põe a `SpecQuestionsFocus` num `Stack` por cima da área. Fechar volta o editor como estava.

### Testes

- **Abertura:**
  - "Responder perguntas" abre a sessão no centro;
  - a coluna tem 720 px em 1440×900;
  - o rodapé fica visível com as opções rolando.
- **Teclado:**
  - 1–4 escolhem;
  - Enter avança;
  - ←/→ trocam;
  - Esc fecha e mantém as respostas;
  - Ctrl+Enter no campo livre avança.
- **Ver na spec:** o trecho certo com as linhas destacadas, e a escolha mantida entre as perguntas.
- **Revisar e diff:** na coluna, com Editar levando à pergunta.
- **Estreito:** 1100×700 sem sobreposição.
- **Movimento reduzido:** sem animação.
- Os testes da SPEC-028 continuam passando (o fluxo é o mesmo).

## Decisões

- **Tela cheia na área de trabalho.** Responder exige atenção; a spec inteira atrás só competia com a pergunta. O trecho que importa aparece em "Ver na spec".
- **720 px.** Dá 70 a 80 caracteres por linha na pergunta e nas descrições, a medida confortável de leitura.
- **Reaproveitar o painel.** O estado e a gravação da SPEC-028 ficam como estão; só muda onde e como aparecem.
- **t1 · Teclas.** ←/→ trocam de pergunta como um clique na etapa: não gravam a sugestão pré-selecionada (só "Próxima" grava) e não fazem nada na primeira e na última pergunta. Enter só vale "Próxima" com o foco numa opção ou na coluna; num botão focado, Enter aciona o botão. Com o foco numa opção, ←/→ trocam de pergunta, e ↑/↓ continuam andando entre as opções.
- **t1 · Crossfade.** A pergunta nova entra com fade de 120 ms e a anterior sai na hora. Duas cópias da pergunta ao mesmo tempo dividiriam os mesmos nós de foco dos rádios e o mesmo campo de texto.
- **t1 · "salvo automaticamente".** As respostas continuam só em memória até "Salvar na spec" (SPEC-028 P2); a dica do texto diz isso.
- **t1 · Partes.** `QuestionSteps`, `QuestionOptionCard` e `QuestionFooter` ficam em `spec_questions_focus.dart`, junto da moldura. O estado continua em `SpecQuestionsPanel`. O link "Ver na spec" entra na t2, com o trecho.
- **t2 · Ditar fica de fora.** O ditado da SPEC-040 não está na `main`: o PR #91 foi mesclado na branch da SPEC-039 depois que ela já tinha entrado na `main`, e `lib/features/dictation/` só existe em `origin/spec/039-nova-spec-com-planejamento`. Trazer o ditado (modelos, gravação, whisper-cli, ajustes) não cabe nesta spec. O cartão de "Outra resposta" já tem o lugar do botão (`QuestionOptionCard.trailing`); o botão entra quando a SPEC-040 chegar à `main`. Por isso o critério de "Outra resposta" segue aberto.
- **t2 · Foco de "Outra resposta".** Escolher a opção com clique, tecla 4 ou clique no campo põe o foco no campo. Com ↑/↓ o foco fica no rádio, para continuar andando entre as opções. Escolher outra opção com o foco no campo leva o foco para ela, e Enter volta a ser "Próxima". O campo tem 3 linhas quando escolhido e cresce até 6.
- **t2 · Trecho.** O trecho vem do texto do editor (`SpecDocument.questionExcerpt`): as linhas da pergunta (até a próxima pergunta, sem as linhas em branco) e até 2 linhas antes e depois, dentro da seção. Os números são os do arquivo, os mesmos do editor.
- **t3 · Revisão.** "Revise as respostas" segue o mockup (cartão por pergunta, resposta com ✓ ou relógio, **Editar**) e mantém o que a SPEC-028 pede: o selo "Para depois", a caixa "Atualizar requisitos e critérios" marcada e a contagem no botão ("Aplicar 2 respostas na spec"). A pergunta deixada para depois diz "Continua em Perguntas em aberto.", como faz o aplicar da SPEC-028. O texto do mockup, "vai para Premissas", não vale aqui.
- **t3 · Diff.** "O que muda na spec" fica na mesma moldura, com a coluna de até 1100 px (menos 32 px de cada lado em janelas estreitas) e o rodapé alinhado a ela. O subtítulo do cabeçalho diz "… · o que muda na spec · nada foi salvo ainda".

## Plano

1. **t1 · Sessão no centro** (R1–R5, R9, R10): `SpecQuestionsFocus`, separação do painel em partes, nova tipografia, rodapé fixo, teclado, regra de largura, movimento e testes.
2. **t2 · Outra resposta e trecho da spec** (R6, R7): campo que cresce, Ditar, Ctrl+Enter, `QuestionExcerpt` e testes.
3. **t3 · Revisar e diff no centro** (R8): revisão e diff na coluna e testes; conferir os testes da SPEC-028.

## Critérios de aceite

- [x] "Responder perguntas" abre a pergunta no centro da tela, numa coluna de 720 px.
- [x] As teclas 1–4 escolhem a opção e Enter vai para a próxima.
- [ ] "Outra resposta" cresce com o texto e aceita ditado.
- [x] "Ver na spec" mostra o trecho da pergunta sem sair da tela.
- [x] A revisão e o diff também ficam no centro.
- [x] Esc fecha e as respostas continuam salvas.
- [x] Em 1100×700 o rodapé fica fixo e nada se sobrepõe.
