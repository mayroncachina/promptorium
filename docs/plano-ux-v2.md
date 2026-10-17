# Plano — UX v2 (mockups aprovados)

> Status: em execução (2026-10-17, branch `teste`). Fonte: [`docs/mockups/v2/`](mockups/v2/README.md)
> (canvas: https://claude.ai/artifact/2nALCRdzQV6oyfneUQZXxN) e [`docs/analise-ides/`](analise-ides/00-README.md).
> Uma **fase** = um commit; cada fase termina com `flutter analyze` limpo, testes passando e entrada no CHANGELOG.
> Nada aqui muda o schema do banco (v14) salvo onde indicado.

## Decisões

1. **Nada de novo no banco sem necessidade**: contadores, inbox e painéis derivam dos providers que já existem
   (`sessionManagerProvider`, `specStepsProvider`, `reviewQueueProvider`, `prBabysitterProvider`,
   `notificationsRepoProvider`).
2. **Barra lateral com 9 itens** (Ctrl+1…9): Início · Projeto · Specs · Quadro · Sessões · Review · Código ·
   Prompt · Ferramentas. `shortcutsVersion` sobe para 3 (aviso único).
3. **Telas não perdem o que já fazem**: diálogos antigos só saem quando a tela nova cobre o mesmo caminho
   (ex.: o diálogo "Etapas e sessões" do Quadro vira painel lateral; o diálogo de config do Projeto vira
   seção de Configurações).
4. **Cada fase tem um teste de widget** da tela nova com banco em memória (`test/helpers/test_db.dart`).

## Fases

| Fase | Tela (mockup) | Escopo |
|---|---|---|
| U1 | Início (`Main`) | `AppSection.home`; `HomeScreen` "Para você" (aprovações, precisam de resposta, aguardando review, PR com problema, interrompidas) + painel Agora (em execução, Autopilot, hoje, últimos avisos); contadores na barra lateral; nova ordem Ctrl+1…9 |
| U2 | Paleta e Atalhos (`Paleta`, `Atalhos`) | Ações pendentes (Aprovar/Negar/Responder) na paleta, grupos por prefixo `>` `#` `@` `:`, recentes; folha de atalhos Ctrl+/ |
| U3 | Sessões (`Sessoes`) | Lado a lado (2 painéis), linha ao vivo na lista, thinking recolhido (DT-20), custo do subagente, "Abrir preview" na porta do worktree |
| U4 | Prompt (`Prompt`) | Card "Plano pronto" com Implementar como sessão / Transformar em spec (DT-26); `@` `/` no composer de Sessões (DT-22) |
| U5 | Specs (`Specs`) | Painel de rastreabilidade por etapa (critérios, gate, design, commits, sessão) |
| U6 | Projeto (`Projeto`) | Aba Saúde (métricas, gate por spec, memória com autor, config detectada); "Analisar repositório" |
| U7 | Novo projeto (`NovoProjeto`, `Planejar`) | Tela Começar sem modal (3 origens, modelos de stack, criar sem planejar); proposta única (visão + stack + roadmap) com refinar em linha |
| U8 | Quadro (`Quadro`) | Painel lateral no cartão, atenção no topo da coluna, Backlog prontas/bloqueadas por onda, limite "3 / 3", barra segmentada, filtros |
| U9 | Configurações (`Configuracoes`) | Seções à esquerda (App × Workspace), busca, "alterado", efeito em linguagem simples, config do projeto migra para cá |

## Execução

| Fase | Commit | Diferenças em relação ao mockup |
|---|---|---|
| U1 | (ver git log) | "Aprovar todas as edições seguras" e "Histórico de avisos" do topo ficaram de fora (o segundo já é o sino da barra de título). Aprovações aparecem com o `ApprovalCard` das Sessões (Negar / Aprovar / Sempre permitir), não como linha simples. Início é a tela inicial só na primeira abertura; depois vale a última tela |
| U2 | (ver git log) | Sem o prefixo `@` (arquivos): a busca de arquivos continua no Ctrl+P da tela Código. Sem "Ctrl+Enter abrir ao lado" (depende da U3). A folha lista só atalhos que existem de fato |
