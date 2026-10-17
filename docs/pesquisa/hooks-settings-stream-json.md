# Sondas — hooks via `--settings`, controle da sessão viva e `--tools`

CLI 2.1.302, haiku, 2026-10-17. Scripts: [`hooks-settings-stream-json.py`](hooks-settings-stream-json.py)
e [`controle-sessao-viva.py`](controle-sessao-viva.py). As duas custaram menos de US$ 0,02.

## 1. Hooks de um `--settings` temporário em `-p --input-format stream-json`

`settings.json` com `PreToolUse` (matcher `Bash`), `PostToolUse` (`Write|Edit|MultiEdit`), `Stop` e
`SessionEnd`, todos chamando o mesmo script, que lê o evento no stdin.

| Pergunta | Resultado |
|---|---|
| `PreToolUse` dispara em `-p` stream-json? | Sim. O evento traz `tool_name`, `tool_input`, `cwd`, `permission_mode`, `session_id`, `transcript_path`. |
| `permissionDecision: deny` bloqueia? | Sim. A chamada não roda; o `tool_result` chega com `is_error: true` e o texto `PreToolUse:Bash hook error: <motivo>`. O agente leu o motivo e não tentou contornar. |
| `PostToolUse` dispara? | Sim, depois do `Write` (traz `tool_response` e `duration_ms`). O `additionalContext` **não** aparece no stream. |
| `Stop` com `decision: block` | Funciona **dentro do mesmo turno**: o agente recebe `Stop hook feedback:\n<motivo>`, continua e só então sai um único `result`. Na segunda vez o evento traz `stop_hook_active: true`. O evento traz `last_assistant_message`. O stream ganha um `system/notification` `stop-hook-error`. |
| `SessionEnd` | Dispara ao fechar o stdin, com `reason`. |
| Os hooks do usuário continuam? | Sim: os `SessionStart` do `~/.claude` rodaram junto (as fontes se somam). |
| Aparecem no stream? | Só `SessionStart` gera `system/hook_started` e `system/hook_response`. Os eventos de ferramenta não geram nada próprio: o app lê o que o hook fez num arquivo de log. |

**Decisão (F2):** os hooks do app (bloquear comandos, formatar, fim da sessão) vão num `settings.json`
por sessão, em `~/.promptorium/run/<sessão>/`. O executável é um script Python 3 (só biblioteca padrão)
escrito ali, que registra cada ação em `hooks.log` (linhas JSON). O app lê esse log a cada `tool_result`
e põe uma nota na timeline. Sem `python3` no PATH, os hooks ficam desligados e a tela Automações avisa.

**Gate no `Stop`: não adotado.** Funcionaria, mas:
- o gate precisa do estado que está no banco do app (`start_sha`, tentativas, relatório que a interface
  mostra), e levar isso ao hook exigiria IPC entre o script e o app;
- um `flutter test` de minutos dentro do `Stop` deixa o turno preso sem nada na interface ("verificando…");
- o reenvio da F1 é uma mensagem na mesma sessão, com o contexto em cache, e custa praticamente o mesmo
  que o `block` do `Stop`.

O gate continua no app (F1). Se um dia valer a pena, o caminho é o hook chamar o app por um socket Unix.

## 2. `control_request` `set_permission_mode` com a sessão viva

Enviado antes da primeira mensagem, numa sessão iniciada com `--permission-mode default`:

```json
{"type":"control_request","request_id":"pm-1","request":{"subtype":"set_permission_mode","mode":"acceptEdits"}}
```

Resposta: `{"type":"control_response","response":{"subtype":"success","request_id":"pm-1","response":{"mode":"acceptEdits"}}}`.
O `system/init` seguinte mostra `permissionMode: acceptEdits` e o `Write` não pediu permissão.
**Dá para trocar o modo sem reiniciar o processo** (03 §3.6).

## 3. Mensagem `user` no meio do turno

Durante um `Bash sleep 6`, o script enviou outra mensagem `user` ("inclua BANANA"). O agente a
incorporou **no mesmo turno**: veio um único `result`, com o texto `PRIMEIRA BANANA`. Os avisos
(edição manual, DT-41) podem ser enviados na hora, sem esperar o `result`.

## 4. `--tools` como lista de permitidos

`--tools Read,Glob,Grep`: o `system/init` lista só `['Glob', 'Grep', 'Read']`, e o agente respondeu que
o Bash não existe ali, sem pedir permissão. Com `--strict-mcp-config`, nenhum servidor MCP entra. Isso
vale para o modo Perguntar e para o planner (F12).

## 5. `claude mcp add-json` lendo de arquivo

Testado num `CLAUDE_CONFIG_DIR` temporário: `add-json -s user t1 - < s.json` e `add-json t2 @s.json`
respondem `Invalid configuration: : Invalid input`. Só o JSON como argumento funciona
(`add-json t3 "$(cat s.json)"`). **O CLI não lê o JSON de um arquivo nem do stdin**, então os
valores de env e header continuam no argv do processo `claude mcp` durante os segundos em que ele roda,
como no `mcp add -e/-H` atual. A F12 fica com o `mcp add` e passa a mascarar, nas mensagens mostradas,
todo argumento que não seja flag conhecida.
