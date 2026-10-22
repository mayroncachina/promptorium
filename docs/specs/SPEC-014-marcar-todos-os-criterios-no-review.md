---
id: SPEC-014
status: rascunho
depende-de: []
---

# Review: marcar todos os critérios de aceite de uma vez

## Objetivo

Acrescentar ao painel da spec, no Review, um controle **"Marcar todos"** que marca de uma vez os critérios de aceite que o usuário já conferiu, em vez de um clique por critério. Hoje cada critério é marcado individualmente (`_CriterionTile`, `setCriterion`), e o merge só passa com todos marcados ou com um motivo em "Mergear mesmo assim…".

- O lote marca só critérios **elegíveis**: ainda sem marca e **sem** comando `verificar:`. Um critério com `verificar:` que a verificação (o gate) ainda não confirmou fica fora do lote e continua marcável um a um.
- O lote pede confirmação, conta como marca do usuário (`humano`, "por você") e tem "Desfazer".
- Desmarcar pelo controle tira **só** as marcas do usuário. Nunca as da verificação (`gate`) nem as do revisor automático (`revisor`).
- Não muda as regras de merge: com todos os critérios marcados, o merge passa sem motivo, como já acontece quando se marca um a um.
- Fora do escopo: marcar em lote na tela Specs (`step_trace_panel.dart`, que também marca critérios), alterar o arquivo da spec (`- [ ]` para `- [x]`) e mudar o que o revisor automático marca.
- Mockup de referência: [`docs/mockups/Review-Criterios.dc.html`](../mockups/Review-Criterios.dc.html) (tela interativa) e [`docs/mockups/Review-Criterios-Estados.dc.html`](../mockups/Review-Criterios-Estados.dc.html) (os estados do controle). Os dados do mockup são de exemplo.

## Requisitos

- R1 · O sistema deve mostrar, no cabeçalho de "Critérios de aceite" do painel da spec no Review, um controle "Marcar todos" com três estados (nenhum marcado, parcial, todos marcados), que informa quantos critérios são elegíveis e quantos aguardam a verificação. Numa spec sem critérios, o controle não deve aparecer.
- R2 · Ao acionar o controle com critérios elegíveis, o sistema deve pedir confirmação ("Marcar N critérios como verificados por você?"), dizer quantos ficam de fora por terem `verificar:` ainda não confirmado e, ao confirmar, marcar todos os elegíveis como `humano` numa única operação, tudo ou nada.
- R3 · O sistema deve deixar de fora do lote os critérios com `verificar:` que ainda não estão marcados, indicá-los na lista como "aguarda a verificação" e continuar permitindo marcá-los um a um, como hoje.
- R4 · Depois de marcar em lote, o sistema deve mostrar um aviso "N critérios marcados por você" com "Desfazer", que desmarca só os critérios daquele lote que ainda estiverem marcados por `humano`, e deve atualizar na hora o resumo da spec (`n/total critérios`), o texto "sem marcar" e o botão de merge ("Mergear mesmo assim…" ou "Fazer merge"), sem alterar nenhuma regra de `ReviewService.merge`.
- R5 · Quando não houver critério elegível e houver marcas do usuário, o controle deve passar a "Desmarcar os meus (N)", que remove só as marcas com `checkedBy = humano`, sem confirmação. Quando não houver nada a marcar nem a desmarcar, o controle deve ficar desabilitado e dizer o motivo (tabela de modos, no Design).
- R6 · O controle deve ser acessível: papel de caixa de seleção com estado "misto" quando parcial, operável por teclado (foco visível, Espaço aciona; a confirmação é sempre pedida, mesmo com um só critério elegível), e deve ficar desabilitado quando a sessão já foi mergeada ou o revisor automático ainda está trabalhando.

## Design

### O que já existe
- `lib/features/review/widgets/spec_review_panel.dart`: `SpecReviewPanel`, `criteriaProvider(specId)` (lista de `CriterionState = ({SpecCriterion criterion, SpecCriteriaData? mark})`), `criterionChecked`, `pendingCriteriaProvider`, `_CriterionTile` (chaves `review-criterion-<i>`; texto mostra `verificar: <comando>` e "por verificação | revisor automático | você | arquivo da spec").
- `ReviewCommentsRepo.setCriterion(specId, texto, checked:, by:)` (uma por vez, `insertOnConflictUpdate` em `spec_criteria`). Chamadores atuais: o painel (`by: 'humano'`), o revisor (`'revisor'`), o gate (`'gate'`, em `spec_runner.dart`) e a tela Specs.
- `SpecCriterion` (`spec_file.dart`) já traz `text`, `verify` (o comando) e `checkedInFile`. `parseCriteria` lê os critérios do arquivo da spec.
- `ReviewService.merge` exige `pendingCriteria(spec, ws)` vazio, ou um motivo (`mergeOverride`). Este recurso não o altera.

