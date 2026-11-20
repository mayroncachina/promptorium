---
id: SPEC-094
status: rascunho
versao: 0.22.0
tipo: melhoria
epico: 332
issue: 334
depende-de: [SPEC-093]
---

# Capacidades e opções por provedor

## Objetivo

As telas e os serviços do app falam hoje a língua do Claude Code: montam `maxBudgetUsd`, `agent`, `settingsFile`, aliases `opus`/`sonnet` e `ClaudePermissionMode`, e cada adaptador se vira com isso. Com o Codex selecionado, o resultado é uma de duas coisas: a execução nem começa, ou começa com a opção errada.

Exemplo concreto (DT-56): com o Codex como provedor, a pessoa liga o review automático de uma etapa. O revisor monta `maxBudgetUsd: 2`, `agent: revisor` e o modelo `sonnet`, e o `CodexProvider.validateOptions` recusa:

> Codex: opções ainda sem equivalente validado: limite monetário, perfil de agente Claude. Ajuste a configuração antes de executar.

Não há o que ajustar na tela: as opções vêm do serviço, não da pessoa. No caminho contrário, a Nova sessão aplicava o modelo e o esforço do Claude ao Codex sem avisar. E há 37 comparações `== 'claude'` / `!= 'claude'` espalhadas em 15 arquivos de `lib/` decidindo, caso a caso, o que cada provedor aceita.

Esta spec troca isso por **capacidades declaradas por provedor**. Cada provedor diz o que suporta; os serviços montam só intenções do app; o adaptador traduz; e a interface mostra "Só Claude Code" (ou "Só Codex") onde a opção não se aplica, em vez de esconder ou falhar no meio (decisão 1 do épico).

## Requisitos

### Capacidades

- R1 · **`ProviderCapabilities`.** Um tipo novo em `lib/core/providers/capabilities.dart`, por provedor e modelo, com pelo menos: `images`, `structuredOutput`, `budgetUsd`, `maxTurns`, `planMode`, `readOnlyEnforced`, `managedHooks`, `agentFiles`, `subagents`, `mcpConfig`, `appMcpServer`, `compactNow`, `steerMidTurn`, `liveApprovalChange`, `quota`, `costUsd`, `nativeReview`, `revertConversation`. Cada campo é `suportado`, `parcial` (com o motivo) ou `não suportado`.
- R2 · **De onde vem.** Claude Code: valores fixos no adaptador, como o app já usa hoje. Codex: a tabela "Capacidades comprovadas no 0.170" da SPEC-093 mais o `model/list` (modalidades e esforços de cada modelo). Agentes ACP: o mínimo (sem estruturado, sem cota, sem custo) até alguém provar mais. Uma capacidade "não testada" na sondagem conta como não suportada.
- R3 · **Por fluxo.** Um registro `providerFlows` diz em quais fluxos cada provedor está liberado: Prompt, Sessões, Executar spec, Review automático, execuções estruturadas (Projeto, Gerar tarefas, Nova skill…), Comparar, Protótipo de telas. O Codex nasce com todos desligados; cada spec do épico liga o seu (a SPEC-096 liga Prompt e Sessões). O registro substitui o interruptor global `codexEnabledProvider`.

### Opções

