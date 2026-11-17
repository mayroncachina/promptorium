---
id: SPEC-078
status: aprovada
tipo: melhoria
depende-de: SPEC-077
issue: 269
versão: 0.19.0
---

# Snippets salvos

## Objetivo

O Claude responde com uma query, um script ou um comando que a pessoa vai usar de novo. Com a SPEC-077, todo bloco de código ganhou uma barra com a linguagem e o botão **Copiar**. Copiar resolve uma vez. Na semana seguinte, a pessoa precisa da mesma query e tem de achar a conversa, rolar até a resposta certa e copiar de novo, ou pedir ao Claude que escreva tudo outra vez.

Exemplo: na conversa "Pedidos atrasados no DBeaver", o Claude montou a query de 17 linhas que lista, por cliente, os pedidos atrasados há mais de 3 dias. A pessoa testou no DBeaver e funcionou. Dois dias depois, o time de suporte pede o mesmo relatório. A conversa já está lá embaixo na lista, o título não lembra "query", e entre a pergunta e a query há outras três respostas. A pessoa só quer digitar "atrasados" e colar.

Esta spec:
- põe um botão **Salvar** na barra do bloco de código, ao lado do Copiar, que guarda o bloco como **snippet do projeto**, com um nome;
- mostra os snippets na **paleta (Ctrl K)**, onde Enter copia e Ctrl+Enter insere no composer;
- dá aos snippets uma seção no painel lateral do Prompt e um diálogo **Snippets** para buscar, editar, renomear e excluir.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/GxygfLvsPiwVLJVUmRSs14). Capturas em `docs/mockups/spec-078/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-salvar.png` | A resposta no Prompt com a query, o botão Salvar na barra, o balão "Salvar snippet" aberto e um bloco já salvo ("✓ Salvo"), com o nome sugerido | R1–R4 |
| `2-paleta.png` | Ctrl K com `$atras`: o grupo Snippets, a prévia do código e as teclas Enter copiar · Ctrl+Enter inserir | R6–R8 |
| `3-gerenciar.png` | O diálogo Snippets: lista com busca à esquerda, o snippet aberto para editar à direita, a origem e as ações | R9–R12 |
| `4-painel-e-composer.png` | A seção Snippets no painel do Prompt e o snippet inserido no composer como bloco cercado | R5, R8 |

