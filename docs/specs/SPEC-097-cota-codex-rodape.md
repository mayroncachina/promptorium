---
id: SPEC-097
status: rascunho
versao: 0.22.0
tipo: melhoria
epico: 332
issue: 349
depende-de: [SPEC-094, SPEC-095]
---

# Cota do Codex no rodapé

## Objetivo

Saber quanto resta do plano do ChatGPT enquanto usa o Codex, do mesmo jeito que o rodapé já mostra a cota do Claude Code. E nunca mostrar US$ onde o Codex não informa custo (decisão 5 do épico).

Exemplo concreto: com o Codex selecionado no rodapé, a régua "Uso 5h · Semana" some (`footer_stats.dart` só lê `rateLimitProvider` quando o provedor é `claude`). A pessoa não sabe se o próximo turno vai bater no limite. E, quando uma sessão do Codex termina, o ledger grava `costUsd: 0`, então o Custo por spec (SPEC-081) mostra "US$ 0,00" para um trabalho que gastou 1,2 milhão de tokens, e o ranking coloca essa spec como a mais barata.

O App Server do Codex já entrega tudo o que falta: `account/rateLimits/read` (janelas primária e secundária com `usedPercent`, `resetsAt` e duração, tipo de plano, créditos e uma visão por limite) e a notificação `account/rateLimits/updated` durante as execuções. Nenhum dos dois gasta turno.

## Requisitos

### Ler a cota

- R1 · **Leitura sem turno.** O app lê `account/rateLimits/read` ao abrir (com o Codex disponível e logado), a cada 5 minutos enquanto o app estiver aberto e o Codex for o provedor ativo ou tiver uma execução viva, e ao clicar em "Atualizar" no detalhe da cota. A leitura usa um `codex app-server` de vida curta (`initialize` → `account/rateLimits/read` → encerra), ou o processo de uma execução viva quando houver. Nunca abre `thread/start` nem `turn/start`.
- R2 · **Durante as execuções.** `account/rateLimits/updated` chega como `QuotaEvent` (SPEC-095 R5) e é **mesclado** à última leitura: campo ausente não apaga o valor anterior, como pede o protocolo.
- R3 · **Guardada por provedor.** A última leitura do Codex fica em `app_settings` (`codex.lastRateLimit`), separada da do Claude (`lastRateLimit`), com a hora da leitura. Uma janela cujo `resetsAt` já passou aparece como renovada, como o `planWindowExpired` já faz para o Claude.
- R4 · **Falha não trava nada.** Sem login, sem rede ou com erro do App Server, o rodapé mostra "cota indisponível" com o motivo na dica e mantém a última leitura identificada pela hora. A leitura nunca bloqueia a abertura do app nem uma execução.

### Mostrar

- R5 · **Rodapé do provedor ativo.** Com o Codex ativo, a régua mostra as janelas do Codex com o rótulo pela duração (`300` min → "Uso 5h", `10080` min → "Semana"; outra duração → "Janela de N h"). O bucket mostrado é o `codex` de `rateLimitsByLimitId` quando houver; senão, o `rateLimits` principal. Com o Claude ativo, nada muda.
- R6 · **Detalhe da cota.** Clicar na régua abre um painel com **Claude Code e Codex lado a lado**: plano (`planType` como "ChatGPT Plus", "Pro"…), cada janela com a porcentagem, "renova às HH:mm" ou "renova seg. 09:00", créditos quando informados (`hasCredits`, `balance`, ilimitado), os outros buckets de `rateLimitsByLimitId` com o nome, e "lido às HH:mm · Atualizar". Um provedor sem leitura mostra "sem leitura ainda".
- R7 · **Limite atingido.** `rateLimitReachedType` ou `usedPercent` em 100 deixa a régua do Codex em vermelho com "limite atingido · renova às HH:mm" e o tipo em palavras ("limite do plano", "créditos do workspace esgotados"). Uma execução nova do Codex nessas condições avisa antes de começar, com a opção explícita de usar o Claude; nunca troca sozinho (decisão 4). `ordinaryUsageAllowed` nulo não é interpretado como liberado.

### Custo e tokens

