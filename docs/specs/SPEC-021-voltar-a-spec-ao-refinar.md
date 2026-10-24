---
id: SPEC-021
status: concluida
---

# Voltar a spec ao refinar

## Objetivo

Hoje "Refinar com IA" (tela Specs, `_refine`) e "Aplicar" numa sugestão do card (quadro, `card_extras.dart`) abrem uma conversa `PromptMode.refine` na tela Prompt e levam o usuário até lá, sem caminho de volta. Quando o refinamento termina, ele precisa navegar à mão até a spec e nem sempre vê as edições aplicadas.

Esta spec faz a conversa de refino lembrar de qual spec e de qual tela partiu, e oferece uma ação "Voltar à spec" que leva o usuário de volta, com o arquivo da spec recarregado.

- Vale só para conversas de refino (`PromptMode.refine`) abertas a partir de uma spec. Perguntar, Planejar e Editar não mudam.
- Volta para onde o usuário estava: a tela Specs (origem "Refinar com IA") ou o card no quadro (origem "Aplicar").
- Terminar de refinar equivale a "transformar em spec".
- Fora do escopo: detectar sozinho que o refinamento acabou, aprovar ou rejeitar edições em nome do usuário e mudar o texto de `refineSpecPrompt`.

## Requisitos

- R1 · Quando uma conversa de refino for criada a partir de uma spec, o sistema deve guardar na conversa o código da spec e a tela de origem (Specs ou quadro).
- R2 · Enquanto a conversa aberta for de refino e tiver origem guardada, o sistema deve mostrar na tela Prompt a ação "Voltar à spec <código>".
- R3 · Quando o usuário acionar "Voltar à spec" e a origem for a tela Specs, o sistema deve abrir essa tela com a spec selecionada e recarregar o arquivo dela do disco, de modo que as edições do refino apareçam.
- R4 · Quando o usuário acionar "Voltar à spec" e a origem for o card, o sistema deve voltar ao quadro com o card da spec em foco e recarregar o arquivo dela do disco.
- R5 · Quando a spec de origem tiver sido removida ou renomeada, o sistema deve avisar que ela não foi encontrada e manter o usuário na conversa.
- R6 · Quando a conversa de refino não tiver origem guardada (por exemplo, criada antes desta função), o sistema não deve mostrar "Voltar à spec".
- R7 · Quando o usuário voltar à spec, o sistema deve apenas navegar: a conversa permanece na lista e pode ser retomada.
- R8 · Quando o usuário acionar "Voltar à spec" com edição do agente ainda pendente de aprovação, o sistema deve avisar da pendência e oferecer "Voltar mesmo assim" e "Ficar na conversa".
- R9 · Quando a spec de destino tiver alterações não salvas no editor, o sistema deve mostrar o que foi editado e perguntar se mantém as alterações ou carrega o arquivo do disco, sem sobrescrever sem confirmação.
- R10 · Quando o usuário voltar à spec, o sistema não deve alterar o status da spec (que continua "rascunho") nem o da sugestão aplicada.
- R11 · A ação "Voltar à spec" deve ser operável por teclado, com foco visível e rótulo acessível.

## Design

### O que já existe

