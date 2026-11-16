---
id: SPEC-076
status: aprovada
depende-de: SPEC-072, SPEC-073, SPEC-074, SPEC-075
issue: 260
---

# Atividades: tudo o que está rodando, com o robô de cada agente

## Objetivo

Com o Autopilot, o Corrigir CI automático, o "Acompanhar PR", as VIBEs e vários workspaces abertos, o app roda muita coisa ao mesmo tempo, e cada uma aparece num lugar: as sessões na tela Sessões do workspace ativo, o gate no card do Quadro, o PR acompanhado no Review, a release no Repositório, o servidor de dev na aba Preview, a cota no rodapé. Para saber "o que está rodando agora, o que está parado esperando por mim e quanto da cota isso está gastando", a pessoa troca de workspace e de tela várias vezes. E nada mostra o que o agente está fazendo naquele segundo: lendo, editando ou rodando os testes.

Esta spec cria a tela **Atividades**:
- um item novo no menu lateral, com o selo do que precisa de você;
- uma lista dos **processos vivos de todos os workspaces** (não do trabalho: isso é o Quadro), agrupada por workspace, com o estado, o tempo, a última ação, o uso e a ação de cada linha;
- o painel do selecionado, a cota de 5 h e da semana **com a previsão no ritmo atual**, e "Pausar automáticos";
- **um robô por agente**, com forma e cor próprias, que mostra pela animação o que ele está fazendo. O mesmo robô aparece no card do Quadro, e clicar nele leva de uma tela à outra.

O nome é "Atividades" porque "Agentes" já é a tela dos subagentes (Ferramentas).

