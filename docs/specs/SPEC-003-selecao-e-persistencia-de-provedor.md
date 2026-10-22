---
id: SPEC-003
status: rascunho
depende-de: [SPEC-002]
---

# Seleção e persistência de Claude Code ou Codex

> **Codex desligado em 22/10/2026** ([DT-56](../debito-tecnico.md#dt-56--integracao-codex)). Spec adiada: o foco é o Claude Code. A auditoria de requisitos e as pendências para religar estão no DT-56.

## Objetivo

Permitir escolher Claude Code ou Codex para novas execuções e conservar essa escolha durante toda a vida de uma conversa, sessão ou execução de spec, incluindo recuperação após reiniciar o app.

## Requisitos

- R1 · Configurações deve permitir definir o provedor padrão global e o projeto deve poder sobrescrevê-lo. Ao atualizar uma instalação existente, Claude Code permanece como padrão e as preferências atuais são preservadas.
- R2 · Prompt, Nova sessão e Executar spec devem oferecer seleção explícita do provedor, com modelo, esforço e opções correspondentes. Ações auxiliares de IA devem mostrar qual provedor será usado antes do início e permitir alterá-lo, diretamente ou por preferências visíveis.
- R3 · O sistema deve resolver a escolha na ordem: provedor já vinculado à execução, escolha explícita para a nova execução, padrão do projeto, padrão global e Claude como padrão legado. O provedor resolvido deve acompanhar automaticamente etapas, reenvios, correções e retomadas dessa execução.
- R4 · Conversas, sessões e execuções de specs devem persistir provedor, identificador externo e configuração efetiva necessária à continuidade. Fork conserva o provedor; escolher outro provedor cria uma nova conversa ou sessão com transferência explícita do contexto selecionado, sem tentar retomar o ID externo original.
- R5 · Listas, timeline, detalhes e notificações devem identificar o provedor. Preferências de modelo e esforço por tipo de execução devem ser independentes para Claude e Codex, sem reaproveitar aliases ou valores incompatíveis ao trocar o seletor.
- R6 · Provedor indisponível, desconhecido ou incompatível com a configuração deve bloquear o início e explicar a correção; o sistema nunca deve substituir automaticamente o provedor salvo por outro habilitado. Alterações de padrão não devem modificar execuções existentes nem suas opções efetivas.

## Design

Usar IDs estáveis `claude` e `codex`, após conferir o ID Claude já persistido e manter exatamente o valor existente. Preservar IDs ACP. Trocar o `ComingSoonProvider` do Codex pelo adaptador da SPEC-002 quando os requisitos de disponibilidade forem satisfeitos.

Criar um resolvedor único de provedor e preferências para UI e serviços. Eliminar o fallback silencioso de `agentProviderByIdProvider` para o primeiro provedor habilitado quando o ID solicitado não existir. Separar resolução do padrão para execução nova de carregamento de uma execução existente.

Adicionar migração Drift incremental sobre a versão vigente, cobrindo sessões e demais entidades que ainda não guardam provedor. Conversas que já tenham `provider` devem mantê-lo. Dados antigos de sessões e execuções Claude recebem o ID legado; não inferir Codex pelo modelo ou pelo nome do agente. Vincular a configuração da execução da spec ao seu estado durável, sem misturá-la ao status editorial do documento.

Guardar UUID local e identificador externo em campos distintos. Migrar IDs Claude antigos para o campo externo quando essa equivalência for comprovada. Registros sem vínculo recuperável continuam visíveis, com diagnóstico ao retomar. A migração não deve recriar worktrees, apagar eventos ou alterar commits.

Preferências propostas: namespace por provedor e tipo (`session`, `conversation`, `planner`), preservando leitura das chaves `claude.*` atuais. Uma execução nova materializa a configuração resolvida; retomadas usam a configuração salva. Para registros antigos sem alguma opção, resolver o fallback uma vez e persistir o resultado. A mudança de modelo numa sessão existente exige ação explícita e respeita a capacidade do provedor.

Componentes: `settings/`, configuração do projeto, `agent_registry.dart`, `data/db/`, repositórios, diálogos de sessão e execução de spec, gerenciadores de conversas e sessões e estado durável do Quadro. Disponibilizar os provedores sem remover os agentes ACP.

## Critérios de aceite

- [ ] [R1] Atualizar banco e preferências antigos mantém Claude, seus modelos, esforços e compactação; um projeto com override Codex não altera outro projeto.
- [ ] [R2] Os três pontos de entrada exibem Claude e Codex e a escolha aparece antes de executar ações auxiliares; trocar provedor atualiza somente as opções do formulário novo.
- [ ] [R3] Teste do resolvedor cobre toda a precedência; uma spec Codex continua com Codex na segunda etapa mesmo após mudar o padrão global para Claude.
- [ ] [R4] Reabrir o app e retomar usa provedor, ID externo e configuração salvos; fork mantém provedor; transferência para outro provedor cria outro registro e informa o contexto enviado.
- [ ] [R5] Sessões simultâneas dos dois provedores são distinguíveis; salvar esforço/modelo Codex não altera os padrões Claude; modelos Claude não são enviados ao Codex.
- [ ] [R6] ID desconhecido, CLI ausente ou sem autenticação não inicia outro agente; alterar preferências não modifica uma sessão salva.
- [ ] Testes de migração, resolvedor, persistência e seletores passam; `flutter analyze` não apresenta novos avisos.

## Perguntas em aberto

- Nenhuma decisão de produto bloqueia a proposta. O formato físico das novas colunas e chaves deve ser definido a partir do schema vigente durante a implementação.
