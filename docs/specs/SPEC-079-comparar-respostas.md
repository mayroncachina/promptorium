---
id: SPEC-079
status: rascunho
tipo: recurso
---

# Comparar respostas

## Objetivo

Antes de pedir uma coisa grande ao Claude, a pessoa fica em dúvida: o Sonnet dá conta ou vale gastar o Opus? Planejar antes ajuda, ou a resposta direta já basta? Hoje, para saber, ela manda o prompt, lê a resposta, troca o modelo no composer, manda de novo numa conversa nova e compara de memória, alternando entre as duas conversas. E não sabe quanto cada uma pesou na cota: o rodapé mostra só o total da janela de 5 h.

Exemplo: na conversa "Cupons expirados", a pessoa pergunta "por que o cupom PRIMEIRACOMPRA aceita pedido de cliente antigo?". Quer ver se o Sonnet acha a causa ou se precisa do Opus. Ela está no plano Max: o que importa não é o preço em dólar, e sim quanto da janela de 5 h e da cota semanal cada resposta come.

Esta spec cria o **Comparar** na tela Prompt:
- o mesmo prompt roda em **dois lados**, com modelos ou modos diferentes (Sonnet × Opus, Planejar × Perguntar), ao mesmo tempo e a partir do mesmo ponto da conversa;
- as respostas aparecem **lado a lado**, cada uma com o **tempo**, os **tokens**, as chamadas e o **peso na janela de 5 h e na semana** (não em US$);
- a pessoa **escolhe uma** e a conversa continua com ela; a outra fica guardada, recolhida.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/G9sgBDiJxEPDSrdFWx25FH). Capturas em `docs/mockups/spec-079/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-composer.png` | O composer em modo Comparar: os lados A e B com modelo e modo, os atalhos "Sonnet × Opus" e "Planejar × Perguntar" e a linha do peso | R1–R4 |
| `2-rodando.png` | Os dois lados rodando: A já terminou, B ainda lendo arquivos, com o tempo ao vivo e "medindo…" | R5–R8 |
| `3-lado-a-lado.png` | As duas respostas prontas, as métricas comparadas (tempo, tokens, peso na janela de 5 h e na semana) e "Continuar com esta" | R6, R7, R9 |
| `4-escolhida.png` | Depois de escolher o B: a resposta na timeline, o cartão recolhido da comparação e o composer de volta, já no Opus | R10–R12 |

Issue: a criar.

## Requisitos

### Pedir a comparação

- R1 · **Botão Comparar.** O composer do Prompt ganha um botão **Comparar** (ícone de duas colunas) entre o seletor de modo e Enviar. Ligado, ele vira âmbar e o composer mostra uma faixa com os **lados A e B**. Cada lado tem o seletor de **modelo** (os do provedor da conversa) e de **modo**. Ao ligar, o A vem com o modelo e o modo atuais da conversa, e o B com o "outro" modelo (Sonnet ↔ Opus; Haiku → Sonnet) e o mesmo modo. Um botão ⇄ troca os lados. Desligar volta ao composer normal, sem perder o texto.
- R2 · **Atalhos.** Dois chips preenchem os lados: **Sonnet × Opus** (mesmo modo) e **Planejar × Perguntar** (mesmo modelo). Lados iguais (mesmo modelo e mesmo modo) não podem ser enviados: "Os dois lados estão iguais. Troque o modelo ou o modo de um deles."
- R3 · **Só modos que não escrevem.** Os lados aceitam **Perguntar** e **Planejar**. **Editar** fica desabilitado, com a dica "Editar mudaria a pasta duas vezes ao mesmo tempo. Compare em Perguntar ou Planejar." Um lado em Planejar que chega ao "plano pronto" para ali: aprovar o plano só é possível depois de escolher esse lado (R10).
- R4 · **Peso antes de enviar.** A faixa mostra "Roda dois agentes ao mesmo tempo · janela de 5 h em 38% · semana em 61%". Com a janela de 5 h em 80% ou mais, a linha fica âmbar: "A janela de 5 h está em 86% e renova às 14:00. Comparar pode esgotá-la." O envio continua possível. Enviar comparando é **Enviar** com o Comparar ligado, ou **Ctrl+Shift+Enter** com ele desligado (liga e envia com os lados padrão).

### Rodar

