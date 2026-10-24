---
id: SPEC-022
status: rascunho
---

# Protótipo de telas da spec

## Objetivo

Hoje uma spec chega à execução só com texto: requisitos, design e etapas. As telas que o agente vai construir só aparecem depois, já em código. Os mockups em `docs/mockups/` são feitos à parte, fora do app, e nada liga uma tela aprovada à etapa que a implementa.

Esta spec acrescenta à tela Specs um modo **Protótipo**, em que o agente gera uma tela por requisito como HTML local, o usuário pede variações, compara e aprova uma. A tela aprovada entra na seção `## Protótipo` da spec e vai como referência para a etapa do requisito na execução.

- Protótipo de referência: canvas "Promptorium · Protótipo de telas" (artboards "1 · Spec no modo Protótipo" e "2 · Comparar variações e aprovar").
- As telas são HTML autocontido em `docs/mockups/<código-da-spec>/`. O app mostra uma miniatura PNG gerada por um navegador headless e abre o HTML no navegador do sistema. Não há webview embutida.
- Fora do escopo: edição visual das telas no app, comentários ancorados em pontos da tela, publicação no claude.ai e protótipos navegáveis entre telas.

## Requisitos

- R1 · O sistema deve oferecer na tela Specs um quarto modo de editor, "Protótipo", ao lado de Editar, Dividido e Visualizar.
- R2 · Quando o usuário acionar "Gerar telas da spec", o sistema deve rodar o agente para criar um arquivo HTML autocontido por requisito com interface em `docs/mockups/<código>/` (nome `R<n>-<slug>.html`), no visual do Promptorium (tokens de `lib/ui/theme/tokens.dart`), sem alterar outros arquivos.
- R3 · Enquanto o modo Protótipo estiver aberto, o sistema deve mostrar as telas da spec num canvas com zoom, cada uma rotulada com o requisito correspondente, e marcar as que estão sendo geradas.
- R4 · Quando um HTML de tela for criado ou alterado, o sistema deve gerar a miniatura PNG com o navegador headless (Chrome/Chromium) no tamanho 1440×900 e atualizar o canvas.
- R5 · Se não houver navegador headless disponível, o sistema deve mostrar no lugar da miniatura um cartão com o nome do arquivo e a ação "Abrir no navegador", e avisar uma vez como instalar um.
- R6 · Quando o usuário clicar duas vezes numa tela (ou acionar "Abrir no navegador"), o sistema deve abri-la no navegador padrão do sistema.
- R7 · O sistema deve oferecer no modo Protótipo um painel "Pedir ao Claude" em que o usuário seleciona uma ou mais telas e envia um pedido. O agente então cria uma nova variação de cada tela selecionada (`R<n>-<slug>.<letra>.html`), sem sobrescrever as existentes.
- R8 · Quando um requisito tiver duas ou mais variações, o sistema deve oferecer "Comparar variações", que mostra as variações lado a lado com a descrição e o horário de cada uma.
- R9 · Quando o usuário acionar "Aprovar e anexar à spec" numa variação, o sistema deve gravar na seção `## Protótipo` da spec a linha `- R<n> → docs/mockups/<código>/<arquivo>.html` (substituindo a aprovação anterior do mesmo requisito), sem mudar o status da spec.
- R10 · Quando uma etapa da spec for executada e o requisito dela tiver tela aprovada em `## Protótipo`, o sistema deve incluir o caminho da tela no prompt da etapa como referência visual a seguir.
- R11 · O painel deve mostrar a aba "Versões" com as variações de cada requisito e qual está aprovada, e permitir remover uma variação não aprovada.
- R12 · Os controles do modo Protótipo (modo, gerar, comparar, aprovar, enviar pedido) devem ser operáveis por teclado, com foco visível e rótulo acessível.

## Design

### O que já existe

