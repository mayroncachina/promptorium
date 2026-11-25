---
id: SPEC-112
status: concluida
versao: 0.26.0
tipo: recurso
issue: 417
depende-de: []
---

# Débitos e decisões

## Objetivo

Registrar o que ficou provisório de propósito (o **débito técnico**) e o que ficou para decidir depois (a **decisão pendente**) no momento em que isso acontece: na entrevista da spec, na Revisão ou na conversa com o agente. Depois, o app lembra desses itens perto do código e ajuda a pagá-los.

Hoje isso fica fora do app. A pessoa pede ao agente, no meio de uma resposta, para "criar um débito", e o agente edita um Markdown à mão. O Promptorium não sabe que o item existe: não o mostra no Quadro, não avisa quando uma spec mexe no arquivo que ele cita e não marca o débito como pago quando uma spec o resolve.

### Exemplo real

Num projeto de inscrições (um sistema web com backend Python e frontend Vue), a pessoa mantém dois arquivos:

- `docs/debitos-tecnicos.md`, uma tabela `| ID | Desde | O quê | Onde | Para resolver |` que vai de DT-01 a DT-08;
- `docs/decisoes-pendentes.md`, uma tabela `| ID | Desde | Origem | Pergunta | Recomendação | Decisão |` que vai de DP-01 a DP-08, todas já decididas.

Os itens nascem quase sempre numa resposta numerada da entrevista de spec, por exemplo:

> 5 - deixa simulado por hora e cria um débito técnico

O agente acrescenta esta linha:

> | DT-05 | 2026-11-21 | **Pagamento simulado**: PIX, boleto e cartão na tela Pagar não chamam o gateway; só o pedido de valor zero é pago de verdade (spec 29, P3). | `PagarView.vue` | ligar o gateway (homologação) junto com o DT-03 |

A spec de origem passa a citar o ID ("Q5 → DT-01"). Quando um débito é pago, a linha não é apagada. O ID e o título ficam riscados, "O quê" ganha "**resolvido** pela [spec 28](…)" e "Para resolver" vira "—":

> | ~~DT-02~~ | 2026-11-21 | ~~Arquivos da coreografia numa pasta local~~ — **resolvido** pela [spec 28](specs/28-armazenamento-s3.md) (S3 com `ARMAZENAMENTO=s3`). | `backend/app/arquivos.py` | — |

As decisões seguem a mesma lógica. A DP-01 ("Quem cadastra as funções de equipe técnica do evento?") foi respondida, e da resposta nasceu o DT-07 ("Lotes da equipe técnica do evento ficam para depois").

O formato funciona. Ele é legível no GitHub e no GitLab, entra no commit e não depende do app. Esta spec mantém o formato e faz o app entendê-lo.

## Requisitos

### Arquivos e dados

