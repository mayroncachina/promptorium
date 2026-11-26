# Sondagem do Codex 0.170 (SPEC-093)

> 20/11/2026 · `codex-cli 0.170.0` (instalação *standalone* em `~/.local/bin/codex`) · Ubuntu 24.04.5, kernel 7.0 · conta ChatGPT Plus.
> Sonda: [`codex-0170.py`](codex-0170.py) (parte sem custo sozinha, parte paga atrás de `--pago`). Transcrições: [`test/fixtures/codex/0.170/`](../../test/fixtures/codex/0.170/). Teste de reprodução: `test/core/codex/codex_0170_fixtures_test.dart`.
> **11 turnos pagos + 1 compactação = 12 chamadas**, todos com `gpt-5.6-luna` e esforço `low`. Nenhum código de produção mudou.

## Resumo

1. **Commit em worktree (R8, bloqueador da SPEC-096).** Pelas regras do próprio Codex, **sem `writableRoots` o commit falha e com o *git common dir* em `writableRoots` ele passa.** Sem `writableRoots`, o sandbox `workspace-write` só libera o cwd do worktree, e o `git commit` precisa gravar em `<repo>/.git/worktrees/<wt>/index.lock`, `objects/`, `refs/` e `logs/`, que ficam fora dele. A prova tem duas partes: o perfil de permissão que o Codex calcula (`codex debug prompt-input`) e a execução desse perfil com Landlock, aplicado pelo kernel: `index.lock: Permissão negada` sem as raízes e `commitou` com elas. **Neste computador não deu para confirmar com o sandbox real do Codex**, porque ele não sobe (item 2). Nos dois turnos pagos de worktree, a escrita e o `git` falharam antes de chegar ao git, com erro do `bwrap`. Para a 096: a preferida (P4) continua de pé, com uma ressalva de segurança (ver "Worktree"). A reserva, **o app commitar depois do turno**, é a única que funciona em qualquer máquina.
2. **O sandbox do Codex não funciona neste Ubuntu.** Com `kernel.apparmor_restrict_unprivileged_userns = 1`, o padrão do Ubuntu 24.04, o `bwrap` (inclusive o que vem empacotado com o Codex) não cria *user namespace*: `bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted`. Na prática, **todo comando e todo `apply_patch` em `read-only` ou `workspace-write` falha**. Só passam `danger-full-access` e o que a pessoa aprova para rodar fora do sandbox. O App Server avisa logo depois do `initialize` com `configWarning` ("Codex's Linux sandbox uses bubblewrap and needs access to create user namespaces."), e um `command/exec ["true"]` em `readOnly` detecta o problema sem gastar cota.
3. **O App Server grava no `~/.codex/config.toml`.** Um `thread/start` (também `ephemeral`) com `sandbox: workspace-write` ou `danger-full-access` acrescenta `[projects."<cwd ou raiz do repo>"] trust_level = "trusted"`. **Com `read-only` não grava**, e abrir a thread em `read-only` e subir o sandbox no `turn/start` (`sandboxPolicy` + `approvalPolicy`) também não, e a política fica na thread. O adaptador atual manda o `sandbox` no `thread/start`, ou seja, hoje ele já gravaria *trust* no global. Os 4 blocos que a primeira rodada provocou foram removidos, e o hash voltou ao original. Depois, uma rodada de `edicao` com a abordagem segura, no `~/.codex` real, terminou com o hash intacto (ver R4).
4. **`-c mcp_servers={}` não desliga os MCP do usuário.** O servidor do `config.toml` e o `codex_apps` sobem mesmo assim. O que funciona é `-c mcp_servers.<nome>.enabled=false` para cada servidor, mais `-c features.apps=false`.
5. **`CLAUDE.md` funciona** com `-c project_doc_fallback_filenames=["CLAUDE.md"]`. O modelo respondeu a palavra-senha, e o `thread/start` devolve `instructionSources` com o arquivo, o que permite conferir sem turno. Sem o override, o Codex não lê o arquivo. A decisão 6 fica com o `CLAUDE.md` como fonte, sem gerar `AGENTS.md`.
6. **Hooks por `-c` não rodam.** O hook aparece no `hooks/list` (`source: sessionFlags`), mas com `trustStatus: untrusted`, e no turno o `rm` passou. O App Server não aceita `--dangerously-bypass-hook-trust`, que só existe em `codex`/`codex exec`. A confiança só fica gravada no `config.toml` (`trusted_hash`).
7. **`untrusted` sumiu da CLI, mas não do App Server.** `codex -a untrusted` e `codex resume <id> -a untrusted` saem com código 2, então o terminal embutido no modo padrão quebra hoje. No App Server, `untrusted` é aceito e pede aprovação de cada comando, sem `acceptForSession` entre as decisões oferecidas.

## Como rodar

```sh
# Sem custo (nenhum turno): CLI, schema, handshake, cota, sandbox, instruções, hooks, Landlock, trust, MCP
python3 -I docs/pesquisa/codex-0170.py --saida /tmp/sonda-codex
# Com custo: os cenários R5–R15 (cerca de 10 turnos); --so limita a cenários
python3 -I docs/pesquisa/codex-0170.py --saida /tmp/sonda-codex --pago --so worktree
```

A sonda grava `resultados.json`, `turnos.json`, a ajuda da CLI em `cli/`, o schema em `schema/` e uma transcrição por cenário em `fixtures/` (`{"dir":"send"|"recv","msg":…}`, já sanitizada: caminhos viram `<sonda>` e `~`, o nome do usuário vira `usuario`, e e-mail, ids de conta, `installationId`, nome da máquina e *tokens* viram `[redigido]`). Ela só usa `-c` e variáveis de ambiente. Nunca usa `--trust` nem `codex login`, e nunca lê o `auth.json`. Depois da primeira rodada (achado 3), o script passou a abrir toda thread em `read-only` e a subir o sandbox no turno.

## CLI (R1)