- `lib/features/specs/specs_screen.dart`: `SpecViewMode` (l.34: Editar / Dividido / Visualizar); `_SpecsScreenState.build` (l.529) monta lista + `_Shell(_Header, _EditorBody)` + painel lateral (`SpecStepsPanel`, l.634); `_Header` (l.742) com `_ModeSwitch` (l.956, `InkWell` por modo, chave `spec-mode-<nome>`) e as ações `SmallButton`; `_EditorBody` (l.1000) escolhe editor/preview por modo; `_design` (l.429) mostra como uma ação do cabeçalho chama um serviço do agente; `_save` (l.295) grava pelo `specServiceProvider.save` (l.276 de `spec_service.dart`, que não muda o status).
- `lib/features/specs/spec_design.dart`: `SpecDesigner.generate` (l.86) roda `runReadOnlyClaude` com `--json-schema` e lê `structuredOutput`.
- `lib/core/claude/readonly_run.dart`: `runReadOnlyClaude` (l.56) aceita `ClaudeOptions` com `tools` próprios (l.119: só usa `readOnlyTools` quando a lista vem vazia), `--strict-mcp-config`, `runSettingsFile` (extensões desligadas, SPEC-017 R2) e **nega toda `PermissionRequest`** (l.150). `ClaudeOptions.allowedTools` (`claude_args.dart` l.80) vira `--allowedTools`.
- `lib/core/providers/claude_code_provider.dart` l.30/l.46: `readOnlyDisallowedTools` e `readOnlyTools`.
- `lib/core/fs/dir_watcher.dart`: `DirWatcher` (não recursivo, com debounce e `update`), usado por `workspace_watcher.dart`.
- `lib/core/process/process_runner.dart`: `processRunnerProvider` (`ProcessRunner = (exe, args)`), injetável nos testes. `xdg-open` já abre URLs (`sessions_screen.dart` l.431, `installer.dart` l.180); não há `url_launcher`.
- `lib/features/specs/spec_file.dart`: `SpecDocument.section` (l.210), `stepPlans` (l.250), `withDesign` (l.282) e `_withSection` (l.295), que troca o corpo de uma seção `##` ou a cria depois de outra, sem tocar no frontmatter.
- `lib/features/board/spec_runner.dart`: `specStepPrompt` (l.224), `specContinuePrompt` (l.372) e `focusedSpecText` (l.106, F7: trecho da spec por etapa).
- `lib/features/board/widgets/spec_canvas.dart` l.1164 `_DotGrid` (fundo pontilhado); `lib/features/sessions/widgets/session_style.dart` l.83 `SmallButton` (com `semanticLabel`/`focusColor`, SPEC-021 R11) e l.157 `AmberButton`.
- `lib/ui/theme/tokens.dart`: `AppColors`, `AppFonts` (cores e fontes que o prompt de geração repassa).

Arquivos novos ficam em `lib/features/specs/prototype/`: `prototype_files.dart` (nomes, índice), `prototype_thumbnails.dart` (headless), `prototype_service.dart` (agente e estado) e `prototype_view.dart` (canvas, painel e comparação).

### R1 · Modo Protótipo
- `SpecViewMode.prototype('Protótipo')`. Com esse modo, `_EditorBody` dá lugar a `PrototypeView` (canvas + painel) e o painel lateral da direita (etapas/subagentes) é substituído pelo painel "Pedir ao Claude / Versões". O controller do editor continua carregado (a view lê os requisitos e grava `## Protótipo` por ele).
- No cabeçalho, em modo Protótipo, as ações Salvar/Refinar/Gerar design/Aprovar dão lugar a "Comparar variações" (`proto-compare`) e "Gerar telas da spec" (`proto-generate`, `AmberButton`), como no protótipo.

