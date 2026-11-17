---
id: SPEC-077
status: aprovada
tipo: melhoria
issue: 266
---

# Copiar código

## Objetivo

Quando o Claude responde com uma query, um script ou um trecho de código, a pessoa quer levar aquilo para outro lugar: o DBeaver, o terminal, o editor. Hoje isso dá trabalho. Não existe botão de copiar no bloco, e a seleção com o mouse se perde no meio do caminho. A query é grande, a pessoa seleciona uma parte, rola, segue selecionando, e o que já estava marcado desmarca.

A causa está no `flutter_markdown_plus` (1.0.12). Com `MarkdownBody(selectable: true)`, o construtor cria um `SelectableText.rich` separado para cada parágrafo, item de lista e bloco de código (`_buildRichText` em `builder.dart`). Cada um tem a sua seleção. Clicar ou arrastar dentro de outro bloco desmarca o anterior, então não dá para selecionar do meio de um parágrafo até a sexta linha da query. O bloco de código é ainda um `SingleChildScrollView` horizontal à parte.

Esta spec:
- põe uma **barra em todo bloco de código**, com a linguagem e o botão **Copiar**, que copia o bloco inteiro e exato;
- troca a seleção por bloco por **uma seleção por mensagem** (`SelectionArea`), que atravessa parágrafos, listas e blocos;
- dá **realce de sintaxe** aos blocos, com o `re_highlight` que o app já usa;
- **recolhe os blocos longos** na timeline, com "Mostrar as outras N linhas";
- acrescenta **"Copiar mensagem"** às respostas e **"Copiar comando"** ao card Bash.

Tudo isso vale para qualquer markdown que o app mostra: respostas nas Sessões e no Prompt, plano pronto, a spec na tela Specs e as outras pré-visualizações.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/XskeXq2BEUmcC9to3S126q). Capturas em `docs/mockups/spec-077/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-prompt.png` | Resposta no Prompt com uma query SQL. O botão aparece normal, em hover (com a dica) e em "Copiado", e há o "Copiar mensagem" no cabeçalho | R1–R5, R7, R11 |
| `2-selecao.png` | Hoje e depois: a seleção do meio do parágrafo até a 6ª linha da query, e o texto que vai para a área de transferência | R6 |
| `3-outros-lugares.png` | O mesmo bloco na spec da tela Specs (hover, foco pelo teclado, bloco sem linguagem), o "Copiar comando" no card Bash e o bloco dentro do plano pronto | R1, R9, R10, R11 |
| `4-bloco-longo.png` | Query de 40 linhas recolhida e expandida | R8 |

