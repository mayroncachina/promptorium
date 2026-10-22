---
id: SPEC-012
status: concluida
depende-de: [SPEC-011]
---

# Review: merge local guiado

## Objetivo

Tornar o **merge local** do Review menos trabalhoso e mais previsível. Hoje o app recusa o merge quando o repositório principal não está na branch base ou tem alterações rastreadas, e deixa o usuário resolver no terminal; só faz merge `--no-ff`; só descobre um conflito ao tentar; e roda os hooks do usuário no commit de pendências sem avisar.

- O comportamento padrão **não muda** quando o repositório principal já está na branch base e sem alterações: `merge --no-ff`, com a mesma ordem de passos e as mesmas garantias de desfazer tudo em caso de falha (`ReviewService.merge`). Quando o usuário aceita a troca guiada (R1), voltar à branch anterior é o padrão.
- Cada novidade é uma escolha explícita do usuário no diálogo de merge. Nada acontece na raiz do repositório sem confirmação.
- Os itens novos aparecem também no painel da SPEC-011.
- Fora do escopo: resolver conflitos na interface (continua sendo pedir ao agente), merge pelo PR (já existe "Mergear PR"), e mudar a branch base de uma spec.

## Requisitos

- R1 · Quando o repositório principal estiver em outra branch, o diálogo de merge deve oferecer "Trocar para `<base>` e continuar" (`git switch`) e, por padrão, voltar à branch anterior depois do merge. Se a troca falhar, nada mais deve ser alterado e o erro do git deve aparecer.
- R2 · Quando o repositório principal tiver alterações rastreadas, o diálogo deve listá-las e oferecer, como opção desligada por padrão, guardá-las com `git stash` antes do merge e restaurá-las depois. Se restaurar falhar, o stash deve ser mantido e o usuário avisado de onde ele está.
- R3 · O diálogo deve permitir escolher o método do merge: merge commit (`--no-ff`, o atual), squash ou rebase com avanço rápido. O padrão vem do `config.yml` do projeto e, sem ele, continua sendo `--no-ff`. O diálogo deve dizer o efeito de cada método sobre o histórico, inclusive que o squash junta os commits de etapa. O rebase deve ficar indisponível, com o motivo, quando a branch já tem PR ou upstream, porque reescreveria uma branch publicada.
- R4 · Antes do merge, o sistema deve prever se haverá conflito, sem alterar nada, listar os arquivos em conflito e mostrá-lo como aviso no painel da SPEC-011. Se o git instalado não oferecer a previsão, deve mostrar "não verificado".
- R5 · Quando o merge parar por conflito, o sistema deve mostrar os arquivos em conflito e oferecer, no próprio diálogo de erro, "Resolver com o agente", que envia à sessão as instruções já existentes para integrar a base na branch.
- R6 · O diálogo deve informar que o commit de pendências do worktree roda os hooks do usuário e oferecer, como opção desligada por padrão, pular os hooks nesse commit.

## Design

### O que o merge faz hoje (`ReviewService.merge`)
Exige critérios marcados (ou motivo), worktree próprio, `mergeGuard`, spec empilhada já mergeada, raiz na branch base e sem alterações rastreadas; encerra a sessão (`release`); commita pendências no worktree; `git merge --no-ff -m … -- <branch>` na raiz; em falha, `merge --abort` e desfaz o commit de pendências (`reset`); em sucesso remove worktree e branch, marca sessão `merged`, fecha a spec (`_closeSpec`) e apaga o rascunho. Esta spec insere passos **antes** (R1, R2, R4, R6) e **variantes** do passo do merge (R3), sem alterar o resto.

### Opções
Novo `MergeOptions { method (merge, squash, rebase), switchBase, restoreBranch, stash, skipHooks }`, passado de `showMergeDialog` para `ReviewService.merge(options: …)`. O padrão equivale a `MergeOptions()` e reproduz o comportamento atual (teste de regressão sobre os comandos git que **alteram** o repositório).

