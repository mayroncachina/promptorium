# 06 — Roadmap sugerido

Critério: primeiro o que evita trabalho perdido e custo desperdiçado (rede de segurança), depois o
que eleva a qualidade por dólar (review automático), depois ergonomia e expansão. Esforço é uma
estimativa grosseira em "fases" do tamanho das que já fizemos (uma fase ≈ um PR como os de
`feat/specs-no-quadro`).

## Onda 1 — Rede de segurança (3 fases)

| # | Item | Parte | DT | Impacto | Esforço |
|---|---|---|---|---|---|
| 1.1 | Gate de verificação por etapa (commit + árvore limpa + `testes:`), reenvio automático 1× | 02 §2.1 | 33 | alto | 1 fase |
| 1.2 | Hooks gerenciados: `Stop` (gate), `PostToolUse` (formatar), `PreToolUse` (bloquear comandos) via `--settings` temporário + sonda | 03 §3.1 | 25 | alto | 1 fase |
| 1.3 | Checkpoint por etapa (ref + stash) com "Voltar"/"Refazer etapa"; Autopilot e rascunho do Review persistidos | 02 §2.4, 05 §5.1 | 06, 36 | alto | 1 fase |

Resultado: etapa só fica "feita" se compilar, testar e commitar; dá para voltar; nada se perde ao
fechar o app.

## Onda 2 — Qualidade e worktree pronto (3 fases)

| # | Item | Parte | DT | Impacto | Esforço |
|---|---|---|---|---|---|
| 2.1 | Worktree: `copiar`, `preparar`, `porta-base` no `config.yml`; variáveis de ambiente; reuso no Fork | 02 §2.2 | 18 | alto | 1 fase |
| 2.2 | Revisor automático de spec (somente leitura, `--json-schema`) com rodadas de correção e comentários na lateral | 04 §4.1 | 34 | alto | 1 fase |
| 2.3 | Review: todos os arquivos, diff por etapa, checks no topo, critérios como checklist com bloqueio de merge | 04 §4.2, 4.4 | 36 | médio | 1 fase |

## Onda 3 — Spec mais inteligente e Quadro operável (3 fases)

| # | Item | Parte | DT | Impacto | Esforço |
|---|---|---|---|---|---|
| 3.1 | Spec em camadas: seção Design gerada pelo planner, etapas ligadas a design e critérios, prompt da etapa só com o trecho relevante | 02 §2.3 | 34 | alto | 1–2 fases |
| 3.2 | Memória do projeto (`.promptorium/memoria.md`) alimentada por gate/agente/humano | 03 §3.5 | — | médio | ½ fase |
| 3.3 | Quadro: linha ao vivo, grafo de ondas, limite de paralelismo e orçamento por onda, falha → `needs_input`, sugestões de spec vindas da sessão | 02 §2.5, 2.6 | 33 | médio | 1 fase |
| 3.4 | Reordenar menus (Projeto → Specs → Quadro → Sessões → Review → Código → Prompt → Ferramentas) + paleta Ctrl+K real | 02 §2.7, 05 §5.8 | 12 | médio | ½ fase |

## Onda 4 — Robustez de plataforma (2–3 fases)

| # | Item | Parte | DT |
|---|---|---|---|
| 4.1 | Migrações geradas + backup do banco; observar disco; gravação atômica; supervisão de PIDs órfãos | 05 §5.2–5.4 | 16, 32, 42, 44 |
| 4.2 | Modo Perguntar por lista de permitidos; MCP sem segredos no argv; `mcp list` em segundo plano | 05 §5.5–5.6 | 25, 45, 46, 48 |
| 4.3 | Painel Git mínimo, busca global, Problemas via `lint:`, central de notificações | 05 §5.8 | 01, 02, 04, 05 |

## Onda 5 — Expansão (quando o ciclo estiver estável)

- Best-of-N para etapa difícil (03 §3.4).
- Babysit de PR com CI e comentários do GitHub (04 §4.3); merge com rebase/squash e sessão de
  resolução de conflito.
- Agendamento do Autopilot (03 §3.7).
- Multi-provedor via ACP (05 §5.7); Flatpak e aviso de versão (05 §5.9).
- Métricas de qualidade por spec na tela Projeto (04 §4.5) — pode vir antes se quisermos medir o
  efeito das ondas 1–2 desde o início.

## O que eu não faria agora

- **Três arquivos por spec** como o Kiro: piora Review, git e o planner; a seção Design dentro do
  mesmo arquivo dá o mesmo ganho.
- **Execução na nuvem própria**: o remote control do Claude Code e o `gh` cobrem o "fechar o laptop"
  sem o app virar um serviço.
- **Multi-provedor antes do ciclo estar robusto**: cada provedor multiplica o custo das sondas e dos
  testes; a interface ACP pode ser decidida agora e implementada depois.

## Próximo passo sugerido

Transformar a Onda 1 em três specs pelo planner (Projeto → Roadmap), com `depende-de` 1.1 → 1.2 →
1.3, e rodar no próprio Promptorium — é o melhor teste de que o fluxo aguenta uma mudança real.
