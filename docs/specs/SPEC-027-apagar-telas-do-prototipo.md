---
id: SPEC-027
status: rascunho
depende-de: SPEC-022
---

# Apagar telas do protótipo

## Objetivo

No modo Protótipo da spec (SPEC-022), o agente gera uma tela por requisito e, a pedido, variações (B, C…). Quem não gosta de uma tela hoje quase não tem como se livrar dela:

- O canvas não oferece nenhuma ação no cartão da tela. Clicar seleciona; clicar duas vezes abre no navegador.
- O único caminho é a aba "Versões" do painel lateral (`prototype_view.dart:1133`, "Remover"). Ela é difícil de achar e tira uma variação por vez.
- A tela aprovada não pode ser apagada: no lugar do botão aparece o selo "aprovada". Para apagá-la é preciso aprovar outra antes, ou editar a seção `## Protótipo` à mão.
- Não há como desfazer: o arquivo é apagado na hora.

Esta spec dá à pessoa que cria ou edita a spec uma forma direta e segura de apagar as telas que não quer:

- pelo próprio cartão no canvas;
- uma ou várias de uma vez;
- incluindo a aprovada, com aviso;
- com "Desfazer" logo depois.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/VgzA6UuHaq7KsMi88f7ZXx). Cópia dos artboards e das capturas em `docs/mockups/spec-027/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-menu-da-tela.png` | Menu "Mais ações da tela" no cartão, com "Apagar tela…" | R1, R1a, R2 |
| `2-confirmar-aprovada.png` | Confirmação para apagar a tela aprovada | R4, R5 |
| `3-varias-selecionadas.png` | Barra de seleção com "Apagar 2 telas…" | R3 |
| `4-desfazer.png` | Aviso "Tela apagada" com "Desfazer" | R6 |
| `5-requisito-sem-tela.png` | Requisito sem tela e aba "Versões" com apagar por variação | R7, R9 |

## Requisitos

- R1 · O rótulo de cada cartão deve mostrar o requisito, o título e a letra da variação (A, B, C…) num selo, também na variação A, para casar com os nomes da aba "Versões". O selo "Aprovada" fica no rótulo, fora da miniatura.
- R1a · Cada cartão de tela no canvas do modo Protótipo deve ter o botão "Mais ações da tela" (⋯, rótulo acessível "Mais ações da tela <requisito>, <título>, variação <letra>").
  - O botão aparece ao passar o mouse ou com foco no cartão.
  - O botão fica sempre visível quando o cartão está selecionado.
  - O menu oferece "Abrir no navegador", "Pedir variação", um separador e "Apagar tela…" (em vermelho, com o atalho Del).
- R2 · Quando o cartão estiver selecionado ou com foco e a pessoa apertar Delete, o sistema deve abrir a mesma confirmação de "Apagar tela…".
- R3 · Enquanto houver duas ou mais telas selecionadas (Ctrl+clique, já existente), o sistema deve mostrar acima do canvas uma barra com:
  - "N telas selecionadas" e o botão "Limpar seleção" (Esc);
  - "Apagar N telas…".
  - Nesse estado os cartões mostram uma caixa de seleção marcada.
  - A barra não repete "Pedir variação": o pedido continua no painel "Pedir ao Claude", que já age sobre a seleção.
- R4 · Antes de apagar, o sistema deve pedir confirmação num diálogo (`alertdialog`) com:
  - o título "Apagar a tela <requisito>, <título>, variação <letra>?", ou "Apagar N telas?" quando forem várias;
  - a miniatura;
  - o nome do arquivo e a pasta `docs/mockups/<código>/`;
  - a nota "Logo depois, dá para desfazer por alguns segundos.";
  - os botões "Cancelar" (Esc, com o foco inicial) e "Apagar tela" (destrutivo, em vermelho).
- R5 · Quando a tela a apagar for a aprovada do requisito, o diálogo deve avisar: "Esta é a tela aprovada do <requisito>. A linha dela também sai da seção Protótipo da spec, e o <requisito> fica sem tela aprovada." Ao confirmar, o sistema deve remover a linha do requisito em `## Protótipo` (`withPrototype(req, null)`) sem mudar o status da spec.
  - Se o editor tiver alterações não salvas, a remoção da linha é aplicada também ao texto do editor, que continua não salvo. É o mesmo padrão de `_approveScreen`.
