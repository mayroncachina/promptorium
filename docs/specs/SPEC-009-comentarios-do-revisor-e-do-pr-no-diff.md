---
id: SPEC-009
status: rascunho
depende-de: []
---

# Review: comentários do revisor e do PR nas linhas do diff

## Objetivo

Mostrar no diff do Review, sob a linha a que se referem, os comentários do **revisor automático** e do **pull request**, junto com os comentários que o próprio usuário está escrevendo, e permitir marcar cada um como tratado. Hoje o diff mostra só os comentários pendentes do usuário; os do revisor e do PR ficam apenas no histórico "Rodadas de review", sem ligação com o código.

- Comentário de revisor e de PR nunca desaparece sem que o usuário o tenha tratado: se a linha mudou depois, ele continua visível numa seção própria.
- "Tratado" é um estado local do Promptorium. Não resolve a conversa no GitHub.
- Os comentários continuam sendo enviados ao agente pelas mesmas ações de hoje ("Pedir ajustes ao agente" e o acompanhamento do PR). Esta spec muda onde eles aparecem e o que se pode fazer com eles, não quem decide.
- Fora do escopo: responder a comentários do PR pelo app, resolver conversas no GitHub, GitLab (SPEC-013) e mostrar o diff desde uma rodada (SPEC-010).

## Requisitos

- R1 · O sistema deve mostrar, no diff do Review, cada comentário do revisor automático (`review_comments.author = revisor`) abaixo da linha nova a que se refere, com a rodada, a severidade e o requisito. Comentário com linha 0 deve aparecer como faixa no topo do arquivo, e comentário sem arquivo deve aparecer na seção "Geral", no topo do diff.
- R2 · Quando a sessão tiver PR, o sistema deve buscar os comentários em linha das revisões do PR e mostrá-los no diff do mesmo modo, identificados como "PR · @autor". Comentários de conversa do PR, que não têm arquivo nem linha, devem aparecer em "Geral". Cada comentário do PR deve ser gravado uma única vez, mesmo que o PR seja lido várias vezes.
- R3 · O sistema deve permitir marcar cada comentário do revisor ou do PR como "Tratado" e reabri-lo, guardando o estado entre aberturas do app, e mostrar a contagem de comentários abertos em cada arquivo da lista lateral e no cabeçalho do item.
- R4 · Quando o arquivo ou a linha de um comentário não existirem mais no diff atual, o sistema deve mostrá-lo na seção "Fora do diff atual" do arquivo (ou em "Geral"), com a rodada e o commit a que se referia.
- R5 · O sistema deve permitir selecionar comentários abertos do revisor ou do PR e incluí-los na mensagem de "Pedir ajustes ao agente", no mesmo formato `arquivo:linha — texto`, marcando-os como tratados ao enviar.
- R6 · O sistema deve permitir filtrar os comentários mostrados por estado (todos, só abertos) e por origem (você, revisor, PR), e ocultá-los todos, sem perder os que o usuário escreve.

## Design

### Dados
- `review_comments` (`app_database.dart`, `ReviewCommentsRepo`) já guarda rodada, autor (`revisor`, `humano`, `pr`), `path`, `line`, `body`, `severity`, `requirement` e `commitSha`. O revisor grava com o commit revisado; o acompanhamento do PR (`PrBabysitter._recordRound`) grava só o texto, sem `path` nem `line`.
- `appSchemaVersion` sobe para 16 (`app_database.dart`). O índice único parcial (`WHERE external_id IS NOT NULL`) não se declara na tabela Drift: é criado por `customStatement` no passo de migração e em `onCreate`, e o snapshot `drift_schema_v16.json` o inclui. `test/data/migration_test.dart` é estendido para v16 e confere as colunas e o índice.
- Migração do esquema v15 para v16 (passo `from15To16` em `onUpgrade`, `app_database.dart`; `schema_versions.dart` regenerado; `drift_schemas/drift_schema_v16.json`; teste de migração): em `review_comments`, `resolved` (booleano, padrão `false`), `resolvedAt` (data, nula) e `externalId` (texto, nulo, o id do comentário no GitHub, com índice único parcial por spec e `externalId` quando não nulo, para o R2; as linhas antigas, sem id, convivem com as novas).
- `ReviewCommentsRepo`: `setResolved(id, bool)`, `watchBySpec` (já existe), e `insertExternal` que ignora `externalId` repetido.

