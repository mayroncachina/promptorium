---
id: SPEC-108
status: rascunho
versao: 0.26.0
tipo: recurso
epico: 332
issue: 336
depende-de: [SPEC-079, SPEC-094, SPEC-095, SPEC-096, SPEC-097, SPEC-099]
---

# Comparar Claude × Codex

## Objetivo

O Comparar da SPEC-079 roda o mesmo prompt em dois lados, mas os dois lados usam o provedor da conversa. "Claude × Codex" ficou fora do escopo. Com o Codex ligado (SPEC-096), essa passa a ser a dúvida mais comum: o Codex resolve isto tão bem quanto o Claude? Qual dos dois gasta menos do plano?

Exemplo: na conversa "Cupons expirados", que já tem 6 mensagens com o Claude Opus, a pessoa pergunta "por que o cupom PRIMEIRACOMPRA aceita pedido de cliente antigo?". Ela quer ver a resposta do Codex (`gpt-6.2-sol`) ao lado da resposta do Opus. Hoje ela precisa abrir uma conversa nova no Codex, colar o contexto à mão, mandar o prompt e comparar de memória. Também não sabe quanto cada resposta pesou: o Claude gasta a janela de 5 h do plano Max e o Codex gasta as janelas do plano ChatGPT. São duas cotas diferentes, e o rodapé mostra uma de cada vez.

Esta spec amplia o Comparar:
- cada lado tem o seu **provedor**, além do modelo, do esforço e do modo, e há o atalho **Claude × Codex**;
- o lado do outro provedor não tem como fazer fork da sessão. Ele começa uma conversa nova com um **contexto de partida** que o app monta e que a pessoa pode revisar antes de enviar;
- as métricas mostram **tempo e tokens** lado a lado. O peso aparece **na cota de cada provedor**, sem US$ e sem razão entre cotas diferentes;
- **Ficar com este lado** pode mudar o provedor da conversa, de forma explícita, entre um turno e outro;
- opcional (R11): o **Comparar A/B** do Quadro, que já usa uma worktree por tentativa, passa a aceitar um provedor por tentativa. Aí também entra a métrica de diff.

## Requisitos

### Pedir a comparação

- R1 · **Provedor por lado.** Cada lado da faixa do Comparar (SPEC-079 R1) ganha o seletor de **provedor**, à esquerda do modelo: Claude Code ou Codex. Ao trocar o provedor, o lado vem com o modelo e o esforço padrão daquele provedor para conversas (chaves `<provedor>.model.conversation` da SPEC-094). Os modelos do Codex vêm do `model/list` e nunca ficam fixos no código. O esforço é o do modelo escolhido: os níveis do Claude, ou os `supportedReasoningEfforts` do modelo do Codex. O lado mostra o selo do provedor com nome e ícone, sem depender só da cor.
- R2 · **Atalho Claude × Codex.** Um terceiro chip, ao lado de "Sonnet × Opus" e "Planejar × Perguntar", põe o provedor da conversa no lado A e o outro provedor no lado B, os dois no mesmo modo. A regra de lados iguais (SPEC-079 R2) passa a comparar provedor, modelo, esforço e modo. Com o Codex indisponível (não instalado, versão abaixo de 0.170, sem login ou desligado no fluxo Prompt pela SPEC-096), o chip e a opção Codex ficam desabilitados com o motivo e o link "Abrir Provedores". O app nunca troca de provedor sem avisar.
- R3 · **Modos de cada provedor.** Os lados continuam só em Perguntar e Planejar (SPEC-079 R3). No Codex, os dois rodam em sandbox `read-only` com aprovação `never` (decisão 3 do épico), então o runtime garante que nada é escrito. Planejar no Codex não tem `ExitPlanMode`. O lado termina em "plano pronto" quando o turno acaba, e a última resposta vira o plano. Aprovar esse plano só é possível depois de escolher o lado, como na SPEC-079.
- R4 · **Contexto de partida.** Numa conversa nova, os dois lados começam juntos, do zero. Numa conversa com histórico:
  - o lado do **mesmo provedor** da conversa faz fork da sessão, como hoje (`--resume … --fork-session` no Claude, `thread/fork` no Codex);
  - o lado do **outro provedor** começa uma sessão nova com o **contexto de partida**. É o mesmo pacote de "Passar o trabalho entre agentes" (SPEC-099): as últimas mensagens, os arquivos citados, o plano vigente e o estado do git, sem copiar segredos;
  - a faixa avisa: "B começa sem a sessão do Claude: recebe um resumo de ≈ 3,1 mil tokens montado pelo app. Os dois lados não partem exatamente do mesmo ponto." O link "Ver o que o B recebe" abre o pacote para revisão e edição antes do envio;
  - o interruptor "Mesmo resumo nos dois lados" (desligado por padrão, P1) faz os dois lados partirem do pacote, para uma comparação mais justa.
