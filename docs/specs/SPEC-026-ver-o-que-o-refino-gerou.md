---
id: SPEC-026
status: rascunho
depende-de: SPEC-021
---

# Ver o que o refino gerou

## Objetivo

"Refinar com IA" (SPEC-021) abre uma conversa `PromptMode.refine` na tela Prompt. Nela, o agente edita o arquivo da spec. Hoje não dá para ver, na conversa, o que ele escreveu:

- **Antes de aprovar:** o cartão de aprovação (`ApprovalCard`, `side_panel.dart:102`) mostra só o caminho do arquivo e "+N" (`editStats`). A pessoa aprova sem ver o texto.
- **Depois de aplicar:** o cartão da ferramenta (`ToolCard`, `timeline_view.dart:411`) mostra "+N −M". Ao expandir, aparece o `tool_result` do Claude Code ("The file … has been updated successfully"), e não o texto que mudou.
- **No fim:** não há resumo do que mudou na spec. Para conferir, é preciso voltar à tela Specs e comparar de memória.

Esta spec faz a conversa de refino mostrar as alterações da spec em três momentos:

1. **Antes de aprovar cada edição:** as linhas que saem e as que entram.
2. **Depois de aplicada:** o mesmo diff no cartão da edição.
3. **No fim do turno:** um resumo e um diálogo com o conjunto das alterações desde o início da conversa.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/G8Y8kRJV6rZTn1y8mtEj3T). A cópia dos artboards e das capturas está em `docs/mockups/spec-026/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-aprovar-vendo-o-diff.png` | Edição aguardando aprovação, com o diff | R1, R5 |
| `2-edicao-aplicada.png` | Cartão da edição expandido, com o diff no lugar da saída da ferramenta | R2, R5 |
| `3-fim-do-refino.png` | Resumo "SPEC-024 atualizada", com as seções alteradas | R6 |
| `4-alteracoes-do-refino.png` | Diálogo com todas as alterações desde o início da conversa | R7, R8 |
| `5-edicao-negada.png` | Edição negada, que continua visível e marcada como não aplicada | R4 |

## Requisitos

- R1 · Quando o agente pedir aprovação para `Edit`, `MultiEdit` ou `Write` no arquivo da spec de origem, o cartão de aprovação deve mostrar:
  - o título "Aprovar esta edição na spec?";
  - a ferramenta, o nome do arquivo e a seção afetada (o título `##` mais próximo acima do trecho);
  - o total "+N −M";
  - o diff da edição, com as linhas removidas e as adicionadas;
  - os botões "Negar" e "Aprovar edição" (primário).
- R2 · Quando uma edição de arquivo (`Edit`, `MultiEdit`, `Write`) terminar, o cartão da ferramenta deve:
  - mostrar no alvo `<código> · <seção>` quando o arquivo for uma spec conhecida, e o caminho relativo nos demais casos;
  - ao ser expandido, mostrar o diff da edição em vez do texto do `tool_result`;
  - mostrar o `tool_result` só se a edição falhar.
- R3 · Quando a edição for um `Write` e o conteúdo anterior do arquivo for conhecido (texto-base do R8 ou edição anterior na mesma conversa), o sistema deve mostrar o diff contra esse conteúdo. Quando não for conhecido, deve mostrar todas as linhas como adicionadas, com a nota "Conteúdo anterior desconhecido".
- R4 · Quando a pessoa negar uma edição, o cartão deve:
  - continuar na conversa com o diff proposto;
  - levar o rótulo "Negada, não aplicada";
  - mostrar o diff em cores neutras, sem fundo nem sinal verde ou vermelho, mantendo os sinais + e − em cinza.
  - A edição negada não entra nas contagens nem no resumo.
- R5 · Enquanto a conversa aberta for de refino com origem guardada, o painel lateral deve mostrar a seção "Spec em refino" com:
  - o código, o título e o status da spec;
  - as edições aplicadas, as que aguardam aprovação e as negadas;
  - as linhas aplicadas "+N −M" desde o início da conversa (as pendentes não entram);
  - o botão "Ver alterações", desabilitado com a dica "Nenhuma edição aplicada ainda" enquanto nada tiver sido aplicado.
