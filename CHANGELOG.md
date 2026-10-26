# Changelog

Todas as mudanças relevantes do Promptorium.

## [0.7.0] - 2026-10-26

### Funcionalidades

- **SPEC-021:** Conversa de refino guarda o código da spec e a origem (Specs ou quadro) (R1) (3f1ef74)
- **SPEC-021:** Espera maior no until de answer_spec_bar_test (R1) (b1c7f5a)
- **SPEC-021:** Etapa verificada (origem do refino já gravada em 3f1ef74) (R1) (aa57ec4)
- **SPEC-021:** Watcher silencioso no teste de verificação do spec_sync_bar (R1) (5dddd8b)
- **SPEC-021:** Ação "Voltar à spec" na tela Prompt (R2, R4–R8, R11) (97c922c)
- **SPEC-021:** Card de origem rolado para a vista ao voltar ao quadro (R4, R10) (c5ba3de)
- **SPEC-021:** Alterações não salvas sobrevivem à troca de tela (R9, R3, R10) (29b23a8)
- **SPEC-019:** Filtro "Ocultar concluídas" por projeto no Quadro (R1–R6) (3bc7ec6)
- **SPEC-019:** Botão "Concluídas" na barra do Canvas e testes do filtro (R7) (d4a659f)
- **SPEC-019:** Finalizar e reabrir spec pelo frontmatter, na fila do sync (R8–R10) (78d2e21)
- **SPEC-019:** "Marcar como finalizada" e "Reabrir" no inspetor do Canvas (R8–R9) (09a109f)
- **SPEC-019:** Cabeçalho do Quadro cabe com o chip novo (rascunhos encolhem) (R5) (ed9b0a9)
- **SPEC-020:** TrayService e ícone na bandeja no Linux (R1–R8) (b276594)
- **SPEC-020:** Testes do TrayService (R7 R8) (6cdf61c)
- **SPEC-020:** Dependências da bandeja no .deb, CI e README (X11/Xi, sem AppIndicator) (R1) (54647b7)
- **SPEC-020:** Bandeja no Flatpak documentada (R7) (7fa9d33)
- **SPEC-023:** Contagem de testes no gate e "Aceitar a redução" (R1-R5) (04ca3aa)
- **SPEC-023:** Modelo com Fora do escopo e Perguntas em aberto, prompts de refino e de etapa (R11-R13) (39b3f05)
- **SPEC-023:** Perguntas antes de aprovar e avisos de estrutura no editor (R6-R10, R14) (5117c9a)
- **specs:** O zoom do editor também aumenta a visualização da spec (5721f2e)
- **SPEC-022:** Seção ## Protótipo na spec e tela aprovada no prompt da etapa (R9 R10) (b6d55ca)
- **SPEC-022:** Agente de telas com escrita restrita à pasta de mockups e variações (R2 R7) (8e68820)
- **SPEC-022:** Testes das miniaturas headless e do caso sem navegador (R4 R5) (b26fad3)
- **SPEC-022:** Modo Protótipo na tela Specs com canvas, painel e comparação (R1 R3 R6 R8 R11 R12) (abe11fe)

### Correções

- **gate:** Não roda os verificar: manual dos critérios (e497a22)

### Documentação

- **SPEC-021:** Critérios de aceite atendidos e status concluida (7a94e8d)
- **SPEC-019:** Spec de ocultar concluídas e finalizar spec, com decisões (c654898)
- **SPEC-019:** Critérios atendidos e spec concluída (b14ee63)
- **specs:** SPEC-020 ícone na bandeja do sistema (Linux) (d97035a)
- **SPEC-020:** Design e decisões; critérios automáticos marcados (72f4136)
- **specs:** SPEC-023 specs mais rigorosas (b4306f2)
- **SPEC-023:** Critérios atendidos, decisões e status aprovada (39926fe)
- **mockups:** Telas da SPEC-023 (8b63efe)
- **specs:** Corrige os avisos de estrutura das specs antigas (e02dbcb)
- **mockups:** Antes e depois do zoom na visualização da spec (a6c9481)
- **SPEC-022:** Spec do protótipo de telas com design e etapas (dd4a015)
- **SPEC-022:** Critérios marcados, status aprovada e mockups das telas (80b4894)
- **specs:** SPEC-022 marca a verificação manual do R6 (1506bc9)
- README enxuto e guia de uso por tela em docs/guia (463a1e0)
- **guia:** Modo Protótipo das specs (SPEC-022) (dc9d465)
- **guia:** Avisos de estrutura, perguntas ao aprovar e contagem de testes (SPEC-023) (84886f3)

