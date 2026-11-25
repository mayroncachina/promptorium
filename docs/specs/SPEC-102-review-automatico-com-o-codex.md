---
id: SPEC-102
status: concluida
versao: 0.24.0
tipo: funcionalidade
epico: 332
issue: 347
depende-de: [SPEC-094, SPEC-097, SPEC-100]
---

# Review automático com o Codex

## Objetivo

Deixar o revisor automático (`lib/features/review/auto_reviewer.dart`) rodar no Codex, além do Claude Code, com o **provedor do revisor escolhido à parte**. O padrão é revisar com o mesmo provedor da execução da spec, mas a pessoa pode pedir o outro provedor como **segunda opinião**. Os apontamentos chegam ao Review no mesmo formato de hoje: veredito, resumo, critérios atendidos e comentários ancorados no diff. Cada rodada passa a dizer quem revisou.

### O problema, com um exemplo

A SPEC-031 · Pagamento com Stripe terminou as 3 etapas no Codex (SPEC-101) e vai para o Review com o revisor ligado (`revisor: ligado: true, modelo: haiku, orcamento: 0.30`). Hoje:

1. Em Manual, `_review` chama `runReadOnlyClaude` com `providerId: null`, e o provedor vem do rodapé. Se for o Codex, a rodada leva `maxBudgetUsd: 0.30` e `model: 'haiku'` e falha ao iniciar. A spec vai para "O revisor automático falhou" sem nenhum apontamento.
2. Se o projeto tem `.claude/agents/spec-reviewer.md`, a rodada também leva `agent: 'spec-reviewer'`, que o Codex não tem (decisão 7).
3. Em Automático, o revisor fica fixo no Claude (`providerId: 'claude'`), sem a pessoa poder escolher.
4. A rodada no Review diz só "Rodada 1 · Revisor automático · pediu correções". Não dá para saber se quem revisou foi o Claude ou o Codex.

Depois desta spec, o projeto tem `revisor: provedor: execucao`. A SPEC-031, executada no Codex, é revisada pelo Codex com `gpt-6.1-terra` e o schema atual. O Review mostra "Rodada 1 · Revisor automático · Codex gpt-6.1-terra · pediu correções · 3 comentários", com cada comentário ancorado na linha do diff. Com `provedor: outro`, a mesma spec seria revisada pelo Claude Code, e a rodada diria "Claude Code haiku · segunda opinião".

## Requisitos

### Provedor do revisor

- R1 · **Escolha no config do projeto.** O bloco `revisor:` do `.promptorium/config.yml` ganha `provedor:`, com os valores `execucao` (padrão), `outro`, `claude` e `codex`. Ele fica no config porque o time inteiro compartilha a regra de revisão, como já acontece com `modelo` e `rodadas`. Em Configuração do projeto, o grupo Revisor automático ganha o campo **Provedor**, com as opções "Mesmo da execução", "O outro provedor (segunda opinião)", "Claude Code" e "Codex". Um config sem `provedor:` se comporta como `execucao`, o que mantém o comportamento atual para quem só usa o Claude.
- R2 · **Resolução.** `execucao` usa o provedor gravado da execução da spec (SPEC-101 R2). Se a spec rodou só com sessões Claude, resolve para `claude`. `outro` usa o provedor que não executou a spec. `claude` e `codex` fixam o provedor. "Rodar revisor" num PR sem spec (SPEC-050 R6) usa o provedor da sessão do PR para `execucao` e `outro`. Se o provedor resolvido estiver indisponível, a rodada não troca de provedor: ela falha com o motivo e oferece "Revisar com o Claude Code desta vez" (ou o Codex), como na SPEC-100 R11. A falha nunca aprova a spec.
- R3 · **Automático do Orquestrador.** Uma spec executada em Automático (SPEC-035) continua revisada pela regra Revisão do plano, que é do Claude, até a SPEC-109. A exceção é um `provedor:` explícito (`claude`, `codex` ou `outro`) no config, que vence a regra do plano. O diálogo Executar mostra a linha Revisão com o provedor resolvido, e a etiqueta "do config do projeto" quando o config decide.
- R4 · **Modelo por provedor.** O `modelo:` atual vale para o Claude. Para o Codex, entra `modelo-codex:`, opcional. Sem ele, o modelo vem de `codex.model.reviewer` e, na falta, do modelo do tipo Revisor (SPEC-094), lido do `model/list`. Um alias do Claude nunca chega ao Codex (SPEC-100 R4). A linha Revisor do cartão Provedor por tipo (SPEC-100 R9) mostra o valor resolvido do projeto ativo e leva à Configuração do projeto, sem guardar uma segunda escolha.

