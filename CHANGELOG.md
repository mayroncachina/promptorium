# Changelog

Todas as mudanças relevantes do Promptorium.

## [não lançado]

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
- **quadro:** Gate de verificação por etapa — commit, árvore limpa, testes/lint/build antes de "feita"; reenvio automático ao agente (F1) (672392c)
- **sessoes:** Hooks gerenciados pelo app via `--settings` — bloqueio de comandos perigosos, formatar ao editar, fim da sessão; Configurações → Automações (F2) (cdd870f)
- **quadro:** Checkpoint por etapa (voltar / refazer) e estado durável — Autopilot, rascunho do Review e avisos sobrevivem ao fechar o app (F3) (cc73922)
- **worktree:** Worktree pronto para rodar — copiar `.env`, `preparar`, porta por worktree e `PROMPTORIUM_*`; fork leva alterações sem commit (F4) (e38aa7d)
- **review:** Revisor automático da spec com rodadas de correção `REVn` (F5) (9a99e3d)
- **review:** Review completo — todos os arquivos, lado a lado, realce, diff por etapa, checks, critérios de aceite, PR rascunho (F6) (0e9ec43)
- **specs:** Spec em camadas — Design, Etapas, Gerar design, prompt focado na etapa, `verificar:` no gate (F7) (f7ef7a9)
- **projeto:** Memória do projeto em `.promptorium/memoria.md` (F8) (b921aa9)
- **quadro:** Quadro operável — linha ao vivo, grafo de ondas, limites do Autopilot, sugestões das sessões, ordem na coluna (F9) (89b570f)
- **shell:** Menus na ordem do trabalho, Ferramentas com abas e paleta Ctrl+K real (F10) (c687a64)
- **robustez:** Migrações geradas (drift), backup antes de migrar, watchers de disco, gravação atômica, órfãos encerrados no splash (F11) (f65a0cf)
- **seguranca:** Lista de permitidos no Perguntar/planner, "Sem perguntar" só em worktree, modo trocado com a sessão viva, MCP mascarado (F12) (79b4ad9)
- **codigo:** Painel Git, busca global, aba Problemas e central de notificações (F13) (75dc5fc)
- **projeto:** Métricas de qualidade por spec (F14) (bd9c185)
- **quadro:** Best-of-N por etapa — Executar em dobro (A/B) e Comparar (F15) (a1a0438)
- **review:** Babysit de PR, merge pelo gh (squash/rebase) e resolver conflito (F16) (7746f72)
- **quadro:** Agendamento do Autopilot (F17) (a5056ef)
- **plataforma:** Cliente ACP (agentes no Prompt), Flatpak e aviso de versão nova (F18) (23a8f3e)
- **início:** Tela Início "Para você" (aprovações, etapas sem resposta, review, PR com problema, sessões interrompidas) com painel Agora; contadores na barra lateral; Ctrl+1…9 na nova ordem (UX v2, U1)
- **paleta:** Pendências (Aprovar / Negar / Responder / Abrir review / Retomar) na paleta, prefixos `>` `#` `:`, recentes e cabeçalhos por grupo; folha de atalhos Ctrl+/; Ctrl+Shift+A / Ctrl+Shift+D respondem a pendência mais antiga (UX v2, U2)
- **sessões:** Lado a lado (dois painéis, abas por sessão, ⫿ na lista, Ctrl+\\), linha ao vivo da ferramenta na lista, thinking recolhido na timeline (DT-20), resumo do subagente (ferramentas · tempo) e "Abrir preview :porta" (UX v2, U3)
- **sessoes:** Indicador de atividade e suspensão por inatividade (04c5235)
- **rodape:** Uso do plano atualizado sem gastar tokens (a525a5b)
- **menu:** Review e Código acima de Agentes (a7094ad)
- **distribuicao:** Pacote .deb e .tar.gz, CI e release no GitHub Actions (586dacb)
- **projeto:** Configuração do projeto em .promptorium/config.yml (a4cf665)
- **prompt:** Anexar e arrastar arquivos para a conversa (168e6a8)
- **aprovacoes:** Pedidos de permissão em qualquer tela (e1b5def)

### Correções

- **quadro:** Aviso "Ver sessão" some sozinho e leva à sessão (a3a12c8)

### Testes

- Specs no quadro, fase 8 — execução real de ponta a ponta (d6c7ef1)

### Build e CI

- Build e .deb só ao mergear na main; PR só analisa e testa (63883d1)

### Manutenção

- Git-cliff — configuração e CHANGELOG (4947774)