- R1 · **Dois arquivos na raiz.** `DEBITO_TECNICO.md` e `DECISOES_PENDENTES.md`, com as tabelas do exemplo e os mesmos campos: `| ID | Desde | O quê | Onde | Para resolver |` e `| ID | Desde | Origem | Pergunta | Recomendação | Decisão |`. Não há gravidade, número de linha nem campo "depende de". "O quê" traz o título em negrito, o motivo e a origem entre parênteses. "Onde" é o arquivo ou a função, sem número de linha. Os caminhos são configuráveis em `.promptorium/config.yml` (`debitos.arquivo` e `debitos.decisoes`). O app cria o arquivo, com um cabeçalho curto e a tabela vazia, quando grava o primeiro item.
- R2 · **Arquivos que já existem.** Se o app encontrar `docs/debitos-tecnicos.md` ou `docs/decisoes-pendentes.md` e não houver arquivo no caminho configurado, oferece duas opções numa faixa da tela: "Usar estes arquivos", que grava o caminho no config, e "Mover para a raiz", que faz `git mv` para o nome novo e conserta os links relativos das linhas (`specs/31-…` vira `docs/specs/31-…`). Nada acontece sem a escolha da pessoa.
- R3 · **IDs em sequência.** `DT-NN` e `DP-NN`, com dois dígitos ou mais, em sequência por repositório. Um ID nunca é reutilizado, nem quando a linha é riscada ou removida à mão. O próximo número é o maior entre os IDs do arquivo da branch principal, os das worktrees abertas e os já reservados no banco, mais um.
- R4 · **O arquivo é a fonte da verdade.** Título, motivo, onde, para resolver, decisão e "pago" (linha riscada) vêm sempre do arquivo. O banco (tabela nova, schema v37) guarda só o que não cabe na tabela: a origem (sessão, spec e pergunta, comentário de revisão, mensagem), o estado "em pagamento" com a spec ou tarefa VIBE que está pagando, as sugestões pendentes do agente e o "pago de carona?". Quando o arquivo e o banco discordam, vale o arquivo: um vínculo cujo ID sumiu do arquivo aparece como "vínculo órfão" e não recria a linha.
- R5 · **Escrita cirúrgica.** O app só acrescenta linhas no fim da tabela ou substitui a linha do item que muda. Todo o resto continua igual byte a byte: o texto antes e depois da tabela, o fim de linha (LF ou CRLF), o espaçamento e a ordem das colunas. Linhas da tabela que o parser não entende aparecem na tela como "N linhas não reconhecidas", com o texto cru, e nunca são reescritas. Antes de gravar, o app relê o arquivo. Se ele mudou desde a leitura, reaplica a alteração sobre o texto novo ou, se a linha do item mudou, desiste e avisa. Quando o arquivo muda fora do app (no editor, num pull ou pelo agente), a tela relê.

### Onde nascem

- R6 · **Entrevista da spec.** No mini-planejamento da Nova spec, no planejamento e em "Perguntas em aberto", cada pergunta ganha duas ações:
  - "Simplificar agora → débito" abre o formulário do débito já preenchido com a pergunta e a resposta simplificada;
  - "Decidir depois → DP" cria a decisão com a pergunta e a sugestão como recomendação.

  O item registra a origem ("spec 31, Q5"). A resposta na spec ganha "→ débito técnico DT-09" ou "→ DP-09", e a pergunta conta como respondida.
- R7 · **Pedido em texto livre.** Quando a resposta da pessoa diz algo como "bota em débito", "deixa simulado e cria um débito" ou "decide depois", o app detecta e cria uma **sugestão** ligada à pergunta. A sugestão vem com o texto proposto e espera a pessoa aceitar ou descartar. O app nunca grava no arquivo só por causa da frase.
- R8 · **Revisão.** Cada comentário aberto ganha "Virar débito", que abre o formulário com o comentário, o arquivo e a função já preenchidos. Ao salvar, o comentário fica resolvido e recebe o selo "→ DT-12", sai da contagem de "Comentários abertos" e deixa de bloquear o merge. Desfazer (apagar o vínculo antes do merge) devolve o comentário à contagem.
- R9 · **Mensagem do agente.** Numa sessão ou no Prompt, o botão de ações da mensagem (hoje só no hover, em `timeline_view.dart`) ganha "Virar débito". Se houver um trecho selecionado, ele preenche "O quê"; senão, entra o primeiro parágrafo. O vínculo guarda a sessão e a mensagem.
- R10 · **À mão.** Na tela, os botões "Novo débito" e "Nova decisão" abrem o mesmo formulário, sem origem.
- R11 · **MCP do Promptorium.** As ferramentas `registrar_debito` (tipo, título, motivo, onde, para resolver ou recomendação) e `listar_debitos` (abertos e decisões pendentes, com ID, título e onde) passam a existir no servidor MCP do app e valem para o Claude Code e o Codex. O que o agente registra entra como sugestão pendente, no mesmo modelo das `SpecSuggestions`, e quem escreve no arquivo é o app, quando a pessoa aceita. O app não mexe no `CLAUDE.md` nem no `AGENTS.md` de ninguém: a descrição da ferramenta basta para o agente saber quando usá-la.
- R12 · **Responder uma decisão.** Na aba Decisões, "Responder" preenche a coluna "Decisão" com "**Decidido (AAAA-MM-DD):** …" e leva a resposta para a spec de origem: a pergunta ganha "→ DP-04: <resposta>" e, se ainda estiver em "Perguntas em aberto", passa a contar como respondida. Ao salvar, o app oferece "Virar débito", que abre o formulário de débito com a origem "DP-04" e grava a ligação nas duas pontas ("(…, DP-04)" no débito e "gerou o DT-10" na decisão).