### R2 · Gerar telas (escrita restrita à pasta)
- Pasta: `docs/mockups/<código em minúsculas>/` (ex.: `docs/mockups/spec-022/`, igual às pastas `spec-016`… existentes).
- `PrototypeService.generate` monta `prototypeGeneratePrompt` (spec inteira, lista de requisitos, telas já existentes que **não** devem ser sobrescritas, nomes `R<n>-<slug>.html`, HTML autocontido sem rede, tokens de `AppColors`/`AppFonts` com os valores hex, e `docs/mockups/Specs.dc.html` só como referência de leitura).
- Execução: `runReadOnlyClaude` com `providerId: 'claude'`, `tools: [Read, Glob, Grep, Write, Edit]` (sem Bash), `allowedTools: ['Edit(<pasta>/**)']` e `permissionMode: default`. A regra `Edit(...)` vale para Write/Edit; qualquer escrita fora da pasta vira `PermissionRequest`, que `runReadOnlyClaude` nega (parâmetro novo `denyMessage` explica o motivo ao agente). Conferido no CLI 2.1.310: `--tools Read,Write --allowedTools 'Edit(docs/mockups/x/**)'` grava dentro da pasta e a escrita fora aparece em `permission_denials`.
- Proteção extra: antes da execução o serviço guarda o conteúdo das telas existentes; depois, restaura qualquer uma alterada ou apagada (R7: "sem sobrescrever").
- `--json-schema` com `{telas: [{arquivo, requisito, descricao}], resposta}`: o app (não o agente) grava `index.json` na pasta com descrição e horário de cada tela e o histórico do painel. Arquivos citados que não existem são ignorados.
- Uma execução por pedido (decisão b); enquanto há uma em andamento para a spec, Gerar/Enviar ficam desabilitados. Timeout de 15 min, orçamento de US$ 3.
- O executor do agente é injetável (`prototypeAgentProvider`) para os testes.

### R3 · Canvas
- `PrototypeScreensNotifier` (família por `(raiz do workspace, código)`) lista os `.html` da pasta (`parseMockupName`: `^(R\d+)-(slug)(\.letra)?\.html$`; sem letra = variação A), lê `index.json` e observa a pasta com `DirWatcher` (e `docs/`, `docs/mockups/` enquanto ela não existe).
- `PrototypeView`: linha de status `docs/mockups/spec-022/ · 3 telas · salvo` (ou `· gerando…`), zoom próprio −/80%/+ (`proto-zoom-out`/`proto-zoom-in`, 40–200 %, muda o tamanho dos cartões), fundo pontilhado e `Wrap` de cartões `R1 · Lista de prompts` (slug humanizado; variação ≠ A ganha ` · B`). Selecionado = borda âmbar (clique seleciona, Ctrl+clique soma). Em geração: cartão com borda tracejada verde-água "Gerando variação B de R1…" ou "Gerando telas da spec…" (`prototypeJobsProvider`, estado global para sobreviver à troca de seção).

### R4 · R5 · Miniaturas
- `PrototypeThumbnails` (`prototype_thumbnails.dart`) recebe `ProcessRunner`. `findBrowser()` testa `google-chrome`, `google-chrome-stable`, `chromium`, `chromium-browser` com `which` (uma vez por instância). `thumbnail(html, size)` roda `<browser> --headless=new --disable-gpu --hide-scrollbars --no-first-run --no-default-browser-check --user-data-dir=<cache>/profile --screenshot=<png> --window-size=1440,900 file://<html>`.
- Cache fora do repo: `$XDG_CACHE_HOME` ou `~/.cache/promptorium/mockups/<sha1(caminho|mtime|tamanho|tamanho da janela)>.png` (`prototypeCacheDirProvider`). Arquivo alterado = chave nova = miniatura nova.
- O notifier gera a miniatura dos arquivos sem PNG em cache, uma por vez, a cada mudança vista pelo watcher (R4).
- Sem navegador (R5): o cartão mostra o nome do arquivo e "Abrir no navegador"; o aviso (snack com "instale google-chrome ou chromium") sai uma vez, gravado em `app_settings` (`prototype.headlessWarned`).

### R6 · Abrir no navegador
- Duplo clique no cartão ou "Abrir no navegador" chama `xdg-open <arquivo>` pelo `processRunnerProvider`.

### R7 · Pedir ao Claude
- Aba "Pedir ao Claude": histórico do `index.json` (pedido, resposta, chips dos arquivos), campo "Pedido para as telas selecionadas" (`proto-request`), "Selecionada: R1" e "Enviar" (`proto-send`).
- Para cada requisito selecionado o app calcula o próximo nome livre (`nextVariationName`: `R1-lista.html` → `R1-lista.b.html` → `.c`…) e o prompt pede exatamente esses arquivos, partindo da tela selecionada como base. Mesma restrição de escrita e mesma restauração do R2.

