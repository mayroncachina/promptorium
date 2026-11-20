---
id: SPEC-101
status: rascunho
versao: 0.23.0
tipo: funcionalidade
epico: 332
depende-de: [SPEC-095, SPEC-096, SPEC-097, SPEC-100]
---

# Executar spec com o Codex

## Objetivo

Levar uma spec do Backlog ao Review só com o Codex: **Executar** no Quadro, as etapas, os lotes, o gate, os reenvios, as correções automáticas, "Executar tudo" e o Autopilot, a continuação por contexto, a sessão de conflito, os commits marcados e as notificações. O provedor é escolhido no início e **fica fixo durante toda a execução da spec** (decisão 4 do épico #332). O que só existe no Claude Code aparece como **Só Claude Code** (decisão 1): Automático do Orquestrador, agentes `.claude/agents` e subagentes.

### O problema, com um exemplo

A pessoa está com o rodapé no Codex desde a 0.22, usando-o no Prompt e nas Sessões. No Quadro, ela clica em **Executar** na SPEC-031 · Pagamento com Stripe (3 etapas). Hoje:

1. O diálogo esconde o Codex no seletor de provedor (`codexEnabledProvider` em `run_spec_dialog.dart:473`), e a spec roda no Claude Code.
2. Se o provedor viesse do rodapé, `_runNext` usaria `runModel = 'inherit'`, e a etapa levaria `agent: spec.agentName ?? config.agent` e o bloco "Subagentes desta spec (chame-os pela ferramenta Agent/Task…)", que o Codex não tem.
3. Ao fim de R1, a etapa R2 iria para uma sessão nova, com a nota "só sessões do Claude continuam" (`_continueHere` em `spec_runner.dart`), mesmo com contexto de sobra.
4. O commit sairia com `Promptorium-Agente: inherit · etapa`, e o Autopilot somaria US$ 0 no orçamento do dia.

Depois desta spec, o diálogo mostra **Provedor: Codex**, o modelo `gpt-6.1-terra` do catálogo, o modo **Editar** e o Automático desabilitado com "Só Claude Code até o Orquestrador multi-provedor". R1, R2 e R3 rodam numa sessão do Codex no worktree da spec. R2 continua na mesma sessão porque o contexto medido está em 96 mil de 400 mil. O gate roda os testes, e um reenvio vai para a mesma thread. Os commits saem com `Promptorium-Agente: gpt-6.1-terra · etapa`. O card mostra o selo **Codex** junto do robô, e a spec chega ao Review.

## Requisitos

### Escolha e fixação do provedor

- R1 · **Codex no Executar.** O seletor de provedor do diálogo Executar mostra o Codex quando o fluxo "Executar spec" está liberado pelo interruptor por fluxo da SPEC-096 e o Codex está disponível e compatível (SPEC-094). O valor inicial segue a ordem da SPEC-100 R9: provedor da execução em andamento > tipo **Executar spec** em Modelo e consumo > rodapé > `claude`. A linha "Executar spec" do cartão Provedor por tipo passa a ser editável.
- R2 · **Provedor fixo por execução.** A execução da spec (do primeiro Executar até chegar ao Review, ou até a pessoa parar) grava o provedor escolhido. Todas as etapas, lotes, reenvios do gate, passos `REVn` do revisor, Corrigir CI e sessão de conflito usam esse provedor, mesmo que o rodapé ou o tipo mudem no meio. Para trocar de provedor, a pessoa usa **Passar para outro agente**, da SPEC-099, que encerra a sessão atual e abre uma nova com a transferência explícita. Ao reabrir o app, a execução continua no provedor gravado.
- R3 · **Modelo e esforço do Codex.** O modelo vem do `model/list` (via SPEC-094), com o padrão de `codex.model.session` e `codex.effort.session`. O valor `inherit` deixa de ser usado como modelo de execução. As escolhas do Claude (`sonnet`, `opus`, `haiku`, `max`) nunca chegam ao Codex, e o diálogo só lista modelos e esforços do provedor selecionado.
- R4 · **Modos de acesso.** O diálogo oferece os modos do Codex conforme a decisão 3: **Editar** (`workspace-write` com confirmação) é o padrão, e **YOLO** só aparece quando a execução tem worktree (SPEC-007). Perguntar e Planejar não executam etapas e não aparecem. O modo vale para a execução inteira, e as correções automáticas que hoje trocam o modo do Claude (`ciFixMode`, sair do `plan`) usam o equivalente no Codex.

### O que é só do Claude Code

- R5 · **Automático do Orquestrador.** Com o Codex selecionado, a aba Automático fica desabilitada com a etiqueta "Só Claude Code" e a dica "o Orquestrador escolhe modelos do Claude; com o Codex, as etapas rodam no modo Manual". Isso dura até a SPEC-109 (Orquestrador multi-provedor). Se "Abrir Executar em Automático" estiver ligado e o tipo Executar spec estiver no Codex, o "Executar tudo" e o Autopilot rodam em Manual com o Codex, e a timeline registra o motivo uma vez.
- R6 · **Agentes e subagentes.** Com o Codex, a etapa não leva `agent` nem o bloco de subagentes do prompt (`subagentPlan`), conforme a decisão 7. O campo Agente do diálogo aparece desabilitado com "Só Claude Code", e a timeline da sessão anota uma vez: "O agente spec-implementer e os subagentes desta spec são só do Claude Code; o Codex executa sem eles". O resto do prompt da etapa (spec, etapas, testes, memória do projeto, tentativa anterior, decisões) é o mesmo nos dois provedores.
- R7 · **Duelo e escalada.** O duelo de uma etapa (SPEC-035 R20) roda os dois lados no provedor da execução. Comparar Claude × Codex é a SPEC-108. "Refazer etapa" mantém o provedor e, no Codex, o modelo da última sessão da etapa.

### As etapas no Codex

- R8 · **Sessão por etapa no worktree.** Cada sessão de etapa é uma sessão Codex da SPEC-096: worktree da spec, `writableRoots` com o diretório git comum (para o commit funcionar no sandbox), ambiente do worktree (`PROMPTORIUM_*`, porta), aprovações no balão do card, interromper e retomar. Se o sandbox recusar o commit, a timeline mostra "O sandbox do Codex bloqueou o commit" com o comando e o caminho, e a etapa para como falha recuperável, em vez de seguir sem commit.
- R9 · **Gate, reenvio e correções.** O gate roda a suíte do projeto como hoje, sem depender do provedor. O reenvio após um gate reprovado, os passos `REVn` pedidos pelo revisor e as mensagens do Corrigir CI vão para a sessão Codex da spec (`CodexRun.send`). Quando a sessão já foi encerrada, eles abrem uma sessão nova no mesmo provedor, com o mesmo prompt de hoje.
- R10 · **Continuar na mesma sessão pelo contexto.** A regra "só sessões do Claude continuam" sai. A decisão de continuar a próxima etapa na mesma sessão (SPEC-017 R4) usa a leitura de contexto neutra (`ContextReading`, da SPEC-095) da sessão Codex, vinda do `ThreadTokenUsage`. O limite configurado em Execução de specs vale nos dois provedores e, no Codex, fica limitado a 70% da janela que o modelo informa (P2). Sem leitura, a nota continua "sem medição do contexto".
- R11 · **Commits marcados.** O trailer da SPEC-048 usa o modelo efetivo da thread (`gpt-6.1-terra · etapa`), nunca `inherit`. A SPEC-093 confirma se o sandbox repassa `PROMPTORIUM_AGENTE` ao `git` (`shell_environment_policy`). Se não repassar, o app passa a variável pelo override de ambiente do Codex. Se ainda assim faltar, a timeline avisa "commits desta etapa sem o trailer do agente" e não inventa o trailer depois.
- R12 · **Vigia de segredos.** Enquanto os hooks do Codex não estiverem ativos (SPEC-103), vale o modo pós-turno da SPEC-085 R2: commits conferidos ao fim de cada turno e bloqueio no push feito pelo app. O aviso da timeline continua uma vez por sessão.
- R13 · **Sessão de conflito.** "Abrir sessão de resolução" (SPEC-092) abre a sessão no provedor da execução da spec. Para PR sem spec, o provedor vem do tipo Sessões.

### Autopilot, uso e avisos

- R14 · **Executar tudo e Autopilot.** Usam o tipo Executar spec para specs novas e o provedor gravado (R2) para specs já começadas. O limite de specs em paralelo vale para a soma dos dois provedores. O orçamento do dia em US$ (`orcamento-dia`) conta só as sessões com custo informado. No Codex, o freio é a cota (P3): quando a janela de 5 h do Codex passa de 90% ou o Codex informa limite atingido, o Autopilot não começa novas specs no Codex e notifica "Autopilot parado: cota do Codex em 92%". Os turnos em andamento terminam.
- R15 · **Provedor no Quadro, nas Atividades e nas notificações.** O card em execução mostra o selo **Codex** ao lado do robô (SPEC-076). O robô e a semente da spec continuam os mesmos, e o selo diz quem trabalha. A linha da tela Atividades, o balão de pedido do card, as notificações de pedido e de fim ("Pronta para review") e o histórico da spec dizem o provedor e o modelo. Uma spec só com sessões Claude continua sem selo.
- R16 · **Uso por spec.** O custo por spec (SPEC-081) soma tokens dos dois provedores e mostra US$ só para o que tem custo informado: "Claude US$ 1,84 · Codex 412 mil tokens (custo indisponível)". As sessões Codex da spec entram no ledger com origem e etapa, como as do Claude.

## Fora do escopo

- Orquestrador com modelos do Codex e troca de provedor por cota: SPEC-109.
- Comparar Claude × Codex na mesma etapa: SPEC-108.
- Agentes `.claude/agents` traduzidos para o Codex: SPEC-106.
- Hooks nativos no Codex (bloquear comandos, formatar, vigia antes do commit): [SPEC-103](SPEC-103-hooks-gerenciados-nos-dois-provedores.md).
- Escolher o provedor do revisor: [SPEC-102](SPEC-102-review-automatico-com-o-codex.md). Aqui, os passos `REVn` só seguem o provedor da execução.
- Trocar de provedor no meio da execução sem a transferência explícita da SPEC-099.

## Decisões em aberto

- P1 · **Onde gravar o provedor da execução.** (a) chave `spec.<id>.provider` em `app_settings`, escrita no Executar e limpa quando a spec chega ao Review ou é rebobinada; (b) coluna nova em `specs`; (c) deduzir da última sessão, como hoje. **Recomendação: (a).** O comportamento de hoje (c) quebra quando a última sessão foi encerrada e a próxima é um passo `REVn` ou do Corrigir CI, e (b) pede uma migração para um dado que só vive enquanto a spec roda.
- P2 · **Limite de continuação no Codex.** (a) o mesmo número absoluto do Claude; (b) o número absoluto limitado a 70% da janela informada; (c) um campo próprio do Codex. **Recomendação: (b).** O limite padrão foi calibrado com a janela do Claude, e os modelos do Codex informam a própria janela no `ThreadTokenUsage`. Um segundo campo agora é configuração sem dado que a justifique.
- P3 · **Freio do Autopilot no Codex.** (a) parar novas specs Codex acima de 90% da janela de 5 h ou com limite atingido; (b) só com limite atingido; (c) usar a mesma regra de "Pausar automáticos". **Recomendação: (a).** Começar uma spec com 95% da cota quase certamente para no meio de uma etapa, e retomar uma etapa custa mais que esperar a janela renovar.
- P4 · **Execução começada no Claude e o tipo trocado para o Codex.** (a) a spec termina no Claude (R2); (b) perguntar no próximo Executar. **Recomendação: (a)**, com o diálogo mostrando "Esta spec está rodando no Claude Code. Para trocar, use Passar para outro agente". Perguntar a cada etapa vira atrito no Autopilot.

## Design

### Arquivos tocados

- `lib/features/board/widgets/run_spec_dialog.dart`: Codex no seletor via interruptor por fluxo; modelos e esforços do provedor; Automático e Agente com Só Claude Code; aviso do P4.
- `lib/features/board/spec_runner.dart`: `_runNext` (provedor gravado, modelo sem `inherit`, sem `agent` e sem subagentes no Codex), `_continueHere` (R10), `runAuto` (R5), rebobinar e "Refazer etapa" (R7), notas da timeline.
- `lib/features/board/autopilot.dart`: freio pela cota do Codex (R14).
- `lib/features/review/ci_fixer.dart`, `lib/features/review/conflict_resolution.dart`: provedor da execução e modo equivalente (R4, R9, R13).
- `lib/core/git/agent_trailer.dart`: modelo efetivo e override de ambiente (R11).
- `lib/features/board/widgets/` (card), `lib/features/activities/` e `lib/features/sessions/app_notifier.dart`: selo e texto do provedor (R15).
- `lib/features/cost/spec_cost.dart`: soma por provedor (R16).
- `lib/core/providers/provider_preferences.dart`: tipo Executar spec e chave `spec.<id>.provider` (P1).

### Migração

**Não**, se o P1 ficar com (a). As sessões já guardam `provider` e `externalId`.

### Dependências

- SPEC-095 (Eventos neutros): `ContextReading` da sessão Codex e cartões de edição na timeline da etapa.
- SPEC-096 (Codex no Prompt e nas Sessões): sessões Codex com worktree, `writableRoots`, aprovações, interromper, retomar e interruptor por fluxo.
- SPEC-097 (Cota do Codex no rodapé): cota do Codex para o freio do Autopilot e "custo indisponível".
- [SPEC-100](SPEC-100-execucoes-estruturadas-em-qualquer-provedor.md) (Execuções estruturadas): Decidir na etapa no Codex e cartão Provedor por tipo.
- SPEC-099 (Passar o trabalho entre agentes): a única forma de trocar de provedor no meio da execução (R2). Se ela atrasar, o diálogo só diz "pare a execução para trocar de provedor".
- Combina com a [SPEC-103](SPEC-103-hooks-gerenciados-nos-dois-provedores.md), que substitui o modo pós-turno do R12 quando os hooks estiverem ativos.

## Tarefas

- T1 · Provedor da execução (R1–R4, P1): seletor, gravação, modelo e esforço do Codex, modos. Verificar: testes do `spec_runner` com o `fake_codex` (provedor gravado entre etapas, rodapé trocado no meio, retomada após reabrir) e testes de widget do diálogo.
- T2 · Só Claude Code (R5–R7): Automático, Agente, subagentes, duelo e escalada. Verificar: testes do prompt da etapa (sem bloco de subagentes no Codex) e do `runAuto` com o tipo no Codex.
- T3 · Etapas no Codex (R8–R13): sessão no worktree, commit no sandbox, gate e reenvio, continuação por contexto, trailer, vigia pós-turno e conflito. Verificar: testes do `spec_runner`, do `ci_fixer` e do `conflict_resolution` com o `fake_codex`, e teste de continuação com e sem leitura.
- T4 · Autopilot, Quadro e uso (R14–R16). Verificar: testes do Autopilot com cota alta, de widget do card com o selo e do custo por spec misto.
- T5 · E2E no app isolado: uma spec de 3 etapas do Backlog ao Review com o Codex, com um gate reprovado e um reenvio. Verificar: capturas reais e relatório em `docs/pesquisa/`.

## Critérios de aceite

- [ ] O Codex aparece no Executar quando o fluxo está liberado, e o padrão vem do tipo Executar spec [R1] verificar: teste de widget do diálogo.
- [ ] Trocar o rodapé ou o tipo no meio não muda o provedor das próximas etapas, dos reenvios, do `REVn` e do Corrigir CI [R2, R9] verificar: teste do `spec_runner` com troca no meio.
- [ ] Nenhuma etapa no Codex recebe `inherit`, alias do Claude, `agent` ou o bloco de subagentes [R3, R6] verificar: testes das opções e do prompt enviados.
- [ ] YOLO só aparece com worktree, e as correções automáticas usam o modo equivalente no Codex [R4] verificar: testes de widget e do `ci_fixer`.
- [ ] Automático e Agente mostram Só Claude Code com o Codex, e o Autopilot com "Abrir em Automático" roda em Manual registrando o motivo [R5, R6] verificar: testes de widget e do `runAuto`.
- [ ] O commit da etapa funciona no sandbox do worktree, e uma recusa do sandbox para a etapa com mensagem clara [R8] verificar: teste com o `fake_codex` e e2e.
- [ ] A próxima etapa continua na mesma sessão Codex quando o contexto medido está abaixo do limite efetivo [R10] verificar: teste com leituras de `ThreadTokenUsage`.
- [ ] O trailer traz o modelo efetivo, e a falta da variável no sandbox gera aviso em vez de trailer inventado [R11] verificar: teste do trailer e e2e.
- [ ] O Autopilot para de começar specs Codex com a cota acima do limite e notifica [R14] verificar: teste do Autopilot.
- [ ] O card, as Atividades e as notificações mostram o provedor, e o custo por spec separa US$ e tokens [R15, R16] verificar: testes de widget.
- [ ] No app isolado, uma spec de 3 etapas vai do Backlog ao Review só com o Codex, com gate, reenvio e commits marcados [R1–R16] verificar: capturas reais 1366×768 e relatório.

## Telas

Mockup: [canvas do Claude Design](https://claude.ai/artifact/PsioN49HoSsD1oK6p5CVo8). Capturas em `docs/mockups/spec-101/`:

| PNG | O que mostra | Requisitos |
|---|---|---|
| `0-antes.png` | Hoje: o diálogo Executar sem o Codex no seletor, e a nota "R2 vai para uma sessão nova: só sessões do Claude continuam" | Problema |
| `1-executar-codex.png` | Diálogo Executar com Provedor Codex: modelo do catálogo, modo Editar, Automático e Agente com Só Claude Code | R1, R3–R6 |
| `2-quadro.png` | Quadro com o selo Codex no card, o balão de aprovação do Codex, o custo misto da spec e o Autopilot parado pela cota do Codex | R14–R16 |
| `3-sessao-etapa.png` | Sessão da etapa no Codex: continuação por contexto (96 mil de 400 mil), gate reprovado e reenvio na mesma thread, commit com o trailer e o aviso de agente Só Claude Code | R6, R8–R12 |
