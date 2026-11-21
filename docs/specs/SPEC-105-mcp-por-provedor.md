---
id: SPEC-105
status: rascunho
versao: 0.25.0
tipo: melhoria
epico: 332
issue: 340
depende-de: [SPEC-093, SPEC-094, SPEC-096]
---

# MCP por provedor

## Problema

A tela MCP (Ferramentas → MCP) só conhece o Claude Code. Ela lê `~/.claude.json` e `.mcp.json`, adiciona e remove com `claude mcp add/remove` e mostra o status pelo `system/init` (`mcp_cli.dart`, `mcp_config.dart`, `mcp_state.dart`). O Codex guarda os servidores dele em outro lugar (`[mcp_servers.*]` no `~/.codex/config.toml`), usa outra CLI (`codex mcp list/get/add/remove/login`) e informa o status por outra via (`mcpServerStatus/list` no App Server). Hoje o app nem mostra quais servidores o Codex tem. E o MCP do próprio Promptorium (SPEC-052) é recusado no Codex: o `validateOptions` rejeita `mcpConfigs`.

Exemplo: a pessoa configurou `github` (http com OAuth) e `postgres-dev` (stdio com `DATABASE_URL`) no Claude Code. Numa sessão Codex, o agente responde "não tenho acesso ao banco". Para resolver, ela precisa descobrir sozinha o formato do `config.toml` e redigitar comando, argumentos e variáveis. E o rodapé continua dizendo "MCP 3/4", que é a conta do Claude, não a do provedor que está rodando.

A decisão 8 do épico #332 define o desenho: **configuração por provedor e um botão "copiar para o Codex"**. Nada é sincronizado sozinho entre os dois.

## Requisitos

### Uma tela, dois provedores

- R1 · **Seletor de provedor na tela MCP.** No topo da lista: "Claude Code · 4" e "Codex · 2". A aba do Claude continua exatamente como hoje. A do Codex lista os servidores do Codex com os mesmos componentes: lista agrupada, painel de conexão, ferramentas, configuração e log. A escolha fica lembrada por workspace, e a aba inicial é a do provedor ativo no rodapé.
- R2 · **Inventário do Codex sem custo.** A configuração vem de `codex mcp list --json` e `codex mcp get --json`. O status vem de `mcpServerStatus/list` (`detail: toolsAndAuthOnly` para a lista e `full` para o selecionado) numa conexão curta com o App Server, sem turno: estado de conexão (`starting/ready/failed`), `authStatus`, ferramentas e `toolsError`. Valores de `env` e de cabeçalhos aparecem mascarados, como já acontece no Claude. O token do `bearer_token_env_var` nunca é lido.
- R3 · **Grupos por onde a configuração vale.** "Globais · `~/.codex/config.toml`" e, se a SPEC-093 comprovar a configuração por projeto do Codex, "Projeto · `.codex/config.toml`". Servidores de plugin (`pluginId`) ficam em "De plugins", só para leitura. "Da sessão" mostra o servidor do Promptorium injetado pela execução (R7).
- R4 · **Adicionar e remover pela CLI do Codex.** "Adicionar servidor" com o Codex selecionado monta `codex mcp add <nome> [--env K=V…] -- <comando> <args…>` (stdio) ou `codex mcp add <nome> --url <url> [--bearer-token-env-var VAR]` (http). Remover usa `codex mcp remove <nome>`. O diálogo de confirmação mostra o comando exato, com valores mascarados, como no Claude. O app nunca edita o `config.toml` direto.
- R5 · **Login OAuth.** Servidor http com `authStatus: notLoggedIn` mostra "Entrar", que roda `mcpServer/oauth/login` (ou `codex mcp login <nome>`) e abre o navegador. O estado se atualiza com `mcpServer/oauthLogin/completed`, e "Sair" usa `codex mcp logout`.

### Copiar para o Codex

- R6 · **"Copiar para o Codex" num servidor do Claude.** É uma ação no painel do servidor, na aba Claude Code. Abre um diálogo com a tradução lado a lado (Claude → Codex): nome, transporte, comando, argumentos, nomes das variáveis e URL. Também mostra o comando `codex mcp add` que será executado e as diferenças:
  - **Escopo.** No Codex o servidor fica global (todos os projetos), a menos que a R3 confirme o escopo de projeto. Servidores de escopo Local ou Projeto no Claude mostram esse aviso.
  - **Segredos.** Os valores das variáveis e cabeçalhos **não** são copiados por padrão. O diálogo traz os campos vazios para preencher, ou a opção marcada pela pessoa "Copiar também os valores (ficam em texto no `~/.codex/config.toml`)". Para http com token, oferece `--bearer-token-env-var` em vez do valor.
  - **Sem equivalente.** Transportes `sse` e `ws`, ou cabeçalhos que o `codex mcp add` não aceita, desabilitam a cópia com o motivo: "Sem equivalente no Codex: transporte sse".
  - **Nome repetido.** Se o Codex já tem um servidor com o mesmo nome, o diálogo mostra a diferença e oferece "Substituir no Codex" (remove e adiciona, com confirmação) ou "Cancelar".

  É uma cópia única. Não fica vínculo, e mudanças posteriores no Claude não chegam ao Codex. Depois de copiar, o app abre a aba Codex com o servidor selecionado e confere o status (R2).