### Tela

- R13 · **Débitos e decisões.** Uma tela nova no menu lateral, com as abas Débitos e Decisões.
  - Os filtros são Abertos / Pagos e Pendentes / Decididas, e a tela abre em Abertos e Pendentes.
  - Cada linha mostra o ID, o título, o "Onde" em monoespaçada, a origem clicável (spec, sessão, comentário) e o estado: aberto, em pagamento (com o link) ou pago.
  - As sugestões do agente aparecem numa faixa no topo da aba Débitos, com "Aceitar", "Editar" e "Descartar".
  - Itens que nasceram numa spec ainda não mesclada aparecem com "na spec N", porque a linha ainda não está no arquivo da branch principal.
  - A tela é a mesma para todos os repositórios do workspace, com o seletor de repositório quando houver mais de um.
- R14 · **Chip no Quadro.** A barra do Quadro ganha o chip "Débitos · N", que conta só os abertos e abre a tela. Sem débitos abertos, o chip some.

### Pagar

- R15 · **Pagar.** A pessoa seleciona um ou mais débitos abertos e clica em "Pagar". O diálogo oferece dois caminhos:
  - uma tarefa VIBE;
  - uma spec "Pagar débitos: DT-03, DT-05", com os itens no Objetivo e um requisito por débito.

  O app sugere VIBE para até 2 débitos e spec a partir de 3, mas a pessoa escolhe. Cada débito fica "em pagamento", com o link para a tarefa ou a spec. No merge, o app risca a linha na branch da spec, antes do commit de merge: ID e título riscados, "— **resolvido** pela [spec N](…)" no "O quê" e "—" em "Para resolver". Se a spec ou a tarefa for descartada, o débito volta a "aberto". Decisões não se pagam: elas se decidem (R12).

### Lembrar

- R16 · **Chip no arquivo.** Quando um arquivo citado em "Onde" aparece num diff, o app mostra o chip "N débitos neste arquivo" no diff da sessão, na Revisão e no card do Quadro da spec que mexe nele. O chip abre a lista desses débitos. A comparação é por caminho, e por nome de arquivo quando "Onde" traz só o nome (`PagarView.vue`). Uma função citada sem arquivo não gera chip.
- R17 · **Lembrete no prompt da execução.** O prompt de cada etapa da spec ganha uma linha com os débitos abertos dos arquivos que a spec cita: "Débitos abertos nestes arquivos: DT-03 (…), DT-05 (…). Pague se for barato e diga quais pagou." O lembrete vem ligado por padrão e pode ser desligado em `.promptorium/config.yml` (`debitos.lembrar_na_execucao: false`). Se o agente disser que pagou um débito (por exemplo, "paguei o DT-05"), o app marca "pago de carona?". O card, o diff da sessão e a Revisão mostram a marca, e a pessoa confirma ou recusa. Confirmado, a linha é riscada no merge, como em R15. O débito nunca fecha sozinho.

### Commit

- R18 · **Onde entra no git.** O débito ou a decisão que nasce numa spec ou sessão com worktree é gravado no arquivo dessa worktree e vai no commit dela. O pagamento entra no merge da spec que pagou (R15). O item criado à mão, ou fora de uma worktree, ganha um commit próprio na branch principal, só com o arquivo (`docs: DT-09 lotes da equipe técnica`). O app pergunta antes de fazer esse commit e não faz push.