- R5 · **Mesmo ponto de partida.** Os dois lados começam juntos. Numa conversa que já tem sessão do Claude, cada lado é um **fork** dela (`--resume <sessão> --fork-session`), então os dois têm o mesmo contexto e a sessão original não muda. Numa conversa nova, cada lado começa uma sessão nova. Os dois rodam na pasta da conversa (a raiz do workspace, ou a worktree da VIBE).
- R6 · **Lado a lado.** A mensagem da pessoa aparece uma vez, no topo, com o selo "Comparando". Abaixo, duas colunas iguais, cada uma com:
  - o cabeçalho: a letra (A, B), o modelo, o modo e o estado ("rodando · 0:42", "pronta · 38 s", "plano pronto", "parou: erro");
  - a timeline daquele lado: os cards de ferramenta, o texto e os blocos de código (com a barra da SPEC-077);
  - o rodapé com as métricas (R7) e o botão **Continuar com esta**.
  
  Cada coluna rola sozinha. Com a janela estreita (menos de 1100 px de área de conversa), as colunas viram abas "A · Sonnet" e "B · Opus", com as métricas das duas no topo.
- R7 · **Métricas sem US$.** Em cada lado, quando ele termina:
  - **Tempo**: a duração do turno (`duration_ms`), "38 s", "1 min 52 s";
  - **Tokens**: entrada (com o cache) e saída, "14,2 mil → 1,1 mil";
  - **Chamadas**: as ferramentas usadas no turno ("9 leituras · 2 buscas");
  - **Peso na janela de 5 h** e **na semana**: "≈ 1,2%" e "≈ 0,2%", com uma barra cada. Entre os lados, a razão: "B pesou 4,8× o A" e "B levou 2,9× o tempo".
  
  O custo em US$ não aparece em lugar nenhum da comparação. Enquanto o lado roda, o tempo conta ao vivo e o peso mostra "medindo…".
- R8 · **Como o peso é medido.** Antes de começar, o app lê o uso do plano (`/usage`, o `UsagePoller`, sem custo). Quando os dois lados terminam, lê de novo. O aumento da janela de 5 h e o da semana são divididos entre os lados pela parte de cada um no `total_cost_usd` (usado só como proporção). Sem as duas leituras, o peso usa a última leitura e a regra da Atividades (`sessionQuotaWeights`, SPEC-076 R7). O peso é sempre mostrado com "≈", e a dica explica: "estimado pela variação da janela durante a comparação".
- R9 · **Pedidos de cada lado.** Uma pergunta do agente (`AskUserQuestion`) ou uma aprovação aparece na coluna do lado que pediu, e a resposta vai só para ele. O selo do Prompt e a Atividades (SPEC-076) contam cada lado como uma atividade, com o robô da conversa e "A" ou "B".
- R10 · **Parar.** Cada coluna tem **Parar** enquanto roda. "Parar os dois" fica no topo. Um lado parado mostra o que respondeu até ali, como "interrompida", e ainda pode ser escolhido.

### Escolher e continuar

- R11 · **Continuar com esta.** Escolher um lado (pronto, interrompido ou com plano pronto):
  - para o outro lado, se ainda roda;
  - faz a conversa seguir pela sessão do lado escolhido (`claudeSessionId` passa a ser o fork dele), com o modelo e o modo dele;
  - põe a resposta escolhida na timeline como uma resposta normal, com a nota "escolhida entre 2 · Opus · Planejar";
  - guarda a outra num **cartão recolhido** "Comparação: Sonnet · Perguntar (não escolhida)", com as métricas dos dois e "Ver a resposta". Aberto, ele mostra a resposta guardada, só leitura;
  - devolve o composer ao normal, já com o modelo e o modo escolhidos, e foco nele.
  
  Um lado em Planejar escolhido traz o "plano pronto" como sempre (aprovar, ajustar).
- R12 · **Descartar a comparação.** "Descartar os dois" (com confirmação) para o que ainda roda, apaga os dois lados e devolve a conversa ao ponto de antes, com a sessão original e o texto do prompt de volta no composer.
- R13 · **Guardar e reabrir.** Enquanto não há escolha, a comparação fica salva como um evento da conversa, com os dois lados (modelo, modo, sessão, métricas e eventos). Fechar e reabrir o app mostra a comparação de novo: o lado que terminou continua pronto; o que rodava aparece "interrompida" e pode ser retomado (Retomar continua o fork) ou escolhido.
- R14 · **Uma por vez.** Enquanto uma comparação não foi escolhida nem descartada, o composer fica bloqueado com "Escolha uma resposta para continuar." e os dois botões de escolha à vista.

### Acessibilidade

