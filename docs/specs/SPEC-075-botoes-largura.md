---
id: SPEC-075
status: aprovada
tipo: bug
---

# Botões com a largura do texto

## Objetivo

Os botões pequenos (`SmallButton`) e o botão âmbar primário (`AmberButton`) têm um parâmetro `expand` que diz se o botão estica até a largura do pai. Com `expand: false`, que é o padrão, eles deveriam ter a largura do conteúdo. Não têm: o conteúdo fica num `Container` com `alignment: Alignment.center` e sem largura, e um `Container` com alinhamento ocupa toda a largura que o pai oferece. Em `Column`, `Wrap`, `Align`, `Center` e `Flexible`, o botão vira uma faixa de ponta a ponta: "Verificar agora" e "Mergear PR…" no Review, "Importar issues" na Bandeja, "Pedir outra proposta" na criação de projeto.

Várias telas contornaram o defeito com `IntrinsicWidth` em volta do botão. A correção fica no componente, e cada uso decide se estica.

## Requisitos

- R1 · `SmallButton` com `expand: false` tem a largura do conteúdo (texto, ícone e `trailing`, mais o padding), em qualquer pai. Se o pai der menos largura que o conteúdo, o botão encolhe e o texto corta com reticências, como hoje.
- R2 · `SmallButton` com `expand: true` ocupa toda a largura que o pai oferece, com o conteúdo centralizado.
- R3 · `AmberButton` segue as mesmas regras (R1 e R2), inclusive no estado ocupado (spinner + texto). Os outros botões de texto com o mesmo defeito também têm a largura do conteúdo: `ChipButton` (sugestões e stacks da criação de projeto), `ProtoButton` (Protótipo), os modelos de "Ponto de partida" da tela Começar, o seletor de modelo do composer do Prompt e "Permissão: …" e "Anexar spec" do composer da sessão.
- R4 · Um pai que impõe largura exata (`Expanded`, `SizedBox(width:)`, `ListView`, `Column` com `CrossAxisAlignment.stretch`) continua definindo a largura do botão, com o conteúdo centralizado, com ou sem `expand`.
- R5 · Cada uso dos dois botões foi revisto. Onde a faixa larga era a intenção (o botão de ação de largura total de um painel ou modal estreito), o uso passa `expand: true`. Nos demais, o botão fica do tamanho do texto, alinhado à esquerda ou à direita conforme o desenho da tela. Nos cabeçalhos em que os botões dividiam a linha com o título por `Flexible` (Prompt, Agentes, Review, Sessões, Skills e o `StepHeader` do Projeto), os botões ficam juntos no lado direito, e o título mantém a largura que tinha.
- R6 · Os `IntrinsicWidth` que só existiam para contornar o defeito saem.

## Fora do escopo

- Os botões que só aparecem em `Row` sem `Flexible` (`CanvasBarButton`, os botões do diff do Review, os da barra de título e as abas do Repositório): ali a largura não é limitada e o defeito não aparece.
- Os botões que ocupam a largura por desenho: os filtros da lista de Sessões (Todas, Aguardando, Concluídas), "Ver review" no cartão do Quadro, os botões do inspetor do canvas (`_PanelButton`) e os segmentos de Configurações.
- Mudar a aparência dos botões (altura, cor, padding).
- As telas novas das SPEC-072, 073 e 074, que ainda não estão na `main`: os usos de `SmallButton` delas são revistos quando a 075 for integrada depois delas.

## Design

A correção não muda o desenho de nenhuma tela: devolve os botões ao tamanho dos mockups. O corpo dos botões passa a ser um componente só, `ButtonBox` (`lib/ui/widgets/button_box.dart`): o conteúdo fica num `Align` com `widthFactor: 1` quando `expand` é falso (o botão encolhe ao conteúdo e continua centralizado na altura) e num `Container` de largura infinita quando é verdadeiro.

Os prints antes/depois estão em `docs/mockups/spec-075/`.

## Critérios de aceite

- [x] `SmallButton` e `AmberButton` sem `expand` têm a largura do conteúdo em `Column`, `Wrap`, `Align` e `Flexible` [R1, R3] verificar: flutter test test/features/sessions/button_width_test.dart
- [x] Com `expand: true` e sob largura exata, os botões ocupam a largura do pai [R2, R4] verificar: flutter test test/features/sessions/button_width_test.dart
- [x] Os usos que esticavam de propósito passam `expand: true` e as telas mantêm o desenho [R5] verificar: flutter test
- [x] Não sobra `IntrinsicWidth` em volta de `SmallButton` ou `AmberButton` [R6] verificar: grep -rn -A1 "IntrinsicWidth(" lib
- [x] O projeto compila e a análise estática passa [R1–R6] verificar: flutter analyze