| Item | 0.170 |
|---|---|
| Versão | `codex-cli 0.170.0` (o `doctor` avisa que existe a 0.171.0) |
| `-a/--ask-for-approval` | só `on-request` e `never`. **`-a untrusted` sai com código 2**, inclusive em `resume` |
| `--yolo` | some do `--help`, mas o parser aceita (`codex --yolo`, `codex resume --yolo`). O nome documentado é `--dangerously-bypass-approvals-and-sandbox` |
| `--sandbox`, `--add-dir`, `-c`, `--image`, `--profile` | existem. `--add-dir` = "diretórios adicionais graváveis" |
| `--ignore-user-config` | não existe no 0.170 |
| `--dangerously-bypass-hook-trust` | em `codex` e `codex exec`; **não** em `codex app-server` |
| `codex debug prompt-input` | mostra o prompt que o modelo veria (instruções do projeto e perfil do sandbox), sem turno. Foi a base de R8 e R10 |
| `codex sandbox -- <cmd>` | roda um comando no sandbox do Codex. Neste host falha com o erro do `bwrap` |
| *Features* estáveis úteis | `hooks`, `shell_tool`, `unified_exec`, `view_image`, `guardian_approval`, `goals`, `plugins`, `skill_search`. `steer` aparece como `removed / true`: o *flag* saiu porque `turn/steer` virou padrão. `code_mode_host` está ligado, e o modelo chama `apply_patch` de dentro de um script `exec` |

Ajuda completa em `cli/help-*.txt` e `cli/features.txt` na saída da sonda.

## Protocolo (R2)

- Bundle `codex_app_server_protocol.schemas.json`: **sha256 `ca6123bc03238217a62a32c745b45e267fdb26825a80ce6849e893fcbe6628b8`**. Com `--experimental`, o hash é `e3f3b0a7…c5dc8db`.
- **109** *client requests*, **10** *server requests* e **86** notificações.
- **P3:** `generate-json-schema` leva **0,05 s**. O custo é desprezível, e a SPEC-094 pode conferir na partida, com cache por versão.

| Método do adaptador | Estado no 0.170 | Observação |
|---|---|---|
| `initialize` | existe | resposta: `userAgent`, `codexHome`, `platformFamily`, `platformOs` |
| `account/read` | existe | `account{type, email, planType, workspaceName}`, `userId`, `workspaceRouting`. O app não precisa dos ids |
| `model/list` | existe | 10 modelos visíveis, todos com `text` + `image`; esforços `low…ultra` (os `luna` param em `max`) |
| `thread/start` / `resume` / `fork` | existe, mudou | resposta nova `instructionSources` e `sandbox` como objeto (`{type, writableRoots, …}`). **Com `sandbox` ≠ `read-only`, grava *trust* no global** |
| `turn/start` | existe | `sandboxPolicy` com `writableRoots`, `excludeSlashTmp`, `excludeTmpdirEnvVar`, `networkAccess`. Entrada `localImage`, `skill` e `mention`. `outputSchema` |
| `turn/interrupt` | existe | resposta `{}`, depois `turn/completed{status:"interrupted"}` |
| `turn/steer` | existe | exige `expectedTurnId` e devolve `{turnId}` |
| `item/commandExecution/requestApproval` | existe, mudou | traz `command`, `cwd`, `commandActions`, `proposedExecpolicyAmendment` e `availableDecisions` |
| `item/fileChange/requestApproval` | existe | **não traz as mudanças**: só `itemId`, `reason`, `grantRoot`. As mudanças vêm no `item/started` com o mesmo `itemId` |
| `item/tool/requestUserInput` | existe | não exercitado |
| `thread/tokenUsage/updated` | existe | `{total, last, modelContextWindow}`. `last` = última chamada ao modelo, não o último turno |
| `turn/started` / `turn/completed` | existe | `TurnStatus = completed \| interrupted \| failed \| inProgress` |
| `item/started` / `item/completed` | existe, mudou | `fileChange.changes[].kind` agora é **objeto** (`{"type":"add"}`, `{"type":"update","move_path":…}`). Item novo `contextCompaction`. `agentMessage.phase` = `commentary` \| `final_answer` |
| `item/agentMessage/delta` | existe | — |
| `serverRequest/resolved` | existe | — |
| `error` | existe | `willRetry`, `codexErrorInfo` |
| `account/rateLimits/read` | existe | ver R3 |
| `thread/compact/start` | existe | resposta `{}`; a compactação roda como um **turno** (ver R14) |
| `thread/compacted` | **sumiu** | no lugar dele vem o item `contextCompaction`. `ContextCompactedNotification` está marcada como *deprecated* |

*Server requests* que o adaptador recusa com `-32601`: `item/permissions/requestApproval`, `mcpServer/elicitation/request`, `item/tool/call`, `account/chatgptAuthTokens/refresh`, `attestation/generate` e os legados `applyPatchApproval`/`execCommandApproval`. A lista de métodos usados fica em `ADAPTADOR` no script, para a conferência de versão da SPEC-094.

## Handshake e conta (R3)

`initialize` → `account/read` → `model/list` (uma página) → `account/rateLimits/read`, sem turno (fixture `handshake.jsonl`).

```json
{"rateLimits": {"limitId": "codex", "primary": {"usedPercent": 0, "windowDurationMins": 300, "resetsAt": 1795242676},
  "secondary": {"usedPercent": 15, "windowDurationMins": 10080, "resetsAt": 1795806604},
  "credits": {"hasCredits": false, "unlimited": false, "balance": "0"}, "planType": "plus",
  "rateLimitReachedType": null, "spendControlReached": false},
 "rateLimitsByLimitId": {"codex": {"…": "igual ao acima"}}, "ordinaryUsageAllowed": true, "accountId": "[redigido]"}
```

Durante os turnos chega `account/rateLimits/updated` com o mesmo `RateLimitSnapshot`, que é parcial: o app junta com o último `read`. **SPEC-097:** janela de 5 h (`primary`) e semanal (`secondary`) em `usedPercent` inteiro, `resetsAt` em segundos Unix, `planType`, créditos e `rateLimitReachedType`. Nada disso abre turno.