- `lib/features/specs/specs_screen.dart`: `_refine(ws, spec)` (l.303) cria a conversa com `conversationManagerProvider.notifier.create(mode: PromptMode.refine)`, seleciona a conversa e chama `navigationProvider.go(AppSection.prompt)`; `_load(ws, spec)` (l.101) lê o arquivo do disco por `specServiceProvider.read`; `_dirty`, `_saved`, `_confirmDiscard()` e `specDirtyProvider`; `pendingDesignProvider` (em `spec_service.dart:479`) serve de modelo para uma ação "ao abrir a spec".
- `lib/features/board/widgets/card_extras.dart:117-136`: o botão "Aplicar" da sugestão cria a conversa de refino, chama `repo.setState(s.id, 'aplicada')` e navega para Prompt.
- `lib/features/prompt/conversation_manager.dart:132` `create({workspace, text, mode, model, providerId, images})`; `LiveState.approvalsOf(id)` (l.48) lista as `PendingApproval` da conversa; `selectedConversationProvider` (l.495).
- `lib/data/repos/conversations_repo.dart` `insert(...)`, `update(id, companion)`.
- `lib/data/db/app_database.dart:478` tabela `Conversations` (`mode`, `runConfig`…); `appSchemaVersion = 16` (l.18); as migrações de v8 em diante são geradas a partir de `drift_schemas/` (`dart run drift_dev schema steps`) e conferidas por `test/data/generated_migration_test.dart`.
- `lib/features/prompt/prompt_screen.dart:264` `_Header` com os botões "Transformar em spec" e "Continuar como sessão" (`SmallButton`) e `_snack`.
- `lib/features/specs/spec_service.dart:466` `SelectedSpec` / `selectedSpecProvider`, que também define o card do quadro com painel lateral (`board_screen.dart:280`, `selected`); `boardGraphViewProvider` (`board_screen.dart:181`); `specServiceProvider.sync(ws)`.
- `lib/features/prompt/widgets/answer_spec_bar.dart:72` `openSpecInSpecs(ref, spec)`; `lib/features/prompt/spec_from_answer.dart:209` `lineDiff(a, b)` (LCS, `DiffOp.same/add/del`).
- `lib/features/sessions/widgets/session_style.dart:83` `SmallButton`: `InkWell` sem `Semantics` explícito.
- `lib/ui/shell/app_shell.dart:292`: cada seção monta a tela de novo (sem `IndexedStack`). Por isso, ao voltar para Specs, `_load` já relê o disco. Só que o texto não salvo do editor se perde quando o usuário sai da tela.

### R1 · Guardar a origem na conversa
- Schema v17: colunas novas e anuláveis em `Conversations`, `refineSpecCode` (texto) e `refineOrigin` (texto `specs` | `board`). Para isso, `appSchemaVersion = 17`, dump em `drift_schemas/`, passos regenerados e `build_runner` (`app_database.g.dart`, `schema_versions.dart`).
- `ConversationsRepo.insert` e `ConversationManager.create` ganham `RefineOrigin? origin` (record `({String specCode, RefineSource source})`, com o enum `RefineSource { specs, board }` num arquivo novo `lib/features/prompt/refine_origin.dart`). O valor só é gravado quando `mode == PromptMode.refine`.
- `_refine` passa `(specCode: spec.code, source: specs)` e `card_extras.dart` passa `source: board`.
- Alternativa descartada: guardar a origem em `runConfig` (JSON). Mistura configuração de execução com navegação e fica difícil de consultar.

### R2 · R6 · R11 · Botão no cabeçalho
- No `_Header`, um `SmallButton` com a chave `prompt-back-to-spec` e o rótulo `Voltar à spec <código>`, mostrado só se `PromptMode.fromName(c.mode) == refine && c.refineSpecCode != null && c.refineOrigin != null`. Conversas antigas (colunas nulas) não exibem nada (R6).
- R11: o botão vem envolto em `Semantics(button: true, label: 'Voltar à spec <código>')`. O `InkWell` já recebe foco por Tab e aciona com Enter/Espaço; o foco visível usa `focusColor` do tema. Se o `SmallButton` não mostrar foco, acrescentar o parâmetro opcional `semanticLabel` e um `focusColor` nele, sem mudar o visual dos demais usos.

### R3 · R4 · R5 · R7 · R10 · Ação "Voltar"
- Função nova `backToSpec(BuildContext, WidgetRef, Conversation)` em `refine_origin.dart`. Ela:
  1. busca o workspace e a spec por código (`specsRepoProvider`, filtrando `code` no workspace) e confere se o arquivo existe com `specServiceProvider.read`.
  2. Se a spec não existir ou não for lida (removida ou renomeada), mostra o snack "A spec <código> não foi encontrada" e retorna sem navegar (R5).
  3. Senão, chama `specServiceProvider.sync(ws)` para atualizar requisitos e etapas a partir do disco e depois `selectedSpecProvider.select(spec.id)`.
     - Origem `specs`: `go(AppSection.specs)`. O `SpecsScreen` monta de novo e o `_load` relê o arquivo (R3).
     - Origem `board`: `boardGraphViewProvider.set(false)` e `go(AppSection.tasks)`. Com `selected`, o painel lateral abre no card. Para garantir o foco, o `SpecCard` com `selectedSpecProvider == id` faz `Scrollable.ensureVisible` no primeiro frame (R4).
