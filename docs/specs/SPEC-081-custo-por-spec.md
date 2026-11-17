---
id: SPEC-081
status: aprovada
versão: 0.20.0
tipo: recurso
depende-de: SPEC-076
issue: 271
---

# Custo por spec

## Objetivo

Uma spec não gasta cota numa sessão só. A SPEC-073 (Corrigir CI) passou por três etapas, duas rodadas do revisor automático, um "Corrigir CI" com duas rodadas, uma VIBE para ajustar o botão e um refinamento no Prompt antes de começar. Cada uma dessas sessões tem o seu custo, mas ele fica espalhado: o card do Quadro soma só as sessões das etapas (em US$), o revisor automático e o classificador do Orquestrador rodam `claude -p` e o custo deles não fica gravado em lugar nenhum, a VIBE e o refinamento ficam na conversa do Prompt. Para responder "quanto da minha cota essa spec comeu?", a pessoa teria de abrir cada sessão e somar de cabeça.

E o número que existe está na unidade errada. O usuário está no plano Max: não paga por chamada, paga uma assinatura e tem duas cotas, a **janela de 5 h** e a **semana**. O US$ que o CLI devolve (`total_cost_usd`) é só uma estimativa do preço da API, e "US$ 4,12" não diz se a spec gastou muito ou pouco da cota. O que importa é "essa spec comeu 1,4 janela de 5 h e 6% da semana".

Esta spec:
- passa a **registrar o consumo de cada turno** de tudo o que trabalha numa spec (etapas, revisor automático, Corrigir CI, VIBE, refinamento, classificador e decisões do Orquestrador), com a spec e a origem;
- converte o consumo em **peso na janela de 5 h e na semana**, em % e em tokens, a partir das leituras de cota que o app já recebe (`rate_limit_event` e `/usage`), como a Atividades (SPEC-076 R7) faz com as sessões vivas;
- mostra o custo **no painel da spec**, que abre com o clique que já existe no card do Quadro, com a divisão por origem e por etapa. O card perde o "US$ x" que mostra hoje e fica sem nenhum custo;
- cria um **ranking das specs que mais custaram**, em Projeto → Métricas.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/8jY976rNGUu6w2TNxAoGTr). Capturas em `docs/mockups/spec-081/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-quadro.png` | O Quadro com o card sem custo e, ao clicar numa spec rodando, o painel com a seção Cota e o peso de agora | R6, R7, R8 |
| `2-detalhe.png` | O painel da spec com a seção Cota: totais, divisão por origem, por etapa e a lista de turnos | R8, R9 |
| `3-ranking.png` | Projeto → Métricas com "Specs que mais custaram", o período e a troca de unidade | R10, R11 |
| `4-estados.png` | Sem leitura de cota ainda, chave de API (US$), histórico estimado e a lista de turnos | R3, R5, R8, R12 |

## Requisitos

### O registro

- R1 · **Um lançamento por turno.** Cada turno que termina (o evento `result`) de uma sessão, de uma conversa ou de um `claude -p` do app grava um lançamento numa tabela nova, `usage_entries`: workspace, spec (quando houver), origem, sessão ou conversa, a hora, os tokens do turno (entrada nova, escrita de cache, leitura de cache, saída) e o custo estimado do turno. O turno é a diferença entre o acumulado do `result` e o acumulado anterior da mesma sessão ou conversa, como o `recordResult` já faz com o total. Turnos sem consumo (`0` tokens) não gravam nada.
- R2 · **A origem.** Cada lançamento tem uma origem, e a spec vem dela:
  - **Etapa**: a sessão de uma etapa (`sessions.specId`, com a etapa de `sessions.steps`); um passo `REVn` conta como etapa de correção;
  - **Revisor**: o revisor automático (`auto_reviewer.dart`), por rodada;
  - **Corrigir CI**: o turno que o `CiFixer` mandou para a sessão da spec (marcado ao enviar a mensagem, não pela sessão);
  - **VIBE**: a conversa com `conversations.specId`;
  - **Refinamento**: a conversa com `refineSpecCode` (a spec pelo código no workspace);
  - **Orquestrador**: a classificação das etapas e a decisão de etapa (`step_classifier.dart`, `step_decision.dart`, `step_decision_compiler.dart`);
  - **Verificação**: a verificação da spec (`spec_verifier.dart`) e as respostas às perguntas (`spec_answers.dart`);
  - **Outros**: o que roda numa spec e não está acima (protótipo de telas, `spec_design.dart`).

  Turnos sem spec (Prompt livre, sessões soltas, Projeto, mini planejamento da Nova spec) também são gravados, com spec nula, para a soma do workspace e para a régua do R3, mas não aparecem no painel da spec nem no ranking.