## Fora do escopo

- Ler TODO e FIXME do código.
- Gravidade ou prioridade dos débitos.
- Contador, gráfico ou tendência da dívida ao longo do tempo.
- Sincronizar com issues do GitHub ou do GitLab.
- Lembrar o agente no meio de um turno. O lembrete vai só no prompt da etapa (R17).
- Pagar decisões, porque decisão se decide.
- Menu de clique direito nas mensagens. R9 usa o botão de ações que já existe.

## Perguntas em aberto

Só decisões menores. As grandes já foram fechadas com o usuário e estão nos requisitos. Em 24/11 o usuário aprovou o canvas e mandou seguir todas as recomendações.

- P1 · **Lugar no menu lateral.** Onde fica o item "Débitos e decisões"?
  - **Decidido:** logo abaixo do Quadro, com o ícone `pending_actions`
- P2 · **Item que nasce antes de a spec ter número.** No mini-planejamento da Nova spec, a spec ainda não existe. O que acontece com o débito?
  - **Decidido:** ele fica como sugestão pendente, ligada ao rascunho. Quando a spec é criada e ganha número, o app grava a linha com "(spec N, Q5)" e escreve o ID na resposta. Se o rascunho for descartado, a sugestão vai junto.
- P3 · **Detecção do pedido em texto livre (R7).** Como reconhecer "bota em débito"?
  - **Decidido:** uma lista local de expressões ("débito", "deixa simulado", "provisório por hora", "decide depois", "fica pendente"), aplicada só às respostas das perguntas da entrevista, sem chamar o modelo. Um falso positivo custa só uma sugestão descartada.
- P4 · **Duas specs em paralelo criando débitos.** O que fazer quando dois merges acrescentam linhas no mesmo arquivo?
  - **Decidido:** a reserva no banco (R3) evita IDs repetidos. Se o merge der conflito só no fim da tabela desse arquivo, o app resolve juntando as linhas dos dois lados em ordem de ID. Qualquer outro conflito no arquivo segue para a sessão de resolução normal (SPEC-092).
- P5 · **Commit à mão com a branch principal suja (R18).** E se o arquivo de débitos já tiver alterações não commitadas na branch principal?
  - **Decidido:** o app grava a linha, mas não commita. Ele avisa "o arquivo já tinha alterações; o commit fica com você". Com o arquivo limpo, commita só esse caminho (`git commit -- DEBITO_TECNICO.md`).
- P6 · **Tamanho do lembrete no prompt (R17).** Quantos débitos entram na linha?
  - **Decidido:** até 5, os mais antigos primeiro, cada um com ID, título e onde. Se houver mais, a linha termina com "e mais N (veja DEBITO_TECNICO.md)".
- P7 · **"Pago de carona?" sem merge.** O agente diz que pagou, mas a spec é descartada. O que acontece?
  - **Decidido:** a marca é descartada junto com a spec, e o débito continua aberto. Confirmar na Revisão só risca a linha no merge, como em R15.

## Design

### O que já existe

