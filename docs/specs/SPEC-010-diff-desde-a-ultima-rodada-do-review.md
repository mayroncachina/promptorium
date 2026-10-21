---
id: SPEC-010
status: rascunho
depende-de: []
---

# Review: diff desde a última rodada

## Objetivo

> Dependência opcional da SPEC-009: o R5 só fica ativo quando ela estiver implementada (reutiliza `comment_anchor.dart`, que ela cria). Os outros requisitos não dependem de nada, por isso o `depende-de` é vazio.

Permitir que o usuário veja **só o que mudou desde uma rodada de review**, para conferir se o agente corrigiu o que foi pedido sem reler a branch inteira. Cada rodada (do revisor automático, do usuário ou do PR) já guarda o commit que foi revisado; falta uma visão que use isso.

- A visão é um filtro do Review, ao lado de "Todas as etapas": "Alterações desde…".
- É só leitura, como o filtro por etapa. Rejeitar hunk, aceitar e comentar continuam disponíveis só na visão normal.
- Não muda o merge nem o que o revisor automático vê.
- Fora do escopo: comparar duas rodadas quaisquer entre si e mostrar o diff de uma rodada específica isolada.

## Requisitos

- R1 · O sistema deve oferecer, no Review de uma spec com rodadas anteriores, o filtro "Alterações desde…" com a lista de rodadas (número, autor, veredito e data) e a opção "Desde a última rodada" como atalho.
- R2 · Ao escolher uma rodada, o sistema deve mostrar o diff entre o commit revisado naquela rodada e o estado atual do worktree (commits novos e alterações não commitadas), com os mesmos controles de visualização (um ou todos os arquivos, unificado ou lado a lado).
- R3 · O sistema deve indicar no cabeçalho do diff quantos commits e arquivos mudaram desde a rodada e marcar, na lista lateral, os arquivos que não mudaram desde então como "sem alterações".
- R4 · Quando a rodada não tiver commit gravado (comentário do PR, rodada antiga) ou o commit já não existir na branch (reescrita de histórico), o sistema deve desabilitar a escolha com o motivo, em vez de mostrar um diff errado ou vazio.
- R5 · Quando houver comentários do revisor ou do usuário daquela rodada (SPEC-009), o sistema deve mostrá-los sobre o diff desde a rodada, com o estado atual de cada um, para o usuário comparar o pedido com a correção.

## Design

### Dados que já existem
- `review_comments` guarda `round`, `author`, `verdict` (na primeira linha da rodada) e `commitSha` (HEAD do worktree quando a rodada foi gravada: `AutoReviewer._review` usa `git.headSha()` e `ReviewService.requestChanges` faz o mesmo). Comentários do PR (`author = pr`) não têm `commitSha`.
- `ReviewService.loadStep(sessionId, step)` é o modelo: devolve um `ReviewDetail` só leitura. O filtro de etapa e seu estado vivem em `_ReviewMainState._step` (`review_screen.dart`).

### Escopo do filtro
- `_step` (etapa) e a nova rodada são **excludentes**: escolher uma limpa a outra. O `DropdownButton` atual ganha um segundo, "Alterações desde…", ao lado.
- Novo `reviewSinceProvider((sessionId, sha))` com `ReviewService.loadSince(sessionId, sha)`: `git diff --no-color --no-ext-diff --unified=3 -M <sha>` no worktree (compara o commit com o working tree, como o diff normal compara o merge-base) mais os arquivos não rastreados, reaproveitando `_untrackedDiff`. A contagem de commits vem de `rev-list --count <sha>..HEAD`.
- R4: antes de oferecer a rodada, `git cat-file -e <sha>^{commit}` e `git merge-base --is-ancestor <sha> HEAD`. Dois motivos, com texto próprio: rodada sem `commitSha` (comentário do PR ou rodada antiga) → "esta rodada não registrou o commit revisado"; commit ausente ou fora da branch → "o commit da rodada não existe mais nesta branch". A verificação roda uma vez por rodada ao abrir o filtro e o resultado fica no provider, com chave `(sessionId, headSha, rodada)`, e é invalidado junto com `reviewDetailProvider` (`_refresh`, rejeitar hunk, merge), porque um commit novo ou uma reescrita de histórico muda o resultado (poucas rodadas, custo baixo).
- "Desde a última rodada" é a rodada mais recente com `commitSha` válido.
- Se `HEAD == sha` e não há alterações não commitadas, o diff é vazio e a tela diz "Nada mudou desde a rodada N", em vez da mensagem de erro de diff vazio.

