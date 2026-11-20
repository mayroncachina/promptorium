---
id: SPEC-106
status: rascunho
versao: 0.24.0
tipo: melhoria
epico: 332
depende-de: [SPEC-094, SPEC-096, SPEC-101, SPEC-102]
---

# Agentes no Codex

## Problema

Os agentes do Promptorium são arquivos `.claude/agents/<nome>.md` (`agent_file.dart`, `agent_repository.dart`). Cada um tem prompt de sistema, `model`, `effort`, `tools`, `disallowedTools`, `permissionMode`, `maxTurns` e `mcpServers`. Eles entram em quatro lugares: Nova sessão (escolher o agente), Executar spec (o agente da spec ou o do projeto, em `spec_runner.dart`), revisor automático (`spec-reviewer`, em `auto_reviewer.dart`) e subagentes da spec (`subagents_editor.dart`, enviados como `--agents`). Tudo isso é Claude: `--agent` e `--agents` são flags do Claude Code, e o Codex não tem agentes definidos em arquivo.

A decisão 7 do épico #332 deixou os agentes "só no Claude por enquanto". Isso vale para o MVP (0.22) e para a onda 2 (0.23). Nessas versões, quem escolhe o Codex perde o agente: o seletor some ou aparece "Só Claude Code".

Exemplo: o agente de projeto `flutter-dev` tem um prompt de sistema de 40 linhas (arquitetura, padrões de teste, "nunca use `setState` em telas com Riverpod"), `model: sonnet`, `tools: Read, Edit, Write, Bash, Grep, Glob` e `maxTurns: 40`. Ao executar a SPEC-120 com o Codex, a sessão começa sem nada disso, e a pessoa precisa colar o prompt à mão em cada execução.

Esta spec é o "depois" da decisão 7: o app **traduz** o agente para o que o Codex aceita numa execução e mostra com clareza o que foi aplicado, o que foi adaptado e o que foi ignorado.

## Requisitos

### A tradução

- R1 · **Prompt de sistema vira instruções do desenvolvedor.** Numa execução Codex com agente, o corpo do `.md` entra em `developerInstructions` do `thread/start`, antes das instruções que o app já manda (`appendSystemPrompt`), separado por um cabeçalho com o nome do agente. As instruções do projeto (SPEC-104) continuam chegando pelo caminho delas: o agente não as substitui.
- R2 · **Modelo pela tabela de equivalentes.** O `model` do agente (`opus`, `sonnet`, `haiku`, `fable`, `inherit` ou um id) vira um modelo do Codex por uma tabela editável (R6). Sem equivalente definido, usa o modelo do Codex escolhido para aquele tipo de execução (SPEC-094) e mostra "modelo: padrão do Codex". Um id de modelo que não existe no `model/list` nunca é enviado.
- R3 · **Esforço pelo que o modelo oferece.** `effort` (`low` … `max`) vira o esforço do Codex pela tabela da R6. O esforço enviado precisa estar na lista de esforços do modelo escolhido, que vem do `model/list`. Sem correspondência, vale o padrão do modelo, e a tela avisa.
- R4 · **Ferramentas só restringem.** `tools` e `disallowedTools` decidem o sandbox da execução, nunca acima do modo escolhido pela pessoa:
  - sem `Edit`, `Write`, `MultiEdit`, `NotebookEdit` e `Bash` (só leitura e busca): `read-only`, mesmo em Editar;
  - com qualquer uma delas: o sandbox do modo (Editar = `workspace-write` com confirmação; YOLO só em worktree, decisão 3).

  `permissionMode` do agente só vale quando é mais restritivo que o modo da execução (`plan` → só leitura). Ferramentas MCP listadas em `tools` não liberam nada no Codex (SPEC-105 R9).
- R5 · **O que não se aplica fica dito.** `maxTurns` é aplicado pelo limite de turnos do lado do app, se a SPEC-094 entregar esse limite (`turn/interrupt` ao atingir); se não, fica "ignorado no Codex". `mcpServers` do agente, `hooks`, `color` (só visual) e subagentes (`Task`/`Agent`) ficam "ignorado no Codex". Nenhum campo ignorado impede a execução.

### Onde aparece

