---
id: SPEC-093
status: concluida
versao: 0.23.0
tipo: pesquisa
epico: 332
issue: 333
depende-de: []
---

# Sondagem do Codex 0.170

## Objetivo

Trocar suposições por evidência registrada antes de religar o Codex. O adaptador em `lib/core/codex/` foi escrito contra o Codex 0.163, e o protocolo do App Server cresceu muito desde então: de cerca de 40 para 109 *requests*. Várias decisões das specs seguintes dependem de perguntas que só um teste real responde.

Exemplo concreto do risco: numa Sessão em worktree com sandbox `workspace-write`, o agente termina a tarefa e roda `git commit`. O git grava em `<repo>/.git/worktrees/<nome>/` e nos objetos da raiz, os dois **fora** do cwd do worktree. Se o sandbox bloquear essa escrita, nenhuma etapa consegue commitar, e a SPEC-096 nasce quebrada. Hoje ninguém sabe se `writableRoots` com o *git common dir* resolve. Outros exemplos do mesmo tipo:

- O app passa `-a untrusted` no terminal embutido (`codex_command.dart`), mas o `--help` do 0.170 só lista `on-request` e `never`.
- O `CodexRun` traduz `thread/tokenUsage/updated` subtraindo `cachedInputTokens` de `inputTokens`. A SPEC-087 exige uma fórmula verificada na versão instalada, e essa ainda não foi.
- O plano supõe que `project_doc_fallback_filenames` faz o Codex ler o `CLAUDE.md` (decisão 6 do épico). Se não fizer, o app precisa gerar `AGENTS.md`.

A saída desta spec é um relatório (`docs/pesquisa/codex-0170.md`), *fixtures* reais para o `fake_codex` e uma tabela de capacidades comprovadas que a SPEC-094 usa como fonte.

## Requisitos

### Sem custo

- R1 · **Versão e ajuda.** Registrar `codex --version`, o `--help` de `codex`, `exec`, `resume`, `fork`, `review`, `login`, `mcp`, `app-server` e `sandbox`, e `codex features list`. Anotar flags que o app usa e sumiram (`-a untrusted`), flags novas úteis (`--add-dir`, `--ignore-user-config`, `-c`) e as *features* estáveis que o app pode usar (`hooks`, `turn/steer`).
- R2 · **Schema do protocolo.** Gerar `codex app-server generate-json-schema` e conferir, método por método, os que o adaptador chama ou trata: `initialize`, `account/read`, `model/list`, `thread/start|resume|fork`, `turn/start|interrupt|steer`, os pedidos de aprovação, `thread/tokenUsage/updated`, `turn/completed`, `item/*`. Para cada um: existe, mudou (campos novos, renomeados ou obrigatórios) ou sumiu. Guardar o hash do schema e a lista dos métodos usados, para a conferência de versão da SPEC-094.
- R3 · **Handshake e conta.** Abrir o App Server num diretório temporário e registrar `initialize`, `account/read`, `model/list` (modelos, esforços e modalidades) e `account/rateLimits/read` (janelas, `planType`, créditos, `rateLimitsByLimitId`). Nenhum desses abre turno.
- R4 · **Arquivos do usuário intactos.** Antes e depois de cada bloco de sondagem, guardar o hash de `~/.codex/config.toml` e a lista de `~/.codex/rules/`. Provar que o app não grava nada no global: só `-c` e variáveis de ambiente, nunca `--trust`, nunca `codex login` pelo app. Não ler `~/.codex/auth.json`.

### Com custo (decisão 9 do épico: cerca de 10 turnos curtos)

Num repositório temporário criado para a sondagem, com prompts de uma linha e o modelo mais barato do `model/list`. Cada turno vira um cenário no relatório.

