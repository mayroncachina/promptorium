---
id: SPEC-002
status: rascunho
depende-de: []
---

# Integração Codex e contrato compartilhado de execução

> **Codex desligado em 22/10/2026** ([DT-56](../debito-tecnico.md#dt-56--integracao-codex)). Spec adiada: o foco é o Claude Code. A auditoria de requisitos e as pendências para religar estão no DT-56.

## Objetivo

Criar a base para executar Codex no Promptorium com streaming, ferramentas, aprovações e continuidade, preservando o comportamento atual do Claude e dos agentes ACP. Esta spec entrega o adaptador; a cobertura de produto depende das SPEC-003 a SPEC-005.

## Requisitos

- R1 · O sistema deve detectar separadamente executável, versão, autenticação e compatibilidade do Claude e do Codex, informando indisponibilidade e como corrigi-la. Ausência de um provedor não deve impedir abrir o app ou usar outro instalado.
- R2 · O sistema deve iniciar Codex pelo App Server e oferecer criação, envio de mensagens e imagens compatíveis, streaming, interrupção do turno, encerramento do processo, retomada e fork através de um contrato compartilhado. Erro de protocolo ou timeout deve encerrar a operação de forma identificável, sem perder o histórico já recebido.
- R3 · O sistema deve representar mensagens, ferramentas, alterações de arquivos, perguntas, aprovações, uso e conclusão de turno em eventos comuns, preservando identidade do provedor, thread, turno e item e distinguindo falha, cancelamento e sucesso. Eventos desconhecidos devem gerar diagnóstico sem derrubar a timeline.
- R4 · O sistema deve encaminhar pedidos de aprovação e perguntas ao usuário pela interface existente, responder à solicitação correta e remover pedidos resolvidos ou cancelados. Aprovar uma vez, aprovar no escopo suportado e negar devem conservar sua semântica, sem ampliar a autorização.
- R5 · O sistema deve manter a continuidade com o identificador externo devolvido pelo provedor, separado do UUID local; garantir um único escritor por conversa; e recuperar sessões após fechamento, falha ou troca para terminal sem duplicar mensagens, ferramentas ou resultados.
- R6 · O sistema deve executar cada processo no diretório e ambiente da sessão, aplicar timeout e encerramento de processos filhos e liberar recursos ao parar. Logs e eventos persistidos devem ocultar credenciais, mantendo informações suficientes para diagnosticar falhas.

## Design

### Contrato e adaptadores

Evoluir `AgentProvider`, `AgentRun` e `AgentStartOptions` em `lib/core/providers/` para atender conversas, sessões e execuções estruturadas. Expor capacidades por provedor e modelo: imagens, perguntas, fork, saída estruturada, modos de acesso e controles avançados. Não presumir que `enabled` significa instalado, autenticado e compatível.

Extrair os tipos compartilhados atualmente importados de `core/claude/` (eventos, anexos e opções) para uma camada neutra, com adaptação dos eventos Claude existentes e dos agentes ACP. O payload bruto pode ser guardado para diagnóstico com sanitização; a UI consome eventos normalizados. Histórico antigo deve continuar legível por leitor compatível, sem reescrever eventos em massa.

Implementar `CodexProvider` e um transporte testável em `lib/core/codex/` (nomes propostos). Usar processo por execução inicialmente, isolando diretório, configuração e ciclo de vida. Serializar operações por thread e correlacionar respostas por ID JSON-RPC, inclusive solicitações iniciadas pelo servidor. O contrato não deve confundir fim de turno com saída do processo.

### Protocolo

Validar o handshake `initialize`/`initialized`, operações `thread/start`, `thread/resume`, `thread/fork`, `turn/start` e interrupção na versão instalada. Guardar `thread.id` como identidade de retomada, sem inferi-lo de outro campo de sessão. Traduzir deltas e itens finais sem exibir o mesmo texto duas vezes. A base é a [documentação oficial do App Server](https://learn.chatgpt.com/docs/app-server); a sondagem deve registrar o contrato efetivamente usado.

Confirmar autenticação pelo mecanismo oficial do CLI e apresentar orientação quando faltar login. Não copiar tokens para o banco do Promptorium. Respostas tardias, IDs desconhecidos e mensagens parciais devem ser tratados explicitamente.

### Arquivos afetados

`lib/core/providers/{agent_provider,agent_registry,claude_code_provider,acp_provider}.dart`, nova camada Codex, tipos de timeline e gerenciadores que recebem eventos. A substituição das chamadas de negócio fica na SPEC-005.

## Critérios de aceite

- [ ] [R1] Com apenas Claude instalado, apenas Codex instalado ou nenhum instalado, o app abre e mostra diagnóstico independente; falta de login é diferenciada de executável ausente.
- [ ] [R2] Um servidor falso cobre handshake, texto fragmentado, imagem suportada, erro JSON-RPC, timeout, interrupção, retomada e fork; encerramento de turno mantém a conversa utilizável.
- [ ] [R3] Reproduzir fixtures Claude, ACP e Codex gera mensagens e ferramentas na ordem correta, sem duplicar deltas e itens finais; evento desconhecido e linha inválida não derrubam a UI.
- [ ] [R4] Duas sessões aguardando aprovação recebem respostas corretas; negar, cancelar e resolver externamente removem apenas o pedido correspondente; pergunta estruturada devolve as respostas selecionadas.
- [ ] [R5] Reiniciar o app retoma a thread original e preserva histórico; tentativa de dois escritores é impedida; fork recebe identidade externa própria e mantém vínculo com o pai.
- [ ] [R6] Parar durante comando ou timeout não deixa processos filhos; diretório e ambiente são os esperados; fixture com segredo não o expõe em logs persistidos.
- [ ] Testes de adaptadores e timeline passam, sem regressões nos testes existentes de Claude e ACP; `flutter analyze` não apresenta novos avisos.

## Perguntas em aberto

- Qual versão mínima do Codex suporta de forma estável o contrato necessário? Resolver com sondagem e registrar antes de habilitar o adaptador.
- Quais solicitações pendentes sobrevivem à retomada nessa versão? Só reconstruir pedidos cuja validade seja confirmada pelo servidor; os demais devem aparecer como interrompidos.
