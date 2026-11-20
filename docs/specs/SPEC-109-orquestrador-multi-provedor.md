---
id: SPEC-109
status: rascunho
versao: 0.25.0
tipo: recurso
epico: 332
issue: 344
depende-de: [SPEC-035, SPEC-094, SPEC-097, SPEC-099, SPEC-100, SPEC-101]
---

# Orquestrador multi-provedor

## Objetivo

O Orquestrador da SPEC-035 escolhe um modelo para cada etapa da spec e sobe de modelo quando a verificação reprova, mas só usa o Claude Code. A decisão D5 deixou o Codex de fora, e o R1 diz que "Automático sempre usa o Claude Code". Com o Codex executando specs (SPEC-101), sobram dois problemas.

Exemplo: às 15h a pessoa manda a SPEC-073 (6 etapas) em Automático. A janela de 5 h do plano Max está em 92%. A R3 (Implementação, Sonnet) passa. No meio da R4, o Claude devolve o limite de uso (`rate_limit_event` rejeitado). A etapa para em "aguardando você" e fica parada até as 18h, quando a janela renova. Nesse tempo, o plano ChatGPT da pessoa está em 12% e o Codex terminaria a spec. E as etapas mecânicas (renomear, mover, ajustar textos) gastam a cota do Claude, que é a mais disputada, quando poderiam rodar num modelo leve do Codex.

Esta spec deixa o Orquestrador usar os dois provedores:
- cada **regra** por tipo de etapa escolhe **provedor**, modelo e esforço;
- a **escada** de escalada tem uma versão para cada provedor;
- quando a **cota** de um provedor acaba, ou passa de um limite configurado, a próxima etapa vai para o **outro provedor**, com o trabalho passado de forma explícita. Nunca há troca no meio de uma execução;
- o plano, a linha do tempo e o histórico mostram o provedor de cada etapa e por que ele foi usado.

Quem não liga nada continua com o comportamento de hoje: as regras padrão são todas do Claude Code e o desvio por cota vem desligado.

## Requisitos

### Regras e escada

- R1 · **Provedor nas regras.** Na seção Orquestrador de Configurações (SPEC-035 R6), cada linha da tabela de tipos passa a ter **provedor**, modelo e esforço. Os modelos do Codex vêm do `model/list` (em cache por versão do CLI) e o esforço vem dos `supportedReasoningEfforts` do modelo, nunca de uma lista fixa. O padrão continua sendo a tabela da SPEC-035, toda no Claude Code. "Restaurar padrão" volta a ela. Uma regra apontando para o Codex mostra "Codex indisponível" quando ele não está pronto (não instalado, versão abaixo de 0.170, sem login ou desligado em "Executar spec" pela SPEC-101).
- R2 · **Regra reserva por tipo.** Cada tipo ganha uma **reserva no outro provedor**, usada no desvio por cota (R5, R6). A reserva é a "mesma regra" do outro lado: Implementação no Claude Sonnet · medium tem como reserva, por exemplo, Codex `gpt-6.2-sol` · medium. A pessoa edita a reserva na mesma linha, recolhida em "Se a cota acabar". Sem reserva definida, o tipo não desvia.
- R3 · **Escada por provedor.** A escalada (SPEC-035 R9) sobe na escada do provedor da etapa:
  - Claude: Haiku → Sonnet → Opus, como hoje;
  - Codex: por padrão, **o mesmo modelo com o esforço subindo** (`low` → `medium` → `high`, e `ultra` quando o modelo oferece). Opcionalmente, uma lista de modelos ordenada pela pessoa (P2).
  
  "Perguntar antes de escalar para Opus" (SPEC-035 R12) passa a ser "Perguntar antes do degrau mais alto", valendo para as duas escadas.
- R4 · **Segunda opinião no topo.** A opção "No topo da escada, tentar o outro provedor" vem desligada. Ligada, uma etapa que reprova no último degrau do seu provedor ganha mais uma tentativa no topo da escada do outro. É uma sessão nova, de volta ao início da etapa (SPEC-035 R10), com o relatório da verificação e o diff da tentativa anterior. Ela conta como uma escalada.

### Desvio por cota

