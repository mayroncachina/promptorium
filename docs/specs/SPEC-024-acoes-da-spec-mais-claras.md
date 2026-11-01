---
id: SPEC-024
status: concluida
---

# Ações da spec mais claras

## Objetivo

O cabeçalho da aba Specs junta numa só faixa nove controles de natureza diferente:

- quatro modos de exibição (Editar, Dividido, Visualizar, Protótipo);
- cinco ações (Salvar, Refinar com IA, Gerar design, Aprovar spec, Excluir).

Todos os controles têm o mesmo peso visual. Na janela mínima (1100×700) os botões são `Flexible` com `TextOverflow.ellipsis`, então os rótulos aparecem cortados ("Refinar c…", "Aprovar…"). Não dá para saber qual é o próximo passo, e "Excluir" fica colado em "Aprovar spec".

É nesse cabeçalho que a pessoa cria, escreve, revisa e aprova uma spec, então o foco é esse ciclo: spec recém-criada → editando → aprovada (ainda editável) → protótipo. A spec travada pela execução no Quadro só precisa continuar funcionando (R5).

Esta spec reorganiza o cabeçalho em três camadas:

1. **Identidade:** caminho, título e status da spec.
2. **Ações:** uma única ação primária por estado, as secundárias com rótulo completo e as raras ou destrutivas no menu "Mais ações".
3. **Modos:** abas com ícone, com o estado de salvamento e o zoom na mesma linha.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/VR4rmavZ1iG3GibBEd2vJQ). Cópia dos artboards e capturas em `docs/mockups/spec-024/`:

- `1-spec-recem-criada.png`: logo após "Nova spec", com o modelo e "Salvo"; a tooltip de "Refinar com IA" indica o próximo passo (R3, R10);
- `2-editando.png`: alterações não salvas, com "Salvar" e `Ctrl+S` (R3, R8);
- `3-menu-mais-acoes.png`: Arquivar e Excluir no menu (R7);
- `4-aprovada-editavel.png`: selo "Aprovada", sem "Aprovar" e sem primária (R4);
- `5-modo-prototipo.png`: ações do modo Protótipo (R6);
- `0-hoje.png`: o cabeçalho atual, com os rótulos cortados.

## Requisitos

- R1 · O cabeçalho da spec deve ter duas linhas: na primeira, o bloco de identidade (caminho, título e um selo de status) e a barra de ações; na segunda, as abas de modo à esquerda e, à direita, o estado de salvamento e o controle de zoom.
- R2 · O sistema deve mostrar os modos como abas (`role tab`, ícone + rótulo, a ativa sublinhada em âmbar) com os rótulos "Editar", "Lado a lado", "Visualizar" e "Protótipo"; "Dividido" passa a se chamar "Lado a lado".
- R3 · Enquanto a spec estiver em rascunho no backlog, a barra de ações deve mostrar, nesta ordem, "Refinar com IA" e "Gerar design" (secundárias), "Aprovar" (primária, botão âmbar preenchido) e o botão "Mais ações".
- R4 · Enquanto a spec estiver aprovada e ainda no backlog, o sistema não deve mostrar "Aprovar" na barra; o status aparece só no selo "Aprovada", e a barra mantém as secundárias e "Mais ações".
- R5 · Enquanto a execução da spec tiver começado (spec travada, fora do fluxo de edição), a barra deve mostrar só "Clonar para alterar" (primária) e "Mais ações"; o selo deve ter ícone de cadeado, e a linha das abas deve mostrar "Somente leitura" no lugar do estado de salvamento. Esse estado não tem mockup próprio: usa os mesmos componentes.
- R6 · Enquanto o modo Protótipo estiver ativo, a barra deve mostrar "Comparar variações" (secundária), "Gerar telas da spec" (primária) e "Mais ações".
- R7 · O menu "Mais ações" deve reunir "Arquivar" (ou "Desarquivar") e, separado por um divisor, "Excluir…" em vermelho; cada item só aparece quando a ação está disponível, e o botão some quando o menu ficaria vazio.
- R7a · Os rótulos das ações não devem repetir "spec", porque o cabeçalho já é da spec aberta: "Aprovar", "Arquivar", "Desarquivar" e "Excluir…". "Gerar telas da spec" e o rótulo acessível "Mais ações da spec" ficam como estão.
- R8 · Quando houver alterações não salvas, a linha das abas deve mostrar "● Não salvo" seguido do botão "Salvar" com o atalho `Ctrl+S` visível; sem alterações, deve mostrar "Salvo" com um ícone de confirmação, sem botão.
- R9 · Na janela de 1100×700, nenhum rótulo de ação, aba ou estado deve ser truncado nem quebrar linha; quando o espaço não couber, "Gerar design" e depois "Refinar com IA" devem ir para o menu "Mais ações", e a ação primária deve continuar visível.
- R10 · Cada ação deve ter tooltip com o que faz e o atalho, se existir. Uma ação indisponível deve aparecer desabilitada no estilo da SPEC-025 R10 (texto `#8A93A3` sobre `#1A1E26`, borda `border`, contraste de 4,5:1 ou mais, sem reduzir a opacidade), com tooltip explicando o motivo, em vez de sumir.
- R11 · A barra, o menu e as abas devem ser operáveis por teclado: Tab entra na barra e nas abas, setas movem entre os itens do menu, Esc fecha o menu e devolve o foco ao botão "Mais ações", e o foco tem anel âmbar visível. O botão só com ícone deve ter o rótulo acessível "Mais ações da spec".