### Elegibilidade (R2, R3)
Um critério é **elegível** quando `!criterionChecked(state)` e `state.criterion.verify == null`. Um critério com `verify` não marcado é **aguardando a verificação**. O gate só o marca como `gate` quando **o relatório inteiro da verificação passou** e o critério cita uma etapa (`[Rn]`) entre as verificadas (`spec_runner.dart`, "Criteria with a `verificar:` that just passed are checked"). Por isso há dois casos, ambos **fora do lote**: com `[Rn]` (ainda não passou, ou o relatório falhou) a lista diz "aguarda a verificação"; **sem `[Rn]`** o gate nunca o marcará, e a lista diz "sem etapa: o gate não o marca, marque um a um". Os dois continuam marcáveis um a um. Função pura `batchPlan(List<CriterionState>)` devolve `(eligible, awaiting, mine)`, testável sem tela:
- `eligible`: os textos que o lote marca;
- `awaiting`: sem marca e com `verificar:`;
- `mine`: com `mark.checked && mark.checkedBy == 'humano'`.

Critério `- [x]` no arquivo da spec sem marca no banco conta como marcado ("por arquivo da spec") e não é elegível nem desmarcável pelo controle.

### Controle e modos (R1, R5, R6)
O modo vem de `batchPlan` e do estado de todos os critérios:

| Prioridade | Situação | Rótulo | Ação ao acionar |
| --- | --- | --- | --- |
| 1 | há elegíveis (`E > 0`) | "Marcar todos (E elegíveis · B aguardam a verificação)" | abre a confirmação (R2) |
| 2 | `E == 0` e `M > 0` | "Desmarcar os meus (M)"; se todos os critérios estão marcados: "Todos marcados · desmarcar os meus (M)" | desmarca `mine`, sem confirmação |
| 3 | `E == 0`, `M == 0` e `B > 0` | "Nada a marcar em lote · B aguardam a verificação", desabilitado | — (marcar um a um) |
| 4 | `E == 0`, `M == 0` e `B == 0` (todos marcados pela verificação, pelo revisor ou pelo arquivo) | "Todos marcados · nada meu para desmarcar", desabilitado | — |

A prioridade é a ordem da tabela: com elegíveis e marcas do usuário ao mesmo tempo, o controle marca (linha 1) e **não** desmarca; para desmarcar os seus enquanto ainda há elegíveis, o usuário desmarca um a um. `B` conta os dois casos de "aguardando" (com e sem `[Rn]`).

- O quadrado usa três estados visuais: vazio, traço (parcial) e marcado; o estado é **misto** quando há critérios marcados e não marcados, e `Semantics(checked/mixed)` o expõe. Não depende só da cor: o traço e o texto dizem o estado.
- O controle é um único alvo de foco (`Focus` com a chave `review-criteria-master`, Espaço/Enter), com decoração de foco (borda âmbar quando `hasFocus`, conferida no teste de widget), com o mesmo estilo dos botões pequenos do painel (`SmallButton`).
- Desabilitado também quando `session.status == merged` (como "Pedir ajustes", em `review_screen.dart`) ou quando o revisor automático está trabalhando (`reviewPhase == auto`, o mesmo critério de `canMerge`).

### Confirmação (R2)
Diálogo no padrão de `review_dialogs.dart` (`ReviewDialogFrame`): título "Marcar N critérios como verificados por você?"; corpo: "B ficam de fora: têm um comando `verificar:` que a verificação ainda não confirmou (dá para marcar um a um). O que a verificação e o revisor já marcaram não muda, e dá para desfazer logo depois." (a frase sobre os que ficam de fora só aparece quando `B > 0`). Botões "Cancelar" e "Marcar N". Confirmar com Enter, cancelar com Esc.

