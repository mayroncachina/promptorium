---
id: SPEC-052
status: proposta
depende-de: SPEC-016, SPEC-017, SPEC-023
issue: 127
---

# Promptorium como servidor MCP

## Objetivo

Hoje o agente não enxerga o Quadro. Para uma resposta virar spec, a pessoa usa "Salvar como spec" (SPEC-016). O andamento de uma etapa só chega ao app pelos marcadores do texto, como `ETAPA CONCLUÍDA: Rn`. O agente não sabe quais specs existem, em que coluna estão nem do que dependem, a não ser que leia os arquivos.

Esta spec faz o Promptorium servir um MCP local, ligado só às sessões e conversas que o próprio app abre. Com ele, o agente pode consultar as specs e o Quadro, criar uma spec ou filhas como rascunho e anotar o andamento. O que altera o projeto passa pela aprovação de ferramenta que já existe. O servidor nunca aprova, executa nem faz merge de uma spec: isso continua com a pessoa.

A ideia vem do Vibe Kanban, que expõe o quadro aos agentes por MCP (issue mãe [#124](https://github.com/mayroncachina/promptorium/issues/124)).

Issue: [#127](https://github.com/mayroncachina/promptorium/issues/127).

Mockup: [canvas do Claude Design](https://claude.ai/artifact/RszcugkDPCGwb6zeMdZoxy). Cópia dos quadros e capturas em `docs/mockups/spec-052/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-aprovacao-na-sessao.png` | Leituras automáticas na timeline e "criar_spec" pedindo aprovação, com a prévia | R3, R4, R5 |
| `2-rascunho-em-specs.png` | O rascunho criado pelo agente em Specs, com a origem e as filhas | R4, R6 |
| `3-andamento-no-quadro.png` | A nota de andamento no card do Quadro e no histórico da spec | R7 |
| `4-configuracoes.png` | Configurações › Execução de specs, com o servidor, as ferramentas e o limite | R1, R8, R9, R10 |

## Requisitos

- R1 · O app deve servir um MCP em `127.0.0.1`, numa porta livre, só enquanto estiver aberto. Cada sessão ou conversa do Claude Code que o app iniciar deve receber o servidor com o nome `promptorium` por `--mcp-config`, num arquivo gerado por execução em `~/.promptorium/run` (permissão 0600). O app nunca escreve em `~/.claude.json` nem em `.mcp.json`. Com o servidor desligado em Configurações, nenhuma execução recebe o arquivo.
- R2 · Cada execução deve ter um token próprio, enviado no cabeçalho `Authorization` do arquivo de R1. O servidor deve:
  - recusar chamadas sem token ou com token desconhecido;
  - saber, pelo token, o workspace, a sessão, a spec (quando houver) e o modo da execução;
  - revogar o token e apagar o arquivo quando o processo terminar.
- R3 · O servidor deve expor estas ferramentas de **leitura**, liberadas sem pedir aprovação (`--allowedTools`):
  - `listar_specs`: código, título, status, coluna do Quadro, sprint e `depende-de` das specs do workspace, com filtro por status e coluna;
  - `ler_spec`: o texto de uma spec e o estado das etapas, com o resultado do último gate;
  - `estado_do_quadro`: as specs de cada coluna, as sessões vivas e o que espera a pessoa ("Precisa de você");
  - `spec_atual`: a spec e a etapa da execução, quando houver.
- R4 · O servidor deve expor estas ferramentas de **escrita**, que sempre passam pela aprovação da sessão (`--permission-prompt-tool stdio`):
  - `criar_spec`: grava uma spec nova pelo `SpecService.create`, no próximo código livre e com `status: rascunho`, e devolve o código e os avisos do `lintSpec` (SPEC-023);
  - `criar_filhas`: cria até 6 specs com `depende-de: <pai>`, numa aprovação só;
  - `anotar_andamento`: grava uma nota curta (até 280 caracteres) na spec da execução (R7).
  
  O cartão de aprovação mostra uma prévia: título, quantidade de requisitos e de critérios, avisos do lint e o caminho do arquivo. Para `criar_spec` e `criar_filhas`, ele não oferece "Sempre permitir" no projeto nem em todos os projetos, só nesta sessão.
- R5 · O servidor nunca deve:
  - mudar o status, a coluna ou as etapas de uma spec existente;
  - sobrescrever um arquivo de spec;
  - aprovar, executar, revisar ou mergear uma spec;
  - aceitar caminhos de arquivo vindos do agente.
  
  Toda gravação usa o serviço de specs, com criação exclusiva, como na SPEC-016 R6.
- R6 · Uma spec criada pelo servidor deve registrar a origem no frontmatter (`origem: agente`, com o id da sessão) e aparecer em Specs com o selo "Criada pelo agente", o link para a sessão e, quando houver, a lista de filhas. Excluir o rascunho continua sendo a ação de sempre.
- R7 · `anotar_andamento` deve:
  - mostrar a nota mais recente no card do Quadro, abaixo da etapa;
  - guardar todas as notas no histórico da spec, com hora e sessão;
  - não marcar etapa como concluída: quem conclui a etapa continua sendo o marcador com o gate (SPEC-023).
- R8 · Por modo da execução:
  - **Perguntar**, no Prompt: só as ferramentas de leitura;
  - **Planejar** e **Editar**: leitura e escrita.
  
  Em sessão "sem perguntar" (`--dangerously-skip-permissions`), a escrita grava sem aprovação, mas continua limitada a R5 e R9, e a timeline marca o que foi criado.
- R9 · Cada execução pode criar no máximo 10 specs; o número pode mudar em Configurações. Acima do limite, a ferramenta devolve um erro que explica o motivo ao agente e nada é gravado.
- R10 · Configurações › Execução de specs deve ganhar "Servidor MCP do Promptorium", com:
  - liga e desliga, ligado por padrão;
  - o estado: porta e execuções conectadas;
  - a lista de ferramentas, com o que cada uma faz e se pede aprovação;
  - o limite de R9.
  
  Em Ferramentas › Servidores MCP, o servidor aparece em "Da sessão", só para leitura.

## Fora do escopo

- Codex e agentes ACP. Eles não recebem `--mcp-config` (`codex_provider.dart` recusa "arquivos MCP Claude"). Ficam para quando religarem.
- Execuções internas do app (Refinar, Planejar spec, revisor automático, protótipo). Elas têm prompt e saída próprios e não precisam do servidor.
- Usar o servidor fora do app, como no Claude Code do terminal ou em outro cliente MCP. O token só existe nas execuções do app.
- Ferramentas que aprovam, movem coluna, rodam etapa ou abrem PR. Ficam para outra spec, se fizer sentido.
- Recursos (`resources`) e prompts MCP. Por enquanto, só ferramentas.

## Design

### O que já existe

- `lib/core/claude/claude_args.dart`: `ClaudeOptions.mcpConfigs` já vira `--mcp-config`, mas nenhuma sessão o preenche. `settingsFile` vira `--settings`.
- `lib/core/claude/run_extensions.dart`: `runSettingsDirProvider` (`~/.promptorium/run`) e `writeRunSettings`, o padrão de arquivo gerado por execução. `deniedMcpServers` tira servidores do usuário (SPEC-017 R2, sonda em `docs/pesquisa/plugins-mcp-desligados.md`).
- `lib/core/claude/managed_hooks.dart` e `SessionManager._prepareHooks`: arquivos por sessão, com limpeza no fim (`_hookCleanups`).
- `lib/features/sessions/session_manager.dart`: o início do processo (`ClaudeProcess.start` com `options.copyWith(settingsFile: …)`), a fila de aprovações (`PendingApproval`), `approve`, `note` e as regras de MCP (`McpRuleArgs`).
- `lib/features/mcp/mcp_rules.dart`: `mcpToolId` (`mcp__promptorium__<ferramenta>`) e o que vira `--allowedTools` e `--disallowedTools`.
- `lib/features/prompt/conversation_manager.dart`: as conversas do Prompt e os modos `PromptMode.ask`, `plan` e `edit` (`agent_provider.dart`).
- `lib/features/specs/spec_service.dart`: `create` (criação exclusiva, `nextSpecCode`) e `_serial`, que já serializa as gravações.
- `lib/features/specs/spec_lint.dart`: `lintSpec`, os avisos da SPEC-023.
- `lib/features/prompt/spec_from_answer.dart` (SPEC-016): a prévia de uma spec escrita pelo agente.
- `lib/features/board/`: `SpecStage`, `spec_runner.dart` e `step_gate.dart`, o estado do Quadro e das etapas.

### Transporte: HTTP local no próprio app

Opções avaliadas:

- **stdio, com um subcomando do próprio binário** (`promptorium mcp`). O CLI iniciaria o processo. Mas o binário é um app Flutter de desktop. Ele sobe GTK e o motor gráfico, e o estado (banco, `SpecService`, sessões vivas) está no processo que já está aberto. O subcomando ainda precisaria falar com esse processo por um socket. Ou seja, seriam dois transportes.
- **stdio, com uma ponte em Python**, como os hooks. Tem o mesmo problema do socket e passaria a depender do `python3` para uma função que não é opcional.
- **HTTP em `127.0.0.1`, dentro do app** (escolhido). O servidor roda no processo que já tem o estado, com `HttpServer` do Dart e o transporte "Streamable HTTP" do MCP (JSON-RPC por POST). O CLI conecta pelo `--mcp-config` com `{"type": "http", "url": …, "headers": {"Authorization": "Bearer <token>"}}`. Não há processo extra nem dependência nova. O token por execução (R2) identifica quem chama, limita o servidor ao workspace dela e impede que outro processo da máquina use a porta sem o token. O token fica num arquivo 0600, não na linha de comando.

O que ainda não foi conferido no CLI está na sonda prevista em [`docs/pesquisa/mcp-do-app.md`](../pesquisa/mcp-do-app.md). Ela roda antes da implementação.

### Componentes

- `lib/core/mcp/app_mcp_server.dart` (novo):
  - `AppMcpServer`: `HttpServer` em `127.0.0.1:0`, com as rotas do MCP (`initialize`, `tools/list`, `tools/call`) e a recusa sem token (R1, R2);
  - `McpGrant`: um valor imutável com token, workspace, sessão, spec, modo e contagem de criações (R2, R8, R9);
  - `appMcpServerProvider`: sobe com o app e para no `dispose`.
- `lib/core/mcp/app_mcp_tools.dart` (novo): as ferramentas de R3 e R4, como funções puras sobre os repositórios e o `SpecService`. `tools/list` filtra pelo modo do grant (R8).
- `lib/core/mcp/app_mcp_config.dart` (novo): `writeMcpConfig(dir, grant)` grava `mcp-<sessão>.json` com 0600 e devolve o caminho, e há uma função para apagá-lo. Segue o padrão de `writeRunSettings`.
- `SessionManager` e `ConversationManager`: criam o grant, passam o arquivo em `mcpConfigs`, somam as ferramentas de leitura a `--allowedTools` e revogam o grant no fim do processo, junto da limpeza dos hooks.
- Aprovação: o cartão de `PendingApproval` reconhece `mcp__promptorium__criar_*` e mostra a prévia, com o parser da SPEC-016 e o `lintSpec`. Para essas ferramentas, esconde "Sempre permitir" no projeto e em todos os projetos (R4).
- `SpecService.create` ganha `origem` opcional, que grava `origem: agente` e `sessao: <id>` no frontmatter (R6). As notas de andamento vão para uma tabela nova, `spec_notes` (spec, sessão, texto, hora), com migração e teste a partir da versão atual (R7).
- Specs: selo "Criada pelo agente", link para a sessão e lista de filhas. Quadro: a última nota no card (R6, R7).
- Configurações: a seção de R10, nas chaves `mcp.servidor` e `mcp.limiteCriacoes` de `AppSettingKeys`.

## Critérios de aceite

- [ ] Uma sessão do app recebe `--mcp-config` com o servidor `promptorium`, e nenhum arquivo do usuário muda [R1] verificar: flutter test test/core/mcp/app_mcp_config_test.dart
- [ ] Chamada sem token, com token desconhecido ou com token revogado é recusada [R2] verificar: flutter test test/core/mcp/app_mcp_server_test.dart
- [ ] O token só enxerga o workspace da execução e é revogado no fim do processo [R2] verificar: flutter test test/core/mcp/app_mcp_server_test.dart
- [ ] As quatro ferramentas de leitura devolvem specs, Quadro e etapa reais e não pedem aprovação [R3] verificar: flutter test test/core/mcp/app_mcp_tools_test.dart
- [ ] `criar_spec` e `criar_filhas` gravam rascunhos no próximo código, com `depende-de` e a origem, e devolvem os avisos do lint [R4, R6] verificar: flutter test test/core/mcp/app_mcp_tools_test.dart
- [ ] O cartão de aprovação mostra a prévia e não oferece "Sempre permitir" no projeto para `criar_*` [R4] verificar: flutter test test/features/sessions/approval_card_test.dart
- [ ] Nenhuma ferramenta muda status, coluna ou etapas, sobrescreve arquivo ou aceita caminho [R5] verificar: flutter test test/core/mcp/app_mcp_tools_test.dart
- [ ] A nota de andamento aparece no card e no histórico e não conclui a etapa [R7] verificar: flutter test test/features/board/spec_notes_test.dart
- [ ] Em Perguntar, `tools/list` só tem leitura; em Planejar e Editar, tem leitura e escrita [R8] verificar: flutter test test/core/mcp/app_mcp_server_test.dart
- [ ] Acima do limite, a criação é recusada com a explicação e nada é gravado [R9] verificar: flutter test test/core/mcp/app_mcp_tools_test.dart
- [ ] Desligar o servidor em Configurações tira o `--mcp-config` das execuções novas [R10] verificar: flutter test test/features/settings/settings_screen_test.dart
- [ ] Num projeto real, o agente lê o Quadro, cria uma spec com filhas aprovada pela pessoa e anota o andamento [R1–R7] verificar: manual (sessão do app num projeto de teste)
- [ ] O projeto compila e a análise estática passa [R1–R10] verificar: flutter analyze

## Decisões

- P1 · Transporte: HTTP em `127.0.0.1`, dentro do app, com token por execução. stdio por subcomando ou por ponte em Python ficou de fora (ver Design).
- P2 · **Em aberto.** O servidor vem ligado por padrão (R10)? A proposta é ligado, porque as ferramentas de leitura economizam turnos de `Read`/`Glob` nos arquivos de spec. Desligado seria mais conservador, como o revisor automático no início.
- P3 · **Em aberto.** Em Perguntar, só leitura (R8). A SPEC-016 deixou de fora "dar ferramenta de escrita ao agente nos modos Perguntar/Planejar". Esta spec libera a escrita em Planejar, sempre com aprovação, porque criar o rascunho é o fim natural de um planejamento. Confirmar.
- P4 · **Em aberto.** Na sessão "sem perguntar", a escrita grava sem aprovação (R8). A outra opção é o servidor pedir confirmação por conta própria, numa notificação do app, mesmo com o bypass. Isso seria mais seguro, mas mudaria o que "sem perguntar" promete.
- P5 · **Em aberto.** Limite de 10 specs por execução (R9) e de 6 filhas por chamada (R4, o mesmo teto de requisitos da SPEC-039). Ajustar se for pouco.
- P6 · As notas de andamento (R7) ficam no banco, não no arquivo da spec, para não sujar o diff da branch a cada nota.
- P7 · Os nomes das ferramentas ficam em português, como as chaves do `config.yml`. O CLI os mostra como `mcp__promptorium__criar_spec`.