- R7: a função não apaga a conversa nem chama `stop`, e `selectedConversationProvider` continua igual. Ao voltar para Prompt, a mesma conversa aparece.
- R10: a função não chama `approve`, `setState` de sugestão nem nada que mude `status` ou `stage`. O `setState('aplicada')` do card continua onde já está.

### R8 · Edição pendente
- Antes de navegar, `backToSpec` lê `conversationManagerProvider.approvalsOf(c.id)`. Se não estiver vazio, abre um `AlertDialog` (`prompt-back-pending-dialog`) com "Ficar na conversa" (`prompt-back-stay`, retorna sem navegar) e "Voltar mesmo assim" (`prompt-back-anyway`). A aprovação continua pendente; a conversa não é interrompida.

### R9 · Alterações não salvas
- Como a tela é desmontada ao trocar de seção, o texto não salvo hoje se perde. Novo `specUnsavedProvider` (`Notifier<Map<int, String>>`, em `specs_screen.dart`): o `dispose` do `_SpecsScreenState` guarda `_controller.text` quando `_dirty`.
- Em `_load`, se houver rascunho guardado para `spec.id` e ele for diferente do disco, abre `showSpecConflictDialog` (`specs-unsaved-dialog`). O diálogo mostra `lineDiff(disco, rascunho)` com linhas +/− e oferece "Manter minhas alterações" (o editor recebe o rascunho, `_saved = disco`, dirty) e "Carregar do disco" (descarta o rascunho). Fechar ou cancelar equivale a manter: nada é sobrescrito sem confirmação.
- Alternativa descartada: um resumo textual. A pergunta 3 da spec sugere diff, e `lineDiff` já existe.
- Risco: hoje `_refine` salva antes de abrir a conversa, então o conflito só ocorre se o usuário editar a spec em Specs durante o refino e sair sem salvar. Os testes precisam montar esse cenário (preencher `specUnsavedProvider` direto).

### Riscos
- Migração v17: esquecer o dump e os passos quebra `generated_migration_test`.
- Spec renomeada guarda o código antigo. A busca é por código, então o caso cai no R5, conforme pedido.
- Testes no quadro: largura ≥ 1440 e inserts com `await db.into(...)`, sem `runAsync`.
- `sync` lança exceção se `specs/` falhar. Nesse caso mostrar snack e não navegar.

## Etapas

- R1 → lib/data/db/app_database.dart, lib/data/repos/conversations_repo.dart, lib/features/prompt/conversation_manager.dart, lib/features/prompt/refine_origin.dart, lib/features/specs/specs_screen.dart, lib/features/board/widgets/card_extras.dart, drift_schemas/ · verificar: `flutter test test/data/generated_migration_test.dart test/features/specs test/features/board`
- R2 → lib/features/prompt/prompt_screen.dart · verificar: `flutter test test/features/prompt`
- R3 → lib/features/prompt/refine_origin.dart, lib/features/specs/specs_screen.dart · verificar: `flutter test test/features/specs`
- R4 → lib/features/prompt/refine_origin.dart, lib/features/board/board_screen.dart · verificar: `flutter test test/features/board`
- R5 → lib/features/prompt/refine_origin.dart · verificar: `flutter test test/features/prompt`
- R6 → lib/features/prompt/prompt_screen.dart · verificar: `flutter test test/features/prompt`
- R7 → lib/features/prompt/refine_origin.dart · verificar: `flutter test test/features/prompt`
- R8 → lib/features/prompt/refine_origin.dart · verificar: `flutter test test/features/prompt`
- R9 → lib/features/specs/specs_screen.dart, lib/features/prompt/spec_from_answer.dart · verificar: `flutter test test/features/specs`
- R10 → lib/features/prompt/refine_origin.dart · verificar: `flutter test test/features/specs`
- R11 → lib/features/prompt/prompt_screen.dart, lib/features/sessions/widgets/session_style.dart · verificar: `flutter test test/features/prompt && flutter analyze`

