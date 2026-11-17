---
id: SPEC-080
status: aprovada
versão: 0.20.0
tipo: recurso
depende-de: SPEC-076
issue: 274
---

# Retomar de onde parei

## Objetivo

Com o Autopilot, o Corrigir CI automático e vários workspaces, o app trabalha enquanto a pessoa está longe. Ela fecha o notebook às 19h com três specs na fila e volta às 9h. Ou sai para almoçar com uma etapa rodando. Na volta, a pergunta é sempre a mesma: **o que aconteceu enquanto eu estava fora, e o que eu faço primeiro?**

Hoje a resposta está espalhada. A Atividades (SPEC-076) mostra só o que **ainda** está vivo: o que terminou some da lista. O Início mostra os pedidos, mas não o que andou. O PR mergeado está no Review, o CI no card do Quadro, a release no Repositório, e o sino de notificações tem um pouco de tudo, sem ordem nem ação. Para remontar a manhã, a pessoa abre cinco telas em dois workspaces.

Exemplo: às 19h42 de ontem, o `loja-api` tinha a SPEC-077 em execução e a SPEC-078 e a SPEC-079 na fila do Autopilot. Durante a noite, a SPEC-077 terminou e passou no gate, o PR #267 foi mergeado no GitHub, o CI do PR #270 falhou e o Corrigir CI automático tentou duas vezes, a SPEC-078 parou pedindo para rodar `flutter test`, e a release v0.18.0 do `promptorium-site` foi publicada. Às 9h, a pessoa quer ver isso tudo num lugar só, com um botão para cada coisa.

Esta spec cria o **cartão "Retomar de onde parei"**:
- aparece **ao abrir o app** e **ao voltar** depois de um tempo fora;
- mostra, de todos os workspaces, o que **espera por você**, o que **terminou** enquanto você estava fora (PRs mergeados, CI, gates, releases, specs concluídas) e o que **continua rodando**, com o robô de cada agente;
- cada item tem **uma ação direta** (Responder, Revisar, Corrigir CI, Ver release, Abrir);
- o app passa a guardar um **diário curto** do que terminou e a hora em que você foi visto pela última vez.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/WSsmky38kLxdN4Za4GKUhP). Capturas em `docs/mockups/spec-080/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-ao-abrir.png` | O app aberto de manhã: o cartão sobre o Início, com "Espera por você", "Terminou" e "Continua rodando", os robôs e as ações | R1–R9 |
| `2-ao-voltar.png` | De volta depois de 47 min com o app aberto: o cartão compacto no canto, sobre o Quadro, e o mesmo cartão expandido | R2, R10, R11 |
| `3-inicio.png` | Depois de fechar: a faixa "Desde a sua última visita" no topo do Início, com o que ainda não foi resolvido | R12, R13 |
| `4-configuracoes.png` | Configurações › Retomar de onde parei: quando mostrar, o tempo fora, o que entra e o "visto por último" | R14, R15 |