- R5 · **Cota esgotada.** Com "Desviar para o outro provedor quando a cota acabar" ligado (desligado por padrão), uma etapa que esbarra no limite do provedor segue no outro:
  - o limite é detectado pelo `rate_limit_event` rejeitado no Claude e, no Codex, pelo `rateLimitReachedType` ou pelo `ordinaryUsageAllowed = false` do `account/rateLimits` (SPEC-097);
  - a sessão que esbarrou termina, e nada troca dentro dela (decisão 4 do épico). A etapa volta ao início (`rewind`, SPEC-035 R10) e abre uma sessão nova no outro provedor com a regra reserva do tipo;
  - a sessão nova recebe o pacote de "Passar o trabalho entre agentes" (SPEC-099): a spec, as etapas feitas, o diff parcial da tentativa interrompida e o estado do git;
  - a linha do tempo registra: "Cota do Claude esgotada (janela de 5 h, renova às 18:00) · R4 seguiu no Codex · gpt-6.2-sol · medium". O card do Quadro mostra o selo do provedor.
  
  Uma tentativa interrompida pela cota não conta como reprovação nem como escalada.
- R6 · **Desvio preventivo.** A opção "Desviar antes de começar uma etapa quando a janela passar de N%" (desligada; N = 90 por padrão) consulta a cota do provedor do plano a cada **fronteira de etapa**, nunca no meio. Acima do limite, a etapa já começa no outro provedor, com a reserva, e a linha do tempo diz o porquê ("Claude · janela de 5 h em 93% ≥ 90%"). Sem leitura de cota, a etapa não desvia por esse motivo.
- R7 · **Volta ao plano.** O desvio vale até a janela renovar (`resetsAt` da cota que acabou). Depois disso, a próxima etapa volta ao provedor do plano, como a etapa seguinte a uma escalada volta ao modelo do plano (SPEC-035 R13). Uma etapa em andamento termina no provedor em que começou.
- R8 · **Os dois provedores sem cota.** Se o outro provedor também está sem cota, ou não tem reserva, ou está indisponível, a etapa para em "aguardando você" com o motivo e o horário de renovação de cada cota: "Claude renova às 18:00 · Codex renova às 16:40". As ações são "Retomar quando renovar", que agenda a retomada para o primeiro horário, "Executar agora com…" e "Usar Manual". O app nunca cai para outro provedor em silêncio.

### Executar e execução

- R9 · **Plano com provedor.** No diálogo Executar em Automático (SPEC-035 R1 e R4), cada linha mostra o selo do provedor antes do modelo ("Codex · gpt-6-luna · low"), e o seletor da linha permite trocar o provedor. "Automático sempre usa o Claude Code" deixa de valer. O cabeçalho do plano mostra a cota dos provedores usados ("Claude · 5 h em 62% · Codex · 5 h em 18%"). A contagem de sessões (SPEC-035 R5) conta uma sessão nova sempre que o provedor muda. Uma linha com o Codex indisponível mostra o aviso e a ação explícita "Usar a regra do Claude nestas etapas".
- R10 · **Mesma worktree, provedores alternados.** Etapas de provedores diferentes rodam na mesma worktree da spec, em sessões separadas. Etapas vizinhas com o mesmo provedor, modelo e esforço continuam na mesma sessão (SPEC-035 R8). A sessão do Codex recebe os *writable roots* do worktree (SPEC-101), e os commits levam o agente certo no `PROMPTORIUM_AGENTE` (SPEC-048). O agente `--agent` da spec só vale no Claude (decisão 7 do épico); numa etapa Codex, o plano mostra "agente só no Claude".
- R11 · **Classificação e revisão.** "Classificar as etapas com" aceita também um modelo do Codex. A classificação passa a usar a execução estruturada neutra (`runStructured`, SPEC-100), com o mesmo cache por texto da etapa. A regra Revisão pode apontar para o Codex, e aí a revisão automática usa o revisor do Codex (SPEC-102).
- R12 · **Piloto automático.** O piloto e "Executar tudo" (SPEC-035 R19) seguem as mesmas regras de provedor, reserva e desvio. Com "Pausar automáticos" (SPEC-076 R8) ligado, nada é desviado nem agendado.

### Histórico