- R6 · Quando um turno do agente terminar (`Result`) com pelo menos uma edição aplicada na spec de origem durante esse turno, o sistema deve mostrar, abaixo da última resposta, o cartão "<código> atualizada" com:
  - o número de edições aplicadas e o total "+N −M";
  - uma linha por seção alterada, com os requisitos e critérios tocados ("R3 reescrito, R4 novo", "1 reescrito, 2 novos"), "seção nova", "seção removida" ou "+a −d linhas";
  - os botões "Ver alterações" e "Voltar à <código>" (primário).
- R7 · Quando a pessoa acionar "Ver alterações", o sistema deve abrir o diálogo "Alterações do refino em <código>". O diálogo deve ter:
  - as abas "Diferenças" (diff entre o texto-base e o arquivo atual) e "Spec como ficou" (a spec renderizada);
  - os trechos sem mudança de mais de 3 linhas recolhidos em "N linhas sem mudança", com o botão "Mostrar";
  - "Fechar" (Esc) e "Voltar à <código>" (primário).
- R8 · Quando uma conversa de refino for criada, o sistema deve guardar na conversa o texto da spec naquele momento (o texto-base). Se o arquivo tiver sido alterado fora da conversa depois disso, por exemplo salvo na tela Specs, o diálogo do R7 deve avisar "A spec também foi alterada fora desta conversa" e continuar comparando com o arquivo atual. Conversas sem texto-base (criadas antes desta spec) mostram no diálogo as edições da conversa, uma a uma, em vez do diff total.
- R9 · O diff deve ser legível sem depender de cor:
  - cada linha leva o sinal + ou − e um rótulo acessível ("linha adicionada", "linha removida", "sem mudança");
  - o número da linha é a posição no arquivo, e a linha removida leva o número da posição que ocupava;
  - a coluna do sinal é separada do texto por um fio, para não se confundir com o "-" de lista do markdown;
  - o texto tem contraste de 4,5:1 ou mais sobre os fundos `addBg` e `delBg`;
  - os cartões expansíveis recebem foco por Tab, abrem com Enter ou Espaço e anunciam se estão expandidos.
- R10 · Quando o diff passar do espaço do cartão, o cartão de aprovação deve limitar a altura e rolar por dentro. O cartão expandido e o diálogo devem mostrar até 400 linhas e oferecer "Mostrar as outras N linhas", sem travar a rolagem da conversa.
- R11 · Quando, numa conversa de refino, o agente editar um arquivo que não seja a spec de origem, o cartão deve mostrar o caminho completo e a marca "fora da spec" em âmbar. Essa edição não entra nas contagens nem no resumo da spec.

## Fora do escopo

- Desfazer ou reverter edições já aplicadas pela conversa (o arquivo continua no git).
- Editar o diff ou aprovar só parte de uma edição.
- Mudar o texto de `refineSpecPrompt` ou o modo de permissão do refino.
- Mostrar o diff de edições em conversas que não sejam de refino. O R2 vale para elas porque o `ToolCard` é compartilhado, mas sem o resumo, o painel e o diálogo.
- Diff por palavra dentro da linha (fica por linha, como `lineDiff`).

## Design

### O que já existe

- **Conversa:**
  - `lib/features/prompt/prompt_screen.dart`: `_Header` (com o "Voltar à spec" da SPEC-021, l.336) e `_Conversation` (l.428), que monta `TimelineListView` com `footer` (aprovações, plano pronto) e `answerFooter` (barra de spec da resposta).
  - `lib/features/prompt/refine_origin.dart`: `refineOriginOf(c)` e `backToSpec`.
  - `lib/features/prompt/widgets/prompt_side_panel.dart`: o painel "Contexto".
