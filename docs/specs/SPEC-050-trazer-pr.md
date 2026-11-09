---
id: SPEC-050
status: proposta
depende-de: SPEC-032, SPEC-045
issue: 125
---

# Trazer um PR qualquer para o app

## Objetivo

Hoje o Review só entende PRs que nasceram de uma spec do Promptorium. A sessão da spec cria o worktree, a branch e o PR, e o Review acompanha tudo a partir dela. Um PR de um colega, um PR do Dependabot ou um PR aberto fora do app não tem worktree, sessão nem lugar na fila. Para pedir um ajuste ao agente nesse PR, a pessoa precisa fazer o checkout à mão e abrir uma sessão solta.

Esta spec cria **Trazer PR**: a pessoa escolhe um PR aberto do repositório e o app faz o checkout num worktree próprio, abre uma sessão do agente com o contexto do PR e coloca o PR na fila do Review, mesmo sem spec. A partir daí valem as ferramentas que já existem: o diff, os comentários do PR no diff, "Pedir ajustes ao agente", Acompanhar PR, "Pronto para merge?" e "Mergear PR".

A ideia vem do Vibe Kanban (vibekanban.com), que abre um worktree a partir de qualquer PR do time para iterar com agentes. Aqui, o PR continua sendo de quem o abriu: o app nunca reescreve o histórico publicado da branch e só publica commits quando tem permissão de escrita.