- R6 · **Modelos equivalentes em Configurações → Provedores → Codex.** Uma tabela com uma linha por alias do Claude (`opus`, `sonnet`, `haiku`, `fable`, `inherit`) e por esforço (`low` … `max`), e um seletor alimentado pelo `model/list` (modelo) ou pelos esforços do modelo. Os valores ficam em `app_settings` (`codex.agentModel.<alias>`, `codex.agentEffort.<nível>`). Começa vazia: o app nunca fixa nome de modelo do Codex no código, porque eles mudam (risco 9 do plano técnico).
- R7 · **"No Codex" no editor do agente.** O editor (Ferramentas → Agentes) ganha um quadro "No Codex" que mostra a tradução daquele agente, campo a campo, com três estados: **aplicado** (instruções), **adaptado** ("sonnet → gpt-6.1-terra", "Read, Grep, Glob → só leitura") e **ignorado no Codex** (`maxTurns`, `mcpServers`). O quadro se atualiza enquanto a pessoa edita. Ele não grava nada novo no `.md`.
- R8 · **Nova sessão e Executar spec com o Codex.** Com o Codex como provedor, o seletor de agente volta a aparecer. Cada agente mostra um resumo ("adaptado · 2 campos ignorados"), e a dica abre o detalhe da R7. Executar spec usa a mesma tradução para o agente da spec ou do projeto (SPEC-101).
- R9 · **Subagentes da spec.** Uma spec com subagentes (`--agents`), executada com o Codex, mostra antes de começar: "Esta spec define 2 subagentes (`tester`, `docs`). No Codex eles não rodam: a sessão principal faz o trabalho deles." As opções são "Executar sem os subagentes" e "Executar com o Claude Code". A escolha vale só para aquela execução, e o provedor nunca troca no meio (decisão 4).
- R10 · **Revisor com agente.** Quando o revisor automático roda no Codex por execução estruturada (SPEC-102), o agente `spec-reviewer` passa pela mesma tradução. Se a SPEC-102 usar o `review/start` nativo, o prompt do agente entra como instruções da revisão, se o protocolo aceitar. Se não aceitar, a revisão segue sem agente, com a etiqueta "revisor nativo do Codex".
- R11 · **Registro da tradução.** Cada execução Codex com agente grava no evento `promptorium_run` (JSON versionado da SPEC-087): o nome do agente, o modelo e o esforço enviados, o sandbox e a lista de campos ignorados. Atividades, a sessão e o Replay mostram "agente `flutter-dev` · adaptado", e o detalhe vem desse registro, não do `.md` atual.
- R12 · **Nada global.** A tradução vale só para a execução, por `thread/start` e overrides. Nada é gravado no `~/.codex` e nenhum perfil do Codex é criado (`-p`). Os arquivos `.claude/agents` não mudam.

## Fora do escopo

- Multiagente nativo do Codex (`multi_agent_v2`, ferramentas `spawnAgent`/`sendInput`) e a central `codex agents`.
- Agentes só do Codex, um formato de agente próprio do Promptorium ou campos `codex-*` no frontmatter. Ver P3.
- `mcpServers` por agente no Codex.
- Trocar o agente no meio da sessão.
- Importar subagentes para o Codex com `externalAgentConfig/import`, que grava no `~/.codex`.

## Decisões em aberto

- P1 · **Tabela de modelos vazia na primeira vez.** (a) Vazia, usando o modelo do tipo de execução até a pessoa escolher; (b) sugerir pela posição no `model/list` (maior → `opus`, médio → `sonnet`, menor → `haiku`) e pedir confirmação. **Recomendação: (b) como sugestão visível, nunca aplicada sem confirmar.** Sem confirmação, vale (a).
- P2 · **`max` e `xhigh` de esforço.** O Codex vai de `low` até `ultra`, e os modelos variam. (a) Mapear para o maior esforço do modelo; (b) mapear para `high`. **Recomendação: (a)**, com o aviso de custo de cota quando o maior for `ultra`.
- P3 · **Ajuste por agente.** (a) Só a tabela global; (b) campo opcional `codex-model` no frontmatter. **Recomendação: (a).** Campos desconhecidos no `.md` podem gerar aviso no Claude Code, e a tabela resolve o caso comum.
- P4 · **Subagentes no Codex.** (a) Avisar e oferecer seguir sem eles ou trocar para o Claude; (b) bloquear. **Recomendação: (a)**, conforme a R9.
- P5 · **`Bash` sem `Edit`/`Write`.** O `Bash` pode escrever arquivos. (a) Tratar como escrita (sandbox do modo); (b) tratar como leitura. **Recomendação: (a).** Só leitura de verdade é o que o sandbox `read-only` garante.

## Design

### Arquivos tocados