- R5 · **Peso antes de enviar, por provedor.** A linha de peso (SPEC-079 R4) mostra a cota de cada provedor envolvido: "Claude · janela de 5 h em 38% · semana em 61% · Codex · janela de 5 h em 12% · semana em 30%". Os nomes das janelas do Codex vêm de `windowDurationMins`, não de um texto fixo. A linha fica âmbar quando qualquer uma das janelas envolvidas passa de 80%, e o aviso diz de qual provedor é a janela. Enviar continua possível.

### Rodar e medir

- R6 · **Colunas com provedor.** O cabeçalho de cada coluna (SPEC-079 R6) mostra o selo do provedor antes do modelo: "B · Codex · gpt-6.2-sol · medium · Perguntar". A timeline do lado Codex usa os eventos neutros da SPEC-095. Uma leitura feita por comando (`commandActions` do tipo `read`, `search` ou `listFiles`) aparece como leitura, e não como comando genérico. Um pedido do lado Codex (`item/permissions/requestApproval`, `item/tool/requestUserInput`) aparece na coluna dele e vale só para ele (SPEC-079 R9). A Atividades conta cada lado com o robô e o provedor.
- R7 · **Métricas comuns.** Ao terminar, cada lado mostra:
  - **Tempo**: `duration_ms` do Claude ou `durationMs` do turno do Codex;
  - **Tokens**: entrada (com o cache) → saída. No Codex aparece também o raciocínio (`reasoningOutputTokens`), separado: "18,4 mil → 1,6 mil · raciocínio 2,1 mil";
  - **Chamadas**: leituras, buscas, comandos, MCP e web, com a mesma contagem nos dois provedores.
  
  Entre os lados aparecem as razões de tempo e de tokens totais ("B levou 0,6× o tempo · usou 1,3× os tokens"). Quando os provedores diferem, a dica avisa: "tokenizadores diferentes: os tokens servem de ordem de grandeza".
- R8 · **Peso na cota de cada provedor.** O app lê a cota de cada provedor envolvido antes de começar e depois que os dois lados terminam. No Claude é o `/usage` (`UsagePoller`); no Codex é o `account/rateLimits/read`, com o `account/rateLimits/updated` durante o turno (SPEC-097).
  - Quando os provedores diferem, cada cota só é gasta por um lado, então a variação inteira é daquele lado e não há divisão pelo custo.
  - Quando os dois lados usam o mesmo provedor, vale a regra da SPEC-079 R8. No Codex, sem custo, a divisão é pela proporção de tokens totais.
  - O peso aparece com o nome do provedor e da janela: "Codex · janela de 5 h ≈ 3%". A razão "B pesou 4,8× o A" só aparece quando os dois lados gastam a mesma cota. Entre cotas diferentes aparece "cotas diferentes · sem razão" (P2).
  - US$ não aparece em lugar nenhum, nem para o Claude. O `total_cost_usd` não entra na conta quando os provedores diferem (decisão 5 do épico).

### Escolher e continuar

- R9 · **Ficar com este lado.** "Continuar com esta" (SPEC-079 R11) faz a conversa seguir pela sessão do lado escolhido, que pode ser de outro provedor:
  - `conversations.provider` passa a ser o provedor do lado, e `claudeSessionId` passa a guardar a sessão ou a thread dele (o nome da coluna fica, como no plano técnico). O modelo, o esforço e o modo também mudam;
  - a timeline ganha a nota "A conversa passou para o Codex · gpt-6.2-sol · Perguntar (escolhida entre 2)". O seletor do rodapé e o composer mostram o provedor novo;
  - a sessão do lado não escolhido fica no cartão recolhido, com as métricas dos dois lados, "Ver a resposta" e "Abrir no terminal" (`claude --resume` ou `codex resume`, só leitura do ponto de vista do app);
  - a troca acontece entre turnos e por escolha explícita, então respeita a decisão 4 do épico ("nunca troca no meio de uma execução").
- R10 · **Guardar e reabrir.** O evento `compare` (SPEC-079 R13) grava o `provider` e o `effort` de cada lado e o pacote de partida enviado (só o texto e a lista de arquivos). Um evento antigo, sem `provider`, usa o provedor da conversa. Ao reabrir o app, um lado Codex interrompido pode ser retomado com `thread/resume`. Descartar a comparação (SPEC-079 R12) volta à sessão e ao provedor de antes.

