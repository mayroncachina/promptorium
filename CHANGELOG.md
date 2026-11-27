# Changelog

Todas as mudanças relevantes do Promptorium.

## [0.28.0] - 2026-11-27

### Funcionalidades

- **instrucoes:** Estado fonte única e a constante do import @AGENTS.md (SPEC-113 T1) (46cff3b)
- **instrucoes:** Import do CLAUDE.md, gravação segura dos dois arquivos e tamanho contra os 32 KiB do Codex (SPEC-113 T1) (94f7b7d)
- **instrucoes:** Editor das instruções do projeto e Ferramentas › Instruções como atalho (SPEC-113 T3) (da1f8a0)
- **projeto:** Criação grava o AGENTS.md e o CLAUDE.md com @AGENTS.md (SPEC-113 T2) (da1753e)
- **instrucoes:** Tabela InstructionInterviews e migração v39 (SPEC-113 T5) (80316f8)
- **instrucoes:** Entrevista em rodadas, pausar e retomar, e a proposta por trecho (SPEC-113 T5) (710c4ab)
- **instrucoes:** Aba Projeto › Instruções, diálogo no planejamento, entrevista na aba e atalho da paleta (SPEC-113 T3) (2ac57e0)
- **instrucoes:** Comparar CLAUDE.md e AGENTS.md por seção e item e compor os dois arquivos (SPEC-113 T4) (7b1c668)
- **instrucoes:** Diálogo Unificar instruções com resultado antes de gravar e Desfazer (SPEC-113 T4) (5508eeb)
- **instrucoes:** Botão Unificar instruções abre o diálogo da T4 (SPEC-113 T3) (cf27229)
- **instrucoes:** Proposta por trecho, conferência dos caminhos e commit opcional na branch atual (SPEC-113 T6) (059aea9)
- **instrucoes:** A proposta da entrevista abre na aba e Concluir volta ao editor (SPEC-113 T3) (7e639f0)

### Correções

- **instrucoes:** "Tentar de novo" refaz a proposta que falhou (SPEC-113 T5) (6df078e)
- **instrucoes:** Ajustes vistos no app isolado, prints e guia (SPEC-113 T7) (cb785ab)
- **instrucoes:** Sem "Recolocar o import" quando o CLAUDE.md repete o AGENTS.md (SPEC-113 R9) (8e4112c)
- **instrucoes:** Tirar o aviso "Duas fontes" da SPEC-104, já dito pelo card Unificar (SPEC-113) (b34c886)

### Refatoração

- **projeto:** Usa a constante do import da T1 e renomeia a gravação da criação (SPEC-113) (029e451)

### Documentação

- **spec:** SPEC-113 Instruções do projeto, com mocks (74a76c3)
- **spec:** SPEC-113 aponta a issue #429 (a16d4db)
- **spec:** SPEC-113 vai para a 0.28.0, canvas aprovado (13d6a20)
- **spec:** SPEC-113 aprovada, commit na branch atual (P7) (08d36d1)
- **spec:** SPEC-113 em implementação, migração v39 (d02b7f0)

## [0.27.1] - 2026-11-26

### Correções

- **provedores:** Codex ligado na documentação e aviso apontando para Provedores (b795041)

## [0.27.0] - 2026-11-26

### Funcionalidades

- **orquestrador:** Provedor nas regras, reservas, escada do Codex e schema v38 (SPEC-109 T1) (e057c97)
- **orquestrador:** Desvio por cota entre provedores, com volta ao plano e retomada agendada (SPEC-109 T2) (f6b325c)
- **orquestrador:** Provedor por etapa no Executar e nas Configurações, e a espera por cota (SPEC-109 T3) (e9d8e27)
- **orquestrador:** Classificação e Revisão no Codex, agente só no Claude (SPEC-109 T4) (dcc4ab9)
- **orquestrador:** Histórico por provedor e modelo, com desvios e tokens (SPEC-109 T5) (4eab996)
- **replay:** Passos do Codex, base pelo ponto de restauração e saída completa pela RPC (SPEC-110 T1–T3) (4e7c0a6)
- **restauracao:** Desfazer também a conversa do Codex, com cópia para o Refazer (SPEC-110 T4) (450b89e)
- **sessoes:** Turnos revertidos esmaecidos na timeline e no Replay (SPEC-110 T5) (97a0527)
- **prompt:** Comparar com provedor, esforço e peso por lado (SPEC-108 T1, T2) (a8e643c)
- **prompt:** Faixa, colunas e pacote de partida do Comparar por provedor (SPEC-108 T3) (28455b5)
- **quadro:** Comparar A/B com provedor, modelo e esforço por tentativa (SPEC-108 T5) (6462845)

### Correções

- **comparar:** Ajustes vistos no app isolado e guia (SPEC-108 T4) (21672de)
- **inicio:** A sessão substituída por um desvio por cota não aparece para retomar (SPEC-109 R5) (ff3149a)
- **orquestrador:** A etapa desviada mantém o selo do provedor no painel (SPEC-109 R14) (2cc77c4)
- **orquestrador:** O selo da etapa desviada não deixa timer do banco pendente (c9b235a)

### Documentação

- **spec:** SPEC-109 Orquestrador multi-provedor (3e7c385)
- **spec:** SPEC-109 aponta a issue #344 (94f548e)
- **spec:** SPEC-109 vai para a 0.26.0 (753ab79)
- **spec:** SPEC-109 arquiva o canvas no repositório (548320d)
- **spec:** SPEC-109 em implementação na 0.27.0, com as decisões fechadas (fa04d8e)
- **spec:** SPEC-110 Replay e restauração com o Codex (2063475)
- **spec:** SPEC-110 aponta a issue #350 (2cc81f6)
- **spec:** SPEC-110 vai para a 0.26.0 (700c35d)
- **spec:** SPEC-110 arquiva o canvas no repositório (40411fa)
- **spec:** SPEC-110 em implementação, com as decisões P1–P6 fechadas (ee514fe)
- **spec:** SPEC-108 Comparar Claude × Codex (5066482)
- **spec:** SPEC-108 aponta a issue #336 (107e14a)
- **spec:** SPEC-108 vai para a 0.26.0 (c742ee9)
- **spec:** SPEC-108 arquiva o canvas no repositório (06ce81b)
- **spec:** SPEC-108 em implementação, decisões P1–P6 fechadas (51eb9a8)
- **spec:** SPEC-108 concluída, prints do app e leitura de antes guardada na hora (cb00803)
- **spec:** SPEC-109 com as decisões além da spec e o E2E pendente (95a667b)
- **spec:** SPEC-109 concluída, E2E no app e prints (27c6b22)

### Testes

- **restauracao:** Ponta a ponta no app compilado, sonda do App Server e ajustes (SPEC-110 T5) (0b88528)
- O Codex roda no Comparar (SPEC-108) (965ce05)
- O Codex roda no Comparar (SPEC-108) (b2a7358)

## [0.26.0] - 2026-11-25

### Funcionalidades

- **debitos:** Parser e escritor das tabelas, arquivos, vínculos e schema v37 (SPEC-112 T1) (6a2eeac)
- **debitos:** Tela Débitos e decisões, menu, itens à mão e commit próprio (SPEC-112 T2) (db2d36f)
- **debitos:** Pagar débitos, riscar no merge, devolver no descarte e chip do Quadro (SPEC-112 T6) (112c8ec)
- **debitos:** Registrar_debito e listar_debitos no MCP e etiqueta do provedor na faixa (SPEC-112 T5) (b411b45)
- **debitos:** "Virar débito" nos comentários da Revisão e nas mensagens do agente (SPEC-112 T4) (03d419c)
- **debitos:** Entrevista e decisões, débito e DP nas perguntas (SPEC-112 T3) (90e229d)
- **debitos:** Chips "débitos neste arquivo", lembrete no prompt da etapa e "pago de carona?" (SPEC-112 T7) (c063ee4)

### Documentação