- **Cartões:**
  - `lib/features/sessions/widgets/timeline_view.dart:411`: o `ToolCard` expande `t.result`, limitado a 40 linhas.
  - `lib/features/sessions/timeline.dart:399`: `editStats(name, input)` conta as linhas de `old_string`, `new_string` e `content`.
  - `toolTarget` (l.355) devolve o caminho.
  - `ToolItem.input` guarda o pedido inteiro da ferramenta, também ao reabrir a conversa. Por isso o diff sai do `input` e não depende do `tool_result`.
  - `lib/features/sessions/widgets/side_panel.dart:102`: `ApprovalCard`, que mostra alvo, "+N", "Negar" e "Aprovar". É usado na tela Prompt e na de Sessões.
- **Diff:**
  - `lib/features/prompt/spec_from_answer.dart:209`: `lineDiff(a, b)` (LCS, `DiffOp.same/add/del`).
  - `answer_spec_bar.dart:497`: renderização de diff com `SessionColors.addBg` e `delBg`.
- **Dados:**
  - `Conversations` tem `refineSpecCode` e `refineOrigin` (SPEC-021).
  - `appSchemaVersion = 17` (`app_database.dart:18`).

### R1–R4 · Diff da edição (`EditDiff`)

- Função pura nova, `editDiffOf(ToolItem|PermissionRequest, {String? before})`, em `lib/features/sessions/edit_diff.dart`. Ela devolve `List<DiffLine>` e a seção.
  - `Edit`: `lineDiff(old_string, new_string)`.
  - `MultiEdit`: a concatenação dos blocos de cada edição.
  - `Write`: `lineDiff(before ?? '', content)`.
- **Seção e números de linha:**
  - O texto-base é o do R8, com as edições anteriores da conversa já aplicadas na ordem.
  - A seção vem do primeiro `## ` acima da posição de `old_string` nesse texto.
  - Os números de linha usam a mesma posição.
  - Sem texto conhecido, não mostrar números de linha.
- Widget novo `DiffView` (`lib/ui/widgets/diff_view.dart`), que reaproveita a renderização de `answer_spec_bar.dart:497`. Esse trecho passa a usar o widget.
  - Parâmetros: `muted` (R4), `maxLines` (R10) e `collapseSame` (R7).
- **`ToolCard`:** para `editStats != null`, o corpo expandido vira `DiffView`. O `tool_result` só aparece quando `isError`.
- **`ApprovalCard`:** para as ferramentas de edição, ganha o título, o alvo com a seção e o `DiffView` com altura máxima de 200 px (R1, R10). "Aprovar" vira "Aprovar edição" só nesses casos.
- **Negadas (R4):** guardar os `toolUseId` negados em `LiveState` e persistir na timeline como `NoticeItem` já existente. O `ToolCard` recebe `denied: true`.

### R5–R7 · Painel, resumo e diálogo

- **`refineProgressProvider(conversationId)`** (derivado da timeline) calcula:
  - as edições aplicadas, pendentes e negadas no arquivo de origem;
  - o diff total `lineDiff(base, atual)`, lendo o arquivo por `specServiceProvider.read`.
- **Painel (R5):** a seção "Spec em refino" entra no `PromptSidePanel` antes de "Contexto", só para refino com origem.
- **Resumo (R6):** o cartão `RefineSummaryCard` entra no `footer` de `_Conversation` quando o último item é a resposta e o turno teve edição aplicada.
  - Para "R3 reescrito / R4 novo", comparar as linhas `- R<n> ·` e `- [ ]` por seção entre a base e o texto atual.
- **Diálogo (R7):** `showRefineChangesDialog`, no padrão de `showAnswerSpecPreview`, com `DiffView(collapseSame: 3)`.
  - A aba "Spec como ficou" usa o mesmo renderizador de markdown do modo Visualizar da tela Specs.
  - "Voltar à <código>" chama `backToSpec`.

### R8 · Texto-base

- Schema v18: coluna nova e anulável `refineBaseText` em `Conversations`.
- `ConversationManager.create` grava o texto quando `mode == refine && origin != null`. `_refine` já salva a spec antes de abrir a conversa (SPEC-021), então o texto é o do disco.
- O aviso de alteração externa aparece quando o arquivo atual difere da base com todas as edições aplicadas da conversa.
- Alternativa descartada: reconstruir a base a partir do `tool_result` do primeiro `Read`. Ela depende do formato `cat -n` do Claude Code e falha se o agente não ler o arquivo antes.

