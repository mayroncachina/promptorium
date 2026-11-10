---
id: SPEC-058
status: aprovada
depende-de: SPEC-026
issue: 145
---

# Item da sessão ampliado

## Objetivo

Na tela Sessões, clicar num item da linha do tempo (Bash, Write, Edit, Read…) abre o resultado dentro do próprio cartão. Isso tem três problemas:
- o cartão tem no máximo 640 px;
- a saída é cortada em 40 linhas;
- a lista de sessões e o painel de detalhes continuam ocupando cerca de 600 px.

Uma saída de teste com erro ou um diff de 50 linhas não cabem.

Esta spec faz o clique abrir o item **ocupando a largura toda da área de trabalho**, com a saída inteira, busca e navegação entre os itens. **Fechar (Esc)** volta ao layout de antes, no mesmo ponto.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/UidCnsDRBFHZxR11ytoMfQ). Capturas em `docs/mockups/spec-058/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-antes.png` | O cartão aberto hoje, cortado em 40 linhas | — |
| `2-bash-ampliado.png` | Bash ampliado, com a busca aberta | R1–R5 |
| `3-edit-ampliado.png` | Edit com o diff lado a lado | R6 |
| `4-write-ampliado.png` | Write com o arquivo e "Abrir no Código" | R7 |
| `5-fechar.png` | De volta ao layout, com o cartão destacado, e as etapas do movimento | R8, R9 |
| `6-estreito.png` | 1100×700 | R10 |

## Requisitos

- R1 · Clicar num cartão de ferramenta já concluído ou negado (ou Enter com ele em foco) abre a **visão ampliada**:
  - ela cobre a área à direita da barra lateral, a lista, a sessão e o painel;
  - a barra de título e o rodapé do app continuam visíveis;
  - em sessões lado a lado, cobre os dois painéis.

  Um cartão que ainda está executando também abre, e a saída vai aparecendo ao vivo.
- R2 · O cabeçalho da visão ampliada mostra:
  - o nome da ferramenta, na cor dela, e o alvo (comando ou caminho);
  - o resultado ("1 falhou", "+9 −3", "arquivo novo"…), a duração e o número de linhas;
  - os botões **Anterior** e **Próxima** (↑/↓ ou K/J);
  - **Copiar**;
  - **Fechar** (Esc).
- R3 · Anterior e Próxima trocam para o item vizinho da linha do tempo da mesma sessão, sem fechar. Nos limites, o botão fica desabilitado.
- R4 · A saída aparece inteira, sem o corte de 40 linhas:
  - com números de linha e fonte mono de 12,5 px;
  - rolagem vertical, e horizontal quando "Quebrar linhas" está desligado (padrão: desligado para Bash, ligado para texto);
  - saídas com mais de 5.000 linhas usam uma lista virtualizada.
- R5 · Buscar (Ctrl+F na visão ampliada):
  - abre uma barra de busca no canto, com o contador "x de n" e anterior/próxima (Enter e Shift+Enter);
  - as ocorrências ficam marcadas em âmbar;
  - Esc fecha a busca antes de fechar a visão.
- R6 · Edit / MultiEdit:
  - abas **Lado a lado** (padrão quando a área tem pelo menos 1000 px) e **Unificado**;
  - o diff lado a lado alinha as linhas e preenche os vazios com hachura;
  - o botão **Abrir no Código** abre o arquivo na tela Código, na primeira linha alterada.
- R7 · Write e Read:
  - aba **Conteúdo** com o arquivo e números de linha. No Read, as linhas lidas (`offset`/`limit`) ficam destacadas;
  - aba **Diff** no Write, quando havia arquivo antes;
  - Abrir no Código.

  Outras ferramentas (Grep, Glob, WebFetch, Task…) mostram a entrada e a saída em texto, nas abas **Saída** e **Entrada**.
- R8 · Fechar:
  - a visão some e o layout volta como estava: lista, painel e a mesma rolagem da linha do tempo;
  - o cartão que estava aberto (ou o último navegado com Anterior e Próxima) recebe o foco e um destaque âmbar que some em 1,2 s;
  - a rolagem leva o cartão para a área visível, se preciso.
- R9 · Movimento:
  - a visão cresce a partir do retângulo do cartão (220 ms, `AppMotion.enter`) e encolhe de volta ao fechar (160 ms);
  - com movimento reduzido, a troca é direta.
- R10 · Em janelas estreitas (abaixo de 1200 px de área), Anterior, Próxima e Copiar viram só ícones, com tooltip, e o Edit abre no modo Unificado.
- R11 · Acessibilidade:
  - a visão é um diálogo com rótulo "<ferramenta> ampliado" e prende o foco do Tab;
  - ao abrir, o foco vai para o texto; ao fechar, volta ao cartão;
  - os botões de ícone têm rótulo.

