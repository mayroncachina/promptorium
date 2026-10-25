---
id: SPEC-004
status: rascunho
depende-de: [SPEC-003]
---

# Paridade das opções de Claude Code e Codex

> **Codex desligado em 22/10/2026** ([DT-56](../debito-tecnico.md#dt-56--integracao-codex)). Spec adiada: o foco é o Claude Code. A auditoria de requisitos e as pendências para religar estão no DT-56.

## Objetivo

Oferecer com Codex todos os controles e recursos que o Promptorium disponibiliza com Claude. A equivalência deve ser de comportamento observável, incluindo restrições, e não apenas de nomes ou campos visíveis.

## Requisitos

- R1 · Cada opção Claude da matriz abaixo deve ter suporte Codex nativo ou equivalente comprovado. O sistema deve validar capacidades antes de iniciar, mostrar o valor efetivo e rejeitar configurações não suportadas. Uma lacuna explícita não satisfaz a conclusão da paridade.
- R2 · Modelo, esforço, compactação, orçamento e limite de turnos devem ser configuráveis por provedor e tipo de execução, com overrides por execução. Valores e modalidades Codex devem ser obtidos do catálogo disponível; ausência de custo ou limite do plano deve aparecer como dado indisponível, sem usar métricas Claude.
- R3 · Perguntar, Planejar, Editar, Refinar e os modos avançados de permissão devem preservar suas garantias em ambos os provedores. Restrições de ferramentas e acesso a arquivos devem ser aplicadas pelo runtime ou por isolamento verificável; instrução textual ao modelo não conta como bloqueio.
- R4 · Agentes, subagentes, instruções adicionais e skills devem poder ser selecionados e gerenciados no contexto do provedor, com escopos global/projeto, precedência e formato compatíveis. O sistema deve detectar referências incompatíveis e oferecer conversão explícita, sem gravar configuração Claude como se fosse Codex.
- R5 · MCP deve oferecer configuração, descoberta, diagnóstico e regras permitir/perguntar/bloquear por provedor. Bloqueios têm precedência, inclusive em retomadas, e uma configuração restrita não pode herdar servidores ou ferramentas extras silenciosamente.
- R6 · Configurações temporárias e hooks devem preservar as automações oferecidas pelo app sem alterar arquivos globais do usuário. Anexos, saída estruturada e detalhes de uso devem funcionar com validação de capacidade e formato; falha de schema não pode ser tratada como sucesso.

## Design

### Matriz obrigatória de cobertura

A origem é `ClaudeOptions`, `AgentStartOptions`, `RunPrefs` e funcionalidades das telas atuais. A coluna Codex descreve o comportamento exigido; não afirma suporte nativo onde ele ainda precisa de sondagem.

| Opção/recurso atual | Comportamento exigido no Codex | Evidência para concluir |
| --- | --- | --- |
| `sessionId`, `resumeId`, `forkSession` | UUID local separado da thread externa; criar, retomar e bifurcar | Histórico e vínculo preservados após reinício |
| `model`, `effort`, `inherit` | Catálogo Codex, esforços válidos por modelo e padrão do provedor | Catálogo paginado e validação de valores salvos |
| `autocompact` | Controle equivalente de compactação e valor efetivo visível | Sondagem de limiar, retomada e modelo; nenhum flag Claude reaproveitado |
| `maxBudgetUsd` | Limite monetário com fonte de custo confiável e sem promessa de teto que não possa cumprir | Caso atingindo limite e descrição de granularidade; lacuna se custo não estiver disponível |
| `maxTurns` | Limite equivalente de ciclos do agente, distinto das mensagens do usuário | Provar contagem e parada no limite, inclusive após retomar |
| `permissionMode`: default, acceptEdits, plan, auto, dontAsk, bypassPermissions | Perfis com garantias explícitas de aprovação, sandbox e rede | Testes de efeito real; mapear cada modo separadamente |
| `allowedTools`, `disallowedTools`, `tools` | Distinguir autoaprovação de restrição de disponibilidade; bloqueio vence permissão | Ferramenta bloqueada não executa nem por caminho alternativo |
| `appendSystemPrompt` | Instruções adicionais no canal adequado, sem sobrescrever instruções do projeto | Fixture com conteúdo e precedência esperados |
| `agent`, `agentsJson` | Perfil principal e subagentes com prompt, modelo, esforço, ferramentas e acesso preservados | Execução do perfil e apresentação de subagentes na timeline |
| `mcpConfigs`, `strictMcpConfig` | Servidores escolhidos e isolamento da configuração quando estrita | Servidor herdado fora da lista não fica acessível |
| Regras MCP permitir/perguntar/bloquear | Política equivalente por servidor/ferramenta e escopo | Negação, aprovação e persistência demonstradas |
| `settingsFile`, hooks gerenciados | Configuração por execução; eventos e efeitos das automações equivalentes | Configurações globais intactas e efeitos disparados uma única vez |
| `jsonSchema` | Resposta estruturada validada antes de consumir | JSON inválido, recusa e resposta incompleta geram falha recuperável |
| `includePartialMessages` | Streaming consolidado com itens finais | Texto e ferramentas sem duplicação |
| Texto, imagens e anexos | Envio suportado pelo modelo e resolução de arquivos no workspace correto | Multimodalidade suportada e rejeição antecipada quando incompatível |
| Tokens, cache, contexto, custo e limites do plano | Métricas separadas por provedor e unidades corretas | Campo ausente não vira zero; sem somar acumulados duas vezes |
| Tipos sessão/conversa/planner, ociosidade e limite de etapas por sessão | Preferências independentes onde forem do provedor; política comum onde for do app | Valores conservados em reabertura, etapas e expiração por ociosidade |
| Skills e escopos global/projeto | Descoberta, criação, edição, uso e instalação no formato do provedor | Skill selecionada realmente carregada; precedência comprovada |

Antes de implementar cada linha, registrar mecanismo, versão, teste e eventuais diferenças em `docs/pesquisa/`. Acrescentar à matriz qualquer opção encontrada na UI ou nos serviços que não esteja listada. A revisão final precisa conferir controles visíveis e opções internas, inclusive as usadas pelo planner e review.

### Permissões e somente leitura

Manter acesso e aprovação como eixos distintos. “Não perguntar” não significa conceder acesso irrestrito; “permitir ferramenta” não significa limitar o conjunto de ferramentas. Não traduzir os seis valores de `ClaudePermissionMode` por uma tabela baseada somente no nome. Exibir descrições de efeito do perfil Codex e bloquear conversões que enfraqueçam garantias.

Perguntar e planners não podem gravar no workspace por comandos, patches ou MCP. Planejar não pode implementar o plano. Refinar pode ler e exige aprovação para alterações e comandos conforme o contrato atual. Editar respeita o diretório autorizado e as demais políticas. Acesso irrestrito requer escolha explícita por execução, conforme a opção atual do produto; não pode ser herdado de modo mais restrito.

### Modelos, limites e métricas

A [documentação oficial do App Server](https://learn.chatgpt.com/docs/app-server) orienta consultar `model/list` para modelos, esforços e modalidades disponíveis. Separar métricas de uso do agente de preços estimados e de cotas da conta. Não fixar IDs GPT ou esforços Claude como catálogo Codex. Um limite imposto pelo app só pode ser descrito como equivalente se sua granularidade permitir a garantia anunciada; interromper ao fim de um turno não comprova um teto rígido durante esse turno.

### Componentes

Generalizar `core/claude/run_prefs.dart`, os seletores de sessão/Quadro, `settings_sections.dart`, telas de agentes, skills e MCP e as regras persistidas. Manter adaptadores específicos para configuração Claude e Codex, sem editar `~/.claude` ou configurações globais Codex para simular isolamento. O painel de capacidades deve explicar lacunas durante o desenvolvimento, mas a entrega completa exige resolver todas as linhas obrigatórias.

## Critérios de aceite

- [ ] [R1] Matriz revisada contra opções e telas atuais; toda linha tem mecanismo, versão e evidência; nenhuma opção é descartada silenciosamente. Lacunas mantêm esta spec incompleta. verificar: manual (matriz revisada com mecanismo, versão e evidência por linha)
- [ ] [R2] Modelo/esforço inválido é recusado; defaults e overrides são preservados; limites são exercitados; métricas ausentes aparecem como indisponíveis e métricas acumuladas não duplicam custo. verificar: manual (modelo e esforço inválidos recusados, limites e métricas por provedor)
- [ ] [R3] Testes de cada modo tentam escrita por patch, comando e MCP, além de acesso fora da raiz; somente as ações autorizadas ocorrem. Cada modo avançado tem cenário próprio. verificar: manual (cada modo tenta patch, comando, MCP e acesso fora da raiz)
- [ ] [R4] Agente e skill de cada provedor são criados, editados e usados com precedência de projeto; referência incompatível não é enviada como argumento válido; subagentes conservam identidade na timeline. verificar: manual (agente e skill por provedor criados, editados e usados)
- [ ] [R5] Descobrir MCP e aplicar as três regras funciona em ambos os provedores; regras conflitantes mantêm o bloqueio e configuração estrita impede herança extra, inclusive após retomar. verificar: manual (descoberta e regras MCP em ambos os provedores, inclusive após retomar)
- [ ] [R6] Hooks/configurações temporárias não alteram arquivos globais; anexos compatíveis são recebidos; saída fora do schema falha sem atualizar indevidamente o estado do produto. verificar: manual (hooks sem alterar arquivos globais, anexos e saída fora do schema)
- [ ] [R1] [R2] [R3] [R4] [R5] [R6] Testes de políticas, preferências, MCP e métricas passam para ambos os provedores; `flutter analyze` não apresenta novos avisos. verificar: flutter analyze && flutter test

## Perguntas em aberto

- Nenhuma pergunta exige resposta do usuário para iniciar a implementação. A exigência de produto é oferecer todas as opções atuais do Claude também com Codex.

## Investigação técnica obrigatória

Cabe a quem implementar verificar, na documentação oficial e por sondagens da versão instalada, o suporte a cada linha da matriz, especialmente orçamento, turnos internos, compactação, agentes e hooks. Essa investigação faz parte do trabalho de implementação e não depende de o usuário conhecer as APIs do Codex.

Para cada opção, registrar em `docs/pesquisa/` a versão avaliada, o mecanismo disponível, o cenário executado e o resultado. Quando não houver suporte nativo, investigar e implementar um equivalente no Promptorium que preserve a garantia descrita na matriz.

Se uma opção não puder ser atendida nem pelo Codex nem por um equivalente verificável no app, registrar a limitação comprovada, o impacto no uso e as alternativas concretas. Continuar as partes independentes e apresentar ao usuário somente a decisão de produto necessária, com recomendação e consequências. Não pedir que ele descubra a capacidade técnica, não reduzir o escopo silenciosamente e não considerar a paridade concluída enquanto houver lacunas obrigatórias.