- `lib/core/codex/codex_agent_mapping.dart` (novo): `AgentFile` + modo + tabela → `CodexAgentPlan{instructions, model, effort, sandbox, ignored[]}`, função pura e testável.
- `lib/core/codex/codex_provider.dart`: juntar as instruções do agente em `developerInstructions`; aplicar modelo, esforço e sandbox do plano.
- `lib/core/providers/agent_provider.dart`: o agente passa a ser intenção do app (`agent`), e não mais um extra só do Claude (SPEC-094).
- `lib/core/providers/provider_preferences.dart`: chaves `codex.agentModel.*` e `codex.agentEffort.*`.
- `lib/features/settings/providers_view.dart`: quadro "Modelos equivalentes" (R6).
- `lib/features/agents/widgets/agent_editor.dart`: quadro "No Codex" (R7).
- `lib/features/sessions/new_session_dialog.dart`, `lib/features/board/widgets/run_spec_dialog.dart`, `lib/features/board/spec_runner.dart`: seletor e aviso dos subagentes (R8, R9).
- `lib/features/review/auto_reviewer.dart`: revisor com agente no Codex (R10).
- `lib/features/context/context_tracker.dart` (evento `promptorium_run`), `lib/features/activities/`, `lib/features/sessions/replay/`: registro e exibição (R11).

### Migração

Não há. O registro vai no evento `promptorium_run`, e a tabela fica em `app_settings`.

### Dependências

- **SPEC-094 · Capacidades e opções por provedor**: o agente como intenção, as capacidades `agentFiles` e `subagents`, o limite de turnos do lado do app e o modelo e esforço por provedor.
- **SPEC-096 · Codex no Prompt e nas Sessões**: Nova sessão com o Codex e `model/list`.
- **SPEC-101 · Executar spec com o Codex**: agente da spec e do projeto, e subagentes.
- **SPEC-102 · Review automático com o Codex**: o caminho do revisor.
- Relacionadas: SPEC-104 (instruções do projeto) e SPEC-105 (`mcpServers`).

## Tarefas

- T1 · `codex_agent_mapping` com testes de tabela: cada campo do `AgentFile` × modos × tabela vazia ou cheia × modelos sem o esforço pedido.
- T2 · Adaptador e registro: instruções, modelo, esforço, sandbox e o evento `promptorium_run`. Testes com o `fake_codex`.
- T3 · Configurações (tabela de equivalentes) e editor do agente (quadro "No Codex"). Testes de widget.
- T4 · Nova sessão, Executar spec (aviso dos subagentes) e revisor. Testes de widget e um teste manual com o app isolado.

## Critérios de aceite

- [ ] O corpo do agente chega em `developerInstructions` antes das instruções do app, e as do projeto continuam carregadas [R1] verificar: payload do `thread/start` no teste do adaptador.
- [ ] Um alias sem equivalente usa o modelo do tipo de execução; um id fora do `model/list` nunca é enviado [R2] verificar: testes do `codex_agent_mapping`.
- [ ] O esforço enviado sempre está na lista do modelo [R3] verificar: testes com modelos de esforços diferentes.
- [ ] Agente só de leitura roda em `read-only` mesmo em Editar, e nenhum agente sobe o sandbox acima do modo [R4] verificar: testes de tabela do mapeamento.
- [ ] `maxTurns`, `mcpServers`, `hooks` e subagentes aparecem como "ignorado no Codex" ou aplicados pelo app, sem bloquear [R5] verificar: testes do mapeamento e de widget.
- [ ] A tabela de equivalentes lista os modelos e os esforços do `model/list`, começa sem nome fixo no código e guarda em `app_settings` [R6] verificar: teste de widget com `model/list` gravado.
- [ ] O quadro "No Codex" mostra aplicado, adaptado e ignorado e acompanha a edição, sem alterar o `.md` [R7] verificar: teste de widget do editor.
- [ ] Nova sessão e Executar spec mostram o agente com o resumo; spec com subagentes avisa antes de começar e respeita a escolha [R8, R9] verificar: testes de widget dos diálogos.
- [ ] Atividades, sessão e Replay mostram o agente e a tradução gravados na execução [R11] verificar: teste com evento gravado e `.md` alterado depois.
- [ ] Nada é gravado em `~/.codex` e nenhum perfil é criado [R12] verificar: sondagem com `HOME` temporário e argumentos do `app-server`.

## Telas

Mockup: [canvas do Claude Design](https://claude.ai/artifact/XNWSncKbMpen3gMf3fNseE). PNGs em `docs/mockups/spec-106/`. Os nomes de modelos do Codex são exemplos e, no app, vêm do `model/list`.

| PNG | O que mostra | Requisitos |
|---|---|---|
| `1-editor-no-codex.png` | Editor do agente `flutter-dev` com o quadro "No Codex": instruções aplicadas, modelo e ferramentas adaptados, `maxTurns` e `mcpServers` ignorados | R1–R5, R7 |
| `2-modelos-equivalentes.png` | Configurações → Provedores → Codex: a tabela de modelos e esforços equivalentes, com a sugestão pela posição no `model/list` esperando confirmação | R2, R3, R6 |
| `3-nova-sessao-e-subagentes.png` | Nova sessão com o Codex e o agente "adaptado · 2 campos ignorados"; o aviso de Executar spec com subagentes ("Executar sem os subagentes" / "Executar com o Claude Code") | R8, R9 |