## Fora do escopo

- Mudar o que cada ação faz (fluxos de aprovar, refinar, gerar design, clonar, arquivar e excluir continuam os mesmos).
- Atalhos de teclado novos além do `Ctrl+S` que já existe.
- Salvamento automático.
- O conteúdo do modo Protótipo (SPEC-022) e da faixa de avisos (SPEC-023).
- Mudar o cabeçalho de outras telas (Prompt, Quadro, Review).
- O diálogo "Nova spec" e o modelo de spec nova (`newSpecMarkdown`): continuam como estão.
- Bloquear "Aprovar" numa spec vazia: hoje não há essa regra, e os avisos de estrutura da SPEC-023 já informam o que falta.

## Design

### O que já existe

- **Cabeçalho:** `_Header` em `lib/features/specs/specs_screen.dart:1070`. As ações são `SmallButton` dentro de `Flexible`, com chaves `spec-save`, `spec-refine`, `spec-design`, `spec-approve`, `spec-delete`, `spec-clone` e `spec-archive`. No modo Protótipo entram os `ProtoButton` `proto-compare` e `proto-generate`.
- **Modos:** `_ModeSwitch` (segmentado, chaves `spec-mode-<nome>`) e o enum `SpecViewMode` (`edit`, `split`, `preview`, `prototype`).
- **Disponibilidade:** em `specs_screen.dart:785`, `ready` e `locked` (`spec.stage != SpecStage.backlog`), `canArchiveSpec` e `canDeleteSpec`.
- **Botões:** `SmallButton` e `AmberButton` em `lib/features/sessions/widgets/session_style.dart`. O `SmallButton` já aceita `semanticLabel` e `focusColor`.
- **Atalho:** `Ctrl+S` com `SingleActivator` em `specs_screen.dart:921`.
- **Tokens:** `lib/ui/theme/tokens.dart` (`AppColors.amber`, `onAmber`, `teal`, `red`, `selectedBg`).

### R1–R2 · Estrutura

- Novo `SpecHeader` em `lib/features/specs/widgets/spec_header.dart`, que tira o `_Header` do arquivo da tela (hoje com 1.550 linhas). Primeira linha: `Row` com o bloco de identidade em `Expanded` e a barra em largura natural. Segunda linha: `Row` com `SpecModeTabs` e, depois de um `Spacer`, `SaveState` e `ZoomControl`.
- `SpecModeTabs` troca o `_ModeSwitch`, mantendo as chaves `spec-mode-<nome>`. Cada aba tem 40 px de altura, ícone de 16 px e rótulo de 13 px, com `Semantics(selected:)`.
- `SpecViewMode.split.label` passa a ser "Lado a lado".
- O selo de status (`StatusBadge`) usa os mesmos textos da lista de specs.