### R8 · Comparar variações
- `PrototypeCompare` substitui o canvas: "← Protótipo", `SPEC-022 · R1 · Lista de prompts`, toggle 1440 / 1100×700 (miniaturas no tamanho escolhido), grade com "Variação A/B…", descrição e horário (`index.json`, senão o mtime), escolhida com borda âmbar e selo "escolhida", "Usar esta" e "Aprovar e anexar à spec". Faixa verde-água com o texto do protótipo e "Ver na spec" (muda para Visualizar).
- Alvo: o requisito da tela selecionada (ou o primeiro com 2+ variações); "Comparar variações" só habilita com 2+.

### R9 · `## Protótipo`
- `SpecDocument.prototypes` (`Map<R, caminho>`) lê as linhas `- R<n> → <caminho>`; `withPrototype(req, caminho)` regrava a seção ordenada por requisito com `_withSection` (depois de Etapas, senão Design, senão Requisitos). Só o corpo muda; o frontmatter e o status ficam iguais.
- Na tela: aplica no texto do disco e grava por `specService.save`; o editor recebe a mesma linha. Se havia alterações não salvas, elas continuam só no editor. Spec iniciada (bloqueada) não aprova.

### R10 · Prompt da etapa
- `prototypeReferences(specText, todo)` devolve as linhas `R1: docs/mockups/…` dos requisitos da etapa; `specStepPrompt` e `specContinuePrompt` acrescentam "Telas aprovadas (referência visual a seguir; abra o HTML)" só quando há alguma.

### R11 · Versões
- Aba "Versões": variações agrupadas por requisito, selo "aprovada" na que está em `## Protótipo`, "Remover" (`proto-remove-<arquivo>`) com confirmação apaga o HTML e a entrada do `index.json`; a aprovada não tem o botão.

### R12 · Teclado e acessibilidade
- Itens do `_ModeSwitch` com `Semantics(button, selected, label)`; botões com `semanticLabel`; cartões do canvas são `InkWell` focáveis (Enter/Espaço selecionam) com rótulo `Tela R1 · …`; abas, zoom, "Usar esta", "Aprovar…", "Enviar" e "Remover" também. Foco visível pelo `focusColor` âmbar.

### Riscos
- Agente ignora os nomes pedidos: o app só registra arquivos que existem e casam com o padrão.
- Chrome aberto pelo usuário: `--user-data-dir` próprio evita usar o perfil em uso.
- Testes: sem processo real (agente e headless injetados); arquivos reais em diretório temporário com `settleIo`; largura ≥ 1440.

## Etapas

- R1 → lib/features/specs/specs_screen.dart, lib/features/specs/prototype/prototype_view.dart · verificar: `flutter test test/features/specs/prototype_view_test.dart`
- R2 → lib/features/specs/prototype/prototype_service.dart, lib/core/claude/readonly_run.dart · verificar: `flutter test test/features/specs/prototype_service_test.dart`
- R3 → lib/features/specs/prototype/prototype_files.dart, lib/features/specs/prototype/prototype_service.dart, lib/features/specs/prototype/prototype_view.dart · verificar: `flutter test test/features/specs/prototype_view_test.dart`
- R4 → lib/features/specs/prototype/prototype_thumbnails.dart, lib/features/specs/prototype/prototype_service.dart · verificar: `flutter test test/features/specs/prototype_thumbnails_test.dart`
- R5 → lib/features/specs/prototype/prototype_thumbnails.dart, lib/features/specs/prototype/prototype_view.dart · verificar: `flutter test test/features/specs/prototype_view_test.dart`
- R6 → lib/features/specs/prototype/prototype_view.dart
- R7 → lib/features/specs/prototype/prototype_files.dart, lib/features/specs/prototype/prototype_service.dart, lib/features/specs/prototype/prototype_view.dart · verificar: `flutter test test/features/specs/prototype_service_test.dart`
- R8 → lib/features/specs/prototype/prototype_view.dart · verificar: `flutter test test/features/specs/prototype_view_test.dart`
- R9 → lib/features/specs/spec_file.dart, lib/features/specs/specs_screen.dart · verificar: `flutter test test/features/specs/prototype_files_test.dart`
- R10 → lib/features/board/spec_runner.dart · verificar: `flutter test test/features/board/spec_runner_test.dart`
- R11 → lib/features/specs/prototype/prototype_view.dart · verificar: `flutter test test/features/specs/prototype_view_test.dart`
- R12 → lib/features/specs/specs_screen.dart, lib/features/specs/prototype/prototype_view.dart · verificar: `flutter test test/features/specs/prototype_view_test.dart`

