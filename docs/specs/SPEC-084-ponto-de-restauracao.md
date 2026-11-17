---
id: SPEC-084
status: rascunho
tipo: recurso
issue: 270
---

# Ponto de restauração

## Objetivo

Um turno do agente pode mexer em muita coisa: editar dez arquivos, criar outros, apagar um diretório com `rm -rf`, rodar um `sed -i` que estraga metade do projeto ou fazer um commit no meio. Quando o resultado é ruim, voltar atrás hoje depende do estado do git. Se a pessoa já tinha alterações não commitadas antes de pedir, um `git checkout .` joga fora o trabalho dela junto com o do agente. Os arquivos novos que o agente criou ficam para trás. E o `/rewind` do Claude Code só desfaz as edições feitas pelas ferramentas Edit e Write, não o que o `Bash` fez.

Exemplo: no workspace `loja-api`, a pessoa tem `src/cupom.ts` editado à mão e ainda não commitado. Ela pede numa sessão "renomeie `Pedido` para `Order` no projeto todo". O agente roda um `sed -i` em 40 arquivos, cria `src/order.ts`, apaga `src/pedido.ts` e faz um commit "wip". A troca quebrou os testes. Para voltar, ela precisa desfazer o commit, restaurar os 40 arquivos, recriar `src/pedido.ts`, apagar `src/order.ts` e, no meio disso, não perder o `src/cupom.ts`. Hoje isso é meia hora de git.

Já existe um pedaço disso: o "Voltar ao início da etapa" (SPEC-035), que grava um ponto (`refs/promptorium/<spec>/<etapa>-inicio` e `-estado`) quando uma etapa de spec começa. Mas ele só vale para etapas de spec e só volta ao começo da etapa inteira, não de um turno.

Esta spec:
- grava um **ponto de restauração antes e depois de cada turno** de qualquer agente que edita arquivos: sessões (com ou sem spec, no worktree ou na raiz), etapas de spec e VIBEs;
- o ponto guarda o `HEAD`, a branch e **todo o working tree, com os arquivos não rastreados**, sem mexer no índice, no stash nem nos arquivos da pessoa;
- põe um botão **"Desfazer o que o agente fez"** na sessão, que volta o último turno em um clique, mesmo com o git sujo;
- mostra antes **o que vai mudar**, separa o que a pessoa editou depois do turno e deixa refazer o que foi desfeito.

