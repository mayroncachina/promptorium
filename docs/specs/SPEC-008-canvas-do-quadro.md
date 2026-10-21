---
id: SPEC-008
status: rascunho
---

# Canvas do Quadro: dependências, etapas e referências

## Objetivo

Transformar a visão **Grafo** do Quadro (`WaveGraph`, hoje um grafo de ondas com rolagem) em um **canvas** navegável, com zoom e movimento. Cada spec é um nó compacto com o estado das etapas; ao selecionar uma spec, o canvas mostra de que ela depende, o que ela desbloqueia e quais **agentes** e **skills** ela referencia.

Responde "o que depende do quê e quem usa o quê?". A visão **Colunas** continua respondendo "em que pé está cada spec?" e continua sendo a padrão.

- A tela é a visão **Canvas** (antes "Grafo") do Quadro, no mesmo seletor `Colunas | Canvas`. Nenhuma tela nova, e a spec selecionada continua selecionada ao trocar de visão (`boardSelectedSpecProvider`).
- Só aparecem agentes e skills **referenciados pelas specs**, nunca todos os instalados. As instaladas ficam nas telas Agentes e Skills.
- Sem métricas de uso (custo, tokens, gráficos): foram descartadas de propósito na exploração do mockup.
- Mockup de referência: [`docs/mockups/Quadro-Canvas.dc.html`](../mockups/Quadro-Canvas.dc.html). Ele mostra a intenção visual; os dados e alguns controles do mockup são de exemplo (ver "O que o mockup não define").
- Fora do escopo: editar dependências arrastando ligações, reposicionar nós à mão, minimapa, mostrar custo ou tokens, e mudar a visão Colunas.

## Requisitos

- R1 · O sistema deve oferecer a visão Canvas do Quadro com movimento (arrastar o fundo) e zoom entre 50% e 150%, por roda do mouse com Ctrl, menu de zoom e atalhos Ctrl+=, Ctrl+- e Ctrl+0. O menu, aberto pelo valor do zoom na barra, deve ter Aproximar, Afastar, Tamanho real (100%), Ajustar à tela e Ajustar à seleção.
- R2 · O sistema deve desenhar cada spec do quadro como um nó posicionado na coluna da sua onda de dependência, com id, título, estado e uma bolinha por etapa (feita, em execução, verificando, aguardando você ou pendente; ao passar o mouse numa bolinha, mostrar o id, o título e o texto do requisito daquela etapa), e uma ligação com seta de cada dependência até a spec que a aguarda. Selecionar um nó deve destacar suas ligações, as specs de que depende e as que desbloqueia, e esmaecer o restante.
- R3 · Quando uma spec estiver selecionada, o sistema deve mostrar, ligados ao nó dela, os agentes e as skills que ela referencia, até 3 por grupo e um nó "+N mais" que, ao ser clicado, expande o grupo e mostra todos. Sem spec selecionada, não deve mostrar nenhum agente nem skill. As camadas Agentes e Skills devem poder ser ligadas e desligadas separadamente.
- R4 · Ao passar o mouse ou focar com o teclado um agente ou skill, o sistema deve mostrar um cartão com o nome, o escopo (Projeto, Global ou Embutida), a descrição, o modelo e as ferramentas (agente) ou a forma de chamada e a origem (skill).
- R5 · O sistema deve mostrar, ao lado do canvas, o painel da spec selecionada com objetivo, "depende de", "desbloqueia", lista de etapas com estado (ao passar o mouse ou focar uma etapa, mostrar o texto do requisito que ela implementa) e as referências, mais a ação do momento da spec, a mesma do cartão das Colunas (Executar, Continuar, Responder na sessão, Tentar de novo ou Ver review), e as ações "Abrir spec" (tela Specs) e "Ver nas colunas" (muda para Colunas mantendo a seleção).
- R6 · Enquanto houver uma etapa em execução, o sistema deve fazer a bolinha dela pulsar, parando a animação quando o sistema operacional pedir menos movimento e quando não houver etapa em execução. O canvas deve ter legenda com estados das etapas, tipos de ligação, agente e skill.
- R7 · Quando uma spec precisar de intervenção humana (etapa aguardando você, inclusive com a verificação falhada; aprovação de ferramenta pendente; falha ao preparar o worktree; spec alterada no disco; duelo A/B pronto, a mesma regra `needsAttention` das Colunas), o sistema deve destacar o nó com um anel âmbar pulsante e o selo "Precisa de você", mostrar no painel o motivo e a ação correspondente e oferecer, na barra de ferramentas, o contador "Atenção · N", que seleciona e centra a próxima spec nessa situação. Quando mais de uma etapa da mesma spec estiver aguardando, o painel deve listar todas no motivo, cada etapa deve mostrar o próprio marcador e o selo e o contador devem contar a spec uma só vez.

