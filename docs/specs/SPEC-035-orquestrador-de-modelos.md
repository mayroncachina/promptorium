---
id: SPEC-035
status: rascunho
depende-de: SPEC-033
---

# Orquestrador: o modelo certo para cada etapa da spec

## Objetivo

Hoje a pessoa escolhe um modelo e um esforço em "Executar", e eles valem para a spec inteira:

- renomear constantes usa o mesmo modelo que uma migração de banco;
- uma etapa simples gasta o que só uma etapa arriscada precisaria;
- uma etapa difícil, com um modelo fraco, reprova na verificação e para em "aguardando você", mesmo quando um modelo mais forte resolveria.

Esta spec cria o **Orquestrador**. Em **Automático**, ele classifica as etapas e propõe um modelo para cada uma, e a pessoa pode trocar qualquer escolha antes de executar. Se a verificação reprovar, a etapa sobe de modelo sozinha, até o limite configurado. **Manual** continua como é hoje.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/UYWjCwuzJJJJLpHuNbEZnr):

| Artboard | O que mostra | Requisitos |
|---|---|---|
| `Main.dc.html` | Hoje: um modelo para a spec inteira | — |
| `Executar.dc.html` | Automático e Manual, com o plano por etapa | R1–R5, R8 |
| `Regras.dc.html` | Regras em Configurações | R6, R7 |
| `Escalada.dc.html` | A etapa reprova e sobe de modelo | R9–R12 |
| `Estados.dc.html` | Classificando, falha, sem provedor e fim da escada | R3, R14–R16 |
| `Historico.dc.html` | Resultado por tipo de etapa | R17, R18 |

## Requisitos

- R1 · O diálogo "Executar" deve ter o seletor **Automático / Manual**:
  - abre em Manual, a não ser que "Abrir Executar em Automático" esteja ligado em Configurações;
  - Manual mostra os campos de hoje, sem mudança de comportamento;
  - Automático mostra o plano por etapa, o modo de permissão e o link "Regras em Configurações". Provedor, modelo e esforço saem do formulário, e o agente (`--agent`) da spec continua valendo.
- R2 · O Orquestrador deve classificar cada etapa aberta em um destes tipos:

  | Tipo | Quando se aplica | Modelo | Esforço |
  |---|---|---|---|
  | Mecânica | Renomear, mover, ajustar valores, sem lógica nova | Haiku | low |
  | Implementação | Tela, serviço ou regra nova, com testes | Sonnet | medium |
  | Alto risco | Migração, concorrência, segurança, arquitetura | Opus | high |
  | Documentação | Só texto: ajuda, README, changelog | Haiku | low |
  | Revisão | Revisão automática do diff (ver P1) | Codex | medium |

  - Os valores da tabela são o padrão; a pessoa pode mudar modelo e esforço em Configurações (R6).
- R3 · A classificação deve rodar numa execução somente leitura (`runReadOnlyClaude` com `--json-schema`), com o modelo escolhido em Configurações (Haiku por padrão):
  - recebe o texto da spec e as etapas; devolve, por etapa, o tipo e o motivo em uma frase;
  - começa ao abrir Automático, nunca antes;
  - fica em cache por spec e texto da etapa: reabrir "Executar" sem mudar o requisito não gasta nova execução;
  - enquanto roda, o plano mostra um skeleton com uma linha por etapa e o texto "Classificando as etapas com Haiku…", com "Usar Manual" disponível.
- R4 · Cada linha do plano deve mostrar o id da etapa, o título, o tipo e o motivo, e o modelo com o esforço num seletor:
  - trocar o seletor mostra "você escolheu" na linha;
  - a escolha da pessoa vale para aquela execução da etapa e nunca é sobrescrita pela reclassificação.
- R5 · O plano deve mostrar quantas sessões serão usadas, contando como uma só as etapas vizinhas com o mesmo provedor, modelo e esforço.
- R6 · Configurações deve ter a seção **Orquestrador**, entre "Modelo e consumo" e "Execução de specs":
  - a tabela de tipos, com modelo e esforço editáveis;
  - "Abrir Executar em Automático", desligado por padrão;
  - "Escaladas por etapa": 2 (padrão), 1 ou 0;
  - "Perguntar antes de escalar para Opus", desligado por padrão;
  - "Classificar as etapas com": Haiku (padrão) ou Sonnet;
  - "Restaurar padrão".
