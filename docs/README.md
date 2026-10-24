# Documentação do Promptorium

## Guia de uso

Como o app funciona e o que cada tela faz: [guia/](guia/README.md).

## Specs

As specs do próprio Promptorium ficam em [`specs/`](specs/), a pasta configurada em `.promptorium/config.yml`.

| Spec | Assunto | Status |
|---|---|---|
| [SPEC-001](specs/SPEC-001-scroll-vertical-no-quadro.md) | Scroll vertical no Quadro | concluída |
| [SPEC-002](specs/SPEC-002-integracao-codex.md) – [SPEC-005](specs/SPEC-005-codex-em-todos-os-fluxos.md) | Integração Codex | adiadas (Codex desligado) |
| [SPEC-006](specs/SPEC-006-seletor-de-provedor-no-rodape.md) | Seletor de provedor no rodapé | concluída |
| [SPEC-007](specs/SPEC-007-modo-yolo-do-codex.md) | Modo YOLO do Codex | concluída (inativa) |
| [SPEC-008](specs/SPEC-008-canvas-do-quadro.md) | Canvas do Quadro | concluída |
| [SPEC-009](specs/SPEC-009-comentarios-do-revisor-e-do-pr-no-diff.md) | Comentários do revisor e do PR no diff | concluída |
| [SPEC-010](specs/SPEC-010-diff-desde-a-ultima-rodada-do-review.md) | Diff desde a última rodada | concluída |
| [SPEC-011](specs/SPEC-011-painel-pronto-para-merge.md) | Painel "Pronto para merge?" | concluída |
| [SPEC-012](specs/SPEC-012-merge-local-guiado.md) | Merge local guiado | concluída |
| [SPEC-013](specs/SPEC-013-review-no-gitlab.md) | Review no GitLab | rascunho |
| [SPEC-014](specs/SPEC-014-deteccao-de-hospedagem-e-cli.md) | Hospedagem e CLI | concluída |
| [SPEC-015](specs/SPEC-015-descoberta-e-reconciliacao-de-specs.md) | Descoberta e reconciliação de specs | concluída |
| [SPEC-016](specs/SPEC-016-salvar-spec-da-resposta.md) | Salvar a spec escrita pelo agente | concluída |
| [SPEC-017](specs/SPEC-017-consumo-de-tokens-nas-etapas.md) | Menos tokens por etapa | concluída |
| [SPEC-018](specs/SPEC-018-marcar-todos-os-criterios-no-review.md) | Marcar todos os critérios no Review | concluída |
| [SPEC-019](specs/SPEC-019-vamos-trabalhar-em-uma-spec-no-quadro-de.md) | Ocultar concluídas e finalizar spec | concluída |
| [SPEC-020](specs/SPEC-020-icone-na-bandeja.md) | Ícone na bandeja | aprovada (verificação manual pendente) |
| [SPEC-021](specs/SPEC-021-voltar-a-spec-ao-refinar.md) | Voltar à spec ao refinar | concluída |
| [SPEC-022](specs/SPEC-022-prototipo-de-telas-da-spec.md) | Protótipo de telas da spec | aprovada (verificação manual pendente) |

Também em `specs/`: [README](specs/README.md) (Claude Code e Codex, ordem das SPEC-002 a 007) e as notas de implementação [008–013](specs/IMPLEMENTACAO-008-013.md) e [014–015](specs/IMPLEMENTACAO-014-015.md).

## Planos

| Documento | Assunto |
|---|---|
| [plano-implementacao.md](plano-implementacao.md) | Plano original do MVP, por fases (0 a 12), com decisões e sondagens do CLI |
| [plano-specs-no-quadro.md](plano-specs-no-quadro.md) | "A spec é o cartão do Quadro": etapas, worktree por spec |
| [plano-ux-v2.md](plano-ux-v2.md) | UX v2 (U1 a U9): Início, paleta, Quadro, Configurações |
| [plano-melhorias-ides.md](plano-melhorias-ides.md) | Melhorias F1 a F18 vindas da análise de outras IDEs |

## Análise e pesquisa

- [analise-ides/](analise-ides/00-README.md): panorama de IDEs e orquestradores de agentes e o roadmap sugerido a partir dele.
- [pesquisa/](pesquisa/): sondagens do Claude Code CLI e de outras ferramentas, com exemplos reais:
  - [stream-json-exemplo.jsonl](pesquisa/stream-json-exemplo.jsonl), [permissao-stdio-responder.py](pesquisa/permissao-stdio-responder.py), [perguntar-somente-leitura.py](pesquisa/perguntar-somente-leitura.py), [controle-sessao-viva.py](pesquisa/controle-sessao-viva.py)
  - [hooks-settings-stream-json.md](pesquisa/hooks-settings-stream-json.md), [plugins-mcp-desligados.md](pesquisa/plugins-mcp-desligados.md)
  - [codex-yolo.md](pesquisa/codex-yolo.md), [glab-1.36.0.md](pesquisa/glab-1.36.0.md)

## Outros

- [debito-tecnico.md](debito-tecnico.md): débito técnico (DT-xx) e pendências de conferência manual.
- [flatpak.md](flatpak.md): build Flatpak e acesso às ferramentas do host (não testado).
- [mockups/](mockups/): telas em HTML (`*.dc.html`), a proposta [v2](mockups/v2/README.md) e os PNGs das specs (`spec-NNN/`).