- R13 · **Histórico por provedor.** O Histórico do Orquestrador (SPEC-035 R17) agrupa por tipo de etapa **e** provedor/modelo e mostra quantas passaram de primeira, quantas escalaram, quantas **desviaram por cota** e os tokens (entrada → saída). O custo em US$ some para as linhas do Codex (decisão 5 do épico). Nas linhas do Claude, ele fica como "estimativa do CLI", como hoje. A sugestão da SPEC-035 R18 continua valendo por tipo e provedor.
- R14 · **Acessibilidade.** O selo do provedor tem texto, além da cor. A linha do tempo e o leitor de tela anunciam o motivo do desvio ("R4 desviada para o Codex: cota do Claude esgotada, renova às 18 horas").

## Fora do escopo

- Trocar de provedor no meio de uma sessão ou de uma etapa em andamento.
- Escolher o provedor pela análise do diff, pelo tamanho do repositório ou por quem "ganhou" no Histórico.
- Converter a cota de um provedor na do outro ou estimar US$ para o Codex.
- Regras por projeto (como na SPEC-035).
- Agentes `.claude/agents` nas etapas do Codex.
- Desvio por cota fora do Orquestrador (Sessões soltas, Prompt). Isso cabe em "Passar o trabalho entre agentes" (SPEC-099).

## Decisões em aberto

- P1 · **Onde guardar o provedor do plano.** (a) Nova coluna `spec_steps.plan_provider` (nula = Claude), com `step_runs.provider`, `tokens_in`, `tokens_out` e `diverted`; (b) codificar no texto do modelo (`codex:gpt-6.2-sol`). **Recomendação: (a).** Fica explícito, os dados antigos continuam válidos (nulo = Claude) e o Histórico consegue agrupar sem fazer parse de texto. Precisa de migração.
- P2 · **Escada do Codex.** (a) O mesmo modelo, subindo o esforço; (b) uma lista de modelos ordenada pela pessoa; (c) ordenar pelo `model/list`. **Recomendação: (a) como padrão, com (b) editável.** O `model/list` não diz qual modelo é "mais forte", e os nomes mudam a cada versão. Subir o esforço é estável e o próprio catálogo diz quais níveis existem.
- P3 · **Segunda opinião no topo da escada.** **Recomendação: desligada por padrão.** Ela gasta a cota dos dois provedores numa etapa só. Quem quer usa a opção.
- P4 · **Etapa interrompida pela cota.** (a) Volta ao início da etapa no outro provedor; (b) continua do ponto em que parou, com o diff parcial. **Recomendação: (a)**, como a escalada (SPEC-035 D2). O diff parcial vai no pacote como informação, não como ponto de partida, e o rewind deixa a worktree coerente.
- P5 · **"Retomar quando renovar".** **Recomendação: entrar**, agendado para o primeiro `resetsAt` conhecido e cancelado se a pessoa agir antes. Sem isso, a etapa para fora do horário e fica parada até alguém ver.
- P6 · **Padrão das reservas.** **Recomendação:** preencher a reserva do Codex com o modelo padrão do Codex para "Executar spec" (SPEC-094) e o esforço da regra. O desvio continua desligado até a pessoa ligar, então nada roda no Codex sem uma escolha explícita.

## Design

### O que já existe

- `lib/features/board/orchestrator/orchestrator_rules.dart`: `StepKind`, `StepRule(model, effort)`, `OrchestratorPrefs` (`app_settings`, chaves `orchestrator.*`), `orchestratorModels` só com o Claude.
- `lib/features/board/orchestrator/escalation.dart`: `escalationLadder` fixa (Haiku, Sonnet, Opus), `nextRung`, `escalationStopReason`, `escalationTrail`.
- `lib/features/board/orchestrator/step_classifier.dart` (`runReadOnlyClaude`), `step_plan.dart`, `step_plan_list.dart`.
- `lib/features/board/spec_runner.dart`: `runNext` (o provedor vem de `last?.provider`; com plano, sempre `claude`), `_verify`, `rewind`, `_previousAttempt`, `_continueHere`.
- `lib/features/board/widgets/run_spec_dialog.dart`, `lib/features/settings/` (seção Orquestrador e Histórico).
- `lib/data/db/app_database.dart`: `spec_steps` (`planModel`, `planEffort`, `kind`, `escalations`…) e `step_runs` (sem provedor nem tokens).
- `lib/features/sessions/session_manager.dart`: `case RateLimit()` encaminha ao `usageTracker`. `lib/features/activities/automation_pause.dart`: "Pausar automáticos".

