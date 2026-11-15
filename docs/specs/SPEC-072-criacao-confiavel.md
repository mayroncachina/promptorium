---
id: SPEC-072
status: proposta
depende-de: SPEC-071
issue: 241
---

# Criação confiável: ambiente conferido, branch, custo honesto e comandos no config.yml

## Objetivo

A tela Começar promete "1 s" e "~US$ 0,30". Na prática, criar e planejar leva de 10 a 30 min, por causa da fila de refino. Nada confere o ambiente antes de criar: a falta de nome no git, um `claude` deslogado ou uma pasta sem permissão só aparecem como erro no meio do caminho. E os comandos que a etapa Stack escreve no CLAUDE.md não chegam ao `.promptorium/config.yml`, então o gate da primeira spec roda sem `executar:` nem `dev:`.

A SPEC-071 (R21–R26) já fez a base: repetir a criação depois de uma falha, conferir a identidade do git antes de criar a pasta, `git init -b main`, specs do roadmap no Backlog, o CLAUDE.md do modelo como base do planner e a limpeza do fluxo. Esta spec fecha o resto das faixas A1, A2, A4 e B4 do relatório de novidades:

- **Checagem do ambiente** na tela Começar: git, Claude Code, GitHub e pasta, cada um com a marca e a correção ao lado. "Criar" fica desabilitado enquanto houver bloqueio.
- **Branch inicial editável**, gravada como `branch-base:` no config.yml.
- **Custo e tempo honestos**: chamadas do planner, fila em "N specs × tempo" e, no plano Max, o uso da quota em vez de dólares.
- **Comandos da stack no config.yml**, editáveis na etapa Stack e mesclados sem sobrescrever. A Saúde e "Analisar repositório" voltam ao stepper.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/MjpXpDuiv3RU1z3CL4ZeoU). Capturas em `docs/mockups/spec-072/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-antes.png` | Hoje: Começar com "1 s · ~US$ 0,30", branch fixa e nenhuma checagem | — |
| `2-ambiente.png` | O painel Ambiente com o git vermelho, os campos que gravam nome e e-mail e os botões de criar desabilitados, com o motivo | R1, R2, R3, R4, R15 |
| `3-tudo-verde.png` | Tudo verde, a branch inicial editada, o GitHub conferido e o custo honesto com o uso da quota do plano Max | R1, R5, R6, R7, R8 |
| `4-comandos.png` | A etapa Stack com o bloco Comandos, a chave do config.yml de cada um e o que já existe | R11, R12, R14 |
| `5-revisar.png` | Revisar e criar com o config.yml mesclado (linhas novas e mantidas) e a seção Custo e tempo | R9, R10, R13 |
| `6-saude.png` | O stepper com "Saúde do projeto" e a Saúde aberta, com "Analisar repositório" | R14 |

