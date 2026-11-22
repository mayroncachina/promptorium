---
id: SPEC-111
status: em implementação
versao: 0.23.1
tipo: correcao
epico: 332
issue: 376
depende-de: [SPEC-096]
---

# Alterações e Diff da sessão depois do commit

## Objetivo

Ver o que uma sessão em worktree mudou mesmo depois que esse trabalho foi commitado.

Hoje o painel "Arquivos alterados" e a aba Diff da sessão leem só o que **ainda não foi commitado**: `sessionChangesProvider` (`lib/features/sessions/session_changes.dart`) usa `git status` e `git diff HEAD`. Isso funcionava quando o agente deixava tudo solto no worktree. Com a SPEC-096 R10/R10a, o app commita o turno do Codex no fim; daí em diante o painel diz "Nenhuma alteração." e o Diff fica vazio, embora a sessão tenha mudado arquivos.

Exemplo concreto, achado na conferência da main da 0.23.0: uma sessão do Codex em worktree altera `lib/a.dart`, o app commita no fim do turno, e o painel lateral passa a mostrar "Nenhuma alteração.". O mesmo acontece com uma sessão do Claude Code que commita sozinha.

## Requisitos

- R1 · **Base da sessão.** Numa sessão em worktree com `baseBranch`, as alterações são medidas desde o `merge-base` entre `baseBranch` e `HEAD`, e não desde o `HEAD`. Entram os commits da sessão e o que ainda não foi commitado, incluindo os arquivos novos não rastreados.
- R2 · **Sem base, nada muda.** Uma sessão sem `baseBranch` (na raiz do workspace) ou sem `merge-base` (ref apagada, histórico cortado) continua medindo desde o `HEAD`, como hoje.
- R3 · **Mesmos lugares.** "Arquivos alterados", a aba Diff, a contagem na lista de sessões e o Desfazer usam a mesma medida. Para o Desfazer, ver P2.
- R4 · **Atualiza depois do commit do app.** O painel recarrega quando o commit do fim do turno do Codex termina (depois de `_codexTurnCommit`, no `beforeEnd` do ponto de restauração), e não só no fim do turno. Hoje o recarregamento acontece antes do commit.
- R5 · **Funciona para os dois provedores.** O provedor da sessão não muda a regra.
- R6 · **Sem custo novo perceptível.** Calcula o `merge-base` uma vez por recarga, sem chamada de git por arquivo.

## Decisões

- P1 · **Separar o que já foi commitado do que não foi?** **Decidido:** não nesta correção. A lista e o Diff ficam iguais; só deixam de ficar vazios. Uma marca visual de "commitado" ou "não commitado" seria tela nova e pediria canvas, então fica para uma spec própria se fizer falta.
- P2 · **O Desfazer passa a contar os commits?** **Decidido:** não mudar o Desfazer aqui. Ele já usa os pontos de restauração (SPEC-084, corrigido no #372) para os commits; só a contagem "N arquivos" que ele mostra passa a vir da nova medida.
- P3 · **Mock.** **Decidido:** não precisa de canvas: o layout não muda. O PR leva os prints de antes e depois do painel, tirados no app.

## Fora do escopo

- "Orçamento do dia" e "Custo médio por spec" somando US$ sem separar o Codex: fica para a SPEC-101 (#346).
- Replay (`file_at_step.dart`), que já usa `startSha` e `merge-base`.

## Tarefas

- T1 · `sessionChangesProvider` com base `merge-base(baseBranch, HEAD)` e queda para `HEAD`; `git status` só para os não rastreados; numstat e diff contra a base, com o worktree.
- T2 · Recarregar `sessionChangesProvider` depois do commit do app (R4).
- T3 · Testes: sessão Codex com o commit do app; sessão Claude que commita; sessão sem `baseBranch`; `merge-base` ausente; arquivo novo não rastreado depois de um commit.
- T4 · E2E com o `fake_codex`: prints de antes e depois em `docs/mockups/spec-111/app/`.

## Critérios de aceite

- [ ] Sessão do Codex em worktree, depois do commit do app: o painel lista os arquivos do turno e o Diff mostra as linhas.
- [ ] Sessão do Claude que commitou: idem.
- [ ] Commit e alteração solta juntos: os dois aparecem.
- [ ] Sessão na raiz do workspace: comportamento igual ao de hoje.
- [ ] Sem `merge-base`: cai para o `HEAD` sem erro na tela.
- [ ] O painel atualiza sozinho quando o commit do app termina.