### Comparar A/B do Quadro

- R11 · **Um provedor por tentativa.** No menu do card, "Comparar A/B" passa a abrir um diálogo curto antes de começar. Cada tentativa escolhe provedor, modelo e esforço; o padrão é a configuração atual das duas, como hoje, e há o atalho "Claude × Codex". As tentativas rodam cada uma na sua worktree temporária, como hoje. A tentativa Codex usa o modo da etapa e os *writable roots* da SPEC-101. O diálogo do duelo mostra por tentativa o provedor, o gate, os arquivos com "+/−", o tempo e os tokens, sem US$. Escolher continua levando a tentativa para a branch da spec. Este requisito depende de "Executar spec com o Codex" (SPEC-101). Sem ela, a opção Codex aparece desabilitada com o motivo.

### Acessibilidade

- R12 · As regiões das colunas incluem o provedor ("Resposta B, Codex, gpt-6.2-sol, Perguntar, pronta em 24 segundos"). O selo do provedor tem texto. Os pesos são lidos com o nome da cota ("peso na janela de 5 horas do Codex, cerca de 3 por cento"). A ordem do Tab é a da SPEC-079 R15.

## Fora do escopo

- Mais de dois lados (Claude × Codex × outro modelo) e um "juiz" que escolhe sozinho.
- Comparar em Editar no Prompt. O A/B do Quadro (R11) já cobre a edição em worktrees separadas.
- Diferença automática entre os textos das respostas.
- Mostrar US$ ou converter a cota de um provedor na do outro.
- Estatística de qual provedor "ganha" mais.
- Agentes `.claude/agents` no lado Codex (decisão 7 do épico): o lado Codex ignora o agente da conversa e mostra "agente só no Claude".
- Comparar nas Sessões, na VIBE ou no review automático.

## Decisões em aberto

- P1 · **Ponto de partida numa conversa com histórico.** (a) O lado do mesmo provedor faz fork e o outro recebe o pacote de partida; (b) os dois partem do mesmo pacote. **Recomendação: (a) como padrão, com (b) no interruptor "Mesmo resumo nos dois lados".** Com (a), o lado da conversa não perde contexto, e é por ele que a conversa provavelmente vai seguir. A faixa avisa que os pontos de partida diferem. Para quem quer só comparar os provedores, (b) fica a um clique.
- P2 · **Razão de peso entre cotas diferentes.** (a) Não mostrar a razão: cada lado mostra o peso na própria cota; (b) comparar as porcentagens como se fossem a mesma unidade. **Recomendação: (a).** 3% da janela do Codex e 1,2% da janela do Claude não são a mesma unidade, e uma razão entre elas engana. A comparação direta fica no tempo e nos tokens, com o aviso sobre os tokenizadores.
- P3 · **Comparar A/B do Quadro nesta spec.** (a) Fica nesta spec, como última tarefa; (b) vira uma spec à parte. **Recomendação: (a), como T5 que pode ser cortada.** O A/B já tem worktree por tentativa e `sessions.provider`, então falta pouco além do diálogo. Se a SPEC-101 atrasar, a T5 sai e o resto entrega sozinho.
- P4 · **Padrão do lado B no atalho.** (a) O modelo padrão do provedor para conversas; (b) uma tabela de "modelo equivalente" (Opus ↔ um modelo Codex). **Recomendação: (a)**, lembrando a última combinação por workspace (SPEC-079 P8). Uma tabela de equivalência precisaria de manutenção a cada versão dos modelos e passaria uma ideia de equivalência que não existe.
- P5 · **Esforço por lado.** **Recomendação: mostrar**, preenchido pela preferência do provedor. O Codex expõe vários esforços por modelo (até `ultra`) e isso muda muito o tempo e os tokens.
- P6 · **Lado não escolhido de outro provedor.** (a) Fica no cartão recolhido com "Abrir no terminal"; (b) vira uma conversa à parte. **Recomendação: (a)**, como a SPEC-079 P6. Duplicar a lista de conversas não ajuda.

## Design

### O que já existe

