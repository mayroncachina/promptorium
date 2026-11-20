# Sonda — medição de contexto e compactação (SPEC-087 T1)

CLI **2.1.329**, Haiku (troca para Sonnet no cenário 4), 20/11/2026, num repositório temporário
descartável. Script: [`contexto-e-compactacao.py`](contexto-e-compactacao.py)
(`python3 contexto-e-compactacao.py claude <cenário>`), sempre no modo que o app usa:
`-p --input-format stream-json --output-format stream-json --verbose --permission-prompt-tool stdio`.
Os payloads abaixo estão sanitizados: `uuid`/`session_id` viram `<uuid>`, caminhos viram
`<caminho>`, e campos grandes que não interessam (lista de skills, `gridRows`) foram cortados.

## Resumo

| Pergunta | Resposta no CLI instalado | Uso no app |
|---|---|---|
| Tamanho atual do contexto | `assistant.message.usage` de cada chamada de nível superior: `input_tokens + cache_creation_input_tokens + cache_read_input_tokens`. É o mesmo número que o CLI chama de `totalTokens` no diagnóstico (26.550 = 2 + 173 + 26.375). | Medição (R1). Saída não entra. |
| Capacidade da janela | `result.modelUsage[<modelo>].contextWindow` (1.000.000 no Haiku/Sonnet desta conta). Só chega no fim do turno. | Capacidade (R2). Antes do primeiro `result`, desconhecida: total sem %. |
| Limiar da compactação automática | Control request **`get_context_usage`** (`detail: "summary"`) devolve `autoCompactThreshold`, `maxTokens`, `isAutoCompactEnabled` e `autocompactSource`. Com `--autocompact 200k`: `maxTokens` 200.000 e limiar **167.000**; com `100k`: limiar **67.000**; sem a flag: limiar 967.000 (janela − 33 mil de reserva, categoria `autocompact_buffer`). | Limiar marcado na barra (R7). O valor enviado (`--autocompact 200k`) aparece como configuração; o limiar efetivo é o informado. |
| Custo do diagnóstico | `summary` “responde com o `usage` da última resposta e estimativas locais, sem chamadas de contagem de tokens” (descrição do próprio schema). Não abre turno, não aparece em `modelUsage`. `full` usa a API de contagem: **não usado**. | Pedido após cada `result` de Claude (R12: sem turno faturável). |
| Composição | `get_context_usage.categories` (`system_prompt`, `system_tools`, `skills`, `messages`, `memory_files`, `mcp_tools`…) com `kind` `used`/`deferred`/`buffer`/`free`. As `used` somam o total, mas são **estimativas locais**. `memoryFiles` vem sempre vazio em `-p` (o CLI esvazia de propósito). | Fontes “informado pelo agente · ≈ estimado”. A barra mostra só a composição medida do `usage` (entrada, escrita e leitura de cache). |
| Início da compactação | `system/status` `status: "compacting"` (pode repetir, com `compact_output_chars` crescendo). | Estado “compactando” só com esse evento (R8). |
| Fim / falha | `system/status` `status: null` com `compact_result: "success"` ou `"failed"` + `compact_error` (ex.: `too_few_groups`). | “concluída” / “falhou”. |
| Marcador | `system/compact_boundary` com `compact_metadata.trigger` (`auto`/`manual`), `pre_tokens`, `post_tokens`, `duration_ms`, e `uuid` próprio. `post_tokens` **não** é a próxima leitura (7.516 contra 27.043 medidos na chamada seguinte: prompt de sistema e ferramentas voltam). | Invalida a leitura atual: “Contexto compactado · aguardando medição” até a próxima chamada. Deduplicado pelo `uuid`. |
| Compactar agora | **Suportado** em `-p` stream-json: a mensagem de usuário `/compact` (ou `/compact <foco>`) roda o comando nativo — `status compacting` → `compact_result: success` → `compact_boundary trigger: manual` → `result` com `num_turns: 0`. O `init` lista `compact`, `autocompact` e `context` em `slash_commands`. | Botão “Compactar agora” com o processo ocioso, um pedido por vez, foco opcional (R9). |
| Troca de modelo | `control_request set_model` responde `{"model": "claude-sonnet-5-5"}`; o próximo `system/init` e o `assistant.message.model` já trazem o novo modelo. | Marcador “troca de modelo”; capacidade e limiar do modelo anterior são invalidados até nova informação (R3). |
| Retomada (`--resume`) | `get_context_usage` antes de qualquer turno devolve o `apiUsage` gravado da última chamada (26.644): é uma leitura **antiga**. | Leitura reconstruída dos eventos gravados, marcada “não é ao vivo” (R3). |
| Dois forks (`--resume --fork-session`) | Cada fork tem `session_id` próprio e começa do mesmo contexto herdado (26.684 nos dois); as leituras seguintes evoluem separadas. | Cada execução tem o seu rastreador; nada é somado (R11). |
| Subagentes | Mensagens com `parent_tool_use_id` têm `usage` próprio da janela do subagente. | Ignoradas no medidor principal: “contexto separado · medição indisponível” (R11). |

