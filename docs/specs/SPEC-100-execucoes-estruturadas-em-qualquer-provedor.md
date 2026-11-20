---
id: SPEC-100
status: rascunho
versao: 0.23.0
tipo: melhoria
epico: 332
issue: 345
depende-de: [SPEC-093, SPEC-094, SPEC-095, SPEC-097]
---

# Execuções estruturadas em qualquer provedor

## Objetivo

Fazer o planner e os assistentes de spec rodarem no Codex, além do Claude Code: Projeto, Nova spec, Dividir em specs, Perguntas e respostas da spec, Design da spec, Verificar spec, Nova skill, Stack própria e Decidir na etapa. Todos são **execuções estruturadas**: uma rodada somente leitura que devolve um JSON validado por um schema. Hoje elas passam por `runReadOnlyClaude` (`lib/core/claude/readonly_run.dart`), que monta opções do Claude Code mesmo quando o provedor é outro.

Esta spec troca essa função por um `runStructured` neutro e deixa a pessoa escolher o provedor **por tipo de execução** em Configurações → Modelo e consumo (decisão 4 do épico #332). Nesta entrega, o tipo é "Planner e assistentes". O Revisor ([SPEC-102](SPEC-102-review-automatico-com-o-codex.md)) e Executar spec ([SPEC-101](SPEC-101-executar-spec-com-o-codex.md)) usam a mesma infraestrutura.

### O problema, com um exemplo

Na 0.22, a pessoa troca o rodapé para **Codex** e conversa no Prompt com o Codex. Depois ela abre **Nova spec**, cola um print e pede "tela de cupons com filtro por validade". Hoje acontece uma destas três coisas:

1. A execução sai pelo ramo `chosen != 'claude'` de `runReadOnlyClaude` e leva `maxBudgetUsd: ProjectPlanner.budgetUsd`. O `CodexProvider.validateOptions` recusa a opção e o diálogo mostra "Falha ao iniciar codex: …" (o bloqueio do DT-56).
2. Num chamador que fixa `providerId: 'claude'` (Stack própria, checagem da VIBE, Protótipo), a execução vai para o Claude Code em silêncio, e a cota gasta é a do Claude.
3. O revisor e a checagem da VIBE mandam `model: 'haiku'`, que não existe no Codex.

Depois desta spec, a mesma Nova spec roda no Codex com `gpt-6.1-terra` (o modelo vem do `model/list`). O schema vai como `outputSchema` e o sandbox é `read-only`. O print segue como imagem quando o modelo tem a modalidade. O diálogo mostra "Codex · gpt-6.1-terra · 14,2 mil tokens · custo indisponível". O que o Codex não faz, como o Protótipo de telas, aparece com a etiqueta **Só Claude Code**, e o motivo fica visível.

## Requisitos

### Execução neutra

- R1 · **`runStructured` substitui `runReadOnlyClaude`.** Uma função neutra em `lib/core/providers/structured_run.dart` recebe a **intenção** da execução: cwd, prompt, schema, instruções de sistema, imagens, modelo e esforço do tipo, retomada ou continuação, tempo-limite, cancelamento e origem do uso (spec, fonte, etapa). Ela devolve um `StructuredResult` com os dados validados, o provedor, o modelo efetivo, o uso em tokens, o custo (quando o provedor informa) e o id externo da rodada. Os 15 chamadores atuais de `runReadOnlyClaude` e o `stepClassifierRunProvider` passam a chamar `runStructured`. Nenhum serviço de feature monta `ClaudeOptions` para uma execução estruturada. As opções exclusivas de um provedor vão como extras dele: no Claude, `maxBudgetUsd`, `agent`, `tools` e `settingsFile`. Cada adaptador recebe só os extras do seu provedor, conforme as capacidades da SPEC-094.
- R2 · **Somente leitura garantida nos dois provedores.** No Claude, continua como hoje (`--tools` de leitura, `--disallowedTools`, MCP desligado, pedidos de permissão negados com a mensagem do chamador). No Codex, a rodada usa sandbox `read-only`, aprovação `never` e `-c mcp_servers={}`. Um pedido de aprovação que chegue mesmo assim é negado com a mesma mensagem. Nenhuma execução estruturada escreve no repositório, em nenhum provedor. A exceção é o Protótipo (R8), que não roda no Codex.
- R3 · **Schema no Codex.** O schema vai em `turn/start.outputSchema`. A resposta é a última mensagem do agente, lida como JSON e validada contra o mesmo schema antes de chegar ao serviço. Se o JSON vier inválido ou incompleto, o erro é o mesmo de hoje ("O planner não devolveu …"), com o provedor no texto, e a resposta crua fica no log de depuração, já sanitizada. Os schemas atuais precisam passar nas restrições do `outputSchema` registradas pela sondagem da SPEC-093. Se um schema tiver campos opcionais que o Codex não aceita, ele ganha uma variante compatível (campo obrigatório que aceita nulo), e o serviço trata o nulo como ausente.
- R4 · **Instruções, modelo e esforço por provedor.** O `appendSystemPrompt` vira `developerInstructions` no `thread/start` do Codex. O modelo e o esforço vêm do tipo de execução e do provedor (`<provedor>.model.planner`, `<provedor>.effort.planner`, já existentes em `provider_preferences.dart`, com a interface da SPEC-094). Um alias do Claude (`haiku`, `sonnet`, `opus`) passado por um chamador nunca chega ao Codex: o adaptador usa o modelo do tipo, e vice-versa. Os chamadores que hoje fixam modelo, como a checagem da VIBE com `haiku · low`, passam a pedir um **perfil** ("rápido") em vez de um nome. Cada provedor resolve o perfil pelo próprio catálogo.
- R5 · **Limite sem orçamento em US$.** No Codex não há `--max-budget-usd` nem `--max-turns` (capacidades `budgetUsd` e `maxTurns` falsas). O limite passa a ser o tempo-limite que cada chamador já tem (5 min no planner, 10 min no revisor). Ao estourar, o app manda `turn/interrupt` e encerra o processo. Cancelar a rodada (por exemplo, fechar o diálogo da Nova spec) também manda `turn/interrupt`, e o resultado conta como **cancelado**, não como falha. No Claude, o orçamento continua como hoje.
- R6 · **Imagens.** Os prints da Nova spec (SPEC-083) vão para o Codex como entrada de imagem, no formato que a SPEC-093 comprovar (data URL ou arquivo local). Se o modelo escolhido não tiver a modalidade `image` no `model/list`, o diálogo avisa antes de enviar: "O modelo gpt-6-luna do Codex não lê imagens". Ele oferece "Enviar sem os prints" e "Usar o Claude Code desta vez". O app nunca descarta os prints sem avisar.
- R7 · **Retomada no mesmo provedor.** As execuções que continuam uma rodada anterior (refinar o plano do Projeto, refinar a Nova spec) usam o provedor e a thread da rodada original (`agent.run.<id>.provider` e `agent.run.<id>.externalId`), mesmo que o tipo tenha mudado de provedor depois. O diálogo diz "Continua no Claude Code, onde o plano começou". Trocar de provedor no meio de uma execução não acontece (decisão 4). Para trocar, a pessoa começa uma rodada nova.

### Escolha do provedor por tipo

- R8 · **Cobertura por fluxo.** Esta spec libera o Codex para os fluxos abaixo. Os demais aparecem como **Só Claude Code** quando o tipo está no Codex (decisão 1):

  | Fluxo | Arquivo | No Codex |
  |---|---|---|
  | Projeto (planner), refinar plano | `project/project_planner.dart` | sim |
  | Stack própria | `project/custom_stack.dart` | sim (sai o `providerId: 'claude'` fixo) |
  | Nova spec, com prints | `specs/spec_planner.dart` | sim (R6) |
  | Dividir em specs | `prompt/split_specs.dart` | sim |
  | Perguntas e respostas da spec | `specs/spec_answers.dart` | sim |
  | Design da spec | `specs/spec_design.dart` | sim |
  | Verificar spec | `specs/spec_verifier.dart` | sim |
  | Nova skill | `skills/skill_writer.dart` | sim (a skill gerada continua no formato `.claude/skills`) |
  | Decidir na etapa e compilar a decisão (SPEC-033) | `board/step_decision*.dart` | sim |
  | Checagem de outro assunto da VIBE | `vibe/vibe_guard.dart` | segue o provedor da conversa VIBE, com o perfil "rápido" (R4) |
  | Protótipo de telas (SPEC-022) | `specs/prototype/prototype_service.dart` | **Só Claude Code**: escreve numa pasta por regras de ferramenta, que o Codex não tem (P1) |
  | Classificador do Orquestrador (SPEC-035) | `board/orchestrator/step_classifier.dart` | **Só Claude Code** até a SPEC-109 (Orquestrador multi-provedor) |
  | Revisor automático | `review/auto_reviewer.dart` | migra para `runStructured` aqui, mas continua no Claude até a SPEC-102 |

- R9 · **Provedor por tipo de execução.** Configurações → Modelo e consumo ganha o cartão **Provedor por tipo**, com uma linha por tipo e três opções: **Seguir o rodapé** (padrão), **Claude Code** e **Codex**. A escolha fica em `agent.provider.kind.<tipo>`. Nesta spec, a linha "Planner e assistentes" é editável. As linhas Sessões e Prompt, Executar spec e Revisor aparecem com o estado atual ("segue o rodapé" ou "Só Claude Code") e ficam editáveis quando a spec de cada fluxo for entregue. A ordem de resolução fica assim: provedor da execução em andamento > escolha explícita no diálogo > tipo > projeto (rodapé por workspace) > padrão global > `claude`. O Codex só aparece como opção quando estiver disponível e compatível (SPEC-094). Se ele ficar indisponível depois de escolhido, o tipo continua "Codex", e a próxima execução falha com o aviso do R11. O app não troca de provedor por conta própria.
- R10 · **Provedor visível em cada execução.** O diálogo ou o painel de cada fluxo do R8 mostra, enquanto roda e no resultado, o provedor e o modelo ("Codex · gpt-6.1-terra") e o uso ("14,2 mil tokens"). O custo aparece em US$ só quando o provedor informa; senão, "custo indisponível" (decisão 5, com o ledger da SPEC-097). Um fluxo marcado **Só Claude Code** mostra a etiqueta junto da ação e explica o motivo numa dica.
- R11 · **Falha sem troca silenciosa.** Se o provedor do tipo não puder rodar (sem login, versão abaixo da mínima, `app-server` não sobe, cota esgotada), a mensagem diz qual provedor falhou e por quê. Ela oferece **Usar o Claude Code desta vez** (ou o Codex, no caso inverso), que roda só aquela execução no outro provedor e registra a troca no resultado. A preferência salva não muda.
- R12 · **Uso e cota.** Cada rodada grava em `usage_entries` com provedor, modelo, tokens (entrada, cache e saída, inclusive os de raciocínio do Codex) e a origem que o chamador já informa (spec, fonte, etapa). O custo fica nulo quando o provedor não informa, e nunca US$ 0. As leituras de cota do Codex que chegarem durante a rodada vão para a fonte de cota do Codex (SPEC-097), não para o `usageTracker` do Claude.

## Fora do escopo

- Executar as etapas de uma spec no Codex: [SPEC-101](SPEC-101-executar-spec-com-o-codex.md).
- Escolher o provedor do revisor e normalizar os achados: [SPEC-102](SPEC-102-review-automatico-com-o-codex.md).
- Orquestrador com modelos do Codex: SPEC-109 (Orquestrador multi-provedor).
- Agentes `.claude/agents` no Codex (decisão 7): SPEC-106 (Agentes no Codex).
- Usar `codex exec --json` como transporte. O App Server é o caminho (decisão 2), e o `exec` só entra como plano B se a SPEC-093 reprovar o `outputSchema` no App Server.
- Gerar skills no formato do Codex: SPEC-104 (Instruções e skills).
- Estimar custo em US$ para o Codex (decisão 5).

## Decisões em aberto

- P1 · **Protótipo de telas no Codex.** (a) Só Claude Code; (b) rodar o Codex em `workspace-write` numa pasta temporária isolada e copiar o resultado para `docs/mockups/`. **Recomendação: (a).** O protótipo depende de restringir a escrita por ferramenta (`--tools` + `allowedTools`), e a cópia de (b) cria um caminho de escrita novo só para esta tela. Reavaliar quando a SPEC-109 abrir o multi-provedor.
- P2 · **Perfil "rápido" no Codex.** (a) o menor modelo do `model/list` com esforço `low`; (b) o modelo do planner com esforço `low`; (c) uma escolha própria em Consumo. **Recomendação: (b) agora**, sem tela nova. A SPEC-094 lê os modelos do catálogo e não fixa nomes no código. A opção (c) entra se a checagem da VIBE ficar lenta.
- P3 · **Tipos de execução.** (a) um tipo só, "Planner e assistentes", para todo o R8; (b) separar Verificação e Decidir na etapa. **Recomendação: (a).** Os fluxos têm o mesmo perfil (somente leitura, curtos), e mais linhas no cartão só confundem. O `RunKind.planner` atual já agrupa esses fluxos para modelo e esforço.
- P4 · **Tempo-limite no Codex.** (a) o mesmo de cada chamador; (b) 1,5× no Codex enquanto não houver medida. **Recomendação: (a)**, com o tempo de cada rodada registrado no ledger para revisar depois com dados.

## Design

### Arquivos tocados

- **Novo:** `lib/core/providers/structured_run.dart` (`runStructured`, `StructuredIntent`, `StructuredResult`, erros e cancelamento).
- `lib/core/claude/readonly_run.dart`: vira o adaptador Claude do `runStructured`. O nome antigo fica como função de transição até migrar o último chamador, e sai no fim da spec.
- `lib/core/codex/codex_provider.dart`: `outputSchema` no `turn/start`, `developerInstructions` no `thread/start`, sandbox `read-only` com aprovação `never`, leitura da última mensagem e `turn/interrupt` no tempo-limite.
- Os arquivos da tabela do R8; no `step_classifier.dart`, só a assinatura do `stepClassifierRunProvider`.
- `lib/core/providers/provider_preferences.dart`: `providerForKind`, chave `agent.provider.kind.<tipo>` e ordem de resolução do R9.
- `lib/features/settings/settings_screen.dart` (Modelo e consumo): cartão Provedor por tipo. `settings_sections.dart`: termos de busca "provedor", "codex".
- Diálogos do R10: Nova spec, Projeto, Dividir em specs, Design, Verificar, Nova skill (rodapé do diálogo com provedor, modelo e uso), usando um widget comum `RunProviderLine`.
- `lib/features/cost/usage_ledger.dart`: custo nulo e campo `provider` (acordo com a SPEC-097).

### Migração

**Não.** A preferência fica em `app_settings`, e a retomada usa as chaves `agent.run.*` que já existem. O provedor no ledger depende do formato que a SPEC-097 definir para `usage_entries`. Se ela criar a coluna, esta spec só a preenche.

### Dependências

- SPEC-093 (Sondagem do Codex 0.170): restrições do `outputSchema`, formato de imagem e comportamento do `turn/interrupt`.
- SPEC-094 (Capacidades e opções por provedor): `ProviderCapabilities`, extras por provedor, modelo e esforço por provedor, versão mínima.
- SPEC-095 (Eventos neutros): uso em tokens no formato neutro.
- SPEC-097 (Cota do Codex no rodapé): fonte de cota do Codex e "custo indisponível" no ledger.
- Habilita a [SPEC-101](SPEC-101-executar-spec-com-o-codex.md) (Decidir na etapa no Codex) e a [SPEC-102](SPEC-102-review-automatico-com-o-codex.md) (revisor).

## Tarefas

- T1 · `runStructured` e adaptador Claude: a intenção, o resultado e a migração do `readonly_run.dart` sem mudar o comportamento no Claude. Verificar: os testes atuais do planner, do verificador e do revisor passam sem alteração de expectativa.
- T2 · Adaptador Codex: `outputSchema`, `developerInstructions`, `read-only`/`never`, tempo-limite e cancelamento com `turn/interrupt`, imagens e uso. Verificar: testes com o `fake_codex` (resposta válida, JSON inválido, pedido de aprovação negado, tempo-limite e cancelamento).
- T3 · Migrar os chamadores do R8, perfis de modelo (R4), variantes de schema (R3) e etiquetas Só Claude Code. Verificar: um teste por chamador com o provedor Codex falso e um teste que valida cada schema contra as restrições registradas na SPEC-093.
- T4 · Provedor por tipo (R9), linha de provedor nos diálogos (R10), falha com "Usar o Claude Code desta vez" (R11) e ledger (R12). Verificar: testes de widget do cartão e dos diálogos, e um teste da ordem de resolução.
- T5 · E2E no app isolado: Projeto, Nova spec com print e Verificar spec no Codex, mais um fluxo Só Claude Code. Verificar: capturas e relatório em `docs/pesquisa/`.

## Critérios de aceite

- [ ] Nenhum serviço de feature monta `ClaudeOptions` para execução estruturada, e `runReadOnlyClaude` não existe mais [R1] verificar: `grep` em `lib/features` e revisão do diff.
- [ ] Uma rodada estruturada no Codex nunca escreve no repositório e nega qualquer aprovação [R2] verificar: teste com o `fake_codex` pedindo `fileChange` e `commandExecution`, mais o sandbox enviado no `thread/start`.
- [ ] O Codex recebe o schema, e uma resposta fora dele vira erro claro, sem quebrar o serviço [R3] verificar: testes de resposta válida, inválida e com campo nulo.
- [ ] Nenhum alias do Claude chega ao Codex, e nenhum `maxBudgetUsd`, `maxTurns` ou `agent` chega a um provedor sem a capacidade [R1, R4, R5] verificar: teste das opções enviadas por adaptador.
- [ ] Tempo-limite e cancelamento interrompem o turno do Codex, e o cancelamento não conta como falha [R5] verificar: testes com o `fake_codex`.
- [ ] Prints vão como imagem quando o modelo aceita, e há aviso com escolha quando não aceita [R6] verificar: teste de widget da Nova spec e teste do adaptador.
- [ ] Refinar um plano continua no provedor e na thread originais [R7] verificar: teste do planner com o tipo trocado entre as rodadas.
- [ ] Cada fluxo do R8 roda no provedor do tipo, e os fluxos Só Claude Code mostram a etiqueta e o motivo [R8, R10] verificar: testes por chamador e de widget.
- [ ] O cartão Provedor por tipo grava a escolha e respeita a ordem de resolução, e o Codex indisponível não troca o provedor sozinho [R9, R11] verificar: testes de preferências e de widget.
- [ ] O ledger guarda tokens do Codex com custo nulo, e a cota do Codex não vai para o rastreador do Claude [R12] verificar: teste do ledger e do roteamento de `RateLimit`.
- [ ] No app isolado, Projeto, Nova spec com print e Verificar spec rodam no Codex com o provedor e o uso visíveis [R1–R12] verificar: capturas reais 1366×768 e relatório.

## Telas

Mockup: [canvas do Claude Design](https://claude.ai/artifact/LrZ5boRJza1uz8WUJ4VXv3). Capturas em `docs/mockups/spec-100/`:

| PNG | O que mostra | Requisitos |
|---|---|---|
| `0-antes.png` | Hoje: Modelo e consumo só com os modelos do Claude, e a Nova spec com o Codex no rodapé falhando com "Falha ao iniciar codex: maxBudgetUsd não suportado" | Problema |
| `1-provedor-por-tipo.png` | Modelo e consumo com o cartão Provedor por tipo: Planner e assistentes no Codex, as outras linhas com o estado atual e a ordem de resolução explicada | R8, R9 |
| `2-nova-spec-codex.png` | Nova spec planejando no Codex com um print: linha "Codex · gpt-6.1-terra", uso em tokens e "custo indisponível" no resultado | R3, R4, R6, R10, R12 |
| `3-so-claude-e-falha.png` | O Protótipo de telas com a etiqueta Só Claude Code e o motivo, o aviso de modelo sem imagem e a falha com "Usar o Claude Code desta vez" | R6, R8, R10, R11 |
