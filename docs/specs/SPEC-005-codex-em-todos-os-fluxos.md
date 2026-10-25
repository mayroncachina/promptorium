---
id: SPEC-005
status: rascunho
depende-de: [SPEC-004]
---

# Codex em todos os fluxos do Promptorium

> **Codex desligado em 22/10/2026** ([DT-56](../debito-tecnico.md#dt-56--integracao-codex)). Spec adiada: o foco é o Claude Code. A auditoria de requisitos e as pendências para religar estão no DT-56.

## Objetivo

Completar a seleção entre Claude Code e Codex em todos os recursos que usam IA, mantendo worktrees, gates, recuperação e revisão humana. O usuário deve conseguir realizar o fluxo de projeto até review e merge usando exclusivamente Codex quando essa for sua escolha.

## Requisitos

- R1 · Sessões dos dois provedores devem oferecer criar, enviar, anexar, acompanhar ferramentas e subagentes, aprovar, parar, retomar, bifurcar e abrir no terminal embutido, com os mesmos dados de contexto, worktree e configuração efetiva. O terminal e a execução gerenciada não podem escrever simultaneamente na mesma conversa.
- R2 · Prompt deve oferecer Perguntar, Planejar e Editar com ambos os provedores, preservar histórico e anexos e permitir transformar plano ou conversa em sessão com provedor e contexto explícitos. Refinar specs deve respeitar o provedor selecionado e as aprovações esperadas.
- R3 · Projeto, geração de specs e tarefas/etapas, geração de design e criação de skills devem usar o provedor resolvido e respostas estruturadas validadas. Nenhum serviço pode continuar chamando Claude diretamente quando Codex tiver sido escolhido.
- R4 · Executar uma spec pelo Quadro ou pela tela Specs deve conservar provedor, agente, opções e worktree entre etapas, lotes de etapas, retomadas, correções automáticas e gates. Duelos devem registrar o provedor de cada tentativa e permitir escolher Claude ou Codex em cada lado sem confundir resultados.
- R5 · Review automático, comentários e ciclos de correção devem usar o provedor explicitamente configurado para a revisão, herdando o da execução quando não houver override. Gates e automações devem produzir os mesmos efeitos de produto para ambos os provedores; concluir um turno não pode pular verificação ou aprovação humana.
- R6 · Recuperação, notificações, métricas, cancelamentos e limpeza de recursos devem funcionar com sessões Claude e Codex simultâneas. Falha, ausência de credenciais, limite da conta ou opção incompatível de um provedor não pode derrubar nem redirecionar execuções do outro.

## Design

### Substituição das chamadas diretas

Migrar `SessionManager` de `ClaudeProcess` para o contrato compartilhado e criar um executor estruturado independente de provedor no lugar do uso obrigatório de `runReadOnlyClaude`. Reutilizar os adaptadores Claude e Codex; regras de negócio de etapas, git, gates e review permanecem nos serviços do produto.

Auditar pelo menos:

| Área | Componentes atuais a adaptar | Verificação do comportamento |
| --- | --- | --- |
| Sessões | `session_manager.dart`, `new_session_dialog.dart`, terminal, composer e timeline | Ciclo de vida completo e exclusão de escritores |
| Prompt | `conversation_manager.dart`, seletores, anexos e ações do plano | Modos e conversão para sessão |
| Projeto | `project_planner.dart` e geração de specs/etapas | Leitura e saída estruturada |
| Specs | `spec_design.dart` e refinamento no Prompt | Design/refinamento com provedor identificado |
| Skills | `skill_writer.dart`, repositório e catálogo | Formato e destino correspondentes ao provedor |
| Quadro | `spec_runner.dart`, diálogo de execução, estado durável e duelos | Provedor persistido por tentativa e por execução |
| Review | `auto_reviewer.dart`, comentários e correções | Revisor identificado, política de leitura e gates |
| Plataforma | Hooks gerenciados, automações, consumo, splash e limpeza | Ausência de dependência obrigatória do Claude |

A auditoria deve localizar também novos usos de `ClaudeOptions`, `ClaudeProcess`, `claudeExecutableProvider` e `runReadOnlyClaude`. Usos dentro do adaptador Claude, seu diagnóstico e sua configuração são legítimos; serviços de produto devem resolver o provedor antes de executar. Não substituir chamadas por um executor genérico que internamente continua fixo em Claude.

### Estado e continuidade

Cada execução de spec guarda um snapshot do provedor e opções; novas sessões das próximas etapas usam esse snapshot. Preservar a regra de um worktree por spec e a distinção entre status editorial e estágio no Quadro. O marcador de conclusão de etapa, commits esperados, testes e política de revisão continuam sendo verificados pelo app.

Revisão pode ter override de provedor, armazenado e exibido separadamente do executor. A correção é enviada ao executor original da tentativa. No duelo, cada tentativa mantém identidade, branch, worktree, custos e histórico próprios; não misturar contexto ou métricas dos lados.

### Terminal e automações

Validar o comando oficial de retomada interativa do Codex na versão adotada antes de montar o PTY. Transferir posse da conversa somente depois de encerrar o escritor anterior e sincronizar o estado ao retornar. Opções que não possam ser preservadas no terminal devem ser resolvidas antes de habilitar essa ação como paridade completa.

Automações hoje implementadas com hooks Claude devem ter equivalente Codex comprovado ou ser executadas pelo app no mesmo ponto semântico. Gate de testes, commit e revisão não pode depender exclusivamente de um evento específico do Claude. Não duplicar automações quando o runtime e o app notificarem o mesmo evento.

## Critérios de aceite

- [ ] [R1] Com Codex, executar uma sessão com alteração real em worktree, aprovação, imagem compatível, parada, reinício do app, retomada, fork e ida/volta do terminal; não há dois escritores nem perda de histórico. verificar: manual (sessão Codex completa com worktree, aprovação, retomada, fork e terminal)
- [ ] [R2] Exercitar os três modos do Prompt, anexos, refinamento com aprovação e continuação como sessão para Claude e Codex, verificando provedor e contexto recebidos. verificar: manual (três modos do Prompt, anexos e refinamento com Claude e Codex)
- [ ] [R3] Com o executável Claude indisponível e Codex autenticado, planejar projeto, gerar specs/etapas, gerar design e criar uma skill funciona; resposta estruturada inválida não cria dados parciais tratados como válidos. verificar: manual (projeto, specs, design e skill com Codex e sem Claude)
- [ ] [R4] Executar spec em múltiplas etapas com reinício entre elas conserva configuração/worktree e respeita gates; duelo Claude/Codex mostra tentativas separadas e permite escolher o resultado sem cruzar branches. verificar: manual (spec em várias etapas com reinício e duelo Claude e Codex)
- [ ] [R5] Review com herança e com override identifica o revisor; reprovação volta ao executor correto; falha de testes mantém a etapa pendente de correção; merge continua sujeito ao fluxo humano existente. verificar: manual (review com herança e override, reprovação volta ao executor certo)
- [ ] [R6] Executar Claude e Codex simultaneamente, provocar falha em um e parar o outro; recuperação, fila de aprovações, notificações e métricas mantêm identidades e não deixam processos órfãos. verificar: manual (Claude e Codex simultâneos, falha em um e parada no outro)
- [ ] [R1] [R2] [R3] [R4] [R5] [R6] Testes com processos falsos cobrem os fluxos acima e a regressão Claude/ACP. Sondagens reais autorizadas registram versões e resultados, sem depender de contas externas para a suíte comum. verificar: manual (processos falsos cobrem os fluxos e sondagens reais registradas)
- [ ] [R1] [R2] [R3] [R4] [R5] [R6] `flutter test` e `flutter analyze` passam; conferência manual do fluxo completo com cada provedor é registrada antes de encerrar a entrega. verificar: flutter analyze && flutter test

## Perguntas em aberto

- Nenhuma escolha funcional adicional é necessária. A disponibilidade real de capacidades avançadas e a compatibilidade do terminal são bloqueios técnicos tratados pelas SPEC-002 e SPEC-004.
