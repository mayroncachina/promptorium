---
id: SPEC-045
status: rascunho
depende-de: SPEC-044, SPEC-032, SPEC-042, SPEC-048
issue: 103
---

# Grafo do repositório

## Objetivo

O Promptorium trabalha com muitas branches ao mesmo tempo: uma por spec, uma por tarefa nas specs grandes (pai e filhas, como na SPEC-042) e worktrees com agentes rodando. O Quadro mostra o estado de cada spec, mas não mostra o histórico: de onde cada branch saiu, quando entrou na main, o que está esperando merge e onde cada versão foi marcada. Hoje isso só se vê com `git log --graph` no terminal ou no GitHub.

Esta spec acrescenta a aba **Grafo** à tela Repositório (SPEC-044). Ela desenha o histórico como um grafo de raias, uma por branch, com os merges, as tags de versão e os PRs abertos. Cada commit fica ligado à sua spec e cada raia tem a cor da spec.

Issue: [#103](https://github.com/mayroncachina/promptorium/issues/103) (sub-issue de [#101](https://github.com/mayroncachina/promptorium/issues/101)).

Mockup: [canvas do Claude Design](https://claude.ai/artifact/HcFbQPFWcM9ZWttmCgcKDw), linha "SPEC-045 · Grafo". Capturas em `docs/mockups/spec-045/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-grafo.png` | Grafo com a main, as specs abertas, uma spec pai com as filhas, tags, PRs com o CI e a etiqueta do modelo (o tooltip está em `docs/mockups/spec-048/3-grafo-etiqueta.png`) | R1, R2, R3, R4, R8, R9 |
| `2-commit.png` | Spec pai recolhida e o painel do commit selecionado | R3, R5, R6 |

## Requisitos

- R1 · A tela Repositório deve ganhar a aba **Grafo**, depois de Releases. Cada linha é um commit, com o grafo de raias à esquerda e, ao lado, a mensagem, a spec, o autor, a data relativa e o SHA curto. As raias e as curvas de merge e de saída de branch são calculadas pelo app, não lidas do `git log --graph`.
- R2 · As cores devem seguir a spec:
  - a branch padrão fica em cinza claro, sempre na primeira raia;
  - os commits de uma branch `spec/NNN-*` ganham a cor da spec, a mesma do card no Quadro, e uma etiqueta `SPEC-NNN` na primeira linha da raia;
  - as outras branches ficam em um tom neutro, com o nome da branch na etiqueta.
- R3 · As filhas de uma spec grande (`spec/NNN-tN-*`) devem ficar ao lado da raia da pai, na cor da pai em tom mais claro. A pai pode ser **recolhida**: vira uma única raia, que mostra "4 tarefas · 4 mergeadas" e esconde os commits das filhas. As specs já mergeadas começam recolhidas, e as abertas, expandidas.
- R4 · As referências devem aparecer como etiquetas no commit:
  - tags de versão, no estilo da linha do tempo da SPEC-044, com um clique que abre a versão em Releases;
  - pontas de branch locais e remotas (`origin/…` só quando está em outro commit);
  - PR aberto na ponta da branch, com número, estado do CI (passou, falhou, rodando) e um clique que abre o card no Review. Os dados vêm do babysitter quando ele já acompanha o PR; os outros PRs vêm de `gh pr list --json number,headRefName,statusCheckRollup`;
  - a raia com um worktree em que um agente está rodando mostra um ponto pulsando na ponta: "agente trabalhando".
- R5 · Ao selecionar um commit, um painel à direita deve mostrar:
  - a mensagem inteira, o autor, a data e o SHA, com "Copiar SHA";
  - os pais (mais de um num merge) e as branches e tags que contêm o commit;
  - os arquivos alterados com `+`/`−` (`git show --numstat`), cada um com "Ver diferença";
  - a spec e o PR, com "Abrir no Quadro" e "Abrir no Review".
- R6 · O cabeçalho da aba deve ter:
  - a escolha **Todas as branches** (padrão), **Só a branch padrão** (`--first-parent`, um commit por merge) ou **Specs abertas** (a branch padrão e as `spec/*` não mergeadas);
  - a busca por mensagem, SHA, autor ou `SPEC-NNN`, que realça os resultados e pula entre eles com Enter;
  - um botão que mostra ou esconde as branches remotas que não têm cópia local.
- R7 · A aba deve carregar 300 commits por vez, em ordem topológica, e mais 300 ao rolar até o fim. As raias são calculadas por partes, sem recalcular o que já está na tela. A lista desenha só as linhas visíveis. A aba atualiza quando HEAD, as refs ou as tags mudam, com o mesmo vigia de arquivos do Código, sem perder o commit selecionado nem a rolagem.
- R8 · Ao passar o ponteiro sobre uma raia, ela fica em destaque e as outras esmaecem, e um balão diz o nome da branch, quantos commits ela tem a mais que a branch padrão e, se mergeada, quando.
- R9 · Com a marcação da SPEC-048 ligada, o commit de agente deve mostrar uma etiqueta com o modelo (`sonnet`, `opus`, `app`) ao lado do autor. O tooltip da etiqueta mostra a origem ("SPEC-042 R2") e o texto exato da linha `Promptorium-Agente`. Sem a marca, só o autor aparece.

## Fora do escopo

- Ações de git pelo grafo (checkout, cherry-pick, rebase, reset, criar ou apagar branch). O grafo só lê.
- Arrastar raias ou mudar a ordem à mão.
- Mostrar stashes e as refs internas `refs/promptorium/*`.
- Comparar dois commits quaisquer.

## Design

### O que já existe

- `lib/features/repository/repository_screen.dart` (SPEC-044): a casca com as abas.
- `lib/core/git/git_service.dart`: `git(args)`.
- `lib/features/board/widgets/spec_canvas.dart` e as cores das specs no Quadro: a mesma cor vale para a raia.
- `lib/features/review/pr_babysitter.dart`: o estado dos PRs acompanhados. `review_stack.dart` monta a pilha pai e filhas da SPEC-032.
- `lib/features/sessions/session_manager.dart`: as sessões vivas e o worktree de cada uma.
- `lib/core/fs/dir_watcher.dart`: o vigia de arquivos que o Código usa.
- `lib/features/sessions/edit_diff.dart` e a tela Código: mostram a diferença de um arquivo.

### Componentes

- `lib/features/repository/graph/commit_log.dart` (novo): lê `git log --topo-order --format=%H%x00%P%x00%an%x00%at%x00%D%x00%s` em páginas, com `--all`, `--first-parent` ou só as refs escolhidas (R6).
- `lib/features/repository/graph/lane_layout.dart` (novo): uma função pura que recebe as linhas em ordem e o estado das raias da página anterior e devolve, por linha, a raia do commit e as arestas (passagem, saída de branch, merge). Ela também sabe recolher uma pai com as filhas (R3).
- `lib/features/repository/graph/spec_of_commit.dart` (novo): liga o commit à spec pela branch que o contém primeiro e pelo `SPEC-NNN` na mensagem do merge.
- `lib/features/repository/graph/graph_tab.dart` e `graph_painter.dart` (novos): a lista virtual e um `CustomPainter` por linha.
- `lib/features/repository/graph/commit_panel.dart` (novo): o painel de R5.

### Testes

- `test/features/repository/lane_layout_test.dart`: história linear, branch e merge, merge com vários pais, raias que se liberam, continuidade entre páginas e pai recolhida.
- `test/features/repository/spec_of_commit_test.dart`: branch de spec, filha, merge de PR e commit sem spec.
- `test/features/repository/graph_tab_test.dart`: filtros, busca, etiquetas de tag, PR e agente, painel do commit e atualização sem perder a seleção.

## Decisões

- **O app calcula as raias.** O `git log --graph` é texto feito para o terminal: não dá para colorir por spec, recolher a pai nem paginar sem recalcular tudo.
- **A cor é da spec, não da branch.** Assim o grafo e o Quadro falam a mesma língua.
- **Só leitura.** As ações de branch já têm lugar no Review e no Quadro, e um clique errado no grafo não pode reescrever o histórico.
- **Mergeadas recolhidas por padrão.** Com dezenas de specs fechadas, o grafo expandido fica ilegível. O que interessa no dia a dia é o que está aberto.

## Plano

1. Validar o mockup (tabela no início da spec).
2. `commit_log` e `lane_layout` com os testes.
3. Aba com a lista virtual, as cores e as etiquetas.
4. Pai e filhas recolhíveis, PRs, CI e agente trabalhando.
5. Painel do commit, filtros, busca e atualização ao vivo.
6. Guia `docs/guia/repositorio.md`.

## Critérios de aceite

- [ ] As raias de branch, merge e merge com vários pais saem certas e continuam entre páginas [R1, R7] verificar: flutter test test/features/repository/lane_layout_test.dart
- [ ] Os commits de spec têm a cor do Quadro e a etiqueta SPEC-NNN [R2] verificar: flutter test test/features/repository/spec_of_commit_test.dart
- [ ] As filhas ficam junto da pai, que recolhe e expande; as mergeadas começam recolhidas [R3] verificar: flutter test test/features/repository/lane_layout_test.dart
- [ ] Tags, PRs com CI e agente trabalhando aparecem como etiquetas que levam a Releases e ao Review [R4] verificar: flutter test test/features/repository/graph_tab_test.dart
- [ ] Commits marcados pela SPEC-048 mostram a etiqueta do modelo com o tooltip da origem [R9] verificar: flutter test test/features/repository/graph_tab_test.dart
- [ ] O painel mostra pais, refs, arquivos com +/− e os links da spec e do PR [R5] verificar: flutter test test/features/repository/graph_tab_test.dart
- [ ] Filtros e busca funcionam, e a aba atualiza sem perder seleção e rolagem [R6, R7] verificar: flutter test test/features/repository/graph_tab_test.dart
- [ ] O grafo do próprio Promptorium (mais de 1.000 commits) rola sem travar e mostra a SPEC-042 com as quatro filhas [R3, R7] verificar: manual (abrir o Promptorium no app)
- [ ] O projeto compila e a análise estática passa [R1–R9] verificar: flutter analyze