- R4 · **Intenção + extras.** `AgentStartOptions` passa a ter só intenções do app: pasta, modo de acesso (`PromptMode` + YOLO), modelo, esforço, retomar/bifurcar, instruções adicionais, schema de saída, imagens, ambiente e MCP do app. O que é de um provedor vai para extras tipados: `ClaudeExtras` (`maxBudgetUsd`, `maxTurns`, `agent`, `agentsJson`, `settingsFile`, `tools`, regras MCP, `autocompact`) e `CodexExtras` (`sandbox`, `approval`, `writableRoots`, overrides `-c`, limite de compactação).
- R5 · **Serviços montam só o que existe.** Quem monta opções consulta as capacidades do provedor resolvido e não monta o que ele não suporta: sem `maxBudgetUsd` sem `budgetUsd`, sem `agent` sem `agentFiles`, sem `jsonSchema` sem `structuredOutput`. O `readonly_run.dart` (`runReadOnlyClaude`) já aplica isso nesta spec, sem mudar os 16 chamadores (a migração deles é da SPEC-100).
- R6 · **Falhar fechado continua.** Extras de um provedor entregues ao adaptador de outro continuam sendo erro, agora de programação (teste falha), não de uso. O adaptador nunca descarta uma opção em silêncio.
- R7 · **Modo de acesso por provedor.** Uma função por adaptador traduz o acesso (decisão 3): Perguntar e Planejar = só leitura imposta pelo runtime (`read-only` + `never` no Codex); Editar = escreve com confirmação (`workspace-write` + `on-request`); Refinar = cada edição pede aprovação; YOLO = `danger-full-access` + `never`, só em worktree. A política do Codex usa os valores que a SPEC-093 comprovou (o `untrusted` sai se tiver sumido). `permission_policy.dart` vira essa função.

### Modelo e esforço

- R8 · **Modelos por provedor.** Configurações → Consumo ganha uma aba por provedor (Claude Code, Codex). Na aba Codex, os modelos e os esforços vêm do `model/list`, lidos sob demanda e guardados com a versão e a hora da leitura ("lista lida do Codex 0.170 às 14:02 · Atualizar"). As chaves `codex.model.<tipo>` e `codex.effort.<tipo>` já existem e continuam. Um alias do Claude nunca vai para o Codex, nem o contrário.
- R9 · **Modelo que sumiu.** Um modelo salvo que não está mais no `model/list` aparece como "indisponível nesta versão" e a execução usa o padrão do provedor, dizendo isso no cabeçalho da sessão ou conversa. Nada de nomes de modelo fixos no código.

### Versão e estado

- R10 · **Versão mínima.** Na detecção, `codex --version` abaixo de 0.170 (decisão 10) deixa o provedor como **incompatível**, com "versão instalada 0.168.0, mínimo 0.170. Atualize o Codex CLI (`codex update`)". Acima da última versão testada, o provedor funciona com o aviso "versão mais nova que a testada (0.170)". A lista de métodos do App Server usados pelo app (SPEC-093 R2) é conferida contra a versão instalada quando esta mudar; um método ausente também deixa o provedor incompatível, nomeando o método.
- R11 · **Etiqueta "Só Claude Code".** Controles que dependem de uma capacidade ausente ficam desabilitados com a etiqueta "Só Claude Code" (ou "Só Codex") e uma dica com o motivo em uma linha ("O Codex não tem limite em US$"). Fluxos não liberados (R3) aparecem no seletor de provedor do fluxo como "Codex · Só Claude Code por enquanto", não somem.
- R12 · **Nunca trocar em silêncio.** Se o provedor resolvido não serve para o fluxo, a execução não começa e a tela diz o motivo antes do clique, com a opção explícita de rodar com o outro provedor. Nenhum caminho cai para o Claude sozinho.
- R13 · **Fim das comparações soltas.** As decisões de `== 'claude'` / `!= 'claude'` fora dos adaptadores e do registro passam a consultar capacidades ou `providerFlows`. Sobram comparações só em `lib/core/claude/`, `lib/core/codex/` e `lib/core/providers/`.

## Fora do escopo

- Ligar o Codex em qualquer fluxo (SPEC-096 em diante).
- Migrar os chamadores de `runReadOnlyClaude` para um `runStructured` neutro (SPEC-100).
- Limites do lado do app que substituam orçamento e turnos no Codex (tempo, número de turnos). Ver P1.
- Provedor por tipo de execução (decisão 4) na UI de Consumo: os seletores de provedor por tipo entram com a SPEC-100; aqui a aba Codex só define modelo e esforço.
- Mudar o modelo de eventos (SPEC-095) ou a cota (SPEC-097).

