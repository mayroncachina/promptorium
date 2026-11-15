---
id: SPEC-073
status: proposta
issue: 242
---

# CI vermelho vira correção

## Objetivo

Quando o CI de um PR falha, o Promptorium só conta: "PR aberto · 2 check(s) falhando". O log nunca chega ao agente. A pessoa abre o GitHub, acha o job, copia o trecho do erro e cola na sessão à mão. Isso acontece em quase todo PR e é sempre o mesmo trabalho.

Esta spec leva o log ao agente:
- num check que falhou, o botão **"Corrigir CI"**, no card do Quadro e no Review, busca o log do GitHub Actions e o manda para a sessão da spec, com as instruções de corrigir, rodar os testes afetados e commitar;
- o app envia o commit para o PR e acompanha o CI de novo, como já faz com os comentários do PR;
- **"Rodar de novo"** roda outra vez só os jobs que falharam, para uma falha que parece intermitente;
- com `revisor.ci-automatico: true` no `.promptorium/config.yml`, a correção começa sozinha, **uma vez por commit vermelho**. Se o commit da correção também ficar vermelho, o app para e avisa. Não há laço.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/MhRbtsweiDN9qoUZBSCJd9). Capturas em `docs/mockups/spec-073/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-hoje.png` | Hoje: o Review diz "3 check(s) falhando" e o card do Quadro não diz nada | — |
| `2-review.png` | O Review com os checks vermelhos, o trecho do log, "Corrigir CI" e "Rodar de novo" | R2, R3, R4, R8, R9 |
| `3-sessao.png` | A sessão recebe a mensagem com o log e o agente corrige | R4, R5, R6 |
| `4-quadro.png` | O card no Review do Quadro: "CI falhou", "Corrigindo CI", "CI rodando" e "CI corrigido" | R7 |
| `5-parado.png` | O automático parou depois da segunda falha, com o aviso | R11, R12 |
| `6-config.png` | A Configuração do projeto com "Corrigir CI sozinho" | R13 |