Outras notificações que chegam sem pedir: `configWarning` (o aviso do sandbox), `remoteControl/status/changed` (com o nome da máquina, que deve ser redigido), `account/updated{authMode, planType}` e `mcpServer/startupStatus/updated`.

## Arquivos do usuário (R4)

| Momento | `config.toml` | `rules/default.rules` |
|---|---|---|
| Antes da sondagem | `3f1bcc8c…cdbaf74843` | `596e3683…769decf7` |
| Depois dos blocos sem custo, `leitura` e `contexto` | igual | igual |
| Depois de `edicao`, `comando`, `worktree`, `hook_turno` | **mudou**: +4 blocos `[projects."<sonda>/repos/<cenário>/repo"] trust_level = "trusted"` | igual |
| Depois da restauração (removidos só esses 4 blocos) | `3f1bcc8c…cdbaf74843` (igual ao original) | igual |
| Depois de `edicao` de novo, com a thread em `read-only` e `workspace-write` + `on-request` no turno (turno 11, `edicao-turno.jsonl`) | **igual** (`3f1bcc8c…`) | igual |

Quem gravou foi o próprio App Server, no `thread/start` com `workspace-write` ou `danger-full-access`. No worktree, o *trust* foi para a **raiz do repositório**, não para o worktree. Reprodução sem tocar no `~/.codex` (cenário `confianca`, com `CODEX_HOME` temporário e sem login, logo sem turno):

| `thread/start` | grava *trust*? |
|---|---|
| `read-only` | não |
| `workspace-write` | **sim** |
| `workspace-write` + `ephemeral: true` | **sim** |
| `danger-full-access` | **sim** |
| `-c projects."<cwd>".trust_level="untrusted"` + `workspace-write` | **sim** (sobrescreve) |
| `read-only` e depois `turn/start{sandboxPolicy: workspaceWrite, approvalPolicy: on-request}` | **não**. O `thread/resume` seguinte devolve `workspaceWrite` / `on-request` |

Outras mudanças no `~/.codex` durante a sondagem, todas do próprio CLI e esperadas: 9 arquivos novos em `sessions/2026/11/20/rollout-*.jsonl` (um por thread com turno), SQLite de estado, histórico e logs (`state_5`, `thread_history_1`, `logs_2`), `models_cache.json`, `skills/.system/` (53 arquivos ressincronizados a cada partida), `plugins/cache/`, `cache/codex_apps_*`, `tmp/arg0-linux`, `shell_snapshots/`. O `auth.json` ficou fora da lista, sem leitura e sem `stat`.

## Cenários

### Somente leitura (R5) · 1 turno · `leitura.jsonl`

`thread/start{sandbox:"read-only", approvalPolicy:"never"}` + "Crie o arquivo ola.txt com o texto oi."

- O arquivo não foi criado, e o turno terminou `completed`. A resposta foi: "Não foi possível criar `ola.txt` porque o ambiente está em modo somente leitura."
- **A recusa não chega como item.** O modelo chamou `tools.apply_patch` de dentro do script `exec` (*code mode*), que voltou `patch rejected: writing is blocked by read-only sandbox; rejected by user approval settings` (visto no *rollout* do próprio CLI). O App Server não emitiu nem `fileChange` nem `commandExecution`: só as duas `agentMessage` (`phase: commentary` e `final_answer`).
- **SPEC-095/096:** o Perguntar no Codex é garantido pelo runtime, mas uma recusa pode não aparecer na timeline. Não dá para depender de item para avisar "o agente tentou escrever".

### Edição com aprovação (R6) · 1 turno · `edicao.jsonl`

`workspace-write` + `on-request`, "Crie nota.txt … e altere base.txt …":

```json
{"method": "item/fileChange/requestApproval", "id": 0, "params": {"threadId": "…", "turnId": "…",
  "itemId": "exec-421c2d75-…", "startedAtMs": 1795224772194, "reason": "command failed; retry without sandbox?", "grantRoot": null}}
{"method": "item/completed", "params": {"item": {"type": "fileChange", "id": "exec-421c2d75-…", "status": "completed",
  "changes": [{"path": "<sonda>/repos/edicao/repo/base.txt", "kind": {"type": "add"}, "diff": "linha dois\n"},
              {"path": "<sonda>/repos/edicao/repo/nota.txt", "kind": {"type": "add"}, "diff": "linha um\n"}]}}}
```

- O pedido de aprovação veio **porque o sandbox falhou** (bwrap), não por política. A sonda respondeu `acceptForSession`, e o patch foi aplicado **fora do sandbox**.
- `kind` é objeto, e o `diff` de um arquivo novo é só o conteúdo. A alteração de `base.txt` chegou como `add` porque o modelo reescreveu o arquivo inteiro.
- Na segunda rodada (turno 11, thread em `read-only` e política no turno), o modelo editou um arquivo existente, e o `kind` de alteração veio assim:

```json
{"path": "<sonda>/repos/edicao/repo/base.txt", "kind": {"type": "update", "move_path": null}, "diff": "@@ -1 +1 @@\n-base\n+linha dois\n"}
```

  Com o sandbox quebrado, até os comandos de leitura (`sed -n`, `ls`) pediram escalonamento, e as aprovações chegaram com `reason` escrito pelo modelo ("Você autoriza a leitura de base.txt…").
- **SPEC-095:** `FileChangeEvent{path, kind: kind.type, unifiedDiff: diff, movePath: kind.move_path}`. O `diff` é um *hunk* unificado em `update` e o conteúdo inteiro em `add`. O cartão de aprovação busca as mudanças no `item/started` com o mesmo `itemId`.

### Comando com aprovação e `untrusted` (R7) · 1 turno · `comando.jsonl`

`workspace-write` + **`untrusted` (aceito pelo App Server)**, com três comandos:

