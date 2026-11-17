---
id: SPEC-083
status: rascunho
tipo: recurso
---

# Spec a partir de um print

## Objetivo

Muita ideia de spec começa numa imagem. A pessoa vê o botão "Retomar" cortado no card do Quadro e tira um print. Ou vê, no app de outra empresa, uma tela de comparação que resolve um problema dela, e tira um print. Hoje, para virar spec, ela tem de descrever a imagem em palavras na Nova spec ("o botão da direita fica cortado quando o título é longo, na coluna Review, com a janela em 1366…"), e o planner nunca vê o que ela viu. O print se perde, e o mockup da spec, quando existe, é feito depois, à mão.

Esta spec deixa **colar uma captura de tela (Ctrl V)** na Nova spec:
- o print aparece como miniatura no campo da ideia, e a pessoa diz se é **um bug** (de uma tela deste projeto) ou **uma referência** (a tela de outro app);
- o planner do mini planejamento **vê a imagem** junto com a ideia e escreve a spec a partir dela, lendo o repositório como hoje;
- ao criar a spec, o print vai para **`docs/mockups/spec-0NN/`** e entra na spec como **mockup**, com uma descrição do que mostra;
- quando o print é de outro produto, ele é **só referência**: a spec descreve a função e o layout com as palavras e o visual do projeto, e **nunca copia a marca, o nome, o logotipo, os textos nem os ícones** do outro produto. O app confere isso antes de criar a spec.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/CPGpYsSQTNWjHkckZDjkhS). Capturas em `docs/mockups/spec-083/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-colar.png` | A Nova spec com o print colado: a miniatura, "Bug" ou "Referência", e o aviso de dados sensíveis | R1–R5 |
| `2-planejar.png` | O mini planejamento com o print: a conversa, o rascunho com a "Referência visual" e a guarda da marca | R6–R9 |
| `3-spec.png` | A spec criada: o print em `docs/mockups/spec-0NN/`, a seção "Referência visual" e a nota de referência | R10, R11 |
| `4-estados.png` | Sem `wl-paste`/`xclip`, imagem grande reduzida, limite de prints e a marca encontrada na spec | R2, R3, R4, R9 |

"Nimbo", nos mockups, é uma marca inventada para mostrar a guarda da marca; não é um produto real.

## Requisitos

### Colar o print

- R1 · **Ctrl V na Nova spec.** Com o foco no campo da ideia (ou em qualquer lugar da tela Nova spec fora de outro campo de texto), Ctrl V com uma **imagem** na área de transferência anexa a imagem como print. Com texto na área de transferência, Ctrl V cola o texto como hoje. Com os dois (alguns apps copiam a imagem e um nome), a imagem ganha e o texto é colado também. O print também entra arrastando um arquivo de imagem (PNG, JPEG, WebP, GIF) para o campo, como já entram PDF, Markdown e TXT (SPEC-057), e pelo botão "Anexar print…", ao lado de "Importar", que abre o seletor de arquivos filtrado para imagens.
- R2 · **Ler a imagem da área de transferência no Linux (P1).** O Flutter só lê texto da área de transferência. O app lê a imagem com `wl-paste --type image/png` no Wayland (`WAYLAND_DISPLAY` definido) e com `xclip -selection clipboard -t image/png -o` no X11, aceitando também `image/jpeg` e `image/webp` quando é o que a área tem (`wl-paste --list-types` e `xclip -t TARGETS`). Se a ferramenta não está instalada, Ctrl V com imagem mostra o aviso "Para colar imagens, instale o wl-clipboard (Wayland) ou o xclip (X11)", com o comando de instalação, e "Anexar print…" continua funcionando. A verificação do ambiente (`environment_check.dart`) passa a listar essa ferramenta como opcional.
- R3 · **Tamanho.** Um print com o lado maior acima de 1568 px é reduzido para 1568 px, mantendo a proporção, com `dart:ui` (decodificar com a largura alvo e gravar em PNG), antes de ir para o planner e para o repositório; a miniatura diz "1568 × 980 · reduzido de 2880 × 1800". Acima de 20 MB, ou um arquivo que não é imagem, é recusado com o motivo. Até **4 prints** por spec; o quinto mostra "No máximo 4 prints por spec".
- R4 · **A miniatura.** Cada print aparece embaixo do campo da ideia como um cartão: a miniatura (até 160 px de largura), o nome (`print-1.png`, `print-2.png` na ordem em que entraram), as dimensões, "Remover" (×) e "Ver" (abre o print em tamanho real num diálogo). Os prints ficam em `.promptorium/attachments/<data>/`, a pasta já ignorada pelo git dos anexos do Prompt (`attachments.dart`), até a spec ser criada ou o rascunho descartado; descartar apaga os arquivos. O rascunho guarda os caminhos em `SpecDraftData` (o JSON de `spec_drafts.data`), e reabrir o rascunho mostra os prints de novo.
- R5 · **Bug ou referência.** Cada print tem uma escolha obrigatória, em botões de rádio, antes de "Planejar a spec": **"Bug neste projeto"** (a tela é deste workspace e algo está errado nela) ou **"Referência de outro app"** (a tela é de outro produto e serve de ideia). Sem escolha, "Planejar a spec" fica desabilitado com a dica "Diga se cada print é um bug ou uma referência". O campo da ideia pode ficar vazio quando há print: a ideia passa a ser "o que o print mostra". Embaixo dos cartões, o aviso fixo: "O print vai para o repositório quando a spec for criada. Confira se ele não mostra senha, token, e-mail ou dado de cliente."