### R1 e R4 · Onde cada comentário cai
- Novo `lib/features/review/comment_anchor.dart`, **de propriedade desta spec** (a SPEC-010 o reutiliza). Duas peças: (1) `ReviewService.anchorShifts(sessionId, comments)`, assíncrona, roda o git (`diff --name-status` e `diff -U0` por `(sha, arquivo)`) e devolve os deslocamentos prontos; o resultado fica em cache num provider com chave `(sessionId, headSha)`, então a UI não chama git a cada reconstrução; (2) `anchorOf(comment, DiffFile?, shifts)`, **pura e síncrona**, que só recebe esses deslocamentos já calculados e devolve a linha do diff atual (`newNo`) ou `null` (fora do diff).
- A linha gravada pelo revisor refere-se ao arquivo no commit da rodada (`commitSha`). Antes de tudo, `git diff --name-status -M <sha>..HEAD -- <arquivo>`: arquivo ausente em HEAD ou renomeado vai direto para "fora do diff" (um diff vazio nesse caso **não** significa "não mudou"). Passada essa checagem, se o arquivo não mudou desde esse commit (`git diff <sha>..HEAD -- <arquivo>` vazio) a linha vale. Se mudou, calcular o deslocamento com `git diff -U0 <sha>..HEAD -- <arquivo>` (linhas antes do hunk não mudam, linhas depois deslocam pelo saldo, linhas dentro do hunk viram "fora do diff"). Sem `commitSha` (comentário antigo), a linha vale se existir no diff e senão cai em "fora do diff".
- Além de existir no arquivo, a linha precisa estar num hunk do diff do Review (diff é contra o merge-base e mostra contexto de 3 linhas). Fora de um hunk, o comentário vai para "Fora do diff atual" com a indicação "linha fora do trecho alterado".
- A tela de Review hoje mostra comentários pendentes do usuário (`ReviewComment`, `anchor = hunkKey#lineIndex`). Os comentários do revisor e do PR são linhas `ReviewCommentRow` (gerada pelo drift) acompanhadas de uma âncora calculada (`AnchoredComment { row, line?, outdatedReason? }`, tipo novo); `ReviewFileDiff` e `ReviewAllFiles` recebem as duas listas e desenham os dois do mesmo jeito (cartão sob a linha), com cor e rótulo da origem. Nenhum dos dois tipos é reescrito para caber no outro.

### R2 · Comentários em linha do PR
- `{owner}/{repo}/<número>` vêm da `pr_url` da sessão (`https://github.com/<owner>/<repo>/pull/<n>`); se o parse falhar, não há leitura em linha e o painel do PR diz "não foi possível ler a URL do PR", sem esvaziar o diff. A leitura usa `--paginate`; PR de fork funciona porque a URL aponta para o repositório base.
- Hoje `prView` roda `gh pr view --json comments,reviews`, que traz comentários de conversa e o corpo das revisões, mas **não** os comentários em linha. Acrescentar `PrInlineComment`, lido por `gh api repos/{owner}/{repo}/pulls/<número>/comments --paginate` (campos `id`, `path`, `line`, `original_line`, `commit_id`, `body`, `user.login`, `created_at`, `in_reply_to_id`). O número vem da `pr_url` da sessão.
- `line` nulo (a linha mudou no PR) usa `original_line` e `commit_id` para o R4. Respostas (`in_reply_to_id`) ficam agrupadas sob o comentário original, sem virar comentários novos.
- Leitura: ao abrir o item do Review com PR (no máximo uma vez por minuto) e em cada `PrBabysitter.check`. Falha de rede mantém o que já foi gravado e mostra o erro no painel do PR, sem esvaziar o diff.
- Os filtros do R6 valem só enquanto a tela está aberta; não são salvos.
- O `PrBabysitter` passa a incluir `arquivo:linha` na mensagem enviada à sessão (`prCommentsMessage`) para comentários em linha. Os comentários enviados por ele entram como **abertos**: o usuário os trata (decisão desta spec). `PrBabysitter._recordRound` passa a gravar pelo `insertExternal`, com o `id` que o `gh` devolve para cada comentário e revisão (`externalId = github:<id>`). As linhas `author = pr` gravadas antes da migração não têm `externalId`: na primeira leitura, cada uma é ligada ao comentário do PR de mesmo autor e texto (`@autor: texto`), atualizando seu `externalId`, em vez de ser inserida de novo. Para isso `prViewFields` e `PrComment` ganham o `id` de cada comentário e revisão (`externalId`); `PrComment.kind`, que alimenta o `verdict` da rodada, continua como está. O desempate é determinístico: linhas antigas e comentários do PR são ordenados por data e cada comentário é consumido uma só vez (dois textos iguais do mesmo autor ligam as duas linhas antigas a dois comentários distintos, na ordem).
- Só GitHub (`gh`). O GitLab é tratado na SPEC-013.