## Critérios de aceite

- [x] Ao refinar pela tela Specs, a conversa criada guarda o código da spec e a origem "Specs" [R1] verificar: flutter test test/features/specs
- [x] Ao aplicar uma sugestão do card, a conversa criada guarda o código da spec e a origem "quadro" [R1] verificar: flutter test test/features/board
- [x] Numa conversa de refino com origem, a tela Prompt mostra "Voltar à spec <código>" [R2] verificar: flutter test test/features/prompt
- [x] Em conversas Perguntar, Planejar e Editar, a ação não aparece [R2] verificar: flutter test test/features/prompt
- [x] Com origem Specs, ao acionar a ação depois de o agente editar o arquivo, a tela Specs abre com a spec selecionada e o conteúdo novo [R3] verificar: flutter test test/features/specs
- [x] Com origem card, ao acionar a ação o usuário volta ao quadro com o card da spec em foco e o conteúdo novo [R4] verificar: flutter test test/features/board
- [x] Com a spec removida ou renomeada, aparece o aviso e a tela Prompt continua aberta [R5] verificar: flutter test test/features/prompt
- [x] Numa conversa de refino sem origem guardada, a ação não aparece e nada quebra [R6] verificar: flutter test test/features/prompt
- [x] Depois de voltar, a conversa continua na lista e pode ser aberta de novo [R7] verificar: flutter test test/features/prompt
- [x] Com edição pendente de aprovação, o aviso aparece antes de voltar; "Voltar mesmo assim" navega e "Ficar na conversa" mantém a tela Prompt [R8] verificar: flutter test test/features/prompt
- [x] Com alterações não salvas na spec, o diálogo mostra o que foi editado e só sobrescreve após confirmação; cancelar mantém o editor intacto [R9] verificar: flutter test test/features/specs
- [x] Depois de voltar, o status da spec e o da sugestão aplicada continuam os mesmos de antes [R10] verificar: flutter test test/features/specs
- [x] A ação recebe foco por Tab, aciona com Enter ou Espaço e tem rótulo de acessibilidade [R11] verificar: flutter test test/features/prompt
- [x] A análise estática passa sem avisos novos [R1] [R2] [R3] [R4] [R5] [R6] [R7] [R8] [R9] [R10] [R11] verificar: flutter analyze

## Decisões

- Terminar de refinar equivale a "transformar em spec".
- Origem "Aplicar" no card volta ao card no quadro.
- Edição pendente de aprovação ao voltar: o sistema avisa (não bloqueia).
- Voltar só navega; não encerra a conversa.
- Alterações não salvas na spec: mostrar o que foi editado e perguntar.
- Voltar não altera o status; a spec continua em rascunho.
- O aviso de edição pendente tem duas opções: "Voltar mesmo assim" e "Ficar na conversa".
- (Pergunta 1) "Voltar à spec" é uma ação própria, separada de "Transformar em spec".
- (Pergunta 2) A sugestão `aplicada` continua `aplicada` ao voltar.
- (Pergunta 3) O diálogo de alterações não salvas mostra o diff (`lineDiff`).

## Perguntas em aberto

1. Como "transformar em spec" se relaciona com "Voltar à spec"? São duas ações separadas (voltar sem transformar) ou "transformar em spec" já leva de volta à spec? Os critérios acima assumem que "Voltar à spec" é uma ação própria e sempre disponível.
2. Uma sugestão já `aplicada` segue como `aplicada` ao voltar (como o R10 assume) ou deve voltar a "pendente"?
3. No diálogo de alterações não salvas (R9), "mostrar o que foi editado" é um diff entre o editor e o disco ou só um resumo das alterações? Sugestão: diff.


