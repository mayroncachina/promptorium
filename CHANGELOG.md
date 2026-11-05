# Changelog

Todas as mudanças relevantes do Promptorium.

## [0.9.0] - 2026-11-05

### Funcionalidades

- **motion:** Tokens AppMotion, MotionEnter e animações desligadas na suíte (SPEC-034 T1) (9f4bb53)
- **motion:** Transição de seção e destaque deslizante na barra lateral (SPEC-034 T2) (2618783)
- **motion:** AppPressable com hover e press em cards, linhas e botões (SPEC-034 T4) (d56c65e)
- **motion:** Eventos novos na timeline e status da etapa com check (SPEC-034 T6) (5a642ca)
- **motion:** Bola da etapa no espaço do ponto antigo, sem quebrar o texto (SPEC-034 T6) (946420b)
- **motion:** Diálogos e toasts com o ritmo do app (SPEC-034 T3) (5660af8)
- **motion:** Skeleton ao abrir uma spec, com o documento atual nos primeiros 300 ms (SPEC-034 T7) (5bfe894)
- **motion:** Card desliza até a coluna nova no Quadro (SPEC-034 T5) (86f4774)
- **motion:** Toast flutuante, teste de R13 e spec atualizada (SPEC-034 T8) (611f236)
- **board:** Subetapas na fila, verificação do requisito na última (SPEC-033 T2) (0bd9f70)
- **board:** Opções do modal de decisão da etapa (SPEC-033 T1) (65561c6)
- **board:** Modal de decisão até a escolha (SPEC-033 T3) (8d5fb8e)
- **board:** Fase Compilar do modal de decisão (SPEC-033 T4) (b2b0a80)
- **orquestrador:** Regras e dados do orquestrador (SPEC-035 T1) (475514f)
- **settings:** Seção Orquestrador (SPEC-035 T2) (81e9275)
- **orquestrador:** Classificação das etapas (SPEC-035 T3) (5677b25)
- **board:** Executar em Automático com o plano por etapa (SPEC-035 T4) (5a0c982)
- **board:** Cada etapa com o modelo do plano (SPEC-035 T5) (37dba07)
- **orquestrador:** Escalada de modelo quando a verificação reprova (SPEC-035 T6) (12268bb)
- **settings:** Histórico do orquestrador (SPEC-035 T7) (79d74e8)
- **board:** Paleta segue o Automático (SPEC-035 R19) (990817d)
- **board:** Visão Foco com a pasta de specs (SPEC-036 T1) (36a59e2)
- **board:** Busca na pasta de specs (SPEC-036 T2) (ce85c8c)
- **board:** Palco do Foco com dependentes e setas (SPEC-036 T3) (d584983)
- **board:** Specs em execução no palco (SPEC-036 T4) (bb8f4ec)

### Correções

- **board:** Executar em Automático igual ao mockup (SPEC-035) (ab39516)
- **settings:** Histórico e Executar iguais ao mockup (SPEC-035) (b2a152c)

### Documentação

- **spec:** SPEC-033 decidir a etapa que precisa de você pelo modal do balão (06ee3fe)
- **spec:** SPEC-033 decisões P1, P3, P4 e P5; P2 com a sugestão do desenvolvimento guiado por spec (d761101)
- **spec:** SPEC-034 motion e fluidez, com canvas interativo e validação (da09ffa)
- **spec:** SPEC-034 canvas aprovado, troca de seção em 640 ms (c0bd200)
- **spec:** SPEC-034 P1 decidida: T3 troca todos os diálogos (d696afb)
- **spec:** SPEC-036 pasta de specs e palco no Canvas do Quadro (56d1258)
- **spec:** SPEC-036 P1, P2 e P3 decididas: Foco como terceira visão, linha de dependências e painel de detalhes (a225d1f)
- **spec:** SPEC-035 orquestrador de modelos por etapa (100e391)
- **spec:** SPEC-035 P1 e P2 decididas: revisão pelo auto_reviewer, Codex fora por enquanto (d5a3654)
- **spec:** SPEC-033 P2 decidida: Dividir cria subetapas R3.1/R3.2 na fila, sem mudar o requisito (fd393b5)
- **spec:** SPEC-035 critérios e status (SPEC-035) (198eb4e)
- **mockups:** Telas da SPEC-035 (canvas e PNGs) (b621b64)
- Guia da visão Foco, decisões e capturas da SPEC-036 (3888ee3)

### Testes

- Prazo real nos testes com IO que estouravam com a suíte inteira (b5da378)
- Prazos reais nos testes que estouravam com a suíte inteira (ec80793)
- Painel de revisão não espera o prazo de 30 s sem o painel e rodadas de 4 ms (3da7717)
- SettleIo com condição usa voltas de 4 ms (sem condição mantém 20 ms) (67b3119)
- Memória do gate com comando de 1 s (limite de lentidão injetável no SpecRunner) (740aa88)
- Barra de sync espera a condição em voltas de 4 ms (4eceeae)
- Until dos testes de sessão consulta a cada 5 ms (o prazo continua 15 s) (2cc8848)
- SettleIo e barra de sync não adiantam o relógio falso mais que o real após as voltas iniciais (78294b6)
- Prazo real no drainUntil e aviso do SPEC-025 R9 sem depender da carga da máquina (SPEC-033 T5) (87a1cfe)
- Prazo real no salvar de project_config_test (SPEC-033 T5) (4f5f9d6)