### R9–R11 · Acessibilidade, tamanho e arquivos fora da spec

- **Acessibilidade (R9):**
  - `DiffView` usa `Semantics(label: 'linha adicionada: <texto>')` por linha.
  - O cabeçalho do `ToolCard` ganha `Semantics(button: true, expanded: _open)`.
- **Limite (R10):** 400 linhas por `DiffView`, com o botão "Mostrar as outras N linhas", e `ListView.builder` no diálogo.
- **Fora da spec (R11):** comparar o `file_path` absoluto com `ws.path/spec.path`.

## Critérios de aceite

- [ ] O cartão de aprovação de um `Edit` na spec mostra a seção, "+N −M", as linhas removidas e as adicionadas, "Negar" e "Aprovar edição" [R1] verificar: flutter test test/features/sessions/approval_card_test.dart
- [ ] Expandir um cartão de `Edit` concluído mostra o diff, e não "has been updated successfully"; com erro, mostra o `tool_result` [R2] verificar: flutter test test/features/sessions/timeline_view_test.dart
- [ ] Um `Write` sobre a spec mostra o diff contra o conteúdo anterior conhecido; sem ele, mostra tudo como adicionado e a nota [R3] verificar: flutter test test/features/sessions/edit_diff_test.dart
- [ ] Uma edição negada continua na conversa com "Negada, não aplicada", o diff em cores neutras e fora das contagens [R4] verificar: flutter test test/features/prompt/refine_changes_test.dart
- [ ] O painel "Spec em refino" mostra as contagens e o total; "Ver alterações" fica desabilitado até a primeira edição aplicada [R5] verificar: flutter test test/features/prompt/refine_changes_test.dart
- [ ] Ao fim de um turno com edição aplicada, aparece o resumo com as seções e os requisitos tocados, "Ver alterações" e "Voltar à <código>" [R6] verificar: flutter test test/features/prompt/refine_changes_test.dart
- [ ] O diálogo compara o texto-base com o arquivo atual, recolhe os trechos iguais com mais de 3 linhas, troca para "Spec como ficou" e fecha com Esc [R7] verificar: flutter test test/features/prompt/refine_changes_test.dart
- [ ] A conversa de refino guarda o texto-base; a alteração externa gera o aviso; uma conversa antiga lista as edições uma a uma [R8] verificar: flutter test test/features/prompt test/data/generated_migration_test.dart
- [ ] Cada linha do diff tem sinal e rótulo acessível; o cartão anuncia se está expandido e abre com Enter e Espaço [R9] verificar: flutter test test/features/sessions/timeline_view_test.dart
- [ ] Um diff de 1.000 linhas mostra 400 e "Mostrar as outras 600 linhas", sem travar a rolagem [R10] verificar: flutter test test/ui/diff_view_test.dart
- [ ] A edição de outro arquivo numa conversa de refino aparece como "fora da spec" e não entra no resumo [R11] verificar: flutter test test/features/prompt/refine_changes_test.dart
- [ ] Os testes atuais de Prompt, Sessões e Specs continuam passando [R2] [R4] verificar: flutter test test/features
- [ ] A análise estática passa sem avisos novos [R1] [R2] [R3] [R4] [R5] [R6] [R7] [R8] [R9] [R10] [R11] verificar: flutter analyze

## Perguntas em aberto

- Mostrar o diff também na tela de Sessões (o `ApprovalCard` e o `ToolCard` são os mesmos)? A spec assume que sim para o R1 e o R2, e que só o resumo, o painel e o diálogo ficam restritos ao refino.
- O resumo do R6 aparece a cada turno com edição ou só uma vez, no último turno? A spec assume a cada turno, com o total desde o início da conversa.
- Guardar o texto-base no banco (schema v18) ou num arquivo ao lado da conversa? A spec escolhe o banco, pelo padrão da SPEC-021.
