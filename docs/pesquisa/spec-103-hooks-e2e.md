# SPEC-103 · Hooks gerenciados no Codex: sondagem e E2E

Data: 22/11/2026. Codex CLI 0.170.0. App compilado da branch `spec/103-t6-e2e`.

## O que o 0.170 aceita (sem turno pago)

Um `codex app-server` com `CODEX_HOME` num diretório temporário recebeu os
overrides que o app gera e respondeu ao `hooks/list`:

```
-c 'hooks.PreToolUse=[{matcher="*",hooks=[{type="command",command="python3 '<run>/promptorium_hook.py' --provedor codex"}]}]'
-c 'hooks.PostToolUse=[{matcher="*",hooks=[{type="command",command="…"}]}]'
-c 'hooks.SessionEnd=[{hooks=[{type="command",command="…"}]}]'
```

| eventName | source | trustStatus | enabled |
|---|---|---|---|
| preToolUse | sessionFlags | untrusted | true |
| postToolUse | sessionFlags | untrusted | true |
| sessionEnd | sessionFlags | untrusted | true |

As três formas são aceitas, sem avisos nem erros. Como a SPEC-093 (R15) já
tinha mostrado, um hook `untrusted` não roda, e o App Server não tem
`--dangerously-bypass-hook-trust`. Por isso, no 0.170, toda sessão Codex fica
em **Hooks só pós-turno**. O caminho nativo está pronto e é ligado pelo
`hooks/list`: quando uma versão listar os hooks do app como `trusted` ou
`managed`, a sessão passa a **Hooks nativos** sem mudança no app.

O schema do 0.170 (`generate-json-schema`) traz `hook/started` e
`hook/completed` com `run.{eventName,status,source,entries}`, e `hooks/list`
aceita `threadId`. O formato de entrada do script no Codex não pôde ser
observado (o hook não roda). O script aceita o formato do Claude, com os
eventos em camelCase, as ferramentas de shell do Codex (`shell` com argv
`bash -lc`, `exec_command` com `cmd`) e o `apply_patch`. A recusa no Codex
sai com o código 2 e o motivo no stderr.

## E2E no app isolado

- Display Xephyr `:7`, 1366×768, `XDG_DATA_HOME` e `HOME` no scratchpad. O app
  nunca viu o `~/.codex` nem o `~/.claude` reais.
- **Sem turno pago.** O `codex` do `PATH` era um Codex falso
  (`docs/pesquisa/spec-103-codex-falso.py`). Ele responde o App Server e roda
  um turno roteirizado. No modo **nativo**, o `hooks/list` lista os hooks do
  app como `trusted`, e o falso roda o script do app como o Codex faria: o
  `preToolUse` antes do comando e o `postToolUse` depois do `apply_patch`. No
  modo **pós-turno**, ele lista os hooks como `untrusted`, que é o caso real do
  0.170, e pede aprovação dos comandos.
- Projeto de teste `loja-api` com `formatar: sh tool/formatar.sh {arquivo}`.

| Cenário | Resultado | Captura |
|---|---|---|
| Automações antes de qualquer sessão Codex | O Claude Code fica em "Antes da ferramenta". O Codex fica em "Na aprovação" no bloqueio e em "Ao fim do turno" nos demais | `app/1-automacoes-pos-turno.png` |
| Sessão nativa (Editar): `apply_patch` com a chave do Stripe | O script formata os dois arquivos do patch ("Formatado: …", selo Codex) | `app/2-sessao-codex-nativo.png` |
| `git add -A && git commit` com a chave | O Vigia recusa antes de rodar: "Vigia de segredos bloqueou o commit · 1 achado", com o selo Codex. O comando aparece "Negada, não aplicada" | `app/2-…`, `app/3-…` |
| `git push --force origin spec-031` | "Hook bloqueou `git push --force origin spec-031` (git push --force)", com o selo Codex | `app/3-sessao-codex-push-bloqueado.png` |
| Chip "Hooks nativos" | A lista mostra preToolUse, postToolUse e sessionEnd, e a origem sessionFlags | `app/4-chip-hooks-nativos.png` |
| Automações depois da sessão nativa | O Codex fica em "Antes da ferramenta" / "Depois do apply_patch" / "sessionEnd", e o "Último:" vem do Codex | `app/1-automacoes-nativo.png` |
| Sessão pós-turno (Editar): pedido de `git push --force` | Recusado antes do balão: o falso recebeu `decline` e a pessoa não viu o pedido | `app/5-pos-turno-aprovacao.png` |
| Pedido de `flutter test` | Vai para a pessoa (Aprovações pendentes) | `app/5-…` |
| Aviso único | Aparece uma vez na sessão, com o motivo e o substituto de cada hook | `app/6-pos-turno-aviso.png` |
| Fim do turno | "Formatado ao fim do turno: …" antes de "O app commitou o que o Codex deixou no worktree" | `app/7-pos-turno-formatado.png` |
| Chip "Hooks só pós-turno" | A lista mostra os substitutos | `app/8-chip-pos-turno.png` |
| Parar | "Sessão encerrada (parada pelo usuário)", com o selo Codex | `app/9-pos-turno-fim.png` |
| Nova sessão Codex em YOLO | Aviso: "No Codex sem hooks, o YOLO não bloqueia comandos perigosos" | `app/10-yolo-sem-hooks.png` |

### `~/.codex` antes e depois

Comparei o `ls -la --time-style=full-iso ~/.codex` antes e depois, sem ler o
conteúdo dos arquivos. Só mudaram `logs_2.sqlite-wal` e `-shm`, que são o log
do Codex real usado por outras sessões da máquina. O `config.toml`, os
registros de confiança e as pastas de hooks ficaram iguais. Como o app rodou
com o `HOME` no scratchpad, ele não tinha como escrever lá. Nenhum argumento
do falso trouxe `--trust`, e nenhum processo recebeu `CODEX_HOME`.

### Observações

- Quando o app processa a fila mais devagar que o agente, um cartão do
  `hooks.log` pode aparecer logo antes do cartão do comando seguinte. Isso
  acontece porque o log é lido inteiro a cada `hook/completed`. Cada linha
  continua aparecendo uma vez só.