### Build e CI

- CI só nos PRs e Criar Release com tag, release e pacotes (a135a91)

### Manutenção

- **hook:** Stop compara o conteúdo do código, não o commit (dc98ebf)

## [0.8.0] - 2026-11-03

### Funcionalidades

- **specs:** Cabeçalho da spec com ações por estado, menu Mais ações e abas de modo (SPEC-024) (058194b)
- **specs:** Spec bloqueada durante ações, com faixa de status, cancelamento e aviso de falha (SPEC-025) (2480123)
- **prompt:** Diff das edições, painel Spec em refino, resumo do turno e diálogo de alterações do refino (SPEC-026) (20c0dfa)
- **prototipo:** Apagar telas pelo cartão, pela seleção e pela aba Versões, com confirmação, aviso da aprovada e Desfazer (SPEC-027) (b5750b3)
- **specs:** Responder as perguntas em aberto numa sessão guiada, com formato P<n>, aviso de formato, aprovar com as sugestões e diff antes de salvar (SPEC-028) (d353a10)
- **icone:** Marca sem o quadrado escuro na janela, na bandeja e no tema hicolor, de 16 a 512 px e em SVG, com volta ao ícone anterior (SPEC-029) (7e0c31d)
- **board:** Balão na etapa que espera você, pulso único de 1,8 s até resolver, motivo no card, selo com balão, pílula neutra e "Atenção · i de n" (SPEC-030) (c8989f3)
- **shell:** Marca do sistema no cabeçalho, desenhada em vetor e animada como a abertura enquanto specs executam, com tooltip da onda e clique para o Quadro (SPEC-031) (2a8b56a)
- **review:** SPEC-032 R1-R5, R8, R10, R14 fila em pilha, estado em texto, uma ação primária e merge que segue para a próxima spec (553b99e)
- **review:** SPEC-032 R6, R7, R15 refaz a base das filhas depois do merge da mãe (34f1fc2)
- **review:** SPEC-032 R9, R11-R13 barra do worktree, aviso da raiz e Mergear a pilha (9bf8d78)
- **review:** SPEC-032 R17 resolver conflito com o agente ou eu mesmo, no editor (f3bbc16)
- **review:** SPEC-032 R16 grafo das ramificações do merge (7b38502)

### Documentação

- **specs:** SPEC-024 ações da spec mais claras, com mockups validados (79b9e73)
- **specs:** SPEC-025 spec bloqueada durante ações, com mockups validados (30c5d97)
- **specs:** SPEC-026 ver o que o refino gerou, com mockups validados (1edaf0b)
- **specs:** SPEC-027 apagar telas do protótipo, com mockups validados (72190c1)
- **specs:** SPEC-028 responder as perguntas em aberto, com mockups validados (9d1d9a0)
- **specs:** SPEC-029 ícone visível nas barras do Linux, com comparação do ícone atual e do esboço sem fundo (3d7cc71)
- **specs:** SPEC-030 precisa de você no card, com mockups validados e decisões do grill (7adb0da)
- **specs:** SPEC-031 marca do sistema no cabeçalho, animada enquanto as ondas executam, com mockups e decisões (d5c266c)
- **specs:** SPEC-031 animação da marca segue a de abertura (onda, bolhas até o gargalo, molécula) (101d96f)
- **specs:** SPEC-032 fila de Review em pilha, com merge de baixo para cima, rebase das filhas, aviso da raiz e mockups validados (d16002d)
- **specs:** SPEC-032 refaz a base das filhas quando a mãe é mergeada fora do app (R15) (07bd352)
- **specs:** SPEC-032 grafo das ramificações do merge (R16), resolver conflito com o agente ou no editor (R17) e fila com várias specs no mockup (c25776f)

### Testes

- **prototipo:** Espera a miniatura de 1100×700 em vez de um settle fixo (3a5f862)
- **specs:** Critérios de aceite do cabeçalho da spec (SPEC-024) (cf1d65d)
- **specs:** Critérios de aceite da spec bloqueada durante ações (SPEC-025) (9e6f07a)
- **prompt:** Critérios de aceite do que o refino gerou (SPEC-026) (ec0fea6)
- **prototipo:** Critérios de aceite de apagar telas do protótipo (SPEC-027) (e31645b)
- **specs:** Critérios de aceite de responder as perguntas em aberto (SPEC-028) (4cd6406)
- **icone:** Critérios de aceite da marca, da bandeja e da instalação dos ícones (SPEC-029) (bd3b7b1)
- **board:** Espera o diálogo de sem-design em vez de um tempo fixo (f8f06ca)
- **board:** Critérios de aceite do card que precisa de você (SPEC-030) (ed69626)
- **shell:** Critérios de aceite da marca no cabeçalho (SPEC-031) (2cf3f53)
- **specs:** Espera mais pela verificação no spec_sync_bar_test, que estourava os 10 s com a suíte inteira rodando (2d73254)
- **review:** Espera o controle Marcar todos no spec_review_panel_test, que falhava com a suíte inteira rodando (fae4594)

### Manutenção

- Versão 0.8.0 e configuração do Claude Code no repositório (81cf85c)
- Hook de Stop do Claude Code (testes verdes) e o settings.local.json que o liga (94e1401)

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

### Testes

- **about:** Ancora "Novidades da" no início para não casar com o CHANGELOG (16e3f57)

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