### R3 · Marcação dos arquivos
Comparar a lista de arquivos do diff desde a rodada com a do diff completo (`reviewDetailProvider`): arquivos só do segundo ficam com o selo "sem alterações" e esmaecidos na lista lateral; clicar neles mostra o diff completo daquele arquivo, rotulado "diff completo desde a base da branch" para não ser confundido com mudança nova desde a rodada. No cabeçalho, `n` é o número de arquivos do diff desde a rodada (não rastreados incluídos, renomeado contado uma vez) e `k` vem de `rev-list --count <sha>..HEAD`; `k` pode ser 0 com `n > 0` quando só há alterações não commitadas.

### R5 · Comentários sobre o diff desde a rodada
Reutiliza a âncora de comentários da SPEC-009 (`comment_anchor.dart`), com a base trocada para `<sha>`. Sem a SPEC-009 implementada, esta spec funciona sem o R5, que fica desabilitado.

### Riscos
- Rodadas do usuário e do revisor gravam o HEAD do worktree no momento da rodada, mas o agente pode ter feito commits **depois** de o revisor ter lido o diff e **antes** de a rodada ser gravada (corrida pequena). O diff desde a rodada pode então omitir a última mudança que o revisor não viu. Aceitável; o rótulo diz "commit da rodada", não "o que o revisor viu".
- `git diff <sha>` inclui arquivos ignorados? Não: só rastreados e os não rastreados listados por `git status`, o mesmo do diff normal.

## Critérios de aceite

- [ ] [R1] Com duas rodadas gravadas, o filtro lista as duas com autor, veredito e data, e "Desde a última rodada" escolhe a mais recente. verificar: `flutter test test/features/review/review_since_test.dart` (a criar)
- [ ] [R2] Num repositório temporário real com uma rodada no commit A, um commit B depois e uma alteração não commitada, o diff mostra B e a alteração e não mostra o que veio até A. verificar: `flutter test test/features/review/review_service_test.dart`
- [ ] [R2] Os controles de visualização (um ou todos os arquivos, unificado ou lado a lado) valem no diff desde a rodada; rejeitar e aceitar hunk ficam desabilitados. verificar: `flutter test test/features/review/review_since_test.dart` (a criar)
- [ ] [R3] O cabeçalho mostra "k commits · n arquivos desde a rodada N" e os arquivos que não mudaram aparecem como "sem alterações". verificar: `flutter test test/features/review/review_since_test.dart` (a criar)
- [ ] [R3] Com 0 commits novos e apenas uma alteração não commitada, o cabeçalho mostra "0 commits · 1 arquivo desde a rodada N". verificar: `flutter test test/features/review/review_since_test.dart` (a criar)
- [ ] [R3] Um arquivo renomeado e um arquivo não rastreado entram no `n` do cabeçalho, cada um contado uma vez. verificar: `flutter test test/features/review/review_since_test.dart` (a criar)
- [ ] [R1] Uma rodada sem veredito (rodada do usuário ou do PR) aparece na lista como "sem veredito". verificar: `flutter test test/features/review/review_since_test.dart` (a criar)
- [ ] [R4] Uma rodada do PR (sem `commitSha`) e uma rodada cujo commit foi removido da branch aparecem desabilitadas, cada uma com o próprio motivo. verificar: `flutter test test/features/review/review_since_test.dart` (a criar)
- [ ] [R2] Sem nada novo desde a rodada, a tela mostra "Nada mudou desde a rodada N". verificar: `flutter test test/features/review/review_since_test.dart` (a criar)
- [ ] [R5] Os comentários da rodada escolhida aparecem sobre o diff desde a rodada, com o estado atual (aberto ou tratado). verificar: `flutter test test/features/review/review_since_test.dart` (a criar, depende da SPEC-009)
- [ ] [R1–R5] O código novo passa na análise estática e a suíte existente continua passando. verificar: `flutter analyze && flutter test`
- [ ] [R2] Numa spec real que passou por uma rodada de correção do revisor, o diff desde a rodada mostra só a correção. verificar: manual (`flutter run -d linux`: 1) numa spec com revisor ligado, deixar o revisor pedir uma correção; 2) esperar a etapa `REVn` terminar; 3) abrir o Review e escolher Alterações desde… → Desde a última rodada)

## Perguntas em aberto

- O filtro por etapa e o filtro por rodada devem poder ser combinados (a rodada 2 restrita à etapa R3)? A exclusão mútua é a decisão provisória desta spec.
- Vale gravar também o commit no momento em que o usuário **abre** o Review, para a opção "desde a minha última visita"? A spec assume só rodadas.
- Rodadas do PR (`author = pr`) poderiam gravar o commit da branch no momento da leitura. Hoje não gravam, e por isso ficam desabilitadas (R4).