### Componentes

- `StepRule` ganha `provider` (padrão `claude`). `OrchestratorPrefs` ganha `fallback(kind)`, `divertOnQuota`, `divertAbovePercent`, `secondOpinion` e `codexLadder`.
- `escalation.dart`: `ladderFor(provider, prefs)`. `nextRung` sobe na escada do provedor da etapa e, com a segunda opinião, devolve o topo do outro provedor.
- `orchestrator/quota_divert.dart` (novo): função pura `divertFor(step, quotas, prefs, now)`, que devolve a regra a usar e o motivo (cota esgotada, limite preventivo, renovação), ou "aguardar" com os horários de renovação. Ela lê o `QuotaSource` neutro da SPEC-097.
- `spec_runner.dart`: na fronteira de etapa, chama `divertFor`. Quando a sessão termina por limite de cota, faz rewind e abre a sessão no outro provedor com o pacote da SPEC-099. Grava o motivo na linha do tempo. Agenda "Retomar quando renovar" (R8).
- `run_spec_dialog.dart` / `step_plan_list.dart`: selo e seletor de provedor, cabeçalho com as cotas, contagem de sessões por provedor.
- `step_classifier.dart`: troca `runReadOnlyClaude` por `runStructured` (SPEC-100).
- Configurações: tabela com provedor e reserva, escada do Codex e as opções de desvio. O Histórico agrupa por provedor e mostra tokens.

### Migração

**Sim** (P1): `spec_steps.plan_provider` (texto, nulo = `claude`); `step_runs.provider` (texto, padrão `claude`), `tokens_in`, `tokens_out` (inteiros, nulos) e `diverted` (texto, nulo, ou `quota`/`threshold`/`second_opinion`). Fica na próxima versão livre do schema na hora da implementação (hoje é a 33). As preferências novas ficam em `app_settings`, sem migração.

### Dependências

- SPEC-035 (Orquestrador), base desta spec.
- SPEC-094 (capacidades e opções por provedor): modelo e esforço por provedor, versão mínima.
- SPEC-097 (cota do Codex no rodapé): leitura de cota e `resetsAt` dos dois provedores.
- SPEC-099 (passar o trabalho entre agentes): o pacote da troca de provedor.
- SPEC-100 (execuções estruturadas em qualquer provedor): classificação no Codex.
- SPEC-101 (executar spec com o Codex): etapas, gates e commits no Codex.
- SPEC-102 (review automático com o Codex): só para a regra Revisão no Codex.

### Arquivos tocados

- `lib/features/board/orchestrator/` (`orchestrator_rules.dart`, `escalation.dart`, `step_classifier.dart`, `step_plan.dart`, `step_plan_list.dart`, `quota_divert.dart` novo)
- `lib/features/board/spec_runner.dart`, `autopilot.dart`, `widgets/run_spec_dialog.dart`, `board_screen.dart` (selo no card)
- `lib/features/settings/` (seção Orquestrador e Histórico)
- `lib/data/db/app_database.dart`, `schema_versions.dart`, `lib/data/repos/` de passos e de `step_runs`
- `test/features/board/orchestrator/`, `test/features/board/spec_runner_orchestrator_test.dart`, `test/features/settings/orchestrator_*`

## Tarefas

- T1 · Dados e regras: migração, `StepRule.provider`, reservas, escada do Codex e preferências [R1–R3, R13 (dados)].
- T2 · Desvio: `divertFor`, detecção de limite nos dois provedores, rewind + pacote, volta ao plano, "aguardando você" com renovações e retomada agendada [R5–R8, R12].
- T3 · Executar e Configurações: selo e seletor no plano, cotas no cabeçalho, tabela com reserva, opções de desvio e segunda opinião [R1, R2, R4, R9, R14].
- T4 · Execução por provedor: sessões por provedor na mesma worktree, classificação por `runStructured`, Revisão no Codex [R10, R11].
- T5 · Histórico por provedor com tokens e desvios [R13].
- T6 · e2e no app isolado com `fake_codex` e uma cota simulada esgotando no meio da spec [R5–R10].

## Critérios de aceite