```json
{"method": "item/commandExecution/requestApproval", "id": 0, "params": {"kind": "command", "itemId": "exec-64585c5c-…",
  "environmentId": "local", "command": "/usr/bin/zsh -lc ls", "cwd": "<sonda>/repos/comando/repo",
  "commandActions": [{"type": "listFiles", "command": "ls", "path": null}], "proposedExecpolicyAmendment": ["ls"],
  "availableDecisions": ["accept", {"acceptWithExecpolicyAmendment": {"execpolicy_amendment": ["ls"]}}, "cancel"]}}
{"method": "item/completed", "params": {"item": {"type": "commandExecution", "command": "/usr/bin/zsh -lc ls",
  "cwd": "<sonda>/repos/comando/repo", "source": "unifiedExecStartup", "status": "completed",
  "aggregatedOutput": "base.txt\n", "exitCode": 0, "durationMs": 0}}}
```

- Três pedidos e três `accept`. O `cat nao-existe.txt` voltou `status: failed`, `exitCode: 1` e a mensagem no `aggregatedOutput`.
- Em `untrusted`, **`acceptForSession` não aparece entre as `availableDecisions`**. A alternativa persistente é `acceptWithExecpolicyAmendment`, que grava regra de execpolicy: o app não deve oferecer essa opção, porque ela escreve no global.
- Os comandos rodam como `zsh -lc` (shell de login da pessoa) e, aprovados, rodaram mesmo com o sandbox quebrado: aprovar = rodar fora do sandbox.

### Worktree (R8) · 2 turnos · `worktree-*.jsonl`, `sandbox.jsonl`, cenário `landlock`

**Perfil que o Codex aplica** (`codex debug prompt-input`, worktree `wt` do repositório `repo`, com `exclude_slash_tmp` para simular um repositório fora de `/tmp`, como em `~/.promptorium/worktrees`):

| | Gravável | Somente leitura dentro do gravável |
|---|---|---|
| sem `writableRoots` | `wt` | `wt/.git` (o arquivo `gitdir:`), `wt/.agents`, `wt/.codex`, `wt/.aws` |
| `writableRoots = [repo/.git]` | `wt`, **`repo/.git`** | os mesmos, mais `repo/.git/.git`, `.agents`, `.codex`, `.aws` (que não existem) |

O Codex protege o `.git` *dentro* de cada raiz gravável, mas não protege uma raiz que **é** o `.git`.

**O que um commit no worktree grava** (medido sem sandbox): `repo/.git/worktrees/wt/{index, COMMIT_EDITMSG, logs/HEAD}`, `repo/.git/objects/…`, `repo/.git/refs/heads/etapa`, `repo/.git/logs/refs/heads/etapa` e o arquivo novo do worktree. O `wt/.git` não é tocado.

**O perfil aplicado pelo kernel** (Landlock, mesma lista de graváveis, leitura livre):

| Graváveis | Resultado |
|---|---|
| `wt` | `fatal: Não foi possível criar '<repo>/.git/worktrees/wt/index.lock': Permissão negada` (rc 128) |
| `wt` + `repo/.git` | `commitou` (rc 0) |
| `wt` + `repo/.git/{worktrees/wt, objects, refs, logs}` | `commitou` (rc 0), com aviso `packed-refs.lock: Permissão negada` do *gc* automático |

**Com o Codex real, neste host** (turnos pagos):

| Turno | Política | Resultado |
|---|---|---|
| `com_roots_never` | `workspaceWrite{writableRoots:[repo/.git]}` + `never` | `fileChange` `status: failed` ("Failed to write file …"); o git nem rodou; `git log` só com `inicio` |
| `sem_roots_on_request` | `workspaceWrite` + `on-request` | a escrita pediu "retry without sandbox?" (aceito, o arquivo foi criado); o `git add && git commit` falhou com `bwrap: loopback: Failed RTM_NEWADDR`, sem item `commandExecution` e sem pedido de escalonamento; nenhum commit |

`command/exec` (sem modelo) com as mesmas políticas: os seis casos em `readOnly`/`workspaceWrite` saem com `exitCode: 1` e o erro do `bwrap`. Em `dangerFullAccess`, `exitCode: 0`.

**Conclusão para a SPEC-096 (P4):**
1. **Preferida:** o app inclui o *git common dir* nas `writableRoots` do `turn/start`. Pelas regras do Codex e pela emulação, o commit passa. Ressalva de segurança: `repo/.git` inteiro gravável deixa o agente escrever `.git/hooks` e `.git/config`, que depois rodam **fora** do sandbox, no próximo commit do app ou da pessoa. O recorte `worktrees/<wt>` + `objects` + `refs` + `logs` também commita e não expõe `hooks/` nem `config`. A recomendação é usar esse recorte.
2. **Reserva, e única que funciona sem sandbox:** **o app commitar depois do turno** (o worktree é do app, e a SPEC-048 já marca o commit). Em máquinas sem o sandbox (achado 2), é o caminho padrão.
3. `--add-dir` é o equivalente na CLI de `writableRoots`, e o `danger-full-access` só para o git não existe por comando. Nenhum dos dois muda a conclusão.
4. **Pendente:** repetir `--pago --so worktree` numa máquina com o sandbox funcionando. Fica como critério da T3 da 096.

### Ambiente (R9) · sem turno próprio (dentro de R7)

- `echo agente=$PROMPTORIUM_AGENTE` com a variável no ambiente do App Server deu `agente=codex` (turno de R7, comando aprovado) e também em `command/exec` com `dangerFullAccess`.
- **Dentro do sandbox não deu para testar**, porque o bwrap não sobe. O Codex não filtra a variável no caminho sem sandbox. O filtro padrão do `shell_environment_policy` tira nomes com `KEY`/`SECRET`/`TOKEN`, e `PROMPTORIUM_AGENTE` não casa com eles. A SPEC-048 continua valendo, mas a conferência dentro do sandbox fica para a mesma máquina do item pendente de R8.

### Instruções do projeto (R10) · 1 turno · `contexto.jsonl`

