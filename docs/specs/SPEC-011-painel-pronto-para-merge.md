---
id: SPEC-011
status: concluida
depende-de: [SPEC-009, SPEC-010]
---

# Review: painel "Pronto para merge?"

## Objetivo

Reunir num só lugar tudo que decide se uma spec (ou sessão) pode ser mergeada, e dizer com clareza **o que bloqueia, o que só merece atenção e o que está certo**. Hoje essa decisão está espalhada: o estado do revisor e os critérios ficam no painel da spec, as verificações das etapas e os checks do PR também, o conflito do PR no painel do PR, e o resto só aparece como erro depois que o usuário clica em "Fazer merge" (repositório principal na branch errada, alterações não commitadas na raiz, spec empilhada sobre outra ainda não mergeada).

- O painel não decide nada sozinho: cada item mostra um estado e a ação que o resolve. O merge continua sendo uma ação do usuário.
- Bloqueio = o que impede o merge hoje: o que `ReviewService.merge` recusa **mais** o revisor automático em andamento, que só a tela impede (o botão fica desabilitado em `review_screen.dart`; `merge` não olha `reviewPhase`). Cada item do painel registra a origem do bloqueio (`servico` ou `tela`). Aviso = o que não impede o merge, mas o usuário provavelmente quer saber antes.
- Não muda as regras de merge. A SPEC-012 acrescenta itens ao painel ao mudar o comportamento do merge local.
- Fora do escopo: mudar o que o revisor automático considera aprovado e aprovar o merge sem passar pelo botão.

## Requisitos

- R1 · O sistema deve mostrar, no cabeçalho do item do Review, um indicador de estado do merge com três valores (pronto, com avisos, bloqueado) e a contagem de bloqueios e avisos, e repetir o estado no item da fila lateral. O item da fila mostra o estado **parcial** (ver Design), marcado como tal; o cabeçalho do item selecionado mostra o estado completo.
- R2 · O sistema deve oferecer um painel "Pronto para merge?" com oito linhas, uma por verificação: `revisor` (revisor automático), `criterios` (critérios de aceite), `verificacoes` (verificações das etapas), `pr` (checks, conflito e decisão de review), `comentarios` (comentários abertos, SPEC-009), `empilhada` (spec empilhada), `raiz` (repositório principal: branch e árvore limpa) e `worktree` (existência do worktree e alterações não commitadas). Cada linha deve mostrar estado, motivo curto e a ação que leva ao ponto de resolução.
- R3 · O sistema deve classificar como **bloqueio** o que o merge local recusa hoje (critérios sem marcar, spec empilhada sobre dependência não mergeada, repositório principal fora da branch base ou com alterações rastreadas, sessão sem worktree próprio ou já mergeada) e o revisor ainda trabalhando (impedido só pela tela), e como **aviso** o restante (verificação de etapa falhando, checks do PR falhando ou pendentes, PR com conflito ou com mudanças pedidas, comentários abertos, alterações não commitadas no worktree).
- R4 · O botão "Fazer merge" deve refletir o estado: com bloqueio fica desabilitado e o tooltip lista os bloqueios; com avisos continua habilitado e o diálogo de confirmação lista os avisos. Os critérios sem marcar são um bloqueio **superável**: quando forem o único bloqueio de origem `servico` (e os demais itens estiverem sem bloqueio), o botão principal fica desabilitado e "Mergear mesmo assim…" fica habilitado e continua exigindo um motivo, como hoje; com qualquer outro bloqueio, os dois ficam desabilitados.
- R5 · O sistema deve recalcular o painel quando mudar qualquer fonte (rodadas, critérios, sessão, PR, estado do repositório principal), indicar enquanto verifica, e tratar uma verificação que falhou em ler como "não verificado", nunca como "ok": um item de bloqueio não verificado (`criterios`, `revisor`, `raiz`, `empilhada`, `worktree`) continua bloqueando e um item de aviso não verificado (`pr`, `verificacoes`, `comentarios`) continua sendo aviso.

## Design