### Operação em lote (R2)
Novo `ReviewCommentsRepo.setCriteria(specId, List<String> textos, {required bool checked, required String by})`, que faz tudo numa `_db.transaction`, com o mesmo `insertOnConflictUpdate` por critério, e devolve a lista de textos efetivamente alterados. Dentro da mesma transação ele **relê** as marcas e, ao marcar, só escreve nos que ainda estão sem marca (o gate ou o revisor podem ter marcado enquanto o diálogo estava aberto). Se qualquer escrita falhar, nenhuma vale. O aviso do R4 usa o N **efetivamente marcado**, que pode ser menor que o N do diálogo; se for 0, nada muda e o aviso diz "nada mudou". Para desmarcar (R5) e desfazer (R4) existe também `uncheckHumanOnly(specId, textos)`, que lê e escreve **na mesma transação**, só desmarca as linhas cujo `checkedBy` ainda é `humano` (uma marca que o gate ou o revisor refizeram entre o lote e o desfazer não é desfeita) e devolve os textos efetivamente desmarcados.

### Desfazer (R4)
Depois do lote, `SpecReviewPanel` guarda em estado de tela (efêmero) a lista de textos do lote e mostra um `SnackBar` (como `_toast` de `review_screen.dart`, que dura 8 segundos) com "N critérios marcados por você" e a ação "Desfazer", que chama `uncheckHumanOnly`. A janela de desfazer é a duração do aviso: quando ele some (ou o usuário marca ou desmarca um critério individualmente, ou muda de item da fila), a lista guardada é descartada. O resumo, "n sem marcar" e o botão de merge já derivam de `criteriaProvider`/`pendingCriteriaProvider`, então atualizam sozinhos.

### Lista (R3)
`_CriterionTile` mostra "· aguarda a verificação" (âmbar) para critério com `[Rn]` e `verificar:` ainda sem marca, e "· sem etapa: o gate não o marca" para critério com `verificar:` e sem `[Rn]`; o texto "por …" continua para os marcados.

### Riscos
- **Atalho para o merge.** O lote é um atalho para passar pelo critério de merge; por isso a confirmação, a exclusão dos critérios com `verificar:` ainda não confirmados, a marca "por você" em cada critério e o "Desfazer".
- **Concorrência.** O gate ou o revisor podem marcar critérios enquanto o diálogo está aberto. A confirmação recalcula `eligible` no momento de confirmar e marca só o que ainda não estiver marcado.
- **Critério com `verificar:` que nunca passará** (comando quebrado) ou **sem `[Rn]`** (o gate nunca o marca) fica sempre fora do lote; o usuário o marca à mão se decidir. É o comportamento pedido: nada de marcar em lote o que tem comando de verificação.
- **Conflito de merge de código** com a SPEC-011 em `spec_review_panel.dart` (ver "Ordem de implementação"); não é dependência funcional.

## Critérios de aceite

Os testes marcados "(a criar)" fazem parte da implementação.