Mockup: [canvas do Claude Design](https://claude.ai/artifact/24NmtjoJLK9oUBrQbabjPK). Capturas em `docs/mockups/spec-076/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-atividades.png` | A tela: menu com o selo, abas, grupos por workspace, a linha de cada atividade com o robô, a cota com a previsão e o painel do selecionado | R1–R8, R15–R23 |
| `2-quadro.png` | O Quadro com o robô no card, o balão do pedido, o robô dormindo da fila do Autopilot e a barra "N agentes trabalhando" | R9–R14 |
| `3-robos.png` | Os robôs, um estado por animação | R9–R12 |

Issue: [#260](https://github.com/mayroncachina/promptorium/issues/260) (sub-issue de [#240](https://github.com/mayroncachina/promptorium/issues/240)) · PR: [#261](https://github.com/mayroncachina/promptorium/pull/261)

## Requisitos

### t1 · Núcleo: o registro das atividades

- R1 · **Uma atividade é um processo vivo**, de qualquer workspace aberto no app:
  - **agente de spec**: a sessão de uma etapa (com o processo do Claude vivo, ou que falhou e não foi retomada);
  - **VIBE** e conversa do Prompt com um turno em andamento ou um pedido pendente (inclusive "plano pronto");
  - **gate** rodando (a suíte da etapa);
  - **PR acompanhado** ("Acompanhar PR") e **Corrigir CI** em andamento;
  - **release** disparada e ainda não terminada (ou que falhou);
  - **planner** (Projeto) com uma execução em andamento;
  - **servidor de dev** no ar ou subindo;
  - **fila do Autopilot**: as specs que o "Executar tudo" vai começar (ligado) ou que o agendamento vai começar (agendado).
  
  O que terminou bem sai da lista. Não há "Feito" nem "Concluídas hoje".
- R2 · **Coluna e "precisa de você".** Cada atividade fica numa coluna, a mesma do Quadro: **Backlog** (só a fila do Autopilot e as agendadas), **Em execução** ou **Review** (gate, Corrigir CI e PR acompanhado de uma spec em Review). Independente da coluna, ela **precisa de você** quando espera uma aprovação, tem um plano pronto, parou com erro ou parou numa etapa sem concluir.
- R3 · **O que o agente está fazendo.** O app passa a guardar, por sessão viva, a ferramenta em uso (nome e alvo), as últimas cinco ações com a hora, o número de chamadas e de arquivos editados no turno e o último texto do agente. Disso sai a pose do robô (R10) e as colunas "última ação" e "uso". Nada disso vai para o banco.
- R4 · **Progresso quando dá para medir**: as etapas da spec (`t2 de 3`), a rodada do Corrigir CI, os jobs da release (`2 de 4 jobs`). Sem medida, a linha não mostra barra.
- R5 · **Identidade estável.** Cada atividade de agente tem uma semente: a spec (workspace + código) para tudo o que trabalha numa spec (etapas, gate, CI, PR), a sessão para uma sessão sem spec, a conversa para a VIBE e o Prompt. A semente dá a forma, a cor e o nome do robô (R9) e não muda entre sessões da mesma spec nem ao reabrir o app.
- R6 · **Ordem.** Os grupos (workspaces) com pedido ou erro sobem; dentro de um grupo, o que precisa de você vem primeiro, depois Em execução, Review e Backlog; empate pelo mais antigo.
- R7 · **Previsão da cota.** O app guarda em memória as leituras de uso da janela de 5 h (de `rate_limit_event` e do `/usage`) e calcula o ritmo das últimas leituras: "neste ritmo, acaba em 1 h 40" quando acaba antes de renovar, "dura até renovar às 14:00" quando não, "sem ritmo ainda" com menos de duas leituras. A semana mostra o uso e "renova seg. 09:00". O **peso na janela de 5 h** de uma sessão é a parte dela no custo das sessões da janela, vezes o uso da janela ("≈ 9%").
- R8 · **Pausar automáticos.** Um interruptor global, guardado em `app_settings`, que segura o Autopilot (o "Executar tudo" e o agendado não começam specs novas) e o Corrigir CI automático. Os turnos em andamento terminam; nada é parado. Despausar volta ao normal e o Autopilot confere a fila de novo. "Pausar após o turno" de uma sessão faz a spec não seguir para a próxima etapa quando o turno acabar.

### t2 · Robôs e o Quadro

- R9 · **`RobotAvatar`.** Cinco formas (antena, redondo, visor, cúpula, quadrado), as cores da paleta do app e um nome (Ada, Bruno, Caio…), escolhidos pela semente (R5). Desenhado com `CustomPainter` a partir do desenho do canvas (`viewBox` 40 × 46): corpo, braços, pernas, cabeça da forma, olhos, e as peças de cada estado.
- R10 · **Um estado por animação:**
  - **Backlog**, só na fila do Autopilot ou agendada: dormindo, olhos fechados, cinza, respirando, soltando "z z z";
  - **Em execução**, segue a ferramenta real: ler/Grep/Glob → olhos varrendo e lupa; Edit/Write → braços digitando e faíscas; Bash e testes → antena piscando e engrenagem girando; entre ferramentas → pensando, com o balão "…";
  - **Review**: esperando a sua revisão (prancheta), gate (lupa), Corrigir CI (chave inglesa), acompanhando o PR (olha para os lados);
  - **precisa de você**: acena (o único estado que acena);
  - **erro**, em qualquer coluna: caído, com fumaça.
  
  O piscar e o balanço variam um pouco por robô (velocidade e fase pela semente), para não andarem em sincronia.
- R11 · **Leve e respeitoso.** Com "reduzir movimento" do sistema (`MediaQuery.disableAnimations`) o robô fica parado na pose do estado, com as peças. Fora da tela (`TickerMode`) ou com a janela sem foco a animação para. Um ticker por robô, sem vazar ao sair da tela; `RepaintBoundary` em volta.
- R12 · **Sem robô no que não é agente nem no que acabou.** Release e servidor de dev têm ícone. Feito não tem robô nem animação (a coluna Feito do Quadro continua igual, só sem robôs).
- R13 · **O robô no card do Quadro.** No canto superior direito do card, com o nome embaixo (ou "na fila", "gate"). Um pedido do agente vira um **balão dentro do card**, com o texto do pedido e o botão ("quer executar `flutter test` · Responder"; "parou: overloaded · Retomar"). Clicar no robô abre a Atividades com a atividade selecionada.
- R14 · **A barra do Quadro** mostra "N agentes trabalhando · M precisam de você" do workspace, antes de "Agendar"; "M precisam de você" em âmbar e só quando M > 0.

### t3 · A tela Atividades

- R15 · **Menu.** Um item "Atividades" logo abaixo de Início, com um ícone de pulso e o selo contando o que precisa de você em **todos** os workspaces. Os atalhos Ctrl+1…0 ficam como estão; a Atividades fica na paleta (Ctrl K).
- R16 · **Cabeçalho.** Título, "Tudo o que está rodando agora, em todos os workspaces.", o cartão da cota (R7) e o botão "Pausar automáticos" / "Retomar automáticos" (R8), com a dica do que ele segura.
- R17 · **Abas**: Todas · Precisa de você · Backlog · Em execução · Review, cada uma com a contagem. "Agrupar por": Workspace (padrão) ou Nenhum.
- R18 · **A lista.** Colunas: atividade (robô ou ícone, selo do tipo — SPEC, VIBE, PR, RELEASE, DEV, PROMPT, PLANNER —, título, "agente · estado · etapa"), estado (rótulo; pedido em âmbar, erro em vermelho; barra quando há progresso, R4), tempo, última ação (mono), uso (chamadas). O cabeçalho de cada grupo: nome, total, "N precisa(m) de você" e, à direita, "Autopilot 2/3", "Corrigir CI automático" ou "agendado 09:00".
- R19 · **A ação na linha**: Responder (aprovação → a sessão, ou a conversa no Prompt), Ver plano (a conversa no Prompt), Retomar (sessão que falhou ou foi interrompida), Parar (agente, VIBE, servidor de dev, release, Corrigir CI; com confirmação para agente e VIBE), Agora (PR acompanhado: confere já).
- R20 · **O painel do selecionado**, à direita: robô grande, workspace e tipo, título, "agente · estado · há 42 min"; Agente (nome · modelo · modo), Branch, Tarefas (`t1 ✓ · t2 · t3`, a atual destacada), Neste turno (chamadas · arquivos), Peso na janela de 5 h; "Agora": as últimas ações com a hora e o último texto do agente. Botões: Abrir sessão, Mensagem…, Pausar após o turno, Parar. "Ver no Quadro" para uma atividade de spec.
- R21 · **Teclado e leitores de tela.** ↑/↓ mudam a seleção, Enter abre; cada linha anuncia "SPEC-075 Botões na largura, em execução, editando, 42 minutos"; estados nunca só pela cor.
- R22 · **Vazio.** Sem nada rodando: "Nada rodando agora." e o atalho para o Quadro.
- R23 · **De uma tela à outra.** Clicar no robô do card do Quadro abre a Atividades com a atividade selecionada; "Ver no Quadro" abre o workspace no Quadro com o card em foco.

## Fora do escopo

- Histórico do que terminou ("Concluídas hoje") e a coluna Feito na Atividades.
- Mudar o rodapé (ele continua com a cota e as contagens de hoje).
- Agrupar por estado ou por agente (só Workspace e Nenhum).
- Gráfico de consumo da cota por hora; a previsão é só o texto do ritmo.
- Robôs em outras telas (Sessões, Review, Início) e personalização do robô.
- Pausar ou parar várias atividades de uma vez, além do "Pausar automáticos".

## Design

Canvas validado: [Atividades](https://claude.ai/artifact/24NmtjoJLK9oUBrQbabjPK) (três artboards: a tela, o Quadro com robôs e o catálogo dos robôs).

### O que já existe

- `lib/features/home/tray_radar.dart` (SPEC-041): já junta, por workspace, as sessões rodando, os pedidos do Início e a release (`trayRadarProvider`). É o modelo do registro novo.
- `lib/features/home/home_inbox.dart`: `workspaceInboxProvider`, os pedidos de um workspace (aprovações, plano pronto, etapas paradas, PR com problema, sessões interrompidas).
- `lib/features/sessions/session_manager.dart`: `LiveSession` (vivo, aprovações, subagentes, `busySince`). Os eventos `AssistantMessage` e `ToolResult` já passam por `_handle`.
- `lib/features/prompt/conversation_manager.dart`: `LiveConversation` (vivo, ocupado, aprovações) das VIBEs e do Prompt.
- `lib/features/board/spec_runner.dart`: `gateRunningProvider` e `_advance` (a próxima etapa).
- `lib/features/review/pr_babysitter.dart` e `ci_fixer.dart` (SPEC-073): `PrBabysitter.watched`, `CiFixer` (fase, rodada, automático).
- `lib/features/repository/releases/release_dispatcher.dart`: `ReleaseRun` por workspace.
- `lib/core/dev/dev_server.dart`: `DevServerRegistry.servers`.
- `lib/features/project/project_planner.dart`: `PlannerActivity` por workspace.
- `lib/features/board/autopilot.dart`: `autopilotPlan` (o que o "Executar tudo" começa e o que espera) e `AutopilotSchedule`.
- `lib/core/claude/usage_tracker.dart`: `rateLimitProvider` (a última leitura da cota).
- `lib/ui/shell/navigation.dart` e `side_bar.dart`: o menu e os selos (`navBadgesProvider`).

### Componentes

- **`LiveSession`** ganha `tool` (ferramenta em uso, ou nenhuma = pensando), `recent` (últimas cinco ações), `calls`, `files` e `lastText` (R3).
- **`lib/features/activities/activity.dart`**: `Activity` (id, workspace, tipo, coluna, precisa de você, erro, pose, rótulos, progresso, início, última ação, uso, ação, sessão/conversa/spec, semente) e `ActivityPose`.
- **`buildActivities(...)`** (função pura) e **`activitiesProvider`** (todos os workspaces); `groupActivities` (R6) e `activityTabCount`.
- **`quota_forecast.dart`**: `QuotaSamples` (leituras em memória) e `quotaForecast` (função pura, R7); `sessionQuotaWeight`.
- **`automation_pause.dart`**: `automationPausedProvider` (R8), lido pelo `Autopilot._tick`/`scheduleTick` e pelo `_autoFixCi` do babysitter; `pauseAfterTurnProvider`, lido pelo `_advance`.
- **`lib/features/activities/widgets/robot_avatar.dart`**: `RobotAvatar(seed, pose, size)`, `RobotIdentity.of(seed)` e o `RobotPainter` (R9–R11).
- **`lib/features/activities/activities_screen.dart`** e `widgets/` (lista, linha, painel, cota) (R15–R23). `AppSection.activities`.
- No Quadro: `CardRobot` e `CardBalloon` no `SpecCard`, e a contagem no `_Header` (R13, R14).

Sem migração do banco: a pausa fica em `app_settings`, o resto em memória.

### Testes

- `buildActivities`: cada fonte vira a atividade certa (coluna, precisa de você, pose, ação); o que terminou some; Feito não aparece.
- Ordem: grupos com pedido ou erro sobem; dentro do grupo, precisa de você primeiro.
- `quotaForecast`: ritmo, "acaba em", "dura até renovar", sem leituras.
- Pausa: o Autopilot não começa spec com a pausa; o Corrigir CI automático não dispara; "Pausar após o turno" não avança a etapa.
- `RobotAvatar`: semente → mesma forma, cor e nome; estado → peças visíveis; reduzir movimento sem ticker ativo; sem tickers ao sair da árvore.
- Tela: abas e contagens, agrupamento e ordem, as ações de cada linha, o painel, o selo do menu, "Pausar automáticos".
- Quadro: robô no card de spec rodando, balão com Responder, sem robô em Feito, a barra com as contagens.

## Tarefas

| Tarefa | Entrega | Requisitos | Branch |
|---|---|---|---|
| t1 · Núcleo | O que o agente está fazendo (`LiveSession`), `Activity`, `buildActivities`, `activitiesProvider`, a previsão da cota, "Pausar automáticos" e "Pausar após o turno" | R1–R8 | `spec/076-t1-nucleo` |
| t2 · Robôs | `RobotAvatar` com as poses e animações, e o robô, o balão e a barra no Quadro | R9–R14 | `spec/076-t2-robos` |
| t3 · Tela | A tela Atividades, o item no menu com o selo, abas, lista, ações, painel e cota | R15–R23 | `spec/076-t3-tela` |

t2 e t3 dependem de t1; t3 usa o `RobotAvatar` da t2.

## Critérios de aceite

- [ ] Sessões, conversas, gate, PR acompanhado, Corrigir CI, release, planner, servidor de dev e a fila do Autopilot de todos os workspaces viram atividades, cada uma na coluna certa, e o que terminou some [R1, R2] verificar: flutter test test/features/activities/activity_test.dart
- [ ] A ferramenta em uso de uma sessão viva vira a pose do robô e a última ação [R3, R10] verificar: flutter test test/features/activities/activity_test.dart
- [ ] Grupos com pedido ou erro sobem e, dentro do grupo, o que precisa de você vem primeiro [R6] verificar: flutter test test/features/activities/activity_test.dart
- [ ] A cota mostra "neste ritmo, acaba em…" ou "dura até renovar" a partir das leituras [R7] verificar: flutter test test/features/activities/quota_forecast_test.dart
- [ ] "Pausar automáticos" segura o Autopilot e o Corrigir CI automático; "Pausar após o turno" não avança a etapa [R8] verificar: flutter test test/features/activities/automation_pause_test.dart
- [ ] O robô tem forma, cor e nome estáveis pela semente, uma pose por estado, fica parado com "reduzir movimento" e não vaza ticker [R9, R10, R11] verificar: flutter test test/features/activities/robot_avatar_test.dart
- [ ] O card do Quadro mostra o robô (nunca em Feito), o balão com o pedido e o botão, e a barra conta agentes trabalhando e pedidos [R12, R13, R14] verificar: flutter test test/features/activities/board_robots_test.dart
- [ ] A tela Atividades lista, agrupa, filtra pelas abas, age pela linha e mostra o painel do selecionado; o menu mostra o selo [R15–R22] verificar: flutter test test/features/activities/activities_screen_test.dart
- [ ] Clicar no robô do card abre a Atividades selecionada, e "Ver no Quadro" volta ao card [R23] verificar: flutter test test/features/activities/activities_screen_test.dart
- [ ] Com sessões reais do `claude` em dois workspaces, a Atividades e o Quadro mostram os robôs se mexendo conforme a ferramenta [R3, R10, R13] verificar: manual (app isolado com `XDG_DATA_HOME`, prints em `docs/mockups/spec-076/app/`)
- [ ] O projeto compila e a análise estática passa [R1–R23] verificar: flutter analyze

## Decisões

Decididas no canvas, com o usuário:

- P1 · **Nome.** **Decidido:** "Atividades". "Agentes" já é a tela dos subagentes, em Ferramentas.
- P2 · **O que entra.** **Decidido:** processos vivos, não o trabalho. Sem Feito e sem "Concluídas hoje"; o histórico é do Quadro e do Review.
- P3 · **Abas.** **Decidido:** Todas · Precisa de você · Backlog · Em execução · Review. Backlog é só a fila do Autopilot e as agendadas.
- P4 · **Robô em Feito.** **Decidido:** nenhum. A coluna Feito do Quadro fica como está.
- P5 · **Release e servidor de dev.** **Decidido:** ícone, não robô. Não são agentes.

Na implementação:

- P6 · **Atalho de teclado.** **Decidido:** a Atividades entra no menu logo abaixo de Início, mas fora de Ctrl+1…0. Pôr ela no Ctrl+2 empurraria todos os outros atalhos (e Ferramentas perderia o Ctrl+0). Fica na paleta (Ctrl K) e no selo.
- P7 · **Semente do robô.** **Decidido:** a spec, não a sessão, para tudo o que trabalha numa spec. Cada etapa abre uma sessão nova; com a sessão como semente, o robô do card mudaria a cada etapa.
- P8 · **Nome do robô.** **Decidido:** um nome próprio curto (Ada, Bruno…) tirado da semente, como no canvas. O nome do subagente (`agentName`), quando houver, aparece no painel ao lado do modelo.
- P9 · **"Parar" pede confirmação** para agente e VIBE (perde o turno em andamento); servidor de dev, release e Corrigir CI param direto.
- P10 · **"Pausar após o turno"** segura só a próxima etapa da spec (`_advance`); o gate das etapas que o agente marcou roda normalmente, porque faz parte do turno que terminou.
- P11 · **Etapa parada e sessão que falhou** contam como "precisa de você" (são o "Interrompidas" e "Precisam de resposta" do Início), porque o agente está parado esperando a pessoa.
- P12 · **Robôs no relógio ambiente.** **Decidido:** o `RobotAvatar` usa o `AmbientTicker` do app (24 Hz), o mesmo das ondas e dos spinners, e não um ticker a cada vsync. No Linux cada frame redesenha a janela inteira; um laço lento a 24 Hz parece igual e custa menos.
- P13 · **Review sem nada vivo no Quadro.** **Decidido:** o card em Review cuja sessão já terminou mostra o robô com a prancheta (esperando a sua revisão), como no canvas, mas não vira linha da Atividades: não há processo vivo.
- P14 · **Menu com onze itens.** **Decidido:** o espaço entre os itens do menu lateral cai de 4 para 2 px, para os onze itens caberem na janela mínima (1100 × 700).
- P15 · **Selo só com workspace aberto.** **Decidido:** sem nenhum workspace aberto o selo da Atividades não lê as listas (nada pode estar rodando).