### Modelo puro
- Novo `lib/features/review/merge_readiness.dart`: `ReadinessItem { id, label, level (ok, aviso, bloqueio, naoVerificado), detail, action? }` e `MergeReadiness { items, level }`. `level` do conjunto = o pior dos níveis efetivos. O nível efetivo de um item não verificado é o que ele teria se falhasse (o do bloqueio ou o do aviso da sua linha); `naoVerificado` é só um marcador de exibição ("não verificado") e o item é contado na categoria correspondente nas contagens do cabeçalho. O painel nunca mostra "pronto" com um item de bloqueio não verificado. Função pura `evaluateReadiness(ReadinessInputs)`, testável sem git: recebe fatos (fase do revisor, critérios pendentes, relatório do último gate por etapa, `PrStatus?`, comentários abertos, nome da dependência empilhada, branch atual e base da raiz, árvore da raiz suja, `uncommitted` do worktree, existência do worktree, sessão mergeada).
- `ReviewService.readinessInputs(sessionId)` junta os fatos que dependem de git (branch e `status` da raiz, `stackedOn`) e reaproveita `pendingCriteria`, `prAvailability` e `prView`. As mesmas condições são extraídas de `ReviewService.merge` para funções compartilhadas (`stackedOnOf`, `rootProblem`), para o painel e o merge **nunca divergirem**; `merge` continua recusando por conta própria.
- `mergeReadinessProvider(sessionId)` (`FutureProvider.family`), invalidado por `_refresh` da tela, pelos streams de `sessions`, `specs`, `spec_steps`, `review_comments` e `spec_criteria`, e pelo resultado de `PrBabysitter.check`.

### Itens e classificação
| Item | Bloqueio | Aviso | Ação |
| --- | --- | --- | --- |
| Revisor automático | `reviewPhase == auto` com a spec em Review (bloqueio de tela) | falhou e passou para você | "Pular revisor" |
| Critérios | algum sem marcar (bloqueio superável com motivo) | — | rolar até os critérios |
| Verificações das etapas | — | último `GateReport` de alguma etapa com `ok == false` | abrir a etapa |
| PR | — | check falhando ou pendente, `conflicting`, decisão `CHANGES_REQUESTED` | abrir o painel do PR |
| Comentários abertos | — | `resolved == false` (SPEC-009) | ir ao primeiro comentário aberto |
| Spec empilhada | dependência ainda não mergeada | — | abrir o item da dependência |
| Repositório principal | branch diferente da base (inclusive HEAD destacado) ou alterações rastreadas, sem contar arquivos não rastreados nem o arquivo da memória do projeto (`ProjectMemory.filePath`), como o merge faz | — | texto do comando necessário (a SPEC-012 oferece o botão) |
| Worktree | sem worktree próprio, já mergeada ou `mergeGuard` recusa | alterações não commitadas (serão commitadas antes) | — |

### Tela
- O indicador do cabeçalho usa as cores já existentes (verde, âmbar, vermelho) e o ícone ou texto, para não depender só da cor. O clique abre o painel.
- O painel é uma seção recolhível junto de `SpecReviewPanel` (`spec_review_panel.dart`), no topo, para specs e sessões sem spec. Sem spec, `revisor`, `criterios`, `verificacoes` e `comentarios` não existem e não são mostrados; `empilhada`, `raiz`, `worktree` e `pr` valem também para sessões sem spec (o merge calcula `stackedOn` com `spec?.id`, que pode ser nulo). Uma falha ao ler a branch base (`baseBranchOf`, "Falha ao ler a branch base") vira `naoVerificado` bloqueante em `worktree` e `empilhada`. Depois de um PR mergeado pelo app (`mergePr`), a sessão fica `merged` e sai da fila, junto com o painel.
- O item da fila lateral (`_QueueTile`) ganha um ponto de estado (verde, âmbar, vermelho) calculado só com os fatos baratos (sem git), para não recalcular git para toda a fila (DT-39). O estado completo é calculado para o item selecionado. Os fatos baratos são os que não usam git: `revisor` (fase da spec), `criterios` (leitura do arquivo da spec), `empilhada` (comparação de branches no banco) e a existência do worktree. `raiz`, `pr` e as alterações não commitadas do worktree exigem git ou rede e ficam de fora; por isso o ponto da fila é "parcial": desenhado só com contorno quando algum fato caro não foi verificado, e cheio para o item selecionado. Um ponto parcial nunca é verde: sem os fatos caros, o melhor estado é "não verificado por completo".

### R4 · Botão e diálogo
- `_ReviewMainState.canMerge` passa a depender do nível, em vez das condições soltas de hoje. O diálogo `showMergeDialog` lista os avisos antes do botão de confirmar. "Mergear mesmo assim…" (`showMergeOverrideDialog`) continua só para critérios.
- O texto do tooltip dos bloqueios é o mesmo texto das linhas do painel.