- R3 · **A régua: quanto da cota vale um turno.** A cota do plano é medida pelo custo das chamadas, não pela contagem de tokens, então o custo estimado do CLI serve de peso e nunca aparece como preço. O app aprende quanto cada janela sobe por unidade de custo: a cada leitura nova da cota (`rate_limit_event` ou `/usage`) na mesma janela (mesmo `resetsAt`), ele divide a subida do uso pela soma do custo dos turnos gravados entre as duas leituras. A régua de cada janela é a **mediana das últimas 20 divisões** válidas (subida > 0 e custo > 0), guardada em `app_settings` (`quota.ruler.five_hour`, `quota.ruler.seven_day`). A mediana tira do cálculo os intervalos em que a pessoa usou o Claude fora do app (o terminal, o claude.ai), que sobem a cota sem turno gravado. Sem régua ainda (menos de 3 divisões), o app mostra só os tokens e "% depois da primeira leitura de cota".
- R4 · **O peso fica no lançamento.** Ao gravar, o lançamento recebe o peso na janela de 5 h e na semana pela régua do momento (`custo × régua`), e esse número não muda depois, mesmo que a régua mude. Um lançamento gravado sem régua recebe o peso quando a primeira régua existir.
- R5 · **O histórico de antes.** As sessões e conversas gravadas antes desta spec têm só o total (`costUsd`, `tokensIn`, `tokensOut`). Na primeira abertura depois da migração, o app lê os eventos `result` de `session_events` e `conversation_events` e cria os lançamentos com a hora de cada turno, em segundo plano e uma vez só. Os `claude -p` antigos (revisor, Orquestrador) não deixaram rastro e ficam de fora. Esses lançamentos vêm marcados como **estimados** (régua de hoje, não a do dia) e o detalhe diz "inclui histórico estimado".

### Onde aparece

- R6 · **O card fica sem custo.** O "US$ x" que o card do Quadro mostra hoje (a soma do custo das sessões, ao lado dos selos) **sai**, e o card não ganha selo, ícone, botão nem número de custo no lugar, nem gatilho novo. O custo aparece **só quando a pessoa clica no card**, com o clique (a seleção) que já existe hoje e que abre o painel da spec (R8), e ali em % da cota (R12 para a chave de API). O arrasto e o clique no robô (SPEC-076) continuam como estão (P2).
- R7 · **Ao vivo.** Com a spec rodando, a seção Cota do painel mostra também o peso da sessão viva na janela de 5 h atual, o mesmo da Atividades (SPEC-076 R7): "agora ≈ 9% · 5 h, rodando", em teal, e os números da seção se atualizam a cada turno.
- R8 · **No detalhe da spec.** O painel da spec no Quadro (`spec_steps_panel.dart`) ganha a seção **Cota**, abaixo das etapas:
  - os totais: "≈ 6% da semana", "≈ 1,4 janela de 5 h" e "1,8 M tokens" (com "+ 41 M lidos do cache" embaixo);
  - a divisão **por origem**, uma barra empilhada e a lista com o peso e a % de cada uma (Etapas, Revisor, Corrigir CI, VIBE, Refinamento, Orquestrador, Verificação, Outros);
  - a divisão **por etapa** (`R1`, `R2`, `REV1`…), com as duas cotas e os tokens;
  - "Ver turnos": a lista dos lançamentos, do mais novo ao mais antigo, com a hora, a origem, o modelo, os tokens e o peso; clicar num turno de sessão abre a sessão.
  
  O "US$" ao lado de "3/3 etapas" sai. Na tela Specs, o painel de rastro da etapa (`step_trace_panel.dart`) troca o "Custo" em US$ pelo peso da sessão.