- R5 · **Somente leitura.** Turno em `read-only` + `never` pedindo para criar um arquivo: confirmar que o sandbox recusa e como a recusa chega (item `commandExecution` ou `fileChange` com `status`).
- R6 · **Edição com aprovação.** Turno em `workspace-write` + `on-request` que cria e altera um arquivo: registrar o item `fileChange` completo (`changes[].path`, `kind`, `diff`), o pedido `item/fileChange/requestApproval` e a resposta `acceptForSession`. Esse payload é a base da SPEC-095.
- R7 · **Comando com aprovação.** Turno que roda `ls` e um comando que falha: registrar `commandExecution` (`command`, `cwd`, `exitCode`, `aggregatedOutput`) e o pedido `item/commandExecution/requestApproval`. Conferir se `untrusted` ainda é aceito pelo App Server.
- R8 · **Commit em worktree.** Num worktree do repositório temporário, turno em `workspace-write` que faz `git add` e `git commit`, primeiro sem e depois com `writableRoots` incluindo o *git common dir*. Registrar o resultado dos dois. Se nenhum funcionar, registrar a alternativa testada (`--add-dir`, `danger-full-access` só para o git, ou o app commitar depois do turno).
- R9 · **Ambiente.** Turno que roda `echo $PROMPTORIUM_AGENTE`, com a variável no ambiente do App Server: confirmar se o sandbox repassa (SPEC-048) ou se precisa de `shell_environment_policy` por `-c`.
- R10 · **Instruções do projeto.** Com só `CLAUDE.md` no repositório e `-c project_doc_fallback_filenames=["CLAUDE.md"]`, perguntar qual é a regra escrita nele. Repetir sem o override. Responde a decisão 6 do épico.
- R11 · **Imagem.** Turno com um PNG pequeno em `UserInput{type:image}` por *data URL* e por caminho local; registrar qual funciona com cada modalidade do `model/list`.
- R12 · **Saída estruturada.** Turno com `outputSchema` simples (`{ok: boolean}`) em `read-only`: registrar onde chega o JSON e se o schema é respeitado.
- R13 · **Interromper e direcionar.** Turno longo interrompido com `turn/interrupt` e outro direcionado com `turn/steer`: registrar o `status` do `turn/completed` (`interrupted`?) e se o uso de tokens chega.
- R14 · **Contexto e compactação.** Registrar `thread/tokenUsage/updated` (`last`, `total`, `modelContextWindow`) ao longo de dois turnos e testar `thread/compact/start` com a thread ociosa: eventos recebidos (`thread/compacted`?), nova leitura depois. Confirmar a fórmula de "contexto atual" que a SPEC-095 vai usar no contrato da SPEC-087.
- R15 · **Hooks sem tocar no global.** Tentar injetar um hook `preToolUse` que nega `rm` por `-c` ou por um `CODEX_HOME` temporário que reaproveite o login sem copiar o `auth.json` (por exemplo, link simbólico criado e removido pela sonda). Registrar o formato da resposta de *deny* e se exige *trust*. Resultado vai para a SPEC-103.
- R16 · **ai-memory.** Um cenário mínimo do ai-memory com o Codex no repositório temporário, com o roteiro que a SPEC-098 definir. Só registrar se funciona e o que gravou; nada é instalado no ambiente da pessoa.

### Saída

- R17 · **Relatório.** `docs/pesquisa/codex-0170.md` com, por cenário: comando ou mensagem JSON-RPC, payload sanitizado (`redactJson`), resultado, e a conclusão com a spec que ela destrava. No fim, a tabela **Capacidades comprovadas no 0.170** (uma linha por capacidade da SPEC-094: comprovada, parcial, não suportada, não testada) e a lista de turnos gastos.
- R18 · **Fixtures.** As transcrições JSON-RPC dos cenários R3 e R5–R14, sanitizadas, em `test/fixtures/codex/0.170/`. O `fake_codex` ganha um modo que reproduz uma transcrição, e um teste confere que o `CodexRun` atual não quebra com elas (falhas viram itens no relatório, não correções nesta spec).
- R19 · **Correções óbvias registradas, não feitas.** Divergências entre adaptador e schema viram uma lista no relatório, apontando a spec que corrige (094, 095 ou 096). Esta spec não altera código de produção.

## Fora do escopo

- Corrigir o adaptador, as políticas de permissão ou o `untrusted` (SPEC-094 e SPEC-096).
- Religar o Codex em qualquer tela.
- Sondar MCP, skills e agentes a fundo (SPEC-105, SPEC-104, SPEC-106). Aqui só entram o que o schema mostra e o necessário para R15.
- Medir desempenho ou memória do App Server.
- Passar de 10 a 12 turnos pagos. Se faltar orçamento, o cenário fica "não testado" no relatório.

## Decisões em aberto