## Fora do escopo

- Editar o arquivo na visão ampliada (para isso existe Abrir no Código).
- Ampliar mensagens de texto do agente.
- Ampliar itens no Prompt (pode reaproveitar o componente depois).

## Design

### O que já existe

- `lib/features/sessions/widgets/timeline_view.dart`: `ToolCard`, que abre no lugar, com `_open`, `DiffView`, `editDiffOf` e o corte de 40 linhas.
- `lib/features/sessions/sessions_screen.dart`: o layout de lista, `_SessionMain` e painel, e o lado a lado.
- `lib/ui/widgets/diff_view.dart`: `DiffView` (unificado), com `scrollable`.
- `lib/features/sessions/edit_diff.dart`: `EditInfo`, `editDiffOf` e `isEditTool`.
- `lib/ui/theme/motion.dart`: `AppMotion`.
- A navegação para a tela Código com arquivo e linha (`code` section, usada por "abrir arquivo").

### Componentes

- **`ToolExpandedController`** (novo, `lib/features/sessions/tool_expanded.dart`): um Notifier com a sessão, o id da ferramenta aberta e o retângulo de origem. Expõe `open`, `next`, `previous` e `close`.
- **`ToolExpandedView`** (novo, `lib/features/sessions/widgets/tool_expanded_view.dart`):
  - o cabeçalho, as abas e o corpo de cada tipo de ferramenta;
  - a barra de busca;
  - a navegação pelo teclado (`Shortcuts`/`Actions`) e o `FocusScope`.
- **`SideBySideDiffView`** (novo, em `diff_view.dart`): o alinhamento das linhas a partir das mesmas `DiffRow`.
- **`NumberedTextView`** (novo): o texto com números de linha, marcações da busca, quebra opcional e virtualização.
- **`SessionsScreen`:** um `Stack` que põe a `ToolExpandedView` por cima da área (com a transição do R9). A rolagem da linha do tempo e o `FocusNode` dos cartões continuam montados por baixo, para o R8.
- **`ToolCard`:** o clique chama `open` com o `RenderBox` do cartão; o destaque de volta usa um `AnimationController` de 1,2 s.

### Testes

- **`ToolExpandedController`:** open, next, previous nos limites, close.
- **Visão:**
  - Bash mostra a saída inteira (mais de 40 linhas);
  - Ctrl+F acha e conta as ocorrências;
  - Esc fecha a busca e depois a visão;
  - ↑/↓ e J/K navegam.
- **Edit:** lado a lado com linhas alinhadas, Unificado e Abrir no Código.
- **Write e Read:** conteúdo e linhas destacadas.
- **Fechar:** o layout volta, o cartão tem foco e destaque, e a rolagem é a mesma.
- **Movimento reduzido:** sem animação.
- **Estreito:** botões só com ícone e Edit unificado.

## Decisões

- **O clique abre direto a visão ampliada.** A prévia no cartão some, porque mostrava um pedaço e a pessoa sempre precisava rolar ou adivinhar. O cartão continua mostrando o resumo (resultado, +/−).
- **Cobre a área da sessão, não a janela.** A barra lateral e o topo ficam, para a pessoa não se perder e poder trocar de tela.
- **Por cima, não no lugar da linha do tempo.** Manter a linha do tempo montada por baixo é o que permite voltar com a mesma rolagem e o foco no cartão.

## Plano

1. **t1 · Visão ampliada e navegação** (R1–R3, R8, R9, R11): `ToolExpandedController`, `ToolExpandedView` com cabeçalho, Copiar, Anterior/Próxima, Fechar, a transição, a volta ao cartão e testes.
2. **t2 · Texto inteiro e busca** (R4, R5, R7): `NumberedTextView` com números de linha, quebra, virtualização, busca e corpos de Bash, Write, Read e outras, e testes.
3. **t3 · Diff lado a lado e janela estreita** (R6, R10): `SideBySideDiffView`, abas do Edit, Abrir no Código, regras de largura e testes.

## Critérios de aceite

- [ ] Clicar num Bash abre a saída inteira ocupando a área toda; Esc volta ao layout com o cartão em foco.
- [ ] ↑/↓ passam para o item vizinho sem fechar.
- [ ] Ctrl+F acha o texto na saída e mostra "x de n".
- [ ] Um Edit abre com o diff lado a lado; Abrir no Código leva à linha alterada.
- [ ] Write e Read mostram o arquivo com números de linha.
- [ ] Com movimento reduzido, a visão abre e fecha sem animação.
- [ ] Em 1100×700 nada fica cortado.