### Planejar com o print

- R6 · **O planner vê a imagem.** O primeiro turno do mini planejamento (`SpecPlanner._turn`) manda os prints como blocos `image` da mensagem (`ClaudeProcess.send(text, images:)`, o mesmo formato dos anexos do Prompt), antes do texto. Para isso, `runReadOnlyClaude` ganha o parâmetro `images`. O texto do turno diz, para cada print, o nome e se é bug ou referência. Nos turnos seguintes (com `--resume`), o planner já tem a imagem na conversa e o app não manda de novo.
- R7 · **O que o planner faz com cada tipo.** O prompt do planner (`specPlannerSystemPrompt`) ganha regras para prints:
  - **Bug**: descrever o defeito que o print mostra (o que está errado, onde, em que estado da tela), achar no repositório a tela e os arquivos prováveis, e escrever requisitos de correção com critérios verificáveis; a spec criada tem `tipo: bug`;
  - **Referência**: extrair só a **ideia** (a função, a organização da tela, o fluxo), adaptá-la ao projeto e ao visual dele (as cores, as fontes e os componentes do repositório), e escrever os requisitos como algo do projeto. **Proibido** pôr na spec a marca, o nome do produto ou da empresa, o logotipo, os slogans e textos da interface, os ícones próprios e as cores de marca do outro produto. Onde precisar se referir a ele, a spec diz "o app de referência".
  
  O esquema de resposta (`specPlannerSchema`) ganha, por print, `descricao` (uma frase do que o print mostra, que vira o texto alternativo) e `marcas` (os nomes de produto, empresa e marca que o planner leu no print; vazio quando não há).
- R8 · **O rascunho mostra os prints.** O painel "Rascunho da spec" ganha a seção **"Referência visual"**, com a miniatura de cada print, o tipo (Bug ou Referência) e a descrição que o planner escreveu, que a pessoa pode editar. Num print de referência, a seção mostra a nota "Só referência: a spec não copia a marca, o nome, os textos nem os ícones do app de referência."
- R9 · **A guarda da marca.** O app junta as `marcas` de todos os prints de referência e procura cada uma (sem diferenciar maiúsculas, acentos e palavras inteiras) no título, no objetivo, nos requisitos, no fora do escopo e nas descrições do rascunho. Cada ocorrência:
  - aparece no rascunho como aviso âmbar, "A spec cita “Nome” do app de referência", com o trecho destacado;
  - **bloqueia "Criar spec"** até sair, com a dica "Tire as citações ao app de referência (2)";
  - tem o botão "Pedir ao planner para reescrever", que manda um turno pedindo para trocar as citações por termos do projeto.
  
  O mesmo vale para a spec já criada: o `spec_lint.dart` ganha o aviso "Cita o app de referência" quando a spec tem prints de referência e o texto cita uma das marcas guardadas (o app guarda as marcas no `docs/mockups/spec-0NN/index.json`, ao lado do índice do protótipo).