## Design

### O que já existe e muda

- `lib/features/board/widgets/wave_graph.dart`: `WaveGraph` já calcula as ondas (`dependencyWaves`), posiciona uma coluna por onda e desenha as dependências com `_EdgesPainter`. Hoje usa dois `SingleChildScrollView` e reaproveita `SpecCard` (170 px de altura) como nó.
- `board_screen.dart`: `boardGraphViewProvider` (booleano) e o seletor `Colunas | Grafo` (`ToggleBox`, chaves `board-view-columns` e `board-view-graph`).
- Mantido: `dependencyWaves`, `nextWave` e o destaque da onda "PRÓXIMA" quando o autopilot roda, as chaves `board-graph` e `board-wave-N` e a leitura de `specs.dependsOn`. Os testes de `board_screen_test.dart` seguem valendo.

### R1 · Movimento e zoom
- Trocar os dois `SingleChildScrollView` por `InteractiveViewer` com `TransformationController`, `minScale: 0.5`, `maxScale: 1.5`, `constrained: false` e margem de limite ao redor do conteúdo. Arrastar o fundo move; roda com Ctrl dá zoom.
- Controlador próprio (`CanvasViewController`) com `zoomIn`, `zoomOut`, `reset`, `fit` e `fitSelection`; o menu e os atalhos só chamam esses métodos.
  - `fit`: escala o retângulo que contém todos os nós para a área visível, limitada a 50–150%.
  - `fitSelection`: 130%, centrando o nó selecionado na área livre do painel.
  - Passo de zoom: 10%, em torno do centro da área visível.
- Menu: `MenuAnchor` aberto pelo botão com o valor do zoom (`Text('${(scale*100).round()}%')`). Atalhos: `CallbackShortcuts` sob um `Focus` do canvas. O app já usa Ctrl+=, Ctrl+- e Ctrl+0 para o zoom do editor da tela ativa; o Quadro passa a usá-los no canvas quando a visão Canvas está ativa (nas Colunas não fazem nada).
- O zoom e a posição não são salvos: o canvas sempre abre em 100%.
- Descartei animar a troca de zoom no primeiro corte: `TransformationController` não anima sozinho e `AnimationController` extra não compensa agora. O mockup anima; é diferença conhecida.

### R2 · Nós, ligações e seleção
- Nó compacto novo (`SpecNode`, ~250×116): id, selo de estado, título e a fileira de bolinhas. **Não** reaproveita `SpecCard`, que continua só nas Colunas. As ações de executar, continuar, responder e revisar ficam no painel (R5), não no nó.
- Posição por onda como hoje (coluna = onda, linha = ordem na onda), com a altura nova do nó. A ligação reaproveita `_EdgesPainter` (curva e seta); ligações do nó selecionado ficam mais grossas e as demais mais claras.
- Estado das etapas vem de `spec_steps.status` (`StepStatus`), a mesma fonte do `spec_steps_panel.dart`. Cores: feita = verde, em execução = laranja (distinta do azul dos agentes), selo Review = magenta, aguardando você = losango âmbar, verificando = anel teal girando, pendente = contorno vazio. Cada estado se distingue também pela forma, não só pela cor. As Colunas usam lilás para "verificando"; o canvas usa teal para não se confundir com o roxo das skills. Cores com contraste mínimo de 4,5:1 sobre o fundo do nó.
- Tooltip da bolinha: mesmo cartão e mesma fonte (`Spec.requirements`) da lista de etapas do painel (R5). Só abre com o mouse; o nó inteiro é um único alvo de foco, então quem usa teclado seleciona o nó e lê o texto no painel.
- Seleção: `boardSelectedSpecProvider`, o mesmo das Colunas. Clicar no fundo limpa a seleção.

