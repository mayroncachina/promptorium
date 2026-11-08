---
id: SPEC-047
status: rascunho
depende-de: SPEC-044, SPEC-032
issue: 105
---

# Higiene do repositório

## Objetivo

Cada spec deixa rastros: uma branch local, a remota, um worktree em `~/.promptorium/worktrees/` ou na pasta escolhida, e refs internas em `refs/promptorium/<spec>/`. Depois do merge, quase nada disso some sozinho. Com o tempo, o repositório acumula dezenas de branches mergeadas, worktrees de specs fechadas há semanas (no próprio Promptorium, mais de vinte) e branches abertas que ficaram tão atrás da main que vão dar conflito.

Esta spec acrescenta a aba **Higiene** à tela Repositório (SPEC-044). Ela mostra o que pode ser limpo e o que precisa de atenção, e limpa com confirmação e sem perder trabalho.

Issue: [#105](https://github.com/mayroncachina/promptorium/issues/105) (sub-issue de [#101](https://github.com/mayroncachina/promptorium/issues/101)).

Mockup: [canvas do Claude Design](https://claude.ai/artifact/HcFbQPFWcM9ZWttmCgcKDw), linha "SPEC-047 · Higiene". Capturas em `docs/mockups/spec-047/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-higiene.png` | Os quatro grupos com contagem, seleção e o que protege cada item | R1, R2, R3, R4, R5 |
| `2-limpar.png` | Confirmação da limpeza e o aviso com "Desfazer" | R6, R7 |

## Requisitos

- R1 · A tela Repositório deve ganhar a aba **Higiene**, depois de Atividade. A aba mostra uma contagem no título ("Higiene · 31") quando há o que limpar. A análise roda ao abrir a aba e com "Analisar de novo".
- R2 · **Branches mergeadas** deve listar as branches locais cujo commit já está na branch padrão (`git branch --merged <padrão>`, mais as que entraram por squash, quando o PR delas consta como mergeado no `gh`), com a data do último commit, a spec e o PR. As remotas mergeadas (`origin/…`) aparecem no mesmo item, com uma caixa separada para apagar também no remoto.
- R3 · **Worktrees** deve listar os worktrees do repositório (`git worktree list --porcelain`) em três situações:
  - **órfão**: a pasta não existe mais (`git worktree prune --dry-run`);
  - **de spec fechada**: a branch foi mergeada ou apagada;
  - **parado**: sem commit há mais de 14 dias e sem sessão viva.
  
  Cada um mostra o caminho, a branch, o espaço em disco e se tem alterações não commitadas.
- R4 · **Atrás da base** deve listar as branches abertas com o número de commits atrás e à frente da branch padrão (`git rev-list --left-right --count`), em ordem de quantos atrás. Se houver conflito previsto (o `predictConflict` do Review, com `git merge-tree --write-tree`), o item diz quais arquivos e oferece "Abrir no Review", onde a SPEC-032 refaz a base e a SPEC-043 confere a resolução. Esse grupo só informa e não apaga nada.
- R5 · **Refs internas** deve contar as refs `refs/promptorium/<spec>/` de specs já mergeadas ou apagadas, agrupadas por spec, com "Limpar" por spec ou todas.
- R6 · Nada é apagado sem proteção:
  - nunca entram na lista: a branch padrão, a branch atual de qualquer worktree, uma branch com sessão viva e um worktree com alterações não commitadas. Eles aparecem esmaecidos, com o motivo ("sessão viva", "alterações não commitadas"), e não podem ser selecionados;
  - "Limpar selecionados" abre uma confirmação que lista tudo o que vai sair, separando local de remoto. Apagar no remoto exige marcar uma caixa própria;
  - uma branch local só é apagada com `git branch -d`. Se o git recusar, o item fica com o erro e não é forçado.
- R7 · Depois da limpeza, um aviso deve dizer o que saiu e oferecer **Desfazer** por 15 s. Ele recria as branches locais nos SHAs guardados e os worktrees removidos de branches que ainda existem. Branches apagadas no remoto e refs internas não voltam, e a confirmação já avisa isso.
- R8 · Quando a soma de branches mergeadas e worktrees de specs fechadas passar de 20, o Início deve mostrar um card discreto "Repositório com 31 itens para limpar", que leva à aba. O card pode ser dispensado por 30 dias.

## Fora do escopo

- Limpeza automática, sem a pessoa.
- Reescrever histórico (`gc`, `filter-repo`, apagar tags).
- Mudar o fim da spec para apagar a branch e o worktree no merge. É uma decisão do Review, para outra spec.
- Atualizar branches atrasadas pela aba. Continua no Review (SPEC-032).

## Design

### O que já existe

- `lib/features/repository/repository_screen.dart` (SPEC-044).
- `lib/core/git/git_service.dart`: `removeWorktree`, `deleteBranch`, `deleteRefs(prefix)` e `resolveRef`.
- `lib/features/review/review_service.dart`: `predictConflict`.
- `lib/features/sessions/session_manager.dart`: as sessões vivas e o worktree de cada uma.
- `lib/core/process/orphans.dart`: o padrão para processos que sobram. Os worktrees seguem a mesma ideia.
- `lib/features/home/`: os cards do Início.

### Componentes

- `lib/features/repository/hygiene/hygiene_scan.dart` (novo): monta os quatro grupos a partir do git, do `gh` e das sessões vivas. As regras de proteção (R6) ficam em funções puras.
- `lib/features/repository/hygiene/hygiene_cleaner.dart` (novo): apaga na ordem certa (worktree, branch local, remota, refs), guarda os SHAs e faz o Desfazer (R7).
- `lib/features/repository/hygiene/hygiene_tab.dart` (novo): os grupos, a seleção e a confirmação.
- `GitService.worktreeListPorcelain()`, `pruneDryRun()` e `aheadBehind(branch, base)` (novos).
- Card do Início: `hygieneSummaryProvider`, com a dispensa guardada nas configurações do app.

### Testes

- `test/features/repository/hygiene_scan_test.dart`: mergeada por merge e por squash, os três tipos de worktree, atrás e à frente, refs por spec, e as proteções.
- `test/features/repository/hygiene_cleaner_test.dart`: ordem de remoção, `-d` recusado sem forçar, remoto só com a caixa marcada, Desfazer.
- `test/features/repository/hygiene_tab_test.dart`: seleção, esmaecidos com o motivo, confirmação e card do Início.

## Decisões

- **`git branch -d`, nunca `-D`.** Se o git acha que há trabalho fora da base, a aba confia nele e mostra o motivo.
- **Remoto em caixa separada.** Apagar no GitHub afeta outras pessoas e não volta com o Desfazer.
- **Atrás da base só informa.** Refazer a base envolve agente, gate e conflito, e isso já está no Review.
- **Parado depois de 14 dias.** É o bastante para uma spec pausada não aparecer como lixo na mesma semana.

## Plano

1. Validar o mockup (tabela no início da spec).
2. `hygiene_scan` com as proteções e os testes.
3. Aba com os quatro grupos e a seleção.
4. `hygiene_cleaner`, confirmação e Desfazer.
5. Card do Início; guia `docs/guia/repositorio.md`.

## Critérios de aceite

- [ ] Branches mergeadas por merge e por squash aparecem, com remotas em caixa separada [R2] verificar: flutter test test/features/repository/hygiene_scan_test.dart
- [ ] Worktrees órfãos, de spec fechada e parados são reconhecidos com o espaço em disco [R3] verificar: flutter test test/features/repository/hygiene_scan_test.dart
- [ ] Atrás da base mostra atrás e à frente e o conflito previsto, sem opção de apagar [R4] verificar: flutter test test/features/repository/hygiene_tab_test.dart
- [ ] Refs internas de specs fechadas são contadas e limpas por spec [R5] verificar: flutter test test/features/repository/hygiene_cleaner_test.dart
- [ ] Branch padrão, branch atual, sessão viva e worktree sujo nunca são selecionáveis [R6] verificar: flutter test test/features/repository/hygiene_scan_test.dart
- [ ] `-d` recusado não é forçado e o remoto só sai com a caixa marcada [R6] verificar: flutter test test/features/repository/hygiene_cleaner_test.dart
- [ ] Desfazer recria branches e worktrees locais em 15 s [R7] verificar: flutter test test/features/repository/hygiene_cleaner_test.dart
- [ ] O card do Início aparece acima de 20 itens e some por 30 dias ao dispensar [R8] verificar: flutter test test/features/repository/hygiene_tab_test.dart
- [ ] Os worktrees antigos do próprio Promptorium são limpos pelo app sem perder alterações [R3, R6, R7] verificar: manual (aba Higiene no próprio repositório)
- [ ] O projeto compila e a análise estática passa [R1–R8] verificar: flutter analyze