### A spec criada

- R10 · **O print vai para `docs/mockups/`.** "Criar spec" copia cada print para `docs/mockups/spec-0NN/print-1.png`, `print-2.png`… (a pasta do protótipo, `mockupDir`, SPEC-022), no mesmo momento em que grava o arquivo da spec, e apaga os temporários. Se a cópia falha, a spec não é criada e o rascunho fica, como já acontece quando a pasta não aceita o arquivo. A tela de protótipo continua lendo só os `R<n>-*.html` da pasta; os `print-*.png` não viram telas do protótipo.
- R11 · **A seção na spec.** O texto da spec (`specTextFromDraft`) ganha, depois do Objetivo, a seção **"## Referência visual"**: para cada print, a imagem em markdown com o caminho relativo à spec e a descrição como texto alternativo (`![Print 1: o card SPEC-073 com o botão Retomar cortado na coluna Review](../mockups/spec-073/print-1.png)`), o tipo, e, num print de referência, a linha "Referência de outro app: só a ideia. A spec não copia a marca, o nome, os textos nem os ícones dele." A pré-visualização da spec na tela Specs mostra a imagem (o `AppMarkdown` resolve o caminho relativo ao arquivo da spec).

### Acessibilidade

- R12 · Os cartões dos prints entram na ordem do Tab; "Remover" e "Ver" têm rótulo ("Remover print 1"); a escolha Bug/Referência é um grupo de rádio com nome ("Tipo do print 1"); a miniatura tem como texto alternativo o nome e, depois do planejamento, a descrição. Colar um print anuncia "Print 1 anexado, 1568 por 980".

## Fora do escopo

- Colar imagens no Prompt, nas Sessões e no refinamento (o leitor da área de transferência fica pronto para isso, mas esta spec só liga na Nova spec).
- Marcar ou borrar uma área do print, ou escrever em cima dele.
- Gerar telas novas (HTML) a partir do print. O protótipo continua sendo a SPEC-022, e pode partir da spec criada.
- Detectar sozinho se o print é bug ou referência.
- Tirar o print pelo app (captura de tela própria).
- Vídeo ou GIF animado como referência (um GIF entra como a primeira imagem).
- Esconder dados sensíveis automaticamente; o app só avisa (R5).

## Decisões em aberto

- P1 · **Como ler a imagem da área de transferência no Linux.** (a) `wl-paste` e `xclip` pela linha de comando; (b) um plugin com código nativo (`super_clipboard`, `pasteboard`); (c) um canal de plataforma próprio com GTK. **Recomendação: (a).** O app já chama muitas ferramentas pelo `ProcessRunner` e já confere o ambiente. As duas ferramentas são pequenas e estão nos repositórios de todas as distribuições. Um plugin nativo traria compilação extra (o `super_clipboard` precisa de Rust) para uma leitura só. Sem a ferramenta, o arrastar e o "Anexar print…" continuam funcionando.
- P2 · **Quantos prints por spec.** **Recomendação: até 4.** Um bug costuma ter um ou dois (antes e depois, ou a tela e o erro), e uma referência, uma ou duas telas. Mais que isso pesa no turno do planner e no repositório.
- P3 · **Reduzir a imagem.** Mandar como veio ou reduzir para 1568 px no lado maior. **Recomendação: reduzir.** É o tamanho em que o modelo lê a imagem sem perder detalhe. Um print de tela 4K pesaria vários MB no repositório e no turno, sem ganho.
- P4 · **Bug ou referência: escolha obrigatória.** **Recomendação: obrigatória, por print.** A regra da marca (R7, R9) só vale para referência, e o tipo da spec (`bug`) só para bug. Adivinhar erraria justo no caso que importa: um print de outro app tratado como bug deste.
- P5 · **A guarda da marca bloqueia ou só avisa.** **Recomendação: bloqueia "Criar spec"**, com o botão para o planner reescrever. A regra é do usuário ("proibir copiar a marca"); um aviso que deixa passar vira hábito de ignorar. A spec criada mantém o aviso no lint, para quem editar depois.
- P6 · **Onde guardar as marcas encontradas.** Na spec (frontmatter), no banco ou no `index.json` da pasta de mockups. **Recomendação: no `index.json` da pasta**, que já é do app (SPEC-022). Na spec, o nome da marca ficaria escrito justamente onde não pode aparecer; no banco, se perderia ao abrir o repositório em outro computador.
- P7 · **Nome dos arquivos.** `print-1.png` ou o nome original. **Recomendação: `print-N`**, com a extensão do formato. O nome original de uma captura ("Captura de tela de 2026-11-16 14-32-10.png") tem espaços e data, e às vezes o nome do app de onde veio.

