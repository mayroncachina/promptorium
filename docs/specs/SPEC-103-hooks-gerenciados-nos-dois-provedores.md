---
id: SPEC-103
status: rascunho
versao: 0.23.0
tipo: melhoria
epico: 332
depende-de: [SPEC-093, SPEC-094, SPEC-095, SPEC-096]
---

# Hooks gerenciados nos dois provedores

## Objetivo

Os hooks que o app põe em cada sessão (`lib/core/claude/managed_hooks.dart`) passam a valer também no Codex: **Bloquear comandos perigosos**, **Formatar ao editar**, **Registrar fim da sessão** e o **Vigia de segredos** (SPEC-085). No Claude Code, nada muda: eles continuam num `--settings` temporário. No Codex 0.170, os hooks são estáveis (`hooks = true`), com `preToolUse`, `postToolUse`, `sessionEnd` e `hooks/list`. Esta spec traduz o mesmo plano de hooks para eles **sem gravar nada no `~/.codex`** e, quando não der para ativar, mostra claramente que a garantia ficou menor (decisão 1 do épico #332).

### O problema, com um exemplo

Numa sessão Codex em worktree (SPEC-096), na SPEC-031 · Pagamento com Stripe, o agente escreve a chave de teste em `src/config/pagamento.ts` e roda `git add -A && git commit -m "integra Stripe"`. Em seguida, tenta `git push --force` para "limpar" a branch. Hoje:

1. `ManagedHooks.prepare` só gera o `settings.json` do Claude, então o Codex roda os dois comandos.
2. O commit com a chave fica no histórico local. O Vigia só o pega ao fim do turno (SPEC-085 R2), e o push só é barrado se for o app a fazê-lo. O `git push --force` do próprio agente não é barrado.
3. O `formatar:` do projeto (`dart format {arquivo}`) não roda depois das edições do Codex, e o fim da sessão não aparece na timeline.
4. A tela Automações diz "Ficam num settings.json temporário de cada sessão (--settings)", sem dizer que no Codex nada disso vale.

Depois desta spec, a mesma sessão Codex sobe com os hooks do app como **hooks de sessão** do Codex. O `git commit` é recusado antes de rodar ("Vigia de segredos bloqueou o commit · 1 achado"), e o `git push --force` também ("Promptorium: comando bloqueado (push forçado)"). O `dart format` roda nos arquivos do patch, e a timeline mostra os mesmos cartões do Claude, com o selo do provedor. Se a versão instalada não aceitar hooks de sessão sem confiança gravada, a sessão mostra **Hooks: só pós-turno**, e a tela Automações explica o que continua valendo e o que não.

## Requisitos

### Um plano, dois adaptadores

- R1 · **Plano de hooks neutro.** `ManagedHooks.prepare` passa a montar um `ManagedHookPlan` independente do provedor: os hooks ligados, as regras de bloqueio (das embutidas, do `bloquear-comandos:`, do PR importado e do worktree), o comando `formatar:`, as regras e ressalvas do Vigia e a pasta da sessão (`~/.promptorium/run/<sessão>/`). Cada provedor tem um adaptador que traduz o plano:
  - o **Claude** gera o `settings.json` de hoje (sem mudança de comportamento);
  - o **Codex** gera os overrides de configuração da sessão (R3).

  O script Python é um só para os dois, e o `hooks.log` mantém o formato atual, com o campo `provedor` acrescentado.
- R2 · **Eventos e ferramentas traduzidos.** O script reconhece os dois formatos de entrada, com os nomes que a SPEC-093 registrar para o 0.170:

  | Hook do app | Claude Code | Codex |
  |---|---|---|
  | Bloquear comandos e Vigia de segredos | `PreToolUse` em `Bash`, com `tool_input.command` | `preToolUse` na ferramenta de shell, com o comando que ela recebe |
  | Formatar ao editar | `PostToolUse` em `Edit`/`Write`/`MultiEdit`, com `file_path` | `postToolUse` em `apply_patch`, com os caminhos tirados das linhas `*** Add File:` e `*** Update File:` do patch (arquivo apagado não formata) |
  | Registrar fim da sessão | `SessionEnd`, com `reason` | `sessionEnd` |

  A resposta de recusa sai no formato de cada provedor. O motivo chega ao agente nos dois, com o mesmo texto de hoje ("Promptorium: comando bloqueado (%s). Não tente contornar; se for necessário, peça ao usuário.").
- R3 · **Injeção sem tocar no `~/.codex`.** Os hooks do app entram pela configuração da sessão do Codex: `thread/start.config` ou `-c` no `codex app-server`, conforme a SPEC-093 comprovar. Eles aparecem no `hooks/list` com a origem `sessionFlags`. O app nunca usa `--trust`, nunca escreve no `~/.codex/config.toml` nem nos registros de confiança de hooks, e nunca troca o `CODEX_HOME`. Os arquivos da sessão ficam na mesma pasta temporária do Claude e são apagados no fim da sessão (`ManagedHooks.cleanup`).
- R4 · **Confiança só para a sessão.** Se o Codex exigir confiança para rodar hooks de sessão, o app só aceita mecanismos que valem para aquele processo e não persistem: o equivalente de `--dangerously-bypass-hook-trust` aplicado só aos hooks do app, ou a origem `sessionFlags` já confiável. Se o 0.170 só aceitar confiança gravada, os hooks do app no Codex ficam no modo pós-turno (R7) até uma versão que permita, e a tela Automações diz por quê. Os hooks do usuário e os do projeto (`.codex/` do repositório) continuam com a confiança que já têm. O app não muda a confiança de nenhum deles.

### Confirmar, mostrar e cair com aviso

- R5 · **Confirmar a ativação.** Depois do `thread/start`, o app chama `hooks/list` com o `threadId` e confere se cada hook do plano está presente, ligado e com confiança que permite rodar (`trustStatus` `managed` ou `trusted`). O resultado vira o estado da sessão: **Hooks nativos** (todos ativos), **Hooks parciais** (lista dos inativos) ou **Hooks só pós-turno**. O app nunca supõe que um hook está ativo só porque o configurou. Erros e avisos do `hooks/list` vão para o log de depuração e para a dica do estado.
- R6 · **Mesma atividade na timeline.** As notificações `hook/started` e `hook/completed` do Codex e as linhas do `hooks.log` viram os mesmos `HookActivity` e os mesmos cartões de hoje (bloqueio, formatado, fim, Vigia). O cartão ganha o selo do provedor só quando a sessão é do Codex. O "Último:" de cada hook em Automações vale para os dois provedores e diz de qual veio. Um mesmo evento chegando pelas duas vias aparece uma vez só.
- R7 · **Modo pós-turno, explícito.** Quando um hook não ficou ativo no Codex (R4, R5), vale o melhor substituto, e a sessão diz qual:
  - **Vigia de segredos:** o modo pós-turno da SPEC-085 R2 (commits conferidos ao fim do turno, bloqueio no push feito pelo app);
  - **Formatar ao editar:** ao fim do turno, o app roda o `formatar:` nos arquivos alterados no turno (`FileChangeEvent`, da SPEC-095) e mostra o resultado no mesmo cartão;
  - **Registrar fim da sessão:** o app registra o fim quando o `CodexRun` termina, com o motivo que conhece;
  - **Bloquear comandos:** quando o modo pede aprovação de comandos, o pedido `item/commandExecution/requestApproval` passa pelas mesmas regras antes do balão, e um comando bloqueado é recusado com o motivo, sem chegar à pessoa (P2). No YOLO, que não pede aprovação, não há bloqueio prévio. Nesse caso, o diálogo da sessão avisa antes de começar: "No Codex sem hooks, o YOLO não bloqueia comandos perigosos".

  A timeline avisa uma vez por sessão com o que ficou no pós-turno.

### Tela e garantias

- R8 · **Automações por provedor.** A tela Configurações → Automações (hooks) mostra, para cada hook, uma coluna por provedor com o estado: **Antes da ferramenta**, **Ao fim do turno** ou **Indisponível**, cada um com o motivo numa dica. O texto do rodapé passa a explicar os dois mecanismos ("Claude Code: settings.json temporário (--settings). Codex: hooks de sessão (-c). Nada é escrito no ~/.claude nem no ~/.codex"). A seção Vigia de segredos troca "no Codex e sem python3, ao fim do turno e antes do push" pelo estado real da última verificação. Ligar ou desligar um hook vale para os dois provedores, como hoje, a partir da próxima sessão iniciada ou retomada.
- R9 · **Estado na sessão.** O cabeçalho da sessão Codex mostra um chip com o estado do R5 ("Hooks nativos" em teal, "Hooks só pós-turno" em âmbar). Clicar no chip abre a lista dos hooks e do substituto de cada um. A linha da tela Atividades e o card do Quadro não mudam.
- R10 · **Sem `python3`.** Continua como hoje nos dois provedores: os hooks ficam desligados, e o Vigia usa o pós-turno. O aviso em Automações vale para os dois.
- R11 · **Testes de garantia.** Para cada provedor, um teste prova que um comando das regras embutidas é recusado antes de rodar quando o hook está ativo, e que o modo pós-turno é anunciado quando não está. Os testes do Codex usam o `fake_codex` com as respostas de `hooks/list` e as notificações de hook gravadas na SPEC-093. Um teste de paridade compara as decisões do script para entradas equivalentes do Claude e do Codex, como o `secret_parity_test.dart` já faz para o Vigia.

## Fora do escopo

- Hooks novos que só o Codex tem (`userPromptSubmit`, `stop`, `preCompact`, `permissionRequest`) e hooks que o usuário edita pelo app.
- Regras do execpolicy (`.rules`) do Codex como substituto do bloqueio. Elas ficam no `~/.codex/rules`, e esta spec não escreve lá (P3).
- Compactação e `preCompact`/`postCompact`: SPEC-107 (Contexto e compactação no Codex).
- Mudar as regras do Vigia, as regras de bloqueio ou o `formatar:`.
- Hooks nas execuções estruturadas (SPEC-100). Elas são somente leitura e não usam hooks hoje em nenhum provedor.

## Decisões em aberto

- P1 · **Se o 0.170 só rodar hooks com confiança gravada.** (a) modo pós-turno com aviso (R7) até uma versão que permita; (b) gravar a confiança só dos hooks do app no `~/.codex`, com o consentimento da pessoa; (c) oferecer um `CODEX_HOME` próprio do app. **Recomendação: (a).** (b) quebra a regra de nunca escrever na configuração global do usuário, e (c) exigiria copiar ou ler o `auth.json`, que o app nunca lê. A SPEC-093 diz qual caso vale. Se for (a), esta spec ainda entrega o R6 a R11.
- P2 · **Bloqueio pela aprovação de comandos.** (a) aplicar as regras de bloqueio aos pedidos de aprovação do Codex quando os hooks não estão ativos; (b) só pós-turno. **Recomendação: (a).** O pedido já passa pelo app antes de chegar à pessoa, então barrar ali uma regra embutida (push forçado, `rm -rf ~`) é barato e dá ao modo Editar a mesma proteção do hook. No YOLO não há pedido, e o aviso do R7 cobre esse caso.
- P3 · **Execpolicy temporária.** (a) fora do escopo; (b) investigar na SPEC-093 se o Codex aceita um arquivo `.rules` por `-c`, sem o `~/.codex`. **Recomendação: (b) como pergunta da sondagem, sem compromisso aqui.** Se funcionar, o bloqueio no YOLO sem hooks vira uma spec pequena depois.
- P4 · **Selo do provedor nos cartões de hook.** (a) só nas sessões Codex; (b) em todas. **Recomendação: (a).** Quem só usa o Claude não ganha ruído, e numa sessão Codex o selo explica por que o texto do motivo pode ser diferente.

## Design

### Arquivos tocados

- `lib/core/claude/managed_hooks.dart`: separar `ManagedHookPlan` (neutro) do adaptador Claude e acrescentar o `provedor` no `hooks.log` e no script (formatos de entrada e de recusa do Codex, caminhos do `apply_patch`). O arquivo pode ir para `lib/core/providers/managed_hooks/` se a revisão preferir. O adaptador Claude continua em `lib/core/claude/`.
- **Novo:** `lib/core/codex/codex_hooks.dart`: overrides da sessão, conferência por `hooks/list`, tradução de `hook/started` e `hook/completed` em `HookActivity`.
- `lib/core/codex/codex_provider.dart`: repassar a configuração no `thread/start` ou no início do processo, expor `hooks/list` e as notificações de hook.
- `lib/features/sessions/session_manager.dart`: preparar o plano para os dois provedores, guardar o estado do R5, aplicar o pós-turno do R7 (formatar e fim) e o filtro de aprovação do P2.
- `lib/features/settings/automations_view.dart` e a seção Vigia de segredos: colunas por provedor e textos (R8).
- Cabeçalho da sessão em `lib/features/sessions/` (chip do R9) e cartões de hook na `timeline.dart` (selo do P4).
- Testes: `test/core/claude/managed_hooks_test.dart` (paridade), `test/core/codex/codex_hooks_test.dart` (novo) e o `fake_codex` com `hooks/list`.

### Migração

**Não.** O estado dos hooks é por processo e vive em memória e nos arquivos temporários da sessão.

### Dependências

- SPEC-093 (Sondagem do Codex 0.170): como injetar hooks de sessão, a confiança exigida, os nomes das ferramentas no evento e o formato da recusa. Esta spec só começa a implementar o R3 e o R4 depois desse registro. O R6 a R11 não dependem dele.
- SPEC-094 (Capacidades e opções por provedor): capacidade `managedHooks` por provedor e versão.
- SPEC-095 (Eventos neutros): `FileChangeEvent` e `CommandEvent` para o pós-turno do formatador e para a timeline.
- SPEC-096 (Codex no Prompt e nas Sessões): sessões Codex, aprovações e o ciclo de vida do `CodexRun`.
- Melhora a [SPEC-101](SPEC-101-executar-spec-com-o-codex.md): as etapas no Codex saem do modo pós-turno do Vigia (SPEC-101 R12) quando os hooks estão ativos.

## Tarefas

- T1 · Plano neutro e adaptador Claude (R1): separar o plano sem mudar o `settings.json` do Claude e acrescentar o `provedor` ao log. Verificar: os testes atuais de hooks passam, com um teste novo do log.
- T2 · Script nos dois formatos (R2) e paridade (R11). Verificar: testes do script com entradas Claude e Codex gravadas, cobrindo bloqueio, Vigia, formatar com patch de vários arquivos e fim.
- T3 · Adaptador Codex (R3–R5): overrides, confiança só da sessão, conferência por `hooks/list` e estado da sessão. Verificar: testes com o `fake_codex` (todos ativos, parcial, sem confiança, `hooks/list` com erro) e teste de que nenhum argumento contém `--trust` nem caminho do `~/.codex`.
- T4 · Atividade e pós-turno (R6, R7, P2): notificações em `HookActivity`, sem duplicar, formatar e fim pós-turno, e filtro de aprovação. Verificar: testes do `session_manager` com o `fake_codex`.
- T5 · Telas (R8–R10): Automações por provedor, Vigia, chip da sessão e selo nos cartões. Verificar: testes de widget.
- T6 · E2E no app isolado: sessão Codex em worktree com commit com segredo e `git push --force`, nos modos nativo e pós-turno (forçado por teste). Verificar: capturas reais e relatório em `docs/pesquisa/`.

## Critérios de aceite

- [ ] O `settings.json` do Claude é idêntico ao de hoje para as mesmas entradas [R1] verificar: teste de regressão do adaptador Claude.
- [ ] O script decide igual para entradas equivalentes do Claude e do Codex e responde no formato de cada um [R2, R11] verificar: teste de paridade.
- [ ] Nenhuma sessão Codex grava no `~/.codex`, usa `--trust` ou troca o `CODEX_HOME` [R3, R4] verificar: teste dos argumentos e do ambiente do processo e inspeção manual do `~/.codex` antes e depois do e2e.
- [ ] O estado da sessão vem do `hooks/list`, nunca da configuração enviada [R5] verificar: teste com o `fake_codex` devolvendo um hook inativo.
- [ ] Com os hooks ativos no Codex, push forçado e commit com segredo são recusados antes de rodar e geram os mesmos cartões do Claude, uma vez só [R2, R6] verificar: teste com o `fake_codex` e e2e.
- [ ] Sem hooks ativos, cada hook usa o substituto do R7, e a sessão anuncia o pós-turno uma vez [R7] verificar: testes do `session_manager`.
- [ ] No modo Editar sem hooks, um comando das regras embutidas é recusado no pedido de aprovação, e o YOLO sem hooks avisa antes de começar [R7, P2] verificar: testes do `session_manager` e de widget.
- [ ] Automações e o chip da sessão mostram o estado real por provedor, com o motivo [R8, R9] verificar: testes de widget.
- [ ] No app isolado, a sessão Codex bloqueia o push forçado e o commit com segredo, e o modo pós-turno aparece quando forçado [R1–R11] verificar: capturas reais 1366×768 e relatório.

## Telas

Mockup: [canvas do Claude Design](https://claude.ai/artifact/L8QfgVnHyijyB5Zfvuih4S). Capturas em `docs/mockups/spec-103/`:

| PNG | O que mostra | Requisitos |
|---|---|---|
| `0-antes.png` | Hoje: Automações com os hooks só explicados pelo `--settings` do Claude, e uma sessão Codex rodando `git push --force` sem bloqueio | Problema |
| `1-automacoes.png` | Automações por provedor: cada hook com as colunas Claude Code e Codex ("Antes da ferramenta", "Ao fim do turno"), o "Último:" com o provedor e o texto dos dois mecanismos | R6, R8, R10 |
| `2-sessao-codex.png` | Sessão Codex com o chip "Hooks nativos", os cartões de push forçado bloqueado, Vigia de segredos no commit e formatado após o `apply_patch` | R2, R5, R6, R9 |
| `3-pos-turno.png` | Sessão Codex com "Hooks só pós-turno": a lista dos substitutos, o aviso único na timeline, o bloqueio pelo pedido de aprovação e o aviso do YOLO sem hooks | R4, R5, R7, R9 |