- R9 · **A janela de 5 h de hoje.** No detalhe, quando a spec gastou na janela atual, aparece "nesta janela: ≈ 23% (renova às 14:00)", para a pessoa saber se ainda dá para mandar outra rodada antes de renovar.
- R10 · **Ranking.** Projeto → Métricas ganha, no topo, **"Specs que mais custaram"**: as 10 specs do workspace com mais peso no período, com o código, o título, a coluna, uma barra pelo peso, a % da semana, a janela de 5 h, os tokens e a origem que mais pesou. O período é **7 dias** (padrão), **30 dias** ou **Tudo**, pelos lançamentos dentro do período. Clicar numa linha abre a spec no Quadro, com o painel aberto. Um "Todos os workspaces" junta as specs dos workspaces abertos, com o nome do workspace na linha.
- R11 · **A tabela de métricas.** A coluna "Custo" (US$) de Projeto → Métricas vira "Cota (semana)", com o mesmo número do painel da spec, e o resumo do topo ("12 spec(s) · …") troca o US$ pelo peso somado.
- R12 · **Chave de API.** Sem plano (`subscriptionType` nulo, chave de API), não há cota: o painel da spec e o ranking mostram o US$ (o card continua sem custo, R6), que nesse caso é o que a pessoa paga, com "estimativa do CLI" ao lado. O detalhe mantém a divisão por origem e por etapa.
- R13 · **Formato.** Pesos com "≈" e uma casa decimal abaixo de 10% ("≈ 0,4%"), sem casa acima ("≈ 23%"); abaixo de 0,1%, "< 0,1%". Janelas acima de 100% viram "1,4 janela de 5 h". Tokens em "k" e "M" com vírgula decimal ("812 k", "1,8 M"). Estados nunca só pela cor: o "agora" em teal vem com o texto "rodando".

### Acessibilidade

- R14 · A seção Cota é anunciada pelo leitor de tela com os totais ("Cota da spec: cerca de 6,2% da semana, 1,4 janela de 5 horas, 1,8 milhão de tokens"). A barra empilhada do detalhe tem a lista ao lado com os mesmos números, e o ranking é uma tabela navegável pelo teclado (↑/↓, Enter abre).

## Fora do escopo

- Limite ou orçamento por spec (parar a spec ao passar de X%). O orçamento diário do Autopilot (`dailyBudgetUsd`) continua como está.
- Previsão de quanto uma spec ainda vai gastar.
- Gráfico do consumo ao longo do tempo por spec.
- Somar o consumo fora do app (terminal, claude.ai) a alguma spec.
- Mudar o rodapé e o cartão de cota da Atividades.
- O mini planejamento da Nova spec antes de a spec existir (o rascunho não tem spec; fica como turno sem spec).
- Exportar o ranking.

## Decisões em aberto

- P1 · **Como transformar consumo em % da cota.** (a) Repartir a subida da cota entre os turnos do app no intervalo; (b) uma régua aprendida (mediana de subida ÷ custo, R3); (c) uma tabela fixa por plano. **Decidido: (b).** A (a) joga na spec o que a pessoa gastou no terminal ao mesmo tempo. A (c) depende de números que a Anthropic não publica e que mudam. A régua se ajusta sozinha e a mediana descarta os intervalos contaminados.
- P2 · **O US$ que o card já mostra hoje.** O card mostra hoje, ao lado dos selos, o custo em US$ das sessões das etapas. **Decidido:** o "US$ x" **sai do card**, que fica sem nenhum custo, e o custo aparece só no painel lateral, em % da cota. No plano Max o US$ é a unidade errada e conta só as etapas, então ficaria diferente do número do painel.
- P2a · **O que a seção Cota destaca.** % da semana, janela de 5 h ou tokens. **Decidido: % da semana primeiro**, com a janela de 5 h ao lado e os tokens no terceiro quadro. Uma spec atravessa várias janelas de 5 h, e "140% da janela" confunde; a semana acumula, como a spec.
- P3 · **Tokens: com ou sem cache.** A leitura de cache é a maior parte dos tokens (40 M num dia) e pesa pouco na cota. **Decidido:** o número principal é entrada nova + escrita de cache + saída; a leitura de cache aparece à parte ("+ 41 M lidos do cache").
- P4 · **Onde fica o ranking.** Em Projeto → Métricas, na Atividades ou numa tela nova. **Decidido: Projeto → Métricas**, que já é a tela de "o que cada spec custou" (F14). A Atividades é do que está vivo agora.
- P5 · **Histórico de antes (R5).** Reconstruir dos eventos, mostrar só a partir de agora ou somar o total da sessão sem divisão. **Decidido: reconstruir dos eventos**, marcado como estimado. Sem isso, o ranking começa vazio e as specs já feitas, que são as que a pessoa quer comparar, ficam de fora.
- P6 · **Corrigir CI na sessão da spec.** O Corrigir CI manda a mensagem para a sessão que já existe. **Decidido:** marcar a origem no turno (o `CiFixer` avisa o `SessionManager` que o próximo turno é dele), e não abrir uma sessão nova só para separar o custo.
- P7 · **Ranking por padrão.** Só o workspace ativo ou todos. **Decidido:** o workspace ativo, com "Todos os workspaces" ao lado, como as Métricas já são por workspace.