## Design

Canvas para validar: [Spec a partir de um print](https://claude.ai/artifact/CPGpYsSQTNWjHkckZDjkhS). Quatro artboards: colar, planejar, a spec criada e os estados.

### O que já existe

- `lib/features/specs/new_spec_view.dart`: a Nova spec (`_Idea`, com o `IdeaField`, "Planejar a spec" e "Criar em branco"; `_MiniPlanning` e `_DraftPanel`, o rascunho com título, objetivo, requisitos, fora do escopo e perguntas).
- `lib/features/ideas/widgets/idea_field.dart` (SPEC-057): o campo da ideia, com o arrastar (`DropTarget`) e "Importar" (PDF, Markdown, TXT).
- `lib/features/prompt/attachments.dart`: `imageMediaType`, `maxImageBytes`, os anexos de imagem como `ImagePart` e a pasta `.promptorium/attachments/` ignorada pelo git.
- `lib/core/claude/claude_process.dart`: `ImagePart` e `send(text, images:)`, que já monta os blocos `image`.
- `lib/core/claude/readonly_run.dart`: `runReadOnlyClaude`, usado pelo planner; hoje manda só o texto.
- `lib/features/specs/spec_planner.dart`: `SpecPlanner` (`begin`, `_turn`, `create`), `specPlannerSystemPrompt`, `specPlannerSchema`.
- `lib/features/specs/spec_draft.dart`: `SpecDraftData` e `specTextFromDraft`.
- `lib/features/specs/prototype/prototype_files.dart`: `mockupDir(code)` e o `index.json` da pasta.
- `lib/features/specs/spec_lint.dart`: os avisos de estrutura da spec (SPEC-023).
- `lib/features/project/environment_check.dart`: as ferramentas do ambiente.

### Componentes

- **`lib/core/clipboard/clipboard_image.dart`**: `ClipboardImageReader` (Wayland ou X11, os tipos disponíveis, a leitura, a falta da ferramenta), atrás de um provider para os testes (R2).
- **`lib/features/specs/spec_prints.dart`**: `SpecPrint` (caminho temporário, nome, tipo, dimensões, descrição, marcas), `preparePrint(bytes)` (validar, reduzir com `dart:ui`, gravar no temporário), `copyPrintsToMockups(...)` e `brandMentions(draft, marcas)`, funções testáveis (R3, R4, R9, R10).
- **`lib/features/specs/widgets/print_cards.dart`**: os cartões com a miniatura, "Ver", "Remover" e o grupo Bug/Referência (R4, R5, R12).
- No `IdeaField`: o atalho Ctrl V (`Shortcuts`/`Actions` no campo e na tela) e as imagens no `DropTarget` (R1).
- No `_DraftPanel`: a seção "Referência visual" e os avisos da marca (R8, R9).

### Arquivos tocados

- `lib/features/specs/new_spec_view.dart`, `lib/features/ideas/widgets/idea_field.dart`.
- `lib/features/specs/spec_planner.dart`, `lib/features/specs/spec_draft.dart`, `lib/core/claude/readonly_run.dart`.
- `lib/features/specs/spec_service.dart` (copiar os prints junto com a criação), `lib/features/specs/prototype/prototype_files.dart` (ler as marcas do `index.json`), `lib/features/specs/spec_lint.dart`.
- `lib/features/prompt/attachments.dart` (reaproveitar `imageMediaType` e a pasta temporária), `lib/features/project/environment_check.dart`.
- `lib/ui/widgets/markdown/` (`AppMarkdown`, SPEC-077): imagem com caminho relativo ao arquivo da spec.
- Novos: `lib/core/clipboard/clipboard_image.dart`, `lib/features/specs/spec_prints.dart`, `lib/features/specs/widgets/print_cards.dart`; testes em `test/features/specs/prints/`.

### Migração

Não. Os prints do rascunho ficam no JSON que já existe em `spec_drafts.data`; as marcas, no `index.json` da pasta de mockups.

### Testes

- `ClipboardImageReader`: escolhe `wl-paste` ou `xclip` pelo ambiente, lê `image/png` e cai para `image/jpeg`; sem a ferramenta, devolve o motivo; com texto, não devolve imagem.
- `preparePrint`: reduz para 1568 px mantendo a proporção, recusa acima de 20 MB e o que não é imagem; o quinto print é recusado.
- `SpecDraftData`: os prints entram e saem do JSON; descartar apaga os temporários.
- `SpecPlanner`: o primeiro turno manda os blocos `image` com o tipo de cada print; os seguintes não mandam de novo; o esquema lê `descricao` e `marcas`.
- `brandMentions`: acha a marca no título, no objetivo e nos requisitos, sem diferenciar maiúsculas e acentos e só em palavras inteiras; "Criar spec" fica bloqueado com citação.
- `specTextFromDraft`: a seção "Referência visual" com o caminho relativo, a descrição e a nota de referência; `tipo: bug` com print de bug.
- `copyPrintsToMockups`: grava `print-N` em `docs/mockups/spec-0NN/`, e a falha da cópia não cria a spec.
- Widgets: Ctrl V com imagem anexa e com texto cola; o arrastar aceita imagem; "Planejar a spec" exige o tipo; o aviso de dados sensíveis; os rótulos de acessibilidade.

## Critérios de aceite

- [ ] Ctrl V com imagem anexa o print, com texto cola o texto, e o arrastar e "Anexar print…" aceitam imagens [R1] verificar: flutter test test/features/specs/prints/print_paste_test.dart
- [ ] A imagem é lida com `wl-paste` ou `xclip`, e a falta da ferramenta mostra o aviso com o comando [R2] verificar: flutter test test/core/clipboard/clipboard_image_test.dart
- [ ] O print grande é reduzido para 1568 px, o arquivo inválido é recusado e o quinto print também [R3] verificar: flutter test test/features/specs/prints/spec_prints_test.dart
- [ ] Os cartões mostram a miniatura, Ver e Remover, ficam no rascunho e somem ao descartar [R4] verificar: flutter test test/features/specs/prints/print_paste_test.dart
- [ ] "Planejar a spec" exige Bug ou Referência em cada print, e o aviso de dados sensíveis aparece [R5, R12] verificar: flutter test test/features/specs/prints/print_paste_test.dart
- [ ] O primeiro turno do planner leva as imagens e o tipo; a resposta traz a descrição e as marcas [R6, R7] verificar: flutter test test/features/specs/prints/spec_planner_prints_test.dart
- [ ] O rascunho mostra a Referência visual, e a marca do app de referência no texto bloqueia "Criar spec" [R8, R9] verificar: flutter test test/features/specs/prints/brand_guard_test.dart
- [ ] Criar a spec grava os prints em `docs/mockups/spec-0NN/` e a seção "Referência visual" no texto [R10, R11] verificar: flutter test test/features/specs/prints/spec_prints_test.dart
- [ ] No app, um print de bug colado com Ctrl V e um print de referência de outro app viram duas specs com o mockup em `docs/mockups/`, e a de referência não cita a marca do outro app [R1–R11] verificar: manual (app isolado com `XDG_DATA_HOME`, prints em `docs/mockups/spec-083/app/`)
- [ ] O projeto compila e a análise estática passa [R1–R12] verificar: flutter analyze