- R15 · Cada coluna é uma região ("Resposta A, Sonnet, Perguntar, pronta em 38 segundos"). As métricas têm o texto completo para o leitor ("peso na janela de 5 horas, cerca de 1,2 por cento"). Os estados usam texto e ícone, não só a cor. A ordem do Tab passa pela coluna A inteira, depois pela B.

## Fora do escopo

- Comparar em **Editar** (precisaria de uma worktree por lado, como o duelo de etapas do Quadro). Ver P3.
- Mais de dois lados e comparar provedores diferentes (Claude × Codex).
- Diferença automática entre as respostas (diff de texto) e um "juiz" que escolhe sozinho.
- Comparar nas Sessões, na VIBE ou na etapa de uma spec (o Quadro já tem o duelo de etapas).
- Mostrar US$ na comparação, mesmo para quem usa a API (P2).
- Guardar estatísticas de qual modelo "ganha" mais.

## Decisões em aberto

- P1 · **Onde fica o botão.** No composer (um interruptor ao lado de Enviar) ou numa ação "Comparar com outro modelo" sobre uma resposta já dada (que roda só o lado que falta). **Recomendação:** **no composer**, como interruptor. Comparar uma resposta já dada mede o lado novo num contexto diferente (já com a resposta antiga) e não seria justo. "Refazer com outro modelo" pode vir depois.
- P2 · **Mostrar US$.** O usuário está no plano Max; o dólar do CLI é só estimativa e distrai. **Recomendação:** **não mostrar**; o custo serve só como proporção para dividir o peso (R8).
- P3 · **Editar.** Dois agentes editando a mesma pasta se atropelam. Com worktrees por lado (como o duelo do Quadro) dá, mas aí é outro recurso. **Recomendação:** **fora**; Perguntar e Planejar cobrem o "plano × direto" sem tocar nos arquivos.
- P4 · **Como medir o peso.** Opções: (a) a variação do `/usage` antes e depois, dividida pela proporção do custo; (b) só a regra da Atividades, pela última leitura; (c) tokens ponderados por modelo. **Recomendação:** **(a)**, com (b) quando não há as duas leituras (R8). A (c) depende de pesos que a Anthropic não publica.
- P5 · **Onde guardar a comparação.** Uma tabela nova (`conversation_compares`) ou um evento da conversa em `conversation_events`. **Recomendação:** **evento da conversa** (`type = 'compare'`, JSON com os dois lados), **sem migração**. A timeline já carrega eventos, e a comparação só existe dentro de uma conversa.
- P6 · **O que acontece com a resposta não escolhida.** Apagar, guardar recolhida ou virar uma conversa à parte. **Recomendação:** **guardar recolhida** no cartão da comparação (R11), só leitura. Virar conversa à parte duplicaria a lista.
- P7 · **Layout em janela estreita.** **Recomendação:** abaixo de 1100 px de área de conversa, abas A/B com as métricas no topo (R6); o painel lateral recolhe sozinho ao comparar, para dar espaço.
- P8 · **Padrão do lado B.** **Recomendação:** o "outro" modelo no mesmo modo (Sonnet ↔ Opus), porque é a dúvida mais comum. A última combinação usada fica lembrada por workspace em `app_settings`.

## Design

