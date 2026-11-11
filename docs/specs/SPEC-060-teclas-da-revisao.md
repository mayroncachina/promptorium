---
id: SPEC-060
status: aprovada
issue: 167
depende-de: SPEC-059
---

# Teclas na revisão das respostas e em "O que muda na spec"

## Objetivo

Na sessão de perguntas (SPEC-059), só as perguntas respondem ao teclado. Depois da última, ninguém mais:
- na revisão das respostas, não há tecla para aplicar, e Esc fecha a sessão inteira em vez de voltar às perguntas;
- em "O que muda na spec", salvar, voltar e descartar só funcionam com o mouse, e Esc também fecha tudo.

Esta spec leva o teclado até o fim da sessão: Esc volta uma tela, Enter faz a ação principal, Delete descarta e **Ctrl+Esc** fecha a sessão em qualquer tela.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/9WhAHpr7JUoYDfgUJ8Dkd5). Capturas em `docs/mockups/spec-060/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-antes.png` | A revisão de hoje: Esc fecha tudo e não há tecla para aplicar | — |
| `2-revisao.png` | Revisão com Esc e Enter nos botões, Fechar com Ctrl+Esc | R1, R2, R5 |
| `3-foco-no-botao.png` | Com o foco em "Editar", Enter aciona o botão | R2 |
| `4-o-que-muda.png` | "O que muda na spec" com Enter, Esc e Delete | R3, R4 |
| `5-descartar.png` | O primeiro Delete arma o descarte; o segundo descarta | R4 |
| `6-teclas.png` | Mapa das teclas de cada tela | R1–R6 |

## Requisitos

- R1 · Na revisão das respostas, **Esc** volta às perguntas, na última pergunta, como "Voltar às perguntas".
- R2 · Na revisão, **Enter** aplica as respostas, como "Aplicar N respostas na spec":
  - não faz nada quando não há resposta para aplicar (o botão está desabilitado);
  - com o foco num botão ("Editar", "Voltar às perguntas") ou na caixa "Atualizar requisitos e critérios", Enter aciona o que está focado, como nas perguntas (SPEC-059 t1).
- R3 · Em "O que muda na spec":
  - **Enter** salva na spec, como "Salvar na spec";
  - **Esc** volta à revisão, como "Voltar às respostas", e o diff já calculado fica guardado: voltar e avançar de novo sem mudar nada não roda o Claude outra vez;
  - num campo de texto (a busca do diff, SPEC-058), Enter e Esc são do campo.
- R4 · Em "O que muda na spec", **Delete** descarta, como "Descartar":
  - o primeiro Delete arma o botão: ele fica vermelho, com "Descartar mudanças? Delete de novo", e um aviso diz "Aperte Delete de novo em 3 s para descartar. As respostas continuam guardadas.";
  - um segundo Delete em até 3 s descarta e fecha a sessão; qualquer outra tecla, clique ou os 3 s passarem desarmam;
  - o clique em "Descartar" continua descartando direto, como hoje.
- R5 · **Ctrl+Esc** fecha a sessão em qualquer tela (perguntas, revisão, diff), e as respostas ficam guardadas como hoje:
  - nas perguntas, Esc continua fechando também;
  - o botão Fechar mostra "Ctrl Esc" e a dica diz "Fechar (Ctrl+Esc)";
  - enquanto o Claude aplica as respostas, nenhuma tecla fecha nem volta (como hoje com Esc).
- R6 · Os botões mostram a tecla ao lado do texto: "Voltar às perguntas · Esc", "Aplicar … · Enter", "Descartar · Delete", "Voltar às respostas · Esc", "Salvar na spec · Enter". Durante o salvar, Enter, Esc e Delete não fazem nada.

## Fora do escopo

- Teclas novas nas perguntas (SPEC-059 R5 continua como está).
- Mudar o que aplicar, salvar e descartar fazem (SPEC-028).
- Atalhos configuráveis em Ajustes.

## Design

### O que já existe

- `lib/features/specs/widgets/spec_questions_focus.dart`: `SpecQuestionsFocus._onKey` trata Esc e chama `onClose` em qualquer etapa; o cabeçalho tem o botão Fechar com `StepKbd('Esc')`.
- `lib/features/specs/widgets/spec_questions_panel.dart`: `_Stage.questions/review/applying/diff`, o teclado das perguntas (`_onKey`), e os rodapés de cada etapa com `spec-questions-previous`, `spec-questions-apply`, `spec-questions-discard`, `spec-questions-back` e `spec-questions-save`.
- `StepKbd`: a tecla desenhada no botão.

### Componentes

- **`SpecQuestionsPanel._onKey`:** passa a tratar Enter, Esc e Delete também nas etapas `review` e `diff`, devolvendo `handled` para que a moldura não feche.
- **`SpecQuestionsFocus._onKey`:** Ctrl+Esc fecha em qualquer etapa; Esc sozinho só fecha quando o painel não tratou a tecla (nas perguntas).
- **Descarte armado:** estado `_discardArmed` com um `Timer` de 3 s no painel; o botão troca de aparência e o aviso usa a região ao vivo para leitores de tela.

### Testes

- **Revisão:** Esc volta à última pergunta; Enter aplica; Enter com 0 respostas não faz nada; Enter com foco em "Editar" abre a pergunta.
- **Diff:** Enter salva; Esc volta à revisão sem rodar o Claude de novo; Delete uma vez arma e não fecha; Delete duas vezes descarta; Delete e depois outra tecla desarma; 3 s desarmam.
- **Fechar:** Ctrl+Esc fecha nas três telas e mantém as respostas; Esc ainda fecha nas perguntas; nenhuma tecla age durante o aplicar e o salvar.
- Os testes da SPEC-028 e da SPEC-059 continuam passando.

## Decisões

- **Esc volta, Ctrl+Esc fecha.** Na revisão e no diff, Esc fechar jogava fora o caminho até ali; voltar uma tela é o que se espera de Esc num fluxo de etapas. Ctrl+Esc está livre no GNOME (Alt+Esc e Ctrl+Alt+Esc são do sistema).
- **Esc ainda fecha nas perguntas.** Ali não há tela anterior, e é o que a SPEC-059 ensinou.
- **Delete pede duas vezes.** Descartar joga fora o diff que o Claude levou tempo para fazer, e Delete fica perto de teclas comuns. O clique continua direto, porque o botão já é uma ação deliberada.
- **Voltar do diff guarda o diff.** Sem isso, Esc seguido de Enter rodaria o Claude de novo por engano.

## Plano

1. **t1 · Teclas da revisão e do diff** (R1–R6): teclado nas etapas `review` e `diff`, Ctrl+Esc, descarte armado, teclas nos botões e testes.

## Critérios de aceite

- [ ] Na revisão, Esc volta às perguntas e Enter aplica as respostas.
- [ ] Em "O que muda na spec", Enter salva, Esc volta à revisão e Delete (duas vezes) descarta.
- [ ] Ctrl+Esc fecha a sessão em qualquer tela, com as respostas guardadas.
- [ ] Os botões mostram as teclas.
