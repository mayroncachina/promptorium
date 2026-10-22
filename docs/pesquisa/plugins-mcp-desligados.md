# Sonda — desligar plugins e servidores MCP só nas execuções do app (SPEC-017 R2)

CLI 2.1.308, haiku, 2026-10-22. Script: [`plugins-mcp-desligados.py`](plugins-mcp-desligados.py)
(`python3 plugins-mcp-desligados.py claude claude-mem@thedotmack youtrack`). Roda numa pasta
temporária, longe dos hooks do projeto; três chamadas de uma frase, custo desprezível.

O arquivo de `--settings` do cenário "settings":

```json
{"enabledPlugins": {"claude-mem@thedotmack": false},
 "deniedMcpServers": [{"serverName": "youtrack"}]}
```

| `system/init` | sem `--settings` | `--settings` acima | `--strict-mcp-config` |
|---|---|---|---|
| `plugins` | claude-mem + 3 `@builtin` | só os 3 `@builtin` | claude-mem + 3 `@builtin` |
| servidor `plugin:claude-mem:mcp-search` | sim (22 ferramentas) | **não** | não |
| servidor `youtrack` (usuário) | sim | **não** | não |
| servidor `context7` (usuário) | sim | sim | não |
| conector `claude.ai Claude Docs` | sim | sim | não |
| hooks `SessionStart` do plugin | 2 | **0** | 2 |

## Conclusões

- `enabledPlugins: {id: false}` num `--settings` (precedência "flag", acima das configurações do
  usuário) desliga o plugin inteiro só naquela execução: some da lista, o servidor MCP e as
  ferramentas dele somem e os hooks não rodam.
- `deniedMcpServers` no mesmo arquivo tira um servidor do usuário pelo nome e mantém os demais,
  inclusive os conectores do claude.ai. O app não precisa ler nem repassar a definição dos servidores
  (o `claude mcp get` mostraria o `env`, com chaves de API).
- `--strict-mcp-config` não serve para isso: derruba todos os servidores, inclusive os de plugin, e
  mantém os hooks do plugin.
- No `system/init`, os servidores do usuário aparecem como `pending` (conectam depois); o campo
  `source` diz a origem: `user`, `project`, `claudeai` ou `plugin`.

**Decisão (SPEC-017 R2):** um arquivo de settings por execução, com `enabledPlugins` e
`deniedMcpServers`, passado em `--settings`; nada de `--strict-mcp-config` para desligar servidores.