### Nas execuções

- R7 · **O MCP do Promptorium no Codex.** O servidor do app (SPEC-052) entra nas execuções Codex por override da execução (`-c mcp_servers.promptorium={command=…, args=[…]}`), com as mesmas ferramentas por modo que o Claude recebe: nas de leitura, liberadas; nas de escrita, sempre com aprovação. Se a SPEC-093 mostrar que o Codex não restringe ferramentas por servidor, as de escrita ficam de fora nas execuções Codex, e a tela diz isso. Nada é gravado no `~/.codex`.
- R8 · **Perguntar e Planejar continuam sem MCP de terceiros.** Esses modos mantêm `-c mcp_servers={}` (já é assim hoje), acrescido apenas do servidor do Promptorium (R7). Os outros modos usam os servidores do Codex como estão.
- R9 · **Regras por ferramenta onde houver suporte.** As regras Permitido, Pedir aprovação e Bloqueado (`mcp_rules.dart`) valem no Codex no que a SPEC-093 comprovar. "Bloqueado" vira `disabled_tools` do servidor, por override da execução. O que não tiver equivalente aparece desabilitado com a etiqueta "Só Claude Code", e o app não finge aplicar.
- R10 · **Log e "Usado por".** O log recente da aba Codex sai dos itens `mcpToolCall` gravados nas sessões Codex do workspace. "Usado por" (agentes que citam o servidor em `mcpServers`) mostra "Só Claude Code" na aba Codex, porque os agentes no Codex são tratados na SPEC-106.
- R11 · **Rodapé do provedor ativo.** O "MCP 3/4 · 1 falhou" do rodapé passa a contar os servidores do provedor da execução em foco, ou do provedor padrão quando nada está rodando, com o nome do provedor na dica.
- R12 · **Codex ausente ou incompatível.** A aba Codex mostra o motivo ("Codex não encontrado", "versão 0.168: precisa de 0.170 ou mais nova") e a orientação. A aba Claude não é afetada, e o app nunca cai para o outro provedor sem avisar.

## Fora do escopo

- Sincronizar sozinho os servidores entre os dois provedores, ou manter um vínculo depois da cópia.
- "Copiar para o Claude Code" (do Codex para o Claude). Ver P4.
- Editar o `config.toml` direto pelo app, ou gravar *trust* de projeto (`--trust`).
- Elicitação de MCP no meio do turno (`mcpServer/elicitation/request`). Entra com as aprovações da SPEC-096.
- Recursos e *templates* de MCP (`mcpServer/resource/read`) e chamar ferramentas pela tela.
- MCP dentro de agentes no Codex (SPEC-106).

## Decisões em aberto

- P1 · **Segredos ao copiar.** (a) Nunca copiar valores, só os nomes; (b) não copiar por padrão, com opção explícita de copiar; (c) copiar sempre. **Recomendação: (b).** Copiar os valores grava segredos em texto num segundo arquivo global, então a pessoa precisa escolher isso. Para http, sugerir `--bearer-token-env-var`.
- P2 · **Escopo de projeto no Codex.** (a) Só global, até a SPEC-093 provar `.codex/config.toml` por projeto; (b) gravar no projeto e marcar o projeto como confiável. **Recomendação: (a).** O app nunca grava *trust* no `config.toml`, que é um princípio do plano técnico.
- P3 · **Nome repetido.** (a) Bloquear; (b) mostrar a diferença e substituir só com confirmação; (c) criar com sufixo (`github-2`). **Recomendação: (b).**
- P4 · **Direção da cópia.** (a) Só Claude → Codex, como na decisão 8; (b) os dois sentidos. **Recomendação: (a) nesta spec.** "Copiar para o Claude Code" pode virar uma spec pequena se o uso pedir.
- P5 · **Regras por ferramenta no Codex.** (a) Mapear só Bloqueado (`disabled_tools`) e etiquetar o resto; (b) esperar a SPEC-093 e mapear tudo o que existir. **Recomendação: (a) como mínimo garantido, ampliando para (b) com o que a sondagem provar.**

## Design

### Arquivos tocados