- R7 · As regras valem para todos os projetos e ficam em `app_settings`. Mudar uma regra não altera execuções já iniciadas.
- R8 · Em Automático, cada etapa deve rodar com o provedor, o modelo e o esforço do plano:
  - etapas vizinhas com os três valores iguais seguem na mesma sessão, respeitando o limite de contexto de hoje;
  - quando um dos três muda, a próxima etapa abre uma sessão nova, na mesma worktree;
  - a ordem das etapas não muda: o plano nunca reordena nem agrupa etapas que não são vizinhas;
  - subetapas (SPEC-033 R16) herdam o tipo da etapa-mãe; as correções `REV<n>` usam a regra Implementação.
- R9 · Quando a verificação reprovar e os reenvios automáticos (`gate.attempts`) acabarem, a etapa deve subir um degrau na escada Haiku → Sonnet → Opus:
  - cada degrau tem o esforço padrão dele: low, medium e high;
  - sobe no máximo o número de "Escaladas por etapa";
  - com 0, o comportamento é o de hoje.
- R10 · A escalada deve abrir uma sessão nova, de volta ao início da etapa (`rewind`), e passar ao modelo novo a spec, o relatório da verificação e o diff da tentativa anterior.
- R11 · O progresso da etapa deve mostrar a escada percorrida, como "Sonnet → Opus · high". A linha do tempo registra cada reprovação, reenvio e escalada.
- R12 · Com "Perguntar antes de escalar para Opus" ligado, a etapa para em "aguardando você" antes do degrau Opus, com a ação "Escalar para Opus". As opções do modal da SPEC-033 incluem essa ação.
- R13 · Etapas escaladas seguintes não herdam o modelo escalado: a próxima etapa volta ao modelo do plano.
- R14 · Se a classificação falhar, o diálogo deve mostrar o aviso e duas ações:
  - "Tentar de novo";
  - "Executar com <modelo>", que usa em todas as etapas o modelo e o esforço de Sessões em Configurações.
- R15 · Se a regra pedir um provedor indisponível, o plano deve avisar e trocar a etapa pelo modelo mais forte do provedor padrão, com o mesmo esforço, mostrando a troca na linha. O aviso oferece "Abrir Provedores".
- R16 · Ao chegar ao topo da escada ou esgotar as escaladas, a etapa fica em "aguardando você", com o relatório da última tentativa. O balão abre o modal da SPEC-033.
- R17 · A seção Orquestrador deve ter o **Histórico** por tipo de etapa, em 7, 30 ou 90 dias, com modelo, quantas passaram de primeira, quantas escalaram e o custo estimado. O texto avisa que US$ é estimativa do CLI e, no plano Max, não é cobrança.
- R18 · Quando um tipo tiver 5 ou mais etapas no período e 20% ou mais delas tiverem escalado, o Histórico deve sugerir subir o modelo ou o esforço daquela regra, com "Ver regra" e "Ignorar". "Ignorar" vale até o período ter novas escaladas.
- R19 · Sem diálogo, o Orquestrador segue a preferência:
  - com "Abrir Executar em Automático" ligado, o piloto automático e "Executar tudo" classificam e executam em Automático;
  - se a classificação falhar nesses casos, a spec roda com o modelo de Sessões e a linha do tempo registra o motivo;
  - desligado, tudo funciona como hoje.
- R20 · A comparação A/B (duelo) e "Refazer etapa" mantêm o modelo que a etapa usou por último.

## Fora do escopo

- Tipos de etapa criados pela pessoa.
- Escolher o modelo pela análise do diff já feito ou pelo tamanho do repositório.
- Escada com provedores que não sejam o Claude: Codex entra só por regra (ver P2).
- Mudar regras por projeto.
- Mudar `gate.attempts` ou a própria verificação.

## Design

### O que já existe

- `lib/features/board/widgets/run_spec_dialog.dart`: `RunSpecDialog`, com agente, modelo, esforço e modo de permissão de toda a spec.
- `lib/features/board/spec_runner.dart`:
  - `runNext` (l.615): recebe um `model` e um `effort` para a spec, e o provedor vem de `last?.provider`, então a sessão anterior trava o provedor;
  - `_advance` (l.1889): repassa `done.model` e `done.effort` à próxima etapa;
  - `_continueHere` (l.1524): mantém a etapa na mesma sessão pelo limite de contexto, só no Claude;
  - `_verify` (l.1601): reenvia à mesma sessão até `config.gate.attempts`, depois marca `needsInput`;
  - `redo` (l.1315) e `_previousAttempt` (l.1332): voltam ao início da etapa e passam a tentativa anterior ao prompt.