### R3–R7 · Ações por estado

- Nova função pura `specHeaderActions(SpecHeaderState)`, que devolve a lista ordenada de `SpecAction` (id, rótulo, ícone, ênfase `primary`/`secondary`/`menu`, `onTap`, motivo de indisponibilidade). A UI só desenha essa lista, e os testes de estado conferem a função sem montar a tela.
- Primária: novo `PrimaryButton` (âmbar preenchido, texto `onAmber`, peso 600), o mesmo visual do `AmberButton`, que passa a aceitar ícone.
- "Mais ações": `MenuAnchor` com `MenuItemButton`. "Excluir…" usa `AppColors.red` e um `Divider` antes. As chaves `spec-archive` e `spec-delete` passam para os itens do menu, e o botão ganha a chave `spec-more`.

### R8 · Salvar

- `SaveState(dirty:, locked:)`: com `dirty`, mostra o ponto âmbar, "Não salvo" e um `SmallButton` "Salvar" (chave `spec-save`) com um `Kbd('Ctrl+S')`. Sem `dirty`, mostra "Salvo". Com `locked`, mostra "Somente leitura".
- O "● não salvo" ao lado do caminho (`spec-unsaved`) sai do bloco de identidade. A chave passa para o texto do `SaveState`.

### R9 · Sem truncar

- Os botões deixam de ser `Flexible` e o `TextOverflow.ellipsis` sai dos rótulos de ação.
- Um `LayoutBuilder` mede a largura disponível para a barra. Se a soma das larguras naturais não couber, as secundárias vão para o menu "Mais ações", na ordem do R9.
- A medição é uma função pura `fitActions(List<double> larguras, double disponivel)`, para poder testá-la.

### R10–R11 · Tooltips, estados e teclado

- `Tooltip` em cada ação, com `waitDuration` de 500 ms. Textos:
  - Refinar com IA: "Abre uma conversa com a IA para escrever objetivo, requisitos e critérios a partir do que você já tem."
  - Gerar design: "Escreve a seção Design a partir do código atual."
  - Aprovar: "Marca a spec como pronta para virar etapas no Quadro."
  - Clonar para alterar: "A execução já começou; crie uma cópia em rascunho para mudar."
- Os estados ficam no tema: hover clareia uns 12 %, pressionado escurece uns 12 % e desabilitado usa texto `#8A93A3` (`AppColors.textDisabled`) sobre `#1A1E26` (`surfaceRaised`), com borda `border`, sem opacidade. Sem animação de layout; com movimento reduzido, a transição de cor é desligada.
- Foco: `focusColor` âmbar a 25 %, mais um contorno de 2 px. A ordem do Tab segue a ordem visual: identidade, ações, abas, Salvar e zoom.

## Critérios de aceite