## Modo interativo e status line

- O modo interativo e a status line não fazem parte do transporte do app (as sessões e conversas
  usam `-p` stream-json; o terminal da sessão abre o TUI, que já mostra `/context` por conta própria).
- A status line recebe `context_window` (tamanho, uso atual e porcentagem) **só no TUI**. Ela exigiria
  configurar `statusLine` no `~/.claude/settings.json` da pessoa — vetado pela spec. Como
  `get_context_usage` entrega os mesmos números no modo `-p`, **nenhuma ponte de status line foi criada**.
- `/context` como mensagem de usuário em `-p` imprimiria o relatório como texto; o control request
  devolve o mesmo dado estruturado sem passar pelo histórico, por isso é o caminho adotado.

## Cenários

### 1–3. Primeira resposta, leitura de arquivo e cache

Uma chamada por mensagem `assistant` (várias linhas do mesmo `message.id` repetem o `usage`):

```json
{"type": "assistant", "message": {"model": "claude-haiku-5-5", "usage": {"input_tokens": 2, "cache_creation_input_tokens": 12918, "cache_read_input_tokens": 13392, "output_tokens": 4}}, "parent_tool_use_id": null}
{"type": "assistant", "message": {"model": "claude-haiku-5-5", "usage": {"input_tokens": 2, "cache_creation_input_tokens": 9698, "cache_read_input_tokens": 16677, "output_tokens": 16}}, "parent_tool_use_id": null}
{"type": "assistant", "message": {"model": "claude-haiku-5-5", "usage": {"input_tokens": 2, "cache_creation_input_tokens": 173, "cache_read_input_tokens": 26375, "output_tokens": 1}}, "parent_tool_use_id": null}
```

O `result` traz o **acumulado** do turno (`usage` soma as chamadas: 43.052 de leitura de cache em
duas chamadas) e a capacidade:

```json
{"type": "result", "subtype": "success", "num_turns": 1, "usage": {"input_tokens": 2, "cache_creation_input_tokens": 12918, "cache_read_input_tokens": 13392, "output_tokens": 4}, "modelUsage": {"claude-haiku-5-5": {"inputTokens": 2, "cacheReadInputTokens": 13392, "cacheCreationInputTokens": 12918, "contextWindow": 1000000, "maxOutputTokens": 128000}}}
```

Conclusão: somar turnos ou usar `result.usage` dá consumo, não contexto. O medidor usa a última
chamada; o “Tokens acumulados” do Prompt continua com a soma.

`get_context_usage` (`summary`), sem `--autocompact`:

```json
{"type": "control_response", "response": {"subtype": "success", "request_id": "ctx-2", "response": {"categories": [{"id": "system_prompt", "name": "System prompt", "tokens": 3531, "kind": "used"}, {"id": "system_tools", "name": "System tools", "tokens": 4866, "kind": "used"}, {"id": "system_tools_deferred", "name": "System tools (deferred)", "tokens": 20278, "isDeferred": true, "kind": "deferred"}, {"id": "skills", "name": "Skills", "tokens": 7454, "kind": "used"}, {"id": "messages", "name": "Messages", "tokens": 10699, "kind": "used"}, {"id": "autocompact_buffer", "name": "Autocompact buffer", "tokens": 33000, "kind": "buffer"}, {"id": "free_space", "name": "Free space", "tokens": 940450, "kind": "free"}], "totalTokens": 26550, "maxTokens": 1000000, "rawMaxTokens": 1000000, "autocompactSource": "model-default", "percentage": 3, "model": "claude-haiku-5-5", "memoryFiles": [], "mcpTools": [], "mcpInstructions": [], "agents": [], "autoCompactThreshold": 967000, "isAutoCompactEnabled": true, "apiUsage": {"input_tokens": 2, "output_tokens": 59, "cache_creation_input_tokens": 173, "cache_read_input_tokens": 26375}}}}
```

### 4. Troca de modelo

```json
{"type": "control_response", "response": {"subtype": "success", "request_id": "m-1", "response": {"model": "claude-sonnet-5-5"}}}
{"type": "assistant", "message": {"model": "claude-sonnet-5-5", "usage": {"input_tokens": 2, "cache_creation_input_tokens": 13351, "cache_read_input_tokens": 13392, "output_tokens": 5}}, "parent_tool_use_id": null}
```

O cache do modelo anterior não serve ao novo (13.351 de escrita), mas o tamanho do contexto segue
parecido: a troca muda limites e custo, não apaga a conversa.

### 5. `/compact` manual com `--autocompact 200k`

Antes: `maxTokens` 200.000, `autoCompactThreshold` 167.000, `autocompactSource: "settings"`.