- `lib/features/board/board_rules.dart`: `nextSteps` (l.101) reúne todas as etapas numa sessão até `singleSessionMaxSteps`; `isReviewStep`: `REV<n>`.
- `lib/features/review/auto_reviewer.dart`: a revisão roda somente leitura com `config.reviewer.model`; o `REV<n>` é a **correção** pedida por ela, que roda como etapa comum.
- `lib/core/claude/run_prefs.dart`: `RunKind` e `RunPrefs`, em `app_settings`.
- `lib/core/claude/readonly_run.dart`: `runReadOnlyClaude`, que aceita `providerId`.
- `lib/core/providers/provider_availability.dart`: `ProviderStatus`.
- `lib/features/settings/settings_sections.dart`: `SettingsSection`.
- `spec_steps`: uma linha por etapa; `sessions`: `model`, `effort`, `provider` e `costUsd`. O schema está na versão 18.

### R1–R5 · Executar

- `RunSpecDialog` ganha o seletor e o widget `StepPlanList`.
- `lib/features/board/orchestrator/step_classifier.dart`: monta o prompt, chama `runReadOnlyClaude` e valida a resposta. Um tipo desconhecido vira Implementação.
- O cache usa o hash do texto da etapa, na coluna `plan_hash`.

### R2, R6, R7 · Regras

- `lib/features/board/orchestrator/orchestrator_rules.dart`: `StepKind`, `StepRule` e `OrchestratorPrefs`, sobre `app_settings`, como `RunPrefs`.
- Nova entrada em `SettingsSection`, com `orchestrator_view.dart`.

### R8 · Execução por etapa

- Schema 19: `spec_steps` ganha `kind`, `plan_provider`, `plan_model`, `plan_effort`, `plan_hash`, `user_picked` e `escalations`.
- `runNext` passa a ler o plano da etapa quando ele existe. O provedor do plano tem prioridade sobre `last?.provider`.
- `nextSteps` ganha um filtro que corta o grupo no primeiro plano diferente; `_continueHere` faz a mesma comparação antes de continuar.
- `_advance` deixa de repassar `done.model` quando a próxima etapa tem plano.

### R9–R13, R16 · Escalada

- `orchestrator/escalation.dart`: função pura `nextRung(current, escalations, prefs)`.
- O ramo final de `_verify` chama a escalada antes de marcar `needsInput`, reusando `rewind` e `_previousAttempt`. `gateAttempts` volta a zero a cada degrau.
- O modelo escalado fica só em `sessions.model`: `plan_model` não muda, então a próxima etapa volta ao plano (R13).

### R17, R18 · Histórico

- Nova tabela `step_runs`: spec, etapa, tipo, provedor, modelo, esforço, sessão, resultado e data, gravada a cada fim de tentativa.
- Quando uma sessão tem várias etapas, o custo dela é dividido igualmente entre as etapas, e por isso é estimativa.

### Branches

A branch pai é `spec/035-orquestrador`. Cada tarefa tem sua branch e vira um PR com base na pai.

| Tarefa | Branch | Requisitos | Depende de |
|---|---|---|---|
| T1 · Dados e regras | `spec/035-t1-regras` | R2, R7 | — |
| T2 · Configurações | `spec/035-t2-configuracoes` | R6 | T1 |
| T3 · Classificação | `spec/035-t3-classificacao` | R3, R14 | T1 |
| T4 · Diálogo Executar | `spec/035-t4-executar` | R1, R4, R5, R15 | T3 |
| T5 · Execução por etapa | `spec/035-t5-execucao` | R8, R19, R20 | T1 |
| T6 · Escalada | `spec/035-t6-escalada` | R9–R13, R16 | T5 |
| T7 · Histórico | `spec/035-t7-historico` | R17, R18 | T6, T2 |

## Critérios de aceite

