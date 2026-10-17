# Análise — Promptorium × IDEs de IA (outubro/2026)

> Objetivo: comparar o que o Promptorium faz hoje com o que as IDEs e orquestradores de agentes
> atuais fazem, e listar melhorias concretas (fluxo de trabalho, sequência de menus, robustez)
> para discutirmos antes de virar specs.

Base da comparação: `README.md`, `docs/debito-tecnico.md` (DT-01…DT-49), `docs/plano-specs-no-quadro.md`
e o código em `lib/` (commit `aa18f69`). Fontes externas estão listadas no fim de cada parte.

## Partes

| Arquivo | O que tem |
|---|---|
| [01-panorama-ides.md](01-panorama-ides.md) | Quem são os concorrentes/referências, o que cada um faz de diferente e a tabela "eles × nós" |
| [02-fluxo-specs-e-quadro.md](02-fluxo-specs-e-quadro.md) | Melhorias no coração do app: spec → etapas → sessão → review → merge |
| [03-sessoes-e-agentes.md](03-sessoes-e-agentes.md) | Sessões, hooks, checkpoints, subagentes, memória, composer |
| [04-review-e-qualidade.md](04-review-e-qualidade.md) | Review por agente antes do humano, diff, PR, merge, conflitos |
| [05-plataforma-e-robustez.md](05-plataforma-e-robustez.md) | Processos, banco, disco, segredos, MCP, provedores, empacotamento |
| [06-roadmap-sugerido.md](06-roadmap-sugerido.md) | Sequência proposta em ondas, com impacto × esforço e o mapeamento para os DT-nn |

## Resumo executivo (1 minuto)

**Onde o Promptorium já está à frente**

- A **spec é o cartão**: uma unidade de trabalho = 1 branch = 1 worktree = 1 PR = 1 merge, com etapas
  (R1…Rn) rodando em sessões de contexto limpo. Nenhuma IDE comercial fecha esse ciclo inteiro
  localmente; Kiro para nas tasks, Cursor/Codex param no PR, Conductor não tem planejamento.
- **Autopilot por dependências** entre specs (ondas) — Cursor e Codex paralelizam tarefas soltas, sem grafo.
- **Aprovações centralizadas** de todas as sessões em qualquer tela, com notificação nativa.
- Planner com saída estruturada (`--json-schema`), catálogo de skills com origem/hash, config do
  projeto versionada (`.promptorium/config.yml`).

**Onde ficamos atrás (e o que mais pesa)**

1. **Sem rede de segurança por etapa**: não há checkpoint/rewind (DT-06), não há *gate* de testes
   automático antes de marcar a etapa como feita, e o marcador `ETAPA CONCLUÍDA` é a única verdade.
   Claude Code tem `/rewind`; Conductor roda *checks* por workspace; Copilot/Codex só abrem PR com CI verde.
2. **Sem hooks**: Claude Code (PreToolUse, PostToolUse, Stop, SessionStart…) e Kiro (on-save, pre-commit)
   permitem automatizar lint/format/test/segurança sem gastar turno. O app não usa nem expõe nada disso.
3. **Review só humano**: nenhuma rodada automática de revisão por agente antes de chegar ao Review
   (Copilot "agentic code review", Cursor Bugbot, Codex review). O `subagentes: quando: fim-da-spec`
   já aponta nessa direção, mas não há padrão embutido nem critérios.
4. **Worktree "nu"**: sem *setup script*, sem cópia de arquivos ignorados (`.env`), sem porta por
   worktree — exatamente o que o Conductor resolve e o que faz o paralelismo falhar na prática.
5. **Spec = texto livre**: Kiro separa requisitos (EARS) / design / tarefas e liga cada tarefa a um
   requisito; o Promptorium tem só "Requisitos" e "Critérios de aceite", sem design nem verificação ligada.
6. **Robustez de plataforma**: estado de Review/Autopilot em memória, migrações à mão, sem observar o
   disco, segredos no argv do MCP, lista fixa de ferramentas no modo Perguntar (DT-16, 25, 36, 42, 45).

**Sugestão de ordem** (detalhe em `06-roadmap-sugerido.md`): primeiro rede de segurança (checkpoints +
gate de testes + hooks), depois review automático e worktree pronto para rodar, depois spec
estruturada e paleta/Git. Multi-provedor (ACP) e nuvem ficam para o fim.