- [x] O cabeçalho mostra caminho, título e selo na primeira linha, e abas, estado de salvamento e zoom na segunda [R1] verificar: flutter test test/features/specs/spec_header_test.dart
- [x] As abas têm os rótulos do R2 com `Semantics(selected:)` na ativa, e "Dividido" não aparece mais [R2] verificar: flutter test test/features/specs/spec_header_test.dart
- [x] `specHeaderActions` devolve, para rascunho no backlog, Refinar com IA, Gerar design, Aprovar (primária) e o menu, nesta ordem [R3] verificar: flutter test test/features/specs/spec_header_actions_test.dart
- [x] Uma spec recém-criada pelo "Nova spec" abre com "Salvo", selo "Rascunho" e as ações do R3 [R3] [R8] verificar: flutter test test/features/specs/specs_screen_test.dart
- [x] Para uma spec aprovada no backlog, "Aprovar" não aparece e não há primária [R4] verificar: flutter test test/features/specs/spec_header_actions_test.dart
- [x] Para uma spec travada, há só "Clonar para alterar" (primária) e o menu; o selo tem cadeado e aparece "Somente leitura" [R5] verificar: flutter test test/features/specs/spec_header_actions_test.dart test/features/specs/spec_header_test.dart
- [x] No modo Protótipo, "Gerar telas da spec" é a primária e "Comparar variações" a secundária; `proto-compare` e `proto-generate` continuam funcionando [R6] verificar: flutter test test/features/specs/prototype_view_test.dart test/features/specs/spec_header_actions_test.dart
- [x] O menu "Mais ações" abre com Arquivar e Excluir separados por divisor; Excluir pede confirmação como hoje; sem ações disponíveis o botão não aparece [R7] verificar: flutter test test/features/specs/specs_screen_test.dart
- [x] Os botões e itens de menu do cabeçalho dizem "Aprovar", "Arquivar"/"Desarquivar" e "Excluir…", sem "spec" [R7a] verificar: flutter test test/features/specs/spec_header_test.dart
- [x] Editar o texto mostra "Não salvo" e "Salvar" com `Ctrl+S`; salvar volta para "Salvo" [R8] verificar: flutter test test/features/specs/specs_screen_test.dart
- [x] Em 1100×700, nenhum `Text` de ação, aba ou estado tem overflow (`didExceedMaxLines` falso) [R9] verificar: flutter test test/features/specs/spec_header_test.dart
- [x] `fitActions` manda primeiro "Gerar design" e depois "Refinar com IA" para o menu quando a largura não basta, e nunca a primária [R9] verificar: flutter test test/features/specs/spec_header_actions_test.dart
- [x] Cada ação tem tooltip; uma ação desabilitada aparece com texto `#8A93A3` sobre `#1A1E26` (contraste ≥ 4,5:1, sem opacidade) e tooltip com o motivo [R10] verificar: flutter test test/features/specs/spec_header_test.dart
- [x] Tab percorre identidade, ações, abas, Salvar e zoom nesta ordem; no menu, as setas movem e Esc fecha e devolve o foco ao `spec-more`; o botão do menu tem o rótulo "Mais ações da spec" [R11] verificar: flutter test test/features/specs/spec_header_test.dart
- [x] Os testes atuais da tela de specs passam com as chaves preservadas ou migradas [R1] [R3] [R7] [R8] verificar: flutter test test/features/specs
- [x] A análise estática passa sem avisos novos [R1] [R2] [R3] [R4] [R5] [R6] [R7] [R8] [R9] [R10] [R11] verificar: flutter analyze

## Decisões

- (Pergunta 1) Spec aprovada e ainda no backlog: sem ação primária extra; a barra fica com as secundárias e "Mais ações" (R4).
- (Pergunta 2) O modo "Dividido" passa a se chamar "Lado a lado" (R2).
- Ações indisponíveis usam o estilo da SPEC-025 R10, não opacidade: texto `#8A93A3` sobre `#1A1E26`, borda `border` (contraste ≥ 4,5:1). O R10 foi ajustado.
- Na janela de 1100×700 a coluna do editor tem cerca de 544 px (a lista de specs e o painel lateral continuam). A largura é medida com `TextPainter`: as abas perdem o ícone quando não cabem e, com alterações não salvas, o estado de salvamento e o zoom sobem para uma linha própria acima das abas, em vez de cortar rótulos (R9). O título e o caminho podem encurtar com reticências; ações, abas e estados não.
- O bloco de identidade não tem controle interativo, então não recebe foco: a ordem do Tab começa nas ações, segue para as abas, "Salvar" e o zoom (R11).
- "Arquivar" (só spec concluída) e "Excluir…" (só spec no backlog) nunca aparecem juntos na prática; o divisor entre os dois é testado no `SpecHeader` (spec_header_test.dart), e a tela testa cada item no seu estado.
- `SpecViewMode` foi para `widgets/spec_header.dart` e continua exportado por `specs_screen.dart`.

## Perguntas em aberto

- Numa spec aprovada ainda no backlog (R4), deve haver uma primária, como "Abrir no Quadro"? Esta spec deixa a barra sem primária para não inventar um fluxo.
- "Lado a lado" é o melhor nome para o modo dividido, ou é melhor "Texto + leitura"?