- `lib/data/db/app_database.dart:438`, `SpecSuggestions`: sugestão `pendente` / `aplicada` / `ignorada`, mostrada no card até a pessoa decidir. É o modelo das sugestões do agente (R7, R11). `lib/features/board/spec_runner.dart:60` faz a leitura das `SPEC SUGESTÃO:`.
- `lib/features/review/comment_anchor.dart`, `isOpenReviewComment`, e `lib/features/review/merge_readiness.dart:231`, o item "Comentários abertos" do merge. "Virar débito" resolve o comentário pela coluna `resolved`, que já existe, e o selo vem do vínculo (R8).
- `lib/features/specs/spec_file.dart:409,568-618`, `## Perguntas em aberto`: `OpenQuestion`, `withOpenQuestions`, `withAssumptions`. Aqui entra a escrita de "→ DT-09" na resposta (R6, R12). O mini-planejamento fica em `lib/features/specs/new_spec_view.dart`, e as ideias em `lib/features/ideas/`.
- `lib/core/mcp/app_mcp_tools.dart`, `AppMcpToolNames`: hoje `listar_specs`, `ler_spec`, `criar_spec`, `anotar_andamento` e outras. Ganha `registrar_debito` e `listar_debitos` (R11).
- `lib/features/vibe/vibe_service.dart` (VIBE é uma spec com merge e descarte) e `lib/features/board/widgets/board_tray.dart` (a Bandeja e a barra do Quadro, onde entra o chip de R14).
- `lib/features/sessions/widgets/timeline_view.dart:767`, o botão de ações da mensagem, que só aparece no hover (R9).
- `lib/features/project/project_config.dart`, `ProjectConfig`, que lê o `.promptorium/config.yml` e ganha `DebtsConfig` (R1, R17).
- `lib/ui/shell/navigation.dart`, `AppSection`, que ganha `debts('Débitos e decisões', 'Novo débito')` (R13).

### Módulo novo: `lib/features/debts/`

- `debt_table.dart`: o parser e o escritor de tabela Markdown, puros e sem I/O (detalhes abaixo).
- `debt_item.dart`: `DebtItem` (id, desde, título, motivo, onde, paraResolver, pago, resolvidoPor) e `DecisionItem` (id, desde, origem, pergunta, recomendação, decisão), com `fromCells` e `toCells`.
- `debt_files.dart`: localiza os arquivos (config, raiz, `docs/` antigo), lê, observa mudanças (`FileSystemEntity.watch` com releitura) e grava com a releitura de R5. Um `StreamProvider` por repositório.
- `debt_links_repo.dart`: o acesso à tabela nova, a reserva de ID (R3) e as sugestões.
- `debt_service.dart`: criar, aceitar sugestão, responder decisão, virar débito, pagar, marcar pago no merge, voltar a aberto no descarte, commit próprio (R18).
- `debt_detector.dart`: as expressões de R7 (P3) e a leitura de "paguei o DT-05" na resposta da etapa (R17).
- `widgets/`: `debts_screen.dart`, `debt_form_dialog.dart`, `pay_debts_dialog.dart`, `debt_suggestions_strip.dart`, `debt_file_chip.dart` e `debts_board_chip.dart`.

### Migração v37

`appSchemaVersion` passa de 36 para 37, com o passo em `lib/data/db/migrations.dart` e o snapshot em `schema_versions.dart`. Tabela nova `DebtLinks`:

| Coluna | Tipo | Para quê |
|---|---|---|
| `id` | int, autoincremento | chave |
| `repoRoot` | text | repositório do item |
| `kind` | text | `debito` / `decisao` |
| `code` | text, nulo | `DT-09` / `DP-04`; nulo numa sugestão ainda não aceita |
| `originSpecId` | int, nulo → `Specs` (set null) | spec de origem |
| `originQuestion` | text, nulo | `Q5`, `P3` |
| `originSessionId` | text, nulo | sessão ou conversa de origem |
| `originMessageId` | text, nulo | mensagem do agente (R9) |
| `originReviewCommentId` | int, nulo → `ReviewComments` (set null) | comentário que virou débito (R8) |
| `originDecision` | text, nulo | `DP-01` que gerou o débito (R12) |
| `suggestionState` | text, nulo | `pendente` / `aceita` / `descartada` |
| `suggestionSource` | text, nulo | `mcp` / `entrevista` / `rascunho` |
| `suggestionBody` | text, nulo | JSON com as células propostas |
| `paymentSpecId` | int, nulo → `Specs` (set null) | spec ou VIBE que está pagando |
| `piggybackSpecId` | int, nulo → `Specs` (set null) | etapa que disse ter pago (R17) |
| `piggybackState` | text, nulo | `a_confirmar` / `confirmado` / `recusado` |
| `createdAt` | datetime | quando |