Issue: [#241](https://github.com/mayroncachina/promptorium/issues/241) (sub-issue de #240) · PR: [#244](https://github.com/mayroncachina/promptorium/pull/244)

## Requisitos

Checagem do ambiente (A2):

- R1 · **Painel Ambiente.** Em "Criar projeto novo", a coluna da direita da tela Começar ganha o bloco "Ambiente", acima de "O que acontece". São quatro itens, cada um com uma marca e uma linha do que foi achado:
  - **Git**: instalado e com nome e e-mail, pela mesma regra do `RepoSetup.checkIdentity` (`git var GIT_AUTHOR_IDENT` e `GIT_COMMITTER_IDENT`). Verde mostra "Ana Lima · ana@exemplo.com".
  - **Claude Code**: instalado, compatível e logado, pelo `providerAvailabilityProvider('claude')`. Verde mostra a versão e o plano ("2.1.300 · plano Max").
  - **GitHub**: `gh auth status`, só quando o remoto é uma URL do `github.com`. Sem remoto, a linha diz "Não se aplica: só local".
  - **Pasta**: "Criar dentro de" existe e é gravável, e o destino não existe ou é sobra de uma criação anterior (`isCreationLeftover`).
  - A marca é verde (ok), vermelha (bloqueia) ou âmbar (aviso), sempre com a palavra ao lado.
- R2 · **Quando confere.** Ao abrir "Criar projeto novo"; ao mudar o nome, a pasta ou o remoto (só os itens Pasta e GitHub, 300 ms depois da última tecla); e em "Verificar de novo".
  - Cada item roda sozinho, com limite de 5 s, e mostra "verificando…" enquanto roda.
  - Um item que passa do limite fica âmbar ("não deu para verificar") e não bloqueia.
- R3 · **A correção ao lado.** Cada item vermelho traz o que resolve:
  - git sem identidade: campos Nome e E-mail e o botão **Gravar no git**, que roda `git config --global user.name` e `user.email` e confere de novo. Os dois comandos aparecem escritos embaixo, para quem prefere o terminal;
  - git ausente: "Instale o git (`sudo apt install git`)";
  - Claude ausente: o link da instalação do Claude Code;
  - Claude deslogado: **Abrir terminal com claude auth login** (`WorktreeLauncher.terminal`). Quando a janela do app volta ao foco, o item confere de novo;
  - gh ausente ou deslogado: "Instale o gh" ou **Abrir terminal com gh auth login**;
  - Pasta: o motivo (não existe, sem permissão de escrita, o destino já tem arquivos) e **Procurar…**.
- R4 · **O que bloqueia.**
  - Git ou Pasta vermelhos desabilitam os dois botões ("Criar e planejar com o planner" e "Criar sem planejar"). Enter no nome também não cria.
  - Claude vermelho desabilita só "Criar e planejar com o planner". "Criar sem planejar" não chama o planner e segue livre.
  - GitHub é sempre aviso (âmbar): criar só grava o `origin`, e o `gh` só é usado depois, no PR.
  - Abaixo dos botões, o motivo: "Corrija 1 item do ambiente para criar".
  - O `createProject` continua conferindo a identidade (SPEC-071 R21), como rede de segurança.

Branch inicial (resto da A1):

- R5 · **Campo "Branch inicial"** na tela Começar, com `main` por padrão.
  - O nome é validado com `git check-ref-format --branch`. Um nome inválido mostra o motivo ao lado e bloqueia como a Pasta.
  - A linha "Será criada: … · branch <nome> · commit inicial" usa o valor do campo.
- R6 · **A branch vale para o repositório e para o config.yml.**
  - `RepoSetup.init` recebe a branch: `git init -b <branch>`, e o `symbolic-ref` da SPEC-071 R25 aponta para ela.
  - O config.yml ganha `branch-base: <branch>` (a chave que o `ProjectConfig` já lê), gravado antes do commit inicial, também no modelo Vazio.
  - O passo 1 do stepper mostra "git init · <branch> · commit inicial".

Custo e tempo honestos (A4):

- R7 · **"O que acontece" sem promessa falsa.** Os passos da tela Começar passam a ser:
  - "Pasta, git init e commit inicial · segundos";
  - "Proposta do planner: 3 chamadas (visão, stack e roadmap) · cada mensagem a mais na Visão é mais uma";
  - "Fila de refino: 1 rodada por spec · 1–3 min cada" (ou a mediana do histórico, R9);
  - "Revisar e criar: CLAUDE.md, config.yml, specs e Quadro".
  - Somem o "1 s" do planner e o "~US$ 0,30".
- R8 · **Quota no plano por assinatura, dólares só na API.**
  - O plano sai do `subscriptionType` do `claude auth status --json` (`pro`, `max`), lido na mesma chamada da R1.
  - No plano por assinatura, o bloco "Uso" mostra a quota do `rateLimitProvider`: janela de 5 h e semana, em barra e porcentagem, com a hora em que renova. Diz também: "No plano Max não há cobrança por chamada: o planner e a fila gastam da quota".
  - Uma janela que já renovou (`planWindowExpired`) aparece como "renovada". Sem dado ainda: "O uso aparece depois da primeira chamada".
  - Com chave de API, o bloco mostra o teto real: "até US$ 0,50 por chamada do planner, US$ 1,00 no roadmap".
  - No stepper, "Planner · US$ 0,42" vira "Planner · 4 chamadas" no plano por assinatura.
- R9 · **Estimativa da fila com histórico.**
  - Cada rodada da fila de refino (`SpecAutoPlanner`) grava quanto durou em `app_settings` (as últimas 20, de qualquer projeto).
  - Com 3 rodadas ou mais, a estimativa usa a mediana: "8 specs × ~2 min ≈ 16 min (mediana de 14 rodadas)". Com menos, "8 specs × 1–3 min ≈ 8–24 min".
  - Quando o workspace já tem specs executadas (`specMetricsProvider`), Revisar e criar mostra também a execução: "depois, ~38 min por spec (média de 6 specs deste projeto)".
- R10 · **Revisar e criar repete o bloco.** Uma seção "Custo e tempo" mostra as chamadas do planner já feitas, a fila (R9) e o uso de agora (R8). A prévia da fila em "O que acontece" ganha o tempo estimado no passo "Refina e planeja as N specs".

Comandos da stack no config.yml (B4):

- R11 · **O schema da stack ganha os comandos.**
  - `stackSchema` passa a pedir `commands: {install, run, dev, test, lint, format}`, com texto vazio quando o comando não se aplica (`dev` num app de desktop, por exemplo).
  - O prompt da stack pede os mesmos comandos que o CLAUDE.md lista e, para `install`, o comando protegido pela existência do manifesto (`test ! -f pubspec.yaml || flutter pub get`), como os modelos já fazem.
  - `StackPlan` guarda `commands` no JSON do plano. Um plano antigo, sem a chave, lê os comandos vazios.
  - Os comandos de um modelo de partida entram fixados, como as decisões fixadas, e o planner não os troca.
- R12 · **Bloco "Comandos" na etapa Stack**, abaixo das decisões, editável. Uma linha por comando, com a chave do config.yml ao lado:

  | Comando | Chave no config.yml |
  |---|---|
  | instalar | `worktree.preparar` |
  | rodar | `executar` |
  | dev | `dev` |
  | testes | `testes` |
  | lint | `lint` |
  | formatar | `formatar` |

  - Um comando que o config.yml já tem aparece com o valor de lá, só leitura, e a marca "já existe". Um comando que vai entrar tem a marca "novo"; um vazio, "não se aplica".
  - Editar um comando marca o CLAUDE.md como desatualizado, com o aviso que já existe (`claudeMdStale` e "Atualizar").
- R13 · **O materialize mescla os comandos no config.yml.**
  - Só preenche as chaves vazias, pela mesma regra do `applyDetection`. O que já existe nunca é sobrescrito.
  - `formatar` sem `{arquivo}` ganha ` {arquivo}` no fim.
  - O config.yml entra no commit "Plano inicial do projeto" e na lista de arquivos de Revisar e criar (`A` ou `M`). A linha abre e mostra o que entra (`+`) e o que ficou como estava (`=`).
- R14 · **A Saúde volta ao stepper.**
  - O stepper ganha "Saúde do projeto", junto de Configuração, Memória e Métricas. Abre a `ProjectHealthView` num diálogo, com "Analisar repositório".
  - O bloco Comandos ganha **Detectar do repositório** quando a pasta tem um manifesto (`detectStack`). A detecção preenche só as linhas vazias e diz de onde leu ("lido de pubspec.yaml").

Acessibilidade:

- R15 · Cada marca do Ambiente tem texto ("ok", "bloqueia", "aviso", "verificando…"), não só cor. A mudança de um item é anunciada ao leitor de tela. Os botões desabilitados dizem o motivo na semântica, e os campos de correção têm rótulo.

## Fora do escopo

As outras faixas do relatório de novidades ficam para specs próprias:

- B1 · Ver cada arquivo antes de gravar, gravação atômica e "Exportar plano".
- B2 · Fila de refino que sobrevive a fechar o app, "Cancelar" e "Reenviar".
- B3 · Fundação que roda (scaffold de cada modelo e a S1 "Esqueleto executável").
- B5 · Importar um repositório existente ("Abrir e analisar").
- B6 · "Criar no GitHub" e CI desde o começo. Com ela, o item GitHub da R1 passa a bloquear quando a criação no GitHub estiver marcada.
- A3 · "Pedir ajuste ao planner" e os avisos de etapa desatualizada.
- C1 · Painel de cobertura do roadmap.
- C2 · Presets de agentes, skills e MCP.

Também fica de fora a checagem do ambiente nos caminhos "Abrir pasta existente" e "Clonar de uma URL".

## Design

### O que já existe

- `lib/features/project/widgets/start_screen.dart`: `StartScreen`, `_createForm` (nome, pasta, modelo, remoto, botões), `_side` com a lista fixa "O que acontece" (onde estão o "1 s" e o "~US$ 0,30") e "Recentes".
- `lib/features/project/project_service.dart`: `ProjectService.createProject` (validação do nome, `isCreationLeftover`, `checkIdentity`, arquivos do modelo, `init`) e `materialize` (CLAUDE.md, specs, commit "Plano inicial do projeto").
- `lib/core/git/repo_setup.dart`: `RepoSetup.init`, `_initMain` (`git init -q -b main` e o `symbolic-ref` de reserva), `checkIdentity`, `isCreationLeftover`, `missingGitIdentity`.
- `lib/core/providers/provider_availability.dart`: `probeProviderAvailability` roda `claude --version`, `--help` e `auth status --json` (que traz `loggedIn` e `subscriptionType`). `providerAvailabilityProvider` guarda o resultado.
- `lib/core/git/gh_cli.dart`: `GhCli.ghAuthStatus` e `GhAuth` (instalado, logado, conta).
- `lib/core/system/worktree_launcher.dart`: `WorktreeLauncher.terminal(path, command)` abre o terminal do sistema com um comando.
- `lib/core/fs/project_paths.dart`: `defaultProjectParent` e `tildePath`.
- `lib/features/project/project_config.dart`: `ProjectConfig` já lê e grava `branch-base` (`baseBranch`), `testes`, `lint`, `formatar`, `executar` (`runCommand`), `dev` (`DevServerConfig`) e `worktree.preparar`.
- `lib/features/project/project_plan.dart`: `ProjectStep`, `StackPlan` (`decisions`, `claudeMd`, `claudeMdStale`).
- `lib/features/project/project_planner.dart`: `stackSchema`, `stackSystemPrompt`, `ProjectPlanner.budgetUsd` (0,50) e `roadmapBudgetUsd` (1,00), `proposeAll`.
- `lib/features/project/widgets/stack_step.dart`: `StackStep`, `_DecisionRow`, o aviso `claudeMdStale` e o editor do CLAUDE.md.
- `lib/features/project/widgets/create_step.dart` e `plan_queue_view.dart`: Revisar e criar, a lista de arquivos, `planQueuePreview` e `_Steps`.
- `lib/features/project/project_screen.dart`: `_Stepper` (passo fixo "Pasta e repositório", links para Configuração, Memória e Métricas, "Planner · US$"). A aba Saúde só aparece quando não há plano e a pasta já tem código; num projeto criado pelo planner ela nunca aparece.
- `lib/features/project/widgets/project_health_view.dart`: `ProjectHealthView` e `showAnalyzeDialog`. `lib/features/project/stack_detect.dart`: `detectStack`, `applyDetection`.
- `lib/features/project/spec_auto_planner.dart`: a fila de refino, que hoje não guarda a duração das rodadas.
- `lib/features/project/spec_metrics.dart`: `specMetricsProvider`, por workspace, com o tempo das sessões de cada spec.
- `lib/core/claude/usage_tracker.dart`: `rateLimitProvider` (janelas de 5 h e semana) e `planWindowExpired`. `lib/ui/shell/footer_stats.dart` já mostra esse uso no rodapé.
- `docs/guia/projeto.md`: a seção "Começar" e "Planejar com o planner".

### Componentes

- `EnvironmentCheck` (novo, `lib/features/project/environment_check.dart`): os quatro itens (`EnvItem`: estado, linha, correção), cada um com sua função de checagem e limite de 5 s. Provider por pasta e remoto. Testável com `ProcessRunner` falso.
- `EnvironmentPanel` (novo, `widgets/environment_panel.dart`): o bloco Ambiente e as correções (campos do git, botões de terminal, "Verificar de novo").
- `RepoSetup`: `init(folder, branch:)`, `setGlobalIdentity(name, email)` e `checkBranchName(name)`.
- `CostEstimate` (novo, `lib/features/project/cost_estimate.dart`): o texto de "O que acontece" e de "Custo e tempo" a partir do plano (assinatura ou API), do `rateLimitProvider`, das durações gravadas e do `specMetricsProvider`. O widget `UsageBlock` é usado na tela Começar e em Revisar e criar.
- `StackPlan.commands` (`StackCommands`: `install`, `run`, `dev`, `test`, `lint`, `format`, com os fixados) e `mergeStackCommands(ProjectConfig, StackCommands)`, que segue a regra do `applyDetection`.
- `StackStep`: o bloco `_CommandsCard`.
- `_Stepper`: o link "Saúde do projeto" e "Planner · N chamadas".

## Tarefas

| Tarefa | Requisitos | Branch |
|---|---|---|
| t1 · Ambiente e branch inicial | R1–R6, R15 | `spec/072-t1-ambiente` |
| t2 · Custo e tempo | R7–R10 | `spec/072-t2-custo` |
| t3 · Comandos e Saúde | R11–R14 | `spec/072-t3-comandos` |

A t3 também atualiza `docs/guia/projeto.md`.

## Critérios de aceite

- [ ] Cada item do Ambiente mostra verde, vermelho ou âmbar com o texto certo para git, Claude, GitHub e pasta [R1] verificar: flutter test test/features/project
- [ ] A checagem roda ao abrir, ao mudar pasta ou remoto e em "Verificar de novo", e um item lento fica âmbar sem bloquear [R2] verificar: flutter test test/features/project
- [ ] "Gravar no git" grava nome e e-mail e o item fica verde; os botões de terminal abrem o comando certo [R3] verificar: flutter test test/features/project
- [ ] Git ou pasta vermelhos desabilitam os dois botões; Claude vermelho desabilita só "Criar e planejar"; GitHub nunca bloqueia [R4] verificar: flutter test test/features/project
- [ ] Uma branch inválida bloqueia; a branch escolhida vira a branch do repositório e o `branch-base:` do config.yml [R5, R6] verificar: flutter test test/core/git test/features/project
- [ ] "O que acontece" não tem "1 s" nem "US$ 0,30" e mostra as chamadas e a fila [R7] verificar: flutter test test/features/project
- [ ] No plano por assinatura aparecem a quota e "N chamadas"; com chave de API, o teto em dólares [R8] verificar: flutter test test/features/project
- [ ] A estimativa da fila usa a mediana com 3 rodadas ou mais, e "1–3 min" sem histórico [R9] verificar: flutter test test/features/project
- [ ] Revisar e criar mostra Custo e tempo e o tempo no passo da fila [R10] verificar: flutter test test/features/project
- [ ] O plano guarda os comandos da stack; plano antigo lê vazio; comandos do modelo ficam fixados [R11] verificar: flutter test test/features/project
- [ ] O bloco Comandos mostra a chave de cada linha, trava o que o config.yml já tem e editar marca o CLAUDE.md como desatualizado [R12] verificar: flutter test test/features/project
- [ ] O materialize preenche só as chaves vazias do config.yml, acrescenta `{arquivo}` ao formatar e commita o config.yml [R13] verificar: flutter test test/features/project
- [ ] "Saúde do projeto" abre a Saúde pelo stepper, e "Detectar do repositório" preenche só as linhas vazias [R14] verificar: flutter test test/features/project
- [ ] As marcas têm texto e os botões desabilitados dizem o motivo ao leitor de tela [R15] verificar: flutter test test/features/project
- [ ] Criar um projeto de verdade num ambiente sem nome no git: o Ambiente aponta, "Gravar no git" resolve e o projeto nasce na branch escolhida, com os comandos no config.yml [R1–R6, R13] verificar: manual (app compilado, `XDG_DATA_HOME` e `HOME` isolados)
- [ ] O projeto compila e a análise estática passa [R1–R15] verificar: flutter analyze

## Decisões em aberto

- P1 · **De onde vem a estimativa da fila.** O `spec_metrics` mede a execução das specs (sessões das etapas) por workspace, e um projeto novo não tem nenhuma. A proposta (R9) grava a duração de cada rodada de refino, de qualquer projeto, e usa o `spec_metrics` só para a execução, quando o workspace tem histórico. Alternativa: usar só o `spec_metrics`, o que deixa a estimativa sempre em "1–3 min" num projeto novo. Recomendação: a proposta.
- P2 · **Claude deslogado bloqueia só "Criar e planejar".** "Criar sem planejar" não chama o modelo. Alternativa: bloquear os dois, para ninguém sair da tela sem o Claude pronto. Recomendação: bloquear só "Criar e planejar".
- P3 · **GitHub é aviso, não bloqueio.** Hoje criar só grava o `origin`; o `gh` serve depois, nos PRs. Recomendação: aviso agora, bloqueio quando a B6 trouxer "Criar no GitHub".
- P4 · **"Gravar no git" grava no `--global`.** É o que o relatório pede e o que serve para todos os projetos. Alternativa: um "Só neste projeto", gravado no repositório depois do `git init`. Recomendação: só o `--global`, com os comandos escritos embaixo.
- P5 · **`branch-base:` sempre gravado**, mesmo com `main` e no modelo Vazio, que hoje não grava config.yml. Deixa a escolha explícita para o time. Alternativa: gravar só quando for outra branch. Recomendação: sempre.
- P6 · **Como saber o plano.** O `subscriptionType` do `claude auth status --json`. Um CLI antigo sem esse campo cai no texto da API (teto em dólares). Recomendação: assim, sem perguntar à pessoa.
- P7 · **`install` sem manifesto.** Num projeto novo o manifesto ainda não existe, e `flutter pub get` falharia no preparo do worktree. A proposta pede ao planner o comando já protegido (R11), como os modelos fazem. Alternativa: o app protege sozinho pelo manifesto da stack, o que exige uma tabela de manifestos. Recomendação: pedir ao planner e mostrar o comando para a pessoa conferir.
- P8 · **Saúde como link do stepper, não como passo.** Ela não faz parte do planejamento, e o link segue o padrão de Configuração, Memória e Métricas. Recomendação: link.