- R8 · **Ledger sabe o provedor.** `usage_entries` ganha `provider` e `tokensReasoning`. Um turno do Codex grava os tokens (`inputTokens`, `cachedInputTokens`, `outputTokens`, `reasoningOutputTokens`) e **custo indisponível** (nunca 0 como se fosse medido).
- R9 · **"Custo indisponível", nunca US$ 0.** Onde o app mostra custo (painel da sessão, painel da conversa, Custo por spec, ranking, Atividades), uma execução do Codex mostra "custo indisponível" e os tokens. Uma spec com etapas nos dois provedores mostra "US$ 4,20 (Claude Code) + 1,2 mi tokens (Codex)". O ranking por custo ordena só o que tem custo e lista as specs só com tokens à parte, sem fingir zero.
- R10 · **Peso na janela.** O peso de um turno do Claude na janela de 5 h continua pela régua de custo (SPEC-081 R4). Para o Codex, o peso fica "indisponível" nesta spec (ver P3).

## Fora do escopo

- Estimar US$ para o Codex por tabela de preço da API (decisão 5).
- Trocar de provedor automaticamente quando a cota acaba (SPEC-109, Orquestrador multi-provedor).
- `account/usage/read` e o histórico diário de tokens da conta.
- Consumir créditos de renovação (`account/rateLimitResetCredit/consume`) pelo app.
- Previsão "neste ritmo, acaba em…" para o Codex nas Atividades (P2).

## Decisões em aberto

- P1 · **Intervalo da leitura.** **Recomendação:** 5 minutos com o Codex ativo ou rodando, e nenhuma leitura periódica com o Codex parado e o Claude ativo. O processo de vida curta custa pouco, mas não precisa rodar à toa.
- P2 · **Previsão nas Atividades.** A SPEC-076 calcula o ritmo da janela de 5 h só com o Claude. **Recomendação:** levar o Codex para a mesma função (`quotaForecast`) quando o cartão de cota das Atividades ganhar seletor de provedor, numa spec futura; aqui só o rodapé e o detalhe.
- P3 · **Peso do Codex na janela.** Dá para estimar pela diferença de `usedPercent` entre leituras antes e depois de um turno, mas outras execuções no mesmo período contaminam a conta. **Recomendação:** "indisponível" agora; reavaliar com dados reais depois do MVP.
- P4 · **Detalhe com os dois provedores mesmo com um só instalado.** **Recomendação:** mostrar só os provedores detectados; com um só, o painel fica igual ao de hoje mais o plano e a hora da leitura.
- P5 · **Nome do plano.** **Recomendação:** traduzir os `planType` conhecidos ("plus" → "ChatGPT Plus", "pro" → "ChatGPT Pro", "team" → "Team"…) e mostrar o valor cru para os outros.

## Design

### O que já existe

- `lib/core/claude/usage_tracker.dart`: `rateLimitProvider` (última leitura do Claude, persistida em `app_settings`) e `planWindowExpired`.
- `lib/core/claude/usage_poller.dart`: `claude -p "/usage"` sem gastar turno.
- `lib/ui/shell/footer_stats.dart` e `status_footer.dart`: `FooterStats` (`usage5h`, `usageWeek`, limite atingido), régua `_UsageBar`; a cota só aparece com o provedor `claude`.
- `lib/features/cost/usage_ledger.dart`, `spec_cost.dart`, `widgets/spec_cost_section.dart`, `widgets/spec_cost_ranking.dart` (SPEC-081): ledger e custo por spec, com `costUsd` padrão 0.
- `lib/core/codex/codex_provider.dart`: `thread/tokenUsage/updated` com `total` e `last`.
- `QuotaEvent` (SPEC-095 R5).

### Arquivos tocados

| Arquivo | Mudança |
|---|---|
| `lib/core/providers/quota_source.dart` | Novo: `QuotaSnapshot` por provedor, leitura e mescla |
| `lib/core/codex/codex_quota.dart` | Novo: App Server de vida curta para `account/rateLimits/read`, tradução para `QuotaSnapshot` |
| `lib/core/claude/usage_tracker.dart` | Passa a alimentar o `quota_source` com a leitura do Claude |
| `lib/ui/shell/footer_stats.dart`, `status_footer.dart` | Régua do provedor ativo, limite atingido, abrir o detalhe |
| `lib/ui/shell/quota_detail.dart` | Novo: painel com os dois provedores |
| `lib/data/db/app_database.dart` | `usage_entries.provider`, `usage_entries.tokensReasoning` |
| `lib/features/cost/usage_ledger.dart`, `spec_cost.dart`, `widgets/*` | Custo indisponível, total misto, ranking sem zero falso |
| `lib/features/sessions/widgets/side_panel.dart`, `lib/features/prompt/widgets/prompt_side_panel.dart` | "Custo indisponível" + tokens |