Issue: [#242](https://github.com/mayroncachina/promptorium/issues/242) (sub-issue de #240)

## Requisitos

- R1 · **Checks com detalhe.** O app passa a ler, de cada check do PR: nome, estado, workflow, link e, quando é do GitHub Actions, o run e o job (tirados do `detailsUrl`). Lê também o SHA do commit do PR (`headRefOid`).
  - Um check que não é do Actions (um `StatusContext` ou outro app) fica marcado "sem log".
- R2 · **Os checks no Review.** O painel do PR lista cada check que falhou numa linha: nome, workflow, o passo que falhou e "Abrir no GitHub".
  - A linha abre e mostra o trecho do log (R3), em fonte mono, com a contagem do que foi cortado.
  - Acima da lista ficam **"Corrigir CI"** e **"Rodar de novo"**.
  - O resumo do topo continua ("PR aberto · 2 de 5 checks falharam · commit a1b2c3d").
- R3 · **O trecho do log.** O app busca `gh run view <run> --log-failed` de cada run que falhou e corta o que vai para o agente:
  - separa por job e por passo; tira cores ANSI e o horário do começo das linhas;
  - em cada passo, guarda as linhas com cara de erro (`error`, `Error:`, `FAILED`, `##[error]`, `Expected`, `exit code`…) com 5 linhas antes e depois, mais as 30 últimas linhas do passo;
  - o teto é de 200 linhas e 16 mil caracteres por mensagem;
  - todo corte vira uma linha que diz o que saiu: `… 1.204 linhas cortadas (linhas 12–1.215 de "Run flutter test") …`;
  - jobs de matriz com o mesmo trecho aparecem uma vez, com "mesmo erro em test (macos), test (windows)";
  - passado o teto, os jobs que sobraram aparecem só pelo nome, com o comando do log completo.
- R4 · **Corrigir CI.** O botão manda a mensagem para a sessão do PR:
  - a sessão da spec, a conversa da VIBE (SPEC-069) ou a sessão do PR trazido (SPEC-050);
  - se a sessão não tem processo vivo, o app a retoma (`--resume`, no mesmo worktree), como "Pedir ajustes" já faz;
  - a mensagem diz o PR, o commit, os checks que falharam, o trecho de cada job (R3), o comando do log completo (`gh run view <run> --log-failed`) e as instruções: achar a causa, corrigir sem mudar o teste para esconder a falha, rodar os testes afetados e o lint, e commitar;
  - se a falha não for do código (rede, runner, segredo ausente), o agente não muda nada e responde começando com `CI: falha externa`;
  - cada correção deixa uma linha na sessão ("Corrigir CI · commit a1b2c3d · 2 checks") e conta como uma rodada no histórico do Review (CI1, CI2…);
  - uma correção por commit: enquanto ela não termina, o botão vira "Corrigindo CI…" e não envia de novo.
- R5 · **Sessão ocupada.** Se o agente está no meio de um turno, a mensagem não entra no meio do trabalho. Ela espera o turno acabar e sai logo depois.
  - O card e o Review mostram "Na fila: a sessão está ocupada", com "Cancelar".
- R6 · **O push é do app.** O agente só commita. Quando a sessão fica parada, o app envia a branch para o PR (`pushIfAhead`), como já faz com os comentários do PR.
  - Se o agente terminar sem commit, o card diz "O agente terminou sem commit" e mostra a resposta dele.
  - Se o agente respondeu `CI: falha externa`, o card mostra o motivo e oferece "Rodar de novo".
  - Se o push for recusado (proteção da branch, hook, credencial), o card mostra o motivo do git com "Tentar de novo".
- R7 · **O selo no card.** O card de uma spec com PR ganha um selo de CI, ao lado do `GateFixBadge`:
  - "CI falhou · 2" em vermelho, com "Corrigir CI";
  - "Na fila" ou "Corrigindo CI", em âmbar, com o tempo;
  - "CI rodando · a1b2c3d" depois do push;
  - "CI corrigido" em verde, até o próximo evento do PR.
  - O card **continua na coluna Review**: corrigir o CI não devolve a spec para Em execução.
  - O selo só aparece quando o app conhece o estado do PR (PR em "Acompanhar PR" ou aberto no Review).
- R8 · **Rodar de novo.** O botão roda `gh run rerun <run> --failed` em cada run que falhou e mostra "Rodando de novo · tentativa 2".
  - Quando o log tem cara de falha intermitente (tempo esgotado, `ECONNRESET`, `Could not resolve host`, HTTP 5xx, limite de requisições, runner desligado), o Review diz "Parece intermitente: <o motivo>" e "Rodar de novo" vem primeiro.
  - Sem permissão no repositório, o erro do `gh` aparece na linha.
- R9 · **Check sem log.** Um check que não é do Actions aparece com "sem log disponível" e "Abrir check". Ele não entra na mensagem.
  - Se só checks sem log falharam, "Corrigir CI" fica desligado, com o motivo: "Nenhum check com log do GitHub Actions".
- R10 · **PR trazido sem permissão de escrita** (SPEC-050). "Corrigir CI" avisa antes: "O commit fica local; use Copiar patch para mandar ao autor". O automático não roda nesse PR.
- R11 · **Corrigir sozinho.** Com `revisor.ci-automatico: true`, o babysitter começa a correção sem a pessoa:
  - só em PR com "Acompanhar PR" ligado, e só quando nenhum check do commit está rodando (uma mensagem cobre todas as falhas);
  - uma vez por commit vermelho, guardada em `pr.ci.<sessão>` (o SHA e a origem: você ou automático);
  - se o log tem cara de falha intermitente (R8), ele roda de novo uma vez antes de corrigir;
  - uma notificação avisa "Corrigindo o CI de SPEC-071 sozinho".
- R12 · **Sem laço.** Se o commit que a correção automática gerou também ficar vermelho, o app **para**:
  - notificação "O CI continua vermelho depois da correção automática";
  - o card diz "CI falhou de novo · automático parado", e o Review mostra o aviso com o trecho novo e "Corrigir CI" à mão;
  - o automático também para quando o agente termina sem commit ou o push é recusado (R6);
  - ele volta a valer quando o CI fica verde, ou quando você usa "Corrigir CI" ou "Rodar de novo" à mão.
- R13 · **Na Configuração.** A Configuração do projeto ganha a seção "CI do PR", com "Corrigir CI sozinho, uma vez por commit vermelho". Ela grava `revisor.ci-automatico` no `.promptorium/config.yml`.
  - O guia `docs/guia/review.md` ganha a seção "CI vermelho".

## Fora do escopo

- GitLab e MR: o acompanhamento de MR ainda não existe (SPEC-013).
- Log de CI fora do GitHub Actions (CircleCI, Buildkite, Jenkins).
- Corrigir CI de uma branch sem PR ou da `main`.
- Mais de uma correção automática por commit, ou mergear sozinho depois do verde.
- Mudar o item "CI falhou" do Início: ele continua abrindo o Review.

## Design

### O que já existe

- `lib/core/git/gh_cli.dart`:
  - `runFailedLog(id, lines: 40)` e `tailFailedLog`: as últimas 40 linhas de `gh run view <id> --log-failed`, sem as colunas `job<TAB>passo`. Hoje só a release usa (`release_dispatcher.dart`);
  - `runView` com `GhJob` e `GhStep` (o job e o passo que falharam);
  - `CiState` e `ciStateOf`.
- `lib/features/review/pr_babysitter.dart`:
  - `PrStatus`, `parsePrView` e `prViewFields`: hoje os checks são só `(nome, estado)`, e `summary` monta "N check(s) falhando";
  - `PrBabysitter.check`: lê o PR, manda os comentários novos à sessão (`prCommentsMessage`) e faz o push quando a sessão está parada;
  - `pr.seen.<sessão>` em `app_settings`, o modelo para `pr.ci.<sessão>`.
- `lib/features/review/review_service.dart`: `prView`, `pushIfAhead`, `_pushImported` (SPEC-050 R7, só com `canPush`), `copyPatch` e `prChecks`.
- `lib/features/review/widgets/pr_panel.dart`: o painel do PR no Review ("Acompanhar PR", "Verificar agora", "Mergear PR…", "Resolver conflito com o agente").
- `lib/features/sessions/session_manager.dart`: `send` retoma a sessão sem processo e leva a mensagem de uma VIBE para a conversa dela. Os avisos de edição (`_notices`) já esperam o turno acabar para sair.
- `lib/features/board/board_screen.dart` (`SpecCard`) e `lib/features/board/widgets/gate_fix_badge.dart`: o selo "Corrigir e verificar" do gate, o modelo do selo de CI.
- `lib/features/review/pr_import.dart`: `ImportedPr.canPush` e o resumo "N checks falharam" do PR trazido.
- `lib/features/home/home_inbox.dart`: o item "CI falhou em …" do Início.
- `lib/features/project/project_config.dart` (`ReviewerConfig`, chave `revisor:`) e `widgets/project_config_view.dart` (a seção "Revisor automático").
- O modelo do automático com limite: `review: resolver-conflitos: automatico` (SPEC-043 R6), que pede "Corrigir e verificar" uma única vez.

### Componentes

- **`PrCheck`** (em `pr_babysitter.dart`): `name`, `state`, `workflow`, `url`, `runId`, `jobId` e `hasLog`. `PrStatus.checks` passa a ser `List<PrCheck>`, e `PrStatus` ganha `headSha`. `prViewFields` pede `headRefOid`.
- **`GhCli.runFailedLogRaw(run)`** e **`GhCli.runRerunFailed(run)`** (`gh run rerun <run> --failed`).
- **`ciLogExcerpt(raw, {maxLines, maxChars})`** (novo, `lib/features/review/ci_log.dart`): o corte da R3, puro e testável. Devolve os trechos por job, o que foi cortado e se tem cara de intermitente (R8).
- **`CiFixer`** (novo Notifier, `lib/features/review/ci_fixer.dart`):
  - `fix(sessionId, {auto})`: lê os runs, monta a mensagem (`ciFixMessage`), grava `pr.ci.<sessão>` e manda à sessão (R4), ou põe na fila se a sessão está ocupada (R5);
  - `rerun(sessionId)` (R8);
  - o estado por sessão (`fila`, `corrigindo`, `rodando`, `corrigido`, `parado`, `semCommit`, `falhaExterna`, `pushRecusado`) que o selo e o Review mostram.
- **`PrBabysitter`**: no `check`, com `ci-automatico`, chama `CiFixer.fix(auto: true)` quando acha um commit novo vermelho e aplica a regra da R12.
- **`CiBadge`** (novo, `lib/features/board/widgets/ci_badge.dart`): o selo da R7 no `SpecCard`.
- **`PrPanel`**: a lista de checks com o trecho (R2), "Corrigir CI" e "Rodar de novo".
- **`ReviewerConfig.ciAuto`** (`ci-automatico`) e a seção "CI do PR" na Configuração.

### Testes

- `parsePrView`: run e job tirados do `detailsUrl`; `StatusContext` sem log; `headRefOid`.
- `ciLogExcerpt`: log de 5 mil linhas fica no teto e diz o que cortou; vários jobs; matriz com o mesmo erro; intermitente.
- `CiFixer.fix`: sessão parada é retomada; sessão ocupada espera o turno; VIBE vai para a conversa; dois cliques enviam uma vez.
- PR trazido sem `canPush`: aviso e nada de automático.
- Automático: uma vez por SHA; o commit da correção vermelho para tudo; volta a valer depois do verde.
- `CiBadge`: os quatro estados; o card fica em Review.

## Tarefas

| Tarefa | Requisitos | Branch |
|---|---|---|
| t1 · Checks e log | R1, R3, R9 | `spec/073-t1-checks-e-log` |
| t2 · Corrigir CI à mão | R2, R4, R5, R6, R7, R8, R10 | `spec/073-t2-corrigir` |
| t3 · Automático e Configuração | R11, R12, R13 | `spec/073-t3-automatico` |

## Critérios de aceite

- [ ] Os checks trazem run, job e workflow, e um check fora do Actions fica "sem log" [R1, R9] verificar: flutter test test/features/review/pr_babysitter_test.dart
- [ ] Um log enorme vira um trecho dentro do teto, com cada corte dito, e jobs de matriz iguais aparecem uma vez [R3] verificar: flutter test test/features/review/ci_log_test.dart
- [ ] "Corrigir CI" manda o log à sessão certa (spec, VIBE ou PR trazido) e retoma a sessão parada [R4] verificar: flutter test test/features/review/ci_fixer_test.dart
- [ ] Com a sessão ocupada, a mensagem espera o turno acabar, e dois cliques enviam uma vez só [R4, R5] verificar: flutter test test/features/review/ci_fixer_test.dart
- [ ] O commit do agente vai para o PR pelo app; sem commit ou com push recusado, o card diz o motivo [R6] verificar: flutter test test/features/review/ci_fixer_test.dart
- [ ] O selo do card mostra falhou, corrigindo, rodando e corrigido, e o card fica em Review [R7] verificar: flutter test test/features/board/ci_badge_test.dart
- [ ] "Rodar de novo" roda só os jobs que falharam e sugere isso numa falha intermitente [R8] verificar: flutter test test/features/review/ci_fixer_test.dart
- [ ] PR trazido sem permissão avisa que o commit fica local e não tem automático [R10] verificar: flutter test test/features/review/ci_fixer_test.dart
- [ ] Com `ci-automatico`, a correção começa sozinha uma vez por commit e para se o commit dela ficar vermelho [R11, R12] verificar: flutter test test/features/review/pr_babysitter_test.dart
- [ ] A Configuração liga e desliga `revisor.ci-automatico` [R13] verificar: flutter test test/features/project
- [ ] Num PR real com um teste quebrado, "Corrigir CI" leva o log ao agente, o commit sobe e o CI fica verde [R2, R4, R6, R7] verificar: manual (repositório de teste no GitHub, app isolado com `XDG_DATA_HOME`)
- [ ] O projeto compila e a análise estática passa [R1–R13] verificar: flutter analyze

## Decisões em aberto

- P1 · **Onde mora a chave.** O pedido diz `revisor.ci-automatico`, mas `revisor:` é o revisor automático da spec (outro agente, com modelo e orçamento). O automático parecido que já existe mora em `review:` (`resolver-conflitos: automatico`). Recomendação: `review: corrigir-ci: automatico`, ao lado do conflito, e a seção "CI do PR" perto de "Revisor automático" na Configuração.
- P2 · **Quem dá o push.** O pedido diz que o agente commita e dá push. Hoje o agente só commita e o app envia (comentários do PR, conflito), e `bloquear-comandos` costuma barrar `git push` no agente. Recomendação: o app dá o push (R6). Assim o PR trazido sem permissão, o remote errado e a proteção da branch continuam tratados num lugar só.
- P3 · **O card volta para Em execução?** "Pedir ajustes" devolve a spec para Em execução. Recomendação: não. O código da spec já foi revisado, e o CI é manutenção do PR. O card fica em Review com o selo (R7).
- P4 · **Gate antes do push.** O app pode rodar o gate do projeto (`testes:`, `lint:`) depois da correção e antes do push. Recomendação: não rodar. O agente já roda os testes afetados e o próprio CI é a verificação. Rodar a suíte inteira atrasaria cada rodada.
- P5 · **Intermitente no automático.** Recomendação: rodar de novo uma vez antes de corrigir, só quando o log tem cara de intermitente (R11). Rodar de novo sempre gastaria minutos de CI em falhas reais.
- P6 · **Check sem log.** Recomendação: não mandar ao agente (R9). Só o nome e o link não bastam para corrigir, e o agente tenderia a adivinhar. A pessoa abre o check e, se quiser, cola o log na sessão.
