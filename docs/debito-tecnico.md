# Débito técnico — Promptorium

Itens identificados durante o desenho dos mockups (2026-10-14) que **não** entram no MVP inicial,
mas são necessários para o Promptorium ser uma IDE robusta.

Mockups: https://claude.ai/artifact/SjkEe4XHWMvccd1VaQGAua

| # | Item | Prioridade | Observações |
|---|------|-----------|-------------|
| DT-01 | **Painel Git** — status, stage, commit, branches, histórico | Alta | Hoje só existe o Review no fim do fluxo |
| DT-02 | **Busca global e substituição** (Ctrl+Shift+F) | Alta | Buscar em todos os arquivos do worktree |
| DT-03 | **Tela de Configurações** | Alta | Engrenagem já existe na barra lateral, sem tela. Caminho do CLI, tema, atalhos, provedores, orçamento padrão |
| DT-04 | **Diagnósticos via LSP** (erros e avisos no editor, aba "Problemas") | Média | No MVP pode ser só `flutter analyze` |
| DT-05 | **Central de notificações** e **folha de atalhos** | Média | Histórico de "sessão terminou", "aprovação pendente" |
| DT-06 | **Checkpoints** — voltar o worktree para antes de uma alteração do agente | Média | |
| ~~DT-07~~ | ~~Uso do plano (5h / semanal) no rodapé~~ | — | **Resolvido na pesquisa:** vem no evento `rate_limit_event` do stream-json. Entra na Fase 5 |
| DT-08 | **Múltiplos provedores** (Codex, Gemini CLI) | Baixa | Seletor já desenhado na tela de Prompt; ícone do botão segue o provedor ativo |
| DT-09 | **Ícone: arte vetorial / bordas** | Baixa | Fase 1 gerou os PNGs recortando `icon.webp` (1254px) com máscara de cantos arredondados aproximada via ffmpeg (raio ≈ 200px). Ideal: SVG de origem + ícone simbólico para o painel |
| DT-10 | **Instalação desktop** (`.desktop` + ícones hicolor) | Média | `linux/promptorium.desktop` existe (`Exec=promptorium`, `Icon=promptorium`, `StartupWMClass=dev.promptorium.promptorium`), mas ainda não é instalado; previsto na Fase 12 |

## Requisitos de UX já decididos

### Editor (Specs e Código)
O editor usado para criar e editar specs — e o editor da tela de Código — precisa ser um editor de código de verdade:

- Realce de sintaxe (Markdown nas specs, Dart/YAML/JSON no código)
- Números de linha, busca e substituição no arquivo (Ctrl+F / Ctrl+H)
- **Zoom in / out**: Ctrl+= aumenta, Ctrl+- diminui, Ctrl+0 volta ao padrão; controle visível no topo do editor (− 100% +)
- Zoom salvo por editor (specs e código podem ter tamanhos diferentes)
- Modo dividido (fonte + visualização) nas specs