- `lib/features/prompt/compare/compare_run.dart`: `CompareSide` (letra, modelo, modo, sessão, métricas, peso, eventos) e `CompareRun` (leituras `before`/`after`, `measured`).
- `lib/features/prompt/compare/compare_controller.dart`: começa os lados com `provider.start(...)` usando `conv.provider` para os dois (l. 248), fork com `resumeId`/`forkSession`, `/usage` antes e depois, `choose` chama `ConversationManager.adoptSession` (sem provedor).
- `lib/features/prompt/compare/compare_weight.dart`: divisão do aumento da janela pela proporção de `total_cost_usd`.
- `lib/features/prompt/compare/widgets/`: `compare_bar.dart`, `compare_view.dart`, `compare_metrics.dart`, `compare_card.dart`.
- `lib/features/prompt/conversation_manager.dart`: `adoptSession(id, sessionId, model, mode)`.
- `lib/core/codex/codex_provider.dart`: `turn/started`, `thread/tokenUsage/updated`, `turn/completed`; `lib/core/providers/agent_registry.dart` e `provider_preferences.dart`.
- `lib/features/board/spec_runner.dart` (`_startDuel`, l. 1122), `widgets/duel_dialog.dart` e `board_screen.dart` (menu `duel`). `spec_duels` guarda as sessões A e B, e `sessions.provider` já diz o provedor de cada uma.

### Componentes

- `CompareSide` ganha `provider` e `effort`. `CompareRun` ganha `before`/`after` por provedor (`Map<String, UsageReading>`) e `handoff` (o pacote enviado ao lado sem fork).
- `compare_controller.dart`: `_startSide` resolve o `AgentProvider` do lado, decide entre fork e pacote (R4), lê a cota de cada provedor envolvido pelo `QuotaSource` da SPEC-097 e chama `adoptSession(..., provider:)` em `choose`.
- `compare_weight.dart`: `compareWeights` por provedor. A variação inteira vai para o lado quando ele é o único da cota; no Codex, sem custo, a divisão é por tokens. `compareRatio` devolve null entre cotas diferentes.
- `widgets/compare_bar.dart`: seletor de provedor, chip "Claude × Codex", aviso do pacote e "Ver o que o B recebe" (reaproveita a revisão do pacote da SPEC-099).
- `widgets/compare_metrics.dart`: raciocínio, nomes de janela por provedor, "cotas diferentes · sem razão" e o aviso dos tokenizadores.
- `ConversationManager.adoptSession` ganha `provider` e `effort`; `ConversationsRepo` grava `provider`.
- R11: `widgets/duel_start_dialog.dart` (novo); `_startDuel` recebe provedor, modelo e esforço por tentativa; `duel_dialog.dart` mostra o provedor e os tokens.

### Migração

Não. O provedor e o esforço de cada lado vão no JSON do evento `compare` (`conversation_events`). `conversations.provider` e `sessions.provider` já existem. A última combinação continua em `app_settings`.

### Dependências

- SPEC-094 (capacidades e opções por provedor): modelo e esforço por provedor, "Só Claude Code".
- SPEC-095 (eventos neutros): timeline e chamadas do lado Codex.
- SPEC-096 (Codex no Prompt e nas Sessões): conversa e fork no Codex.
- SPEC-097 (cota do Codex no rodapé): `QuotaSource` do Codex.
- SPEC-099 (passar o trabalho entre agentes): o pacote de partida do R4.
- SPEC-101 (executar spec com o Codex): só para o R11.

### Arquivos tocados

- `lib/features/prompt/compare/` (os arquivos acima)
- `lib/features/prompt/conversation_manager.dart`, `lib/data/repos/conversations_repo.dart`
- `lib/features/board/spec_runner.dart`, `board_screen.dart`, `widgets/duel_dialog.dart`, `widgets/duel_start_dialog.dart` (novo)
- `test/features/prompt/compare/`, `test/features/board/duel_*`

## Tarefas

- T1 · Modelo e controle: `provider`/`effort` em `CompareSide`, compatibilidade com eventos antigos, início por provedor, fork ou pacote, escolha que troca o provedor da conversa [R1, R3, R4, R9, R10].
- T2 · Peso e métricas: cota por provedor antes e depois, pesos sem divisão entre cotas diferentes, raciocínio e razões [R5, R7, R8].
- T3 · Faixa e colunas: seletor de provedor, chip, aviso e revisão do pacote, selo nas colunas, pedidos do lado Codex [R1, R2, R4, R6, R12].
- T4 · e2e no app isolado (xdotool, `XDG_DATA_HOME`), com uma conversa Claude e um lado Codex [R1–R10, R12].
- T5 · Comparar A/B do Quadro com provedor por tentativa (cortável, depende da SPEC-101) [R11].

## Critérios de aceite