### R3 · Agentes e skills da spec
- **Agentes** de uma spec = união de `specs.agentName` e de `sessions.agentName` das sessões com `sessions.specId` igual à spec.
- **Skills** de uma spec = nomes distintos da ferramenta `Skill` (`"name":"Skill"` com `"skill":"<nome>"`) nos `session_events` das sessões com `specId` igual à spec. É a mesma estratégia do `skillUsageProvider`, em `skills_state.dart`, agrupada por spec.
  - Essa leitura é aproximada: depende do evento no JSON. Skills usadas em sessões de outra spec não entram. Skills só "disponíveis" (de `system/init`) **não** contam; só as realmente carregadas.
- Posição: duas fileiras abaixo do nó selecionado (agentes primeiro, skills depois), centradas no nó, com ligação tracejada (azul para agente, roxo para skill). Agente é retângulo; skill é pílula.
- Cada nó mostra em quantas specs do quadro o nome aparece (ex.: "3 specs"). O excedente de 3 vira o nó tracejado "+N mais"; clicar nele mostra todos os nós do grupo (as fileiras quebram em mais linhas, centradas no nó da spec) e clicar de novo recolhe.
- Provider novo `specReferencesProvider(specId)`, com `FutureProvider.autoDispose.family` e `watch` em `appDatabaseProvider`. Falha de leitura não derruba o canvas: a spec fica sem referências e o painel mostra "referências indisponíveis".

### R4 · Cartão de detalhes
- Fonte do agente: `AgentFile` (`lib/features/agents/agent_file.dart`), já lido pela tela Agentes (frontmatter `description`, `model`, `tools`, escopo Global/Projeto).
- Fonte da skill: `SKILL.md` (tela Skills) para skills de projeto e globais. Skills de plugin ou embutidas só têm o nome (vindo dos eventos); o cartão mostra "Embutida" e "sem descrição disponível", sem inventar texto.
- Abre ao passar o mouse (espera de 300 ms) e ao receber foco pelo teclado (Tab), fecha ao sair ou com Esc. `Tooltip` do Flutter não abre por foco; usar `OverlayPortal` e `Focus`.
- O cartão não diz em quais etapas o agente ou a skill foi usado: o app só guarda a última sessão de cada etapa, então a informação sairia incompleta. A spec inteira é a unidade (R3).

### R5 · Painel da spec
Largura fixa de 290 px, sobre o canvas, à direita. Conteúdo vem de `Spec` (objetivo = primeira seção "Objetivo" do arquivo, `dependsOn`, etapas) e de `specReferencesProvider`. "Desbloqueia" = specs do quadro cujo `dependsOn` contém o código. "Abrir spec" usa a navegação já existente para Specs.
- Texto da etapa: `Spec.requirements` (`({String id, String text})`, espelho dos requisitos do arquivo) já traz o texto de cada etapa, o mesmo mostrado no painel Etapas da tela Specs. O cartão de detalhes usa o mesmo mecanismo de abertura (mouse com espera de 300 ms, foco por teclado, Esc fecha) do R4, com o id e o título da etapa no cabeçalho. Etapa sem texto (a `REV1`, criada pelo revisor automático, usa `spec_steps.body`) mostra esse texto; se também não houver, não abre cartão.
- Ação do momento: hoje fica dentro do `SpecCard`, em `board_screen.dart` (`board-run-<código>`, `board-answer-<código>`, `board-prep-retry-<código>`, `board-review-<código>`), e chama `runSpec` (`run_spec_dialog.dart`, que abre o `RunSpecDialog` na primeira execução). Extrair essa escolha de botão para um widget compartilhado, usado pelo cartão das Colunas e pelo painel, para os dois sempre oferecerem a mesma ação, com as mesmas regras (`canRun`, bloqueio por dependência, execução em andamento). O painel não duplica a lógica nem chama o `specRunnerProvider` por conta própria. Executar uma spec bloqueada por dependência continua impossível, e o painel mostra o motivo, como o cartão. Em janelas estreitas o painel vira uma faixa recolhível; larguras abaixo de 900 px não são alvo desta spec.

