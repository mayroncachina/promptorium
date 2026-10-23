---
id: SPEC-017
status: concluida
depende-de: []
---

# Execução de specs: menos tokens por etapa

## Objetivo

Reduzir o consumo de tokens na produção e na execução de specs sem perder a qualidade das etapas. A medição da SPEC-001 (7 etapas, Sonnet, banco do app em 2026-10-22) mostrou 81 chamadas ao modelo e **3,2 milhões de tokens relidos do cache**, contra ~5 mil de saída: quase todo o consumo é o contexto reenviado a cada chamada. As causas medidas:

- **Base fixa de ~29 mil tokens por etapa**, antes de ler qualquer arquivo, porque cada etapa abre uma sessão nova. Parte dessa base vem de plugins do usuário: o claude-mem injeta ~1,5 mil tokens de índice e 22 ferramentas MCP em toda etapa e resume as ferramentas com Haiku em segundo plano, no mesmo limite do plano.
- **Testes rodados pelo agente.** O prompt da etapa manda "rode os testes do projeto": o agente roda a suíte completa (~2,5 min) e espera em laço (`Monitor`, `sleep`, "Wait for test result"). Só a R2 fez 27 chamadas e 1,3 milhão de tokens relidos, 40% da spec.
- **Spec sem Design.** A SPEC-001 foi aprovada com `design: dispensado`; sem Design, `focusedSpecText` devolve null e cada etapa recebe a spec inteira e explora o código do zero.
- **Etapas pequenas em sessões separadas.** Com mais de `singleSessionMaxSteps` (padrão 3) requisitos, cada etapa ganha uma sessão; R5 e R7 eram mudanças de poucas linhas e cada uma pagou a base inteira.

