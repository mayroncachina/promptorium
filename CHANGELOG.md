# Changelog

Todas as mudanças relevantes do Promptorium.

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