### Build e CI

- Workflow Preparar release (versão no pubspec e CHANGELOG) e conferência na release (14a2d68)

## [0.6.0] - 2026-10-23

### Funcionalidades

- **review:** Marcar todos os critérios de aceite de uma vez (SPEC-014) (91fd57d)
- **specs:** Testes focados no prompt da etapa (SPEC-017 R1) (e43591a)
- **agents:** Desligar plugins e servidores MCP nas execuções do app (SPEC-017 R2) (78661fe)
- **specs:** Design com "O que já existe" e aviso ao executar sem ele (SPEC-017 R3) (7357828)
- **specs:** Continuar a próxima etapa na mesma sessão (SPEC-017 R4) (78dfd4d)
- **settings:** Seção Execução de specs (SPEC-017 R5) (1744903)
- **board:** Trava do gate, corrigir e verificar, etapa ao vivo (d12dbfd)

### Correções

- **review:** Descartar o "Desfazer" do lote ao trocar de item da fila (77b44a1)
- **specs:** Só ler o arquivo no Executar quando a spec pode precisar do aviso de Design (66ff10d)
- **sessions:** Retomar depois de suspender abre um processo novo (5668c45)
- Versão real no splash e atualização pelo pacote da cópia instalada (455d22a)

### Documentação

- Especificar o "marcar todos" dos critérios de aceite no Review (1eb6299)
- **specs:** Imagens dos mockups da SPEC-014 (ecd8ea0)
- Renumerar o "marcar todos" para SPEC-018 (19c97e8)
- Especificar a redução de tokens na execução de specs (SPEC-017) (9933004)
- **specs:** Mockups da SPEC-017 (3178835)
- **specs:** Decisões da SPEC-017 (35d63e8)
- **pesquisa:** Sonda de plugins e MCP desligados via --settings (SPEC-017 R2) (83f4299)
- **specs:** SPEC-017 e SPEC-018 concluídas (57e7a0c)

### Testes

- **review:** Esperar o painel refletir o banco nos testes do lote (791e279)
- Esperar condições em vez de tempo fixo nos testes instáveis (abb0ad6)
- Answer_spec_bar e run_extensions esperam até 15 s de tempo real (c0ff636)
- Spec_review_panel espera o painel até 15 s de tempo real (461558f)
- Specs_screen espera o arquivo até 15 s de tempo real (ad7a5eb)

### Build e CI

- Gerar o .deb só ao publicar uma release (8c90d60)

## [0.5.0] - 2026-10-22

### Funcionalidades

- **prompt:** Salvar a spec escrita pelo agente na resposta (SPEC-016) (e84368f)

### Documentação

- **specs:** Imagens dos mockups da SPEC-016 (a015ce4)

## [0.4.0] - 2026-10-22

### Funcionalidades

- **review:** Comentarios no diff, diff por rodada, prontidao e merge local guiado (6fe3375)
- **specs:** Descobrir specs da pasta configurada e verificar implementacao (e7c4c40)
- **board:** Canvas do Quadro no visual do mockup (384a74f)
- **board:** Fechar a SPEC-008 do canvas (083fe9d)
- **review:** Fechar a SPEC-010 do diff desde a rodada (5021770)
- **review:** Fechar a SPEC-014 de hospedagem e CLI (64f1ebe)
- **review:** Fechar a SPEC-009 dos comentarios no diff (810f03c)
- **review:** Fechar a SPEC-011 do painel pronto para merge (8cfd1ca)
- **specs:** Fechar a SPEC-015 com revisão do repositório no relatório e testes dos critérios (8bc971c)
- **review:** Fechar a SPEC-012 do merge local guiado (1a3feaf)
- **agents:** Desligar o Codex e focar no Claude Code (d251f38)

### Documentação

- Registrar specs do canvas do Quadro e das melhorias do Review (8ee088d)
- Definir a ordem de implementação das specs do Review e do canvas (2659eaa)
- **specs:** Ler specs de docs/specs e marcar a SPEC-001 como concluida (a1e3cc1)

## [0.3.0] - 2026-10-21

### Funcionalidades

- **db:** Persistir provedor e identidade externa das sessoes (070131b)
- **agents:** Integrar Codex App Server e politicas de permissao (17d96b7)
- **execucao:** Respeitar provedor em sessoes specs e acoes auxiliares (4553aa1)
- **ui:** Selecionar provedor padrao pelo rodape (fe04e13)