- [ ] Cada lado escolhe provedor, modelo e esforço; os modelos do Codex vêm do `model/list`; o chip "Claude × Codex" preenche os lados e lados iguais (com provedor) não são enviados [R1, R2] verificar: flutter test test/features/prompt/compare/compare_bar_test.dart
- [ ] Com o Codex indisponível, o chip e a opção ficam desabilitados com o motivo [R2] verificar: flutter test test/features/prompt/compare/compare_bar_test.dart
- [ ] O lado Codex roda em `read-only` com aprovação `never` em Perguntar e Planejar, e o Planejar termina em "plano pronto" [R3] verificar: flutter test test/features/prompt/compare/compare_controller_test.dart (fake_codex)
- [ ] Numa conversa com histórico, o lado do mesmo provedor faz fork e o outro recebe o pacote revisável; com "Mesmo resumo nos dois lados", os dois recebem o pacote [R4] verificar: flutter test test/features/prompt/compare/compare_controller_test.dart
- [ ] A linha de peso mostra as janelas de cada provedor envolvido e fica âmbar com 80% em qualquer uma [R5] verificar: flutter test test/features/prompt/compare/compare_bar_test.dart
- [ ] As colunas mostram o selo do provedor, as leituras do Codex como leituras e os pedidos só no lado que pediu [R6] verificar: flutter test test/features/prompt/compare/compare_view_test.dart
- [ ] Tempo, tokens (com o raciocínio do Codex) e chamadas aparecem nos dois lados, sem US$, com as razões de tempo e tokens [R7] verificar: flutter test test/features/prompt/compare/compare_view_test.dart
- [ ] Com provedores diferentes, cada lado recebe a variação inteira da própria cota e não há razão de peso; com o mesmo provedor, vale a regra da SPEC-079 (no Codex, por tokens) [R8] verificar: flutter test test/features/prompt/compare/compare_weight_test.dart
- [ ] Escolher o lado de outro provedor troca o provedor, a sessão, o modelo, o esforço e o modo da conversa, grava a nota e guarda o outro lado no cartão [R9] verificar: flutter test test/features/prompt/compare/compare_controller_test.dart
- [ ] Um evento `compare` antigo, sem provedor, abre com o provedor da conversa; um lado Codex interrompido é retomado; descartar volta ao provedor de antes [R10] verificar: flutter test test/features/prompt/compare/compare_controller_test.dart
- [ ] O Comparar A/B do Quadro aceita um provedor por tentativa e mostra o provedor, o gate, o diff, o tempo e os tokens de cada uma [R11] verificar: flutter test test/features/board/duel_start_dialog_test.dart
- [ ] O leitor de tela anuncia o provedor das colunas e o nome da cota de cada peso [R12] verificar: flutter test test/features/prompt/compare/compare_view_test.dart (semantics)
- [ ] No app isolado, uma conversa Claude com histórico compara Opus × Codex, mostra o aviso do pacote, as métricas e o peso de cada cota, e a conversa continua no Codex depois da escolha [R1–R10] verificar: manual (xdotool, `XDG_DATA_HOME`, prints em `docs/mockups/spec-108/app/`)
- [ ] O projeto compila e a análise estática passa [R1–R12] verificar: flutter analyze

## Telas

Mockup: [canvas do Claude Design](https://claude.ai/artifact/9iNV7WHKi4USJtoQuLsAAi). Capturas em `docs/mockups/spec-108/` (1366×768):

| PNG | O que mostra | Requisitos |
|---|---|---|
| `0-antes.png` | Hoje: o Comparar só oferece modelos do provedor da conversa; para comparar com o Codex é preciso abrir outra conversa e colar o contexto à mão | — |
| `1-faixa-provedores.png` | A faixa com o seletor de provedor por lado, o chip "Claude × Codex", o aviso do pacote de partida com "Ver o que o B recebe" e a linha de peso com as duas cotas | R1, R2, R4, R5 |
| `2-lado-a-lado.png` | Opus × Codex prontos: selo do provedor, leituras do Codex como leituras, tempo, tokens com raciocínio, peso em cada cota, "cotas diferentes · sem razão" e o aviso dos tokenizadores | R6–R8, R12 |
| `3-escolhida-codex.png` | Depois de ficar com o lado Codex: a nota "A conversa passou para o Codex", o cartão recolhido com "Abrir no terminal" e o rodapé no Codex | R9, R10 |
| `4-duelo-quadro.png` | Comparar A/B do Quadro: o diálogo de início com um provedor por tentativa e o resultado com gate, diff, tempo e tokens | R11 |