- **spec:** SPEC-112 débitos e decisões, com os mocks (04cda44)
- **spec:** SPEC-112 ligada à issue #417 (a2ecfbf)
- **spec:** SPEC-112 com o ícone pending_actions no menu e nos mocks (67cae83)
- **spec:** SPEC-112 em implementação, com as decisões P fechadas (ac8ee4c)
- **guia:** O Codex nas páginas do guia de uso (#383) (0c26564)

### Testes

- **debitos:** O menu tem 12 itens com Débitos e decisões (SPEC-112 T2) (902c9fb)
- **debitos:** Ponta a ponta no app compilado e ajustes do teste (SPEC-112 T8) (79353f8)

## [0.25.0] - 2026-11-23

### Funcionalidades

- **contexto:** Medidor e compactação do Codex pelo contrato da SPEC-087 (SPEC-107) (8a900d9)
- **contexto:** Fontes do Codex com caminhos relativos e subagente pela thread (SPEC-107) (d6d7f04)
- **codex:** Traduz o agente .claude/agents para a execução Codex (SPEC-106 T1) (e2151d4)
- **codex:** Sessão Codex com agente traduzido e registro no promptorium_run (SPEC-106 T2) (d16d16a)
- **agentes:** Modelos equivalentes do Codex e quadro "No Codex" no editor (SPEC-106 T3) (51d505a)
- **codex:** Agente na Nova sessão, Executar spec e revisor; aviso dos subagentes (SPEC-106 T4) (48e998a)
- **mcp:** Inventário do Codex por codex mcp e mcpServerStatus/list (SPEC-105 T1) (bfa4d39)
- **mcp:** Aba Codex na tela MCP com grupos, status, Entrar/Sair e adicionar/remover (SPEC-105 T2) (09bec2f)
- **mcp:** Copiar para o Codex com tradução, segredos, escopo e nome repetido (SPEC-105 T3) (64682c2)
- **codex:** MCP do Promptorium, servidores desligados por nome nos modos de leitura, Bloqueado e rodapé por provedor (SPEC-105 T4) (2bd5ae2)
- **codex:** CLAUDE.md e skills do Claude no Codex por override da execução (SPEC-104 T1, T2) (3782b8e)
- **instrucoes:** Aba Instruções em Ferramentas e AGENTS.md do plano B na criação (SPEC-104 T3) (168f7f1)
- **skills:** Selos Claude/Codex, grupo Do Codex, erros do skills/list e plano B (SPEC-104 T4) (7c079d3)

### Correções

- **codex:** Ajustes visuais do E2E da SPEC-106 (pílula à direita, nota do maior esforço, aviso sem crases) (cfe5baa)
- **codex:** Razões curtas das capacidades MCP (SPEC-105 T4) (eae6868)
- **skills:** A consulta do Codex espera o workspace ativo pela configuração, sem ouvir o stream dos workspaces (SPEC-104) (3d63789)

### Documentação

- **spec:** SPEC-107 contexto e compactação no Codex, com mocks (e2a5076)
- **spec:** SPEC-107 aponta a issue #342 (b2b46e0)
- **spec:** SPEC-107 vai para a 0.25.0 (c483fa2)
- **spec:** SPEC-107 arquiva o canvas no repositório (5164dfd)
- **spec:** SPEC-107 em implementação, decisões P1–P5 fechadas (390e753)
- **spec:** SPEC-107 concluída, prints do app e Codex falso do E2E; corrige o marcador depois da última leitura (72c3b92)
- **spec:** SPEC-106 agentes no Codex, com mocks (3e4c660)
- **spec:** SPEC-106 aponta a issue #341 (721744b)
- **spec:** SPEC-106 vai para a 0.25.0 (37dc11a)
- **spec:** SPEC-106 arquiva o canvas no repositório (6a99cdc)
- **spec:** SPEC-106 em implementação, decisões P fechadas (88ab2f3)
- **spec:** SPEC-106 concluída, prints do app e aviso dos subagentes sem crases (a567ffe)
- **spec:** SPEC-105 MCP por provedor, com mocks (380e164)
- **spec:** SPEC-105 aponta a issue #340 (44351ed)
- **spec:** SPEC-105 vai para a 0.25.0 (21ac13d)
- **spec:** SPEC-105 arquiva o canvas no repositório (87f6591)
- **spec:** SPEC-105 em implementação, decisões e sondagem sem custo (4f6a7f5)
- **spec:** SPEC-105 concluída, prints do app e critérios (b99eb98)
- **spec:** SPEC-104 instruções (AGENTS.md) e skills, com mocks (34c9a94)
- **spec:** SPEC-104 aponta a issue #339 (3bc505d)
- **spec:** SPEC-104 vai para a 0.25.0 (28103ed)
- **spec:** SPEC-104 arquiva o canvas no repositório (c887b65)
- **spec:** SPEC-104 concluída, com os prints do app e o diff sem rolagem própria (855fb5c)

### Testes

- **mcp:** Os args exatos do app-server incluem o override de instruções da SPEC-104 (SPEC-105) (1aaaff2)

## [0.24.0] - 2026-11-22

### Funcionalidades

- **planner:** RunStructured neutro com adaptadores do Claude Code e do Codex (SPEC-100 T1, T2) (b5c69fe)
- **planner:** Fluxos do R8 no provedor do tipo, perfil rápido, falha e escolha desta vez (SPEC-100 T3) (321a0ff)
- **planner:** Provedor por tipo, linha do provedor nos diálogos e escolha desta vez (SPEC-100 T4) (bbcb18f)
- **revisor:** Provedor do revisor no config do projeto, resolução e linha Revisão do Executar (SPEC-102 T1) (e9806b1)
- **revisor:** Rodada no Codex, achados normalizados e autoria da rodada (schema v36) (SPEC-102 T2, T3) (5050e7b)
- **quadro:** Executar spec com o Codex, com provedor fixo por execução (SPEC-101) (c23e06b)
- **memoria:** Detectar o ai-memory e mostrar o estado em Configurações (SPEC-098 T1) (a7caa94)
- **memoria:** Execuções auxiliares e etapas fora da memória do ai-memory (SPEC-098 T2) (9566f46)
- **memoria:** Ligar o ai-memory no Claude Code e no Codex com prévia (SPEC-098 T3) (cc80bcc)
- **memoria:** Passagens do ai-memory na aba Memória do projeto (SPEC-098 T4) (7a60073)
- **memoria:** Detecção na abertura, E2E com capturas e SPEC-098 concluída (SPEC-098 T5) (b3860b0)
- **sessoes:** Continuar no outro agente com resumo do app e vínculo (SPEC-099 T1+T2) (163cbba)
- **sessoes:** Passagem do ai-memory ao continuar no outro agente (SPEC-099 T3) (e76345f)
- **sessoes:** Faixa de cota, Prompt e Memória levam ao outro agente (SPEC-099 T4) (f7f7484)
- **hooks:** Plano neutro e adaptador Claude, provedor no hooks.log (SPEC-103 T1) (78580fe)
- **hooks:** Script nos formatos do Claude e do Codex, teste de paridade (SPEC-103 T2) (6fe86ce)
- **codex:** Hooks do app por -c e estado da sessão pelo hooks/list (SPEC-103 T3) (5fdf51b)
- **sessoes:** Atividade dos hooks do Codex, pós-turno e bloqueio pela aprovação (SPEC-103 T4) (dd45953)
- **telas:** Automações por provedor, chip dos hooks na sessão Codex, selo nos cartões e aviso do YOLO (SPEC-103 T5) (89d21ad)
- **hooks:** E2E no app isolado, estado do Codex mantido após o fim e SPEC-103 concluída (SPEC-103 T6) (79462c5)

### Correções

- **planner:** Opções do Provedor por tipo na largura do texto e contraste do botão desta vez (SPEC-100 T4) (2ed47d3)
- **revisor:** Rodada repetida "desta vez" leva o veredito no título; campos do revisor numa linha (SPEC-102) (1c1168a)
- **sessoes:** Ajustes do teste no app da SPEC-099 (746e7b7)

### Documentação

- **spec:** SPEC-102 Review automático com o Codex, com mocks (16f7f46)
- **spec:** SPEC-102 aponta para a issue #347 (03a5106)
- **spec:** SPEC-102 vai para a 0.24.0 (c79d9f6)
- **spec:** SPEC-102 arquiva o canvas no repositório (77fb307)
- **spec:** SPEC-100 Execuções estruturadas em qualquer provedor, com mocks (9b612b2)
- **spec:** SPEC-100 aponta para a issue #345 (b27705e)
- **spec:** SPEC-100 vai para a 0.24.0 (be54bf9)
- **spec:** SPEC-100 arquiva o canvas no repositório (79e0d44)
- **spec:** SPEC-100 em implementação, decisões P fechadas (f2ee0a4)
- **spec:** SPEC-100 concluída, com o E2E no app isolado e os prints (T5) (56dfc91)
- **spec:** SPEC-102 concluída, com o E2E no app isolado e os prints (T4) (5be8958)
- **spec:** SPEC-101 Executar spec com o Codex, com mocks (00d5c8a)
- **spec:** SPEC-101 aponta para a issue #346 (fe66c34)
- **spec:** SPEC-101 vai para a 0.24.0 (c5beb18)
- **spec:** SPEC-101 arquiva o canvas no repositório (3dccc68)
- **spec:** SPEC-101 concluída, com o E2E no app isolado e os prints (T5) (2e614a3)
- **spec:** SPEC-098 Memória com ai-memory (eca6fc9)
- **spec:** SPEC-098 com a issue #337 (9621dfb)
- **spec:** SPEC-098 vai para a 0.24.0 (b5e8a39)
- **spec:** SPEC-098 arquiva o canvas no repositório (3742e77)
- **spec:** SPEC-098 em implementação, decisões P1–P8 fechadas (55cce44)
- README de projeto com logo, badges e apresentação (66633d0)
- **spec:** SPEC-099 Passar o trabalho entre agentes (603ff8d)
- **spec:** SPEC-099 com a issue #338 (cb1b3ad)
- **spec:** SPEC-099 vai para a 0.24.0 (90c9161)
- **spec:** SPEC-099 arquiva o canvas no repositório (983337c)
- **spec:** SPEC-099 em implementação, com as decisões P (91e3586)
- **spec:** SPEC-099 concluída, com a implementação e o E2E (3916b3f)
- **spec:** SPEC-103 Hooks gerenciados nos dois provedores, com mocks (ff9d39e)
- **spec:** SPEC-103 aponta para a issue #348 (931280c)
- **spec:** SPEC-103 vai para a 0.24.0 (3fd6203)
- **spec:** SPEC-103 arquiva o canvas no repositório (b75571c)
- **spec:** SPEC-103 em implementação, decisões P fechadas (ac9f72b)

### Testes

- O Codex roda nas execuções estruturadas (SPEC-100 R8) (0932c65)
- **revisor:** O Codex libera o fluxo do revisor automático na seleção de provedor (SPEC-102) (f3d846c)
- **configurações:** Executar spec liberado no chip do Codex (SPEC-101) (4580bf0)
- **provedores:** Executar spec liberado para o Codex no registro de fluxos (SPEC-101) (fea62cf)
- Desfaz formatação acidental em codex_consumption_test (SPEC-098 T3) (9711f2c)
- **sessoes:** Formatar pós-turno espera o turno começar (SPEC-103) (91c7161)
- **sessoes:** Formatar pós-turno espera o turno começar (SPEC-103) (81ce0aa)

## [0.23.1] - 2026-11-22

### Correções

- **sessoes:** Arquivos alterados e Diff medidos desde o merge-base da sessão (SPEC-111) (c046d7c)

### Documentação

- **spec:** SPEC-111 alterações e Diff da sessão depois do commit (#376) (bf9409e)
- **spec:** SPEC-111 concluída, com os prints do app (bd5c1d1)

### Testes

- **rodape:** Casos da cota não dependem da hora do dia (quebravam entre 00:00 e 01:00 no CI) (6abe670)

## [0.23.0] - 2026-11-21

### Funcionalidades

- **codex:** Sonda do Codex 0.170 com parte paga atrás de --pago (SPEC-093) (a219468)
- **provedores:** Capacidades declaradas por provedor e registro de fluxos (SPEC-094 T1) (cc7401a)
- **provedores:** Opções = intenção + extras tipados, acesso por adaptador (SPEC-094 T2) (8a886d0)
- **provedores:** Modelos do Codex, versão mínima, sandbox, etiqueta Só Claude Code e fim das comparações soltas (SPEC-094 T3) (873d657)
- **provedores:** Identidade visual com logos oficiais, glifos e ProviderChip (SPEC-094 T4) (bee0ac8)
- **eventos:** Tipos neutros, conversor do Claude e Codex emitindo neutros (SPEC-095 T1) (1fcea5a)
- **timeline:** Cartões de arquivo e comando, arquivos do turno e Atividades pelos eventos neutros (SPEC-095 T2) (b0f3a6e)
- **contexto:** Medidor e Replay pelos eventos neutros, antes do Codex pelo diff (SPEC-095 T3) (9b266f1)
- **codex:** Religar Prompt e Sessões, estado e login, interruptor de emergência e provedor nas listas (SPEC-096 T1) (f29d98e)
- **codex:** Codex no Prompt — thread em read-only, direcionar, interromper, Aprovar nesta conversa, permissões e Executar plano (SPEC-096 T2) (9147494)
- **codex:** Sessões com o Codex — worktree que commita, interromper, retomar, fork com vínculo (v35), terminal e acesso por turno (SPEC-096 T3) (3d3743e)
- **codex:** Grupo de processos do App Server, órfãos na partida e SPEC-006/007 revalidadas (SPEC-096 T4) (fa6053e)
- **codex:** Sem sandbox o Codex só roda em worktree com YOLO, E2E com capturas e SPEC-096 concluída (SPEC-096 T4) (e7e57f9)
- **cota:** Ler a cota do Codex sem turno, mesclar atualizações e guardar por provedor (SPEC-097 T1) (1e6d013)
- **custo:** Ledger com provedor e tokens de raciocínio, custo indisponível no Codex e ranking sem zero falso (SPEC-097 T3, schema v34) (25442d5)
- **rodape:** Régua da cota do provedor ativo, detalhe lado a lado e aviso de limite na Nova sessão (SPEC-097 T2) (3b99401)

### Correções

- **provedores:** Registro não dispara a detecção do Codex; status em implementação reconhecido (cf12fec)
- **provedores:** Menu do rodapé mais largo, modelos do Codex em lista e prints do app (SPEC-094) (1f4e639)
- **specs:** Status em implementação conta como aprovada (c942af1)
- **rodape:** Nome do provedor inteiro no detalhe da cota (f36970e)
- **codex:** Primeira mensagem não duplica, trocar de workspace encerra o Codex ocioso, teste de widget das Sessões recuperado e turno real sem mexer no config.toml (SPEC-096 pendências) (3c215ea)
- **sessoes:** O commit do app no fim do turno do Codex entra antes do ponto de restauração (4e994ef)
- **inicio:** O custo de Hoje não soma o Codex como $0.00 (SPEC-097 decisão 5) (f771c74)
- **codex:** Rotular o modo Perguntar como Perguntar, não Planejar (657e094)
- **codex:** O diálogo de fork do Codex não cita as flags do Claude (375c651)
- **codex:** Separar as colunas do custo nas linhas só do Codex (64b2b81)
- **codex:** Com o Codex desligado, o Prompt não o oferece nem cria conversa vazia (306792d)

### Documentação

- **spec:** SPEC-096 Codex no Prompt e nas Sessões, com tarefas pai/filhos e mocks (4d6f45a)
- **spec:** SPEC-096 aponta a issue #343 (d87644f)
- **spec:** SPEC-096 cores de provedor (1955a78)
- **spec:** SPEC-096 logos oficiais de provedor (f2c68f5)
- **spec:** SPEC-096 logo da OpenAI em branco oficial (d4b7743)
- **spec:** SPEC-096 aprovada (3eb20de)
- **spec:** SPEC-096 worktree sem sandbox e commit do app (decisão 15) (bb5df3b)
- **spec:** SPEC-094 Capacidades e opções por provedor, com mocks (57948c8)
- **spec:** SPEC-094 aponta a issue #334 (254f934)
- **spec:** SPEC-094 cores de provedor (6a74641)
- **spec:** SPEC-094 logos oficiais de provedor (983c13b)
- **spec:** SPEC-094 logo da OpenAI em branco oficial (b9c666c)
- **spec:** SPEC-094 aprovada (00f07cb)
- **spec:** SPEC-094 sandbox disponível por máquina (decisão 15) (a4c31f2)
- **spec:** SPEC-093 Sondagem do Codex 0.170, plano técnico do épico e destino das specs 002–007 (518c4f5)
- **spec:** SPEC-093 aponta a issue #333 (12d0902)
- **spec:** SPEC-093 aprovada (bc8cbb2)
- **pesquisa:** Relatório da sondagem do Codex 0.170 e SPEC-093 concluída (c78f2dd)
- **spec:** SPEC-094 em implementação, decisões P fechadas (be210dc)
- **spec:** SPEC-094 concluída, critérios e registro da implementação (522e378)
- **spec:** SPEC-095 Eventos neutros, com mocks (0d145f0)
- **spec:** SPEC-095 aponta a issue #335 (512e9e0)
- **spec:** SPEC-095 cores de provedor (25f0ef1)
- **spec:** SPEC-095 logos oficiais de provedor (9c06e86)
- **spec:** SPEC-095 logo da OpenAI em branco oficial (84e8a64)
- **spec:** SPEC-095 aprovada (3d0e0ac)
- **spec:** SPEC-095 em implementação, decisões P1–P5 (367e481)
- **spec:** SPEC-095 prints do app (e9f0591)
- **spec:** SPEC-095 concluída (67ae2fb)
- **spec:** SPEC-094 permissão de uso do logo da OpenAI concedida (bc9c634)
- **spec:** SPEC-096 em implementação, decisões P fechadas (5cec506)
- **spec:** SPEC-097 Cota do Codex no rodapé, com mocks (6f068f5)
- **spec:** SPEC-097 aponta a issue #349 (cf59379)
- **spec:** SPEC-097 cores de provedor (eeec984)
- **spec:** SPEC-097 logos oficiais de provedor (353c75e)
- **spec:** SPEC-097 logo da OpenAI em branco oficial (9aea410)
- **spec:** SPEC-097 aprovada (40075f5)
- **spec:** SPEC-097 em implementação, decisões fechadas (88f9cb1)
- **spec:** SPEC-097 concluída, prints do app (b55008a)

### Testes

- **codex:** Fixtures reais do App Server 0.170 e modo de reprodução no fake_codex (SPEC-093) (17aeb33)
- Imports não usados (3d1ddf6)
- Sem reformatar o teste do rodapé (e19e0f7)

### Manutenção

- Desfaz reformatação alheia (c88df3f)

## [0.22.0] - 2026-11-21

### Funcionalidades

- **contexto:** Sondagem do CLI, contrato da medição e redutor (SPEC-087 T1) (4f0cdfe)
- **contexto:** Medidor e painel Contexto no Prompt e nas Sessões (SPEC-087 T2) (82b0226)
- **contexto:** Compactação automática visível, aviso e ações (SPEC-087 T3) (66df732)
- **contexto:** Comparar, Replay e retomada com leituras próprias (SPEC-087 T4) (bd44399)

### Correções

- **contexto:** Aviso segue a leitura mais nova e diz quando o limiar passou (20340af)
- **contexto:** Ajustes do teste no app isolado (045d3cb)
- **comparar:** Medidor de cada lado junto das métricas (0ee77f2)

### Documentação

- **spec:** SPEC-087 contexto visual e compactação, com mocks (0ce3c22)
- **spec:** SPEC-087 aponta a issue #324 (c63acda)
- **spec:** SPEC-087 aprovada (4eaa905)
- **spec:** SPEC-087 concluída, com capturas do app e teste manual (48e489e)

### Testes

- O FakeProcess separa os pedidos de get_context_usage das mensagens (6b6402b)

## [0.21.1] - 2026-11-20

### Correções

- **prompt:** Título Aplicar à spec e sugestão em Markdown (SPEC-088) (c5f8477)
- **specs:** Replanejar deixa um único ## Plano em spec já duplicada (SPEC-090) (e98a29c)
- **specs:** Resposta às perguntas sem marcas de Markdown e foco visível (SPEC-091) (6addfe0)
- **revisao:** Cartão em resolução volta a selecionar o item (SPEC-092) (d7e2359)
- **specs:** Commitar a spec ao salvar o plano de Planejar (#313) (0c8a8af)

### Documentação

- **specs:** Telas e status concluída das SPEC-088 a 092 (4e1f854)

### Testes

- **quadro:** Dependências em janela estreita e atualização ao vivo (SPEC-089) (7ca184f)
- **comparar:** Reset da semana relativo à data atual (556d0a2)

## [0.21.0] - 2026-11-19

### Funcionalidades

- **prompt:** Cabeçalho Aplicar à spec e cartão da sugestão com pedido completo (SPEC-088) (b042221)
- **quadro:** Bloco Depende de com o estado de cada dependência no painel da spec (SPEC-089) (1674a31)
- **specs:** Perguntas com opções no mini planejamento (SPEC-091) (0398166)
- **revisao:** Abrir a sessão de resolução do conflito pela fila e pelo chip (SPEC-092) (f865832)

### Correções

- **specs:** O plano gerado não repete o título Plano (SPEC-090) (a5c1e2a)

## [0.20.0] - 2026-11-17

### Funcionalidades

- **spec-079:** Núcleo da comparação de respostas (7141859)
- **spec-079:** Interface da comparação de respostas (281a467)
- **spec-083:** Núcleo dos prints — área de transferência, preparo, planner e cópia para docs/mockups (38ca376)
- **spec-083:** Telas dos prints — colar, cartões, Referência visual e guarda da marca (eec7d06)
- **db:** Tabela activity_events na migração v30 provisória (SPEC-080 R6) (eb37c13)
- **resume:** Diário do que terminou e conferência do GitHub ao abrir (SPEC-080 R6, R7) (2291bcd)
- **resume:** Cartão Retomar de onde parei, presença, faixa do Início, Atividades, paleta e Configurações (SPEC-080 R1–R5, R8–R15) (b004cf7)
- **db:** Tabela usage_entries na migração v30 provisória (SPEC-081 R1) (bdb4895)
- **custo:** Registro dos turnos, régua da cota e histórico de antes (SPEC-081 R1–R5) (dc3f757)
- **custo:** Seção Cota no painel da spec, card sem custo e ranking nas Métricas (SPEC-081 R6–R14) (63248d1)
- **db:** Tabela restore_points na migração v30 provisória (SPEC-084 R3) (c774ba7)
- **sessoes:** Ponto de restauração antes e depois de cada turno, desfazer/refazer e retenção (SPEC-084 R1–R4, R6–R8, R11–R13, R15–R17) (d9635c7)
- **sessoes:** Botão Desfazer o último turno, janela do desfazer, pontos no painel e na timeline, paleta e Configurações (SPEC-084 R5, R6, R9–R12, R14, R16) (ad6af73)
- **segredos:** Tabela secret_waivers na migração v30 provisória (SPEC-085 R11) (26379ac)
- **segredos:** Regras, scanner, máscara, impressão, hook em Python e gitleaks (SPEC-085 R1, R3, R4, R8, R13, R16) (608b6a8)
- **segredos:** Cartão do bloqueio na sessão, ações, justificativa, pedidos "Segredo encontrado" e conferência sem hook (SPEC-085 R1, R2, R7–R11) (d263510)
- **segredos:** Vigia nos commits e pushes do app, janela de achados, commit manual da tela Código e Configurações › Vigia de segredos (SPEC-085 R5, R6, R12–R15) (74595b7)

### Correções

- **spec-079:** Resposta interrompida marcada, peso de reserva com as conversas e prompt de volta ao descartar (99d22d7)
- **resume:** O foco sozinho não conta como presença; título do Terminou no O que aconteceu (SPEC-080 R2, R13) (4deb890)
- **custo:** Ajustes vistos no app real (SPEC-081) (157bd5c)
- **sessoes:** Ponto do primeiro turno antes de o agente iniciar; aviso de desfeito some em 10 s (SPEC-084 R1, R11) (05b6e67)
- **sessoes:** O limite de 5 s vale para a captura; um ponto capturado a tempo é gravado inteiro (SPEC-084 R4) (e51be4a)
- **segredos:** Retoma a sessão com o aviso, log de hooks novo por processo, botões desabilitados em vez de sumirem e layout do achado (SPEC-085 R7, R9) (081ae93)

### Documentação

- **spec-079:** Spec e canvas de comparar respostas (b95b27b)
- **spec-079:** Issue #272 (6d7cc6a)
- **spec-079:** Aprovada para a 0.20.0, decisões fechadas (c4b1923)
- **spec-083:** Spec a partir de um print, rascunho e canvas (e77cf32)
- **spec-083:** Issue #277 (c0fae9a)
- **spec-083:** Aprovada para a 0.20.0, decisões fechadas (4283631)
- **spec-083:** Prints do app real e critérios conferidos (58bbf14)
- **spec-080:** Spec e canvas de retomar de onde parei (b210104)
- **spec-080:** Issue #274 (b5f855c)
- **spec-080:** Aprovada para a 0.20.0, decisões fechadas (40088a8)
- **spec-080:** Prints do app real, v30 provisória e critérios conferidos (286a02f)
- **spec-081:** Custo por spec, rascunho e canvas (b15a995)
- **spec-081:** Issue #271 (0e40459)
- **spec-081:** Custo no verso do card, que vira (72fbe8b)
- **spec-081:** Medidor de cota como gatilho do verso (45433bd)
- **spec-081:** Custo só no painel da spec; o card não muda (3e0aab6)
- **spec-081:** Aprovada para a 0.20.0, decisões fechadas, card sem custo (71b1f5e)
- **spec-084:** Ponto de restauração — spec e mockups (01a86a1)
- **spec-084:** Issue #270 (b554d64)
- **spec-084:** Aprovada para a 0.20.0, decisões fechadas (8f48dd5)
- **spec-084:** Prints do app real e critérios conferidos (d53a29a)
- **spec-085:** Vigia de segredos — spec e mockups (7589b3a)
- **spec-085:** Issue #273 (2ae9da9)
- **spec-085:** Aprovada para a 0.20.0, decisões fechadas (b1a616b)
- **spec-085:** Prints do app real e critérios conferidos (bc78287)

### Manutenção

- Desfaz formatação fora do escopo (19f1193)

## [0.19.0] - 2026-11-17

### Funcionalidades

- **spec-077:** Copiar código, seleção única e blocos recolhíveis no markdown (9f9e28b)
- **snippets:** Tabela snippets na migração v29, repositório, nome sugerido e copiar/inserir no composer (SPEC-078 R3, R5, R8) (cc239ce)
- **snippets:** Salvar no bloco, grupo Snippets na paleta, diálogo Snippets e seção no painel do Prompt (SPEC-078 R1–R4, R6–R14) (c8b8c70)
- **spec-082:** Passos do replay, estado neste ponto e arquivo neste ponto (3ca60c4)
- **spec-082:** Aba Replay, linha do tempo, painel do passo e entradas "Ver replay" (df2892a)
- **spec-086:** Notificações direto no DBus, com clique e token de ativação (c8c04c2)
- **spec-086:** Robô parado acenando para a notificação (2de3075)
- **spec-086:** Alertas com o robô, contra spam, e o clique abre o pedido (741c9e9)
- **spec-086:** Configurações › Notificações com prévia e Testar notificação (bd251fb)

### Correções

- **spec-077:** Copiar mensagem só com o ícone (R7) (2df4da0)
- **paleta:** Chips de prefixo no tamanho do texto e prévia do snippet sem rolagem (SPEC-078 R6, R7) (044999f)
- **spec-082:** Posição no filtro com o cursor fora dele mostra "–" (1aeb83f)
- **spec-086:** O foco do clique fica com o cartão da tela nova, não com o flutuante (f4e49ec)

### Documentação

- **spec-078:** Spec e canvas dos snippets salvos (7e0fecc)
- **spec-078:** Issue #269 (e6a05d4)
- **spec-077:** Spec e mockups de Copiar código (c55fae5)
- **spec-077:** Issue #266 (ae7b8c0)
- **spec-077:** Decisões fechadas, prints do app real e critérios conferidos (5fb78c5)
- **spec-078:** Aprovada, decisões P1–P9 e versão 0.19.0 (dfd7ec0)
- **spec-078:** Prints do app real e critérios conferidos (50aa9c5)
- **spec-082:** Replay da sessão, rascunho e canvas (d5f93d0)
- **spec-082:** Issue #275 (7e017b3)
- **spec-082:** Aprovada, decisões P1–P7 e versão 0.19.0 (9683ae9)
- **spec-082:** Prints do app real e critérios conferidos (1e56726)
- **spec-086:** Notificação com o robô — spec e mockups (02740a3)
- **spec-086:** Issue #276 (70c88de)
- **spec-086:** Aprovada, decisões P1–P6 e versão 0.19.0 (51c671b)
- **spec-086:** Prints do app real e critérios conferidos (c873064)

### Testes

- **spec-086:** Import a mais (4ac6e53)
- **spec-086:** Import a mais (16539af)
- **spec-082:** Limite de 100 ms no passo do cursor do replay, para os runners do CI (f3d5a40)

## [0.18.0] - 2026-11-16

### Funcionalidades

- **spec-072:** Ambiente, hospedagem e branch inicial na tela Começar (R1–R6, R15, R20–R22) (24f6e1a)
- **spec-072:** Custo e tempo honestos na criação (R7–R10) (c3ed3fb)
- **spec-072:** Comandos da stack no config.yml e Saúde no stepper (R11–R14) (4e7c25c)
- **spec-072:** Stack fora dos modelos com o chip "Outro…" (R16–R19) (b52e618)
- **review:** Checks com run, job e workflow, e o corte do log do CI (SPEC-073 R1, R3, R9) (c81f2e0)
- **review:** Corrigir CI e Rodar de novo, no Review e no card (SPEC-073 R2, R4–R8, R10) (bb662ad)
- **review:** Corrigir CI sozinho, uma vez por commit vermelho (SPEC-073 R11–R13) (a83bc66)
- **issues:** Comandos de issue no GhCli, issue: N lido no sync (migração v28 provisória), diagnóstico do GitHub e o selo #N na Bandeja, no Quadro e em Specs (SPEC-074 R1, R2, R12) (75f7765)
- **issues:** O PR da spec ligada leva Closes #N ou Parte de #N, o Pronto para merge mostra a linha da issue, o estado das issues muda só o selo e a spec ganha Criar issue (SPEC-074 R8, R9, R11) (56eedde)
- **issues:** Com o opt-in issues.comentar-andamento, o anotar_andamento mantém um comentário por spec na issue, e a configuração do projeto ganha a seção Issues do GitHub (SPEC-074 R10) (5e78ca9)
- **issues:** Importar issues na Bandeja e na paleta, com filtros, páginas de 50 e sem duplicar; a issue vira rascunho com o Objetivo, e o menu da spec refina com o Claude, atualiza com a issue e desliga (SPEC-074 R3–R7, R12) (21be11d)
- **spec-076:** Núcleo da Atividades — registro, o que o agente faz, cota e pausas (t1) (537a8e8)
- **spec-076:** Robôs dos agentes e o Quadro com robôs (t2) (f18e0f7)
- **spec-076:** Tela Atividades, item no menu com o selo e o robô do card (t3) (b0e9e20)

### Correções

- **spec-072:** Custo e tempo depois das opções de Revisar e criar (R10) (dc3676c)
- **spec-072:** Chips do Ponto de partida e "Gravar no git" não esticam na linha toda (0cf757a)
- **spec-072:** Comandos legíveis no modal "Outro…" e alternativas da stack como chips (bff5345)
- **spec-072:** A chave worktree.preparar cabe numa linha no modal "Outro…" (0080e0e)
- **spec-073:** "Rodar de novo" e "Corrigir CI" lado a lado no Review (612f24a)
- **spec-073:** "Corrigir CI" sai do modo plano antes de mandar o log (339f949)
- **spec-073:** PR com CI vermelho aparece como "CI falhou" na lista do Review (08bfd4d)
- **issues:** A fila da importação é por pasta do workspace (SPEC-074 R4) (9252a8e)
- **spec-074:** Título ## da issue desce um nível no Objetivo, não dois (7f3e7f1)
- **spec-074:** O selo "#N fechada" aparece inteiro no card do Quadro (d3c0c30)
- **spec-074:** Selo da issue não corta no card estreito do Quadro (14275bd)
- **spec-075:** Botões com a largura do texto, só expand estica (9e77a27)

### Desempenho

- **spec-076:** Robôs no relógio ambiente (24 Hz), como os outros laços (c1f9270)

### Documentação

- SPEC-072, criação confiável (#241) (41a8961)
- **spec-072:** Link do PR #244 (31b5311)
- **spec-072:** Status em-revisao, um valor que o app reconhece (b0d11e9)
- **spec-072:** Stack fora dos modelos pelo chip Outro (R16–R19) (711058c)
- **spec-072:** Hospedagem GitHub, GitLab ou Local no Ambiente (R20–R22) (8154d34)
- **spec-072:** A hospedagem segue o Repositório remoto (R20–R22, P11) (99f5d0d)
- **spec-072:** Aprovada (b967807)
- **spec-072:** Marca os critérios de R1 a R22 (86c22ca)
- **spec-072:** Prints do app compilado e critérios manuais marcados (5e56db3)
- SPEC-073, CI vermelho vira correção (#242) (7f4af44)
- **spec-073:** Link do PR #245 (a8b9166)
- **spec-073:** Status em-revisao, um valor que o app reconhece (cf66721)
- **spec-073:** Aprovada (cf0d826)
- **spec-073:** Decisões P1–P6 registradas e critérios marcados (84fcddc)
- **spec-073:** Prints do app compilado e critério manual marcado (3189336)
- SPEC-074, issues e specs nos dois sentidos (#243) (de1efd2)
- **spec-074:** Link do PR #246 (7cec7c9)
- **spec-074:** Status em-revisao, um valor que o app reconhece (ae7e63b)
- **spec-074:** Aprovada (23d1c79)
- **spec-074:** Decisões P1–P6 registradas e critérios de aceite marcados (f3cbd0d)
- **spec-074:** Prints do app compilado e critério manual marcado (1a9e607)
- **spec-075:** Spec dos botões com a largura do texto (4520779)
- **spec-075:** Prints antes e depois (ff35f32)
- **spec-076:** Mockups do canvas da Atividades (e3d8a0a)
- **spec-076:** Spec da Atividades (02815b9)
- **spec-076:** Link do PR (2f1fb3f)
- **spec-076:** Prints do app real e critérios conferidos (f2fb0ee)

### Testes

- **spec-072:** O rádio do remoto entra na tela antes do toque (027ef42)
- **issues:** O selo conta a semântica pelo widget, sem timer pendente, e a busca do dublê não conta os PRs (SPEC-074 R1, R12) (e59a66b)
- **specs:** O print da miniatura procura a chamada do navegador, não a primeira (o Specs pergunta o remote ao git, SPEC-074 R2) (ecbe125)
- **spec-076:** O menu tem onze itens, dez com atalho (119d65b)

## [0.17.2] - 2026-11-15

### Correções

- **review:** Merge sem perder trabalho, verificação de PR e VIBE em gate (R1–R5) (a8f6cde)
- **processos:** Git, gh e o runner padrão aceitam saída fora de UTF-8 (R12) (fa50fde)
- **processos:** Consulta de uso encerrada no limite, uma por vez (R16) (cb0bc89)
- **processos:** Fim do claude sem esperar 2 s; streams tolerantes (R12, R13) (560e828)
- **processos:** Redação do Codex sobre os valores do JSON (R12, R14) (5deec45)
- **processos:** ACP sem processo órfão e com limite no handshake (R12, R15) (b974883)
- **review:** Saída do gh decodificada com substituição (R12) e critérios R1–R5 marcados (abd37e9)
- **quadro:** Uma spec nunca arranca duas vezes (R6) (cf648d2)
- **sessões:** Mensagem no instante da ociosidade não se perde (R7) (331ad5e)
- **sessões:** Retomar fica ocupado e não manda Continue duas vezes (R10) (75e076c)
- **sessões:** Elemento apontado chega ao composer depois de trocar de tela (R11) (a384eb9)
- **specs:** Editor não sobrescreve alteração feita fora do app (R8) (d2c04f1)
- **quadro:** Só transições válidas ao arrastar e em Mover para (R9) (7536974)
- **dev:** Parar durante a subida encerra o servidor que estava subindo (R17) (0a1c1c6)
- **preview:** Abrir o preview duas vezes reaproveita a mesma abertura (R18) (043d6b7)
- **mcp:** Parar o servidor MCP durante a partida fecha o socket (R19) (10501b1)
- **dados:** A cópia antes da restauração leva o -wal e o -shm (R20) (12bb33d)
- **projeto:** Confere a identidade do git antes de criar, aceita repetir após falha e começa na main (R21, R25) (ec6883c)
- **projeto:** Specs do roadmap vão para o Backlog do Quadro e repetir após falha não duplica (R22) (c84b8f5)
- **projeto:** CLAUDE.md mínimo do modelo é substituído por padrão e vai ao planner como base (R23) (5571f1d)
- **projeto:** CLAUDE.md, README, LICENSE e .gitignore não contam como código (R24) (1e24774)
- **projeto:** Área fixada não duplica com sinônimo e a proposta completa fica ocupada até o fim (R26) (7600211)
- **spec-071:** Repositório sem commits sempre aponta o HEAD para main (R25) (454dd52)

### Refatoração

- **projeto:** Enter no nome cria o projeto; sai o NewProjectDialog morto e tildePath/defaultProjectParent vão para core (R26) (f6f2635)

### Documentação

- **spec:** SPEC-071 Correções da 0.17.2 (35f2940)
- **spec:** SPEC-071 marca os critérios de R12–R16 (214cd61)
- **spec:** SPEC-071 marca os critérios de R6 a R11 (12c085c)
- **spec:** SPEC-071 marca os critérios de R17–R26 (34cf493)
- **spec-071:** R9 deixa claro que a VIBE vai para Feito pelo merge (5030341)

## [0.17.1] - 2026-11-15

### Correções

- **atualização:** Fecha pelo encerramento da janela e reabre pelo lançador (SPEC-070 R1–R6) (faca741)
- **sobre:** A logo toca a abertura uma vez e depois só borbulha (SPEC-070 R7) (32715fc)
- **update:** Saída da cópia nova, troca atômica e fechamento durante a instalação (SPEC-070 t3) (22f739e)

### Documentação

- **SPEC-070:** Spec e mockups de atualizar e reabrir e da logo do Sobre (b4b2e89)
- **SPEC-070:** Issue #221 (d472f22)
- **SPEC-070:** Link do PR #222 (f7de6c7)
- **SPEC-070:** Critérios cumpridos, causa do bug 1 e telas do app real (40e4dc6)

### Build e CI

- **release:** Número de build a partir da última tag quando a main está atrás (#225) (d56b09d)

## [0.17.0] - 2026-11-14

### Funcionalidades

- **motion:** Tokens AppMotion, MotionEnter e animações desligadas na suíte (SPEC-034 T1) (9f4bb53)
- **motion:** Transição de seção e destaque deslizante na barra lateral (SPEC-034 T2) (2618783)
- **motion:** AppPressable com hover e press em cards, linhas e botões (SPEC-034 T4) (d56c65e)
- **motion:** Eventos novos na timeline e status da etapa com check (SPEC-034 T6) (5a642ca)
- **motion:** Bola da etapa no espaço do ponto antigo, sem quebrar o texto (SPEC-034 T6) (946420b)
- **motion:** Diálogos e toasts com o ritmo do app (SPEC-034 T3) (5660af8)
- **motion:** Skeleton ao abrir uma spec, com o documento atual nos primeiros 300 ms (SPEC-034 T7) (5bfe894)
- **motion:** Card desliza até a coluna nova no Quadro (SPEC-034 T5) (86f4774)
- **motion:** Toast flutuante, teste de R13 e spec atualizada (SPEC-034 T8) (611f236)
- **board:** Subetapas na fila, verificação do requisito na última (SPEC-033 T2) (0bd9f70)
- **board:** Opções do modal de decisão da etapa (SPEC-033 T1) (65561c6)
- **board:** Modal de decisão até a escolha (SPEC-033 T3) (8d5fb8e)
- **board:** Fase Compilar do modal de decisão (SPEC-033 T4) (b2b0a80)
- **orquestrador:** Regras e dados do orquestrador (SPEC-035 T1) (475514f)
- **settings:** Seção Orquestrador (SPEC-035 T2) (81e9275)
- **orquestrador:** Classificação das etapas (SPEC-035 T3) (5677b25)
- **board:** Executar em Automático com o plano por etapa (SPEC-035 T4) (5a0c982)
- **board:** Cada etapa com o modelo do plano (SPEC-035 T5) (37dba07)
- **orquestrador:** Escalada de modelo quando a verificação reprova (SPEC-035 T6) (12268bb)
- **settings:** Histórico do orquestrador (SPEC-035 T7) (79d74e8)
- **board:** Paleta segue o Automático (SPEC-035 R19) (990817d)
- **board:** Visão Foco com a pasta de specs (SPEC-036 T1) (36a59e2)
- **board:** Busca na pasta de specs (SPEC-036 T2) (ce85c8c)
- **board:** Palco do Foco com dependentes e setas (SPEC-036 T3) (d584983)
- **board:** Specs em execução no palco (SPEC-036 T4) (bb8f4ec)
- **specs:** Ação Planejar e seção ## Plano, com leitura de ## Design (SPEC-037 R1-R4) (45faf08)
- **specs:** Rodada que refina e planeja, com as regras do R12 (SPEC-037 R6, R12) (2bcb2a5)
- **project:** Fila que refina e planeja as specs ao criar o projeto (SPEC-037 R5-R9, R11) (9db8a66)
- **specs:** Specs da fila bloqueadas e marca retirada ao salvar (SPEC-037 R10, R13) (c47c6be)
- **board:** Executar e autopilot esperam o plano, com Plano anterior no cartão (SPEC-037 R13) (8a51382)
- **update:** Só as novidades da última versão, sem hash e sem escopo (SPEC-038 R5, R6) (254ce87)
- **splash:** SplashStage público, com loop opcional e estado final sem bolhas (SPEC-038 R2, R3) (eccc9ae)
- **shell:** UpdateFlow, a atualização inteira num estado selado (SPEC-038 R7, R8) (c35bc09)
- **shell:** Sobre em duas colunas, com o cartão de atualização e só a última novidade (SPEC-038 R1, R4, R5, R7-R9, R11, R12) (f64b895)
- **db:** Spec_drafts, o rascunho de Nova spec por workspace (SPEC-039 R8) (fbd9ca1)
- **specs:** Planner da nova spec, com rascunho e limite de 6 requisitos (SPEC-039 R4-R6, R9, R10) (4b736c7)
- **specs:** Sem Plano, Planejar é a ação em destaque (SPEC-039 R7) (26774a1)
- **specs:** Tela de ideia e mini planejamento em Nova spec (SPEC-039 R1-R3, R5-R9, R12) (9c5829e)
- **tray:** Radar na bandeja com estado no ícone, tooltip e menu (SPEC-041) (a408a2e)
- **sprints:** Tabela, migração, repositório e regras (SPEC-042 T1) (2081c23)
- **sprints:** Seletor no Quadro, criação e movimentação de specs (SPEC-042 T2) (2ab1c62)
- **sprints:** Grafo e Foco por sprint, com dependências externas e busca em todas (SPEC-042 T3) (13eaab4)
- **sprints:** Concluir sprint, Autopilot na sprint Ativa e aviso de pendências (SPEC-042 T4) (9d06068)
- **repo:** Casca da tela Repositório com a aba Releases (SPEC-044 R1, R10) (c99ac84)
- **repo:** Linha do tempo, card Não lançado e prévia do changelog (SPEC-044 R2-R4, R9) (5c4ea2a)
- **repo:** Criar release, acompanhamento do run e aviso no fim (SPEC-044 R5-R8) (30872ff)
- **repo:** Raias do grafo calculadas pelo app (SPEC-045 R1, R3, R7) (2397b95)
- **repo:** Aba Grafo com raias, cores da spec e etiquetas (SPEC-045 R1-R4, R8) (1f5d42b)
- **repo:** Painel do commit, filtros, busca e atualização ao vivo do grafo (SPEC-045 R5-R7) (c96ca70)
- **git:** Marcar commits das sessões de agente (SPEC-048 R1, R2, R3, R8) (b750167)
- **git:** Commit do app marcado como app e leitura das origens (SPEC-048 R4, R5) (411518f)
- **git:** InfoTip, grupo Git na configuração e confirmação de ligar (SPEC-048 R1, R6, R7) (24f3145)
- **repo:** Aba Atividade com resumo, mapa por dia, tipos, ciclo das specs, arquivos e quem fez os commits (SPEC-046 R1–R8) (866fbf2)
- **repo:** Etiqueta do modelo ao lado do autor no Grafo (SPEC-045 R9) (8c3e769)
- **repo:** Painel do arquivo com três commits por spec e "+N anteriores" (SPEC-046 R5) (66df960)
- **git:** Worktrees órfãos, atrás e à frente, PRs mergeados e conflito por branch (SPEC-047) (f1f6719)
- **repo:** Análise e limpeza de branches, worktrees e refs com proteções e Desfazer (SPEC-047 R2–R7) (5af1c02)
- **repo:** Aba Higiene e card do Início acima de 20 itens (SPEC-047 R1, R6–R8) (d140140)
- **review:** Gate confere a resolução de conflito (SPEC-043 R1) (8e2cfe2)
- **review:** Estados da resolução, saídas e o que ela decidiu (SPEC-043 R2–R4) (ff550db)
- **perf:** Medidor de quadros e script de medição (SPEC-049 R7) (0eabaea)
- **ui:** Fundo de vidro, tokens translúcidos, AppGlass e desfoque dos diálogos (SPEC-049 R1, R3, R5, R6) (c71effb)
- **ui:** Casca flutuante em vidro, colunas e cartões de vidro, menus opacos e a seção Aparência (SPEC-049 R2–R4, R6) (8815592)
- **board:** Agendador e widget do tremor de atenção (SPEC-054 R1–R4, R6, R8, R9) (7189d97)
- **board:** Tremor de atenção nas Colunas, no Grafo e no Foco (SPEC-054 R5) (3fd9ce5)
- **settings:** Opção Tremer cards que precisam de você em Aparência, guias e decisões (SPEC-054 R7) (2af6593)
- **ui:** Nova spec com movimento curto, foco e respiração de atenção (SPEC-053 R1–R6) (6f58605)
- **board:** Barra do Quadro em três zonas, controle segmentado e filtros num chip na janela estreita (SPEC-053 R7–R9) (4791241)
- **ui:** Prompt logo abaixo do Projeto na barra lateral (SPEC-055 R1–R3, R6, R8) (91825dd)
- **ui:** Ícone novo do Prompt, ponto "respondendo" e contador próprio (SPEC-055 R4, R5, R10) (b49b80c)
- **prompt:** Tela de boas-vindas com os três modos e exemplos (SPEC-055 R7, R9, R10) (aafed6e)
- **prompt:** Arquivar e desarquivar conversas (SPEC-056 R1, R4–R7, R11) (0addf21)
- **prompt:** Renomear a conversa no cabeçalho e na lista (SPEC-056 R2, R3) (7de61a6)
- **prompt:** Recolher o painel da direita numa faixa de 48 px (SPEC-056 R8–R10) (7d7c456)
- **ideas:** Ler PDF, Markdown e TXT para o "Conte a ideia" (SPEC-057 R3, R7) (e295764)
- **ideas:** Campo "Conte a ideia" com importação de arquivo (SPEC-057 R1, R2, R4–R6, R9) (1076a74)
- **specs:** Importar arquivo na Nova spec e no passo Visão (SPEC-057 R8) (fe8e7b4)
- **sessions:** Item da sessão ampliado com navegação e volta ao cartão (SPEC-058 R1–R3, R8, R9, R11) (d0a6a8a)
- **sessions:** Texto inteiro com números de linha e busca na visão ampliada (SPEC-058 R4, R5, R7) (1109111)
- **sessions:** Diff lado a lado, Abrir no Código e janela estreita na visão ampliada (SPEC-058 R6, R10) (2c5e70f)
- **specs:** Perguntas da spec no centro, com coluna de 720 px e teclado (SPEC-059 R1–R5, R9, R10) (2e3bab8)
- **specs:** Outra resposta que cresce e trecho da spec junto da pergunta (SPEC-059 R6, R7) (f3e2a65)
- **specs:** Revisão e diff das respostas na coluna central (SPEC-059 R8) (a7b49ac)
- **board:** Executar tudo abre uma prévia de quem começa, espera e não entra, com liberar em Review ou Feito (SPEC-064 R1–R3, R7) (83012db)
- **board:** Enquanto Executar tudo roda, cards dizem quem esperam, a barra resume e os avisos dizem quando a espera acaba (SPEC-064 R4–R6) (d46299f)
- **specs:** Três sugestões do Claude por pergunta e Outras sugestões com Ctrl+R (SPEC-061) (87f7fb8)
- **specs:** Teclas na revisão das respostas e em O que muda na spec, e Ctrl+Esc para fechar (SPEC-060) (f1d7e68)
- **specs:** Planejar de novo fica na barra e Planejada na lista e no cabeçalho (SPEC-062) (40013e5)
- **specs:** Variações de depende-de valem e viram depende-de ao salvar (SPEC-063 R1, R2) (5a4bb99)
- **specs:** Avisos de dependência e de chave desconhecida, e /spec e Transformar em spec com depende-de (SPEC-063 R3–R5) (f4b8a22)
- **board:** Uma cor por estado na barra do card e pulso na etapa ativa (SPEC-065) (f6ce57f)
- **sobre:** A logo segue viva no ritmo calmo, agita com o mouse e toca a abertura de novo com clique, Enter ou Espaço (SPEC-066 R2-R9) (b2b3b53)
- **sobre:** A coluna da direita entra em cascata em até 640 ms, com o foco já na ação do cartão (SPEC-066 R1, R8) (ecef77b)
- **sobre:** O líquido do frasco acompanha o download da atualização e borbulha ao terminar (SPEC-066 R10) (f968048)
- **prototipo:** Uma carta por tela, com a versão mostrada e o botão "D · 4" quando há mais de uma (SPEC-067 R1, R2, R6, R7) (62141a3)
- **prototipo:** A letra abre as versões daquela tela, onde clique ou ↑/↓ trocam a carta na hora, e a variação nova chega mostrada e marcada como "nova" (SPEC-067 R3, R4, R5, R8) (3d7d11e)
- **prompt:** Uma resposta com várias specs vira uma lista de revisão que cria todas com os números e o depende-de certos (SPEC-068 R1, R3-R6, R9) (de5110b)
- **prompt:** Dividir em specs no menu da conversa e no Plano pronto pede ao Claude as specs e abre a lista de revisão (SPEC-068 R2) (b2f923a)
- **board:** A Bandeja do Quadro guarda as specs novas e as aprovadas até você levá-las para o Backlog, com Desfazer (SPEC-068 R7-R9) (8168eb9)
- **dev:** O projeto declara o servidor de desenvolvimento em dev: e o app o sobe no worktree num grupo próprio, confere a porta e guarda o registro de cada servidor (SPEC-051 R1, R3, R5) (4b72517)
- **sessoes:** O cabeçalho da sessão de spec controla o servidor de desenvolvimento e a aba Preview mostra o estado, os logs e manda o erro para a sessão (SPEC-051 R2-R5) (7ca3789)
- **dev:** Abrir preview abre um Chromium do app com perfil próprio e Apontar captura pelo CDP o elemento clicado na página, com seletor, HTML, estilos e prints (SPEC-051 R6, R7, R9, R10) (b09c23b)
- **sessoes:** O elemento apontado vira anexo no composer, com miniatura, seletor, HTML e estilos, e vai no pedido com os prints; o preview recarrega sozinho quando o servidor não tem recarga a quente (SPEC-051 R8, R11) (b1be49f)
- **mcp:** O app serve um MCP local em 127.0.0.1 e cada sessão ou conversa recebe o promptorium por --mcp-config, com token próprio revogado no fim (SPEC-052 R1, R2, R8) (3f52cd4)
- **mcp:** As ferramentas listar_specs, ler_spec, estado_do_quadro, spec_atual, criar_spec e criar_filhas, com a origem no frontmatter e o limite por execução (SPEC-052 R3-R6, R9) (d225de7)
- **sessions:** O cartão de aprovação de criar_spec e criar_filhas mostra a prévia com título, requisitos, critérios, avisos do lint e arquivo, e só permite sempre nesta sessão (SPEC-052 R4) (9e088f4)
- **board:** Anotar_andamento grava a nota em spec_notes, o card do Quadro mostra a mais recente e o painel guarda o histórico; Specs ganha o selo Criada pelo agente, a sessão e as filhas (SPEC-052 R6, R7) (ba7cd1e)
- **settings:** Execução de specs ganha o Servidor MCP do Promptorium, com liga e desliga, estado, ferramentas e limite; Ferramentas mostra o servidor em Da sessão (SPEC-052 R9, R10) (23453d3)
- **review:** Trazer PR busca a cabeça do PR, cria o worktree na branch dele e abre a sessão com o contexto e as regras do PR alheio (SPEC-050 R1, R3, R4, R7, R10) (1b65670)
- **review:** O PR trazido entra na fila com Sem spec, guarda os comentários por sessão (migração v25 provisória) e tem Pronto para merge sem spec e revisor sob demanda (SPEC-050 R5, R6) (b8332d5)
- **review:** Trazer PR… no topo da fila abre o diálogo com os PRs abertos e como começar, e o Grafo oferece Trazer para o app (SPEC-050 R1, R2, R4, R10) (b7db493)
- **review:** O PR trazido só recebe push com permissão, oferece Copiar patch, Atualizar com os commits do autor, Responder no PR e Soltar o PR (SPEC-050 R7, R8, R9) (f320aca)
- **specs:** A VIBE é uma spec mínima em docs/vibe, com série VIBE- própria, número reservado no banco e renumeração no merge (SPEC-069 R3, R12) (6c5fbe3)
- **prompt:** Fazer como tarefa abre uma VIBE num worktree próprio, com o aviso Use com cuidado, a barra da conversa e Enviar para Review (SPEC-069 R1, R2, R4, R7, R13) (5c2cc30)
- **prompt:** A VIBE mede o tamanho, para no teto com Virar spec ou Continuar, pergunta quando o pedido é outro assunto e leva os prints de tela ao Review (SPEC-069 R5, R6, R8) (ea46539)
- **board:** A VIBE entra no Quadro com a marca roxa, fica fora do Executar tudo e do Autopilot, ganha Descartar VIBE e o selo de parada (SPEC-069 R9, R10, R11) (ea94016)

### Correções

- **board:** Executar em Automático igual ao mockup (SPEC-035) (ab39516)
- **settings:** Histórico e Executar iguais ao mockup (SPEC-035) (b2a152c)
- **update:** Consulta que falha não parece mais versão mais recente (SPEC-038 R10) (4cc6216)
- **update:** Cancelar o download apaga o arquivo parcial e os links abrem no Windows (SPEC-038 R8) (2c8a955)
- **tray:** Sublinhado do rótulo não vira atalho no menu (SPEC-041) (0732551)
- **board:** Filtros têm prioridade no cabeçalho com o seletor de sprint (SPEC-042 T2) (ba8ca63)
- **sprints:** Singular na contagem de specs do seletor (SPEC-042 T4) (6350be3)
- **ui:** Desfoque do diálogo sem ProviderScope e teste de contraste com o token sólido (SPEC-049) (479d3f4)
- **ui:** Rótulo da pasta de specs com contraste AA sobre a luz âmbar do fundo (SPEC-049) (cf5eea1)
- **sessoes:** Os botões do cabeçalho da sessão ficam do tamanho do texto, a aba Preview deixa pelo menos 150 px para o log e só pinta de vermelho as linhas de erro (SPEC-051 R2, R4) (6cc2854)
- **mcp:** Apaga o arquivo da execução antes de revogar o token, para quem espera o fim não ver o arquivo ainda lá (SPEC-052 R2) (b8af1ec)
- **sessions:** A prévia de criar_spec junta os avisos repetidos do lint, com a contagem (SPEC-052 R4) (ff397ec)
- **specs:** O selo Criada pelo agente vai para a linha das etapas na lista e para a linha do caminho no cabeçalho, e a nota do card mostra a idade numa linha própria (SPEC-052 R6, R7) (d495a69)
- **specs:** A faixa da origem só diz onde a spec nasceu depois de achar a sessão; telas do app (SPEC-052 R4, R6, R7) (2c14329)
- **mcp:** O promptorium em Da sessão abre um painel próprio, só de leitura, e não é a seleção inicial (SPEC-052 R10) (838d840)
- **review:** Comentários do PR com o gh 2.45, sem --slurp, uma linha por comentário (SPEC-050 R6) (b7ca288)
- **review:** O painel do PR trazido não estica os botões, e a conta dos commits do autor busca no máximo uma vez por minuto, sem gravar o FETCH_HEAD (SPEC-050 R7) (685e559)

### Desempenho

- **ui:** Animações de ambiente a 24 quadros/s, Executar salva o Plano e ações discretas da pasta de specs (SPEC-049) (842c4de)

### Documentação

- **spec:** SPEC-033 decidir a etapa que precisa de você pelo modal do balão (06ee3fe)
- **spec:** SPEC-033 decisões P1, P3, P4 e P5; P2 com a sugestão do desenvolvimento guiado por spec (d761101)
- **spec:** SPEC-034 motion e fluidez, com canvas interativo e validação (da09ffa)
- **spec:** SPEC-034 canvas aprovado, troca de seção em 640 ms (c0bd200)
- **spec:** SPEC-034 P1 decidida: T3 troca todos os diálogos (d696afb)
- **spec:** SPEC-036 pasta de specs e palco no Canvas do Quadro (56d1258)
- **spec:** SPEC-036 P1, P2 e P3 decididas: Foco como terceira visão, linha de dependências e painel de detalhes (a225d1f)
- **spec:** SPEC-035 orquestrador de modelos por etapa (100e391)
- **spec:** SPEC-035 P1 e P2 decididas: revisão pelo auto_reviewer, Codex fora por enquanto (d5a3654)
- **spec:** SPEC-033 P2 decidida: Dividir cria subetapas R3.1/R3.2 na fila, sem mudar o requisito (fd393b5)
- **spec:** SPEC-035 critérios e status (SPEC-035) (198eb4e)
- **mockups:** Telas da SPEC-035 (canvas e PNGs) (b621b64)
- Guia da visão Foco, decisões e capturas da SPEC-036 (3888ee3)
- **spec:** SPEC-037 Planejar, refino e plano automáticos, com mockups (949d732)
- Guia de Planejar e decisões da SPEC-037 (10aa816)
- **specs:** SPEC-038 tela Sobre, com mockups validados (9d539c8)
- Guia do Sobre e decisões da SPEC-038 (4ffa257)
- SPEC-039, nova spec com mini planejamento (#88) (f66b905)
- Guia de Nova spec e decisões da SPEC-039 (09fc9e3)
- SPEC-041, radar na bandeja, mockups e sondagem (ebab864)
- SPEC-042, sprints no Quadro e mockups (4f5091d)
- SPEC-046, atividade do repositório (8b06a3f)
- SPEC-046, quem fez os commits (SPEC-048) (2e80865)
- SPEC-045, grafo do repositório (0b2ebd6)
- SPEC-045, etiqueta do modelo no lugar do autor agente (e7ee241)
- SPEC-044, releases na tela Repositório (a4dc916)
- Canvas do Repositório com a SPEC-048 (caa9786)
- Guia do Repositório e SPEC-044 aprovada (6def7ae)
- Guia do Grafo e SPEC-045 aprovada (876caae)
- SPEC-048, marcar commits feitos por agentes (fa6a064)
- Guia da marcação de commits e decisões da SPEC-048 (526b46e)
- Guia da Atividade, SPEC-046 aprovada e R9 da SPEC-045 ligada (ef5bc0a)
- SPEC-047, higiene do repositório (711b285)
- Guia da aba Higiene e decisões da SPEC-047 (9a07f70)
- SPEC-043, conflito resolvido pelo agente, conferido pelo gate (edc6463)
- SPEC-043, decisões e mockups (3291362)
- SPEC-043, referência à issue #99 (3b8a756)
- Guia do Review e decisões da SPEC-043 (0cf4322)
- SPEC-051, preview com apontar e pedir (#126) (044990a)
- SPEC-049, tema Vidro (278050d)
- SPEC-049, referência à issue #118 (119df63)
- Capturas do app com o tema Vidro (SPEC-049) (e71507c)
- Requisito mínimo, Aparência, medição de desempenho e decisões da SPEC-049 (1bd9d41)
- SPEC-054, card que precisa de você treme de tempos em tempos (spec e mockups) (01643c3)
- SPEC-054 ligada à issue #134 (9667612)
- Capturas antes e depois do layout da pasta de specs e do Salvar (SPEC-049) (311f7ac)
- SPEC-053, Nova spec animado e barra do Quadro em três zonas (647cd8b)
- Mockups da SPEC-053 (canvas, capturas e fontes .dc.html) (82d59d4)
- SPEC-053 ligada à issue #132 (97b4375)
- **spec:** SPEC-055 Prompt em destaque — spec e mockups (83aac5a)
- **spec:** SPEC-055 aponta a issue #141 (ec42930)
- **spec:** SPEC-055 plano em três tarefas e critérios de aceite (c3d5b77)
- **spec:** SPEC-055 capturas da barra lateral (t1) (c829492)
- **mockups:** SPEC-056 telas de organizar conversas do Prompt (7d9e55f)
- **spec:** SPEC-056 organizar as conversas do Prompt (cd9b65f)
- **spec:** SPEC-056 aponta a issue #143 (cf871d2)
- **spec:** SPEC-056 telas do app de arquivar (t1) (129e764)
- **spec:** SPEC-056 telas do app de renomear (t2) (9c84046)
- **spec:** SPEC-056 telas do app do painel recolhido (t3) (50367cf)
- **mockups:** SPEC-057 telas de importar arquivo no Conte a ideia (3addf57)
- **spec:** SPEC-057 importar arquivo no Conte a ideia (05756bb)
- **spec:** SPEC-057 aponta a issue #144 (594a89b)
- **mockups:** SPEC-058 telas do item da sessão ampliado (c7db4cf)
- **spec:** SPEC-058 item da sessão ampliado (47f6f9c)
- **spec:** SPEC-058 aponta a issue #145 (bf7001a)
- **spec:** SPEC-059 perguntas da spec no centro, com mockups (2ff7a6b)
- **spec:** SPEC-059 aponta a issue #146 (085e841)
- **spec:** SPEC-064 Executar tudo diz quem começa e quem espera, com mockups (a578253)
- **spec:** SPEC-064 aponta a issue #178 (e2bf6e1)
- **spec:** 064-executar-tudo aprovada (620ced4)
- **spec:** SPEC-061 três sugestões do Claude e Outras sugestões, com mockups (4071363)
- **spec:** SPEC-061 aponta a issue #170 (1b2cbce)
- **spec:** SPEC-061 aprovada (7d183c4)
- **spec:** SPEC-060 teclas na revisão das respostas e em O que muda na spec, com mockups (0e8cb8e)
- **spec:** SPEC-060 aponta a issue #167 (52d06b5)
- **spec:** SPEC-060 aprovada (3a6f8b9)
- **spec:** SPEC-062 Planejar de novo visível e Planejada na lista, com mockups (c0b533a)
- **spec:** SPEC-062 aponta a issue #173 (ae1dd12)
- **spec:** SPEC-062 aprovada (c7090d8)
- **spec:** SPEC-063 dependências que o app entende e avisa, com mockups (cad4683)
- **spec:** SPEC-063 aponta a issue #176 (f8a9168)
- **spec:** 063-dependencias aprovada (45d8963)
- **spec:** SPEC-065 a barra do card mostra o estado de cada etapa, com mockups (9963dcc)
- **spec:** SPEC-065 aponta a issue #184 (cc897a7)
- **spec:** SPEC-065 aprovada (9eb82b7)
- **spec:** SPEC-066 o Sobre com a logo viva, com mockups (886b5a5)
- **spec:** SPEC-066 aponta a issue #187 (934a77d)
- **spec:** SPEC-066 aprovada (479b96f)
- **spec:** SPEC-066 com os critérios de aceite cumpridos (58a9cfe)
- **spec:** SPEC-067 o protótipo mostra uma versão por tela, com mockups (56f565b)
- **spec:** SPEC-067 aponta a issue #192 (3a5c4a2)
- **spec:** SPEC-067 com os critérios de aceite cumpridos (2a566a1)
- **spec:** SPEC-068 várias specs de uma conversa e a Bandeja do Quadro, com mockups (b3351d0)
- **spec:** SPEC-068 aponta a issue #194 (e3fbcfa)
- **spec:** SPEC-068 t1 com as telas do app (f2ea77f)
- **spec:** SPEC-068 t2 com as telas do app (5635969)
- **spec:** SPEC-068 t3 com as telas do app (2cce700)
- **spec:** SPEC-068 com os critérios de aceite cumpridos (719a55f)
- **spec:** SPEC-051 com as telas do app (6c6fca1)
- **spec:** SPEC-051 com os critérios de aceite cumpridos (08575ee)
- SPEC-052, Promptorium como servidor MCP (#127) (98fea63)
- **spec:** SPEC-052 t5 com as telas do app (5e26b28)
- **spec:** SPEC-052 com os critérios de aceite cumpridos (1b84d5b)
- SPEC-050, trazer um PR qualquer para o app (#125) (317d306)
- SPEC-050, números fictícios nos mockups e link do PR (0bcb308)
- **spec:** SPEC-050 com os critérios de aceite cumpridos e as telas do app (ff6e87b)
- **spec:** SPEC-069 modo vibe code, com mockups (bb277b9)
- **spec:** SPEC-069 aponta a issue #196 (dacc010)
- **spec:** SPEC-069 com os critérios de aceite cumpridos (2a7bd58)

### Testes

- Prazo real nos testes com IO que estouravam com a suíte inteira (b5da378)
- Prazos reais nos testes que estouravam com a suíte inteira (ec80793)
- Painel de revisão não espera o prazo de 30 s sem o painel e rodadas de 4 ms (3da7717)
- SettleIo com condição usa voltas de 4 ms (sem condição mantém 20 ms) (67b3119)
- Memória do gate com comando de 1 s (limite de lentidão injetável no SpecRunner) (740aa88)
- Barra de sync espera a condição em voltas de 4 ms (4eceeae)
- Until dos testes de sessão consulta a cada 5 ms (o prazo continua 15 s) (2cc8848)
- SettleIo e barra de sync não adiantam o relógio falso mais que o real após as voltas iniciais (78294b6)
- Prazo real no drainUntil e aviso do SPEC-025 R9 sem depender da carga da máquina (SPEC-033 T5) (87a1cfe)
- Prazo real no salvar de project_config_test (SPEC-033 T5) (4f5f9d6)
- **splash:** O splash segue em loop no mesmo SplashStage do Sobre (SPEC-038 R2) (5f3d66a)
- **repo:** Mensagem do teste de desempenho do grafo (03acb13)
- **board:** Import desnecessário (3048c10)
- **ideas:** Esperar a leitura do arquivo terminar em vez de um tempo fixo (87a182f)
- **specs:** Contagem de avisos com a chave desconhecida do sample (SPEC-063 R4) (1bed63e)
- **review:** Pr_import_test sem import sobrando (SPEC-050) (f97f8b9)

### Build e CI

- CI só nos PRs e Criar Release com tag, release e pacotes (a135a91)

### Manutenção

- **hook:** Stop compara o conteúdo do código, não o commit (dc98ebf)
- Remove o hook de Stop que rodava analyze e testes a cada turno (f6efe6c)
- **repo:** Chaves no if da branch padrão (593f553)
- **perf:** Import desnecessário (db204ec)

## [0.8.0] - 2026-11-03

### Funcionalidades

- **specs:** Cabeçalho da spec com ações por estado, menu Mais ações e abas de modo (SPEC-024) (058194b)
- **specs:** Spec bloqueada durante ações, com faixa de status, cancelamento e aviso de falha (SPEC-025) (2480123)
- **prompt:** Diff das edições, painel Spec em refino, resumo do turno e diálogo de alterações do refino (SPEC-026) (20c0dfa)
- **prototipo:** Apagar telas pelo cartão, pela seleção e pela aba Versões, com confirmação, aviso da aprovada e Desfazer (SPEC-027) (b5750b3)
- **specs:** Responder as perguntas em aberto numa sessão guiada, com formato P<n>, aviso de formato, aprovar com as sugestões e diff antes de salvar (SPEC-028) (d353a10)
- **icone:** Marca sem o quadrado escuro na janela, na bandeja e no tema hicolor, de 16 a 512 px e em SVG, com volta ao ícone anterior (SPEC-029) (7e0c31d)
- **board:** Balão na etapa que espera você, pulso único de 1,8 s até resolver, motivo no card, selo com balão, pílula neutra e "Atenção · i de n" (SPEC-030) (c8989f3)
- **shell:** Marca do sistema no cabeçalho, desenhada em vetor e animada como a abertura enquanto specs executam, com tooltip da onda e clique para o Quadro (SPEC-031) (2a8b56a)
- **review:** SPEC-032 R1-R5, R8, R10, R14 fila em pilha, estado em texto, uma ação primária e merge que segue para a próxima spec (553b99e)
- **review:** SPEC-032 R6, R7, R15 refaz a base das filhas depois do merge da mãe (34f1fc2)
- **review:** SPEC-032 R9, R11-R13 barra do worktree, aviso da raiz e Mergear a pilha (9bf8d78)
- **review:** SPEC-032 R17 resolver conflito com o agente ou eu mesmo, no editor (f3bbc16)
- **review:** SPEC-032 R16 grafo das ramificações do merge (7b38502)

### Documentação

- **specs:** SPEC-024 ações da spec mais claras, com mockups validados (79b9e73)
- **specs:** SPEC-025 spec bloqueada durante ações, com mockups validados (30c5d97)
- **specs:** SPEC-026 ver o que o refino gerou, com mockups validados (1edaf0b)
- **specs:** SPEC-027 apagar telas do protótipo, com mockups validados (72190c1)
- **specs:** SPEC-028 responder as perguntas em aberto, com mockups validados (9d1d9a0)
- **specs:** SPEC-029 ícone visível nas barras do Linux, com comparação do ícone atual e do esboço sem fundo (3d7cc71)
- **specs:** SPEC-030 precisa de você no card, com mockups validados e decisões do grill (7adb0da)
- **specs:** SPEC-031 marca do sistema no cabeçalho, animada enquanto as ondas executam, com mockups e decisões (d5c266c)
- **specs:** SPEC-031 animação da marca segue a de abertura (onda, bolhas até o gargalo, molécula) (101d96f)
- **specs:** SPEC-032 fila de Review em pilha, com merge de baixo para cima, rebase das filhas, aviso da raiz e mockups validados (d16002d)
- **specs:** SPEC-032 refaz a base das filhas quando a mãe é mergeada fora do app (R15) (07bd352)
- **specs:** SPEC-032 grafo das ramificações do merge (R16), resolver conflito com o agente ou no editor (R17) e fila com várias specs no mockup (c25776f)

### Testes

- **prototipo:** Espera a miniatura de 1100×700 em vez de um settle fixo (3a5f862)
- **specs:** Critérios de aceite do cabeçalho da spec (SPEC-024) (cf1d65d)
- **specs:** Critérios de aceite da spec bloqueada durante ações (SPEC-025) (9e6f07a)
- **prompt:** Critérios de aceite do que o refino gerou (SPEC-026) (ec0fea6)
- **prototipo:** Critérios de aceite de apagar telas do protótipo (SPEC-027) (e31645b)
- **specs:** Critérios de aceite de responder as perguntas em aberto (SPEC-028) (4cd6406)
- **icone:** Critérios de aceite da marca, da bandeja e da instalação dos ícones (SPEC-029) (bd3b7b1)
- **board:** Espera o diálogo de sem-design em vez de um tempo fixo (f8f06ca)
- **board:** Critérios de aceite do card que precisa de você (SPEC-030) (ed69626)
- **shell:** Critérios de aceite da marca no cabeçalho (SPEC-031) (2cf3f53)
- **specs:** Espera mais pela verificação no spec_sync_bar_test, que estourava os 10 s com a suíte inteira rodando (2d73254)
- **review:** Espera o controle Marcar todos no spec_review_panel_test, que falhava com a suíte inteira rodando (fae4594)

### Manutenção

- Versão 0.8.0 e configuração do Claude Code no repositório (81cf85c)
- Hook de Stop do Claude Code (testes verdes) e o settings.local.json que o liga (94e1401)

## [0.7.0] - 2026-10-26

### Funcionalidades

- **SPEC-021:** Conversa de refino guarda o código da spec e a origem (Specs ou quadro) (R1) (3f1ef74)
- **SPEC-021:** Espera maior no until de answer_spec_bar_test (R1) (b1c7f5a)
- **SPEC-021:** Etapa verificada (origem do refino já gravada em 3f1ef74) (R1) (aa57ec4)
- **SPEC-021:** Watcher silencioso no teste de verificação do spec_sync_bar (R1) (5dddd8b)
- **SPEC-021:** Ação "Voltar à spec" na tela Prompt (R2, R4–R8, R11) (97c922c)
- **SPEC-021:** Card de origem rolado para a vista ao voltar ao quadro (R4, R10) (c5ba3de)
- **SPEC-021:** Alterações não salvas sobrevivem à troca de tela (R9, R3, R10) (29b23a8)
- **SPEC-019:** Filtro "Ocultar concluídas" por projeto no Quadro (R1–R6) (3bc7ec6)
- **SPEC-019:** Botão "Concluídas" na barra do Canvas e testes do filtro (R7) (d4a659f)
- **SPEC-019:** Finalizar e reabrir spec pelo frontmatter, na fila do sync (R8–R10) (78d2e21)
- **SPEC-019:** "Marcar como finalizada" e "Reabrir" no inspetor do Canvas (R8–R9) (09a109f)
- **SPEC-019:** Cabeçalho do Quadro cabe com o chip novo (rascunhos encolhem) (R5) (ed9b0a9)
- **SPEC-020:** TrayService e ícone na bandeja no Linux (R1–R8) (b276594)
- **SPEC-020:** Testes do TrayService (R7 R8) (6cdf61c)
- **SPEC-020:** Dependências da bandeja no .deb, CI e README (X11/Xi, sem AppIndicator) (R1) (54647b7)
- **SPEC-020:** Bandeja no Flatpak documentada (R7) (7fa9d33)
- **SPEC-023:** Contagem de testes no gate e "Aceitar a redução" (R1-R5) (04ca3aa)
- **SPEC-023:** Modelo com Fora do escopo e Perguntas em aberto, prompts de refino e de etapa (R11-R13) (39b3f05)
- **SPEC-023:** Perguntas antes de aprovar e avisos de estrutura no editor (R6-R10, R14) (5117c9a)
- **specs:** O zoom do editor também aumenta a visualização da spec (5721f2e)
- **SPEC-022:** Seção ## Protótipo na spec e tela aprovada no prompt da etapa (R9 R10) (b6d55ca)
- **SPEC-022:** Agente de telas com escrita restrita à pasta de mockups e variações (R2 R7) (8e68820)
- **SPEC-022:** Testes das miniaturas headless e do caso sem navegador (R4 R5) (b26fad3)
- **SPEC-022:** Modo Protótipo na tela Specs com canvas, painel e comparação (R1 R3 R6 R8 R11 R12) (abe11fe)

### Correções

- **gate:** Não roda os verificar: manual dos critérios (e497a22)

### Documentação

- **SPEC-021:** Critérios de aceite atendidos e status concluida (7a94e8d)
- **SPEC-019:** Spec de ocultar concluídas e finalizar spec, com decisões (c654898)
- **SPEC-019:** Critérios atendidos e spec concluída (b14ee63)
- **specs:** SPEC-020 ícone na bandeja do sistema (Linux) (d97035a)
- **SPEC-020:** Design e decisões; critérios automáticos marcados (72f4136)
- **specs:** SPEC-023 specs mais rigorosas (b4306f2)
- **SPEC-023:** Critérios atendidos, decisões e status aprovada (39926fe)
- **mockups:** Telas da SPEC-023 (8b63efe)
- **specs:** Corrige os avisos de estrutura das specs antigas (e02dbcb)
- **mockups:** Antes e depois do zoom na visualização da spec (a6c9481)
- **SPEC-022:** Spec do protótipo de telas com design e etapas (dd4a015)
- **SPEC-022:** Critérios marcados, status aprovada e mockups das telas (80b4894)
- **specs:** SPEC-022 marca a verificação manual do R6 (1506bc9)
- README enxuto e guia de uso por tela em docs/guia (463a1e0)
- **guia:** Modo Protótipo das specs (SPEC-022) (dc9d465)
- **guia:** Avisos de estrutura, perguntas ao aprovar e contagem de testes (SPEC-023) (84886f3)

### Testes

- **about:** Ancora "Novidades da" no início para não casar com o CHANGELOG (16e3f57)

### Build e CI

- Workflow Preparar release (versão no pubspec e CHANGELOG) e conferência na release (14a2d68)

## [0.6.0] - 2026-10-23

### Funcionalidades

- **review:** Marcar todos os critérios de aceite de uma vez (SPEC-014) (91fd57d)
- **specs:** Testes focados no prompt da etapa (SPEC-017 R1) (e43591a)
- **agents:** Desligar plugins e servidores MCP nas execuções do app (SPEC-017 R2) (78661fe)
- **specs:** Design com "O que já existe" e aviso ao executar sem ele (SPEC-017 R3) (7357828)
- **specs:** Continuar a próxima etapa na mesma sessão (SPEC-017 R4) (78dfd4d)
- **settings:** Seção Execução de specs (SPEC-017 R5) (1744903)
- **board:** Trava do gate, corrigir e verificar, etapa ao vivo (d12dbfd)

### Correções

- **review:** Descartar o "Desfazer" do lote ao trocar de item da fila (77b44a1)
- **specs:** Só ler o arquivo no Executar quando a spec pode precisar do aviso de Design (66ff10d)
- **sessions:** Retomar depois de suspender abre um processo novo (5668c45)
- Versão real no splash e atualização pelo pacote da cópia instalada (455d22a)

### Documentação

- Especificar o "marcar todos" dos critérios de aceite no Review (1eb6299)
- **specs:** Imagens dos mockups da SPEC-014 (ecd8ea0)
- Renumerar o "marcar todos" para SPEC-018 (19c97e8)
- Especificar a redução de tokens na execução de specs (SPEC-017) (9933004)
- **specs:** Mockups da SPEC-017 (3178835)
- **specs:** Decisões da SPEC-017 (35d63e8)
- **pesquisa:** Sonda de plugins e MCP desligados via --settings (SPEC-017 R2) (83f4299)
- **specs:** SPEC-017 e SPEC-018 concluídas (57e7a0c)

### Testes

- **review:** Esperar o painel refletir o banco nos testes do lote (791e279)
- Esperar condições em vez de tempo fixo nos testes instáveis (abb0ad6)
- Answer_spec_bar e run_extensions esperam até 15 s de tempo real (c0ff636)
- Spec_review_panel espera o painel até 15 s de tempo real (461558f)
- Specs_screen espera o arquivo até 15 s de tempo real (ad7a5eb)

### Build e CI

- Gerar o .deb só ao publicar uma release (8c90d60)

## [0.5.0] - 2026-10-22

### Funcionalidades

- **prompt:** Salvar a spec escrita pelo agente na resposta (SPEC-016) (e84368f)

### Documentação

- **specs:** Imagens dos mockups da SPEC-016 (a015ce4)

## [0.4.0] - 2026-10-22

### Funcionalidades

- **review:** Comentarios no diff, diff por rodada, prontidao e merge local guiado (6fe3375)
- **specs:** Descobrir specs da pasta configurada e verificar implementacao (e7c4c40)
- **board:** Canvas do Quadro no visual do mockup (384a74f)
- **board:** Fechar a SPEC-008 do canvas (083fe9d)
- **review:** Fechar a SPEC-010 do diff desde a rodada (5021770)
- **review:** Fechar a SPEC-014 de hospedagem e CLI (64f1ebe)
- **review:** Fechar a SPEC-009 dos comentarios no diff (810f03c)
- **review:** Fechar a SPEC-011 do painel pronto para merge (8cfd1ca)
- **specs:** Fechar a SPEC-015 com revisão do repositório no relatório e testes dos critérios (8bc971c)
- **review:** Fechar a SPEC-012 do merge local guiado (1a3feaf)
- **agents:** Desligar o Codex e focar no Claude Code (d251f38)

### Documentação

- Registrar specs do canvas do Quadro e das melhorias do Review (8ee088d)
- Definir a ordem de implementação das specs do Review e do canvas (2659eaa)
- **specs:** Ler specs de docs/specs e marcar a SPEC-001 como concluida (a1e3cc1)

## [0.3.0] - 2026-10-21

### Funcionalidades

- **db:** Persistir provedor e identidade externa das sessoes (070131b)
- **agents:** Integrar Codex App Server e politicas de permissao (17d96b7)
- **execucao:** Respeitar provedor em sessoes specs e acoes auxiliares (4553aa1)
- **ui:** Selecionar provedor padrao pelo rodape (fe04e13)

### Correções

- **footer:** Evitar sondagens de CLI ao consultar contadores (5fe72f2)

### Documentação

- Registrar specs de provedores e validacoes do Codex (9fa64a6)

### Build e CI

- **release:** Notas da release sempre geradas pelo git-cliff (8948daf)

## [0.2.1] - 2026-10-20

### Funcionalidades

- **SPEC-001:** Versão do app vem de PackageInfo (appVersionProvider) em vez de constante (R1) (276f106)
- **SPEC-001:** Testes cobrem falha do PackageInfo (0.0.0) e UpdatesCard sem erro (R2) (943ca6e)
- **SPEC-001:** Diálogo Sobre (F1, paleta e Configurações) com versão, repositório e changelog offline (R3) (65be29d)
- **SPEC-001:** Teste cobre F1 fechando o diálogo Sobre sem empilhar um segundo (R4) (1509b9b)
- **SPEC-001:** Teste cobre o changelog embutido com rede falhando e rolagem (R5) (3c05100)
- **SPEC-001:** AvailableUpdate lê notes/publishedAt/assets; diálogo Sobre mostra "Novidades da X.Y.Z" acima do changelog e habilita "Atualizar agora" (R6) (d262087)
- **SPEC-001:** Botão "Atualizar agora" só é renderizado quando há release mais nova (R7) (6944814)
- **SPEC-001:** Botão "Verificar agora" no diálogo Sobre chama check(force: true) e atualiza o diálogo com o resultado (R8) (34b1bf2)
- **SPEC-001:** "Atualizar agora" pede confirmação explícita (diálogo Atualizar/Cancelar) antes de qualquer download (R9) (fab397a)
- **SPEC-001:** Ao confirmar, escolhe o asset Linux (.deb/.tar.gz), baixa para diretório temporário novo e mostra o progresso (UpdateInstaller) (R10) (5a6d140)
- **SPEC-001:** Após o download, instala o pacote (.deb via pkexec apt install, .tar.gz sobre o diretório do executável), fecha o banco e reinicia o app (UpdateInstaller) (R11) (78a8571)
- **SPEC-001:** Falha no download/instalação mostra o erro no diálogo e oferece "Abrir página da release" (UpdateInstaller.openReleasePage) (R12) (6437b1a)
- **SPEC-001:** Download só por HTTPS em github.com, com nome de asset no padrão, tamanho e .sha256 conferidos; qualquer divergência aborta sem instalar (validateAsset) (R13) (37cbc93)
- **SPEC-001:** F1 com o terminal xterm focado abre o diálogo Sobre e não chega ao PTY; demais teclas de função seguem para o PTY (AppTerminalView.onKeyEvent) (R14) (751b4ee)
- **aprovacoes:** Perguntas do agente (AskUserQuestion) com opções para escolher (e78f6bf)
- **SPEC-001:** Quadro rola na vertical quando a altura é menor que o mínimo das colunas (R1) (823d358)
- **SPEC-001:** Teste garante rolagem vertical e horizontal do Grafo (o código já aninhava as duas rolagens) (R2) (85cecd2)
- **SPEC-001:** Teste garante que a roda do mouse sobre um cartão rola o Quadro (o código já repassa o gesto) (R3) (878e581)
- **SPEC-001:** Teste garante que uma coluna com muitos cartões rola sozinha, sem mover as outras (o código já usa um ListView por coluna) (R4) (6a4315a)
- **SPEC-001:** Teste garante que um Quadro que cabe na tela não tem barra de rolagem nem muda o layout (o código já devolve o Quadro direto) (R5) (561e10f)
- **SPEC-001:** Teste garante que arrastar um cartão muda a etapa mesmo com o Quadro rolando na vertical (o código já aceita o arraste) (R6) (064973d)
- **SPEC-001:** Barra de rolagem vertical sempre visível quando o Quadro rola na vertical (R7) (1af5bc7)

### Correções

- **projeto:** Preparar dos modelos pula enquanto o manifesto não existe (4b4bf16)
- **atalhos:** Clique fora de um campo não desliga mais os atalhos globais (2adbbf9)
- Splash mostrava v0.1.0; uma só constante de versão (AppInfo.version) (e9fe71f)
- **update:** Remove import de app_info que sobrou do merge da main (87dace2)

### Build e CI

- **release:** Gerar e anexar o .zip do Windows na release, como o Linux (6dc38e0)

## [0.2.0] - 2026-10-19

### Funcionalidades

- **projeto:** Configuração do projeto em .promptorium/config.yml (a4cf665)
- **prompt:** Anexar e arrastar arquivos para a conversa (168e6a8)
- **aprovacoes:** Pedidos de permissão em qualquer tela (e1b5def)
- **quadro:** Gate de verificação por etapa (F1) (672392c)
- **sessoes:** Hooks gerenciados pelo app via --settings (F2) (cdd870f)
- **quadro:** Checkpoint por etapa e estado durável (F3) (cc73922)
- **worktree:** Worktree pronto para rodar (F4) (e38aa7d)
- **review:** Revisor automático da spec (F5) (9a99e3d)
- **review:** Review completo (F6) (0e9ec43)
- **specs:** Spec em camadas (F7) (f7ef7a9)
- **projeto:** Memória do projeto (F8) (b921aa9)
- **quadro:** Quadro operável (F9) (89b570f)
- **shell:** Menus na ordem do trabalho e paleta Ctrl+K real (F10) (c687a64)
- **robustez:** Banco, disco e processos (F11) (f65a0cf)
- **seguranca:** Permissões e segredos (F12) (79b4ad9)
- **codigo:** IDE básica (F13) (75dc5fc)
- **projeto:** Métricas de qualidade por spec (F14) (bd9c185)
- **quadro:** Best-of-N por etapa (F15) (a1a0438)
- **review:** Babysit de PR, merge pelo gh e resolver conflito (F16) (7746f72)
- **quadro:** Agendamento do Autopilot (F17) (a5056ef)
- **plataforma:** Cliente ACP, Flatpak e aviso de versão nova (F18) (23a8f3e)
- **início:** Tela Para você, contadores na barra lateral e Ctrl+1…9 (UX v2, U1) (f80d122)
- **paleta:** Pendências, prefixos, recentes e folha de atalhos Ctrl+/ (UX v2, U2) (96702ae)
- **sessões:** Lado a lado, thinking recolhido, resumo do subagente e preview (UX v2, U3) (0719a81)
- **prompt:** Card Plano pronto e @/ no composer de Sessões (UX v2, U4) (e923613)
- **specs:** Painel de rastreabilidade por etapa (UX v2, U5) (e973b63)
- **projeto:** Aba Saúde e Analisar repositório (UX v2, U6) (fa864c3)
- **projeto:** Tela Começar com modelos e proposta completa do planner (UX v2, U7) (a3abb0e)
- **quadro:** Painel lateral, filtros, ondas, limite e barra segmentada (UX v2, U8) (87fee8e)
- **configurações:** Seções App e Workspace com busca, alterado e efeito (UX v2, U9) (6233037)

### Correções

- **checkpoint:** Início da etapa guarda arquivos não rastreados e fica preso a uma ref (96de1b1)
- **duelo:** Porta própria para A e B e merge abortado em conflito (17fcd54)
- **sessões:** Fork respeita F12, sem worktree órfão, hooks e modo skip (4b58623)
- **review:** Mergear PR fecha a sessão quando o gh só falha ao apagar a branch local (2a11db4)
- **início:** Plano pronto sem Aprovar, aprovações só do workspace e Retomar seguro (11b1550)
- **palette:** Recentes não repete item pendente nem rótulo ambíguo (8a6e822)
- **quadro:** ↑/↓ salva a ordem visível sem bagunçar cartões filtrados; filtro por workspace (98798b9)
- **sessões:** Lado a lado/Ctrl+\ seguem o que a tela mostra (4959f14)
- **specs:** Etapa selecionada guarda a spec junto (219075f)
- **configurações:** "alterado" compara valores, não a presença da chave (2902db6)
- **ux:** Ctrl+/ fecha a folha de atalhos; critério marcado no arquivo fica só leitura (4abde1c)
- **prompt:** Implementar como sessão só responde ao plano depois de criar a sessão (3de60fd)

### Documentação

- Atualizar CHANGELOG (34a4159)
- Análise comparativa com IDEs de IA e plano de melhorias (ed7bf13)
- Atualizar CHANGELOG, status do plano de melhorias e débito técnico (e6496b8)
- **ux:** Mockups v2 e plano de implementação (e0bd02e)
- CHANGELOG da 0.2.0 (cliff reconhece tags com ou sem v) (d69e10c)

### Testes

- **specs:** Espera o diálogo de design antes de aprovar (621f33c)

### Build e CI

- Workflow manual para gerar o build Windows (.zip como artefato) (d81c608)

### Manutenção

- Versão 0.2.0 (pubspec e appVersion) (818d0b7)
- Configuração do VS Code (CMake aponta para linux/) (3fbf764)

## [0.1.0] - 2026-10-16

### Funcionalidades

- Fase 1 — esqueleto do projeto Flutter, tema, fontes, janela e ícone (e8d3a9e)
- Fase 2 — shell da IDE, navegação, atalhos e splash animado (3cf8235)
- Fase 3 — banco local (drift), repositórios, seletor de workspace e preferências (a51b68b)
- Fase 4 — núcleo do Claude Code (stream-json, aprovações stdio), git/worktrees, diff e uso (4d32026)
- Fase 5 — tela de Sessões (timeline ao vivo, aprovações, notificações, retomar/fork, terminal, rodapé real) (bd27f33)
- Fase 6 — tela de Prompt (conversas livres, modos, @arquivos, /prompts salvos, provedores) (55ec98c)
- Fase 7 — tela de Agentes (frontmatter round-trip, global/projeto, orçamento e turnos na sessão) (08a4047)
- Fase 8 — editor com zoom/busca, Specs (planner com structured output) e kanban de Tarefas (c427c02)
- Fase 9 — tela de Review (diff, rejeitar hunk, comentários ao agente, PR e merge) (54e5a1f)
- Fase 10 — tela de Código (árvore do worktree, abas, marcas, aviso ao agente, terminal, Ctrl+P) (ea32785)
- Fase 11 — tela de MCP (servidores por escopo, status, regras por ferramenta, add/remove via CLI) (6b5df92)
- Fase 12 — verificação final, build release, instalação desktop e README (08f50ac)
- Seletor de pastas nativo ao adicionar workspace (062ae7c)
- Iniciar ou clonar repositório ao adicionar pasta sem git (aef8b8d)
- Tela Projeto — planejamento de projeto novo com o planner (f6bb92e)
- Tela Skills — instalar, criar e atualizar skills de catálogos no GitHub (4a33cbb)
- Roadmap do Projeto editável à mão (5006199)
- Ideias de "Depois" viram specs, geradas pelo planner ou vazias (7174989)
- Notificação da sessão leva para a tela de onde ela foi aberta (f8bccb6)
- Apagar projeto — pasta para a lixeira e dados do app removidos (af5f35d)
- Modo de sessão sem perguntar (--dangerously-skip-permissions), opcional (ddb5e02)
- Consumo — modelo, esforço e compactação por tipo de uso; rodapé só com o uso do plano (ae73e6f)
- Specs no quadro, fase 1 — dados (schema v8, etapas, dependências entre specs) (2220ec0)
- Specs no quadro, fase 2 — execução por etapas (SpecRunner) (e040242)
- Specs no quadro, fase 3 — Quadro com um cartão por spec (d4d5dab)
- Specs no quadro, fase 4 — tela Specs com etapas; remove Gerar tarefas (7ae6659)
- Specs no quadro, fase 5 — Review e merge por spec (616339f)
- Specs no quadro, fase 6 — roadmap do Projeto só com specs (4dfc787)
- Specs no quadro, fase 7 — limpeza (sem tarefas na interface) (7f244c1)
- **quadro:** Modo automático (Executar tudo/Parar) e merge de specs empilhadas (199f607)
- **specs:** Clonar para alterar, arquivar e excluir; edição travada após iniciar (6fd1357)
- **specs:** Subagentes por spec, com momento de execução e estado no cartão (cff8df0)
- **sessoes:** Indicador de atividade e suspensão por inatividade (04c5235)
- **rodape:** Uso do plano atualizado sem gastar tokens (a525a5b)
- **menu:** Review e Código acima de Agentes (a7094ad)
- **distribuicao:** Pacote .deb e .tar.gz, CI e release no GitHub Actions (586dacb)

### Correções

- **quadro:** Aviso "Ver sessão" some sozinho e leva à sessão (a3a12c8)

### Testes

- Specs no quadro, fase 8 — execução real de ponta a ponta (d6c7ef1)

### Build e CI

- Build e .deb só ao mergear na main; PR só analisa e testa (63883d1)

### Manutenção

- Git-cliff — configuração e CHANGELOG (4947774)