### R7 · Atenção
- Mesma regra das Colunas: reaproveitar `needsAttention` e o `attentionCount` já calculados em `board_screen.dart` (etapa em `needsInput`, aprovação pendente, `prep?.error`, `changedOnDisk`, duelo `pronto`). O canvas não cria regra própria; um estado novo de atenção nas Colunas aparece sozinho no canvas.
- Nó: anel âmbar pulsante (animação de `box-shadow`, mesma regra de movimento reduzido do R6) e selo "Precisa de você" na borda superior. O destaque soma-se à seleção: um nó selecionado que precisa de você mantém os dois.
- Painel: aviso no topo com o motivo, o mesmo texto da linha `meta` do cartão ("R3 aguardando você", "verificação falhou", "aguardando aprovação", "falha ao preparar o worktree"). A ação vem do widget compartilhado do R5: "Responder na sessão" (`openSession`) para etapa aguardando você, "Tentar de novo" para falha de preparo e, para aprovação de ferramenta pendente, "Abrir aprovações", que leva à fila de aprovações em Sessões. O canvas **não** aprova nem nega ferramentas por conta própria: aprovar exige ver o comando, e isso é da fila de aprovações.
- Quando o destaque some: ele é recalculado a partir do estado salvo das etapas, não é um aviso a dispensar. Ao enviar uma mensagem na sessão, `SessionManager` marca a sessão como `running` e chama `SpecRunner.onActive`, que devolve as etapas não concluídas a `running`; o anel e o selo somem no instante do envio, e voltam se a sessão parar de novo sem concluir (`onResult` marca as etapas como `needsInput`). Aprovação pendente tem sinal próprio (`waitingApproval`) e dura até a aprovação ser decidida.
- Várias etapas: uma sessão cobre até as etapas da spec pequena (até 3 por padrão) e, ao parar sem concluir, `SpecRunner` marca **todas** as suas etapas como `needsInput` de uma vez. O `current` do cartão (`board_rules.dart`) devolve só a primeira; o canvas não usa `current` para isso: lê todas as etapas da spec. A ação é única ("Responder na sessão"), porque as etapas partilham a mesma sessão. O motivo junta os ids ("R3 e R4 aguardam você").
- Barra de ferramentas: botão "Atenção · N" (N = `attentionCount`). Cada clique seleciona a próxima spec com atenção, na ordem onda e depois id, e usa o mesmo cálculo de "Ajustar à seleção" do R1. Com N = 0 o botão fica desabilitado.

### R6 · Pulso e legenda
- `AnimationController` com `repeat(reverse: true)`, 1,4 s, ligado só quando existe etapa `running` visível e `MediaQuery.disableAnimations` é falso. Anima só a opacidade e o anel da bolinha, num `RepaintBoundary`, sem reconstruir os nós.
- Legenda fixa no canto inferior esquerdo, com os mesmos textos e cores do mockup: os cinco estados de etapa, as duas ligações, agente e skill.

### O que o mockup não define
Reaproveitar o `SpecCard` (descartado), arrastar nós (fora), o estado sem seleção (R3 o define: nada aparece), o que acontece com dezenas de agentes e skills (o limite de 3 e o "+N mais" expansível cobrem o caso comum; com muitos nós expandidos o grupo quebra em várias linhas, sem rolagem própria) e o modo sem workspace aberto (já tratado pelo Quadro vazio).

### Riscos
- A leitura de skills por `LIKE` no JSON dos eventos é lenta com muito histórico. Mitigação: uma consulta por spec, com `autoDispose`, e índice se medido necessário.
- `InteractiveViewer` com centenas de nós reconstrói tudo a cada mudança de seleção. Mitigação: nós `const` quando possível e `RepaintBoundary` por nó; medir com 60 specs.
- Atalhos Ctrl+= / Ctrl+- / Ctrl+0 dependem do foco; se o foco estiver num campo de texto, o atalho do editor não deve ser capturado.

## Critérios de aceite

Os testes marcados "(a criar)" fazem parte da implementação; usam banco em memória e arquivos falsos, sem rede.

