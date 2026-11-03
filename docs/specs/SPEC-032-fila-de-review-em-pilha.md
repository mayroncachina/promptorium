---
id: SPEC-032
status: rascunho
---

# Fila de Review em pilha: merge de baixo para cima, sem conflito de base

## Objetivo

A tela de Review lista as specs na ordem das sessões, sem considerar quem depende de quem. Esse é o motivo da maioria dos conflitos:

1. **Pilha com squash.** Uma spec criada em cima de outra (SPEC-031 sobre a SPEC-029) carrega os commits originais da mãe. Quando a mãe entra na `main` por squash, ela vira um commit novo. Para o git, a filha passa a ter as mesmas mudanças em commits diferentes, e o merge dela conflita. Hoje nada refaz a base da filha: `baseBranchOf` só passa a usar a `main` quando a branch da mãe é apagada.
2. **Raiz fora da `main` ou suja.** O merge local exige que a raiz do projeto esteja na branch base e limpa (`rootProblem`). Um `git switch` feito à mão na raiz, para testar uma branch, trava o merge. O aviso só aparece ao clicar em "Fazer merge".
3. **Depois do merge, a tela não continua.** A seleção volta ao primeiro item da fila, que pode ser uma spec que ainda depende de outra.

Esta spec ordena a fila como uma pilha, da base para o topo, e segue para o próximo item depois de cada merge. Ela também refaz sozinha a base das filhas quando a mãe entra e mostra os problemas da raiz na própria fila. Para testar uma branch sem trocar a raiz, a tela ganha "Testar", "Terminal" e "Editor", que abrem no worktree da spec.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/MczasWNKVPLQAm2fvhU9Xf). Cópia dos artboards e capturas em `docs/mockups/spec-032/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `0-hoje.png` | A tela de hoje: fila plana, cabeçalho com seis ações e o aviso da raiz só no merge | — |
| `1-pilha.png` | Fila em pilha: SPEC-029 na base, SPEC-031 em cima e SPEC-030 sozinha; o cabeçalho tem uma ação primária e a barra do worktree | R1–R4, R8–R10 |
| `5-mais.png` | O menu "Mais", com "Mergear a pilha" e as ações secundárias | R8, R13 |
| `6-muitas.png` | Fila com oito specs: uma pilha de 3, uma de 2 e três avulsas | R1–R3 |
| `7-grafo.png` | Grafo das ramificações do merge: a `main` como tronco embaixo, cada pilha como um galho, o conflito previsto entre avulsas e o "próximo" | R16 |
| `8-resolver.png` | Resolver conflito: com o agente (recomendado) ou eu mesmo, vendo os dois lados do trecho | R7, R17 |
| `9-eu-mesmo.png` | Rebase em andamento no worktree: trechos resolvidos e pendentes, "Continuar rebase" e "Desistir" | R17 |
| `2-depois-do-merge.png` | Depois do merge da SPEC-029: a base da SPEC-031 foi refeita sobre a `main` e ela foi selecionada sozinha | R5–R7 |
| `3-conflito.png` | A base refeita conflitou: o card e o cabeçalho mostram "Resolver conflito" | R6, R7 |
| `4-raiz.png` | A raiz está em outra branch: aviso fixo na fila, com "Voltar para a main" | R11, R12 |

## Requisitos

- R1 · A fila "Aguardando review" deve seguir a **ordem das dependências**: uma spec só aparece depois daquela de cuja branch ela nasceu (`base_branch` = branch da mãe). Entre specs sem relação, vale a onda (`dependencyWaves`) e depois o código da spec. Itens sem spec (tarefas) ficam no fim.
- R2 · Specs empilhadas devem aparecer **agrupadas como pilha**:
  - um trilho vertical liga os cards da base ao topo;
  - cada card mostra a posição ("1 de 2") e "sobre SPEC-029" quando tiver mãe;
  - a ordem de leitura é de cima para baixo, com a base primeiro. "De baixo para cima" se refere à pilha de branches, não à tela: o próximo merge é sempre o primeiro card da pilha;
  - specs sem mãe nem filhas ficam num grupo próprio, "Avulsas · n", separado das pilhas;
  - os títulos de seção da tela ("Aguardando review · 3", "Arquivos · 4") ficam em caixa normal, sem a caixa-alta espaçada de hoje.
- R3 · O card de cada spec deve mostrar o **estado de merge** com ícone e texto curto, não só com cor:
  - "Pronto para merge";
  - "Espera SPEC-029" (a mãe ainda não entrou);
  - "Conflito em `arquivo`" (há conflito previsto com a base);
  - "Revisor revisando";
  - "Pendências" (critérios, comentários ou verificações).
- R4 · A previsão de conflito (`predictConflict`) deve rodar para cada item da fila em segundo plano, com no máximo uma verificação de git por vez, e ser refeita quando a base ou a branch mudarem. Até lá, o card mostra "Verificando…".
- R5 · Depois de um merge bem-sucedido, a tela deve **selecionar o próximo item** da fila: a filha da spec mergeada, se houver; senão, o próximo da ordem de R1. Um aviso diz "SPEC-029 entrou na main · seguindo para SPEC-031".
- R6 · Depois que uma spec entra na base, o sistema deve **refazer a base das filhas diretas** sem pedir confirmação:
  - **merge local:** `git rebase --onto <base> <ponta antiga da mãe> <filha>`, rodado no worktree da filha. A ponta antiga é guardada antes do merge em `refs/promptorium/<spec>/base-antiga`;
  - **PR:** o mesmo rebase, depois `git push --force-with-lease` e `gh pr edit --base <base>` no PR da filha, para ele não fechar nem ficar com a base errada;
  - `base_branch` da sessão da filha passa a ser a base da mãe;
  - o rebase só começa com o worktree da filha limpo e com nenhuma sessão viva nele. Se não for possível, a filha fica com "Base desatualizada · Refazer agora".
- R7 · Se o rebase de R6 conflitar, o sistema deve abortá-lo (`git rebase --abort`), deixar a branch como estava e marcar a filha com **"Conflito ao refazer a base"**:
  - a ação primária vira "Resolver conflito", que manda o agente da spec refazer o rebase e resolver os conflitos no worktree dela;
  - "Ver arquivos" lista os arquivos em conflito;
  - a mesma regra vale para o conflito com a `main` de uma spec avulsa, quando outra spec que mexe nos mesmos arquivos entra antes dela.
- R8 · O cabeçalho da spec selecionada deve ter **uma ação primária por estado**, com as demais num menu "Mais":
  - pronto → "Fazer merge" (ou "Mergear PR", se houver PR);
  - espera a mãe → "Ir para SPEC-029";
  - conflito → "Resolver conflito";
  - pendências → "Pedir ajustes ao agente";
  - revisor revisando → nenhuma ação primária, só o estado.

  "Criar PR", "Rascunho", "Mergear mesmo assim…" e "Preparar merge local…" vão para o menu "Mais". O botão "Mais" informa se o menu está aberto (`Semantics(expanded:)`).

  Quando a ação primária não puder rodar (por exemplo, com a raiz fora da `main`), ela fica desabilitada de verdade, sem foco nem clique, e o motivo aparece em texto logo abaixo do título, ligado ao botão no rótulo semântico.
- R9 · Abaixo do cabeçalho, uma **barra do worktree** deve mostrar o caminho do worktree e a branch e oferecer três botões, sem trocar a branch da raiz:
  - "Testar": roda o comando de execução do projeto (`runCommand`, nova chave de `.promptorium/config.yaml`) num terminal, dentro do worktree. Sem `runCommand`, o botão abre o diálogo de configuração com o campo em foco;
  - "Terminal": abre o terminal do sistema no worktree;
  - "Editor": abre o worktree no editor configurado (`editorCommand`, padrão `code`), ou no gerenciador de arquivos se o editor não existir.
- R10 · Clicar num card **só seleciona** a spec. Nunca troca a branch da raiz.
- R11 · Quando a raiz estiver fora da branch base ou tiver alterações rastreadas não commitadas, a fila deve mostrar um **aviso fixo no topo**, antes de qualquer merge. Ele diz o que está errado ("A raiz está em spec/031-…, o merge vai para main") e oferece:
  - "Voltar para a main" (`git switch <base>`), habilitado só com a raiz limpa;
  - com alterações, "Guardar alterações" (`git stash push -m promptorium`) e, em seguida, "Voltar para a main".
- R12 · O aviso de R11 deve ser atualizado pelo vigia de repositório que já existe (`watchRepositories`), sem consulta periódica.
- R13 · "Mergear a pilha": quando a primeira spec de uma pilha estiver pronta, o menu "Mais" oferece fazer o merge de toda a pilha em sequência (R5 e R6 a cada passo). A sequência para no primeiro item que não estiver pronto ou que conflitar, e mostra onde parou.
- R14 · Acessibilidade:
  - cada card tem rótulo semântico com título, posição na pilha e estado ("SPEC-031, 2 de 2 na pilha, espera SPEC-029");
  - o aviso de R5 é anunciado uma vez, sem roubar o foco;
  - todos os botões novos são focáveis por Tab, com anel de foco visível.
- R15 · **Mãe mergeada fora do app** (pelo site do GitHub, por exemplo): ao abrir a tela de Review, e quando o vigia do repositório notar mudança nas refs, o sistema deve detectar as filhas cuja mãe já entrou na base e refazer a base delas como em R6 e R7:
  - a mãe conta como mergeada quando o PR dela está `MERGED` (`gh pr view --json state`) ou, sem PR, quando a branch dela sumiu do remote e os commits dela estão em `origin/<base>`;
  - antes de refazer, o sistema roda `git fetch origin <base>` e refaz a base sobre `origin/<base>`, porque a `main` local da raiz pode estar atrasada;
  - a ponta antiga da mãe vem de `refs/promptorium/<spec>/base-antiga`. A fila grava essa ref sempre que lê uma filha com a branch da mãe ainda existente, então ela continua disponível depois que a branch da mãe é apagada. Sem a ref, o card mostra "Base desatualizada · Refazer agora", que usa `git merge-base` como ponta antiga;
  - o aviso de R5 diz "SPEC-029 entrou na main pelo GitHub · base da SPEC-031 refeita".

- R16 · **Grafo das ramificações do merge.** A fila deve ter duas visões, "Lista" e "Grafo", escolhidas por abas no topo. A escolha é guardada por projeto. O grafo:
  - ocupa a área toda da tela (a lista lateral some) e se lê **de baixo para cima**: a `main` é um tronco horizontal embaixo, e cada pilha é um galho vertical que sai dele, da base para o topo. Cada spec avulsa é um galho de um nó;
  - mostra em cada nó o código, o título e o estado de R3. Os nós que podem entrar agora têm contorno âmbar e o selo "próximo";
  - liga com uma linha tracejada vermelha, com o nome do arquivo, as specs que mexem no mesmo arquivo (previsão de R4 entre as specs da fila, não só contra a base);
  - mostra no tronco as specs que entraram hoje na `main`, com a hora;
  - selecionar um nó (clique, ou as setas do teclado e Enter) mostra uma barra embaixo com o estado, "Abrir o review", que volta para a Lista com o diff, e a ação primária de R8;
  - tem legenda das linhas e do contorno, e cada nó tem rótulo semântico, como em R14.
- R17 · **Como resolver um conflito.** Quando houver conflito (R7, ou conflito previsto com a base), a tela deve oferecer dois caminhos, lado a lado, e mostrar os trechos em conflito:
  - **com o agente da spec (recomendado):** como em R7, o agente refaz a base no worktree, junta os dois lados, roda os testes da spec e commita. O card mostra "Agente resolvendo o conflito…" até ele terminar, e o resultado volta para o diff para ser revisado antes do merge;
  - **eu mesmo, no editor:** o app roda o rebase no worktree e para nos conflitos. O estado vira "Rebase em andamento · i de n". A tela lista cada trecho com "resolvido" ou "ainda tem marcadores", atualizada pelo vigia do worktree, e oferece "Abrir no editor", "Continuar rebase" (`git rebase --continue`, habilitado só sem marcadores `<<<<<<<`, `=======` e `>>>>>>>`) e "Desistir e voltar como estava" (`git rebase --abort`). Depois de continuar, o app roda os testes da spec antes de devolver o card à fila;
  - "Passar para o agente" fica disponível durante o rebase manual, e o agente continua do ponto em que ele parou;
  - **trechos:** cada trecho aparece com os dois lados, "Na main (veio da SPEC-x)" e "Nesta spec", sem cores de adição ou remoção, porque nenhum dos lados é uma remoção;
  - em nenhum dos caminhos a raiz do projeto muda de branch.

## Fora do escopo

- Trocar a branch da raiz ao clicar num card (decisão P1).
- Editar o conflito dentro do app, num editor de três vias. O app mostra os dois lados (R17), mas a edição acontece no editor do sistema ou pelo agente.
- Mudar o método de merge padrão. O squash continua disponível; R6 é o que o torna seguro em pilhas.
- O GitLab (SPEC-013): o rebase local vale, mas o `push` e a troca de base do MR ficam para outra spec.

## Design

### O que já existe

- `lib/features/review/review_service.dart`:
  - `queue()` (l.~212) monta a fila na ordem das sessões;
  - `baseBranchOf`, `stackedOnOf` e `rootProblem` (l.~1167–1201);
  - `predictConflict`, `merge` e `_mergeLocal` (l.~1379–1790), com `refs/promptorium/<id>/pre-rebase` como checkpoint;
  - `mergePr` (l.~976) chama `gh pr merge --delete-branch`.
- `lib/features/review/review_screen.dart`:
  - `_ReviewSidebar` e `_QueueTile` (l.235–440): fila plana, cor sem texto;
  - `_merge` (l.755) chama `select(null)` depois do merge, e a tela volta ao primeiro item;
  - o ramo `'empilhada'` de `_readinessAction` já pula para a mãe;
  - o cabeçalho tem "Pedir ajustes ao agente", "Criar PR", "Rascunho", "Fazer merge" e a linha da hospedagem, todos visíveis.
- `lib/features/board/widgets/wave_graph.dart`: `dependencyWaves`.
- `lib/features/project/project_config.dart`: `testCommand`, `lintCommand`, `buildCommand` e `formatCommand`. Não há `runCommand` nem `editorCommand`.
- `watchRepositories` já vigia as refs e os arquivos rastreados da raiz e do worktree.

### R1–R4 · Fila em pilha

- `review_logic.dart`: `orderQueue(items, specs)` devolve `List<ReviewStack>`, onde `ReviewStack` tem `items` (da base ao topo). A mãe de um item é o item cuja `session.branch == item.session.baseBranch`. Os ciclos, que não devem ocorrer, são quebrados pelo código da spec.
- `reviewQueueProvider` continua devolvendo os itens; `reviewStacksProvider` aplica `orderQueue`.
- `MergeState` (enum) é calculado de `mergeReadinessProvider`, `stackedOnOf` e de um novo `conflictForecastProvider(sessionId)`, um `FutureProvider` que roda `predictConflict` atrás de um `Pool(1)` e é invalidado pelo vigia do repositório.
- `_QueueTile` ganha o trilho, a posição, "sobre SPEC-x" e a linha de estado (ícone e texto).

### R5–R7 · Merge que continua

- `MergeResult` ganha `next` (id da sessão a selecionar) e `restacked` (`List<RestackResult>`, com `ok`, `conflict` ou `skipped`).
- Antes do merge, `_mergeLocal` e `mergePr` gravam `refs/promptorium/<spec>/base-antiga` com a ponta da branch da mãe. Depois do merge, `restackChildren(mother)` roda R6 para cada filha direta. Para o PR, a sequência é `git push --force-with-lease` e `gh pr edit <url> --base <base>`.
- Em `_merge`, `select(null)` passa a ser `select(r.next)`, seguido do aviso de R5.
- "Resolver conflito" cria a mensagem do agente: "Refaça o rebase de <branch> sobre <base> (`git rebase --onto <base> <base-antiga>`), resolva os conflitos e rode os testes". Ela é enviada pela mesma via de "Pedir ajustes ao agente".

### R8–R10 · Cabeçalho e barra do worktree

- `primaryActionOf(MergeState, hasPr)` é uma função pura e testável.
- `_WorktreeBar` mostra o caminho (fonte mono, com reticências no meio e o caminho completo no tooltip) e os botões "Testar", "Terminal" e "Editor".
- `WorktreeLauncher` (`lib/core/system/`): `terminal(path, [command])` tenta `x-terminal-emulator`, `gnome-terminal`, `konsole` e `xterm`, nessa ordem; `editor(path)` usa `editorCommand` e, na falta dele, `xdg-open`.
- `ProjectConfig`: novas chaves `runCommand` e `editorCommand`, com os campos correspondentes na tela de configuração.

### R11–R12 · Aviso da raiz

- `_RootBanner` no topo da fila lê `rootProblemProvider(workspaceId)`, que reaproveita `rootProblem` e é invalidado pelo vigia.

### R13 · Mergear a pilha

- `mergeStack(stack)` faz o merge em laço, item a item, e para no primeiro `MergeState` que não seja `pronto`. Ela usa um diálogo de confirmação só no início, com a lista das specs e o método de merge.

### R16 · Grafo

- `ReviewGraph` (`lib/features/review/widgets/review_graph.dart`): um `CustomPaint` para o tronco, os galhos e as linhas de conflito, com os nós como widgets posicionados (`Stack`). Ele reaproveita `orderQueue` (pilhas) e `conflictForecastProvider` entre pares de itens da fila, por meio de `git merge-tree` entre as duas branches, com o mesmo `Pool(1)`.
- `reviewViewProvider` ganha `mode` (`lista` | `grafo`), persistido por projeto como os filtros de hoje.
- As specs que entraram hoje vêm das sessões `merged` com `endedAt` de hoje.

### R17 · Resolver conflito

- `ReviewService.startRebase(sessionId)` roda `git rebase --onto <base> <base-antiga>` no worktree e deixa o rebase parado. `rebaseStatus(sessionId)` lê `.git/rebase-merge` e procura marcadores nos arquivos em conflito (`git diff --name-only --diff-filter=U`, mais a busca de `<<<<<<<`). `continueRebase` e `abortRebase` completam o fluxo.
- `conflictHunks(sessionId)` monta os trechos com os dois lados a partir de `git merge-tree --write-tree --name-only` e dos estágios 2 e 3 do índice durante o rebase.
- "Passar para o agente" envia a mensagem de R7 com "o rebase já está em andamento; continue de onde parou".

### Testes

- `test/features/review/review_stack_test.dart`: `orderQueue` (pilha de três, duas pilhas, item sem spec, ciclo) e `primaryActionOf` (todos os estados).
- `test/features/review/restack_test.dart`, num repositório git temporário:
  - mãe com squash na `main` e filha rebaseada sem conflito; a filha fica com só os commits dela;
  - conflito real: rebase abortado, a branch fica igual e o estado vira `conflitoBase`;
  - worktree sujo: o rebase é pulado.
- `test/features/review/review_graph_test.dart` (widget): galhos e nós na ordem da base ao topo, o selo "próximo", a linha de conflito com o nome do arquivo, a seleção pelo teclado e a barra de ação.
- `restack_test.dart` também cobre R17: `startRebase` para nos conflitos, `rebaseStatus` conta os marcadores, `continueRebase` é recusado com marcadores e `abortRebase` volta ao SHA anterior.
- `test/features/review/review_screen_stack_test.dart` (widget):
  - a ordem dos cards e o trilho;
  - os rótulos de estado com texto;
  - depois do merge, o próximo item é selecionado e o aviso aparece;
  - o clique no card não chama `git switch`;
  - o aviso da raiz com "Voltar para a main";
  - os botões da barra do worktree chamam o `WorktreeLauncher` falso com o caminho do worktree.

## Critérios de aceite

- [x] A fila segue a ordem das dependências e agrupa as pilhas [R1] [R2] verificar: flutter test test/features/review/review_stack_test.dart
- [x] Cada card mostra o estado de merge com ícone e texto, incluindo o conflito previsto [R3] [R4] [R14] verificar: flutter test test/features/review/review_screen_stack_test.dart
- [x] Depois do merge, a tela seleciona o próximo item e avisa [R5] verificar: flutter test test/features/review/review_screen_stack_test.dart
- [x] A base da filha é refeita sozinha depois do squash da mãe; com conflito, o rebase é abortado e a filha fica marcada [R6] [R7] verificar: flutter test test/features/review/restack_test.dart
- [x] O cabeçalho tem uma ação primária por estado [R8] verificar: flutter test test/features/review/review_stack_test.dart
- [x] "Testar", "Terminal" e "Editor" abrem no worktree, e clicar no card não troca a branch da raiz [R9] [R10] verificar: flutter test test/features/review/review_screen_stack_test.dart
- [x] O aviso da raiz aparece na fila e "Voltar para a main" funciona [R11] [R12] verificar: flutter test test/features/review/review_screen_stack_test.dart
- [x] "Mergear a pilha" para no primeiro item que não está pronto [R13] verificar: flutter test test/features/review/restack_test.dart
- [x] Com a mãe mergeada fora do app (PR `MERGED` e branch apagada), abrir a Review refaz a base da filha sobre `origin/main` com a `base-antiga` gravada; sem a ref, mostra "Refazer agora" [R15] verificar: flutter test test/features/review/restack_test.dart
- [ ] Com um PR empilhado no GitHub, o merge da mãe troca a base do PR filho para a `main`, e ele continua aberto (verificação manual) [R6] verificar: manual (dois PRs empilhados de teste)
- [x] O grafo desenha a main embaixo, as pilhas como galhos da base ao topo, o "próximo" e a linha de conflito entre specs da fila; selecionar um nó mostra a ação primária [R16] verificar: flutter test test/features/review/review_graph_test.dart
- [x] Resolver eu mesmo: o rebase para nos conflitos, "Continuar rebase" só libera sem marcadores, e "Desistir" volta a branch ao estado anterior [R17] verificar: flutter test test/features/review/restack_test.dart
- [x] A análise estática passa sem avisos novos [R1] [R2] [R3] [R4] [R5] [R6] [R7] [R8] [R9] [R10] [R11] [R12] [R13] [R14] [R15] [R16] [R17] verificar: flutter analyze

## Decisões

- (P1) Clicar num card não troca a branch da raiz. Testar uma branch acontece no worktree dela, com "Testar", "Terminal" e "Editor". O merge local exige a raiz na `main`, e o git recusa o checkout de uma branch que já está aberta em um worktree (R9, R10).
- (P2) Depois do merge da mãe, a base das filhas é refeita sozinha. Se houver conflito, o rebase é desfeito e a filha fica marcada para "Resolver conflito" (R6, R7).
- (P3) Os problemas mais frequentes, segundo o usuário, são o conflito em pilha e a raiz suja ou fora da `main` (R6 e R11 são o núcleo da spec).
- (P4) Quando a mãe é mergeada fora do app, a base das filhas é refeita na próxima vez que a Review abre ou que as refs mudam, sobre `origin/<base>` (R15).
- (P5) A fila ganha a visão em grafo das ramificações do merge, que se lê de baixo para cima, como o usuário descreveu ("um canvas com as ramificações do merge, caso um dependa do outro") (R16).
- (P6) O conflito é resolvido pelo agente por padrão, ou à mão, no editor, com o rebase parado no worktree. O app mostra os dois lados de cada trecho (R17).
- Validação do mockup (`/validar-layouts`, relatório em `docs/mockups/spec-032/relatorio-validacao-fila-de-review-em-pilha-2026-11-02.html`): a proposta tirou 94 e a tela de hoje 85. A v2 do mockup corrige os ganhos rápidos apontados: o grupo "Avulsas" (R2), os títulos sem caixa-alta espaçada (R2), "Fazer merge" desabilitado de verdade com o motivo (R8), o estado aberto do "Mais" (R8) e o tooltip de "Testar" (R9).
