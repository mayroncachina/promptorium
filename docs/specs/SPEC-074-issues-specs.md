---
id: SPEC-074
status: aprovada
depende-de: SPEC-068
issue: 243
---

# Issues ↔ specs: importar issues na Bandeja, Closes #N no PR e andamento na issue

## Objetivo

O backlog real de um projeto costuma estar nas issues do GitHub. Hoje, para trabalhar uma delas no app, a pessoa copia o texto à mão para a Nova spec, escreve "Closes #N" no PR à mão (ou esquece) e nada liga a spec à issue: dá para copiar a mesma issue duas vezes, e uma issue fechada no GitHub não aparece no app.

O frontmatter `issue: N` já existe nas specs deste repositório, mas o app só o conhece como chave válida (`knownFrontmatterKeys` em `spec_lint.dart`). Ninguém o lê.

Esta spec liga issues e specs nos dois sentidos:
- **"Importar issues"** na Bandeja (SPEC-068), com filtros e busca. Cada issue marcada vira uma spec em rascunho com `issue: N`;
- o PR da spec leva **`Closes #N`** sozinho;
- com opt-in, o `anotar_andamento` (SPEC-052) mantém **um comentário de andamento** na issue;
- uma spec criada no app ganha **"Criar issue"** e fica ligada;
- o app mostra o **selo `#N`** e, quando a issue fecha no GitHub, o selo muda. Nada se move sozinho.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/WiB5xU4HnnMMXAUZA1WMRV). Capturas em `docs/mockups/spec-074/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-antes.png` | Hoje: a Bandeja não enxerga as issues; copiar à mão, PR sem "Closes", issue aberta depois do merge | — |
| `2-importar-issues.png` | O diálogo "Importar issues": busca, filtros, número previsto e a issue já importada travada | R3, R4, R12 |
| `3-bandeja-com-selo.png` | As specs importadas na Bandeja com o selo `#N`, o menu da spec e a issue fechada só com o selo | R1, R5, R6, R7, R9 |
| `4-pr-closes.png` | O PR criado com `Closes #226` no corpo, a linha ISSUE no "Pronto para merge?" e o caso do PR empilhado | R8 |
| `5-andamento-na-issue.png` | O comentário de andamento na issue e o opt-in na configuração do projeto | R10 |
| `6-criar-issue.png` | "Criar issue" a partir de uma spec, com o texto já montado | R11 |
| `7-sem-github.png` | Sem `gh`, sem login, repositório no GitLab e issues desligadas | R2 |