### A rodada no Codex

- R5 · **Mesma rodada, mesmo schema.** A rodada usa `runStructured` (SPEC-100) com o `reviewerSchema` atual, o prompt atual (`reviewerPrompt` ou `prReviewerPrompt`) e o diff da branch contra a base, já limitado a `maxDiff`. No Codex, o sandbox é `read-only`, com aprovação `never`, e o agente pode ler os arquivos do worktree, como no Claude. O veredito é lido por `ReviewerVerdict.parse`, sem mudança. O `review/start` nativo do Codex fica fora desta entrega (P1).
- R6 · **Limite.** `orcamento:` (US$ por rodada) vale só para o Claude. No Codex, o limite é o tempo-limite do revisor (10 min) com `turn/interrupt` (SPEC-100 R5). Configuração do projeto mostra "US$ por rodada (só Claude Code)" ao lado do campo.
- R7 · **Revisor do projeto.** Com o Codex, o arquivo `.claude/agents/spec-reviewer.md` não é usado (decisão 7): a rodada usa o revisor embutido (`builtinReviewerPrompt`). O Review anota uma vez por spec: "O revisor do projeto (.claude/agents/spec-reviewer.md) é só do Claude Code; esta rodada usou o revisor embutido do Promptorium". Traduzir o agente para o Codex é a SPEC-106.

### Achados normalizados

- R8 · **Normalização dos comentários.** Antes de gravar, cada comentário passa por um normalizador comum aos dois provedores:
  - o caminho vira relativo à raiz do worktree, sem `./`, `a/` ou `b/` e sem o caminho absoluto;
  - um arquivo fora do diff vira comentário geral, com o caminho no texto;
  - uma linha fora dos trechos do diff do arquivo vira comentário do arquivo (linha 0);
  - severidade fora de `alta`, `media` e `baixa` vira `media`;
  - um requisito que não existe na spec fica vazio;
  - comentários duplicados na mesma rodada (mesmo arquivo, linha e texto) entram uma vez só.

  A ancoragem no diff continua a de `comment_anchor.dart` (SPEC-009). Um índice de critério fora da lista é ignorado, como hoje.
- R9 · **Quem revisou.** Cada rodada grava o provedor e o modelo efetivo do revisor. O Review mostra a autoria no título da rodada ("Rodada 2 · Revisor automático · Codex gpt-6.1-terra · aprovou · 9f3c2a1"), no painel do PR importado e no item Revisor automático da prontidão do merge (SPEC-073). Rodadas antigas, sem o dado, continuam como hoje. Quando o revisor é o outro provedor, a rodada leva a etiqueta "segunda opinião".
- R10 · **Uso e cota.** A rodada entra no ledger como hoje (origem `revisor`, etapa `rodada N`), com tokens e custo nulo no Codex (SPEC-097). O custo por spec separa US$ e tokens, como na SPEC-101 R16.
- R11 · **Correções seguem a execução.** Um veredito `corrigir` cria o passo `REVn` como hoje. Esse passo roda no provedor da **execução** da spec (SPEC-101 R2), não no provedor do revisor. A segunda opinião do Codex numa spec do Claude gera um `REVn` que o Claude corrige.

## Fora do escopo

- `review/start` e `codex review` nativos como motor do revisor (P1).
- Duas revisões em paralelo, uma por provedor, com comparação dos achados: fica para a SPEC-108 (Comparar Claude × Codex).
- Agente revisor do projeto no Codex: SPEC-106.
- Escolha de provedor pelo Orquestrador: SPEC-109.
- Mudar o schema dos achados ou as regras do que o revisor deve pedir.

## Decisões