- [ ] [R1] A visão Canvas abre com 100%; arrastar o fundo move o conteúdo e Ctrl + roda altera o zoom, sem passar de 50% nem de 150%. verificar: `flutter test test/features/board/canvas_view_test.dart` (a criar)
- [ ] [R1] O menu do zoom tem Aproximar, Afastar, Tamanho real, Ajustar à tela e Ajustar à seleção; Ajustar à tela deixa todos os nós visíveis e Ajustar à seleção centra o nó selecionado. verificar: `flutter test test/features/board/canvas_view_test.dart` (a criar)
- [ ] [R1] Ctrl+=, Ctrl+- e Ctrl+0 mudam o zoom do canvas quando a visão Canvas está ativa e não fazem nada nas Colunas. verificar: `flutter test test/features/board/canvas_view_test.dart` (a criar)
- [ ] [R2] Cada spec aparece na coluna da sua onda, com uma bolinha por etapa no estado correto, e cada dependência tem uma ligação até a spec que a aguarda. verificar: `flutter test test/features/board/wave_graph_test.dart` (a criar)
- [ ] [R2] Passar o mouse numa bolinha de etapa do nó mostra id, título e texto do requisito daquela etapa. verificar: `flutter test test/features/board/wave_graph_test.dart` (a criar)
- [ ] [R2] Uma etapa `needsInput` aparece como losango âmbar, uma `verifying` como anel teal girando, e os dois se distinguem da etapa pendente e da em execução também pela forma. verificar: `flutter test test/features/board/wave_graph_test.dart` (a criar)
- [ ] [R2] Selecionar uma spec destaca as ligações dela e esmaece os nós que não são dela, das dependências nem das dependentes; clicar no fundo limpa a seleção. verificar: `flutter test test/features/board/wave_graph_test.dart` (a criar)
- [ ] [R2] Os testes atuais do Quadro (chaves `board-graph`, `board-wave-N`, `board-view-graph`) continuam passando. verificar: `flutter test test/features/board/board_screen_test.dart`
- [ ] [R3] Com uma spec selecionada, aparecem só os agentes e skills dela, ligados ao nó; sem seleção, nenhum aparece. verificar: `flutter test test/features/board/spec_references_test.dart` (a criar)
- [ ] [R3] Uma spec com 5 skills mostra 3 e o nó "+2 mais"; clicar nele mostra as 5 e clicar de novo volta a 3. verificar: `flutter test test/features/board/spec_references_test.dart` (a criar)
- [ ] [R3] As skills vêm só da ferramenta `Skill` nos eventos das sessões da spec; uma skill listada apenas no `system/init` não aparece. verificar: `flutter test test/features/board/spec_references_test.dart` (a criar)
- [ ] [R3] Desligar a camada Agentes esconde só os agentes e as ligações deles; o mesmo vale para Skills. verificar: `flutter test test/features/board/canvas_view_test.dart` (a criar)
- [ ] [R4] Passar o mouse num agente mostra nome, escopo, descrição, modelo e ferramentas; Tab no nó mostra o mesmo cartão e Esc o fecha. verificar: `flutter test test/features/board/canvas_view_test.dart` (a criar)
- [ ] [R4] O cartão de uma skill embutida mostra "Embutida" e "sem descrição disponível", sem texto inventado. verificar: `flutter test test/features/board/canvas_view_test.dart` (a criar)
- [ ] [R5] Numa spec aprovada sem execução o painel mostra "Executar", que abre o diálogo de opções; com sessões anteriores mostra "Continuar · Rn"; aguardando resposta mostra "Responder na sessão"; em review mostra "Ver review". Uma spec bloqueada por dependência não oferece Executar e mostra o motivo. verificar: `flutter test test/features/board/canvas_view_test.dart` (a criar)
- [ ] [R5] Passar o mouse numa etapa do painel (ou focá-la com Tab) mostra o texto do requisito dela, com id e título no cabeçalho; Esc fecha; uma etapa sem texto não abre cartão. verificar: `flutter test test/features/board/canvas_view_test.dart` (a criar)
- [ ] [R5] O cartão das Colunas e o painel do canvas oferecem a mesma ação para a mesma spec, e os testes atuais das ações do cartão continuam passando. verificar: `flutter test test/features/board/board_screen_test.dart`
- [ ] [R5] O painel mostra objetivo, depende de, desbloqueia, etapas e referências da spec selecionada; "Abrir spec" leva à tela Specs e "Ver nas colunas" volta às Colunas com a mesma spec selecionada. verificar: `flutter test test/features/board/canvas_view_test.dart` (a criar)
- [ ] [R6] Com uma etapa em execução a bolinha anima; sem etapa em execução, ou com `disableAnimations`, fica parada e nenhum `AnimationController` continua ativo. verificar: `flutter test test/features/board/canvas_view_test.dart` (a criar)
- [ ] [R6] A legenda mostra os cinco estados de etapa, os dois tipos de ligação, agente e skill. verificar: `flutter test test/features/board/canvas_view_test.dart` (a criar)
- [ ] [R7] Uma spec com etapa aguardando você, aprovação pendente, falha de preparo, alteração no disco ou duelo pronto mostra o anel âmbar e o selo "Precisa de você" no nó; uma spec concluída não mostra. verificar: `flutter test test/features/board/canvas_view_test.dart` (a criar)
- [ ] [R7] Com duas etapas da mesma spec em `needsInput`, as duas bolinhas mostram o losango, o painel lista "R3 e R4" no motivo com um único botão "Responder na sessão", e o contador "Atenção" conta a spec uma vez. verificar: `flutter test test/features/board/canvas_view_test.dart` (a criar)
- [ ] [R7] Ao enviar uma mensagem numa sessão parada em `needsInput`, o anel e o selo do nó somem; se a sessão parar de novo sem concluir, voltam. verificar: `flutter test test/features/board/canvas_view_test.dart` (a criar, com `SessionManager` e `SpecRunner` falsos)
- [ ] [R7] Selecionar essa spec mostra no painel o motivo e a ação correta ("Responder na sessão", "Tentar de novo" ou "Abrir aprovações"), a mesma do cartão das Colunas. verificar: `flutter test test/features/board/canvas_view_test.dart` (a criar)
- [ ] [R7] O botão "Atenção · N" mostra o mesmo N do cabeçalho das Colunas, cada clique seleciona a próxima spec com atenção, e com N = 0 fica desabilitado. verificar: `flutter test test/features/board/canvas_view_test.dart` (a criar)
- [ ] [R7] O canvas não aprova nem nega nenhuma ferramenta: nenhum botão do canvas chama o aprovador de sessões. verificar: `flutter test test/features/board/canvas_view_test.dart` (a criar)
- [ ] [R1–R7] O código novo passa na análise estática e a suíte existente continua passando. verificar: `flutter analyze && flutter test`
- [ ] [R1, R2] Com 60 specs de exemplo, mover e dar zoom no canvas continua fluido, sem travar. verificar: manual (`flutter run -d linux`, Quadro → Canvas)
- [ ] [R7] Com uma sessão real parada pedindo aprovação, o canvas mostra o anel e o motivo e "Abrir aprovações" leva à fila certa. verificar: manual (`flutter run -d linux`, iniciar uma etapa que peça uma ferramenta, abrir Quadro → Canvas)
- [ ] [R3, R4] Num workspace com sessões reais de specs que usaram skills, o canvas mostra as skills certas e o cartão traz a descrição do `SKILL.md`. verificar: manual (`flutter run -d linux`, Quadro → Canvas, selecionar uma spec com sessões)