## Design

Canvas para validar: [Custo por spec](https://claude.ai/artifact/8jY976rNGUu6w2TNxAoGTr). Quatro artboards: o Quadro com o card sem custo e o painel aberto, o detalhe da spec, o ranking e os estados.

### O que já existe

- `lib/features/activities/quota_forecast.dart` (SPEC-076): `QuotaSamples` (leituras da cota em memória) e `sessionQuotaWeights`, que dá o peso das sessões vivas como a parte delas no custo da janela vezes o uso da janela. O peso ao vivo do R7 é esse.
- `lib/features/activities/activities_state.dart`: junta o custo das sessões da janela atual para o `sessionQuotaWeights`.
- `lib/core/claude/usage_tracker.dart`: `rateLimitProvider` (a última leitura, em `app_settings`) e `UsageTracker.handle`, por onde passam todos os `rate_limit_event`. A régua (R3) se alimenta daqui e do `usage_poller.dart` (`/usage`).
- `lib/features/sessions/session_manager.dart`: o `Result` grava `recordResult` (custo acumulado e tokens). O lançamento do R1 nasce aí.
- `lib/features/prompt/conversation_manager.dart`: o mesmo para as conversas (VIBE, refinamento, Prompt).
- `lib/core/claude/readonly_run.dart`: `runReadOnlyClaude`, o `claude -p` do revisor, do Orquestrador, da verificação e do protótipo. Hoje o custo dele se perde.
- `lib/features/review/ci_fixer.dart`: envia a mensagem do Corrigir CI para a sessão da spec.
- `lib/features/board/board_screen.dart`: `SpecCardData.cost` (soma em US$ das sessões da spec), o `Text(formatCost(data.cost))` do card (que sai, R6) e o clique no card que abre o painel. `widgets/spec_steps_panel.dart`: o "3/3 etapas · US$".
- `lib/features/project/spec_metrics.dart` e `widgets/spec_metrics_view.dart` (F14): as métricas por spec, com a coluna Custo.
- `lib/features/project/widgets/usage_block.dart` e `provider_availability.dart`: o plano (`subscriptionType`) para o R12.

### Componentes

- **Tabela `usage_entries`** (migração): `id`, `workspaceId`, `specId` (nulo), `source` (`UsageSource`: etapa, revisor, ci, vibe, refino, orquestrador, verificacao, outros, livre), `step` (nulo), `sessionId` (nulo), `conversationId` (nulo), `model`, `at`, `tokensIn`, `tokensCacheWrite`, `tokensCacheRead`, `tokensOut`, `costUsd`, `fiveHourPct` (nulo), `weekPct` (nulo), `estimated`.
- **`lib/data/repos/usage_entries_repo.dart`**: `add`, `bySpec`, `byWorkspace(since)`, `pendingWeights`, `setWeights`.
- **`lib/features/cost/quota_ruler.dart`**: `QuotaRuler` (as divisões e a mediana, função pura) e `quotaRulerProvider`, alimentado pelo `UsageTracker` (R3, R4).
- **`lib/features/cost/usage_ledger.dart`**: `UsageLedger.record(...)`, chamado pelo `SessionManager`, pelo `ConversationManager` e pelo `runReadOnlyClaude` (com `specId` e `source` novos nos parâmetros) (R1, R2).
- **`lib/features/cost/spec_cost.dart`**: `SpecCost` (totais, por origem, por etapa, nesta janela) e `specCostOf(entries)` (função pura); `specCostProvider(specId)` e `specCostRankingProvider(workspace, período)` (R6–R11).
- **`lib/features/cost/usage_backfill.dart`**: a reconstrução do R5, uma vez, marcada em `app_settings`.
- **`lib/features/cost/widgets/`**: `SpecCostSection` (detalhe), `SpecCostRanking` (Métricas); `formatQuota` e `formatTokens` (R13).

### Arquivos tocados

- `lib/data/db/app_database.dart`, `migrations.dart`, `schema_versions.dart`, `app_database.g.dart` (tabela nova).
- `lib/data/providers.dart` (repo novo).
- `lib/features/sessions/session_manager.dart`, `lib/features/prompt/conversation_manager.dart`, `lib/core/claude/readonly_run.dart`, `lib/core/claude/usage_tracker.dart`, `lib/core/claude/usage_poller.dart`.
- Quem chama `runReadOnlyClaude` numa spec: `lib/features/review/auto_reviewer.dart`, `lib/features/board/orchestrator/step_classifier.dart`, `lib/features/board/step_decision.dart`, `lib/features/board/step_decision_compiler.dart`, `lib/features/specs/spec_verifier.dart`, `lib/features/specs/spec_answers.dart`, `lib/features/specs/spec_design.dart`, `lib/features/specs/prototype/prototype_service.dart`.
- `lib/features/review/ci_fixer.dart` (origem do turno, P6).
- `lib/features/board/board_screen.dart` (tirar o `Text(formatCost(data.cost))` do card, perto da linha 1957, e o `SpecCardData.cost` se mais ninguém o usar), `lib/features/board/widgets/spec_steps_panel.dart`, `lib/features/specs/widgets/step_trace_panel.dart`.
- `lib/features/project/spec_metrics.dart`, `lib/features/project/widgets/spec_metrics_view.dart`.
- `lib/features/sessions/widgets/session_style.dart` (formatos).
- Novos em `lib/features/cost/` e os testes em `test/features/cost/`.

### Migração

Sim. Uma tabela nova, `usage_entries`, na **v31** (a v30 ficou com `activity_events`, da SPEC-080). Nenhuma coluna das tabelas que existem muda. A reconstrução do histórico (R5) não é feita na migração, para não travar a abertura do app: roda depois, em segundo plano.

### Testes

- `QuotaRuler`: divisões na mesma janela, janela que renova no meio, mediana com intervalos contaminados, menos de 3 divisões → sem régua.
- `UsageLedger`: o turno é a diferença do acumulado; turno sem consumo não grava; origem e spec de cada caminho (etapa, `REVn`, revisor, CI, VIBE, refinamento pelo código, Orquestrador).
- `specCostOf`: totais, por origem, por etapa, nesta janela; lançamentos sem peso ficam só com tokens.
- Backfill: lê os `result` dos eventos, uma vez só, marca como estimado.
- Widgets: o card do Quadro não mostra custo (sem US$, selo, ícone ou botão novos); clicar no card abre o painel com a seção Cota; com sessão viva aparece o "agora"; o detalhe mostra as três divisões; o ranking ordena, filtra pelo período e abre a spec; chave de API mostra US$.

## Critérios de aceite

- [x] Cada turno de etapa, revisor, Corrigir CI, VIBE, refinamento e Orquestrador grava um lançamento com a spec e a origem certas [R1, R2] verificar: flutter test test/features/cost/usage_ledger_test.dart
- [x] A régua sai da mediana das divisões na mesma janela e ignora a janela que renovou [R3] verificar: flutter test test/features/cost/quota_ruler_test.dart
- [x] O peso fica no lançamento e um lançamento sem régua recebe o peso depois [R4] verificar: flutter test test/features/cost/usage_ledger_test.dart
- [x] O histórico de antes é reconstruído dos eventos uma vez só, marcado como estimado [R5] verificar: flutter test test/features/cost/usage_backfill_test.dart
- [x] O card do Quadro não mostra mais o US$ nem nenhum custo, e o clique que já existe nele abre o painel com a seção Cota [R6, R8] verificar: flutter test test/features/cost/spec_cost_section_test.dart
- [x] Com a spec rodando, a seção mostra "agora" com o peso na janela de 5 h atual [R7, R13, R14] verificar: flutter test test/features/cost/spec_cost_section_test.dart
- [x] O detalhe mostra os totais, a divisão por origem e por etapa, "nesta janela" e os turnos [R8, R9] verificar: flutter test test/features/cost/spec_cost_section_test.dart
- [x] O ranking lista as 10 que mais custaram no período, junta os workspaces e abre a spec [R10, R11] verificar: flutter test test/features/cost/spec_cost_ranking_test.dart
- [x] Com chave de API, o detalhe e o ranking mostram US$ com "estimativa do CLI" [R12] verificar: flutter test test/features/cost/spec_cost_section_test.dart
- [x] A migração cria `usage_entries` sem tocar nas outras tabelas [R1] verificar: flutter test test/data/migration_test.dart test/data/generated_migration_test.dart
- [ ] No app, uma spec rodada de ponta a ponta (etapas, revisor, Corrigir CI e uma VIBE) mostra no painel da spec a soma de todas as origens, e o ranking a coloca na posição certa [R1–R10] verificar: manual (app isolado com `XDG_DATA_HOME`, prints em `docs/mockups/spec-081/app/`)
- [x] O projeto compila e a análise estática passa [R1–R14] verificar: flutter analyze