- P1 · **Motor da rodada no Codex.** (a) `runStructured` com o `reviewerSchema` atual; (b) `review/start` nativo, com alvo `baseBranch`, e um segundo turno para converter a resposta no schema; (c) `review/start` puro. **Decidido:** (a). O schema do 0.170 mostra que o `review/start` devolve o achado como texto livre (`exitedReviewMode.review` é uma string). Por isso (c) perde os critérios e a ancoragem, e (b) paga dois turnos por rodada. (a) mantém o mesmo veredito nos dois provedores. Reavaliar (b) depois da SPEC-093, se o texto nativo trouxer arquivo e linha confiáveis.
- P2 · **Padrão do `provedor:`.** (a) `execucao`; (b) `outro`. **Decidido:** (a). A segunda opinião gasta a cota do outro plano a cada rodada, e quem só tem um dos dois logado teria o revisor falhando por padrão. A opção fica a um clique em Configuração do projeto.
- P3 · **Onde gravar a autoria da rodada.** (a) colunas novas `provider` e `model` (anuláveis) em `review_comments`, na linha do veredito; (b) cruzar com o `usage_entries` da rodada; (c) prefixar no texto do resumo. **Decidido:** (a). Cruzar com o ledger (b) falha quando a rodada não grava uso, como no cancelamento, e o texto (c) não serve para filtrar nem para a SPEC-108. São duas colunas anuláveis numa migração pequena.
- P4 · **`modelo-codex:` no config do time.** (a) no config, como o `modelo:`; (b) só na preferência local (`codex.model.reviewer`). **Decidido:** (a), opcional. Quem quer revisor igual para o time inteiro já usa o `modelo:` no config, e sem `modelo-codex:` vale a preferência local.

## Design

### Arquivos tocados

- `lib/features/project/project_config.dart`: `ReviewerConfig.provider` e `codexModel`, leitura e escrita de `provedor` e `modelo-codex`.
- `lib/features/project/widgets/project_config_view.dart`: campo Provedor, `modelo-codex` e o rótulo "(só Claude Code)" no orçamento.
- `lib/features/review/auto_reviewer.dart`: resolução do provedor (R2, R3), `runStructured` (R5), agente do projeto (R7), normalizador (R8), autoria (R9).
- **Novo:** `lib/features/review/reviewer_findings.dart` (normalizador do R8, puro e testável).
- `lib/features/review/widgets/spec_review_panel.dart`, `imported_pr_panel.dart`, `merge_readiness.dart`: autoria e "segunda opinião" (R9).
- `lib/features/board/widgets/run_spec_dialog.dart` e `orchestrator/step_plan_list.dart`: linha Revisão com o provedor resolvido (R3).
- `lib/data/db/app_database.dart` e `review_comments_repo.dart`: colunas do P3.

### Migração

**Sim**, se o P3 ficar com (a): `review_comments.provider TEXT NULL` e `review_comments.model TEXT NULL`, com `schemaVersion` + 1, sem preencher linhas antigas.

### Dependências

- SPEC-094 (Capacidades e opções por provedor): modelo do tipo Revisor e capacidades (`budgetUsd`, `agentFiles`).
- SPEC-097 (Cota do Codex no rodapé): tokens com custo nulo no ledger.
- [SPEC-100](SPEC-100-execucoes-estruturadas-em-qualquer-provedor.md) (Execuções estruturadas): `runStructured` no Codex e a migração do `auto_reviewer.dart`.
- [SPEC-101](SPEC-101-executar-spec-com-o-codex.md) (Executar spec com o Codex): o provedor gravado da execução, usado por `execucao` e `outro` e pelo `REVn`. Sem a 101, `execucao` resolve para o provedor das sessões da spec.

## Tarefas

- T1 · Config e resolução (R1–R4, P2, P4): `provedor`, `modelo-codex`, Configuração do projeto, regra do Automático e linha Revisão do Executar. Verificar: testes do `ProjectConfig` (ler e gravar), de widget da Configuração do projeto e da resolução para cada valor.
- T2 · Rodada no Codex (R5–R7): `runStructured`, limite e revisor embutido no lugar do agente do projeto. Verificar: testes do `AutoReviewer` com o `fake_codex` (aprovar, corrigir, JSON inválido, tempo-limite) e teste de que nenhum `agent` ou `maxBudgetUsd` chega ao Codex.
- T3 · Normalizador e autoria (R8–R11, P3): `reviewer_findings.dart`, migração, Review, painel do PR e prontidão. Verificar: testes unitários do normalizador (cada regra do R8), teste da migração e testes de widget da rodada com e sem autoria.
- T4 · E2E no app isolado: uma spec executada no Codex e revisada pelo Codex, e outra executada no Claude com `provedor: outro`. Verificar: capturas reais e relatório em `docs/pesquisa/`.

## Critérios de aceite