Índice único em `(repoRoot, code)`, quando `code` não é nulo. Ele impede reservar o mesmo ID duas vezes. "Em pagamento" é `paymentSpecId` preenchido com a spec ainda aberta, e não precisa de coluna própria. A migração só cria a tabela e não importa nada: os arquivos já são a fonte.

### Parser de tabela Markdown

1. Divide o texto em linhas e guarda o fim de linha detectado e se há quebra no fim.
2. Procura a primeira linha de cabeçalho cujas células, normalizadas (sem acento, minúsculas, sem espaços nas pontas), batem com as colunas esperadas, na mesma ordem. Logo depois deve vir a linha separadora (`|---|`, com ou sem `:`).
3. As linhas seguintes que começam com `|` são linhas da tabela, até a primeira que não começa. As células são separadas por `|` que não esteja escapado (`\|`) nem dentro de crase.
4. Uma linha vira item quando a primeira célula é `DT-NN` ou `~~DT-NN~~` e o número de células bate. `~~…~~` no ID significa pago. O título é o primeiro trecho em negrito ou riscado de "O quê". "**resolvido** pela [spec N](…)" dá o `resolvidoPor`.
5. Qualquer outra linha dentro da tabela vai para `unrecognized`, com o número da linha e o texto cru (R5).
6. O resultado traz `items`, `unrecognized`, a faixa de linhas da tabela e o texto original.

### Escritor

- **Acrescentar:** insere a linha nova logo depois da última linha da tabela, com o mesmo fim de linha. Sem tabela, acrescenta o cabeçalho e o separador no fim do arquivo.
- **Alterar:** substitui só a linha do item, achada pelo ID. Se o texto da linha mudou desde a leitura, a escrita falha com `DebtRowChanged`.
- **Células:** `|` vira `\|`, quebras de linha viram espaço, e `Onde` vai entre crases quando é um caminho.
- **Riscar (R15):** `| ~~DT-05~~ | … | ~~Pagamento simulado~~ — **resolvido** pela [spec 118](docs/specs/SPEC-118-….md) (…resto do motivo…). | … | — |`.
- **Propriedade testada:** `parse(write(parse(x))) == parse(x)`, e todo byte fora da linha alterada continua igual.

### Pagamento e merge

- `DebtService.pay` cria a VIBE (`VibeService`) ou a spec (`SpecService`, com o modelo "Pagar débitos") e grava `paymentSpecId`.
- No fluxo de merge (Review), antes do commit de merge, o app risca as linhas dos débitos com `paymentSpecId` igual à spec e os de "pago de carona?" confirmados, no arquivo da worktree. Depois commita `docs: DT-03, DT-05 pagos pela spec 118` na branch da spec.
- No descarte, `paymentSpecId` volta a nulo e o `piggyback*` da spec é limpo.

## Tarefas

A spec é grande e segue o padrão pai e filhos: uma branch pai `spec/112-debitos-e-decisoes` e uma branch por tarefa, com PR para a pai.