## Decisões em aberto

- P1 · **Orçamento e turnos no Codex.** (a) Não mandar e mostrar "Só Claude Code" no campo; (b) limite do lado do app (tempo máximo + `turn/interrupt`). **Recomendação:** (a) agora. O limite do app entra se a SPEC-101 (Executar spec com o Codex) precisar, porque é lá que um turno sem fim custa caro.
- P2 · **Onde guardar o `model/list`.** (a) `app_settings` com JSON e versão; (b) só em memória, lido a cada abertura. **Recomendação:** (a), com chave `codex.models.cache`. Abrir Configurações não pode depender do Codex responder.
- P3 · **Conferência de métodos.** (a) Rodar `generate-json-schema` a cada versão nova e guardar o resultado; (b) só comparar a versão. **Recomendação:** (a) se a SPEC-093 medir menos de 2 s; senão (b) com a lista de métodos fixa por versão testada.
- P4 · **Etiqueta.** "Só Claude Code" em lilás (cor de recursos de IA) ou âmbar. **Recomendação:** âmbar claro, mesma família dos avisos, para não parecer um recurso a mais.
- P5 · **Capacidades por modelo ou por provedor.** **Recomendação:** por provedor com sobrescrita por modelo só para `images` e esforços, que são os únicos campos que o `model/list` informa por modelo.

## Design

### O que já existe

- `lib/core/providers/agent_provider.dart`: `AgentStartOptions` com flags Claude, `PromptMode`, `AgentRun`, `ManagedAgentRun`.
- `lib/core/codex/codex_provider.dart`: `validateOptions` (falha fechado), `model/list` paginado.
- `lib/core/providers/agent_registry.dart`: `codexEnabledProvider` e `ComingSoonProvider`.
- `lib/core/providers/provider_preferences.dart`: `providerModel`/`providerEffort` com as chaves `<provedor>.model.<tipo>`.
- `lib/core/providers/permission_policy.dart`: `codexPermissionPolicy` (com o `untrusted`).
- `lib/core/providers/provider_availability.dart`: `ProviderStatus.incompatible` já existe, sem regra de versão.
- `lib/core/claude/readonly_run.dart`: repassa `maxBudgetUsd` e `agent` a qualquer provedor.
- Configurações → Consumo: modelo e esforço por tipo, só Claude.

### Arquivos tocados

| Arquivo | Mudança |
|---|---|
| `lib/core/providers/capabilities.dart` | Novo: `ProviderCapabilities`, `CapabilitySupport`, `providerFlows` |
| `lib/core/providers/run_intent.dart` | Novo: intenção, `ClaudeExtras`, `CodexExtras` |
| `lib/core/providers/agent_provider.dart` | `AgentStartOptions` = intenção + extras; `AgentProvider.capabilities` |
| `lib/core/providers/claude_code_provider.dart`, `lib/core/claude/claude_args.dart` | Traduzem intenção + `ClaudeExtras` |
| `lib/core/codex/codex_provider.dart`, `codex_command.dart` | Traduzem intenção + `CodexExtras`; `untrusted` conforme a SPEC-093 |
| `lib/core/providers/permission_policy.dart` | Acesso → política, por adaptador |
| `lib/core/providers/agent_registry.dart`, `provider_preferences.dart` | `providerFlows` no lugar de `codexEnabledProvider` |
| `lib/core/providers/provider_availability.dart`, `lib/core/codex/codex_cli.dart` | Versão mínima, última testada, métodos |
| `lib/core/claude/readonly_run.dart` | Monta só o suportado (R5) |
| `lib/features/settings/` (Consumo) | Abas por provedor, modelos do `model/list` |
| `lib/ui/widgets/only_provider_tag.dart` | Novo: etiqueta "Só Claude Code" |
| Os 15 arquivos com `== 'claude'` (R13) | Consultam capacidades ou fluxos |