## Critérios de aceite

- [ ] [R1] A tela Specs mostra o modo "Protótipo" e alternar para ele exibe o canvas e o painel. verificar: `flutter test test/features/specs`
- [ ] [R2] "Gerar telas da spec" roda o agente com um prompt que pede um HTML por requisito em `docs/mockups/<código>/` e restringe a escrita a essa pasta. verificar: `flutter test test/features/specs`
- [ ] [R3] Com arquivos em `docs/mockups/<código>/`, o canvas mostra uma tela por arquivo rotulada pelo requisito, e a tela em geração aparece marcada. verificar: `flutter test test/features/specs`
- [ ] [R4] Criar ou alterar um HTML dispara a geração da miniatura com o comando headless esperado e o canvas passa a mostrá-la. verificar: `flutter test test/features/specs`
- [ ] [R5] Sem navegador headless, aparece o cartão com "Abrir no navegador" e o aviso só uma vez. verificar: `flutter test test/features/specs`
- [ ] [R6] Clicar duas vezes numa tela abre o arquivo no navegador padrão (verificação manual).
- [ ] [R7] Enviar um pedido com R1 selecionada cria `R1-<slug>.b.html` e mantém o arquivo original. verificar: `flutter test test/features/specs`
- [ ] [R8] Com duas variações de R1, "Comparar variações" mostra as duas lado a lado. Com uma só, a ação fica desabilitada. verificar: `flutter test test/features/specs`
- [ ] [R9] Aprovar uma variação grava a linha em `## Protótipo`, aprovar outra do mesmo requisito substitui a linha e o status da spec não muda. verificar: `flutter test test/features/specs`
- [ ] [R10] O prompt da etapa de um requisito com tela aprovada cita o caminho do HTML, e o de um requisito sem tela não cita nada. verificar: `flutter test test/features/board`
- [ ] [R11] A aba "Versões" lista as variações, marca a aprovada e remove uma não aprovada. verificar: `flutter test test/features/specs`
- [ ] [R12] Os controles recebem foco por Tab, acionam com Enter/Espaço e têm rótulo acessível. verificar: `flutter test test/features/specs`
- [ ] [R1–R12] A análise estática e a suíte passam. verificar: `flutter analyze && flutter test`

## Decisões

- Renderização: HTML local com miniatura PNG gerada por navegador headless. Sem webview e sem claude.ai.
- Escopo da primeira versão: gerar, variar, comparar e aprovar. A aba "Comentários" do protótipo fica de fora (comentários ancorados estão fora do escopo).
- (Pergunta 1) O prompt de geração usa os tokens de `lib/ui/theme/tokens.dart` (cores e tipografia) e cita `docs/mockups/Specs.dc.html` só como referência visual de leitura.
- (Pergunta 2) Uma única execução do agente por pedido, sem paralelizar.
- (Pergunta 3) A pasta `docs/mockups/<código>/` é commitada junto com a spec, como os mockups existentes.
- A escrita do agente fica restrita à pasta pela regra `Edit(<pasta>/**)` em `--allowedTools`, com `--tools` sem Bash; o resto é negado pelo app.
- Miniaturas ficam em cache fora do repositório (`~/.cache/promptorium/mockups/`); descrições, horários e histórico ficam em `docs/mockups/<código>/index.json`, sem migração de schema.

## Perguntas em aberto

- Nenhuma.