- T1 · **Base: parser, escritor, arquivos e migração v37** (R1, R3, R4, R5). `lib/features/debts/debt_table.dart`, `debt_item.dart`, `debt_files.dart`, `debt_links_repo.dart` e `app_database.dart`. Verificar: testes do parser com cópias anonimizadas das tabelas do exemplo (DT-01 a DT-08, DP-01 a DP-08), a propriedade de ida e volta, CRLF, linhas não reconhecidas, reescrita concorrente e o teste de migração 36 → 37.
- T2 · **Tela Débitos e decisões, menu e itens à mão** (R2, R10, R13, R18). `AppSection.debts`, `debts_screen.dart`, `debt_form_dialog.dart`, a faixa de `docs/` antigo e o commit próprio. Verificar: testes de widget dos filtros, das abas, de "N linhas não reconhecidas" e do diálogo de commit.
- T3 · **Entrevista e decisões** (R6, R7, R12). Ações nas perguntas (`new_spec_view.dart`, planejamento, "Perguntas em aberto"), `debt_detector.dart`, "→ DT-NN" na spec e Responder decisão com "Virar débito". Verificar: testes de `spec_file.dart` com a resposta anotada e do detector.
- T4 · **Revisão e mensagens** (R8, R9). "Virar débito" no comentário, o selo, a contagem em `merge_readiness.dart` e o item no botão de ações da mensagem. Verificar: teste de que o comentário sai de "Comentários abertos" e volta ao desfazer.
- T5 · **MCP e sugestões** (R11, faixa de R13). `registrar_debito` e `listar_debitos` em `app_mcp_tools.dart`, com a faixa de sugestões. Verificar: testes das ferramentas nos dois provedores e de aceitar e descartar.
- T6 · **Pagar** (R14, R15). `pay_debts_dialog.dart`, os estados, riscar no merge e voltar no descarte, mais o chip do Quadro. Verificar: testes do serviço com merge e descarte e da sugestão VIBE × spec.
- T7 · **Lembrar** (R16, R17). Chips no diff, na Revisão e no card, a linha no prompt da etapa (`spec_runner.dart`), o config e o "pago de carona?". Verificar: teste do prompt com e sem o config e da confirmação na Revisão.
- T8 · **Teste ponta a ponta** com o app compilado e dados isolados: criar um débito na entrevista, outro na Revisão, pagar por VIBE e conferir o arquivo e o commit. Verificar: prints e relatório.

## Critérios de aceite

- [x] Ler e regravar as tabelas do exemplo (anonimizadas) não muda nenhum byte fora da linha alterada, e linhas estranhas aparecem como "N linhas não reconhecidas" [R1, R5] verificar: testes de `debt_table.dart`.
- [x] Com `docs/debitos-tecnicos.md` no repositório, a tela oferece usar o arquivo ou movê-lo, e nada muda sem escolha [R2] verificar: teste de widget e teste do `git mv` com links consertados.
- [x] Dois débitos criados em worktrees diferentes recebem IDs diferentes, e um ID riscado ou apagado nunca volta [R3] verificar: testes de `debt_links_repo.dart`.
- [x] Editar o arquivo fora do app atualiza a tela, e um vínculo sem linha aparece como órfão sem recriar a linha [R4, R5] verificar: teste com escrita externa.
- [x] "Simplificar agora → débito" e "Decidir depois → DP" gravam a linha com "(spec N, Q5)" e anotam "→ DT-NN" na resposta [R6] verificar: testes de `spec_file.dart` e do serviço.
- [x] "bota em débito" numa resposta gera uma sugestão e não grava no arquivo até aceitar [R7] verificar: teste do detector e do serviço.
- [x] "Virar débito" num comentário mostra o selo "→ DT-12", baixa "Comentários abertos" em um e libera o merge, e desfazer devolve o comentário [R8] verificar: testes de `merge_readiness.dart`.
- [x] "Virar débito" numa mensagem usa o trecho selecionado ou o primeiro parágrafo [R9] verificar: teste de widget da timeline.
- [x] `registrar_debito` no Claude Code e no Codex cria só uma sugestão, e `listar_debitos` devolve os abertos [R11] verificar: testes das ferramentas MCP.
- [x] Responder uma DP preenche "Decisão", leva a resposta à spec de origem e "Virar débito" cria um DT ligado à DP nas duas pontas [R12] verificar: teste do serviço.
- [x] A tela abre em Abertos e Pendentes, mostra a faixa de sugestões e o "na spec N", e o chip do Quadro conta só os abertos [R13, R14] verificar: testes de widget.
- [x] Pagar 2 débitos sugere VIBE, 3 sugere spec, e o merge risca as linhas com "**resolvido** pela spec N", enquanto o descarte as devolve a "aberto" [R15] verificar: testes do serviço com merge e descarte.
- [x] O diff, a Revisão e o card mostram "N débitos neste arquivo" para caminhos e nomes citados em "Onde" [R16] verificar: testes de widget.
- [x] O prompt da etapa traz a linha dos débitos dos arquivos da spec só quando o config permite, e "paguei o DT-05" vira "pago de carona?" a confirmar, sem fechar sozinho [R17] verificar: testes de `spec_runner.dart`.
- [x] O item de uma spec vai no commit dela, e o item à mão só é commitado depois da confirmação, com `docs: DT-NN …` e sem push [R18] verificar: teste de git com repositório temporário.
- [x] No app compilado, com dados isolados, o fluxo completo (entrevista, Revisão, Pagar por VIBE, merge) deixa o arquivo e o histórico do git corretos [R1–R18] verificar: prints e relatório do teste ponta a ponta.

