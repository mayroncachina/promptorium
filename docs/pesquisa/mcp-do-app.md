# Sonda prevista — MCP do app por HTTP local (SPEC-052)

> **Status: rodada.** CLI 2.1.325, haiku, 2026-11-13. Script: [`mcp-do-app.py`](mcp-do-app.py)
> (`python3 mcp-do-app.py claude youtrack`). Roda numa pasta temporária, longe dos hooks do
> projeto; seis execuções curtas (`SONDA_CENARIOS=perguntar,planejar` roda só as últimas). Todas as premissas da SPEC-052 se confirmaram.

## Montagem

Um servidor MCP mínimo em Python ([`mcp-do-app.py`](mcp-do-app.py)), em `127.0.0.1:<porta>`, com o transporte "Streamable HTTP": `initialize`, `tools/list` com `ler` (só leitura) e `criar` (escrita) e `tools/call`, que registra cada chamada num log. Ele exige `Authorization: Bearer <token>`.

O CLI roda como o app o roda (`-p --input-format stream-json --output-format stream-json --verbose --permission-prompt-tool stdio`), numa pasta temporária, com haiku. O `--mcp-config` aponta para um arquivo:

```json
{"mcpServers": {"promptorium": {"type": "http", "url": "http://127.0.0.1:<porta>/mcp",
  "headers": {"Authorization": "Bearer <token>"}}}}
```

## Perguntas

1. O CLI conecta com `type: http` e envia o cabeçalho? O `system/init` mostra `promptorium` com `status: connected` e quais `source`?
2. As ferramentas aparecem como `mcp__promptorium__ler` e `mcp__promptorium__criar` em `system/init.tools`?
3. `--allowedTools mcp__promptorium__ler` libera a leitura sem `can_use_tool`, e `criar` chega pelo `control_request` `can_use_tool` com o `input` completo, para a prévia?
4. Negar `criar` pelo stdio impede a chamada? (O log do servidor não pode registrá-la.)
5. Um `--settings` com `deniedMcpServers` de outros servidores, como o app já gera (SPEC-017), mantém o `promptorium`?
6. Com o token errado (401), o que o CLI mostra no `system/init` e na timeline, e a sessão segue?
7. Com `--dangerously-skip-permissions`, `criar` roda sem `can_use_tool`, como se espera em R8?
8. Com `--resume`, o servidor reconecta com o arquivo novo, que tem outro token?

## Se alguma resposta for "não"

- 1 ou 2: cair para stdio, com uma ponte pequena que repassa o JSON-RPC para o HTTP local. Isso muda P1 da SPEC-052.
- 3 ou 4: a escrita não pode depender da aprovação do CLI. Nesse caso, o servidor pede a confirmação ao app (P4 vira regra).
- 5: o arquivo de settings passa a listar só os servidores negados pelo nome, sem tocar no `promptorium`, o que já é o caso, e a sonda descobre o motivo.

## Resultado (CLI 2.1.325, 2026-11-13)

| # | Pergunta | Resposta |
|---|---|---|
| 1 | Conecta com `type: http` e envia o cabeçalho? | **Sim.** Todo POST chega com `Authorization: Bearer <token>`. O `system/init` mostra `{"name": "promptorium", "status": "connected", "source": "dynamic"}`: o `source` de um servidor de `--mcp-config` é `dynamic` (não `user`, `project`, `claudeai` nem `plugin`). |
| 2 | As ferramentas aparecem como `mcp__promptorium__<nome>`? | **Sim.** `system/init.tools` lista `mcp__promptorium__criar` e `mcp__promptorium__ler`. O modelo as carrega pelo `ToolSearch` (o primeiro `tool_result` é um `tool_reference` das duas), como as dos outros servidores MCP. |
| 3 | `--allowedTools` libera a leitura, e a escrita chega por `can_use_tool` com o `input` completo? | **Sim.** `ler` rodou sem `control_request`. `criar` chegou com `tool_name: mcp__promptorium__criar`, `input: {"titulo": "Sonda"}` e uma só sugestão: `addRules` / `allow` / `localSettings` com a regra da ferramenta. |
| 4 | Negar `criar` pelo stdio impede a chamada? | **Sim.** O `tool_result` é a mensagem da negação, e o log do servidor só tem `ler`. |
| 5 | `--settings` com `deniedMcpServers` de outro servidor mantém o `promptorium`? | **Sim.** Com `deniedMcpServers: [{"serverName": "youtrack"}]`, o `youtrack` some do init e o `promptorium` fica conectado. |
| 6 | Com o token errado (401)? | O `promptorium` aparece com `status: failed` e nenhuma ferramenta dele; a sessão segue normalmente, e o modelo diz que o servidor recusou o token. O CLI só tentou `initialize` (mais o `server/discover`, abaixo). |
| 7 | Com `--dangerously-skip-permissions`, `criar` roda sem `can_use_tool`? | **Sim.** As duas ferramentas rodaram sem `control_request` (R8, P4). |
| 8 | Com `--resume` e um arquivo novo (outro token), reconecta? | **Sim.** Com o token antigo já revogado no servidor, o `--resume` com o arquivo novo conectou e chamou `ler` com o token novo. |
| 9 | (extra) No modo Perguntar do app (`--tools` só de leitura, `--strict-mcp-config`), o `promptorium` funciona? | **Sim.** `--tools` só limita as ferramentas embutidas: `ler` aparece em `system/init.tools` e roda direto (sem `ToolSearch`, que não está na lista). Com `mcp__promptorium__criar` em `--disallowedTools`, ela some do init e a chamada volta "No such tool available"; o servidor não a recebe. `--strict-mcp-config` mantém os servidores de `--mcp-config`. |
| 10 | (extra) No modo Planejar (`--permission-mode plan`)? | A leitura em `--allowedTools` **ainda pede** `can_use_tool` (`ler` chegou sem sugestões), a menos que a ferramenta declare `annotations.readOnlyHint: true` no `tools/list`: aí ela roda direto (rodado de novo com `SONDA_READONLY=1`). A escrita fica bloqueada pelo próprio modo plan: o modelo propõe o plano, e só depois de aprovado o `ExitPlanMode` ele chama `criar`, que pede `can_use_tool` normalmente. |

Outros detalhes vistos:

- Além de `initialize`, `notifications/initialized`, `tools/list` e `tools/call`, o CLI manda um `server/discover` (JSON-RPC) logo no início. O servidor responde `-32601` (método desconhecido) e nada muda.
- Depois do `initialize`, o CLI abre um `GET` no mesmo caminho (o fluxo SSE opcional do transporte). Responder `405` basta: o servidor não precisa de SSE.
- Notificações (sem `id`) recebem `202` sem corpo.

**Decisão (SPEC-052):** P1 fica como está. No modo Perguntar, além de o servidor não listar a
escrita, o app põe as ferramentas de escrita em `--disallowedTools` (defesa em dobro) e soma as de
leitura a `--allowedTools` mesmo com "Permitido" ignorado nesse modo, porque elas não escrevem.
As ferramentas de leitura declaram `readOnlyHint: true` (senão o modo Planejar pede aprovação para
cada leitura), e as de escrita, `readOnlyHint: false` e `destructiveHint: false`. Em Planejar, a
escrita chega depois que a pessoa aprova o plano, o que combina com P3. O app serve o MCP por HTTP em `127.0.0.1`, com o token
no cabeçalho do arquivo de `--mcp-config`, a leitura em `--allowedTools` e a escrita pela aprovação
do stdio. A tela de Ferramentas reconhece o `promptorium` pelo `source: dynamic` ("Da sessão").