```json
{"type": "system", "subtype": "status", "status": "compacting", "session_id": "<uuid>", "uuid": "<uuid>"}
{"type": "system", "subtype": "status", "status": null, "compact_result": "success", "session_id": "<uuid>", "uuid": "<uuid>"}
{"type": "system", "subtype": "compact_boundary", "session_id": "<uuid>", "uuid": "<uuid>", "compact_metadata": {"trigger": "manual", "pre_tokens": 26316, "post_tokens": 7516, "cumulative_dropped_tokens": 18800, "duration_ms": 2836}, "logical_parent_uuid": "<uuid>"}
{"type": "result", "subtype": "success", "num_turns": 0, "usage": {"input_tokens": 0, "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "output_tokens": 0}, "modelUsage": {"claude-haiku-5-5": {"inputTokens": 2019, "cacheReadInputTokens": 42987, "cacheCreationInputTokens": 9636, "contextWindow": 1000000, "maxOutputTokens": 128000}}}
```

O texto após `/compact ` vira o foco do resumo. Depois da compactação, `get_context_usage` volta com
`apiUsage: null` e `totalTokens` estimado (25.809): o app **não** trata isso como medição. A chamada
seguinte mediu 27.043.

### 6. Retomada

`--resume <id>` e `get_context_usage` antes de enviar nada: `totalTokens` 26.644 com o `apiUsage`
gravado da última chamada da sessão original. Nenhuma chamada nova foi feita.

### 7. Dois forks

Dois `--resume <id> --fork-session` seguidos: `session_id` diferentes, os dois começam em 26.684
(o contexto herdado) e o `get_context_usage` de cada um responde só pela própria execução.

### 8. Compactação automática (`--autocompact 100k`, limiar 67.000)

Três mensagens grandes (~27 mil tokens cada). A checagem acontece **antes de enviar** a mensagem
seguinte, quando a última leitura passou do limiar:

```json
{"type": "system", "subtype": "status", "status": "compacting", "compact_output_chars": 0, "uuid": "<uuid>"}
{"type": "system", "subtype": "status", "status": null, "compact_result": "failed", "compact_error": "too_few_groups", "uuid": "<uuid>"}
{"type": "system", "subtype": "status", "status": "compacting", "compact_output_chars": 0, "uuid": "<uuid>"}
{"type": "system", "subtype": "status", "status": null, "compact_result": "success", "uuid": "<uuid>"}
{"type": "system", "subtype": "compact_boundary", "uuid": "<uuid>", "compact_metadata": {"trigger": "auto", "pre_tokens": 143482, "post_tokens": 29401, "cumulative_dropped_tokens": 114081, "duration_ms": 5529, "preserved_segment": {"head_uuid": "<uuid>", "anchor_uuid": "<uuid>", "tail_uuid": "<uuid>"}}, "logical_parent_uuid": "<uuid>"}
{"type": "system", "subtype": "status", "status": "compacting", "compact_output_chars": 0, "uuid": "<uuid>"}
{"type": "system", "subtype": "status", "status": "compacting", "compact_output_chars": 824, "uuid": "<uuid>"}
{"type": "system", "subtype": "status", "status": null, "compact_result": "success", "uuid": "<uuid>"}
{"type": "system", "subtype": "compact_boundary", "uuid": "<uuid>", "compact_metadata": {"trigger": "auto", "pre_tokens": 75023, "post_tokens": 7825, "cumulative_dropped_tokens": 181279, "duration_ms": 36188}, "logical_parent_uuid": "<uuid>"}
```

Leituras: 74.139 → (falhou) 121.881 → (compactou) 74.993 → (compactou) 27.347. Observações:

- a primeira tentativa falhou e a conversa seguiu normal (o turno respondeu);
- a leitura pode passar do `maxTokens` da janela de compactação (121.881 > 100.000): esse valor
  não é um teto, e a capacidade real continua sendo `contextWindow`;
- `compacting` repete no mesmo ciclo: o app registra o ciclo uma vez.

## Decisões para a implementação

1. **Medição**: `ContextTracker` lê só `assistant` de nível superior, substitui (não soma) a leitura e
   deduplica pelo `message.id`.
2. **Capacidade**: `modelUsage[modelo].contextWindow` do `result`; sem ele, total sem porcentagem.
   Nunca inferida pelo nome do modelo.
3. **Limiar**: `autoCompactThreshold` do `get_context_usage` (`summary`), pedido pelo app depois de
   cada `result` das execuções Claude e gravado como evento do app `promptorium_context_usage`
   (JSON versionado, só números e nomes de categoria; nenhum caminho de skill nem conteúdo).
   Sem a resposta, o painel mostra o `--autocompact` enviado como configuração, sem marca na barra.
4. **Compactação**: estados vindos de `system/status` e `compact_boundary`; leitura corrente
   invalidada até a próxima chamada; deduplicação por `uuid`.
5. **Compactar agora**: mensagem `/compact [foco]` na sessão viva, só com o processo ocioso e só em
   Claude. Outros provedores explicam a indisponibilidade.
6. **Mudança de `--autocompact`**: testado `control_request apply_flag_settings` com
   `{"autoCompactWindow": 300000}` numa execução iniciada com `--autocompact 200k`: a resposta é
   `success`, mas o `get_context_usage` seguinte continua com `maxTokens` 200.000 e limiar 167.000.
   Sem confirmação de aplicação em tempo de execução, a alteração vale para as próximas execuções e o
   painel mantém visível o valor efetivo da atual (R7). Nenhuma sessão viva é reiniciada.