- [ ] Executar abre em Manual, com os campos de hoje; com a preferência ligada, abre em Automático [R1] verificar: flutter test test/features/board/run_spec_dialog_test.dart
- [ ] A classificação devolve um tipo por etapa, e um tipo desconhecido vira Implementação [R2] [R3] verificar: flutter test test/features/board/orchestrator/step_classifier_test.dart
- [ ] Reabrir Executar sem mudar o requisito não chama nova classificação; mudar o texto chama [R3] verificar: flutter test test/features/board/orchestrator/step_classifier_test.dart
- [ ] Trocar o modelo de uma linha mostra "você escolheu" e a reclassificação não muda a escolha [R4] verificar: flutter test test/features/board/run_spec_dialog_test.dart
- [ ] O plano conta uma sessão por grupo de etapas vizinhas iguais [R5] verificar: flutter test test/features/board/run_spec_dialog_test.dart
- [ ] A seção Orquestrador edita regras, opções e "Restaurar padrão", e a mudança não altera execuções já iniciadas [R6] [R7] verificar: flutter test test/features/settings/orchestrator_view_test.dart
- [ ] Cada etapa roda com o provedor, o modelo e o esforço do plano; vizinhas iguais ficam na mesma sessão, e diferentes abrem sessão nova na mesma worktree [R8] verificar: flutter test test/features/board/spec_runner_orchestrator_test.dart
- [ ] Subetapas herdam o tipo da mãe, e `REV<n>` usa Implementação [R8] verificar: flutter test test/features/board/spec_runner_orchestrator_test.dart
- [ ] Reprovar depois dos reenvios sobe um degrau, com sessão nova no início da etapa e o relatório e o diff no prompt; com 0 escaladas, nada muda [R9] [R10] verificar: flutter test test/features/board/orchestrator/escalation_test.dart
- [ ] O progresso mostra a escada, e a linha do tempo registra reprovação, reenvio e escalada [R11] verificar: flutter test test/features/board/orchestrator/escalation_test.dart
- [ ] Com a opção ligada, a etapa pergunta antes do Opus [R12] verificar: flutter test test/features/board/orchestrator/escalation_test.dart
- [ ] A etapa seguinte a uma escalada volta ao modelo do plano [R13] verificar: flutter test test/features/board/orchestrator/escalation_test.dart
- [ ] Falha na classificação mostra "Tentar de novo" e "Executar com <modelo>" [R14] verificar: flutter test test/features/board/run_spec_dialog_test.dart
- [ ] Provedor indisponível troca a etapa pelo modelo mais forte do provedor padrão e avisa [R15] verificar: flutter test test/features/board/run_spec_dialog_test.dart
- [ ] No topo da escada, a etapa fica em "aguardando você" com o relatório da última tentativa [R16] verificar: flutter test test/features/board/orchestrator/escalation_test.dart
- [ ] O Histórico soma por tipo e período, e a sugestão só aparece com 5 etapas e 20% de escaladas [R17] [R18] verificar: flutter test test/features/settings/orchestrator_history_test.dart
- [ ] O piloto automático segue a preferência, e a falha de classificação não para a spec [R19] verificar: flutter test test/features/board/spec_runner_orchestrator_test.dart
- [ ] Duelo e "Refazer etapa" mantêm o modelo usado por último [R20] verificar: flutter test test/features/board/spec_runner_orchestrator_test.dart

## Decisões

- D1 · Manual continua sendo o padrão: Automático é uma escolha da pessoa, ligada em Configurações.
- D2 · A escalada volta ao início da etapa, em vez de continuar a tentativa que reprovou: o modelo novo recebe a tentativa como informação, não como ponto de partida.
- D3 · Mudança no canvas: a sugestão do Histórico não propõe "Crie um tipo próprio", porque tipos próprios estão fora do escopo, nem cita o motivo das escaladas, que exigiria analisar o diff.

## Perguntas em aberto

- P1 · O canvas mostra uma etapa `REV` "Revisão final do diff" rodando no Codex, mas no código a revisão não é uma etapa: ela roda pelo `auto_reviewer`, e o `REV<n>` é a correção pedida por ela. O que a regra Revisão deve controlar?
  - Sugestão: a regra Revisão controla o modelo e o provedor do `auto_reviewer`, no lugar de `config.reviewer.model`, e a revisão aparece no plano como a última linha. Assim a segunda opinião de outro provedor continua existindo, sem criar uma etapa falsa na fila. As correções `REV<n>` usam a regra Implementação.
- P2 · Uma etapa em Codex reprovou. Para qual degrau ela sobe?
  - Sugestão: Codex fica fora da escada e sobe direto para Opus · high, porque comparar a força entre provedores não é confiável.