## Perguntas em aberto

- Specs empilhadas: com o autopilot, uma spec pode começar quando a dependência está em Review e sua branch nasce da branch da dependência (`SpecRunner.runNext`, `reviewUnblocks`). O Review já protege a ordem: `ReviewService.merge` recusa o merge da spec empilhada enquanto a dependência não foi mergeada ("faça o merge de SPEC-A primeiro") e, depois que a dependência é mergeada, `_closeSpec` religa a base das specs empilhadas para a branch principal. Não encontrei propagação automática de mudanças feitas na dependência durante o review para a spec empilhada. Esta spec **não** muda essa regra. Pergunta: o canvas deve mostrar a ligação empilhada de forma própria (tracejada) e avisar "faça o merge de SPEC-A antes" no painel, em vez de o usuário só descobrir ao tentar o merge?
- A visão se chama "Canvas" ou continua "Grafo"? A spec assume "Canvas" no rótulo e mantém as chaves de teste `board-view-graph`.
- Como mostrar specs `ideia`, `rascunho` e `arquivada`, que hoje não entram no quadro (`Nenhuma spec aprovada`)? A spec assume que continuam fora.
- A numeração de specs em `docs/specs/` repete SPEC-001 e SPEC-002 (a tela Sobre, GitHub/GitLab e a integração Codex). Renumerar antes de aprovar esta?
