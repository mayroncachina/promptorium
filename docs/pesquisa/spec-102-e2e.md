# SPEC-102 · E2E do review automático com o Codex no app isolado

Data: 22/11/2026. Build release da branch `spec/102-review-automatico-codex`, Xephyr `:6` a 1366×768, `XDG_DATA_HOME` num diretório do scratchpad. Os dados reais do usuário (`~/.local/share/promptorium`, `~/.codex`, `~/.claude`) não foram tocados.

## Sem turno pago

Nenhum turno real do Codex nem do Claude Code foi gasto. No `PATH` do app ficaram dois executáveis falsos:

- **Codex falso** (o mesmo da SPEC-100, em Python): responde à sondagem e ao App Server. No `turn/start` de um revisor (o `outputSchema` tem `veredito`), devolve a resposta preparada para a spec e a rodada, e manda um `thread/tokenUsage/updated` de 14,2 mil tokens. Cada pedido fica num log.
- **Claude Code falso**: responde à sondagem (`--version`, `--help`, `auth status --json`) e roda as sessões de etapa em stream-json. A cada mensagem, grava um arquivo no worktree, commita e devolve `ETAPA CONCLUÍDA: <etapas>`.

O workspace de teste é `loja-api`, com a SPEC-031 · Pagamento com Stripe e a SPEC-029 · Exportar pedidos em CSV. O projeto tem `.claude/agents/spec-reviewer.md`.

**Estado montado.** Executar spec no Codex é a SPEC-101, ainda não entregue. Por isso a execução da SPEC-031 no Codex foi montada no banco isolado: um worktree com o commit das 3 etapas, uma sessão `codex` concluída e a spec no Review. Também foi montada uma falha anterior do revisor no Claude Code ("Execute claude auth login…"). A SPEC-029 rodou de verdade pelo app, com o Claude Code falso.

## Resultado

| # | Fluxo | O que se viu | Print |
|---|---|---|---|
| 0 | Falha do provedor (R2) | A rodada que falhou no Claude Code mostra **Revisar com o Codex desta vez**. A falha não aprova a spec e o app não troca de provedor por conta própria | `app/0-falha-desta-vez.png` |
| 1 | Configuração do projeto (R1, R4, R6) | O grupo Revisor automático mostra Provedor (Mesmo da execução, O outro provedor, Claude Code, Codex), o modelo no Claude Code, o modelo no Codex (opcional), "US$ por rodada (só Claude Code)" e a nota do Codex. Ao escolher "O outro provedor" e salvar, o `config.yml` ganhou `provedor: outro` e `modelo-codex: "gpt-6.1-terra"` | `app/1-config-revisor.png` |
| 2 | SPEC-031 revisada pelo Codex (R5, R7, R8, R9) | O `thread/start` levou `sandbox: read-only`, `approvalPolicy: never`, `model: gpt-6.1-terra` e o revisor embutido em `developerInstructions`. Nenhum `haiku`, `maxBudgetUsd` ou `spec-reviewer` chegou ao Codex. A rodada diz "Rodada 1 · Revisor automático · Codex gpt-6.1-terra · aprovou · 3 comentários · a61f706", com o aviso do revisor do projeto uma vez. Os critérios 1 e 3 foram marcados pelo revisor | `app/2-review-codex.png` |
| 3 | Achados normalizados (R8) | O caminho absoluto do worktree virou `lib/pagamento/checkout_service.dart:9`, ancorado na linha do diff. O comentário duplicado entrou uma vez. `lib/pagamento/legado.dart`, fora do diff, virou comentário geral com o caminho no texto. O requisito R9, que não existe, ficou vazio | `app/3-ancorado-no-diff.png` |
| 4 | Prontidão do merge (R9) | Item Revisor automático: "OK · Codex · aprovou" | `app/4-prontidao-codex.png` |
| 5 | Executar a SPEC-029 (R2, R3) | O diálogo em Manual, com o Claude Code, mostra a linha Revisão: **Codex** `gpt-6.1-terra`, "segunda opinião · do config do projeto · provedor: outro" | `app/5-executar-segunda-opiniao.png` |
| 6 | Segunda opinião e REV1 (R9, R11) | A spec rodou no Claude Code falso. O Codex revisou ("pediu correções", 1 comentário em `exportacao.txt:1`). O passo `REV1` rodou numa sessão **claude**, e o Codex aprovou na rodada 2. O Review mostra as duas rodadas com "Codex gpt-6.1-terra · segunda opinião" | `app/6-review-segunda-opiniao.png` |
| 7 | Prontidão da segunda opinião | "OK · Codex · segunda opinião · aprovou" | `app/7-prontidao-segunda-opiniao.png` |
| 8 | Provedor por tipo (R4) | A linha Revisor automático mostra "do projeto: Mesmo da execução", os modelos (`Claude Code haiku · Codex gpt-6.1-terra`) e o link **Configuração do projeto**, que abre a seção. Nenhuma escolha fica guardada no cartão | `app/8-provedor-por-tipo.png` |

No banco isolado, cada linha de veredito ganhou `provider = codex` e `model = gpt-6.1-terra`. As linhas de comentário ficaram sem autoria, e a falha anterior ficou com `provider = claude`.

## Achados corrigidos durante o E2E

- Uma rodada repetida "desta vez" depois de uma falha tem o mesmo número da falha. O título da rodada passou a usar a linha do veredito, e o contador de comentários ignora a linha da falha.
- Os campos do grupo Revisor automático não cabiam numa linha. As larguras foram reduzidas.

## Limites conhecidos

- **Executar spec no Codex (SPEC-101).** Até a SPEC-101, "Mesmo da execução" usa o provedor da última sessão da spec. A SPEC-101 grava o provedor da execução e pode trocar `executionProviderOf` pela leitura desse valor.
- **Severidade fora do enum.** No Codex, a resposta é validada contra o schema antes do normalizador. Uma severidade fora de `alta`, `media` e `baixa` derruba a rodada como "fora do schema", como em qualquer execução estruturada. A regra do normalizador vale para respostas que passam pela validação, e o teste unitário cobre esse caso.
- **Sandbox.** Nesta máquina, o sandbox real do Codex não sobe (decisão 15). O app recusa a rodada estruturada no Codex quando a sondagem acusa isso. A falha aparece no Review com o motivo, e o botão oferece o Claude Code desta vez.