### Ordem dos passos
1. Guardar as alterações rastreadas no stash, na branch em que a raiz está (R2).
2. Trocar para a base (R1).
3. Checagens de hoje (critérios, spec empilhada, árvore limpa).
4. `release` e commit de pendências no worktree (R6).
5. Merge pelo método escolhido (R3).
6. `_closeSpec`, que faz o commit "spec concluída" na raiz, **na base**.
7. Voltar à branch anterior (R1).
8. Restaurar o stash (R2), já na branch original.

O voltar (7) vem depois do `_closeSpec` (6) para o commit da spec cair na base.

### Falhas e desfazer
| Falha no passo | O que se desfaz |
| --- | --- |
| 1 (stash) | nada |
| 2 (troca de branch) | restaura o stash |
| 3 (checagens) | volta à branch anterior e restaura o stash |
| 4 (commit de pendências) | `reset` do commit de pendências (como hoje), volta e restaura |
| 5 (merge, squash ou rebase) | aborta o método (`merge --abort`, `reset --merge` ou `rebase --abort`), `reset` do commit de pendências (como hoje), volta e restaura |
| 6 (`_closeSpec`) | **nada do merge**: continua sendo só aviso, como hoje (`warnings`); segue para 7 e 8 |
| 7 (voltar à branch) | **não** restaura o stash (estaria na branch errada): avisa a branch atual e o sha do stash |
| 8 (restaurar o stash) | avisa o sha; o stash fica |

Se o próprio desfazer falhar, o app mostra um aviso final com o que ficou: a branch atual da raiz e o sha do stash guardado.

Com o arquivo da spec alterado pelo usuário (fora do stash, ver R2), `_closeSpec` grava `status: concluida` no disco sem commitar, como hoje (só commita com o arquivo limpo), e uma falha de hook nesse commit é só aviso: a raiz fica com a spec modificada e o aviso diz isso. Nenhum desses casos desfaz o merge.

### R1 · Troca de branch
- Antes de trocar de branch ou guardar o stash, a raiz **não pode** ter operação em andamento: `MERGE_HEAD`, `rebase-merge/` ou `rebase-apply/`, `CHERRY_PICK_HEAD` ou `REVERT_HEAD` em `.git`. Se houver, a opção é recusada com o motivo.
- `main.currentBranch()` já é lido. Com `current != base` e `switchBase`, rodar `git switch -- <base>` na raiz antes de qualquer outro passo. Guardar `previous` e, com `restoreBranch`, `git switch -- <previous>` ao final (sucesso ou falha). Com HEAD destacado, `previous` é o sha e voltar é `git switch --detach <sha>`.
- A troca é recusada pelo git se houver alterações que conflitem; o erro é mostrado e o merge não prossegue.

### R2 · Stash
- Só para alterações rastreadas (as que bloqueiam hoje; não rastreados não bloqueiam). `git stash push -m "promptorium-merge-<sessão>" -- . ":(exclude)<ProjectMemory.filePath>" ":(exclude)<spec.path>"`: o arquivo da memória do projeto (que o app escreve durante o merge) e o arquivo da spec (que `_closeSpec` edita e commita quando está limpo) não entram. `git stash push` sai com código 0 mesmo sem nada a guardar, então o app compara `git rev-parse -q --verify refs/stash` antes e depois: só considera que guardou algo se o topo do stash mudou, e guarda esse **sha**. Restaurar é `git stash apply --index <sha>` (tenta devolver também o que estava no índice, "staged"; se der conflito com `--index`, tenta sem ele e avisa que a separação entre staged e não staged foi perdida) (já existe `GitService.stashApply`) e, só se der certo, `git stash drop` do índice cujo sha confere (`git stash list --format=%H`). Nunca `stash pop`, que restauraria um stash antigo do usuário se nada tivesse sido guardado. Se restaurar falhar ou conflitar, **não** descartar nada: o stash fica na lista do git e o aviso diz o sha.
- Não usar `--include-untracked` (não mexer no que o git não rastreia) nem `--all`.
- Risco: o merge muda os mesmos arquivos que o stash. Nesse caso o `pop` conflita; é o caso do aviso acima.