### Correções

- **footer:** Evitar sondagens de CLI ao consultar contadores (5fe72f2)

### Documentação

- Registrar specs de provedores e validacoes do Codex (9fa64a6)

### Build e CI

- **release:** Notas da release sempre geradas pelo git-cliff (8948daf)

## [0.2.1] - 2026-10-20

### Funcionalidades

- **SPEC-001:** Versão do app vem de PackageInfo (appVersionProvider) em vez de constante (R1) (276f106)
- **SPEC-001:** Testes cobrem falha do PackageInfo (0.0.0) e UpdatesCard sem erro (R2) (943ca6e)
- **SPEC-001:** Diálogo Sobre (F1, paleta e Configurações) com versão, repositório e changelog offline (R3) (65be29d)
- **SPEC-001:** Teste cobre F1 fechando o diálogo Sobre sem empilhar um segundo (R4) (1509b9b)
- **SPEC-001:** Teste cobre o changelog embutido com rede falhando e rolagem (R5) (3c05100)
- **SPEC-001:** AvailableUpdate lê notes/publishedAt/assets; diálogo Sobre mostra "Novidades da X.Y.Z" acima do changelog e habilita "Atualizar agora" (R6) (d262087)
- **SPEC-001:** Botão "Atualizar agora" só é renderizado quando há release mais nova (R7) (6944814)
- **SPEC-001:** Botão "Verificar agora" no diálogo Sobre chama check(force: true) e atualiza o diálogo com o resultado (R8) (34b1bf2)
- **SPEC-001:** "Atualizar agora" pede confirmação explícita (diálogo Atualizar/Cancelar) antes de qualquer download (R9) (fab397a)
- **SPEC-001:** Ao confirmar, escolhe o asset Linux (.deb/.tar.gz), baixa para diretório temporário novo e mostra o progresso (UpdateInstaller) (R10) (5a6d140)
- **SPEC-001:** Após o download, instala o pacote (.deb via pkexec apt install, .tar.gz sobre o diretório do executável), fecha o banco e reinicia o app (UpdateInstaller) (R11) (78a8571)
- **SPEC-001:** Falha no download/instalação mostra o erro no diálogo e oferece "Abrir página da release" (UpdateInstaller.openReleasePage) (R12) (6437b1a)
- **SPEC-001:** Download só por HTTPS em github.com, com nome de asset no padrão, tamanho e .sha256 conferidos; qualquer divergência aborta sem instalar (validateAsset) (R13) (37cbc93)
- **SPEC-001:** F1 com o terminal xterm focado abre o diálogo Sobre e não chega ao PTY; demais teclas de função seguem para o PTY (AppTerminalView.onKeyEvent) (R14) (751b4ee)
- **aprovacoes:** Perguntas do agente (AskUserQuestion) com opções para escolher (e78f6bf)
- **SPEC-001:** Quadro rola na vertical quando a altura é menor que o mínimo das colunas (R1) (823d358)
- **SPEC-001:** Teste garante rolagem vertical e horizontal do Grafo (o código já aninhava as duas rolagens) (R2) (85cecd2)
- **SPEC-001:** Teste garante que a roda do mouse sobre um cartão rola o Quadro (o código já repassa o gesto) (R3) (878e581)
- **SPEC-001:** Teste garante que uma coluna com muitos cartões rola sozinha, sem mover as outras (o código já usa um ListView por coluna) (R4) (6a4315a)
- **SPEC-001:** Teste garante que um Quadro que cabe na tela não tem barra de rolagem nem muda o layout (o código já devolve o Quadro direto) (R5) (561e10f)
- **SPEC-001:** Teste garante que arrastar um cartão muda a etapa mesmo com o Quadro rolando na vertical (o código já aceita o arraste) (R6) (064973d)
- **SPEC-001:** Barra de rolagem vertical sempre visível quando o Quadro rola na vertical (R7) (1af5bc7)

### Correções

- **projeto:** Preparar dos modelos pula enquanto o manifesto não existe (4b4bf16)
- **atalhos:** Clique fora de um campo não desliga mais os atalhos globais (2adbbf9)
- Splash mostrava v0.1.0; uma só constante de versão (AppInfo.version) (e9fe71f)
- **update:** Remove import de app_info que sobrou do merge da main (87dace2)

### Build e CI

- **release:** Gerar e anexar o .zip do Windows na release, como o Linux (6dc38e0)

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
- CHANGELOG da 0.2.0 (cliff reconhece tags com ou sem v) (d69e10c)

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