**Migração do banco:** sim. `usage_entries.provider` (texto, padrão `claude`, preenchido nas linhas existentes) e `usage_entries.tokensReasoning` (inteiro, padrão 0), na próxima versão do schema. Entradas existentes continuam com o custo que têm.

### Dependências

- SPEC-094 (capacidade `quota` e `costUsd` por provedor; versão mínima) e SPEC-095 (`QuotaEvent`).
- Não depende da SPEC-096: a leitura de cota funciona com o Codex logado, mesmo sem nenhum fluxo liberado. O custo indisponível só aparece quando houver execuções do Codex.
- Destrava a SPEC-109 (Orquestrador multi-provedor desvia pela cota).

## Tarefas

| Tarefa | Entrega | Requisitos |
|---|---|---|
| T1 · Leitura | `quota_source`, `codex_quota`, mescla de atualizações, persistência, falhas | R1–R4 |
| T2 · Rodapé e detalhe | Régua do provedor ativo, painel lado a lado, limite atingido | R5–R7 |
| T3 · Custo | Migração do ledger, "custo indisponível", total misto e ranking | R8–R10 |

## Critérios de aceite

- [ ] Abrir o app com o Codex logado lê a cota sem abrir thread nem turno; o intervalo de 5 minutos só corre com o Codex ativo ou rodando [R1] verificar: `flutter test test/core/codex/codex_quota_test.dart` com o `fake_codex` conferindo os métodos chamados.
- [ ] `account/rateLimits/updated` parcial não apaga campos da leitura anterior [R2] verificar: teste da mescla.
- [ ] A leitura do Codex sobrevive a reiniciar o app e aparece como renovada depois do `resetsAt` [R3] verificar: teste do `quota_source`.
- [ ] Sem login ou com erro, o rodapé mostra "cota indisponível" com o motivo e a leitura antiga com a hora [R4] verificar: teste de widget do rodapé.
- [ ] Com o Codex ativo, a régua mostra "Uso 5h" e "Semana" do bucket `codex`; com o Claude, nada muda [R5] verificar: `flutter test test/ui/provider_footer_test.dart`.
- [ ] O detalhe mostra os dois provedores com plano, janelas, renovação, créditos e hora da leitura [R6] verificar: teste de widget do `quota_detail`.
- [ ] Limite atingido deixa a régua vermelha com a renovação, e uma execução nova do Codex avisa antes sem trocar de provedor [R7] verificar: testes do rodapé e da Nova sessão.
- [ ] Um turno do Codex grava provedor, tokens (com raciocínio) e custo indisponível; a migração preenche `claude` nas linhas antigas [R8] verificar: teste do ledger e teste de migração.
- [ ] Nenhuma tela mostra "US$ 0,00" para execução do Codex; spec mista mostra o total misto e o ranking não põe a spec só com tokens como a mais barata [R9] verificar: testes de `spec_cost` e dos widgets de custo.

## Telas

Canvas: [SPEC-097 · Cota do Codex no rodapé](https://claude.ai/artifact/5ZUZtmcXhPKqyoTHENyb8G)

| PNG | O que mostra | Requisitos |
|---|---|---|
| `docs/mockups/spec-097/0-antes.png` | Antes: Codex ativo sem régua de cota no rodapé e Custo por spec com "US$ 0,00" para uma spec feita no Codex | — |
| `docs/mockups/spec-097/1-rodape-e-detalhe.png` | Rodapé com a cota do Codex e o detalhe aberto: Claude Code e Codex lado a lado, plano, janelas, renovação, créditos, hora da leitura e "Atualizar" | R1, R5, R6 |
| `docs/mockups/spec-097/2-custo-indisponivel.png` | Custo por spec com "custo indisponível · 1,2 mi tokens" no Codex, o total misto e o ranking com as specs só com tokens à parte | R8–R10 |
| `docs/mockups/spec-097/3-limite-atingido.png` | Limite do Codex atingido: régua vermelha com a renovação, aviso antes de uma sessão nova com a opção explícita de usar o Claude, e "cota indisponível" sem login | R4, R7 |