- R6 · Depois de apagar, o sistema deve mostrar o aviso "Tela <requisito>, variação <letra>, apagada." (ou "N telas apagadas.") com "Desfazer" (Ctrl+Z) por 10 segundos.
  - "Desfazer" restaura os arquivos, as entradas do `index.json` e, se for o caso, a linha de `## Protótipo`.
  - Depois do prazo, ou ao sair da spec, a exclusão fica definitiva.
- R7 · Quando a última tela de um requisito for apagada, o canvas deve mostrar no lugar dela um espaço tracejado "O <requisito> ficou sem tela." com o botão "Gerar tela do <requisito>". O botão roda "Gerar telas da spec" só para esse requisito.
- R8 · Enquanto "Gerar telas da spec" ou um pedido de variação estiver em andamento (SPEC-025), as ações de apagar devem ficar desabilitadas, com a dica "Aguarde a geração terminar". A tela que está sendo gerada não pode ser apagada.
- R9 · A aba "Versões" deve seguir as mesmas regras:
  - o botão "Remover" vira um botão de lixeira neutro (vermelho só ao passar o mouse ou com foco) com rótulo "Apagar <arquivo>";
  - na variação aprovada, o rótulo e a dica avisam que apagar tira a aprovação da spec;
  - a variação aprovada também pode ser apagada, com o aviso do R5;
  - a exclusão passa pelos mesmos diálogo e aviso de desfazer.
- R10 · Ao apagar, o sistema deve tirar as telas apagadas da seleção e da tela "Comparar variações", se estiver aberta, e devolver o foco ao próximo cartão do canvas (ou ao espaço vazio do R7).
  - Leitores de tela recebem o anúncio "<N> tela(s) apagada(s)".
  - Menu e diálogo funcionam só com teclado: setas no menu, Enter e Esc.

## Fora do escopo

- Lixeira permanente ou histórico de telas apagadas além dos 10 segundos do "Desfazer". O arquivo continua recuperável pelo git, se tiver sido versionado.
- Apagar todas as telas da spec de uma vez por uma ação própria (é possível selecionar todas e apagar).
- Apagar telas fora do modo Protótipo, por exemplo na lista de specs ou no quadro.
- Mudar a geração, a comparação ou a aprovação de telas (SPEC-022).

## Design

### O que já existe

- `lib/features/specs/prototype/prototype_service.dart:444`: `remove(ws, spec, screen)` apaga o HTML e a entrada do `index.json` e recarrega o `prototypeScreensProvider`.
- `lib/features/specs/prototype/prototype_view.dart`:
  - `PrototypeUi.select(file, add:)` (l.74), com seleção múltipla por Ctrl+clique;
  - `PrototypeCanvas.card` (l.373), um `InkWell` com `Semantics(button, selected)`;
  - `_PrototypePanelState._remove` (l.939), com `AlertDialog` "Remover <arquivo>?";
  - a aba "Versões" (l.1094), com `ProtoButton` "Remover" e selo "aprovada";
  - `approvedFile(approved, req)` (l.128).
- `lib/features/specs/spec_file.dart:396`: `withPrototype(requirement, null)` já remove a linha de `## Protótipo`.
- `lib/features/specs/specs_screen.dart:707`: `_approveScreen` mostra como gravar no disco e manter o texto do editor quando houver alterações não salvas.
- Miniaturas: cache por hash do HTML (`prototype_thumbnails.dart:83`). Não precisam ser apagadas, porque não aparecem sem o arquivo.

### R1–R3 · Ações no cartão e na seleção

- `PrototypeCanvas.card` ganha:
  - um `Stack` com `ProtoMoreButton` no canto (visível por `MouseRegion` e foco, ou quando selecionado);
  - um `MenuAnchor` com os três itens.
- "Pedir variação" seleciona a tela e foca o campo do painel "Pedir ao Claude".
- Atalho: `Shortcuts`/`Actions` no canvas, com `LogicalKeyboardKey.delete` levando a `DeleteScreensIntent` sobre a seleção (ou o cartão com foco).
- `PrototypeSelectionBar`, mostrado quando `ui.selected.length >= 2`, com Esc ligado a `uiCtrl.clear()`.

### R4–R6 · Confirmar, apagar e desfazer

- `showDeleteScreensDialog(context, screens, approved)` substitui `_remove`. A lista de telas aprovadas define se aparece o aviso do R5.
- `PrototypeService.removeAll(ws, spec, screens)`:
  - lê os bytes de cada HTML e a entrada do índice antes de apagar;
  - devolve um `RemovedScreens` (arquivos, entradas, linhas de `## Protótipo` removidas).