### R5 · Falhas de leitura
`gh` ausente, sem rede ou git falhando em um item vira `naoVerificado` com o erro; nunca vira "ok". O nível do item é o que ele teria se falhasse: `raiz`, `empilhada` e `worktree` (que o merge bloqueia, e onde uma falha de git faz `merge` lançar `ReviewException`) continuam **bloqueando** até serem verificados; `pr`, `verificacoes` e `comentarios` ficam como aviso. O painel mostra um botão "Verificar de novo".

### Riscos
- **Divergência** entre painel e merge se as regras forem duplicadas. Mitigação: funções compartilhadas e um teste que roda os dois sobre os mesmos fatos.
- **Custo de git** a cada recálculo: restringir o cálculo completo ao item selecionado e coalescer invalidações (um recálculo por quadro).
- **Falso "pronto"** se uma fonte falhar em silêncio: coberto pelo R5.

## Critérios de aceite

- [x] [R3] `evaluateReadiness` classifica como bloqueio cada condição que `ReviewService.merge` recusa e como aviso as demais, e o nível geral é o pior dos itens. verificar: `flutter test test/features/review/merge_readiness_test.dart`
- [x] [R3] Para cada item de bloqueio de origem `servico`, `merge` de fato recusa, e para cada aviso `merge` não recusa (mesmos fatos, repositório temporário real); o bloqueio do revisor, de origem `tela`, desabilita o botão (`canMerge`). O `merge` não muda. verificar: `flutter test test/features/review/review_service_test.dart`
- [x] [R1] O cabeçalho mostra pronto, avisos ou bloqueado, com a contagem, e o item da fila mostra o ponto de estado correspondente. verificar: `flutter test test/features/review/review_screen_test.dart`
- [x] [R2] O painel lista as oito linhas (`revisor`, `criterios`, `verificacoes`, `pr`, `comentarios`, `empilhada`, `raiz`, `worktree`), cada uma com estado, motivo e ação; numa sessão sem spec, `revisor`, `criterios`, `verificacoes` e `comentarios` não aparecem. verificar: `flutter test test/features/review/merge_readiness_test.dart`
- [x] [R4] Com bloqueio, "Fazer merge" fica desabilitado e o tooltip lista os bloqueios; com avisos, o diálogo lista os avisos antes de confirmar. verificar: `flutter test test/features/review/review_screen_test.dart`
- [x] [R4] Com os critérios como único bloqueio de origem `servico`, "Fazer merge" fica desabilitado e "Mergear mesmo assim…" fica habilitado e exige um motivo; com outro bloqueio, os dois ficam desabilitados. verificar: `flutter test test/features/review/review_screen_test.dart`
- [x] [R5] Mudar um critério, um comentário, o PR ou a branch da raiz recalcula o painel (a invalidação por streams e por `PrBabysitter.check`). verificar: `flutter test test/features/review/review_service_test.dart`
- [x] [R5] Uma fonte que falha aparece como "não verificado": em `raiz`, `empilhada` e `worktree` continua bloqueando; em `pr`, `verificacoes` e `comentarios` conta como aviso; nunca como "ok". verificar: `flutter test test/features/review/merge_readiness_test.dart`
- [x] [R1–R5] O código novo passa na análise estática e a suíte existente continua passando. verificar: `flutter analyze && flutter test`
- [ ] [R2, R4] Numa spec real com revisor, critérios e PR, o painel reflete o estado e o merge segue o que ele diz. verificar: manual (`flutter run -d linux`, Review de uma spec com PR e um critério sem marcar)

## Ordem de implementação

Sequência de implementação das specs do Review e do canvas: SPEC-009 → SPEC-010 → SPEC-011 → SPEC-012 → SPEC-013, e a SPEC-008 (independente) por último.

**Esta é a 3ª das 5 do Review.** Dependência real: SPEC-009 (item `comentarios`, coluna `resolved`). A SPEC-010 entra só pela ordem, para evitar conflitos em `review_screen.dart` (ver a SPEC-010). Vem antes da SPEC-012, que acrescenta itens a este painel.

## Perguntas em aberto

- Verificação de etapa falhando deveria ser **bloqueio** em vez de aviso? Hoje o merge não a considera, mas a spec só chega em Review depois que as etapas passam pelo gate, então o caso é raro.
- Checks do PR falhando deveriam bloquear o merge **local**? A spec assume que não (o merge local não olha o PR) e só avisa.
- O revisor automático em andamento bloqueia hoje só pelo botão da tela; `ReviewService.merge` não o recusa. O serviço deveria recusar também, para o bloqueio valer fora da tela? A spec assume que não (não muda as regras de merge) e marca a origem como `tela`.