Issue: [#266](https://github.com/mayroncachina/promptorium/issues/266)

## Requisitos

### O bloco de código

- R1 · **Barra do bloco.** Todo bloco de código do markdown, cercado (```` ``` ```` ou `~~~`) ou indentado, ganha uma barra no topo. À esquerda fica a linguagem como escrita na cerca, em minúsculas e em mono (`sql`, `bash`, `dart`); sem linguagem, aparece `texto`. A partir de 3 linhas, a barra mostra também "· N linhas". À direita fica o botão **Copiar**, com ícone e texto, sempre visível. Com o mouse sobre o bloco, a borda do bloco e o botão ganham mais contraste. A dica do botão diz "Copiar o código (N linhas)".
- R2 · **Copiar copia o bloco exato.** Vai para a área de transferência só o conteúdo entre as cercas. Ficam de fora as cercas, o nome da linguagem e a barra, e não há números de linha. A indentação, as tabulações, as linhas em branco e os espaços do fim da linha ficam como o Claude escreveu. Sai só a quebra de linha final que o parser acrescenta. Num bloco dentro de lista ou citação, a indentação do markdown sai, como o parser já faz. O que se copia é sempre o bloco inteiro, recolhido ou não (R8).
- R3 · **Retorno "Copiado".** Depois de copiar, o botão vira "✓ Copiado" em teal por 1,5 s e depois volta a "Copiar". Outro clique nesse tempo copia de novo e reinicia o tempo. O leitor de tela anuncia "Código copiado". O bloco não mostra toast, porque o próprio botão já é o retorno. O "Copiado" usa ícone e texto, e não só a cor.
- R4 · **Teclado.** O botão Copiar entra na ordem do Tab, depois do texto que vem antes do bloco. Enter ou Espaço copiam. O foco mostra o anel âmbar claro (`amberLight`) do app. O rótulo semântico é "Copiar código SQL, 17 linhas" (a linguagem e as linhas do bloco).
- R5 · **Realce de sintaxe.** O código do bloco ganha as cores do `re_highlight` com o tema do editor (`promptoriumCodeTheme`), as mesmas do editor de Código e do diff. A linguagem sai da cerca por uma tabela de apelidos: `sql`, `postgres`, `postgresql`, `psql`, `mysql`, `sqlite` → SQL; `sh`, `bash`, `zsh`, `shell`, `console` → Shell; `js`, `jsx`, `ts`, `tsx`, `py`, `yml`, `jsonc`, `html`, `toml` e os nomes de `CodeLanguage`. Uma linguagem desconhecida, ou um bloco sem linguagem, fica sem realce, na cor do texto. O realce é calculado uma vez por bloco, com cache por linguagem e texto, e nunca a cada frame. Acima de 2.000 linhas, o bloco fica sem realce.

### Seleção e mensagem

- R6 · **Uma seleção por mensagem.** Cada mensagem do Claude, e cada documento em markdown (a spec, o plano, a skill, as Novidades), fica dentro de um único `SelectionArea`, e o `MarkdownBody` deixa de ser `selectable`. A seleção com o mouse atravessa parágrafos, títulos, listas, tabelas e blocos de código sem desmarcar o que já estava marcado. Ctrl+C e o menu de contexto ("Copiar", "Selecionar tudo") copiam o trecho marcado. As linhas de um bloco de código chegam com as quebras e a indentação. A barra do bloco (R1) e a barra de baixo (R8) ficam fora da seleção (`SelectionContainer.disabled`) e não entram no texto copiado. A seleção de uma mensagem não se perde quando chegam itens novos na timeline.
- R7 · **Copiar mensagem.** No cabeçalho de cada resposta do Claude ("Claude · 14:04"), aparece um botão de ícone "Copiar mensagem" quando o mouse está sobre a mensagem ou o foco está dentro dela. Ele copia o markdown da resposta como o Claude escreveu, com as cercas, e dá o mesmo retorno do R3: o ícone vira ✓ e o anúncio é "Mensagem copiada". No Prompt, o botão "Copiar" que já existe embaixo da última resposta continua.

### Blocos longos

- R8 · **Recolher na timeline.** Nas respostas da timeline (Sessões, Prompt e a janela ao vivo da etapa), um bloco com mais de 24 linhas chega recolhido. Ele mostra as 16 primeiras linhas, com um degradê no fim, e um botão "Mostrar as outras N linhas". Expandido, o bloco ganha uma barra embaixo com "Recolher" e um segundo **Copiar**, para não ter de voltar ao topo. O botão anuncia o estado (`aria-expanded`, ou o `Semantics` equivalente). Cada bloco guarda o próprio estado enquanto a conversa está aberta, e esse estado não é salvo. O bloco não tem rolagem vertical própria, porque a timeline já rola. As linhas largas rolam na horizontal, como hoje, com a barra de rolagem, e a query não quebra linha. Fora da timeline (tela Specs, plano pronto, pré-visualizações, Sobre), o bloco nunca recolhe.

### Onde vale

- R9 · **Card Bash.** No card de ferramenta da timeline, um `Bash` mostra um botão de ícone "Copiar comando" quando o mouse está sobre o card ou o foco está nele. O botão fica antes da duração. Ele copia o `command` da ferramenta inteiro e exato, sem a saída, e dá o retorno do R3. A visão ampliada (SPEC-058), que já tem Copiar, não muda.
- R10 · **Um componente só.** Todos os usos de `MarkdownBody` passam a usar o mesmo componente, com o bloco de código dos R1–R5 e a seleção do R6:
  - as respostas da timeline (`timeline_view.dart`, `_AssistantText`), que valem para as Sessões, o Prompt e a janela ao vivo da etapa (`step_live_dialog.dart`), com recolher (R8);
  - o plano pronto (`plan_ready.dart`);
  - a pré-visualização da spec na tela Specs (`specs_screen.dart`);
  - a spec da resposta (`answer_spec_bar.dart`) e a pré-visualização em lote (`spec_batch_dialog.dart`);
  - a pré-visualização da skill (`installed_view.dart`);
  - as Novidades do Sobre (`about_dialog.dart`).
- R11 · **Tema.** O bloco usa os tokens do app e fica certo no tema sólido e no tema vidro (SPEC-049). As cores são `border`, `borderHover` e `teal` para o "Copiado", e o fundo do bloco é mais escuro que o painel.

## Fora do escopo

- O texto que ainda está chegando (`item.live`). Ele continua como `Text` simples, sem barra e sem seleção, e a barra aparece quando a resposta termina.
- Botão de copiar em código inline (`assim`).
- Seleção que atravessa mensagens diferentes. A timeline é uma lista preguiçosa, e um `SelectionArea` na lista inteira perderia o que sai da tela.
- O diff (`DiffView`), a visão ampliada da ferramenta e o `NumberedTextView` (já têm Copiar e `SelectionArea`), a saída do card de ferramenta, o relatório do gate e o terminal.
- Números de linha no bloco, quebra de linha ligável e "Copiar como…" (outros formatos).
- Executar o código, salvar como arquivo e abrir em outro programa.
- Atalho de teclado global para copiar o bloco sob o mouse.
- A aba Editor da spec e o editor de skill (o realce ali é o do `AppCodeEditor`).

## Design

Canvas para validar: [Copiar código](https://claude.ai/artifact/XskeXq2BEUmcC9to3S126q). Ele tem quatro artboards: a resposta no Prompt, a seleção, os outros lugares e o bloco longo.

### O que já existe

- `lib/features/sessions/widgets/timeline_view.dart`: `_AssistantText`, com `MarkdownBody(selectable: true)` e o `MarkdownStyleSheet` da timeline (`codeblockDecoration`), e o `ToolCard`, com cabeçalho, alvo e `trailing`.
- `flutter_markdown_plus` 1.0.12: `MarkdownBody(builders:)` aceita um `MarkdownElementBuilder` para a tag `pre`. O bloco cercado chega como `pre > code`, com a classe `language-xxx` no `code`.
- `lib/ui/widgets/code_editor/code_language.dart`: `CodeLanguage` (inclui SQL), e `code_editor_theme.dart`: `promptoriumCodeTheme`.
- `lib/features/review/widgets/diff_highlight.dart`: o modelo do realce com cache (`Highlight` + `TextSpanRenderer`).
- `lib/ui/widgets/numbered_text_view.dart`: o modelo do `SelectionArea` com uma parte fora da seleção (`SelectionContainer.disabled`).
- `lib/features/sessions/widgets/tool_expanded_view.dart`: o `Copiar` da visão ampliada (SPEC-058).

### Componentes

- **`lib/ui/widgets/markdown/app_markdown.dart`**: `AppMarkdown(data, styleSheet, {collapseLongCode = false})`. Ele põe `SelectionArea` em volta de `MarkdownBody(selectable: false, builders: {'pre': CodeBlockBuilder(...)})` (R6, R10).
- **`lib/ui/widgets/markdown/code_block.dart`**: `CodeBlock(code, language, collapsible)`, com a barra, o realce, recolher/expandir e o estado "Copiado" (R1–R5, R8). Também `codeOfPre(element)`, uma função pura que extrai o texto exato e a linguagem do elemento `pre` (R2).
- **`lib/ui/widgets/copy_button.dart`**: `CopyButton` (texto ou só ícone), que copia, mostra "Copiado" por 1,5 s e anuncia. É usado pelo bloco, por "Copiar mensagem" e por "Copiar comando" (R3, R7, R9).
- **`CodeLanguage.forFence(String info)`**, com a tabela de apelidos (R5). **`CodeHighlight.spans(code, language)`**, com cache, extraído do `DiffHighlight` (R5).
- No `ToolCard`: o `CopyButton` de ícone para `Bash` (R9). No `_AssistantText`: o `CopyButton` de ícone no cabeçalho (R7).

Sem mudança de banco nem de configuração.

### Testes

- `codeOfPre`: bloco cercado, com `~~~`, indentado, dentro de lista, com tabs e espaços no fim; sem a quebra final; linguagem da classe ou `texto`.
- `CodeLanguage.forFence`: apelidos, maiúsculas, desconhecida → sem realce.
- `CodeBlock`: Copiar põe o texto exato na área de transferência (`SystemChannels.platform` simulado); "Copiado" aparece e some depois de 1,5 s; Enter e Espaço com foco copiam; o rótulo semântico tem a linguagem e as linhas; mais de 24 linhas recolhe e mostra 16; "Mostrar" expande e o Copiar de baixo aparece; sem recolher fora da timeline.
- `AppMarkdown`: um `SelectionArea` só por documento, nenhum `SelectableText` dentro; selecionar tudo e copiar traz parágrafo e código, sem "Copiar" nem a linguagem.
- Timeline: o botão "Copiar mensagem" copia o markdown; o card Bash copia o `command`; o texto ao vivo continua sem barra.
- Telas: Specs, plano pronto, spec da resposta, lote, skill e Sobre usam `AppMarkdown`.

## Critérios de aceite

- [x] Todo bloco de código mostra a barra com a linguagem (ou `texto`), as linhas a partir de 3 e o botão Copiar [R1] verificar: flutter test test/ui/widgets/markdown/code_block_test.dart
- [x] Copiar põe na área de transferência o bloco exato, sem cercas, sem a linguagem e sem números de linha, com a indentação [R2] verificar: flutter test test/ui/widgets/markdown/code_block_test.dart
- [x] O botão vira "Copiado" por 1,5 s, anuncia ao leitor de tela e funciona com Tab + Enter/Espaço [R3, R4] verificar: flutter test test/ui/widgets/markdown/code_block_test.dart
- [x] O bloco tem realce pela linguagem da cerca, apelidos incluídos, e fica sem realce numa linguagem desconhecida [R5] verificar: flutter test test/ui/widgets/code_editor/code_language_test.dart
- [x] Cada mensagem e cada documento é um só `SelectionArea`, e selecionar e copiar atravessa parágrafo e bloco sem levar a barra [R6] verificar: flutter test test/ui/widgets/markdown/app_markdown_test.dart
- [x] "Copiar mensagem" copia o markdown da resposta, e "Copiar comando" copia o `command` do card Bash [R7, R9] verificar: flutter test test/features/sessions/timeline_copy_test.dart
- [x] Na timeline, um bloco com mais de 24 linhas chega recolhido em 16, expande, recolhe e copia inteiro; fora da timeline não recolhe [R8] verificar: flutter test test/ui/widgets/markdown/code_block_test.dart
- [x] Não sobra `MarkdownBody` fora do `AppMarkdown` [R10] verificar: grep -rn "MarkdownBody(" lib
- [x] No app, a query SQL de uma resposta do Prompt é copiada pelo botão e colada inteira no DBeaver (ou num editor), e a seleção do meio do parágrafo até o meio da query não se perde, nos temas sólido e vidro [R2, R6, R11] verificar: manual (app isolado com `XDG_DATA_HOME`, prints em `docs/mockups/spec-077/app/`)
- [x] O projeto compila e a análise estática passa [R1–R11] verificar: flutter analyze

## Decisões

Decididas no canvas, com o usuário, que aceitou todas as recomendações:

- P1 · **Botão sempre visível ou só no hover.** **Decidido:** **sempre visível** e discreto, ganhando contraste no hover. No hover ele sumiria para quem usa só o teclado e para quem não sabe que o botão existe. A barra também mostra a linguagem, o que ajuda a ler.
- P2 · **Realce de sintaxe.** **Decidido:** **entra**, com o `re_highlight` e o tema do editor (`promptoriumCodeTheme`). O custo é pequeno com o cache.
- P3 · **Limite para recolher.** **Decidido:** na timeline, um bloco com **mais de 24 linhas chega recolhido em 16**, com "Mostrar as outras N linhas" e, expandido, um segundo Copiar embaixo.
- P4 · **Rolagem vertical dentro do bloco.** **Decidido:** **não**. Rolagem dentro de rolagem prende a roda do mouse na timeline.
- P5 · **"Copiar mensagem" copia markdown ou texto puro.** **Decidido:** **markdown**, como o Claude escreveu, com as cercas. Para texto puro, a pessoa seleciona e usa Ctrl+C (R6).
- P6 · **"Copiar comando" no card Bash.** **Decidido:** **entra**, só no hover ou com o foco no card.
- P7 · **Toast além do "Copiado" no botão.** **Decidido:** **sem toast** no bloco. O retorno é o próprio "✓ Copiado" por 1,5 s, anunciado ao leitor de tela. Os outros botões "Copiar" do app continuam com o toast.