## Telas

Mockup: [canvas do Claude Design](https://claude.ai/artifact/QCqBhDaQGrctTyWWKraG9v). Capturas em `docs/mockups/spec-112/`:

| PNG | O que mostra | Requisitos |
|---|---|---|
| `1-debitos.png` | A tela Débitos e decisões na aba Débitos, em Abertos: a faixa com 2 sugestões do agente (MCP e entrevista), o DT-07 "em pagamento", o DT-09 "na spec 33", DT-05 e DT-06 selecionados, "Pagar · 2" e "1 linha não reconhecida" | R4, R5, R11, R13, R15 |
| `2-decisoes.png` | A aba Decisões com a DP-09 pendente aberta: pergunta, recomendação, a decisão escrita, "Levar a resposta para a spec 33", a linha que o app grava e "Virar débito" | R12, R13 |
| `3-entrevista.png` | As perguntas da spec 33: Q4 respondida com "→ débito técnico DT-09", Q5 com "Simplificar agora → débito" e "Decidir depois → DP", Q6 com a sugestão gerada por "bota em débito", Q7 com "→ DP-09" e o formulário do DT-10 | R6, R7, R18 |
| `4-revisao.png` | A Revisão da spec 33: um comentário que virou débito com o selo "→ DT-12" e "Desfazer", outro aberto com "Virar débito", "Comentários abertos" caindo de 3 para 2 e o chip "3 débitos neste arquivo" | R8, R16, R18 |
| `5-pagar.png` | O diálogo Pagar com 2 débitos: VIBE (sugerido até 2) × spec, o prompt da VIBE e o que acontece agora, no merge e no descarte | R15 |
| `6-quadro-e-diff.png` | O chip "Débitos · 7" no Quadro, os chips nos cards, o diff da sessão com "2 débitos neste arquivo" aberto e o "pago de carona?" do DT-03 para confirmar | R14, R16, R17 |

### No app

Teste ponta a ponta com o app compilado, dados isolados (`XDG_DATA_HOME`, `HOME`, `CODEX_HOME` e `CLAUDE_CONFIG_DIR` no scratchpad) e Claude e Codex falsos, sem turno pago. Capturas em `docs/mockups/spec-112/app/`: a tela com a sugestão do Codex via MCP (`1-debitos.png`), a decisão respondida (`2-decisoes.png`), "Simplificar agora → débito" na entrevista (`3-entrevista.png`), o commit próprio (`4-commit-proprio.png`), o chip do Quadro (`5-quadro-chip.png`), a seleção, o Pagar e o "em pagamento" (`6` a `8`), a Revisão da VIBE com "Esta spec vai pagar" (`9-revisao-vai-pagar.png`), os pagos depois do merge (`10-pagos.png`) e o commit ao aceitar uma sugestão (`11-aceitar-sugestao-commit.png`). O trabalho do agente na VIBE foi simulado com um commit feito à mão na worktree; a sugestão do MCP foi montada no banco isolado.