- [ ] Cada regra escolhe provedor, modelo e esforço; os modelos do Codex vêm do `model/list`; o padrão continua todo no Claude [R1] verificar: flutter test test/features/settings/orchestrator_view_test.dart
- [ ] Cada tipo tem uma reserva no outro provedor, e um tipo sem reserva não desvia [R2] verificar: flutter test test/features/board/orchestrator/quota_divert_test.dart
- [ ] A escalada sobe na escada do provedor da etapa; no Codex, por padrão, sobe o esforço [R3] verificar: flutter test test/features/board/orchestrator/escalation_test.dart
- [ ] Com a segunda opinião ligada, o topo de um provedor tenta o topo do outro, e isso conta como uma escalada [R4] verificar: flutter test test/features/board/orchestrator/escalation_test.dart
- [ ] Um limite de cota termina a sessão, volta ao início da etapa e abre uma sessão no outro provedor com o pacote; isso não conta como reprovação [R5] verificar: flutter test test/features/board/spec_runner_orchestrator_test.dart
- [ ] O desvio preventivo só olha a cota na fronteira de etapa e não desvia sem leitura [R6] verificar: flutter test test/features/board/orchestrator/quota_divert_test.dart
- [ ] Depois do `resetsAt`, a próxima etapa volta ao provedor do plano [R7] verificar: flutter test test/features/board/orchestrator/quota_divert_test.dart
- [ ] Sem cota nos dois provedores, a etapa espera com os horários de renovação e as três ações, sem cair em silêncio para outro provedor [R8] verificar: flutter test test/features/board/spec_runner_orchestrator_test.dart
- [ ] O plano mostra o provedor por etapa, as cotas no cabeçalho e uma sessão nova a cada troca de provedor [R9] verificar: flutter test test/features/board/run_spec_dialog_test.dart
- [ ] Etapas de provedores diferentes rodam na mesma worktree, com os commits marcados com o agente certo [R10] verificar: flutter test test/features/board/spec_runner_orchestrator_test.dart
- [ ] A classificação roda no modelo escolhido, inclusive no Codex, e mantém o cache [R11] verificar: flutter test test/features/board/orchestrator/step_classifier_test.dart
- [ ] O piloto segue as mesmas regras, e "Pausar automáticos" impede desvios e agendamentos [R12] verificar: flutter test test/features/board/autopilot_test.dart
- [ ] O Histórico agrupa por tipo e provedor, conta os desvios e mostra tokens, sem US$ no Codex [R13] verificar: flutter test test/features/settings/orchestrator_history_test.dart
- [ ] No app isolado, uma spec em Automático com a cota do Claude esgotando na R4 segue no Codex e volta ao Claude depois da renovação [R5–R10] verificar: manual (xdotool, `XDG_DATA_HOME`, `fake_codex`, prints em `docs/mockups/spec-109/app/`)
- [ ] O projeto compila, a migração tem teste e a análise estática passa [R1–R14] verificar: flutter analyze e flutter test test/data/migration_test.dart

## Telas

Mockup: [canvas do Claude Design](https://claude.ai/artifact/6eD6puW5gbjEXZqqXRD3tA). Capturas em `docs/mockups/spec-109/` (1366×768):

| PNG | O que mostra | Requisitos |
|---|---|---|
| `0-antes.png` | Hoje: a R4 parada em "aguardando você" porque a cota do Claude acabou, com o Codex ocioso | — |
| `1-executar-plano.png` | Executar em Automático: selo do provedor por etapa, mecânicas no Codex, cotas dos dois provedores no cabeçalho e a contagem de sessões | R9, R10 |
| `2-regras.png` | Configurações › Orquestrador: provedor por tipo, reserva "Se a cota acabar", escada do Codex por esforço, desvio por cota, desvio preventivo e segunda opinião | R1–R4, R6 |
| `3-desvio-cota.png` | Linha do tempo da spec: a R4 interrompida pela cota do Claude, desviada para o Codex com o pacote e a volta ao Claude depois da renovação; o card do Quadro com o selo | R5, R7, R14 |
| `4-estados.png` | Os dois provedores sem cota com os horários e "Retomar quando renovar", o Codex indisponível no plano e o Histórico por provedor com desvios e tokens | R8, R9, R13 |
