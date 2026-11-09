# Sonda prevista — MCP do app por HTTP local (SPEC-052)

> **Status: prevista, ainda não rodada.** Roda antes da implementação da SPEC-052. Anotar aqui a versão do CLI, a data e o resultado de cada pergunta, como em [`plugins-mcp-desligados.md`](plugins-mcp-desligados.md).

## Montagem

Um servidor MCP mínimo em Python (`mcp-do-app.py`, a escrever), em `127.0.0.1:<porta>`, com o transporte "Streamable HTTP": `initialize`, `tools/list` com `ler` (só leitura) e `criar` (escrita) e `tools/call`, que registra cada chamada num log. Ele exige `Authorization: Bearer <token>`.

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