- [x] `provedor:` é lido e gravado no config, e a ausência dele mantém o comportamento atual [R1] verificar: testes do `ProjectConfig` e de um config antigo.
- [x] Cada valor de `provedor:` resolve o provedor certo para spec e PR sem spec, e o provedor indisponível falha sem aprovar e sem trocar em silêncio [R2] verificar: testes da resolução e da falha.
- [x] Em Automático, a regra do plano vale, salvo `provedor:` explícito no config [R3] verificar: teste do `AutoReviewer` com plano.
- [x] Nenhum alias do Claude, `agent` ou `maxBudgetUsd` chega ao Codex [R4, R6, R7] verificar: teste das opções enviadas.
- [x] A rodada no Codex usa o schema atual e grava veredito, critérios e comentários como no Claude [R5] verificar: testes com o `fake_codex`.
- [x] O projeto com `spec-reviewer.md` revisado no Codex usa o revisor embutido e mostra o aviso uma vez [R7] verificar: teste do `AutoReviewer` e de widget.
- [x] Caminho absoluto, arquivo fora do diff, linha fora do trecho, severidade inválida e duplicatas são normalizados [R8] verificar: testes unitários do normalizador.
- [x] Cada rodada nova mostra provedor e modelo, e as rodadas antigas continuam legíveis [R9] verificar: teste da migração e testes de widget.
- [x] O `REVn` de uma segunda opinião roda no provedor da execução [R11] verificar: teste do `spec_runner` com revisor e execução em provedores diferentes.
- [x] No app isolado, uma spec é revisada pelo Codex com comentários ancorados no diff, e outra recebe a segunda opinião do outro provedor [R1–R11] verificar: capturas reais 1366×768 e relatório.

## Telas

Mockup: [canvas do Claude Design](https://claude.ai/artifact/PQFynop9PbwkFTnZNkyqGv). Capturas em `docs/mockups/spec-102/`:

| PNG | O que mostra | Requisitos |
|---|---|---|
| `0-antes.png` | Hoje: o Review com "O revisor automático falhou: Falha ao iniciar codex" e a rodada sem autoria | Problema |
| `1-config-revisor.png` | Configuração do projeto, grupo Revisor automático: Provedor (Mesmo da execução, O outro provedor, Claude Code, Codex), `modelo-codex` e "US$ por rodada (só Claude Code)" | R1, R4, R6 |
| `2-review-codex.png` | Review da SPEC-031 com a rodada do Codex: autoria no título, comentários ancorados no diff, critérios marcados e o aviso do revisor do projeto Só Claude Code | R5, R7–R9 |
| `3-segunda-opiniao.png` | Executar com a linha Revisão "Claude Code · segunda opinião (do config do projeto)", a rodada no Review e o `REVn` no provedor da execução | R2, R3, R9, R11 |

## Implementação

- E2E: [`docs/pesquisa/spec-102-e2e.md`](../pesquisa/spec-102-e2e.md), com o Codex e o Claude Code falsos (sem turno pago) e os prints em `docs/mockups/spec-102/app/`.
- Migração: schema v36 (`review_comments.provider` e `review_comments.model`, anuláveis).
- Decisões além da spec:
  1. Sem a SPEC-101, "Mesmo da execução" usa o provedor da última sessão da spec (`executionProviderOf`). A 101 pode trocar essa leitura pelo provedor gravado da execução.
  2. A resolução fica num arquivo puro, `lib/features/review/reviewer_provider.dart`, usado pelo revisor, pelo Executar e pelo cartão Provedor por tipo.
  3. `StructuredIntent` ganhou `modelOverride`, o modelo de um provedor que não é o Claude Code. É por ele que o `modelo-codex` chega ao Codex. Um alias do Claude ou um modelo fora do catálogo em cache é pulado.
  4. Sem `modelo-codex` nem `codex.model.reviewer`, vale o modelo Codex do tipo Planner (o app não tem um tipo Revisor separado nas preferências de modelo).
  5. "Revisar com o … desta vez" aparece na rodada que falhou (Review da spec) e ao lado de "Rodar revisor" (PR sem spec). A falha grava o provedor que falhou, e a rodada repetida mantém o número da falha, com o veredito no título.
  6. O aviso do revisor do projeto (R7) aparece uma vez na seção Rodadas, quando alguma rodada rodou fora do Claude Code num projeto com `.claude/agents/spec-reviewer.md`.
  7. No Codex, a resposta é validada contra o schema antes do normalizador. Por isso uma severidade fora do enum derruba a rodada como "fora do schema"; a regra do R8 vale para o que passa pela validação.