- P1 · **Onde fica a sonda.** (a) Script em `docs/pesquisa/codex-0170.py`, como as sondas anteriores (`contexto-e-compactacao.py`); (b) um teste de integração marcado para não rodar no CI. **Recomendação:** (a), com a parte sem custo rodando sozinha e a parte paga atrás de uma flag `--pago`, para nunca gastar cota por engano.
- P2 · **Formato das fixtures.** (a) Uma transcrição JSONL por cenário, com as mensagens nos dois sentidos; (b) só as respostas do servidor. **Recomendação:** (a), para o `fake_codex` conferir também o que o app enviou.
- P3 · **Conferência do schema na partida.** Gerar o schema leva tempo. **Recomendação:** medir aqui o tempo do `generate-json-schema` e deixar a decisão para a SPEC-094 (cache por versão, ou só a lista de métodos).
- P4 · **Se o commit em worktree falhar (R8).** **Recomendação:** registrar as alternativas com o resultado de cada uma e levar a escolha para a T3 da SPEC-096; a preferida é o app incluir o *git common dir* nas `writableRoots`, e a de reserva é o app commitar depois do turno.
- P5 · **Modelo das sondas pagas.** **Recomendação:** o modelo mais barato do `model/list` com esforço `low`; só R11 usa um modelo com modalidade de imagem, se o barato não tiver.

## Design

### Arquivos

| Arquivo | Mudança |
|---|---|
| `docs/pesquisa/codex-0170.md` | Novo: relatório (R17) |
| `docs/pesquisa/codex-0170.py` | Novo: sonda (P1) |
| `test/fixtures/codex/0.170/*.jsonl` | Novo: transcrições sanitizadas (R18) |
| `test/core/codex/fake_codex.dart` | Modo de reprodução de transcrição |
| `test/core/codex/codex_0170_fixtures_test.dart` | Novo: o `CodexRun` lê as transcrições sem quebrar |
| `docs/pesquisa/plano-codex.md` | Plano técnico do épico (já incluído neste branch) |

**Migração do banco:** não.

### Dependências

Nenhuma. Destrava todas as outras do épico: SPEC-094 (capacidades e versão), SPEC-095 (payloads de arquivo, comando e uso), SPEC-096 (worktree, interromper, terminal), SPEC-097 (cota), SPEC-098 (ai-memory) e SPEC-103 (hooks).

## Tarefas

| Tarefa | Entrega | Requisitos |
|---|---|---|
| T1 · Sem custo | Sonda sem turno, schema, handshake, hash dos arquivos globais | R1–R4 |
| T2 · Com custo | Cenários pagos no repositório temporário | R5–R16 |
| T3 · Relatório e fixtures | `codex-0170.md`, tabela de capacidades, fixtures e teste | R17–R19 |

## Critérios de aceite

- [x] O relatório registra versão, ajuda e *features* do 0.170, e lista as flags que o app usa e sumiram [R1] verificar: seção "CLI" de `docs/pesquisa/codex-0170.md`.
- [x] Cada método usado pelo adaptador aparece como existe, mudou ou sumiu, com o hash do schema [R2] verificar: tabela "Protocolo" do relatório.
- [x] `~/.codex/config.toml` e `~/.codex/rules/` têm o mesmo hash antes e depois de toda a sondagem [R4] verificar: saída da sonda no relatório.
- [x] Os cenários R5–R16 têm comando, payload sanitizado, resultado e conclusão, ou "não testado" com o motivo [R5–R16] verificar: leitura do relatório.
- [x] O commit em worktree tem resultado registrado com e sem `writableRoots`, e a alternativa quando falha [R8] verificar: cenário "Worktree" do relatório.
- [x] A fórmula de contexto atual do Codex está escrita com o payload que a comprova [R14] verificar: cenário "Contexto" do relatório.
- [x] A tabela de capacidades comprovadas cobre todas as capacidades da SPEC-094 [R17] verificar: tabela no fim do relatório.
- [x] As fixtures não têm credenciais nem caminhos pessoais e o teste de reprodução passa [R18] verificar: `flutter test test/core/codex/codex_0170_fixtures_test.dart` e `grep -ri "token\|auth" test/fixtures/codex/0.170/`.
- [x] No máximo 12 turnos pagos, listados no relatório [R5–R16] verificar: lista de turnos do relatório.

## Telas

Sem tela nova. O diagrama abaixo mostra os blocos da sondagem e a spec que cada um destrava.

| PNG | O que mostra |
|---|---|
| `docs/mockups/spec-093/1-mapa-da-sondagem.png` | Os três blocos (sem custo, com custo, saída), os cenários de cada um e as specs que dependem deles |