Mockups: [Configurações › Execução de specs](../mockups/spec-017/1-configuracoes-execucao.png), [plugins: nenhum visto ainda](../mockups/spec-017/2-plugins-nenhum-visto.png) e [executar sem Design](../mockups/spec-017/3-executar-sem-design.png) (canvas: https://claude.ai/artifact/KvDHT5qfnGC63Z2GzUFwNx). Dados de exemplo; os do claude-mem são os medidos na SPEC-001.

- Fora do escopo: trocar o modelo padrão, mudar o gate (o que ele verifica) e o revisor automático.

## Requisitos

- R1 · O prompt da etapa deve mandar o agente rodar só os testes ligados às etapas da sessão (o `verificar` de cada etapa em `## Etapas` e os `verificar:` dos critérios dessas etapas; sem nenhum, os testes dos arquivos que ele mudou), em primeiro plano e sem laços de espera. Quando o gate do projeto roda testes (`testes:` no `.promptorium/config.yml`), o prompt deve dizer que a suíte completa fica com o gate; sem `testes:`, o agente roda a suíte uma vez, ao final. O prompt do "Plano pronto" (`implementPrompt`) segue a mesma regra.
- R2 · As execuções do Claude lançadas pelo app (sessões de etapa e avulsas, conversas do Prompt e execuções somente leitura como "Gerar design" e o revisor) devem desligar os plugins e os servidores MCP do usuário que ele escolher em Configurações, sem mudar o uso interativo do Claude Code fora do app.
- R3 · "Gerar design" deve escrever uma subseção "O que já existe" com os arquivos, classes e funções a reaproveitar, e cada etapa de `## Etapas` deve citar ao menos um arquivo. Ao executar no Quadro uma spec sem Design, com mais etapas que `singleSessionMaxSteps`, o sistema deve avisar o custo e oferecer "Gerar design" ou "Executar mesmo assim".
- R4 · Depois que o gate aprova as etapas de uma sessão e a spec avança sozinha, o sistema deve mandar a próxima etapa **na mesma sessão** quando o contexto atual dela estiver abaixo do limite configurado, a sessão estiver viva e ela não tiver precisado de reenvio do gate; senão, abre uma sessão nova, como hoje.
- R5 · Configurações deve expor o limite de contexto para continuar na mesma sessão (padrão 60 mil tokens; 0 desliga) e as listas de plugins e de servidores MCP das execuções do app, e cada decisão de continuar ou abrir sessão deve ficar registrada na timeline da sessão com o contexto medido e o limite.

## Design

### O que já existe
- `specStepPrompt` (`lib/features/board/spec_runner.dart`): monta o prompt da etapa; o passo "1. rode os testes do projeto[ com `$testCommand`]" é o que R1 troca. `focusedSpecText` já envia só o trecho do Design ligado às etapas quando há `## Objetivo` e `## Design`.
- `SpecDocument.stepPlans` (`lib/features/specs/spec_file.dart`): `StepPlan(files, verify)` por etapa, gerado por "Gerar design" (`designPrompt` e `designSchema` em `lib/features/specs/spec_design.dart`). `parseCriteria` dá os `verificar:` dos critérios.
- `ProjectConfig.testCommand` (`lib/features/project/project_config.dart`): o comando de testes do gate. Este repositório não define `testes:`.
- `nextSteps` (`lib/features/board/board_rules.dart`) e `RunPrefs.singleSessionMaxSteps` (`lib/core/claude/run_prefs.dart`, chave `board.singleSessionSteps`, padrão 3): agrupamento no início da spec.
- `SpecRunner._continue` / `_advance`: depois do gate, `_advance` libera a sessão (`_manager.release`) e chama `runNext`, que abre uma sessão nova. `SessionManager.send(id, text)` já manda texto a uma sessão viva (usado no reenvio do gate).
- `SessionManager._prepareHooks` grava o arquivo passado em `--settings` (`ClaudeOptions.settingsFile`), mas só para sessões e só com hooks gerenciados e Python; devolve null nos outros casos. Conversas (`conversation_manager`) e `runReadOnlyClaude` (`lib/core/claude/readonly_run.dart`) não passam `--settings`.
- `system/init` traz `plugins` (nome, `source` como `claude-mem@thedotmack`, caminho); `AgentEvent` já lê `cache_read_input_tokens` e `cache_creation_input_tokens` do `usage` de cada mensagem.
- Diálogo "A spec não tem Design" (`_approve` em `lib/features/specs/specs_screen.dart`) e `SpecDocument.designWaived`.

### R1 · Testes focados
`specStepPrompt` recebe `gateRunsTests` (`config.testCommand != null`) e a lista de comandos focados: os `stepPlans[t].verify` das etapas de `todo` e os `verificar:` dos critérios dessas etapas, sem repetir e sem os que são exatamente o `testCommand` (a suíte). O passo 1 vira:
- com comandos focados: "rode só: `cmd1`; `cmd2`" (em primeiro plano, com `timeout`, sem `sleep`/espera em segundo plano);
- sem comandos: "rode só os testes dos arquivos que você mudou ou criou";
- e então "a suíte completa (`$testCommand`) roda no gate depois do commit; não a rode" ou, sem `testes:`, "rode a suíte uma vez, ao final".

O "Plano pronto" não tem gate nem `## Etapas`: `implementPrompt` troca "rode os testes do projeto" por "rode os testes ligados ao que mudou durante o trabalho e a suíte do projeto uma vez, ao final (`$testCommand` quando houver), em primeiro plano e sem laços de espera". Ele passa a receber o `testCommand` do projeto.

Este repositório passa a ter `testes: flutter analyze && flutter test` no `.promptorium/config.yml`, para que o gate rode a suíte (hoje nenhum lado garante a suíte verde ao fim da etapa).

### R2 · Plugins e servidores MCP desligados nas execuções do app
Nova preferência `agent.disabledPlugins` (lista de ids `nome@marketplace`). Um gerador único de settings (`lib/core/claude/run_extensions.dart`) escreve o JSON com `enabledPlugins: {id: false}`, `deniedMcpServers` e, quando houver, os hooks gerenciados de hoje; `_prepareHooks` passa a usá-lo e conversas e `runReadOnlyClaude` passam `--settings` também. Sem plugin nem servidor desligado e sem hooks, nenhum arquivo é criado (comportamento atual). Os plugins conhecidos vêm do último `system/init` recebido (gravado em `agent.knownPlugins`), sem os de `source` `@builtin`.

**Servidores MCP.** Nova preferência `agent.disabledMcpServers` (nomes). Os servidores conhecidos vêm de `system/init.mcp_servers` com `source` `user`, `project` ou `claudeai` (os de plugin seguem o plugin). O mesmo arquivo de settings leva `deniedMcpServers: [{serverName: nome}]` para cada um desligado; nada de `--strict-mcp-config`, e o app não lê nem repassa a definição dos servidores (que traz o `env`, com chaves de API).

**Sonda** ([`docs/pesquisa/plugins-mcp-desligados.md`](../pesquisa/plugins-mcp-desligados.md), CLI 2.1.308): `enabledPlugins: false` num `--settings` tira o plugin, o servidor MCP e as ferramentas dele e os hooks `SessionStart`; `deniedMcpServers` tira só o servidor nomeado, mantendo os demais e os conectores do claude.ai; `--strict-mcp-config` derruba todos os servidores e mantém os hooks do plugin, por isso não é usado.

### R3 · Design que poupa exploração
`designPrompt` passa a pedir, antes das subseções por requisito, "### O que já existe": arquivos, classes e funções a reaproveitar, com caminho; e `designSchema` exige `arquivos` não vazio por etapa (`minItems: 1`). No Quadro, "Executar" (`run_spec_dialog.dart`) mostra o aviso quando `doc.design == null` e `steps.length > singleSessionMaxSteps`: "Sem Design, cada etapa recebe a spec inteira e explora o código do zero", com "Gerar design" e "Executar mesmo assim". O diálogo de aprovação continua aceitando `design: dispensado` (spec trivial); o aviso aparece só na execução.

### R4 · Continuar na mesma sessão
No `_continue`, quando `mineDone && spec.autoAdvance`, antes de `_advance`:
1. `contexto` = `input_tokens + cache_read_input_tokens + cache_creation_input_tokens` da última mensagem do assistente da sessão (o tamanho real do que vai ser reenviado). O `SessionManager` guarda esse valor por sessão ao receber cada mensagem.
2. Continua na mesma sessão quando: limite > 0, `contexto < limite`, a sessão está viva, o gate desta rodada passou na primeira tentativa (`attempts == 0`) e o provedor é Claude. Senão, `_advance` como hoje.
3. Para continuar: calcula `nextSteps` (uma etapa), marca o início (`_markStart`), acrescenta a etapa a `sessions.steps` e ao título, e manda por `send` um prompt curto, `specContinuePrompt`, com só a etapa nova, o trecho do Design e os critérios dela (`focusedSpecText` com `todo` = a etapa) e os passos "Ao terminar" de R1. A spec inteira não é reenviada: já está no contexto.

O gate e o `ETAPA CONCLUÍDA: Rn` continuam por etapa; cada etapa continua com o seu commit. Com o agrupamento inicial (`singleSessionMaxSteps`) nada muda.

### R5 · Preferências e registro
Em Configurações (`settings_screen.dart`), na seção de modelo e esforço por tipo de execução: "Continuar na mesma sessão até" (opções Desligado, 40, 60, 80 e 120 mil tokens, padrão 60; chave `board.continueContextTokens`) e "Plugins nas execuções do app" (um interruptor por plugin conhecido; ligado = carrega). Hoje `board.singleSessionSteps` não tem campo na tela, só é lido no diálogo de execução; ele ganha o campo "Etapas numa sessão só" ao lado, já que as duas preferências decidem juntas quantas sessões uma spec abre. Cada decisão de R4 vira uma `promptorium_note` na sessão: "R3 continua nesta sessão (contexto 41 mil de 60 mil)" ou "R3 vai para uma sessão nova: contexto 72 mil passou do limite de 60 mil" (ou o motivo: reenvio do gate, sessão encerrada, limite desligado).

### Riscos
- **Contexto que cresce demais.** Continuar acumula o histórico das etapas anteriores; o limite corta isso, e o `autocompact` (200k) continua valendo como teto. Por isso o padrão é baixo (60 mil) e a sessão que precisou de reenvio do gate não continua.
- **Testes focados que deixam passar uma regressão.** Com `testes:` configurado, o gate roda a suíte e devolve a falha à mesma sessão (até `verificacao.tentativas`); sem `testes:`, o agente roda a suíte uma vez, ao final.
- **Plugin desligado que o agente precisava.** A escolha é do usuário, por plugin; nada é desligado por padrão.
- **Medição sem `usage`.** Se a última mensagem não trouxer `usage` (outro provedor, erro), a decisão cai para sessão nova.

## Critérios de aceite

Os testes marcados "(a criar)" fazem parte da implementação.

- [x] [R1] Com `testes:` configurado e `verificar` nas etapas, o prompt manda rodar só esses comandos, diz que a suíte fica com o gate e não contém "rode os testes do projeto". verificar: `flutter test test/features/board/spec_runner_test.dart`
- [x] [R1] Sem `testes:` e sem `verificar`, o prompt manda rodar os testes dos arquivos mudados e a suíte uma vez, ao final; um `verificar:` igual ao `testCommand` não entra na lista focada. verificar: `flutter test test/features/board/spec_runner_test.dart`
- [x] [R1] O prompt do "Plano pronto" não contém "rode os testes do projeto", manda rodar os testes ligados ao que mudou e a suíte uma vez, ao final, e cita o `testCommand` quando houver. verificar: `flutter test test/features/prompt/plan_ready_test.dart`
- [x] [R1] Este repositório define `testes: flutter analyze && flutter test` e o gate de uma etapa roda esse comando. verificar: `flutter test test/features/board/step_gate_test.dart`
- [x] [R2] A sonda está registrada em `docs/pesquisa/plugins-mcp-desligados.md` com a versão do CLI e o resultado de `enabledPlugins: false` e `deniedMcpServers` via `--settings` (plugins, ferramentas MCP e hooks do plugin).
- [x] [R2] Com um plugin desligado, o arquivo de settings tem `enabledPlugins: {id: false}` e é passado em sessões, conversas e execuções somente leitura; sem plugin desligado e sem hooks, nenhum `--settings` é passado. verificar: `flutter test test/core/claude/run_extensions_test.dart`
- [x] [R2] Com um servidor MCP desligado, o arquivo de settings tem `deniedMcpServers: [{serverName: nome}]` e é passado em sessões, conversas e execuções somente leitura. verificar: `flutter test test/core/claude/run_extensions_test.dart`
- [x] [R2] Os plugins e os servidores MCP conhecidos vêm do último `system/init`, sem os plugins `@builtin` e sem os servidores de plugin e do app. verificar: `flutter test test/core/claude/run_extensions_test.dart`
- [x] [R3] `designPrompt` pede "O que já existe" e `designSchema` exige ao menos um arquivo por etapa. verificar: `flutter test test/features/specs/spec_design_test.dart`
- [x] [R3] Executar uma spec sem Design e com mais etapas que `singleSessionMaxSteps` mostra o aviso; "Executar mesmo assim" executa e "Gerar design" abre o design; com Design, ou com poucas etapas, não há aviso. verificar: `flutter test test/features/board/run_spec_design_test.dart`
- [x] [R4] Com o contexto abaixo do limite, gate aprovado na primeira tentativa e sessão viva, a próxima etapa vai por `send` na mesma sessão, com `specContinuePrompt` (sem a spec inteira), e `sessions.steps` passa a ter as duas etapas. verificar: `flutter test test/features/board/spec_runner_test.dart`
- [x] [R4] Acima do limite, com reenvio do gate, com a sessão encerrada, com limite 0 ou sem `usage`, a próxima etapa abre uma sessão nova, como hoje. verificar: `flutter test test/features/board/spec_runner_test.dart`
- [x] [R4] Cada etapa continuada passa pelo seu gate e tem o seu commit `SPEC-NNN Rn:`. verificar: `flutter test test/features/board/spec_runner_test.dart`
- [x] [R5] Configurações grava o limite (`board.continueContextTokens`) e os plugins desligados (`agent.disabledPlugins`); a timeline registra cada decisão com o contexto medido e o limite. verificar: `flutter test test/features/settings/settings_screen_test.dart`
- [x] [R1–R5] O código novo passa na análise estática e a suíte existente continua passando. verificar: `flutter analyze && flutter test`
- [ ] [R1–R5] Executar no app uma spec de 5 a 7 etapas com Design, claude-mem desligado e o limite padrão relê do cache bem menos que a linha de base da SPEC-001 (3,2 milhões de tokens em 7 etapas), medido pelo `usage` gravado em `session_events`. verificar: manual (executar e somar o `usage` das mensagens do assistente)

## Decisões

Respondidas em 2026-10-22:

- O limite padrão para continuar na mesma sessão é 60 mil tokens: na SPEC-001 as etapas terminaram entre 40 e 60 mil, então as pequenas continuam e as pesadas abrem sessão nova.
- O "Plano pronto" entra nesta spec (R1).
- Os servidores MCP do usuário também podem ser desligados, na mesma tela dos plugins (R2, R5).