### R3 · Estado e contagens
- `reviewCommentsProvider(specId)` (já existe em `spec_review_panel.dart`) alimenta tudo. Contagem por arquivo = comentários abertos cujo `path` é o arquivo, ancorados ou "fora do diff". A contagem do cabeçalho é o total de comentários abertos da spec, **cada um uma só vez**: soma os arquivos e o "Geral" (comentários sem arquivo), sem recontar os "fora do diff", que já estão no arquivo deles.
- O badge na lista lateral usa o mesmo estilo do `+n −n`, em âmbar.
- "Tratado" não apaga: o cartão fica recolhido e esmaecido, com o botão "Reabrir".

### R5 · Enviar ao agente
- A seleção de comentários é estado efêmero da tela (caixas de seleção no cartão do comentário); `_requestChanges` em `review_screen.dart` passa a lê-la e a repassá-la. Gravar a rodada do usuário e marcar os comentários como tratados acontece numa só transação do banco (`db.transaction`); se o envio à sessão falhar, nada é gravado.
- `ReviewService.requestChanges` recebe, além de `List<ReviewComment>` pendentes, `List<ReviewCommentRow>` selecionados. `adjustmentMessage` (`review_logic.dart`) inclui os selecionados no mesmo bloco, indicando a origem ("revisor, rodada 2", "PR, @fulano") e o trecho da linha quando houver.
- Os selecionados viram `resolved = true` e a rodada do usuário (já gravada por `requestChanges`) referencia o envio. Falha no envio não marca nada.

### R6 · Filtros
- Estado de tela em `reviewViewProvider` (hoje `allFiles`, `sideBySide`), com três campos independentes: `commentsVisible` (bool, padrão verdadeiro; falso = ocultar todos), `onlyOpen` (bool, padrão verdadeiro) e `sources` (conjunto de origens visíveis: você, revisor, PR; padrão todas). "Ocultos" vence os outros dois.
- Os comentários do próprio usuário (rascunho) nunca são ocultados.

### Riscos
- **Texto de terceiros:** o corpo dos comentários do PR vem do GitHub. É mostrado como texto simples (sem interpretar HTML ou links) e, ao reenviar ao agente, é cortado em 4000 caracteres por comentário.
- **Deslocamento de linha** com `git diff -U0` não cobre renomeação de arquivo; nesse caso o comentário vai para "fora do diff". Aceitável.
- **Cota da API** do GitHub: uma chamada por minuto por PR aberto é pouca, mas o `PrBabysitter` roda a cada poucos minutos para todos os PRs acompanhados. Reutilizar a mesma leitura.
- **Linha do revisor:** esta spec ajusta `builtinReviewerPrompt` e `reviewerPrompt` (`auto_reviewer.dart`) para exigir "a linha do arquivo novo, como numerada no diff". Comentários de rodadas anteriores à mudança são tratados como linha do arquivo novo, em melhor esforço; quando não casarem com o diff, caem em "Fora do diff atual".

