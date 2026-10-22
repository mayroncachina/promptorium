# Claude Code e Codex no Promptorium

Proposta em rascunho para oferecer Codex em todos os fluxos que hoje usam Claude Code, com as mesmas possibilidades de uso e controles do produto. Segue o formato de [SPEC-001](SPEC-001-scroll-vertical-no-quadro.md): frontmatter, objetivo, requisitos numerados, design e critérios de aceite vinculados aos requisitos.

## Ordem de implementação

| Spec | Entrega | Dependências |
| --- | --- | --- |
| [SPEC-002](SPEC-002-integracao-codex.md) | Adaptador Codex e contrato de execução compartilhado | Nenhuma |
| [SPEC-003](SPEC-003-selecao-e-persistencia-de-provedor.md) | Seleção, preferências e persistência do provedor | SPEC-002 |
| [SPEC-004](SPEC-004-paridade-de-opcoes-claude-codex.md) | Opções, permissões, agentes, skills, MCP e consumo | SPEC-003 |
| [SPEC-005](SPEC-005-codex-em-todos-os-fluxos.md) | Sessões, specs, Quadro, planejamento, review e automações | SPEC-004 |
| [SPEC-006](SPEC-006-seletor-de-provedor-no-rodape.md) | Seleção de provedor pelo indicador de conexão do rodapé | SPEC-003 |
| [SPEC-007](SPEC-007-modo-yolo-do-codex.md) | Modo YOLO do Codex no lugar do bypass Claude | SPEC-003, SPEC-004 |

As SPEC-002 a SPEC-005 compõem a integração; a SPEC-006 complementa a seleção com o acesso pelo rodapé e a SPEC-007 detalha o modo YOLO do Codex. Habilitar apenas o seletor do Prompt não encerra a funcionalidade. Os IDs continuam a numeração encontrada no repositório; a SPEC-001 também fica em `docs/specs/`, a pasta configurada em `.promptorium/config.yml`.

## Base da proposta

- [Plano de implementação](../plano-implementacao.md), especialmente fases 4–11 e preferências de consumo.
- [A spec é o cartão do Quadro](../plano-specs-no-quadro.md): etapas sequenciais, worktree por spec e specs com aproximadamente seis requisitos.
- [Melhorias de IDE](../plano-melhorias-ides.md): gates, hooks, review automático, duelos e recuperação.
- [DT-08](../debito-tecnico.md): múltiplos provedores.
- Código atual: `lib/core/providers/`, `lib/core/claude/claude_args.dart`, `lib/core/claude/run_prefs.dart`, gerenciadores de sessões e conversas e chamadas diretas de Claude nos serviços de planejamento, design, skills e review.

O registro já oferece Claude e agentes ACP, mas mantém Codex como `ComingSoonProvider`. O contrato compartilhado ainda usa eventos e tipos do Claude; o gerenciador de sessões e vários serviços não passam por esse contrato. A implementação precisa tratar ambos os pontos e preservar os provedores ACP existentes.

## O que significa ter todas as opções do Claude

Cada opção atual deve constar na matriz da SPEC-004 e receber implementação nativa ou equivalente com garantia verificável. Apenas copiar o nome de uma opção não garante paridade. Diferenças reais do Codex devem aparecer no controle correspondente e na configuração efetiva da execução.

Uma opção sem equivalente permanece documentada como lacuna, com motivo e critério de resolução. Se for necessária ao fluxo escolhido, a execução deve ser bloqueada antes de iniciar. Exibir “indisponível” é um estado intermediário honesto, mas não conta como concluir a paridade. Nunca ignorar uma opção, diminuir uma restrição ou executar Claude no lugar do Codex silenciosamente.

## Validação técnica e fonte externa

A proposta usa o [Codex App Server, documentação oficial da OpenAI](https://learn.chatgpt.com/docs/app-server), consultada em 2026-10-20. A documentação descreve JSON-RPC, inicialização, threads, turnos, eventos e aprovações; também orienta descobrir modelos e esforços disponíveis com `model/list`. Esses recursos fundamentam o adaptador proposto. Não há suposição de equivalência entre flags do Claude e campos do Codex.

Os detalhes de opções avançadas, autenticação, terminal, hooks e isolamento devem ser confirmados por sondagens da versão instalada antes da implementação correspondente. Registrar versão, cenário, resultado e limitações em `docs/pesquisa/`; não fixar modelos ou uma versão mínima sem evidência.

## Local dos documentos

Estes arquivos ficam em `docs/specs/`. O serviço de specs lê a pasta configurada em `ProjectConfig.specsDir` (padrão `specs/`); este projeto define `specs: docs/specs` em `.promptorium/config.yml`, e a SPEC-001 foi movida para cá, então todas aparecem na aba Specs e no Quadro.


## Hospedagem do projeto e Review

- [SPEC-014 — Identificação da hospedagem e orientação de CLI](SPEC-014-deteccao-de-hospedagem-e-cli.md): próximo escopo para identificar GitHub/GitLab/outros, escolher a ferramenta correta e orientar instalação/login.
- [SPEC-013 — Review no GitLab](SPEC-013-review-no-gitlab.md): proposta operacional adiada no [DT-55](../debito-tecnico.md#dt-55--integracao-completa-do-review-no-gitlab). Mantida como referência técnica.

A sequência histórica SPEC-009 → SPEC-013 nos documentos originais fica atualizada por esta decisão: a integração completa da SPEC-013 sai do escopo ativo. A SPEC-014 pode ser entregue sem concluir o DT-55 e sem bloquear o Canvas da SPEC-008.


## Descoberta de specs e estado no Quadro

- [SPEC-015 — Descoberta de specs existentes e conclusão no Quadro](SPEC-015-descoberta-e-reconciliacao-de-specs.md): varrer a pasta configurada, importar sem duplicar, colocar specs declaradas concluídas em Concluído e verificar implementação de documentos ainda desatualizados com evidências por requisito.