Canvas para validar: [Comparar respostas](https://claude.ai/artifact/G9sgBDiJxEPDSrdFWx25FH). Quatro artboards de 1366 × 768: o composer, os lados rodando, lado a lado e depois de escolher.

### O que já existe

- `lib/features/prompt/conversation_manager.dart`: `ConversationManager` (um processo por conversa, `_Run`, `_handle` dos eventos, `Result` com custo e uso), `PromptDraft`, `modelLabel`.
- `lib/features/prompt/prompt_screen.dart` e `widgets/prompt_composer.dart`: a tela, o `_Header`, o composer com o seletor de modo e de modelo.
- `lib/core/providers/agent_provider.dart`: `PromptMode` (ask, plan, edit) e as opções de execução (`resumeId`, `forkSession`), já usadas em `session_manager.dart`.
- `lib/core/providers/agent_event.dart`: `Result` (`durationMs`, `usage`, `totalCostUsd`, `numTurns`).
- `lib/core/claude/usage_poller.dart` (`/usage` sem custo) e `usage_tracker.dart` (`rateLimitProvider`).
- `lib/features/activities/quota_forecast.dart`: `sessionQuotaWeights`, `quotaDuration` (SPEC-076).
- `lib/features/prompt/plan_ready.dart`: o plano pronto.
- `lib/features/board/widgets/duel_dialog.dart`: o duelo de etapas (A × B em worktrees), referência de layout e de nomes.

### Componentes

- **`lib/features/prompt/compare/compare_run.dart`**: `CompareSide` (letra, modelo, modo, sessão, estado, timeline em memória, métricas) e `CompareRun` (conversa, prompt, os dois lados, leituras de uso antes e depois).
- **`compare_controller.dart`**: `compareProvider(conversationId)`: começa os dois lados (fork), encaminha aprovações, para, escolhe (R11), descarta (R12), salva e restaura o evento `compare` (R13).
- **`compare_weight.dart`**: `compareWeights(before, after, costs)` (função pura, R8) e `compareRatio`.
- **`widgets/compare_bar.dart`** (faixa dos lados no composer, R1–R4), **`compare_view.dart`** (as colunas, R6–R10), **`compare_metrics.dart`** (R7) e **`compare_card.dart`** (o cartão recolhido, R11).
- `ConversationManager` ganha `adoptSession(id, sessionId, model, mode)` e o `ConversationRepo` grava o evento `compare`.

### Migração

Não. A comparação é um evento da conversa (`conversation_events`, `type = 'compare'`) e a escolha atualiza colunas que já existem (`claude_session_id`, `model`, `mode`). A combinação dos lados fica em `app_settings`.

### Arquivos tocados

- `lib/features/prompt/compare/` (novo)
- `lib/features/prompt/conversation_manager.dart`, `prompt_screen.dart`, `widgets/prompt_composer.dart`
- `lib/data/repos/conversations_repo.dart`, `app_settings_repo.dart` (chave da última combinação)
- `lib/features/sessions/widgets/timeline_view.dart` (o item `compare`)
- `lib/features/activities/activity.dart` (lado A/B como atividade)
- `test/features/prompt/compare/`

### Testes

- `compareWeights`: divide o aumento pela proporção do custo; sem leitura, cai na regra da Atividades; razão entre os lados.
- Controller: começa os dois com `forkSession`; conversa nova sem `resumeId`; escolher troca a sessão, o modelo e o modo e grava o cartão; descartar devolve o texto; reabrir restaura e marca o que rodava como interrompido.
- Composer: Comparar liga a faixa; lados iguais bloqueiam o envio; Editar desabilitado; aviso com a janela em 80% ou mais; Ctrl+Shift+Enter.
- Tela: duas colunas e as abas em janela estreita; métricas sem US$; "Continuar com esta" e o cartão recolhido.

## Critérios de aceite

- [ ] O Comparar liga os lados A e B com modelo e modo, os atalhos preenchem, lados iguais e Editar não podem ser enviados [R1–R3] verificar: flutter test test/features/prompt/compare/compare_bar_test.dart
- [ ] A faixa mostra a janela de 5 h e a semana, e fica âmbar com 80% ou mais [R4] verificar: flutter test test/features/prompt/compare/compare_bar_test.dart
- [ ] Os dois lados começam juntos, como fork da sessão da conversa, e a sessão original não muda [R5] verificar: flutter test test/features/prompt/compare/compare_controller_test.dart
- [ ] As colunas mostram a timeline de cada lado, o estado e as métricas de tempo, tokens, chamadas e peso, sem US$ [R6, R7] verificar: flutter test test/features/prompt/compare/compare_view_test.dart
- [ ] O peso divide a variação do uso pela proporção do custo e cai na regra da Atividades sem leitura [R8] verificar: flutter test test/features/prompt/compare/compare_weight_test.dart
- [ ] Pedidos e Parar valem por lado [R9, R10] verificar: flutter test test/features/prompt/compare/compare_controller_test.dart
- [ ] Escolher um lado continua a conversa pela sessão, modelo e modo dele, e guarda o outro recolhido; descartar volta ao ponto de antes [R11, R12] verificar: flutter test test/features/prompt/compare/compare_controller_test.dart
- [ ] A comparação sem escolha volta ao reabrir o app, e o composer fica bloqueado até a escolha [R13, R14] verificar: flutter test test/features/prompt/compare/compare_controller_test.dart
- [ ] No app, o mesmo prompt em Sonnet × Opus mostra as duas respostas lado a lado, o peso de cada uma na janela de 5 h e na semana, e a conversa continua no lado escolhido [R1–R14] verificar: manual (app isolado com `XDG_DATA_HOME`, prints em `docs/mockups/spec-079/app/`)
- [ ] O projeto compila e a análise estática passa [R1–R15] verificar: flutter analyze