### R3 · Métodos
- **merge** (atual): `git merge --no-ff -m … -- <branch>` na raiz.
- **squash**: `git merge --squash -- <branch>` e depois `git commit` com a mensagem de `reviewTitle` (o título que o merge commit usa depois de `Merge <branch>:`) e, no corpo, os assuntos dos commits integrados (`git log --format=%s <base>..<branch>`, no máximo 50 linhas e "…" se passar). O commit de pendências do worktree é desfeito (`reset`) em qualquer falha, em todos os métodos. Sem diferença a integrar, o `git commit` falha por não haver o que commitar: o erro "nada a integrar" é mostrado e a branch e o worktree ficam como estavam. Hook de commit que falha também faz `git reset --merge`. O `git branch -d` recusa uma branch que só entrou por squash ("not fully merged"), então o squash apaga a branch com `deleteBranch(force: true)` (`-D`), só depois de confirmar que o commit de squash existe na base. Conflito: `git reset --merge` (não há `MERGE_HEAD` depois do `--squash`, então `merge --abort` não serve). O histórico perde os commits de etapa; os checkpoints `refs/promptorium/<spec>/…` e o filtro "Etapa" deixam de funcionar para essa spec depois do merge, o que já vale hoje porque a branch é apagada (`_closeSpec` apaga os checkpoints).
- **rebase**: no **worktree**, `git rebase <base>` (o commit de pendências já foi feito); em conflito `git rebase --abort`. Antes do rebase, guardar a ponta (`git rev-parse HEAD` no worktree) também numa ref persistente `refs/promptorium/<spec>/pre-rebase`, apagada no sucesso (o `_closeSpec` já remove `refs/promptorium/<spec>/`), para um app que morra entre o rebase e o `--ff-only` não perder a branch original. Se passar, na raiz `git merge --ff-only -- <branch>`; se o `--ff-only` falhar (por exemplo, arquivos não rastreados que seriam sobrescritos), `git reset -q --hard <ponta>` no worktree, onde tudo já está commitado, devolve a branch ao estado anterior. Histórico linear e sem merge commit. O hash devolvido é o da ponta.
- `ProjectConfig` ganha `merge: metodo: merge|squash|rebase` (tabela das chaves em `project_config.dart`, com o teste de leitura e escrita já existente).
- Sempre `--` antes da referência, como hoje, e `_safeRef` nos nomes.

### R4 · Previsão de conflito
- `git merge-tree --write-tree --name-only <base> <branch>` (git ≥ 2.38) grava objetos no repositório, mas não toca índice nem árvore de trabalho. Código 0 = sem conflito; 1 = conflito, com os arquivos listados; qualquer outro (por exemplo 129, opção desconhecida em git mais antigo) = "não verificado". A previsão usa o HEAD da branch: alterações não commitadas do worktree, que só serão commitadas no merge, **não** entram, e o painel avisa isso. Para o método rebase, que reaplica commit a commit, a previsão é aproximada e é rotulada assim.
- O resultado entra no painel da SPEC-011 como item "Conflito previsto" (aviso) e no diálogo de merge. Não bloqueia: o merge real continua se desfazendo sozinho em conflito.
- Recalculada quando o HEAD da branch ou o HEAD da base mudam.