Issue: [#269](https://github.com/mayroncachina/promptorium/issues/269) (sub-issue de [#268](https://github.com/mayroncachina/promptorium/issues/268))

## Requisitos

### Salvar

- R1 · **Botão Salvar no bloco.** A barra do bloco de código (SPEC-077 R1) ganha um botão **Salvar**, com ícone de marcador e texto, à esquerda do Copiar. Ele aparece só onde o bloco veio de uma conversa ou sessão de um workspace: as respostas da timeline (Sessões, Prompt e a janela ao vivo da etapa) e o plano pronto. Na tela Specs, nas pré-visualizações e no Sobre a barra continua só com o Copiar. A dica diz "Salvar como snippet do projeto". O rótulo semântico é "Salvar código SQL como snippet". O botão entra na ordem do Tab logo antes do Copiar.
- R2 · **Balão "Salvar snippet".** Clicar em Salvar abre um balão preso ao botão (não um diálogo modal: a resposta continua à vista), com:
  - **Nome**, já preenchido e selecionado (R3), obrigatório, até 80 caracteres;
  - **Linguagem**, com a palavra da cerca (`sql`) e a lista de `CodeLanguage` para trocar;
  - **Descrição**, opcional, uma linha;
  - a **prévia** do código com realce, só leitura, até 12 linhas e "+ N linhas";
  - a origem: "da conversa *Pedidos atrasados no DBeaver* · 14:04";
  - **Salvar** (Enter) e **Cancelar** (Esc).
  
  O código salvo é o do bloco inteiro e exato, o mesmo que o Copiar leva (SPEC-077 R2).
- R3 · **Nome sugerido.** O primeiro comentário de linha do bloco, sem o marcador (`-- Pedidos atrasados há mais de 3 dias, por cliente` → "Pedidos atrasados há mais de 3 dias, por cliente"). Sem comentário, o título da conversa ou da spec da sessão, mais a linguagem quando ela não aparece no título ("Pedidos atrasados no DBeaver (sql)"). O nome sugerido é cortado em 60 caracteres, numa palavra inteira.
- R4 · **Nome repetido e código repetido.** O nome é único por workspace, sem diferença de maiúsculas. Com um nome que já existe, o balão mostra "Já existe um snippet com esse nome." e troca Salvar por **Substituir**. Um bloco cujo código exato já está salvo no workspace mostra o botão como **✓ Salvo**, em teal, com ícone e texto; clicar nele abre o snippet no diálogo Snippets (R9). Depois de salvar, o botão vira "✓ Salvo" e o leitor de tela anuncia "Snippet salvo".

### Guardar

- R5 · **No banco, por workspace.** Os snippets ficam numa tabela nova, `snippets`, com o workspace (apagar o workspace apaga os snippets), o nome, a linguagem, a descrição, o código, a origem (conversa ou sessão, e um rótulo para quando a origem for apagada), o número de usos, a data do último uso, a criação e a última edição. Nada vai para o repositório: os arquivos do projeto e as worktrees das specs não mudam.

### Achar e usar

- R6 · **Grupo Snippets na paleta.** O Ctrl K lista os snippets do workspace ativo num grupo **Snippets**, depois de Specs e antes de Sessões. Cada linha mostra o nome e, em cinza, "sql · 17 linhas", com um ícone de código. A busca usa o nome e a descrição (o mesmo `fuzzyScore`). O prefixo **`$`** mostra só os snippets, e o chip `$ Snippets` entra ao lado dos outros prefixos. Sem texto na busca, os snippets vêm pelo uso mais recente.
- R7 · **Prévia na paleta.** Com um snippet selecionado, a paleta abre à direita uma prévia de até 14 linhas do código com realce, a descrição e "usado 4 vezes · último uso ontem". O rodapé da paleta troca as dicas para **Enter** copiar · **Ctrl+Enter** inserir no composer · **Ctrl+E** editar.
- R8 · **Copiar e inserir.**
  - **Copiar** (Enter na paleta, ou o botão no painel e no diálogo) põe o código exato na área de transferência e mostra o toast "Snippet copiado: Pedidos atrasados…".
  - **Inserir** (Ctrl+Enter na paleta, clique na seção do painel, ou o botão no diálogo) põe o snippet no composer como **bloco cercado** com a linguagem (```` ```sql ````), no cursor, com uma linha em branco antes quando o cursor não está no começo de uma linha. Vale para o composer do Prompt e o das Sessões: o da tela aberta. Em outra tela, inserir abre o Prompt na conversa selecionada (ou numa nova) e insere lá.
  
  As duas ações somam um uso e atualizam o último uso.

### Gerenciar

- R9 · **Diálogo Snippets.** Abre pela paleta ("Gerenciar snippets", e Ctrl+E num snippet), por "Ver todos" na seção do painel e pelo "✓ Salvo" do bloco. Tem duas colunas:
  - à esquerda, a busca ("Buscar snippets") e a lista do workspace, com o nome, "sql · 17 linhas" e o último uso; ordem por "Usados por último", "Nome" ou "Criados por último";
  - à direita, o snippet selecionado: nome, linguagem e descrição editáveis, o código num `AppCodeEditor` com realce, a origem e os botões **Copiar**, **Inserir no composer** e **Excluir**.
- R10 · **Editar.** As mudanças no snippet aberto ficam marcadas ("não salvo") e são gravadas com **Salvar** ou Ctrl+S. Trocar de snippet ou fechar com mudanças pergunta "Salvar as mudanças em 'Pedidos atrasados…'?" (Salvar · Descartar · Cancelar). O nome segue a regra de R4.
- R11 · **Origem.** "da conversa *Pedidos atrasados no DBeaver* · 12 nov." é um link que abre a conversa no Prompt (ou a sessão nas Sessões). Quando a conversa ou sessão foi apagada, o rótulo fica, sem link, com "(apagada)".
- R12 · **Excluir.** Excluir não pede confirmação: o snippet sai da lista e o toast "Snippet excluído" tem **Desfazer** por 5 s.
- R13 · **Seção no painel do Prompt.** O painel lateral do Prompt (SPEC-056) ganha a seção **SNIPPETS**, abaixo de PROMPTS SALVOS, com os cinco usados por último: nome, "sql · 17 linhas" e, no hover, os botões de ícone Copiar e Editar. Clicar na linha insere no composer (R8). "Ver todos (12)" abre o diálogo. Sem snippets, a seção diz "Salve um bloco de código pelo botão Salvar da resposta.". No painel recolhido, a seção ganha o seu botão na faixa, como as outras (`SideSection.snippets`).

### Acessibilidade

- R14 · Os botões de ícone têm rótulo ("Copiar snippet Pedidos atrasados…", "Editar snippet…"). Na paleta, a linha anuncia "Snippet Pedidos atrasados há mais de 3 dias, SQL, 17 linhas". O estado "Salvo" usa ícone e texto, não só a cor. O diálogo Snippets funciona só pelo teclado: ↑/↓ na lista, Enter abre, Tab vai ao editor.

## Fora do escopo

- Snippets globais (de todos os workspaces) e mover ou copiar um snippet para outro workspace.
- Guardar os snippets em arquivos do projeto, exportar como `.sql` e sincronizar com o time (P1).
- Variáveis no snippet (`:data_inicio`) que o app pergunta ao inserir.
- Rodar a query ou o comando a partir do app, ou abrir no DBeaver.
- Snippets no seletor `/` do composer (que continua sendo dos prompts salvos) (P6).
- Salvar um trecho selecionado (parte de um bloco ou texto fora de bloco). Salva-se o bloco inteiro; o trecho se ajusta depois no editor (R10).
- Pastas, tags e cores de snippet.

## Decisões

- P1 · **Onde ficam os snippets: banco ou arquivo no projeto.** Num arquivo (`.promptorium/snippets/atrasados.sql`), eles entram no git, aparecem no diff do agente, se repetem em cada worktree de spec e exigem tratar `.gitignore` e conflitos. No banco, ficam junto dos prompts salvos e das conversas, por workspace, e a origem aponta para a conversa sem copiar nada. **Decidido:** **banco**, numa tabela `snippets` por workspace (R5). Compartilhar com o time fica para uma exportação futura.
- P2 · **Por workspace ou globais.** O pedido é "snippet do projeto", e uma query do `loja-api` não serve no `site-institucional`. **Decidido:** **por workspace**; a paleta mostra os do workspace ativo.
- P3 · **Onde gerenciar.** Opções: uma aba "Snippets" em Ferramentas, uma tela nova no menu, ou um diálogo aberto da paleta e do painel do Prompt. Ferramentas é de agentes, skills e MCP, e uma tela nova é demais para uma lista curta. **Decidido:** **diálogo Snippets** (R9) mais a **seção no painel do Prompt** (R13), onde o snippet é usado.
- P4 · **Inserir como bloco cercado ou texto puro.** Cercado, o Claude lê como código e sabe a linguagem; texto puro mistura a query com a pergunta. **Decidido:** **bloco cercado** com a linguagem (R8). Quem quer texto puro usa Copiar.
- P5 · **Prefixo da paleta.** `>`, `#` e `:` já estão em uso. **Decidido:** **`$`**, de "trecho guardado", fácil de lembrar e sem conflito.
- P6 · **Snippets no `/` do composer.** Seria um terceiro caminho, mas o `/` lista prompts (texto que vira pedido), e misturar código ali confunde. **Decidido:** **não** nesta spec; paleta e painel bastam.
- P7 · **Nome sugerido.** **Decidido:** o primeiro comentário do bloco, depois o título da conversa com a linguagem (R3). Pedir ao Claude um nome custaria um turno e tempo.
- P8 · **Onde aparece o botão Salvar.** Na tela Specs o bloco é parte de um documento do repositório, não de uma resposta, e não há origem. **Decidido:** **só na timeline e no plano pronto** (R1).
- P9 · **Código já salvo.** Comparar o código exato do bloco com os snippets do workspace custa uma consulta por bloco. **Decidido:** guardar o hash (SHA-1) do código numa coluna indexada e consultar por hash; o provider cacheia o conjunto de hashes do workspace, então a timeline não faz uma consulta por bloco.

## Design

Canvas para validar: [Snippets salvos](https://claude.ai/artifact/GxygfLvsPiwVLJVUmRSs14). Quatro artboards de 1366 × 768: salvar, a paleta, o diálogo Snippets e o painel com o composer.

### O que já existe

- SPEC-077 (`spec/077-copiar-codigo`, PR #267): `lib/ui/widgets/markdown/code_block.dart` (`CodeBlock`, a barra, `codeOfPre`), `app_markdown.dart` (`AppMarkdown`, o `_PreBuilder`), `lib/ui/widgets/copy_button.dart` e `CodeLanguage.forFence`.
- `lib/data/db/app_database.dart`: `SavedPrompts` (o modelo de uma tabela de itens do usuário) e as migrações (`appSchemaVersion = 28` na main).
- `lib/data/repos/saved_prompts_repo.dart`: `watchAll`, `upsert`, `incrementUses`.
- `lib/ui/shell/command_palette.dart`: `PaletteCommand`, `paletteGroups`, `palettePrefixes`, `filterCommands`, `CommandPalette` (lista, rodapé com as teclas).
- `lib/features/prompt/widgets/prompt_side_panel.dart`: `SavedPromptsSection`, `SideSection`, `PromptSideStrip`.
- `lib/features/prompt/widgets/prompt_composer.dart`: `replaceComposerRange`, `insertSavedPrompt`; e o composer das Sessões (`lib/features/sessions/widgets/composer.dart`).
- `lib/ui/widgets/code_editor/`: `AppCodeEditor` e `CodeLanguage`.

### Componentes

- **Tabela `Snippets`** (`app_database.dart`): `id`, `workspaceId` (FK, cascade), `name`, `nameKey` (minúsculas, único com o workspace), `language` (nulo = texto), `description`, `body`, `bodyHash` (indexado), `originConversationId` e `originSessionId` (nulos, `set null`), `originLabel`, `uses`, `lastUsedAt`, `createdAt`, `updatedAt`.
- **`lib/data/repos/snippets_repo.dart`**: `watch(workspaceId)`, `hashes(workspaceId)`, `save` (com conflito de nome), `update`, `delete` / `restore` (Desfazer), `markUsed`.
- **`lib/features/snippets/`**:
  - `snippet_naming.dart`: `suggestSnippetName(code, language, title)` (função pura, R3);
  - `snippet_actions.dart`: `copySnippet`, `insertSnippet` (bloco cercado, R8), `composerTargetProvider` (o composer da tela aberta);
  - `widgets/save_snippet_dialog.dart` (R2–R4), `widgets/snippets_dialog.dart` (R9–R12), `widgets/snippets_section.dart` (R13).
- **`CodeBlock`** ganha `onSave` e `saved` (o `AppMarkdown` passa um `SnippetContext` com o workspace e a origem; sem ele, o botão não aparece).
- **Paleta**: `PaletteCommand` ganha `preview` (o widget da prévia) e `secondary` / `edit` (Ctrl+Enter e Ctrl+E); grupo `Snippets` e prefixo `$`.

### Migração

Sim. **v29** (a única migração da 0.19.0): cria a tabela `snippets` e o índice `(workspace_id, body_hash)`. Atualizar `drift_schemas/drift_schema_v29.json`, `schema_versions.dart` e o teste de migração.

### Arquivos tocados

- `lib/data/db/app_database.dart`, `app_database.g.dart`, `schema_versions.dart`, `drift_schemas/drift_schema_v29.json`
- `lib/data/repos/snippets_repo.dart` (novo), `lib/data/providers.dart`
- `lib/ui/widgets/markdown/code_block.dart`, `app_markdown.dart`
- `lib/features/snippets/` (novo)
- `lib/features/sessions/widgets/timeline_view.dart`, `lib/features/prompt/plan_ready.dart` (passam a origem)
- `lib/ui/shell/command_palette.dart`
- `lib/features/prompt/widgets/prompt_side_panel.dart`, `prompt_composer.dart`, `lib/features/sessions/widgets/composer.dart`
- `test/features/snippets/`, `test/data/migration_test.dart`, `test/ui/shell/command_palette_test.dart`

### Testes

- `suggestSnippetName`: comentário `--`, `#`, `//`; sem comentário usa o título; corta em 60 numa palavra.
- Repositório: nome único sem diferença de maiúsculas; substituir; hash do código; apagar o workspace apaga os snippets; apagar a conversa deixa o rótulo.
- `CodeBlock`: Salvar aparece só com `SnippetContext`; "✓ Salvo" quando o hash existe.
- Paleta: grupo e prefixo `$`; Enter copia; Ctrl+Enter insere; Ctrl+E abre o diálogo; prévia com o snippet selecionado.
- `insertSnippet`: bloco cercado com a linguagem, linha em branco antes quando preciso; soma um uso.
- Diálogo: editar e Ctrl+S; trocar com mudanças pergunta; excluir e Desfazer.

## Critérios de aceite

- [ ] A barra do bloco tem Salvar na timeline e no plano pronto, e não na tela Specs [R1, P8] verificar: flutter test test/features/snippets/save_snippet_test.dart
- [ ] O balão sugere o nome pelo comentário ou pelo título e salva o código exato do bloco [R2, R3] verificar: flutter test test/features/snippets/snippet_naming_test.dart
- [ ] Nome repetido troca Salvar por Substituir; código já salvo mostra "✓ Salvo" [R4] verificar: flutter test test/features/snippets/save_snippet_test.dart
- [ ] A tabela `snippets` é criada na v29, por workspace, e apagar o workspace apaga os snippets [R5] verificar: flutter test test/data/migration_test.dart
- [ ] A paleta lista os snippets no grupo Snippets, filtra com `$`, mostra a prévia, copia com Enter e insere com Ctrl+Enter [R6, R7, R8] verificar: flutter test test/ui/shell/command_palette_test.dart
- [ ] Inserir põe um bloco cercado com a linguagem no composer da tela aberta e soma um uso [R8] verificar: flutter test test/features/snippets/snippet_actions_test.dart
- [ ] O diálogo Snippets busca, edita com Ctrl+S, pergunta antes de perder mudanças, abre a origem e exclui com Desfazer [R9–R12] verificar: flutter test test/features/snippets/snippets_dialog_test.dart
- [ ] O painel do Prompt mostra os cinco últimos snippets e "Ver todos" [R13] verificar: flutter test test/features/prompt/prompt_side_panel_test.dart
- [ ] No app, a query de uma resposta vira snippet, é achada com Ctrl K `$atras`, copiada e colada no DBeaver, e inserida no composer de outra conversa [R1–R8] verificar: manual (app isolado com `XDG_DATA_HOME`, prints em `docs/mockups/spec-078/app/`)
- [ ] O projeto compila e a análise estática passa [R1–R14] verificar: flutter analyze