Issue: [#243](https://github.com/mayroncachina/promptorium/issues/243) (sub-issue de [#240](https://github.com/mayroncachina/promptorium/issues/240)) · PR: [#246](https://github.com/mayroncachina/promptorium/pull/246)

## Requisitos

- R1 · **A ligação é o `issue: N` do frontmatter.**
  - O app lê `issue:` (um número inteiro) e guarda o número no banco a cada sincronização da spec.
  - Uma spec ligada mostra o selo **`#N`** na Bandeja, nos cards do Quadro, na lista e no cabeçalho da tela Specs. Clicar abre a issue no navegador, no repositório do remote do Review.
  - Um valor inválido (`issue: abc`) vira aviso de estrutura (SPEC-023 R8) e não mostra selo.
  - As specs que já têm `issue:`, como as deste repositório, ganham o selo sem mudar nada.
- R2 · **Sem GitHub, nada quebra.** "Importar issues", "Criar issue", o `Closes #N` e o comentário usam o mesmo diagnóstico do Review (`prAvailability`):
  - sem remote, remote local, host que não é GitHub (inclusive GitLab), `gh` ausente (com o link de instalação), `gh` sem login em `github.com`, e as issues desligadas no repositório;
  - o botão fica desligado, com o motivo como dica; o diálogo mostra o motivo e "Conferir de novo";
  - specs, Quadro e PRs seguem como hoje. O selo continua aparecendo, só sem o estado da issue.
- R3 · **"Importar issues".** O cabeçalho da Bandeja ganha o botão, que abre um diálogo com:
  - a busca no título e no texto, e os filtros Estado (Abertas, o padrão; Fechadas; Todas), Label (várias), Milestone e Responsável (qualquer, eu, uma pessoa, sem responsável). As opções dos filtros vêm do repositório;
  - a lista: caixa, `#N`, título, labels, milestone, responsável e dicas ("checklist · 3 itens", "2 imagens"). Cada issue marcada mostra o número que vai ganhar ("vira SPEC-024"), como na SPEC-068 R4;
  - o total com os filtros e páginas de 50, com "Carregar mais N". A lista não trava enquanto carrega;
  - o botão diz quantas entram ("Importar 3 issues"). Esc ou "Cancelar" fecha sem criar nada.
- R4 · **Sem duplicar.**
  - Uma issue que já tem spec (em qualquer estado, até em Feito) aparece travada, com "já importada · SPEC-023" e "Abrir".
  - Pull requests nunca aparecem na lista.
  - A criação é exclusiva, como a da SPEC-068 R4: o app confere de novo antes de gravar, e duas importações ao mesmo tempo não criam duas specs para a mesma issue.
- R5 · **A spec importada.** Cada issue vira uma spec `status: rascunho`, com `issue: N`, na Bandeja:
  - o título é o da issue; o texto da issue vira o **Objetivo**;
  - os comentários HTML (restos de modelo de issue) saem; os títulos da issue descem um nível, para ficar dentro do Objetivo; checklists e links ficam como estão; imagens ficam como links, sem baixar nada;
  - um texto acima de 40.000 caracteres é cortado no fim do último parágrafo que cabe, com aviso (o limite da SPEC-057);
  - "Requisitos" e "Critérios de aceite" vêm vazios, com uma linha que lembra de refinar (R6);
  - a Bandeja agrupa essas specs em "Das issues do GitHub · N". O aviso final diz "3 issues viraram SPEC-024 a SPEC-026, na Bandeja", com "Abrir a primeira".
- R6 · **Refinar com o Claude.** O menu da spec ligada (na Bandeja e na tela Specs) tem "Refinar requisitos com o Claude".
  - Ele abre a Nova spec (SPEC-039) com o texto da issue já no "Conte a ideia", como um arquivo importado na SPEC-057, com o cartão "Da issue #215".
  - Salvar a spec planejada reescreve a **mesma** spec (mesmo código, mesmo `issue:`), sem criar outra.
  - Nada é enviado sozinho: a pessoa revisa como em qualquer Nova spec.
- R7 · **Atualizar e desligar.**
  - Se a issue foi editada depois da importação, o menu mostra "Atualizar com a issue · texto mudou". Numa spec em rascunho, ele troca o Objetivo pelo texto novo, mostrando o antes e o depois, e só grava ao confirmar. Numa spec aprovada, só avisa.
  - "Desligar da issue" tira o `issue:` do frontmatter, com confirmação.
- R8 · **`Closes #N` no PR.** Ao criar o PR de uma spec ligada (`createPr`):
  - se a base do PR é a branch padrão do repositório, o corpo ganha a linha `Closes #N`;
  - se a base é outra (PR empilhado, filha de uma spec mãe), o corpo leva `Parte de #N`, porque o GitHub só fecha a issue no merge para a branch padrão;
  - com `issues.closes-no-pr: false` no `config.yml`, o corpo leva só `Issue: #N`;
  - o "Pronto para merge?" do Review mostra a linha "ISSUE · #N fecha quando este PR entrar na main" (ou "não fecha: a base é spec/020-frete");
  - um PR que já existe não é editado.
- R9 · **Estado da issue.** O app confere o estado das issues ligadas ao abrir o Quadro e a cada 10 minutos com o app aberto (`issues.conferir-fechadas`, ligado por padrão), numa consulta só por workspace.
  - Uma issue fechada muda o selo para "**#N fechada**" (em texto, não só na cor), com a dica "Fechada no GitHub em 14/11, pelo PR #250" (ou "à mão").
  - **Nada se move**: o estado da spec, a coluna do Quadro e a Bandeja ficam como estão. Isso vale também para um PR feito fora do app que fecha a issue.
  - Uma issue reaberta volta ao selo normal. Uma issue apagada ou transferida mostra "#N não encontrada".
- R10 · **Andamento na issue, com opt-in.** Com `issues.comentar-andamento: true` no `config.yml` (desligado por padrão):
  - depois que o `anotar_andamento` grava uma nota numa spec ligada, o app cria ou edita **um comentário só por spec** na issue, achado por uma marca escondida (`<!-- promptorium:SPEC-023 -->`);
  - o comentário tem o título "Andamento da SPEC-023", o estado de cada requisito (feito, em execução, a fazer) com a última nota de cada um, o PR quando houver e a linha "Atualizado pelo Promptorium";
  - o app comenta com a conta do `gh` logado e nunca numa issue fechada;
  - sem rede ou sem `gh`, a nota fica no app, o selo mostra "comentário pendente" e a próxima nota tenta de novo;
  - a resposta da ferramenta diz ao agente se a issue foi atualizada ("Nota gravada em SPEC-023 e publicada na issue #226") ou por que não;
  - desligado, nada vai para o GitHub.
- R11 · **"Criar issue".** Uma spec sem `issue:`, num repositório GitHub disponível, ganha "Criar issue" no cabeçalho da tela Specs e no menu do card da Bandeja.
  - O diálogo traz o título (o da spec), o texto (o Objetivo, os requisitos como checklist e a linha "Spec: `docs/specs/SPEC-027-….md`"), e labels, milestone e responsável opcionais.
  - "Criar issue" roda `gh issue create` e só então grava `issue: N` no arquivo da spec e mostra o selo. Se falhar, nada muda na spec e o motivo aparece no diálogo.
- R12 · **Acessibilidade.**
  - A lista do diálogo é um grupo de caixas operável pelo teclado: Espaço marca, Enter importa, e a issue travada sai da ordem do Tab, com "Abrir" alcançável.
  - O selo anuncia "Issue 226, aberta" ou "Issue 226, fechada".
  - Os estados nunca dependem só da cor: "fechada", "já importada" e "comentário pendente" são texto.

## Fora do escopo

- Issues de GitLab, Jira, Linear ou YouTrack. O Review hoje só cria PR no GitHub (a integração GitLab está adiada no DT-55, SPEC-013); quando ela voltar, as issues do GitLab podem seguir o mesmo caminho.
- Sincronizar o texto nos dois sentidos: editar a spec não edita a issue, e a issue só volta para a spec pelo "Atualizar com a issue" (R7).
- Fechar, reabrir, rotular ou atribuir issues pelo app, além do que o `Closes #N` faz no merge.
- Mover uma spec quando a issue fecha (R9).
- Trazer os comentários da issue para a spec. Entra só o texto da issue.
- Issues de outro repositório (fork ou upstream): só o repositório do remote do Review.
- Campos do GitHub Projects.

## Design

### O que já existe

- `lib/core/git/gh_cli.dart`: `GhCli` com `gh(args)`, `_json`, `ghAvailable`, `ghAuthStatus`, `prList`, `prListMerged`, `prListOpen`, `prView`, `runFailedLog`. **Não há nenhum comando de issue** (`issue list`, `issue view`, `issue create`, comentários).
- `lib/features/specs/spec_file.dart`: `SpecDocument`, com `id`, `status`, `kind`, `origin` (`origem`), `dependsOn`, e os escritores `with…` (`withAutoPlan`, `withSection`). Não lê `issue`.
- `lib/features/specs/spec_lint.dart`: `knownFrontmatterKeys` tem `'issue'` como literal, só para não dar aviso de chave desconhecida.
- `lib/features/specs/spec_service.dart`: `sync`, que lê a pasta de specs e insere ou atualiza a tabela `specs`.
- `lib/data/db/app_database.dart`: a tabela `Specs`, com `originConversationId`, `originAnswer`, `originItem` e `inTray` (SPEC-068, schema v24); a tabela `SpecNotes` (SPEC-052).
- `lib/features/board/widgets/board_tray.dart`: a Bandeja (`BoardTrayOpen`, `trayGroups` por conversa de origem, `takenMessage`). `lib/features/board/board_rules.dart`: `isInTray`.
- `lib/features/prompt/spec_batch.dart`: `createSpecBatch`, a criação exclusiva com o próximo número livre (SPEC-068 R4). `lib/features/prompt/widgets/spec_batch_dialog.dart`: a lista de revisão.
- `lib/features/ideas/idea_import.dart` e `lib/features/ideas/widgets/idea_field.dart`: o texto importado no "Conte a ideia", com o cartão de origem e o limite de 40.000 (SPEC-057). `lib/features/specs/new_spec_view.dart` e `spec_planner.dart`: a Nova spec (SPEC-039).
- `lib/features/review/review_service.dart`: `createPr` monta o corpo do PR (`Spec: …`, `Etapas: …`, `Criado pelo Promptorium (sessão …)`) e roda `gh pr create`; `prAvailability` dá o diagnóstico de remote e host (`PrAvailability.reason`).
- `lib/features/review/review_host.dart`: `detectReviewHost` (github, gitlab ou nenhum) e `GithubHost.availability` (instalação e `gh auth status`).
- `lib/features/review/merge_readiness.dart`: as linhas do "Pronto para merge?".
- `lib/features/review/widgets/pr_import_dialog.dart`: o "Trazer PR" (SPEC-050), uma lista de PRs do GitHub num diálogo, bom modelo para a lista de issues.
- `lib/core/mcp/app_mcp_tools.dart`: `_note`, o `anotar_andamento`, grava em `spec_notes` e responde ao agente (limite de 280 caracteres).
- `lib/features/project/project_config.dart`: as seções do `config.yml` (`revisor:`, `vibe:`, `review:`…) e `lib/features/project/widgets/project_config_view.dart`, a tela que as edita.

### Componentes

- **`GhCli`**, comandos novos, todos por `--json` e testáveis com o `CliRunner` falso:
  - `issueList({state, labels, milestone, assignee, search, page})`, por `gh api` paginado (50 por página, sem os PRs) e `gh issue list --search` para a busca;
  - `issueView(n)`, `issueCreate({title, body, labels, milestone, assignee})` (devolve o número), `issueStates(numbers)` (uma consulta GraphQL para todos), `labelList`, `milestoneList`;
  - `issueCommentUpsert(n, marker, body)`: procura o comentário com a marca e edita (`PATCH`) ou cria.
  - A classe `GhIssue` (número, título, texto, estado, labels, milestone, responsáveis, `updatedAt`, `closedAt`, quem fechou).
- **`SpecDocument.issue`** (`int?`) e `withIssue(int?)`; a constante `specIssueKey = 'issue'` substitui o literal de `spec_lint.dart`, que passa a avisar valor inválido (R1).
- **Banco**: colunas novas em `specs` (migração): `issueNumber`, `issueState` (aberta, fechada, não encontrada), `issueClosedAt`, `issueClosedBy`, `issueImportedAt`, `issueCommentPending`. O `SpecService.sync` preenche `issueNumber` a partir do arquivo; o resto é do app, como a origem da SPEC-068.
- **`issueAvailability(workspace)`**: o diagnóstico do R2, feito a partir de `prAvailability` sem exigir sessão nem worktree, mais a checagem de issues ligadas no repositório.
- **`issueToSpecText(GhIssue, code)`** (função pura): monta o rascunho do R5. **`importIssues(issues)`** usa `createSpecBatch` para os números e grava `issueImportedAt`.
- **`IssueImportDialog`**: o diálogo do R3 e R4, com os filtros e a paginação. **`IssueBadge`**: o selo, usado na Bandeja, no `card_extras.dart` do Quadro, na `spec_list.dart` e no `spec_header.dart`.
- **`trayGroups`** ganha o grupo "Das issues do GitHub" para as specs com `issueImportedAt` e sem conversa de origem.
- **`prIssueLine(spec, base, defaultBranch, config)`** (função pura) em `review_service.dart`: `Closes #N`, `Parte de #N` ou `Issue: #N` (R8). A branch padrão vem de `gh repo view --json defaultBranchRef`, guardada por workspace. Uma linha nova em `merge_readiness.dart`.
- **`IssueStateWatcher`**: o laço do R9, por workspace, só com GitHub disponível e só para as specs com `issueNumber`.
- **`IssueProgressPublisher`**: chamado por `_note` depois de gravar a nota, só com o opt-in; monta o comentário a partir de `spec_steps` e `spec_notes` e chama `issueCommentUpsert` (R10).
- **`IssuesConfig`** em `ProjectConfig` (`issues:` com `closes-no-pr`, `comentar-andamento`, `conferir-fechadas`) e a seção "Issues do GitHub" na `project_config_view.dart`.
- **`CreateIssueDialog`**: o R11, com o texto montado por uma função pura (`issueBodyFromSpec`).

### Testes

- `GhCli`: os argumentos e o parse de cada comando de issue; a paginação; PRs fora da lista; o upsert do comentário acha a marca e edita, ou cria.
- `SpecDocument.issue`: lê, escreve e avisa valor inválido; as specs deste repositório ganham `issueNumber` no sync.
- `issueToSpecText`: comentário HTML removido, títulos rebaixados, checklist e imagens mantidos, corte em 40.000 com aviso.
- Importar: número previsto, issue já importada travada, criação exclusiva com duas importações ao mesmo tempo, grupo na Bandeja.
- `prIssueLine`: `Closes` com base na branch padrão, `Parte de` com outra base, `Issue:` com a opção desligada, nada sem `issue:`.
- Estado: fechada muda o selo e não move nada; reaberta volta; 404 vira "não encontrada".
- Andamento: desligado não chama o `gh`; ligado cria e depois edita o mesmo comentário; falha marca "comentário pendente" e a resposta ao agente diz o motivo; issue fechada não recebe comentário.
- Criar issue: grava `issue: N` só depois do `gh issue create`; falha não muda o arquivo.
- Disponibilidade: cada motivo do R2 desliga o botão com a dica certa.

## Tarefas

| Tarefa | Entrega | Requisitos |
|---|---|---|
| t1 · Base | Comandos de issue no `GhCli`, `SpecDocument.issue`, colunas novas, `issueAvailability` e o selo `#N` | R1, R2, R12 |
| t2 · Importar | O diálogo, a conversão da issue, a criação sem duplicar, o grupo na Bandeja, refinar, atualizar e desligar | R3, R4, R5, R6, R7, R12 |
| t3 · PR, estado e Criar issue | `Closes #N` / `Parte de #N`, a linha no "Pronto para merge?", o `IssueStateWatcher` e o "Criar issue" | R8, R9, R11 |
| t4 · Andamento | `IssuesConfig`, a seção na configuração e o comentário único do `anotar_andamento` | R10 |

t2, t3 e t4 dependem de t1 e não dependem entre si.

## Critérios de aceite

- [ ] Uma spec com `issue: N` mostra o selo `#N` na Bandeja, no Quadro e na tela Specs; um valor inválido vira aviso [R1] verificar: flutter test test/features/specs
- [ ] Sem remote, com GitLab, sem `gh` ou sem login, os botões ficam desligados com o motivo, e o resto do app segue igual [R2] verificar: flutter test test/features/review/review_host_test.dart
- [ ] Os comandos de issue do `GhCli` montam os argumentos certos, paginam e deixam os PRs de fora [R3] verificar: flutter test test/core/git/gh_cli_test.dart
- [ ] Importar 3 issues cria 3 rascunhos com `issue: N` na Bandeja, no grupo "Das issues do GitHub", e uma issue já importada fica travada [R3, R4, R5] verificar: flutter test test/features/board/board_tray_test.dart
- [ ] O texto da issue vira o Objetivo, sem comentários HTML, com títulos rebaixados e cortado em 40.000 caracteres [R5] verificar: flutter test test/features/specs
- [ ] "Refinar requisitos com o Claude" reescreve a mesma spec, sem criar outra [R6] verificar: flutter test test/features/specs/new_spec_flow_test.dart
- [ ] "Atualizar com a issue" troca o Objetivo só num rascunho e só ao confirmar; "Desligar da issue" tira o `issue:` [R7] verificar: flutter test test/features/specs
- [ ] O PR de uma spec ligada leva `Closes #N` com base na branch padrão e `Parte de #N` com outra base [R8] verificar: flutter test test/features/review/review_service_test.dart
- [ ] Uma issue fechada no GitHub muda o selo para "#N fechada" e não move a spec [R9] verificar: flutter test test/features/board
- [ ] Com o opt-in, notas seguidas editam um comentário só na issue; desligado, nada vai para o GitHub [R10] verificar: flutter test test/core/mcp/app_mcp_tools_test.dart
- [ ] "Criar issue" grava `issue: N` só depois de a issue existir [R11] verificar: flutter test test/features/specs
- [ ] A lista do diálogo funciona só com o teclado e os estados aparecem em texto [R12] verificar: flutter test test/features/board/board_tray_test.dart
- [ ] Importar, criar o PR e mergear num repositório de teste fecha a issue e muda o selo [R3, R8, R9] verificar: manual (repositório de teste no GitHub, app isolado com `XDG_DATA_HOME`)
- [ ] O projeto compila e a análise estática passa [R1–R12] verificar: flutter analyze

## Decisões em aberto

- P1 · **Onde fica o opt-in do comentário.** No `config.yml` (`issues.comentar-andamento`, vale para todos que usam o repositório no app) ou numa preferência local do app, por workspace. **Recomendação:** `config.yml`. O comentário é público na issue; a decisão de publicar é do projeto, fica versionada e não muda de pessoa para pessoa.
- P2 · **Um comentário por spec, editado, ou um por nota.** Um por nota avisa quem acompanha a issue a cada passo, mas enche a issue. **Recomendação:** um por spec, editado (R10). Quem quer acompanhar de perto já tem o PR.
- P3 · **O que fazer quando a issue fecha.** Só o selo (R9) ou também oferecer "Marcar a spec como concluída" / "Descartar o rascunho". **Recomendação:** só o selo nesta spec, como pedido. Se o uso mostrar que falta, uma ação manual no menu do selo entra depois.
- P4 · **`Parte de #N` no PR empilhado.** Escrever `Parte de #N` quando a base não é a branch padrão, ou escrever `Closes #N` sempre. **Recomendação:** `Parte de #N` (R8). O `Closes` num PR para outra branch não fecha nada no GitHub e engana quem lê.
- P5 · **Onde fica o botão "Importar issues".** Só no cabeçalho da Bandeja ou também no menu do "Nova spec" e na paleta de comandos (Ctrl K). **Recomendação:** Bandeja e paleta. O menu do "Nova spec" já tem "Fazer como tarefa" (SPEC-069) e ficaria cheio.
- P6 · **Texto da issue criada pelo app.** Só o Objetivo e o caminho da spec, ou também os requisitos como checklist. **Recomendação:** com a checklist (R11). Quem lê a issue vê o escopo sem abrir o repositório; os itens não são marcados pelo app (fora do escopo).