### R5 · Conflito no merge
Hoje o erro de conflito (`Conflito ao fazer merge de …`) tem texto fixo e o diálogo `showReviewError` só mostra a mensagem. Acrescentar ao diálogo o botão "Resolver com o agente" quando o erro for de conflito, chamando `ReviewService.resolveConflict` (que já envia `conflictMessage(base)` à sessão), e a lista de arquivos em conflito já calculada em `merge`. O erro de conflito passa a ser `MergeConflictException extends ReviewException`, com `files` (hoje `ReviewException` só tem `message`), e `showReviewError` mostra o botão quando recebe esse tipo. `resolveConflict` também passa a mover a tarefa para "Em execução", como `requestChanges` faz. O estado `_conflict` da tela continua alimentando o painel do PR.

### R6 · Hooks
`_commitPending` roda `git commit -q -m`, com os hooks do usuário (DT-37). Com `skipHooks`, usar `--no-verify` **somente** no commit de pendências do merge. Os commits que o merge faz na raiz (o do squash e o "spec concluída" de `_closeSpec`) continuam rodando os hooks, e `createPr`, que também usa `_commitPending`, não é afetado. O diálogo explica o risco: o commit pode não passar nas verificações que o projeto exige.

### Riscos
- **Rebase** reescreve a branch da spec: depois dele, rodadas anteriores (`commitSha`) deixam de existir na branch, o que afeta o diff desde a rodada da SPEC-010 (R4 dela trata o caso).
- **Troca de branch e stash** mexem na raiz do usuário: por isso são opções explícitas, desligadas por padrão (stash) ou confirmadas no diálogo (troca).
- **Squash** perde o histórico por etapa.

## Critérios de aceite

Os testes usam repositórios temporários reais, como os de `test/features/review/review_service_test.dart`.