- A tela chama `restore(RemovedScreens)` em "Desfazer". O `RemovedScreens` fica em memória, num `undoProvider` com `Timer` de 10 s. Ele é descartado ao trocar de spec ou de seção.
- A linha da spec segue `_approveScreen`: lê do disco, aplica `withPrototype(req, null)`, grava e reaplica no `_controller` se estiver sujo.
- Alternativa descartada: mover os arquivos para uma pasta de lixeira. Ela deixaria arquivos soltos em `docs/mockups/` ou exigiria limpeza, e 10 s em memória cobrem o arrependimento imediato.

### R7–R10 · Requisito vazio, bloqueio e acessibilidade

- **Espaço vazio (R7):** `requirementsWithoutScreen` = requisitos com interface que já tiveram tela no `index.json` e não têm mais nenhuma. O espaço vazio chama `PrototypeService.generate` com `only: {req}`.
- **Bloqueio (R8):** usa o `prototypeJobsProvider` (já existente) e o `SpecActionState` da SPEC-025.
- **Foco e anúncio (R10):** `FocusNode` por cartão e `SemanticsService.announce`.

## Critérios de aceite

- [ ] O cartão mostra "Mais ações da tela" ao passar o mouse, com foco ou selecionado, e o menu tem "Abrir no navegador", "Pedir variação" e "Apagar tela…" [R1a] verificar: flutter test test/features/specs/prototype_view_test.dart
- [ ] O rótulo do cartão mostra requisito, título e o selo da variação, inclusive "A", e o selo "Aprovada" fica fora da miniatura [R1] verificar: flutter test test/features/specs/prototype_view_test.dart
- [ ] Delete com um cartão selecionado abre a confirmação [R2] verificar: flutter test test/features/specs/prototype_view_test.dart
- [ ] Com duas telas selecionadas, a barra mostra "2 telas selecionadas" e "Apagar 2 telas…", e Esc limpa a seleção [R3] verificar: flutter test test/features/specs/prototype_view_test.dart
- [ ] O diálogo mostra a miniatura, o arquivo e a pasta, começa com foco em "Cancelar" e não apaga nada se cancelado [R4] verificar: flutter test test/features/specs/prototype_view_test.dart
- [ ] Apagar a tela aprovada mostra o aviso, remove a linha de `## Protótipo` e mantém o status; com o editor sujo, o texto do editor também perde a linha e continua não salvo [R5] verificar: flutter test test/features/specs/specs_screen_test.dart
- [ ] "Desfazer" em até 10 s restaura arquivo, índice e linha da spec; depois do prazo, o aviso some e a exclusão fica [R6] verificar: flutter test test/features/specs/prototype_service_test.dart test/features/specs/prototype_view_test.dart
- [ ] Apagar a última tela de um requisito mostra o espaço vazio com "Gerar tela do R<n>", que gera só esse requisito [R7] verificar: flutter test test/features/specs/prototype_view_test.dart
- [ ] Durante uma geração, apagar fica desabilitado com a dica "Aguarde a geração terminar" [R8] verificar: flutter test test/features/specs/prototype_view_test.dart
- [ ] Na aba "Versões", a variação aprovada também pode ser apagada pelo mesmo diálogo [R9] verificar: flutter test test/features/specs/prototype_view_test.dart
- [ ] Depois de apagar, a tela sai da seleção e de "Comparar variações", o foco vai para o próximo cartão e o leitor de tela anuncia a exclusão [R10] verificar: flutter test test/features/specs/prototype_view_test.dart
- [ ] Os testes atuais do protótipo continuam passando [R9] verificar: flutter test test/features/specs
- [ ] A análise estática passa sem avisos novos [R1] [R1a] [R2] [R3] [R4] [R5] [R6] [R7] [R8] [R9] [R10] verificar: flutter analyze

## Perguntas em aberto

- "Desfazer" por 10 segundos basta, ou as telas apagadas devem ir para uma lixeira que dure até fechar o app?
- O espaço vazio do R7 deve aparecer sempre, ou só até a pessoa sair do modo Protótipo (para não ficar lembrando de um requisito que ela decidiu não ter tela)?
- O atalho Delete deve pedir confirmação sempre, ou só quando a tela for a aprovada?