| | `codex debug prompt-input` | `thread/start.instructionSources` | Turno |
|---|---|---|---|
| `-c project_doc_fallback_filenames=["CLAUDE.md"]` | bloco `# AGENTS.md instructions for <repo>` com o `CLAUDE.md` | `["<repo>/CLAUDE.md"]` | "LARANJA-42" (correto) |
| sem override | nenhum bloco | `[]` | — |

**Decisão 6:** o app passa o override e confere `instructionSources` no `thread/start`, sem turno. O `AGENTS.md` só precisa existir se a pessoa quiser usar o Codex fora do app.

### Skills (SPEC-104) · sem turno · `skills.jsonl`

Sondagem de 22/11 com `HOME` e `CODEX_HOME` isolados no scratchpad, sem login e sem turno. O repositório tinha `.claude/skills/{gerar-release,Migrar_Banco,sem-front}`, `.agents/skills/nativa-agents` e `.codex/skills/nativa-codex`. O `HOME` tinha `~/.claude/skills/commit-pt`.

| Pedido | Resultado |
|---|---|
| `skills/list` sem raízes extras | `.agents/skills` e `.codex/skills` com `scope: repo`, as 5 de sistema (`scope: system`, em `~/.codex/skills/.system`). Nada do `.claude/skills` |
| `skills/extraRoots/set` com `<repo>/.claude/skills` e `~/.claude/skills` | `{}` e a notificação `skills/changed`. Nada gravado no `config.toml` (o `CODEX_HOME` continuou sem ele) |
| `skills/list` com `forceReload` | as skills do `.claude/skills` e do `~/.claude/skills` aparecem com `scope: user`. `Migrar_Banco` é aceita (o Codex não valida o nome). `sem-front` vai para `errors`: "missing YAML frontmatter delimited by ---" |
| `thread/start` com `-c project_doc_fallback_filenames=["CLAUDE.md"]` | `instructionSources: ["<repo>/CLAUDE.md"]` |

`git status` do repositório ficou limpo, e nada foi criado no `HOME`. **Conclusão:** o caminho principal da R6 funciona (`skillsExtraRoots` comprovada). A pasta de skills de repositório do Codex, usada pelo plano B (R10), é `.agents/skills`.

### Imagem (R11) · 1 turno · `imagem.jsonl`

Um turno com `{"type":"image","url":"data:image/png;base64,…"}` (vermelho) e `{"type":"localImage","path":"<repo>/b.png"}` (azul). A resposta foi "(1) Vermelho; (2) Azul.": **os dois formatos funcionam** com `gpt-5.6-luna`. Todos os modelos do `model/list` anunciam `image`. O adaptador só manda *data URL*, o que já funciona. `localImage` evita o base64 no JSON-RPC.

### Saída estruturada (R12) · 1 turno · `contexto.jsonl`

`turn/start.outputSchema = {"type":"object","properties":{"ok":{"type":"boolean"}},"required":["ok"],"additionalProperties":false}` em `read-only`. O JSON chega como **texto da `agentMessage` final** (`"{\"ok\":true}"`, `phase: final_answer`), sem campo separado, e o schema foi respeitado. O `structuredOutput()` neutro (SPEC-100) faz `jsonDecode` do texto final.

### Interromper e direcionar (R13) · 1 turno · `interromper.jsonl`

`turn/steer{expectedTurnId}` no meio do turno devolveu `{"turnId": "<o mesmo>"}`. Depois, `turn/interrupt` devolveu `{}`, seguido de `turn/completed{"status":"interrupted","error":null,"durationMs":6679}`. **O uso chega** (`thread/tokenUsage/updated` antes do fim, `outputTokens: 98`). O modelo recusou a tarefa longa ("Não posso reproduzir esse conteúdo…"), então o *efeito* do steer no texto não foi observado; o servidor aceitou o pedido.

### Contexto e compactação (R14) · 1 turno + 1 compactação · `contexto.jsonl`

| Momento | `last.totalTokens` | `last.inputTokens` / `cached` | `total.totalTokens` | `modelContextWindow` |
|---|---|---|---|---|
| Turno 1 (1 chamada) | 12 403 | 12 393 / 10 112 | 12 403 | 258 400 |
| Turno 2 (1 chamada) | 14 052 | 14 037 / 0 | 26 455 | 258 400 |
| Depois de `thread/compact/start` | 15 663 | 0 / 0 | 26 455 | 258 400 |

- `thread/compact/start` responde `{}` e roda **como turno**: `turn/started`, item `contextCompaction` (start/complete), `thread/tokenUsage/updated`, `turn/completed{status:"completed"}`, 3,6 s. Não existe `thread/compacted`. O `thread/read` seguinte funciona.
- Em turnos com mais de uma chamada ao modelo (R5, R6), `last` ≠ delta de `total`: `last` é a **última chamada**.
- **Fórmula (contrato da SPEC-087 para a 095):** *contexto atual* = `tokenUsage.last.totalTokens`; *janela* = `tokenUsage.modelContextWindow`; *uso do turno* = `total(depois) − total(antes)`, como o `CodexRun` já calcula, com `inputTokens − cachedInputTokens` como entrada nova. Depois da compactação, `last.totalTokens` traz o tamanho novo, com `inputTokens = 0`.

### Hooks sem tocar no global (R15) · 1 turno · `hook_turno.jsonl`, `hooks-por_c.jsonl`

- `-c 'hooks.PreToolUse=[{matcher="*",hooks=[{type="command",command="python3 …/nega_rm.py …"}]}]'` aparece no `hooks/list` como `{"eventName":"preToolUse","source":"sessionFlags","sourcePath":"/<session-flags>/config.toml","trustStatus":"untrusted","enabled":true,"currentHash":"sha256:…"}`.
- Tentativas de confiar só por `-c` (`hooks.state."<key>".trusted_hash="<hash>"`, `bypass_hook_trust=true`) **continuam `untrusted`**, e `codex app-server --dangerously-bypass-hook-trust` sai com erro.
- No turno (`danger-full-access` + `never`, "Rode exatamente `rm apagar.txt`"), **o hook não rodou** (log vazio) e o arquivo foi apagado. O formato da resposta de *deny* não pôde ser observado.
- O `CODEX_HOME` temporário com o `auth.json` por link simbólico não foi tentado, para não criar link para a credencial. Um `CODEX_HOME` próprio grava a confiança no `config.toml` *dele*, o que resolveria, mas fica para a SPEC-103 decidir com o resultado acima.
- **SPEC-103:** pelo App Server, só com *trust* persistido, o que o app não deve gravar no global. Alternativas: `CODEX_HOME` do app, `codex exec --dangerously-bypass-hook-trust` (plano B) ou o fallback pós-turno da SPEC-085.