- [ ] [R1] O painel mostra o controle "Marcar todos" no cabeçalho dos critérios, com o texto "(E elegíveis · B aguardam a verificação)", e nenhum controle numa spec sem critérios. verificar: `flutter test test/features/review/spec_review_panel_test.dart`
- [ ] [R1] O quadrado mostra vazio com nenhum marcado, traço com parcial e marcado com todos, e expõe o estado misto à acessibilidade. verificar: `flutter test test/features/review/spec_review_panel_test.dart`
- [ ] [R2] Acionar o controle abre a confirmação com a contagem de elegíveis e a de critérios que ficam de fora; confirmar marca só os elegíveis como `humano`; cancelar não altera nada. verificar: `flutter test test/features/review/spec_review_panel_test.dart`
- [ ] [R2] Um critério `- [x]` no arquivo da spec, sem marca no banco, não é elegível, nem aguardando, nem `mine`. verificar: `flutter test test/features/review/batch_plan_test.dart` (a criar)
- [ ] [R2] `batchPlan` separa elegíveis (sem marca e sem `verificar:`), aguardando (sem marca e com `verificar:`) e as marcas do usuário; critérios marcados no arquivo da spec não entram em nenhum grupo. verificar: `flutter test test/features/review/batch_plan_test.dart` (a criar)
- [ ] [R2] `setCriteria` é tudo ou nada: com uma `QueryExecutor` de teste que falha na segunda inserção, a primeira é revertida e nenhum critério muda. verificar: `flutter test test/data/repos_test.dart`
- [ ] [R2] `setCriteria` relê as marcas dentro da transação: um critério que o gate marcou depois de aberto o diálogo não é sobrescrito, e o N devolvido é o efetivo (0 mostra "nada mudou"). verificar: `flutter test test/data/repos_test.dart`
- [ ] [R4] `uncheckHumanOnly` lê e escreve na mesma transação e só desmarca linhas `humano`. verificar: `flutter test test/data/repos_test.dart`
- [ ] [R3] Um critério com `[Rn]` e `verificar:` ainda sem marca aparece como "aguarda a verificação"; um critério com `verificar:` e sem `[Rn]` aparece como "sem etapa: o gate não o marca"; nenhum dos dois entra no lote e os dois podem ser marcados individualmente. verificar: `flutter test test/features/review/spec_review_panel_test.dart`
- [ ] [R3] Um critério com `verificar:` e sem `[Rn]` não é marcado pelo gate nem com o relatório da verificação ok, e continua fora do lote. verificar: `flutter test test/features/board/spec_runner_test.dart` (a criar o caso)
- [ ] [R3] Um critério com `verificar:` ainda sem marca não entra no lote. verificar: `flutter test test/features/review/spec_review_panel_test.dart`
- [ ] [R4] Depois do lote aparece "N critérios marcados por você" com "Desfazer"; desfazer desmarca só o lote e só o que ainda é `humano` (uma marca que o gate refez fica); o resumo e o botão de merge mudam em cada passo. verificar: `flutter test test/features/review/spec_review_panel_test.dart`
- [ ] [R4] Marcar ou desmarcar um critério individualmente descarta o "Desfazer" do lote. verificar: `flutter test test/features/review/spec_review_panel_test.dart`
- [ ] [R5] Sem elegíveis e com marcas do usuário, o controle vira "Desmarcar os meus (N)" e remove só as marcas `humano`; as marcas `gate` e `revisor` permanecem. verificar: `flutter test test/features/review/spec_review_panel_test.dart`
- [ ] [R5] Cada linha da tabela de modos produz o rótulo e o estado (habilitado ou não) descritos, e com elegíveis e marcas do usuário ao mesmo tempo o controle marca e não desmarca. verificar: `flutter test test/features/review/batch_plan_test.dart` (a criar)
- [ ] [R5] Sem nada a marcar nem a desmarcar, o controle fica desabilitado e mostra o motivo. verificar: `flutter test test/features/review/spec_review_panel_test.dart`
- [ ] [R6] O controle é alcançável pelo teclado, mostra a decoração de foco quando `hasFocus` e é acionado por Espaço; fica desabilitado com a sessão mergeada ou com o revisor automático trabalhando. verificar: `flutter test test/features/review/spec_review_panel_test.dart`
- [ ] [R4] O aviso com "Desfazer" some após 8 segundos e a lista guardada é descartada; "Desfazer" depois disso não faz nada. verificar: `flutter test test/features/review/spec_review_panel_test.dart`
- [ ] [R4] Com todos os critérios marcados pelo lote, `ReviewService.merge` não exige motivo (nenhuma regra de merge muda). verificar: `flutter test test/features/review/review_service_test.dart`
- [ ] [R1–R6] O código novo passa na análise estática e a suíte existente continua passando. verificar: `flutter analyze && flutter test`
- [ ] [R1–R5] Numa spec real com critérios marcados pelo gate, pelo revisor e por você, marcar em lote, desfazer e desmarcar se comportam como no mockup. verificar: manual (`flutter run -d linux`, Review de uma spec com critérios, conferir contra `docs/mockups/Review-Criterios.dc.html`)

## Ordem de implementação

Independente das outras specs do Review e sem `depende-de`. Sugerida depois da SPEC-011, que também altera `spec_review_panel.dart` (acrescenta o painel "Pronto para merge?" e a linha `criterios`); a linha já reflete o novo lote sozinha, porque lê `pendingCriteriaProvider`. A ordem é só para evitar conflito de merge no mesmo arquivo, não uma dependência funcional.

## Perguntas em aberto

- A tela Specs (`step_trace_panel.dart`) também marca critérios um a um. O lote deve existir lá também? A spec assume que não (pedido só para o Review).
- O texto "por você" distingue o lote da marca individual? A spec assume que não (ambos são `humano`); o desfazer só vale logo depois do lote.
- Critérios com `verificar:` cujo comando falhou no gate (e não só "ainda não rodou") merecem um destaque diferente na lista (por exemplo, vermelho)? A spec os trata como "aguarda a verificação" (o gate só marca critérios quando o relatório inteiro passa, então não distingue os dois casos).