- [x] [R1–R6] Com as opções padrão e a raiz já na base, `merge` executa os mesmos comandos git que **alteram** o repositório, na mesma ordem, e produz o mesmo resultado de hoje (um `GitService` injetado grava as chamadas; consultas só de leitura, como `merge-tree`, `status` e `rev-parse refs/stash`, ficam fora da comparação). verificar: `flutter test test/features/review/review_service_test.dart`
- [x] [R1] Com a raiz em outra branch, "Trocar para a base e continuar" troca, faz o merge e volta à branch anterior; se a troca falhar, nada é alterado e o erro do git aparece. verificar: `flutter test test/features/review/merge_options_test.dart test/features/review/review_service_test.dart`
- [x] [R2] Com alterações rastreadas na raiz e o stash ligado, o merge guarda, integra e restaura as alterações; se restaurar conflitar, o stash permanece e o aviso o menciona. verificar: `flutter test test/features/review/merge_options_test.dart test/features/review/review_service_test.dart`
- [x] [R3] Cada método produz o histórico esperado: `--no-ff` com merge commit, squash com um único commit com o título da spec, rebase com histórico linear e sem merge commit. verificar: `flutter test test/features/review/merge_options_test.dart test/features/review/review_service_test.dart`
- [x] [R3] O squash apaga a branch com `-D` depois de confirmar o commit de squash; um squash sem diferença mostra "nada a integrar" e não altera a branch nem o worktree; um hook de commit que falha desfaz com `reset --merge`. verificar: `flutter test test/features/review/merge_options_test.dart test/features/review/review_service_test.dart`
- [x] [R3] Se o `merge --ff-only` do rebase falhar, a ponta da branch volta ao valor anterior ao rebase; o rebase fica indisponível quando a branch tem PR ou upstream. verificar: `flutter test test/features/review/merge_options_test.dart test/features/review/review_service_test.dart`
- [x] [R2] Com apenas o arquivo da memória do projeto alterado, o stash não guarda nada e a restauração não toca nenhum stash antigo do usuário; com alterações rastreadas, restaura pelo sha e só então remove aquele stash. verificar: `flutter test test/features/review/merge_options_test.dart test/features/review/review_service_test.dart`
- [x] [R1] Com `MERGE_HEAD`, rebase ou cherry-pick em andamento na raiz, a troca de branch e o stash são recusados com o motivo. verificar: `flutter test test/features/review/merge_options_test.dart test/features/review/review_service_test.dart`
- [x] [R1, R2] Uma falha em cada passo de 2 a 8 desfaz o que a tabela "Falhas e desfazer" manda; se voltar à branch falhar, o stash não é restaurado e o aviso traz a branch atual e o sha. verificar: `flutter test test/features/review/merge_options_test.dart test/features/review/review_service_test.dart`
- [x] [R2] Com o arquivo da spec alterado pelo usuário, `_closeSpec` grava o status sem commit e avisa; uma falha de hook no commit dele é só aviso e o merge não é desfeito. verificar: `flutter test test/features/review/review_service_test.dart`
- [x] [R2] `stash apply --index` restaura o que estava no índice; com conflito, restaura sem `--index` e avisa. verificar: `flutter test test/features/review/merge_options_test.dart test/features/review/review_service_test.dart`
- [x] [R3] Depois de um rebase interrompido entre o rebase e o `--ff-only`, a ref `pre-rebase` guarda a ponta anterior. verificar: `flutter test test/features/review/merge_options_test.dart test/features/review/review_service_test.dart`
- [x] [R5] `resolveConflict` move a tarefa para "Em execução". verificar: `flutter test test/features/review/review_service_test.dart`
- [x] [R1, R2] Com troca de branch e stash, o commit "spec concluída" cai na branch base e a branch original volta depois dele; uma falha no meio desfaz tudo em ordem inversa. verificar: `flutter test test/features/review/merge_options_test.dart test/features/review/review_service_test.dart`
- [x] [R3] Conflito em cada método desfaz tudo (raiz e worktree como antes) e devolve a mensagem de conflito com os arquivos. verificar: `flutter test test/features/review/merge_options_test.dart test/features/review/review_service_test.dart`
- [x] [R3] O padrão do `config.yml` (`merge.metodo`) pré-seleciona o método; sem a chave, o padrão é `--no-ff`. verificar: `flutter test test/features/project/project_config_test.dart`
- [x] [R4] A previsão lista os arquivos que conflitariam sem alterar índice nem árvore, e mostra "não verificado" quando `git merge-tree --write-tree` não existe. verificar: `flutter test test/features/review/merge_options_test.dart test/features/review/review_service_test.dart`
- [x] [R5] O erro de conflito oferece "Resolver com o agente", que envia a mensagem de `conflictMessage` à sessão. verificar: `flutter test test/features/review/review_screen_test.dart`
- [x] [R6] Com hooks que falham num repositório temporário, o commit de pendências falha por padrão e passa com `skipHooks`; o diálogo avisa dos hooks. verificar: `flutter test test/features/review/merge_options_test.dart test/features/review/review_service_test.dart`
- [x] [R1–R6] O código novo passa na análise estática e a suíte existente continua passando. verificar: `flutter analyze && flutter test`
- [ ] [R1–R3] Num repositório real, merge com troca de branch, stash e squash, conferindo `git log` e `git stash list`. verificar: manual (`flutter run -d linux`, Review → Fazer merge)

## Ordem de implementação

Sequência de implementação das specs do Review e do canvas: SPEC-009 → SPEC-010 → SPEC-011 → SPEC-012 → SPEC-013, e a SPEC-008 (independente) por último.

**Esta é a 4ª das 5 do Review.** Depende da SPEC-011: acrescenta o item "Conflito previsto" ao painel dela e muda o merge que o painel descreve. Vem antes da SPEC-013 porque as duas alteram `ReviewService.merge`/`mergePr` e a SPEC-013 extrai a parte de PR para `ReviewHost`; mudar o merge local primeiro evita reescrever a extração.

## Perguntas em aberto

- O método padrão por spec ou por projeto? A spec assume por projeto (`config.yml`); uma spec com `merge:` no frontmatter poderia sobrescrever.
- O stash deve incluir arquivos não rastreados quando eles bloqueiam o merge (o git recusa se o merge os sobrescrever)? A spec assume que não.