Issue: [#270](https://github.com/mayroncachina/promptorium/issues/270) (sub-issue de [#268](https://github.com/mayroncachina/promptorium/issues/268))

Mockup: [canvas do Claude Design](https://claude.ai/artifact/4kUbHocUqgLjPcXTuWYCg5). Capturas em `docs/mockups/spec-084/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-sessao.png` | A sessão com o botão "Desfazer o último turno", os pontos na timeline e a seção "Pontos de restauração" no painel | R1–R4, R9, R10 |
| `2-desfazer.png` | A janela de confirmação: arquivos que voltam, o arquivo que a pessoa editou depois do turno, o commit descartado | R5–R8 |
| `3-desfeito.png` | Depois de desfazer: a nota na timeline, o aviso com "Refazer" e o ponto marcado como desfeito; o caso do commit já enviado | R8, R11, R12 |
| `4-configuracoes.png` | Configurações › Sessões: retenção e espaço usado | R13–R15 |

## Requisitos

### O ponto

- R1 · **Quando o ponto é gravado.** Antes de o app mandar a mensagem de um turno novo ao agente (`SessionManager.send`, inclusive o "Retomar" e as mensagens do Autopilot e das etapas), ele grava o **início do turno**. Quando o turno termina (o `result` do turno, ou o processo morre no meio), grava o **fim do turno**. Os avisos enviados no meio de um turno (`_sendMidTurn`) e as respostas a aprovações não criam ponto novo. O mesmo vale para as VIBEs (`ConversationManager`), que rodam no worktree da spec. As conversas do Prompt (raiz do workspace, modo Perguntar/Planejar) não gravam ponto (P5).
- R2 · **O que o ponto guarda.** Para cada ponto: o `HEAD` (sha), a branch atual (ou "HEAD destacado") e um commit com **todo o working tree**: os arquivos rastreados, modificados ou não, e os **não rastreados**, sem os ignorados pelo `.gitignore`. O commit é feito pelo `GitService.snapshot()`, que já existe: ele usa um índice temporário (`GIT_INDEX_FILE`), então o índice da pessoa, o que ela deixou em stage, o stash (`git stash list`) e os arquivos ficam como estavam. Com o working tree limpo, o ponto guarda só o `HEAD`.
- R3 · **Onde o ponto fica.** O commit fica numa ref oculta, `refs/promptorium/restore/<sessão>/<turno>-inicio` e `-fim`, para o `git gc` não apagá-lo. Essas refs não aparecem no `git log`, no `git branch`, no grafo do Repositório nem num `git push` comum. A tabela `restore_points` guarda a sessão (ou a conversa da VIBE), o workspace, o caminho do worktree, o turno, a hora, a branch, os shas e os números (arquivos, tamanho). O ponto vale para o worktree em que a sessão roda: uma sessão em worktree grava no worktree dela; uma sessão na raiz grava na raiz.
- R4 · **Rápido e sem travar o turno.** A gravação roda antes de a mensagem sair, com limite de 5 s. Se passar disso ou falhar (repositório sem commit, disco cheio, lock do índice), o turno segue, sem ponto, e a timeline mostra "Ponto de restauração não gravado: <motivo>". Arquivos não rastreados com mais de 20 MB ficam fora do ponto e a timeline lista os nomes ("2 arquivos grandes fora do ponto: `dump.sql`, `video.mp4`"). Um workspace que não é repositório git não grava ponto, e o botão não aparece.

### Desfazer

- R5 · **O botão.** No cabeçalho da sessão, ao lado de "Fork", fica **"Desfazer o último turno"**, com o ícone de voltar. Ele aparece quando a sessão tem pelo menos um ponto não desfeito, e fica desativado com a dica "Espere o turno terminar ou pare a sessão" enquanto um turno roda (P3). A dica do botão diz o que ele faz: "Volta os arquivos e commits ao que eram antes do turno 4 (14:02)". O mesmo comando fica na paleta (Ctrl K) e no menu de cada ponto (R9).
- R6 · **Mostrar antes de fazer.** O botão abre uma janela com o que vai acontecer, calculado pelos pontos:
  - **arquivos que voltam**: o que o agente mudou no turno (diferença entre o início e o fim do turno), com o tipo (modificado, criado → será apagado, apagado → volta) e as linhas `+`/`−`;
  - **arquivos que você mudou depois do turno** (diferença entre o fim do turno e agora, nos mesmos arquivos): vêm desmarcados e com o selo "editado por você depois" (R7);
  - **commits descartados**: os commits entre o `HEAD` do início e o atual, com o assunto;
  - o que **não volta**: arquivos ignorados, os grandes fora do ponto, e mudanças fora do worktree.
  
  Cada arquivo tem uma caixa de marcar. "Desfazer N arquivos" aplica; "Cancelar" não muda nada.
- R7 · **Edições da pessoa junto com o agente.** O app separa o que é do agente do que é da pessoa pelos dois pontos do turno:
  - um arquivo que mudou **depois** do fim do turno (fora do turno) é da pessoa: vem desmarcado e, se ela marcar, a janela avisa que essa edição se perde;
  - um arquivo que a pessoa salvou **durante** o turno pela tela Código (o app já sabe, `notifyUserEdit`) vem marcado com o selo "você também editou durante o turno";
  - um arquivo que **não** mudou no turno nunca é tocado, mesmo que esteja diferente do ponto (o trabalho da pessoa antes do turno fica como estava, como o `src/cupom.ts` do exemplo).
- R8 · **Como volta.** Ao confirmar, o app:
  1. grava um ponto **"antes de desfazer"** (o estado atual, R2), para o Refazer (R11);
  2. se o `HEAD` andou no turno, volta a branch ao `HEAD` do início (`git reset --soft` seguido da restauração dos arquivos, para não tocar nos arquivos fora da lista); se o agente trocou de branch, volta à branch do início e deixa a branch nova onde está;
  3. restaura **só os arquivos marcados** para o conteúdo do início do turno: modificados e apagados voltam ao que eram; os criados no turno são apagados;
  4. deixa o índice como estava para os arquivos não tocados;
  5. escreve na timeline "Turno 4 desfeito: 41 arquivos, 1 commit (wip). Refazer" e manda à sessão o aviso "O usuário desfez o turno 4; os arquivos voltaram ao estado anterior. Releia antes de alterar." na próxima mensagem (o mesmo caminho dos avisos de edição manual).
  
  Se algo falhar no meio, o app volta ao ponto "antes de desfazer" e mostra o erro. Nunca fica meio desfeito.
- R9 · **Os pontos da sessão.** O painel da direita da sessão ganha a seção **"Pontos de restauração"**, abaixo de "Arquivos alterados": um item por turno, do mais novo ao mais velho, com "Turno 4 · 14:02", "41 arquivos · 1 commit" e o estado (ativo, desfeito, refeito). Cada item tem o menu "Voltar a antes deste turno…", que desfaz esse turno **e todos os seguintes** com a mesma janela do R6 (os arquivos somados dos turnos). A seção mostra no máximo 5 itens e "Ver todos (12)".
- R10 · **O ponto na timeline.** Cada mensagem do usuário na timeline ganha, à direita da hora, um marcador discreto "◷ ponto" com a dica "Ponto de restauração: 14:02 · 3 arquivos não commitados guardados". Clicar abre a janela do R6 para aquele turno.
- R11 · **Refazer.** Depois de desfazer, um aviso "Turno 4 desfeito. Refazer" fica 10 s, e o item do ponto muda para "desfeito" com o botão "Refazer". Refazer volta ao ponto "antes de desfazer" com a mesma janela e as mesmas regras (R6–R8). Um turno novo depois do desfeito tira o "Refazer" (o histórico segue em frente, como em qualquer editor).
- R12 · **Commits já enviados.** Se algum commit que seria descartado já está no remoto (`git branch -r --contains`), a janela mostra o aviso "1 commit já foi enviado para origin/feat/order. Desfazer reescreve a branch e o próximo push vai precisar de --force." O botão muda para "Desfazer só os arquivos": os commits ficam e só os arquivos marcados voltam, num estado não commitado. Reescrever o histórico já enviado fica fora (P4).

### Retenção e espaço

- R13 · **Quanto tempo o ponto fica.** Por sessão, ficam os pontos dos **últimos 20 turnos**; os mais velhos são apagados quando um turno novo começa. Todos os pontos de uma sessão são apagados quando ela é integrada (merge), descartada ou apagada, e quando o worktree some. Pontos sem uso há mais de 14 dias são apagados ao abrir o app. Os pontos de uma VIBE seguem a mesma regra.
- R14 · **Configurações.** Em Configurações › Sessões, o grupo "Pontos de restauração" tem: o interruptor "Gravar um ponto antes de cada turno" (ligado por padrão), "Guardar os últimos N turnos por sessão" (padrão 20) e "Apagar pontos sem uso depois de N dias" (padrão 14), o espaço que os pontos ocupam no repositório do workspace ativo (aproximado, pelos objetos que só eles referenciam) e o botão "Apagar todos os pontos deste workspace…", com confirmação.
- R15 · **Higiene do repositório.** A limpeza de refs internas da Higiene (SPEC-047) ignora `refs/promptorium/restore/`. Hoje ela agruparia essas refs pela chave `restore`, que não é uma spec conhecida, e ofereceria apagá-las como "spec apagada". Os pontos só saem pela retenção (R13) e pelo botão do R14.

### Outros casos

- R16 · **Duas sessões no mesmo diretório.** Se outra sessão viva roda no mesmo diretório (duas sessões na raiz), a janela avisa "A sessão *Ajustar CSS* também está mexendo neste diretório; os arquivos dela podem voltar junto" e lista os arquivos que as duas mudaram. Desfazer continua possível.
- R17 · **Etapas de spec.** O "Voltar ao início da etapa" continua como está. O ponto do primeiro turno de uma etapa é o mesmo momento do checkpoint da etapa, e o app reaproveita o snapshot (não grava dois iguais).

## Fora do escopo

- Desfazer arquivos ignorados pelo `.gitignore` (`.env`, `node_modules`, `build/`) e arquivos fora do worktree (o agente escreveu em `~/` ou `/tmp`). A janela avisa que eles não voltam.
- Desfazer efeitos fora dos arquivos: banco de dados, pacotes instalados, push, PR aberto, issue criada.
- Reescrever um histórico já enviado ao remoto (R12).
- Pontos dentro de um turno (por chamada de ferramenta). O `/rewind` do Claude Code continua disponível para isso.
- Pontos para as conversas do Prompt na raiz e para o planner do Projeto.
- Submódulos: o ponto guarda só o sha do submódulo, não os arquivos dentro dele.
- Comparar dois pontos quaisquer num diff (a janela mostra só o que volta).

## Design

Canvas para validar: [Ponto de restauração](https://claude.ai/artifact/4kUbHocUqgLjPcXTuWYCg5). Ele tem quatro artboards: a sessão com os pontos, a janela de desfazer, depois de desfazer, e as configurações.

### O que já existe

- `lib/core/git/git_service.dart`: `snapshot()` (working tree com não rastreados num índice temporário, sem tocar o índice nem o stash), `restoreSnapshot`, `resetHard`, `updateRef`, `resolveRef`, `deleteRefs`, `headSha`, `subjectsSince`, `stashCreate`.
- `lib/features/board/spec_runner.dart`: `_markStart`, `rewindPreview` e `rewind` (o checkpoint por etapa, SPEC-035), modelo do que esta spec faz por turno.
- `lib/features/board/widgets/spec_steps_panel.dart`: `rewindStepAction`, a janela que lista commits e arquivos antes de voltar a etapa.
- `lib/features/sessions/session_manager.dart`: `create`, `send` (o início de cada turno), `_start` (o processo), o `case Result()` em `_handle` (o fim do turno), `notifyUserEdit` e `_notices` (as edições da pessoa pela tela Código e o aviso ao agente).
- `lib/features/prompt/conversation_manager.dart`: o turno das VIBEs, no worktree da spec (`_vibeWorktree`).
- `lib/features/sessions/session_changes.dart`: `sessionChangesProvider` (status e diff do worktree).
- `lib/features/repository/hygiene/hygiene_scan.dart`: o grupo 4, refs internas sob `refs/promptorium/`.

### Por que uma ref oculta e não uma worktree (P1)

O ponto é um commit feito com o `snapshot()` (índice temporário + `commit-tree`) e guardado com `git update-ref` numa ref sob `refs/promptorium/restore/`. Uma worktree por turno copiaria o projeto inteiro no disco a cada mensagem (lento e pesado num projeto com `node_modules`), deixaria entradas em `git worktree list` e não guardaria o estado do worktree em que o agente roda, só o de um commit. A ref custa só os objetos novos (o git deduplica os arquivos iguais entre os pontos) e leva menos de um segundo num projeto médio. O `git stash create` também foi descartado: ele não guarda os não rastreados, e o `stash -u` mexe no working tree e no stash da pessoa.

### Componentes

- **`lib/features/sessions/restore/restore_point.dart`**: `RestorePoint` (id, sessão ou conversa, worktree, turno, hora, branch, `headSha`, `treeSha` do início e do fim, estado: ativo, desfeito, refeito) e `UndoPlan`, com os arquivos (caminho, tipo, `+`/`−`, do agente, da pessoa depois, da pessoa durante), os commits, os commits já enviados e o que não volta.
- **`buildUndoPlan(...)`**: função pura que recebe as listas `--name-status` de início→fim e fim→agora, os commits, os enviados e as edições pela tela Código, e devolve o `UndoPlan` (R6, R7, R12, R16).
- **`lib/features/sessions/restore/restore_service.dart`**: `RestoreService.capture(sessão, turno, fase)`, `plan(ponto)`, `undo(ponto, arquivos)`, `redo(ponto)` e `prune()` (R1–R4, R8, R11, R13).
- **`GitService`** ganha `snapshot(maxUntrackedBytes:)` (lista os grandes que ficaram fora), `nameStatus(a, b)`, `restorePaths(sha, paths)` (volta e apaga só esses caminhos) e `pushedCommits(base)`.
- **`lib/data/repos/restore_points_repo.dart`** e a tabela `restore_points`.
- **`lib/features/sessions/widgets/undo_dialog.dart`**: a janela (R6, R12, R16). `restore_points_section.dart` no painel da sessão (R9) e o marcador na timeline (R10).
- No cabeçalho da sessão (`sessions_screen.dart`): `SmallButton` "Desfazer o último turno" (R5). Paleta: o comando "Desfazer o último turno da sessão".
- `settings_sections.dart` (Sessões): o grupo "Pontos de restauração" (R14). `hygiene_scan.dart`: ignorar `restore` (R15).

### Migração

**Precisa de migração**: a tabela nova `restore_points` (v29, ou a próxima livre quando implementar, já que outras specs podem subir a versão antes). As preferências do R14 ficam em `app_settings`, sem migração.

### Testes

- `GitService.snapshot`: guarda modificados e não rastreados, deixa de fora os ignorados e os grandes; o índice, o stage e o `git stash list` ficam iguais.
- `buildUndoPlan`: arquivo do agente marcado; arquivo da pessoa depois do turno desmarcado; arquivo intocado no turno fora da lista; arquivo criado vira "será apagado"; commits e enviados; outra sessão no mesmo diretório.
- `RestoreService.undo`: o exemplo do problema (commit + `sed` em vários arquivos + criado + apagado + `cupom.ts` da pessoa) volta exatamente ao início do turno e o `cupom.ts` fica; falha no meio volta ao "antes de desfazer"; refazer volta ao estado desfeito.
- `SessionManager.send`: grava o início; o `result` grava o fim; aviso no meio do turno não grava; mais de 5 s segue sem ponto e com a nota.
- Retenção: o 21º turno apaga o 1º; merge/descartar apaga tudo da sessão; 14 dias sem uso; a Higiene não oferece as refs `restore`.
- Telas: o botão aparece com ponto e fica desativado com turno rodando; a janela lista e desmarca certo; a seção do painel e o marcador da timeline.

## Critérios de aceite

- [ ] Antes de cada turno o app grava um ponto com o `HEAD`, a branch e o working tree com os não rastreados, sem mudar o índice nem o stash [R1, R2, R3] verificar: flutter test test/core/git/git_snapshot_test.dart
- [ ] Gravar o ponto não passa de 5 s, e uma falha deixa o turno seguir com a nota na timeline [R4] verificar: flutter test test/features/sessions/restore/restore_service_test.dart
- [ ] O plano separa o que o agente mudou, o que a pessoa mudou depois e o que não mudou no turno, com commits e enviados [R6, R7, R12, R16] verificar: flutter test test/features/sessions/restore/undo_plan_test.dart
- [ ] Desfazer o exemplo do problema volta os 40 arquivos, recria o apagado, apaga o criado, descarta o commit e mantém o arquivo da pessoa; Refazer volta ao estado desfeito [R8, R11] verificar: flutter test test/features/sessions/restore/restore_service_test.dart
- [ ] Os pontos respeitam a retenção, somem com a sessão e a Higiene não os oferece [R13, R15] verificar: flutter test test/features/sessions/restore/restore_retention_test.dart
- [ ] O botão, a janela, a seção do painel e o marcador da timeline aparecem e funcionam [R5, R9, R10] verificar: flutter test test/features/sessions/widgets/undo_dialog_test.dart
- [ ] No app, uma sessão real com `sed -i` em vários arquivos, um arquivo criado e um commit volta em um clique, com um arquivo editado à mão antes do turno intacto [R1–R12] verificar: manual (app isolado com `XDG_DATA_HOME`, prints em `docs/mockups/spec-084/app/`)
- [ ] O projeto compila e a análise estática passa [R1–R17] verificar: flutter analyze

## Decisões em aberto

- P1 · **Mecanismo: ref oculta ou worktree.** **Recomendação:** **commit numa ref oculta** (`refs/promptorium/restore/<sessão>/<turno>-inicio|fim`), feito pelo `GitService.snapshot()` que já existe (índice temporário + `commit-tree`), e não `git stash create` (não guarda os não rastreados) nem uma worktree por turno (copia o projeto, é lenta, não guarda o estado do worktree em uso). Ver "Por que uma ref oculta" acima.
- P2 · **O que o botão principal desfaz.** **Recomendação:** **o último turno**, com o rótulo "Desfazer o último turno". Desfazer a sessão inteira com um clique é destrutivo demais para o botão do cabeçalho; quem quer voltar mais usa "Voltar a antes deste turno…" num ponto mais velho (R9), que soma os turnos.
- P3 · **Desfazer com o turno rodando.** **Recomendação:** **não**. O botão fica desativado durante o turno (o agente estaria escrevendo nos mesmos arquivos). A janela oferece "Parar e desfazer" quando aberta pelo ponto com a sessão ocupada.
- P4 · **Commits já enviados.** **Recomendação:** **não reescrever** a branch remota. A janela avisa e troca o botão por "Desfazer só os arquivos" (R12). Reescrever com `--force-with-lease` fica para outra spec, se pedirem.
- P5 · **Quem grava ponto.** **Recomendação:** sessões (todas, com ou sem worktree, Claude e Codex), etapas de spec e VIBEs. **Não** as conversas do Prompt na raiz (rodam em Perguntar/Planejar e quase nunca editam) nem o planner. Se a conversa do Prompt estiver em modo que edita, entra numa spec futura.
- P6 · **Retenção.** **Recomendação:** os **últimos 20 turnos por sessão**, tudo apagado com a sessão integrada, descartada ou apagada, e **14 dias** sem uso. Configurável (R14). O espaço é pequeno porque o git guarda cada versão de arquivo uma vez só; o que pesa são arquivos grandes, que ficam fora acima de 20 MB (R4).
- P7 · **Edições da pessoa junto com o agente.** **Recomendação:** **dois pontos por turno** (início e fim), para separar o que o agente fez (início→fim) do que a pessoa fez depois (fim→agora), mais a lista de edições pela tela Código para o que foi feito durante o turno. O que a pessoa mexeu depois vem desmarcado; nada que não mudou no turno é tocado. Uma edição feita num editor externo durante o turno não tem como ser separada e conta como do agente; a janela mostra o diff do arquivo para conferir.
- P8 · **Sessões em worktree.** **Recomendação:** o ponto é do **worktree em que a sessão roda**. As refs ficam no repositório principal (são compartilhadas por todos os worktrees), com a sessão no nome, então um worktree nunca restaura o ponto de outro. Quando o worktree é removido (merge ou descartar), os pontos da sessão vão junto (R13).
- P9 · **Limite dos não rastreados grandes.** **Recomendação:** **20 MB por arquivo**, listados na nota da timeline e na janela como "não volta". Sem limite, um `dump.sql` de 2 GB entraria no repositório a cada turno.