- `lib/features/mcp/mcp_cli.dart`: separar a parte do Claude e criar `codex_mcp_cli.dart` (`codex mcp list/get/add/remove/login/logout --json`).
- `lib/features/mcp/mcp_config.dart`: `McpProvider` em cada entrada; `McpScope` do Codex (global/projeto/plugin).
- `lib/features/mcp/mcp_state.dart`: inventário e status por provedor; `mcpServerStatus/list` via App Server curto.
- `lib/features/mcp/mcp_screen.dart`: seletor de provedor, grupos do Codex, "Entrar/Sair", "Copiar para o Codex".
- `lib/features/mcp/widgets/add_server_dialog.dart`: modo Codex; `widgets/copy_to_codex_dialog.dart` (novo).
- `lib/features/mcp/mcp_rules.dart`: tradução das regras para o Codex (R9).
- `lib/core/codex/codex_provider.dart`: aceitar o MCP do app por override (R7) em vez de recusar `mcpConfigs`; manter `mcp_servers={}` em Perguntar/Planejar (R8).
- `lib/core/mcp/app_mcp_config.dart`: gerar o override TOML do servidor do app.
- `lib/ui/shell/status_footer.dart`, `footer_stats.dart`: contagem pelo provedor ativo (R11).

### Migração

Não há. A aba escolhida fica em `app_settings` (`mcp.provider.workspace.<id>`).

### Dependências

- **SPEC-093 · Sondagem do Codex 0.170**: formato do `codex mcp list --json`; configuração por projeto; se `enabled_tools`/`disabled_tools` funcionam por `-c`; formato do override do servidor do app.
- **SPEC-094 · Capacidades e opções por provedor**: capacidades `mcpConfig` e `appMcpServer`, estado "incompatível" e o fim da recusa de `mcpConfigs`.
- **SPEC-096 · Codex no Prompt e nas Sessões**: as execuções em que R7 e R8 se aplicam; aprovações de ferramentas MCP.
- Relacionada: SPEC-106 (agentes no Codex, `mcpServers` do agente).

## Tarefas

- T1 · `codex_mcp_cli` e status por `mcpServerStatus/list`; inventário por provedor. Testes com saídas gravadas do `codex mcp list --json` e respostas do `fake_codex`.
- T2 · Tela: seletor de provedor, grupos, painel, adicionar, remover, Entrar/Sair, estados de Codex ausente. Testes de widget.
- T3 · "Copiar para o Codex": tradução, segredos, escopo, sem equivalente, nome repetido. Testes de unidade da tradução e de widget do diálogo.
- T4 · Execuções: servidor do app por override, Perguntar/Planejar, regras, log e rodapé. Testes do adaptador e um teste manual com o app isolado.

## Critérios de aceite

- [ ] A aba Codex lista os servidores do `codex mcp list --json` com status, autenticação e ferramentas, sem nenhum turno pago [R1–R3] verificar: teste de widget com saídas gravadas e contagem de `turn/start` no `fake_codex` igual a zero.
- [ ] Adicionar e remover no Codex rodam o comando mostrado na confirmação e nunca escrevem no `config.toml` direto [R4] verificar: teste do `codex_mcp_cli` com executor falso.
- [ ] "Entrar" num servidor `notLoggedIn` chama o login e atualiza o estado [R5] verificar: teste com notificação `mcpServer/oauthLogin/completed` simulada.
- [ ] Copiar um servidor stdio com variáveis gera o `codex mcp add` certo, sem valores por padrão; com a opção marcada, inclui os valores [R6] verificar: testes de unidade da tradução.
- [ ] `sse`/`ws` ficam desabilitados com o motivo; nome repetido mostra a diferença e só substitui com confirmação [R6] verificar: testes de widget do diálogo.
- [ ] Numa sessão Codex, as ferramentas do Promptorium aparecem com as mesmas regras por modo do Claude, e nada é gravado em `~/.codex` [R7] verificar: argumentos do `app-server` no teste do adaptador e sondagem real num `HOME` temporário.
- [ ] Perguntar e Planejar no Codex não recebem servidores de terceiros [R8] verificar: argumentos `-c mcp_servers` no teste do adaptador.
- [ ] Regras sem equivalente aparecem com "Só Claude Code"; Bloqueado vira `disabled_tools` [R9] verificar: teste do `mcp_rules` e teste de widget.
- [ ] O rodapé conta os servidores do provedor ativo, e a aba Codex explica Codex ausente ou incompatível [R11, R12] verificar: testes de widget do rodapé e da aba.

## Telas

Mockup: [canvas do Claude Design](https://claude.ai/artifact/6MEv3ZAg1NaGjN4ubQMuYe). PNGs em `docs/mockups/spec-105/`, com servidores de exemplo.

| PNG | O que mostra | Requisitos |
|---|---|---|
| `1-mcp-codex.png` | Tela MCP com o seletor "Claude Code · 4 / Codex · 2", aba Codex: grupos Globais, De plugins e Da sessão; painel do servidor com status do `mcpServerStatus/list`, OAuth, ferramentas e regras ("Só Claude Code" onde não há equivalente) | R1–R3, R5, R7, R9 |
| `2-copiar-para-codex.png` | Diálogo "Copiar para o Codex" a partir de um servidor do Claude: tradução lado a lado, aviso de escopo global, valores das variáveis vazios com a opção de copiar, e o comando `codex mcp add` | R6 |
| `3-estados.png` | Nome repetido com a diferença, transporte sem equivalente, Codex incompatível na aba e o rodapé contando pelo provedor ativo | R6, R11, R12 |