## Critérios de aceite

Os testes marcados "(a criar)" fazem parte da implementação, com `gh` e git falsos ou repositório temporário real.

- [ ] [R1] Um comentário do revisor na linha 12 de `a.dart` aparece sob a linha 12 do diff, com rodada, severidade e requisito; linha 0 vira faixa no topo do arquivo; sem arquivo aparece em "Geral". verificar: `flutter test test/features/review/review_inline_comments_test.dart` (a criar)
- [ ] [R1] O comentário continua na linha certa quando o arquivo mudou depois da rodada em um trecho acima da linha (deslocamento) e vai para "Fora do diff atual" quando a própria linha foi alterada. verificar: `flutter test test/features/review/comment_anchor_test.dart` (a criar)
- [ ] [R2] Comentários em linha do PR, devolvidos por um `gh api` falso, aparecem como "PR · @autor" nas linhas certas; comentários de conversa aparecem em "Geral"; ler duas vezes o mesmo PR não duplica nada. verificar: `flutter test test/features/review/pr_inline_comments_test.dart` (a criar)
- [ ] [R2] Com `gh` falhando, os comentários já gravados continuam no diff e o painel do PR mostra o erro. verificar: `flutter test test/features/review/pr_inline_comments_test.dart` (a criar)
- [ ] [R3] Marcar um comentário como tratado o recolhe, reduz a contagem do arquivo e do cabeçalho e persiste ao recriar o provider; reabrir desfaz. verificar: `flutter test test/features/review/review_inline_comments_test.dart` (a criar)
- [ ] [R3] A migração v15→v16 acrescenta `resolved`, `resolvedAt` e `externalId` sem perder as linhas existentes. verificar: `flutter test test/data/migration_test.dart`
- [ ] [R4] Comentário de um arquivo removido, de uma linha fora de qualquer hunk ou de um arquivo renomeado aparece em "Fora do diff atual", com rodada e commit. verificar: `flutter test test/features/review/comment_anchor_test.dart` (a criar)
- [ ] [R5] Selecionar dois comentários abertos (um do revisor, um do PR) e pedir ajustes envia uma mensagem com os dois em `arquivo:linha — texto`, os marca como tratados e, se o envio falhar, não marca nenhum. verificar: `flutter test test/features/review/review_service_test.dart`
- [ ] [R6] Os filtros "só abertos", "ocultos" e por origem mudam o que aparece no diff sem esconder o rascunho do usuário. verificar: `flutter test test/features/review/review_inline_comments_test.dart` (a criar)
- [ ] [R1] O prompt do revisor exige a linha do arquivo novo, como numerada no diff. verificar: `flutter test test/features/review/auto_reviewer_test.dart`
- [ ] [R2] `PrBabysitter._recordRound` grava com `externalId`; uma linha `author = pr` antiga, sem `externalId`, é ligada ao comentário de mesmo autor e texto na primeira leitura, sem duplicar. verificar: `flutter test test/features/review/pr_inline_comments_test.dart` (a criar)
- [ ] [R3] O cabeçalho conta cada comentário aberto uma só vez (arquivos mais "Geral"), mesmo quando há comentários "fora do diff". verificar: `flutter test test/features/review/review_inline_comments_test.dart` (a criar)
- [ ] [R1–R6] O código novo passa na análise estática e a suíte existente continua passando. verificar: `flutter analyze && flutter test`
- [ ] [R2] Com um PR real no GitHub com comentários em linha, o app os mostra nas linhas certas. verificar: manual (`flutter run -d linux`, Review de uma spec com PR, comentar em linha no GitHub e atualizar)

## Perguntas em aberto

- "Tratado" deveria também resolver a conversa no GitHub (`resolveReviewThread`, via GraphQL)? A spec assume que não.
- Comentários do usuário enviados ao agente ("humano") também devem aparecer no diff como histórico, depois de enviados?