### ai-memory (R16) · lido no código da 3.5.1, sem rodar

A SPEC-098 foi implementada sem instalar o ai-memory e sem rodar os instaladores dele, por ordem do usuário. O roteiro da 098 foi conferido no código-fonte da versão 3.5.1 (clone raso do repositório, 19/11/2026). Os testes usam um `ai-memory` falso que responde no formato desse código. **Nenhum turno do Claude ou do Codex foi gasto.**

| Passo do roteiro | O que o código da 3.5.1 mostra | Efeito na 098 |
|---|---|---|
| 1 · `setup --plan` | `setup --plan --json` imprime um `PlanDocument` com `format: 1`, `data_dir`, `agents[]` (`agent`, `found{kind,path}` e `wiring`, que vale `mcp+hooks+skills` ou `plugin`) e `other_agents`. **Não diz se os hooks e o MCP já estão instalados.** | O estado por agente (R3) junta três leituras: o `--plan` (detecção e plugin), `uninstall --only hooks\|mcp` **sem `--apply`** (o *dry-run* lista "would remove … from <arquivo>") e `doctor --json` (`codex_hooks.skipped` = aguardando confiança) |
| 2 · `install-hooks` / `install-mcp --apply` | Os dois são idempotentes, só trocam as entradas do ai-memory e gravam uma cópia com data ao lado de cada arquivo antes de mudar | São os únicos comandos que "Ligar" roda (R4) |
| 3 · auxiliar sem sessão e sem consumir a passagem | `hooks/_lib.sh`: com `AI_MEMORY_CAPTURE_OWNER` não vazio, `ai_memory_post_hook` descarta o evento antes do *spool*, e `ai_memory_get_handoff` manda `claim=0`, ou seja, oferece a passagem sem consumir (#2148). `AI_MEMORY_AUTO_HANDOFF=off` vira `auto_handoff=0`, e o fim da sessão não deixa passagem (#1951). O hook nativo e os plugins gerados leem as mesmas variáveis | P4 confirmada no código: auxiliares com as duas variáveis; sessões de etapa só com `AUTO_HANDOFF=off` (R6) |
| 4 · Codex pelo App Server | Os hooks do `~/.codex` só rodam depois de o Codex confiar neles (`hooks/list` → `trustStatus`). O `doctor` pergunta isso ao próprio Codex | O app não isola o `CODEX_HOME`, então as sessões do Codex no app herdam os hooks e o MCP. Enquanto não houver confiança, o bloco do Codex diz "Codex no app sem memória" (R7) |
| 5 · `memory_handoff_list` | Devolve `{handoffs: [...], newer_unended_session?}`. Cada linha vem plana: `id`, `from_session_id` (nulo = manual), `from_agent`, `cwd`, `owner_user` (nulo = compartilhada), `summary`, `open_questions`, `next_steps`, `files_touched`, `state`, `created_at`, `accepted_*`. **Só lista as abertas**, sem estado como filtro. O dono é filtrado pelo servidor (as suas e as compartilhadas) | Ordem de entrega e selo "será entregue" (R9); o filtro "Mostrar aceitas e expiradas" avisa que esta versão só informa as abertas |
| 6 · `memory_handoff_cancel` e desinstalar por agente | `memory_handoff_cancel {handoff_id}` devolve `cancelled`/`state`. `uninstall` só tem `--only hooks\|mcp\|instructions\|skills`, **sem filtro por agente** | "Descartar" com confirmação (R11, P6); "Desligar" só mostra `ai-memory uninstall --only hooks --apply` e `--only mcp --apply` com o aviso "remove de todos os agentes" (P5) |
| 7 · `status --json` | Traz `data_dir`; o wiki fica em `<data_dir>/wiki/<workspace>/<projeto>`. A interface web responde em `/web/w/<ws>/<proj>` (página em `/p/<caminho>`) | "Abrir wiki" testa a interface web e, sem ela, abre a pasta (R12) |

Pendente para quando o ai-memory estiver instalado de propósito: repetir os passos 3 e 4 com o binário real, num `CLAUDE_CONFIG_DIR`/`CODEX_HOME` temporário.

## Divergências do adaptador (R19, registradas, não corrigidas)

| # | Onde | Divergência no 0.170 | Spec |
|---|---|---|---|
| D1 | `CodexRun.open` (`thread/start\|resume\|fork` com `sandbox`) | `workspace-write`/`danger-full-access` no `thread/*` **grava `trust_level` no `~/.codex/config.toml`**. Abrir em `read-only` e mandar a política no `turn/start` | 096 |
| D2 | `CodexProvider.start` (`-c mcp_servers={}`) | Não desliga os MCP do usuário nem o `codex_apps`. Usar `mcp_servers.<nome>.enabled=false` e `features.apps=false` | 094/105 |
| D3 | `codex_command.dart` + `codexPermissionPolicy` | `-a untrusted` sai com código 2 na CLI, e o terminal embutido no modo padrão falha no `validateCodexCommand`. No App Server, `untrusted` continua válido | 096 |
| D4 | `_item` (`fileChange` → `Edit` com `input.changes`) | `kind` é objeto (`{type, move_path}`), e `diff` de arquivo novo é o conteúdo. Nada de `file_path`/`old_string`/`new_string` | 095 |
| D5 | `_request` (aprovação de arquivo) | `item/fileChange/requestApproval` não traz as mudanças. O cartão precisa do `item/started` com o mesmo `itemId` | 095/096 |
| D6 | `approve()` | Sempre responde `accept`. Faltam `acceptForSession` (ofertado em `on-request`), `cancel` (recusar e interromper) e leitura de `availableDecisions`. Não oferecer `acceptWithExecpolicyAmendment` (grava no global) | 096 |
| D7 | `_item` (`agentMessage`) | `phase: commentary` vs `final_answer`. O `_answer` pega a última mensagem concluída (hoje é a final), mas os comentários aparecem como resposta na timeline | 095 |
| D8 | `_message` (`thread/compacted`) | Não existe mais: a compactação é um turno com item `contextCompaction`. O `CodexRun` ignora o `turn/completed` da compactação quando não está ocupado. Para "Compactar agora", tratar como turno | 095/107 |
| D9 | `turn/start.sandboxPolicy` | Não manda `writableRoots`, e o worktree precisa do recorte do *git common dir* (R8) | 096 |
| D10 | Partida | Sem detecção do sandbox quebrado: `configWarning` no `initialize` ou `command/exec ["true"]` em `readOnly` (sem custo). Sem sandbox, Perguntar e Editar não conseguem nem rodar comandos de leitura | 094/096 |
| D11 | `_request` | Recusa com `-32601`: `item/permissions/requestApproval`, `mcpServer/elicitation/request`, `item/tool/call`, `account/chatgptAuthTokens/refresh`, `attestation/generate` | 096 |
| D12 | Timeline | Recusas e falhas dentro do *code mode* podem não gerar item (R5 e o git de R8). Só o texto do agente conta | 095 |
| D13 | `initialize` | `clientInfo.version` fixo em `0.2.0`. Usar a versão do app | 094 |
| D14 | `_emit` (redação) | `remoteControl/status/changed` traz o nome da máquina e o `installationId`. O adaptador guarda só o método (ok), mas qualquer persistência bruta precisa redigir esses campos | 095 |

O `CodexRun` atual **não quebra** com nenhuma das transcrições (`codex_0170_fixtures_test.dart`, 13 testes): os turnos terminam, o uso bate e as aprovações viram `PermissionRequest`. A exceção esperada é `edicao-turno`: o `open()` recusa a thread `read-only` quando pediu `workspace-write` ("Codex não aplicou o modo de permissão solicitado"), e a 096 muda os dois lados. Os testes registram o comportamento atual, inclusive os itens acima.

## Conclusões por spec

- **SPEC-094:** a tabela abaixo é a fonte. Conferência de versão: `codex --version` ≥ 0.170 mais o hash do schema (0,05 s, dá para gerar na partida). Capacidade nova a considerar: **sandbox disponível** (por máquina, detectada sem custo). `mcp_servers={}` sai em favor de `enabled=false` por servidor.
- **SPEC-095:** payloads de `fileChange`, `commandExecution`, aprovação e uso registrados nas fixtures. Fórmula de contexto em R14. `kind` objeto, `phase` e `contextCompaction`.
- **SPEC-096:** (1) thread em `read-only` e política por turno (D1); (2) worktree com o recorte do *git common dir* nas `writableRoots` e reserva "o app commita depois do turno"; (3) sem sandbox (Ubuntu 24.04 padrão), avisar e oferecer só o que funciona: YOLO em worktree, ou orientar a liberar o bwrap no AppArmor. Não alterar nada no sistema pelo app; (4) terminal sem `-a untrusted`; (5) `untrusted` no App Server só quando quiser aprovar cada comando, sabendo que aprovar = rodar fora do sandbox.
- **SPEC-097:** `account/rateLimits/read` e `account/rateLimits/updated` (parcial, juntar) prontos. Janelas de 300 min e 10 080 min, `usedPercent` inteiro.
- **SPEC-098:** o roteiro do ai-memory foi conferido no código da 3.5.1 (seção R16), sem instalar e sem rodar.
- **SPEC-103:** hooks por `-c` não rodam sem *trust*, e o App Server não tem *bypass*. Ver R15.
- **SPEC-104/105/107:** `CLAUDE.md` por fallback comprovado; MCP desligável por servidor; "Compactar agora" comprovado.

## Voltar a conversa (SPEC-110)

Sonda de 25/11 com o binário 0.170.0 e `CODEX_HOME`/`HOME` isolados. O modelo era um servidor local (`model_providers.mock`, `wire_api = "responses"`, em `127.0.0.1`), com o proxy apontando para uma porta morta: nenhuma chamada saiu da máquina e nenhuma cota foi gasta. O que cada pedido de modelo levou mostrou o que o agente lembra.

- `thread/revert {threadId, beforeTurnId}` só funciona numa conexão que carregou a thread (senão `thread not found`) e numa thread `paginated`, que é o padrão do 0.170 (todas as fixtures). Tira o turno e os seguintes; o turno depois dele não leva mais nada dos turnos revertidos ao modelo. Emite `thread/reverted`.
- Um turno que já saiu dá `turn not found: <id>`. Reverter o primeiro turno deixa a thread vazia e utilizável: ela retoma em outro processo e aceita turnos e forks.
- `thread/fork {threadId, excludeTurns, ephemeral: false}` funciona com a thread carregada ou não e **mantém os ids dos turnos**. A cópia continua inteira depois que a original é revertida. O fork emite `thread/started` da cópia na mesma conexão.
- Uma thread tem um escritor por vez: com o processo da sessão vivo, outro processo recebe `thread … already has an active writer` no `thread/resume`. `thread/fork`, `thread/read` e `thread/items/list` de outro processo passam.
- `thread/archive` funciona sem carregar a thread; arquivar de novo dá `no rollout found`. Uma thread arquivada não retoma (`session … is archived`), mas o `thread/read` dela ainda responde: só o `thread/resume` prova que a cópia serve.
- `thread/items/list {threadId, turnId}` funciona sem carregar a thread; um turno revertido devolve a lista vazia.
- Depois do revert, o `total` de `thread/tokenUsage/updated` encolhe junto com a conversa (só os turnos que ficaram).
- Não testado: revert de uma thread `legacy` (criada por versões antigas) e com turno em andamento.

## Capacidades comprovadas no 0.170

Fonte da SPEC-094 (R2: "não testada" conta como não suportada).

| Capacidade (SPEC-094) | Estado | Evidência |
|---|---|---|
| `images` | **comprovada** | R11: *data URL* e `localImage`; todos os modelos com `image` |
| `structuredOutput` | **comprovada** | R12: `outputSchema` → JSON no texto final |
| `budgetUsd` | não suportada | sem campo no protocolo |
| `maxTurns` | não suportada | sem campo no protocolo |
| `planMode` | não suportada | `collaboration_modes` removida; Planejar = `read-only` + instrução |
| `readOnlyEnforced` | **parcial** | R5: `apply_patch` recusado pela política; comandos em `read-only` falham fechados neste host (bwrap). Com o sandbox funcionando, não testado |
| `managedHooks` | não suportada | R15: hook por `-c` fica `untrusted` e não roda; sem *bypass* no App Server |
| `agentFiles` | não suportada | sem agentes em arquivo (decisão 7) |
| `subagents` | não testada | `multi_agent_v2` desligado |
| `mcpConfig` | **parcial** | desligar por servidor com `-c mcp_servers.<n>.enabled=false` + `features.apps=false`; `mcp_servers={}` não funciona; adicionar por `-c` não testado |
| `appMcpServer` | não testada | — |
| `compactNow` | **comprovada** | R14: `thread/compact/start` (gasta uma chamada ao modelo) |
| `steerMidTurn` | **parcial** | R13: `turn/steer` aceito no meio do turno; efeito no texto não observado |
| `liveApprovalChange` | **comprovada (entre turnos)** | `turn/start` muda sandbox e aprovação, e a thread guarda a política (cenário `confianca`) |
| `quota` | **comprovada** | R3: `account/rateLimits/read` + `account/rateLimits/updated` |
| `costUsd` | não suportada | só tokens (decisão 5) |
| `nativeReview` | não testada | `review/start` existe no schema |
| `revertConversation` | **comprovada** (SPEC-110) | `thread/revert` + `thread/fork` no App Server 0.170, sem turno pago (seção "Voltar a conversa") |

Capacidades fora da lista da 094 que as outras specs usam:

| Capacidade | Estado | Evidência |
|---|---|---|
| Sandbox disponível na máquina | **depende do host** | Ubuntu 24.04 padrão: não (AppArmor). Detectável por `configWarning` ou `command/exec` |
| Commit em worktree (`writableRoots`) | **parcial** | perfil do Codex + Landlock: passa com o *git common dir*; o sandbox real não foi confirmado (host) |
| Instruções por `CLAUDE.md` | **comprovada** | R10 |
| Ambiente (`PROMPTORIUM_AGENTE`) | **parcial** | passa fora do sandbox; dentro, não testado (host) |
| Interromper (`turn/interrupt`) | **comprovada** | R13: `status: interrupted` + uso |
| Aprovação por comando (`untrusted`) | **comprovada** no App Server | R7; recusado na CLI |
| Thread sem gravar no global | **comprovada** | `read-only` no `thread/start` + política no turno |

## Turnos gastos

| # | Cenário | Política (thread → turno) | Status |
|---|---|---|---|
| 1 | `leitura` (R5) | `read-only` / `never` | completed |
| 2 | `edicao` (R6) | `workspace-write` / `on-request` | completed |
| 3 | `comando` (R7, R9) | `workspace-write` / `untrusted` | completed |
| 4 | `worktree_com_roots_never` (R8) | `workspace-write` / `never`, `writableRoots=[repo/.git]` | completed (escrita falhou) |
| 5 | `worktree_sem_roots_on_request` (R8) | `workspace-write` / `on-request` | completed (git falhou) |
| 6 | `contexto_claude_md` (R10) | `read-only` / `never` | completed |
| 7 | `contexto_output_schema` (R12, R14) | `read-only` / `never` | completed |
| — | `thread/compact/start` (R14) | — | completed (uma chamada ao modelo) |
| 8 | `imagem` (R11) | `read-only` / `never` | completed |
| 9 | `interromper` (R13) | `read-only` / `never` | interrupted |
| 10 | `hook_turno` (R15) | `danger-full-access` / `never` | completed |
| 11 | `edicao` de novo (R4/R6, abordagem segura) | thread `read-only`; turno `workspace-write` / `on-request` | completed (config.toml intacto) |

Total: **11 turnos + 1 compactação = 12 chamadas pagas**, no teto da spec. Modelo `gpt-5.6-luna`, esforço `low`. O catálogo não traz preço: o "mais barato" foi escolhido pela linha leve (`luna`), entre os modelos com `low` (P5). O uso semanal da conta continuou em 15 % e a janela de 5 h em 0 % durante toda a sondagem.

## Fixtures

`test/fixtures/codex/0.170/`: `handshake`, `leitura`, `edicao`, `edicao-turno`, `comando`, `worktree-com_roots_never`, `worktree-sem_roots_on_request`, `contexto`, `imagem`, `interromper`, `hook_turno`, `sandbox` (`command/exec`) e `hooks-por_c` (`hooks/list`). Cada linha tem `{"dir":"send"|"recv","msg":…}`, com as mensagens nos dois sentidos (P2), sanitizadas. O `FakeCodex.replay` responde cada pedido do app com a resposta gravada ao mesmo método e reemite as notificações e os pedidos do servidor gravados depois dela. As respostas do app às aprovações ficam em `appAnswers`, para comparar com as da sonda (`recordedAnswers`).

O `grep -ri "token\|auth"` do critério de aceite só encontra campos de uso (`inputTokens`, `thread/tokenUsage/updated`…), `authMode: "chatgpt"` e `requiresOpenaiAuth`; nenhuma credencial. O último teste do arquivo confere que não há `/home/`, e-mail, `sk-` nem JWT.