Issue: [#125](https://github.com/mayroncachina/promptorium/issues/125), parte de [#124](https://github.com/mayroncachina/promptorium/issues/124). PR: [#129](https://github.com/mayroncachina/promptorium/pull/129).

Mockup: [canvas do Claude Design](https://claude.ai/artifact/NVC9Pyp1mQBbmMDp7KhQtr). Cópia dos quadros e capturas em `docs/mockups/spec-050/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-escolher-pr.png` | "Trazer PR" com a lista de PRs abertos, busca e "Já no app" | R1, R2 |
| `2-como-comecar.png` | O PR escolhido, de um fork sem permissão de escrita, com o primeiro pedido ao agente | R3, R4, R7 |
| `3-no-review.png` | O PR trazido na fila e no Review, com o resumo do agente e os comentários do PR no diff | R5, R6, R8 |
| `4-pronto-para-merge.png` | "Pronto para merge?" de um PR sem spec, com commits novos do autor | R6, R7, R9 |

## Requisitos

- R1 · O Review deve ganhar o botão **Trazer PR…** no topo da fila. Ele abre um diálogo com:
  - os PRs abertos do repositório (`gh pr list --state open`), com número, título, autor, branch, rascunho ou não, checks e data da última atualização;
  - uma busca por título, autor ou número, e um campo que aceita o número (`#212`) ou a URL do PR, inclusive de um PR que não aparece na lista;
  - o selo **Já no app** nos PRs que já têm sessão no workspace (pela `prUrl` da sessão ou pela branch), com "Abrir no Review" no lugar de "Trazer".
- R2 · Na aba Grafo do Repositório (SPEC-045), o painel de um PR sem sessão deve oferecer **Trazer para o app**, que abre o mesmo diálogo com o PR já escolhido.
- R3 · Ao trazer um PR, o sistema deve:
  - buscar a cabeça do PR (`git fetch <remote> pull/<n>/head`) e criar um worktree em `<worktreesBase>/<repo>-pr-<n>`;
  - usar a branch do PR com o mesmo nome (`headRefName`) quando o PR é do próprio repositório, com upstream no remote. Quando o PR vem de um fork, a branch local é `pr/<n>-<slug>`, com push para o fork só se `maintainerCanModify` for verdadeiro;
  - usar a base do PR (`baseRefName`) como base do Review e do merge;
  - rodar `worktree.copiar` e `worktree.preparar` do `.promptorium/config.yml`, como num worktree de spec;
  - criar a sessão sem spec e sem tarefa, com `prUrl` preenchida e o título `PR #<n> · <título>`.
- R4 · O diálogo deve pedir como começar, com uma escolha:
  - **Resumir o PR** (padrão): o agente lê o PR em modo plano, sem editar nada, e responde com o que o PR muda, os riscos e as perguntas em aberto;
  - **Responder aos comentários**: envia os comentários abertos do PR, com arquivo e linha, e pede as correções;
  - **Meu pedido**: um campo de texto livre.

  Em todos os casos, a primeira mensagem leva o contexto do PR: título, descrição, autor, base, `git diff --stat` contra a base, comentários abertos e checks que falharam. Ela também leva as regras do PR alheio (R7).
- R5 · O PR trazido deve entrar em **Aguardando review** quando a sessão terminar um turno, como uma sessão solta com alterações. O card mostra `PR #<n> · @<autor>` e o selo **Sem spec**. Ele sai da fila quando o PR é mergeado ou fechado, ou quando a pessoa usa **Soltar o PR**.
- R6 · No Review, um PR sem spec deve ter:
  - o diff contra o merge-base com a base do PR, com "Desde a última rodada";
  - os comentários do PR no diff e os comentários da pessoa, guardados por sessão, porque não há spec (P1);
  - "Pedir ajustes ao agente", Acompanhar PR, "Resolver conflito com o agente" e "Mergear PR", como num PR de spec;
  - o revisor automático desligado por padrão, com **Rodar revisor** sob demanda;
  - em "Pronto para merge?", só os itens que não dependem de spec: checks e conflitos do PR, decisão de review do PR, base atualizada e o gate do projeto (`testes:`, `lint:` e `build:`) rodado sob demanda com **Verificar**. Critérios, etapas e revisor não aparecem.
- R7 · O sistema nunca deve reescrever o histórico publicado da branch do PR:
  - a sessão roda com `git push --force*`, `git push -f*` e `git push --force-with-lease*` bloqueados, somados ao `bloquear-comandos` do projeto;
  - o push dos commits do agente vai para a branch do PR só com permissão de escrita (mesmo repositório com permissão, ou fork com `maintainerCanModify`). Sem permissão, o Review avisa "Sem permissão de escrita na branch do PR · os commits ficam locais" e oferece **Copiar patch** (`git format-patch` da base local até `HEAD`);
  - quando o autor publica commits novos, o Review mostra "O autor publicou N commits" com **Atualizar**. Atualizar busca a branch e, havendo commits locais não publicados, refaz esses commits por cima com rebase. Em conflito, segue o fluxo de conflito da SPEC-032 e da SPEC-043.
- R8 · Quando a pessoa usa "Responder aos comentários" ou "Pedir ajustes ao agente" com comentários do PR, o envio pode, se a pessoa marcar **Responder no PR depois do push**, deixar em cada conversa tratada uma resposta curta com o SHA que corrigiu (`gh api …/comments/<id>/replies`). Nada é respondido sem essa marcação, e a conversa nunca é resolvida pelo app.
- R9 · **Soltar o PR** remove o worktree e a branch local e deixa a sessão no histórico. Ele nunca apaga a branch remota nem fecha o PR. Se houver commits não publicados, pede confirmação e oferece "Copiar patch" antes.
- R10 · Em GitLab, "Trazer PR…" aparece desabilitado com o motivo, como as outras ações de MR (SPEC-013).

## Fora do escopo

- Transformar o PR trazido em spec, com requisitos e critérios. Fica para outra spec.
- Abrir um PR de sugestão no fork do autor quando não há permissão de escrita. Aqui, só o patch.
- Resolver ou aprovar conversas e reviews no GitHub. O app só comenta quando a pessoa pede (R8).
- PRs de outro repositório que não o do workspace.
- GitLab (SPEC-013).

## Design

### O que já existe

- `lib/core/git/gh_cli.dart`: `GhCli.prList`, `prListOpen` e `GhPullRequest`. Nenhuma das chamadas pede `author`, `baseRefName`, `isCrossRepository`, `maintainerCanModify` nem `isDraft`.
- `lib/core/git/git_service.dart`: `addWorktree(slug, baseBranch:)` sempre cria a branch `pr/<slug>` a partir de uma base. Para trazer um PR é preciso partir de uma ref buscada e, no mesmo repositório, usar o nome da branch do PR.
- `lib/features/sessions/session_manager.dart`: `NewSessionRequest` já aceita `worktreePath`, `branch` e `baseBranch` de um worktree existente, e `_setupWorktree` roda `copiar` e `preparar`.
- `lib/features/review/review_service.dart`: `queue` já aceita sessões sem spec (`isAwaitingReview` em `review_logic.dart`). `prView`, `inlineComments`, `pushIfAhead` e `mergePr` trabalham a partir da `prUrl` da sessão. `prView` só grava os comentários do PR quando há spec, porque `review_comments.spec_id` é obrigatório.
- `lib/features/review/pr_babysitter.dart`: `PrBabysitter` acompanha o PR da sessão e publica os commits novos.
- `lib/features/review/merge_readiness.dart`: `MergeReadiness` e `ReadinessInputs` montam os itens de "Pronto para merge?".
- `lib/features/repository/graph/graph_sources.dart`: `mergePrSources` já liga cada PR aberto à sessão da mesma branch, e o painel do Grafo mostra "Abrir no Review" quando ela existe.
- `lib/features/board/step_gate.dart`: `StepGate.run` roda os comandos do projeto num worktree.

### Componentes

- `lib/features/review/pr_import.dart` (novo):
  - `PrImportCandidate`: número, URL, título, autor, branch, base, fork ou não, `maintainerCanModify`, rascunho, checks e a sessão que já o trouxe;
  - `PrImportService.candidates(ws)` e `PrImportService.resolve(ws, texto)`, que aceita `#n`, `n` ou a URL;
  - `PrImportService.bring(ws, candidate, start)`: busca, cria o worktree (R3), monta a primeira mensagem (R4) e chama `SessionManager.create`;
  - `prContextMessage(...)`, a mensagem com o contexto e as regras (R4, R7), testável sem git.
- `GhCli.prListOpen` ganha os campos de R1, e `GhCli.prView(n)` lê um PR fora da lista.
- `GitService.addWorktreeAt(slug, ref, branch:, upstream:)`: cria o worktree de uma ref buscada com o nome de branch dado (R3).
- `lib/features/review/widgets/pr_import_dialog.dart` (novo): o diálogo de R1 e R4.
- `ReviewService`:
  - `queue` marca o item como PR trazido (`ReviewItem.imported`) quando a sessão tem `prUrl` e não tem spec (R5);
  - `pushIfAhead` respeita a permissão do PR (R7);
  - `remoteAhead` e `updateFromRemote` cuidam dos commits novos do autor (R7);
  - `copyPatch` e `releaseImported` (R7, R9).
- `review_comments`: `spec_id` passa a ser opcional e ganha `session_id`, com uma migração e o teste de migração a partir da versão atual (P1).
- `MergeReadiness` ganha o modo sem spec (R6).
- Bloqueio de comandos: a sessão trazida soma ao `bloquear-comandos` os pushes forçados de R7, pelo mesmo hook `PreToolUse` das etapas.

## Critérios de aceite

- [ ] O diálogo lista os PRs abertos com autor, branch e checks, aceita número ou URL e marca "Já no app" [R1] verificar: flutter test test/features/review/pr_import_test.dart
- [ ] O painel do Grafo oferece "Trazer para o app" num PR sem sessão [R2] verificar: flutter test test/features/repository/graph_tab_test.dart
- [ ] Um PR do mesmo repositório vira worktree na branch do PR, e um de fork vira `pr/<n>-<slug>`, com `copiar` e `preparar` rodados [R3] verificar: flutter test test/features/review/pr_import_test.dart
- [ ] A primeira mensagem leva o contexto do PR e as regras, nas três formas de começar [R4] verificar: flutter test test/features/review/pr_import_test.dart
- [ ] O card entra na fila com "PR #n · @autor" e "Sem spec" e sai quando o PR é mergeado ou fechado [R5] verificar: flutter test test/features/review/review_stack_test.dart
- [ ] Os comentários do PR e da pessoa são guardados por sessão, sem spec, e a migração preserva os comentários de spec [R6] verificar: flutter test test/data/migrations_test.dart
- [ ] "Pronto para merge?" de um PR sem spec mostra só checks, conflitos, decisão do PR, base e gate do projeto [R6] verificar: flutter test test/features/review/merge_readiness_test.dart
- [ ] Push forçado é bloqueado, e sem permissão de escrita os commits ficam locais com "Copiar patch" [R7] verificar: flutter test test/features/review/pr_import_test.dart
- [ ] "Atualizar" traz os commits novos do autor e refaz os locais por cima, e o conflito cai no fluxo existente [R7] verificar: flutter test test/features/review/pr_import_test.dart
- [ ] Só com "Responder no PR depois do push" marcado o app comenta nas conversas tratadas [R8] verificar: flutter test test/features/review/pr_import_test.dart
- [ ] "Soltar o PR" remove worktree e branch local, nunca a remota, e confirma com commits não publicados [R9] verificar: flutter test test/features/review/pr_import_test.dart
- [ ] Em GitLab, "Trazer PR…" aparece desabilitado com o motivo [R10] verificar: flutter test test/features/review/pr_import_test.dart
- [ ] Um PR real de outra pessoa é trazido, ajustado pelo agente, publicado e mergeado no app [R1–R7] verificar: manual (repositório de teste com um PR aberto por outra conta)
- [ ] O projeto compila e a análise estática passa [R1–R10] verificar: flutter analyze

## Decisões

Perguntas em aberto, com a recomendação de cada uma:

- P1 · Onde guardar os comentários de um PR sem spec? Recomendado: `review_comments.spec_id` opcional e uma coluna `session_id`, com migração. A alternativa é criar uma spec "sombra" para o PR, mas ela apareceria no Quadro e nas specs sem ter sido escrita.
- P2 · Qual é o começo padrão? Recomendado: **Resumir o PR**, em modo plano, porque gasta poucos tokens e já deixa algo útil no Review. A alternativa é não iniciar o agente até o primeiro pedido, o que exige uma sessão sem processo, algo que o app ainda não tem.
- P3 · Responder no GitHub depois do push (R8) deve vir marcado? Recomendado: desmarcado, lembrando a última escolha por workspace.
- P4 · Com commits novos do autor e commits locais não publicados, "Atualizar" faz rebase sozinho ou pergunta antes? Recomendado: pergunta, mostrando quantos commits locais serão refeitos.
- P5 · A entrada pelo Grafo (R2) fica nesta spec? Recomendado: sim. É uma ação a mais num painel que já existe e já sabe quando o PR não tem sessão.
- P6 · Mockups: o diálogo com a lista, o diálogo com o PR escolhido de um fork sem permissão, o PR no Review e "Pronto para merge?" sem spec.