**Migração do banco:** não. As preferências ficam em `app_settings` (chaves existentes + `codex.models.cache`).

### Dependências

- Depende da SPEC-093 (capacidades comprovadas, métodos usados, `untrusted`).
- Destrava a SPEC-096 (fluxos e acesso), a SPEC-097 (capacidade `quota`) e a SPEC-100 (execuções estruturadas).
- Pode correr junto da SPEC-095; as duas tocam `agent_provider.dart` em partes diferentes (opções aqui, eventos lá).

## Tarefas

| Tarefa | Entrega | Requisitos |
|---|---|---|
| T1 · Capacidades e fluxos | `capabilities.dart`, valores por provedor, `providerFlows` | R1–R3 |
| T2 · Opções | Intenção + extras, adaptadores, acesso, `readonly_run` | R4–R7 |
| T3 · Modelo, versão e etiqueta | Aba Codex em Consumo, versão mínima, "Só Claude Code", sem troca silenciosa, fim das comparações | R8–R13 |

## Critérios de aceite

- [ ] Cada provedor expõe as capacidades de R1; o Codex usa a tabela da SPEC-093 e o `model/list`, e "não testada" conta como não suportada [R1, R2] verificar: `flutter test test/core/providers/capabilities_test.dart`.
- [ ] Com o Codex, nenhum fluxo está liberado até a spec dele ligar; o interruptor global sumiu [R3] verificar: teste de `providerFlows`.
- [ ] O review automático com o Codex selecionado não monta `maxBudgetUsd` nem `agent`, e o `validateOptions` não é mais o que barra [R4–R6] verificar: teste de `readonly_run` com capacidades do Codex.
- [ ] Extras do Claude entregues ao Codex fazem um teste falhar [R6] verificar: teste do adaptador.
- [ ] Perguntar e Planejar no Codex saem como `read-only` + `never`, Editar como `workspace-write` + `on-request`, YOLO só com worktree [R7] verificar: teste da política.
- [ ] A aba Codex de Consumo lista os modelos e esforços do `model/list` guardado, com a versão e a hora; um modelo salvo que sumiu aparece como indisponível [R8, R9] verificar: teste de widget da tela Consumo.
- [ ] Codex 0.168 aparece como incompatível com a orientação; acima de 0.170 funciona com aviso; método ausente aparece nomeado [R10] verificar: teste de `inspectProvider` com versões falsas.
- [ ] Controles sem suporte mostram "Só Claude Code" com o motivo, e nenhum fluxo troca de provedor sozinho [R11, R12] verificar: testes de widget da Nova sessão e do Executar spec.
- [ ] `grep -rn "== 'claude'\|!= 'claude'" lib` só encontra adaptadores e registro [R13] verificar: o próprio grep.

## Telas

Canvas: [SPEC-094 · Capacidades e opções por provedor](https://claude.ai/artifact/HuGfpYA9AN3SBM1Hu1HhNZ)

| PNG | O que mostra | Requisitos |
|---|---|---|
| `docs/mockups/spec-094/0-antes.png` | Antes: o review automático com o Codex falha com "opções ainda sem equivalente validado", sem nada que a pessoa possa ajustar | — |
| `docs/mockups/spec-094/1-consumo-por-provedor.png` | Configurações → Consumo com as abas Claude Code e Codex: modelo e esforço por tipo vindos do `model/list`, versão e hora da leitura, e o quadro "O que o Codex faz neste app" | R1, R8, R9, R11 |
| `docs/mockups/spec-094/2-so-claude-code.png` | Nova sessão com o Codex: Agente e Orçamento desabilitados com "Só Claude Code", modelo do Codex, acesso com a política de cada modo | R5, R7, R11 |
| `docs/mockups/spec-094/3-versao-incompativel.png` | Menu do provedor no rodapé: Codex 0.168 incompatível com a orientação, e o aviso de versão mais nova que a testada; Executar spec com "Codex · Só Claude Code por enquanto" | R3, R10, R12 |