Issue: [#274](https://github.com/mayroncachina/promptorium/issues/274) (sub-issue de [#278](https://github.com/mayroncachina/promptorium/issues/278))

## Requisitos

### Quando você está "fora"

- R1 · **Visto por último.** O app guarda a hora em que você foi visto: a última vez em que a janela estava em foco **e** recebeu uma tecla, um clique ou uma rolagem. A hora vai para `app_settings` (`resume.lastSeenAt`), gravada no máximo uma vez por minuto enquanto você usa o app, ao tirar o foco da janela e ao fechar o app.
- R2 · **O que conta como fora.** Você esteve fora quando:
  - **abriu o app** e o visto por último tem 30 min ou mais; ou
  - **voltou à janela** (ela ganhou foco, ou recebeu uma tecla ou um clique) depois de 30 min ou mais sem foco ou sem nenhuma tecla, clique ou rolagem.
  
  O limite é configurável (15 min, 30 min, 1 h, 2 h; R14). Fora do app aberto, contam o tempo sem foco e o tempo parado em foco (a pessoa saiu com o app na frente). O cartão só aparece se houver pelo menos um item (R4); sem nada, a volta é silenciosa.

### O que o cartão mostra

- R3 · **Todos os workspaces.** O cartão junta os workspaces abertos no app, como a Atividades. Cada item mostra o workspace em cinza ("loja-api") quando há mais de um.
- R4 · **Três grupos, nesta ordem:**
  - **Espera por você**: o que a Atividades marca como "precisa de você" agora (aprovação, pergunta, plano pronto, etapa parada, erro), mais os pedidos do Início que não são atividades (PR com problema, review pendente, sessão interrompida);
  - **Terminou enquanto você estava fora**: os eventos do diário (R6) entre o visto por último e agora, do mais novo para o mais antigo;
  - **Continua rodando**: as atividades que estão em execução ou em Review agora, com o robô na pose atual e há quanto tempo rodam.
  
  Um grupo vazio não aparece. Com mais de 6 itens num grupo, os 6 primeiros aparecem e "+ 4 em Terminou" abre a lista inteira no próprio cartão.
- R5 · **Cada item:** o robô do agente (a mesma semente da SPEC-076 R5) ou o ícone (release, servidor de dev, PR sem spec), o selo do tipo (SPEC, PR, CI, GATE, RELEASE, VIBE, PROMPT), o título, uma linha do que aconteceu ("passou no gate · R1–R4", "mergeado por mayroncachina", "falhou em `test` · Corrigir CI tentou 2 vezes"), a hora ("23:14", "ontem 21:02") e **uma ação**.
- R6 · **O diário.** O app passa a registrar, por workspace, quando:
  - uma **spec** termina uma etapa, passa ou falha no **gate**, vai para Review ou é concluída;
  - um **PR** é aberto, **mergeado** (pelo app ou no GitHub) ou fechado sem merge;
  - o **CI** de um PR acompanhado passa ou falha, e o **Corrigir CI** termina (corrigiu ou desistiu);
  - uma **release** é publicada ou falha;
  - uma **sessão**, **VIBE** ou **conversa do Prompt** termina um turno longo (mais de 2 min) ou para com erro;
  - o **Autopilot** começa uma spec da fila ou termina a fila.
  
  Cada registro tem o tipo, o resultado (ok, falhou, atenção), o título, o detalhe, a semente do robô, a referência (spec, sessão, conversa, PR, release) e a hora. Registros com mais de 14 dias são apagados ao abrir o app.
- R7 · **O que aconteceu com o app fechado.** Ao abrir, antes de montar o cartão, o app confere no GitHub (`gh pr view`) os PRs abertos das specs e os PRs acompanhados, e registra no diário os que foram mergeados ou fechados e o CI que terminou desde o visto por último, com a hora do GitHub. Sem rede ou sem `gh`, o cartão mostra o resto e uma linha "Não deu para conferir o GitHub agora." com **Tentar de novo**.
- R8 · **Um item por coisa.** Eventos da mesma spec, PR ou release se juntam no mais recente, com o resto na linha de detalhe: "SPEC-077 · passou no gate e foi para Review · PR #267 mergeado" vira um item. O que já está em "Espera por você" não se repete em "Terminou".

### Agir

- R9 · **A ação de cada item:**

  | Item | Ação |
  |---|---|
  | aprovação ou pergunta | **Responder** (a sessão ou a conversa) |
  | plano pronto | **Ver plano** |
  | etapa parada, sessão interrompida | **Retomar** |
  | erro | **Ver erro** (a sessão, no ponto do erro) |
  | gate passou, spec em Review | **Revisar** (o Review da spec) |
  | gate falhou | **Ver gate** (o relatório) |
  | PR mergeado | **Ver no Quadro** (o card em Feito) |
  | CI falhou | **Corrigir CI** (o fluxo da SPEC-073) ou **Ver CI** quando o Corrigir CI já está rodando |
  | CI passou | **Abrir PR** |
  | release publicada | **Ver release** |
  | release falhou | **Ver log** |
  | continua rodando | **Abrir** (a Atividades com a atividade selecionada) |
  
  A ação leva ao workspace do item (troca o workspace ativo, se preciso) e à tela certa. O item resolvido some do cartão. Fazer a ação não fecha o cartão, a não ser que ele fique vazio.

### Mostrar e fechar

- R10 · **Ao abrir: o cartão grande.** Sobre a tela que abrir (o Início, em geral), centrado no alto, com o título "Enquanto você esteve fora", "desde ontem 19:42 · 13 h" e a contagem por grupo. Não é modal: a tela continua usável por trás, o cartão fecha com Esc, com "Fechar" ou com **Tudo visto**. O foco do teclado vai para o primeiro item.
- R11 · **Ao voltar: o cartão compacto.** Com o app aberto, a volta mostra o cartão no canto superior direito, compacto: "Voltou? Em 47 min: 2 terminaram · 1 espera por você", com os robôs dos itens e **Ver**. Ver expande no cartão grande. Ele some sozinho depois de 20 s sem interação se não houver nada em "Espera por você"; com algo esperando, fica até ser fechado.
- R12 · **Desde a sua última visita, no Início.** Fechar o cartão sem "Tudo visto" deixa os itens não resolvidos numa faixa recolhível no topo do Início, "Desde a sua última visita · 5", até o próximo "Tudo visto" ou a próxima volta. "Tudo visto" esvazia a faixa e marca o diário como visto até agora.
- R13 · **Atividades e paleta.** A Atividades ganha o botão "O que aconteceu" no cabeçalho, que abre o cartão grande com o diário das últimas 24 h, mesmo sem ter estado fora. A paleta (Ctrl K) ganha "Retomar de onde parei".

### Configurar

- R14 · **Configurações › Retomar de onde parei.** Uma seção nova no grupo App das Configurações (`SettingsSection.resume`), logo depois de Sessões, achada pela busca por "retomar", "fora" e "visto":
  - **Mostrar ao abrir o app** (ligado);
  - **Mostrar ao voltar depois de** 15 min · 30 min · 1 h · 2 h · nunca (30 min);
  - **O que entra em "Terminou"**: specs e gates, PRs, CI, releases, sessões e conversas (todos ligados);
  - "Visto por último: hoje 09:12" e **Limpar o diário**.
- R15 · **Acessibilidade.** O cartão é uma região com título; cada grupo é uma lista com o nome e a contagem; cada item anuncia "SPEC-077 Copiar código, passou no gate, 23 horas e 14, Revisar". O resultado usa ícone e texto (✓, ✕, !), não só a cor. ↑/↓ andam pelos itens, Enter faz a ação. Com "reduzir movimento", os robôs ficam parados na pose.

## Fora do escopo

- Resumo escrito pelo Claude ("Durante a noite, o agente…"). O cartão é montado do diário, sem gastar cota.
- Notificação do sistema com o resumo (a SPEC-086 cuida da notificação com o robô).
- Mandar o resumo por e-mail, Slack ou celular.
- Histórico completo e pesquisável do diário (o diário guarda 14 dias e só aparece no cartão).
- Mudar a Atividades para mostrar o que terminou (ela continua só com o que está vivo, SPEC-076 P2).
- Detectar "fora" pelo bloqueio de tela ou pela inatividade do sistema operacional.

## Decisões em aberto

- P1 · **O que conta como "fora".** Opções: (a) só o app fechado; (b) a janela sem foco; (c) sem foco **ou** sem nenhuma tecla, clique ou rolagem no app. **Decidido:** **(c), com 30 min** (R2). Sem foco sozinho não pega quem sai com o app na frente; a ociosidade do sistema operacional exigiria código nativo.
- P2 · **Onde guardar o visto por último.** **Decidido:** **`app_settings`** (`resume.lastSeenAt`), uma hora só para o app, não por workspace. A pessoa é uma, e o cartão junta os workspaces. Gravar no máximo uma vez por minuto evita escrever no banco a cada tecla.
- P3 · **De onde vem o "Terminou".** Opções: (a) uma tabela nova de diário, escrita quando as coisas terminam; (b) montar na hora a partir das tabelas que existem (sessões com `endedAt`, `step_runs`, specs); (c) reaproveitar as notificações. **Decidido:** **(a)** mais a conferência do GitHub ao abrir (R7). A (b) não sabe de CI nem de PR mergeado fora do app, e a (c) não tem workspace, tipo nem ação, e encheria o sino.
- P4 · **Cartão modal ou não.** **Decidido:** **não modal** (R10). A pessoa pode querer olhar o Quadro por trás antes de decidir; Esc fecha e a faixa do Início guarda o resto.
- P5 · **Ao voltar com o app aberto: cartão grande ou compacto.** **Decidido:** **compacto no canto** (R11), que expande. Um cartão grande a cada volta do almoço cansa.
- P6 · **Quanto tempo o diário guarda.** **Decidido:** **14 dias**. Cobre um fim de semana longo e férias curtas sem crescer o banco.
- P7 · **Juntar eventos.** **Decidido:** **um item por spec, PR ou release** (R8), com o resto no detalhe. Três linhas da mesma spec escondem as outras.
- P8 · **Contar a fila do Autopilot em "Continua rodando".** **Decidido:** **não**; a fila aparece numa linha só ("Autopilot: 2 specs na fila"), sem item por spec, para o cartão não repetir a Atividades.

## Design

Canvas para validar: [Retomar de onde parei](https://claude.ai/artifact/WSsmky38kLxdN4Za4GKUhP). Quatro artboards de 1366 × 768: ao abrir, ao voltar, a faixa do Início e as configurações.

### O que já existe

- `lib/features/activities/` (SPEC-076): `Activity`, `buildActivities`, `activitiesProvider` (todos os workspaces), `ActivityPose`, `ActivityAction`, `activity_actions.dart` (Responder, Retomar, Parar…) e `widgets/robot_avatar.dart` (`RobotAvatar`, `RobotIdentity.of(seed)`).
- `lib/features/home/home_inbox.dart` (`workspaceInboxProvider`, os pedidos) e `tray_radar.dart` (junta os workspaces).
- `lib/features/review/pr_babysitter.dart` e `ci_fixer.dart` (SPEC-073): PR acompanhado, CI, Corrigir CI.
- `lib/features/board/spec_runner.dart` (etapas, gate) e `autopilot.dart`.
- `lib/features/repository/releases/release_dispatcher.dart` (`ReleaseRun`).
- `lib/core/git/gh_cli.dart` (`gh pr view` com `state` e `mergedAt`).
- `lib/data/repos/app_settings_repo.dart` (`AppSettingKeys`), `lib/data/db/app_database.dart` (`appSchemaVersion = 28` na main).
- `window_manager` (foco da janela) e o `AppLifecycleState` já usado pelo robô.
- `lib/ui/shell/app_shell.dart`: o que roda depois do splash (`_checkUpdate`, a release retomada).

### Componentes

- **Tabela `ActivityEvents`**: `id`, `workspaceId` (FK, cascade), `kind` (spec, gate, pr, ci, release, session, conversation, autopilot), `outcome` (ok, failed, attention), `title`, `detail`, `seed`, `specId`, `sessionId`, `conversationId`, `prNumber`, `releaseTag`, `groupKey` (para juntar, R8), `at`.
- **`lib/data/repos/activity_events_repo.dart`**: `add`, `since(at)`, `purgeOlderThan`.
- **`lib/features/resume/`**:
  - `presence.dart`: `PresenceTracker` (foco, entrada, `lastSeenAt`, "voltou depois de X", R1, R2);
  - `activity_journal.dart`: escreve no diário a partir das transições (o fim de uma atividade em `activitiesProvider`, os ganchos do gate, do babysitter, do Corrigir CI, da release) (R6);
  - `github_catch_up.dart`: a conferência dos PRs e do CI ao abrir (R7);
  - `resume_summary.dart`: `buildResumeSummary(...)` (função pura: grupos, junção, ordem, ação de cada item, R4, R5, R8, R9);
  - `widgets/resume_card.dart` (grande e compacto, R10, R11), `widgets/since_last_visit.dart` (a faixa do Início, R12) e `resume_settings.dart` (R14).
- Ganchos: `spec_runner.dart`, `pr_babysitter.dart`, `ci_fixer.dart`, `release_dispatcher.dart`, `autopilot.dart` chamam o diário.

### Migração

Sim. **v30** (a v29 ficou com `snippets`, da SPEC-078): cria a tabela `activity_events` e o índice `(workspace_id, at)`. Atualizar `drift_schemas/`, `schema_versions.dart` e o teste de migração. O visto por último e as preferências ficam em `app_settings` (sem migração).

### Arquivos tocados

- `lib/data/db/app_database.dart`, `app_database.g.dart`, `schema_versions.dart`, `drift_schemas/drift_schema_v30.json`
- `lib/data/repos/activity_events_repo.dart` (novo), `app_settings_repo.dart`, `lib/data/providers.dart`
- `lib/features/resume/` (novo)
- `lib/features/board/spec_runner.dart`, `autopilot.dart`, `lib/features/review/pr_babysitter.dart`, `ci_fixer.dart`, `lib/features/repository/releases/release_dispatcher.dart`, `lib/features/sessions/session_manager.dart`, `lib/features/prompt/conversation_manager.dart` (ganchos do diário)
- `lib/features/home/home_screen.dart` (a faixa), `lib/features/activities/activities_screen.dart` ("O que aconteceu")
- `lib/ui/shell/app_shell.dart` (presença e o cartão), `command_palette.dart`
- `lib/features/settings/settings_sections.dart`
- `test/features/resume/`, `test/data/migration_test.dart`

### Testes

- `PresenceTracker`: abrir com o visto por último antigo; voltar depois de 30 min sem foco; parado em foco; gravar no máximo uma vez por minuto.
- `buildResumeSummary`: grupos e ordem; juntar por spec/PR/release; o que espera não se repete em Terminou; ação de cada tipo; mais de 6 itens.
- Diário: cada gancho registra o evento certo; apagar com mais de 14 dias.
- GitHub ao abrir: PR mergeado entra com a hora do GitHub; sem `gh`, a linha "Tentar de novo".
- Cartão: grande ao abrir, compacto ao voltar, some sozinho só sem pedidos; Esc fecha; Tudo visto marca o diário; a faixa do Início fica com o resto.
- Configurações: desligar "ao abrir"; mudar o limite; tirar um tipo de "Terminou".

## Critérios de aceite

- [x] O visto por último é gravado com foco e entrada, no máximo uma vez por minuto, e a volta depois do limite é detectada ao abrir e com o app aberto [R1, R2] verificar: flutter test test/features/resume/presence_test.dart
- [x] O cartão junta os workspaces em Espera por você, Terminou e Continua rodando, com robô, detalhe, hora e uma ação por item [R3, R4, R5, R9] verificar: flutter test test/features/resume/resume_summary_test.dart
- [x] O diário registra gate, PR, CI, release, sessões longas e o Autopilot, e apaga o que tem mais de 14 dias [R6] verificar: flutter test test/features/resume/activity_journal_test.dart
- [x] Ao abrir, PRs mergeados e CI terminados no GitHub entram no diário com a hora do GitHub [R7] verificar: flutter test test/features/resume/github_catch_up_test.dart
- [x] Eventos da mesma spec, PR ou release viram um item, e o que espera não se repete [R8] verificar: flutter test test/features/resume/resume_summary_test.dart
- [x] O cartão grande ao abrir e o compacto ao voltar, não modais; Tudo visto e a faixa do Início [R10–R12] verificar: flutter test test/features/resume/resume_card_test.dart
- [x] "O que aconteceu" na Atividades e "Retomar de onde parei" na paleta abrem o cartão [R13] verificar: flutter test test/features/resume/resume_card_test.dart
- [x] Configurações › Retomar de onde parei liga, desliga, muda o limite e os tipos [R14] verificar: flutter test test/features/settings/resume_settings_test.dart
- [x] A tabela `activity_events` é criada na v30 [R6] verificar: flutter test test/data/migration_test.dart
- [x] No app, com uma spec rodando no Autopilot, fechar, mergear o PR no GitHub e reabrir mostra o cartão com o merge, o que espera e o que roda, e cada ação leva à tela certa [R1–R15] verificar: manual (app isolado com `XDG_DATA_HOME`, prints em `docs/mockups/spec-080/app/`)
- [x] O projeto compila e a análise estática passa [R1–R15] verificar: flutter analyze
