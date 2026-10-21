---
id: SPEC-013
status: rascunho
depende-de: [SPEC-009, SPEC-011, SPEC-012]
---

# Review no GitLab

## Objetivo

Fazer o Review funcionar com repositórios hospedados no **GitLab** (gitlab.com ou instância própria) do mesmo jeito que funciona com o GitHub: criar o merge request, acompanhá-lo, ler os checks e os comentários em linha e mergeá-lo. Hoje tudo isso é feito pelo `gh` e só existe para o GitHub; num repositório GitLab o botão "Criar PR" fica desabilitado com "GitHub CLI (gh) não encontrado" ou "o repositório não tem remote", e o app nunca olha o `glab`.

- Usa a CLI `glab` do usuário, assim como o GitHub usa o `gh`: o app não guarda o token do GitLab para esta função. (A spec de contas GitHub e GitLab, `SPEC-002-configuracao-do-github-e-gitlab.md`, trata de contas dentro das Configurações; as duas são independentes.)
- O texto da interface diz "MR" para GitLab e "PR" para GitHub, conforme o provedor da sessão.
- Fora do escopo: Bitbucket e outros hospedeiros, pipelines além de ler o estado, aprovações do GitLab (approvals), e o merge local (não depende do hospedeiro).

## Requisitos

- R1 · O sistema deve identificar o hospedeiro do repositório pelo remote (`github.com`, `gitlab.com` ou um host GitLab) e oferecer as ações do Review pelo provedor correspondente, `gh` ou `glab`, sem pedir ao usuário que escolha na maioria dos casos. Para uma instância GitLab própria, o sistema deve permitir indicar o host no `config.yml` do projeto.
- R2 · O sistema deve verificar, sem alterar nada, se a CLI do hospedeiro está instalada, autenticada e se o repositório tem remote, e mostrar o motivo em linguagem clara quando "Criar PR/MR" estiver indisponível, para GitHub e para GitLab. Esta etapa inclui rodar e registrar a sondagem do `glab` (ver Design); as etapas R3 a R6 só começam depois dela.
- R3 · "Criar MR" deve enviar a branch e criar o merge request no GitLab (inclusive como rascunho), com título e descrição iguais aos do PR (spec, etapas e critérios), e guardar o link na sessão.
- R4 · "Acompanhar" deve ler o estado do MR (aberto, mergeado, fechado), os conflitos, o estado do pipeline e os comentários, e agir como já faz com o PR: comentários novos viram uma rodada na sessão, commits do agente são enviados, e merge e conflito geram notificação.
- R5 · O sistema deve mostrar no diff os comentários em linha do MR, como os do PR na SPEC-009, e alimentar o painel "Pronto para merge?" (SPEC-011) com o estado do pipeline, o conflito e as discussões abertas do MR.
- R6 · O sistema deve mergear o MR pelo app, com as formas que o projeto GitLab permitir (merge commit, squash, rebase), e fechar a sessão e a spec como o "Mergear PR" faz hoje.

## Design

### Abstração do hospedeiro
Hoje `ReviewService` chama `gh` direto em `prAvailability`, `createPr`, `prView`, `pushIfAhead`, `mergePr`, `prChecks` e o `PrBabysitter` usa `PrStatus`/`PrComment`. Extrair:

```
abstract class ReviewHost {
  String get id;            // 'github' | 'gitlab'
  String get requestLabel;  // 'PR' | 'MR'
  Future<HostAvailability> availability(Workspace ws, String remote);
  Future<String> create(CreateRequest r);          // só cria; devolve a URL
  Future<PrStatus?> view(String url, String cwd);
  Future<List<InlineComment>> inlineComments(String url, String cwd);
  Future<List<(String, String)>> checks(String url, String cwd);
  Future<MergeOutcome> merge(String url, MergeMethod m, String cwd);
}
```
- Tipos novos do contrato:
  - `CreateRequest { head, base, title, body, draft, fill }`.
  - `InlineComment { externalId, path, line, originalLine?, commitSha?, author, body, createdAt, inReplyTo? }`.
  - `MergeOutcome { merged, localBranchDeleteFailed, pending, message }`. `localBranchDeleteFailed` preserva o caso do `gh` (merge feito, mas a branch local em uso pelo worktree não pôde ser apagada: o `mergePr` apaga a branch com `force` só nesse caso). `pending` é verdadeiro quando o merge ficou agendado (ver R6).
- O que **fica** em `ReviewService` por não depender do hospedeiro: o commit de pendências e o `git push -u` que `createPr` faz antes de criar, e `pushIfAhead` (só git, pelo upstream). O `PrBabysitter` continua chamando `pushIfAhead` no `ReviewService`.
- `merge` devolve `MergeOutcome` e inclui a conferência "já mergeado" que hoje é o `_prMerged` de `mergePr`: o `gh` sai com código 1 quando só a branch local não pôde ser apagada (ela está em uso pelo worktree) e o merge aconteceu mesmo assim. O `GitlabHost` precisa do mesmo tratamento para `glab mr merge --remove-source-branch`, confirmado na sondagem.
- `PrStatus` ganha `openThreads` (`int?`, discussões abertas; nulo = não informado). O pipeline entra em `PrStatus.checks` como **uma** entrada `("pipeline", estado)`, com o estado mapeado na tabela abaixo. O vocabulário do `PrStatus` (`OPEN`/`MERGED`/`CLOSED`, `MERGEABLE`/`CONFLICTING`/`UNKNOWN`, `APPROVED`/`REVIEW_REQUIRED`/`CHANGES_REQUESTED`) é declarado **canônico**; cada hospedeiro traduz para ele.
- `GithubHost` recebe o código que já existe, sem mudar o comportamento; a suíte atual (`review_service_test.dart`) é a rede de segurança da extração.
- `GitlabHost` implementa o mesmo contrato com `glab`.
- `PrStatus` e `PrComment` (`pr_babysitter.dart`) são neutros o bastante; ganham `host`. `PrMergeMethod` ganha o que o GitLab permitir.
- `reviewHostProvider(sessionId)` escolhe o host (R1). Os testes injetam hospedeiros falsos, como hoje injetam `commandRunnerProvider`.

### R1 · Detecção
- Ler `git remote get-url <remote>` (o mesmo remote que `prAvailability` escolhe) e extrair o host de URLs `https://`, `ssh://` e `git@host:`. `github.com` → GitHub; `gitlab.com` → GitLab; outro host → pelo `config.yml` (`hospedagem: {host: git.exemplo.com, tipo: gitlab}`), senão "hospedeiro desconhecido" com o texto de como configurar.
- A sessão guarda o hospedeiro no momento de criar o PR/MR (coluna `sessions.pr_host`, na próxima versão do esquema, `pr_url` continua), para que acompanhar e mergear usem o mesmo hospedeiro mesmo se o remote mudar. Sessões antigas, com `pr_url` e sem `pr_host`, são tratadas como GitHub. A coluna entra numa migração própria, na versão seguinte ao esquema vigente quando a spec for implementada (v17 se a SPEC-009 entrar antes); o teste de migração confere isso.

### R2 · Disponibilidade
Ordem: `ReviewService` escolhe o remote (como `prAvailability` faz hoje), checa o worktree da sessão (que não depende do hospedeiro), identifica o hospedeiro pelo remote (R1) e só então chama `host.availability(ws, remote)`, que verifica CLI e autenticação.

`HostAvailability { available, reason, remote }`, o mesmo formato de `PrAvailability`. GitLab: `which glab`, remote, `glab auth status --hostname <host>`. Cada falha tem texto próprio, e os de GitHub continuam iguais. O botão "Criar PR/MR" usa `requestLabel`.

### R3 a R6 · Comandos do `glab`
Os comandos e campos abaixo são a intenção; **cada um deve ser confirmado com uma sondagem da versão instalada do `glab`**, registrada em `docs/pesquisa/` (versão, comando, saída, limitações), como o restante do projeto faz com o `gh` e o Codex, antes de ser implementado. Não fixar uma versão mínima sem evidência.
- Criar: `glab mr create --source-branch <branch> --target-branch <base> --title … --description … [--draft] --yes`. Sem tarefa nem spec, usa `--fill`, como o `gh` faz hoje (a confirmar na sondagem).
- Detalhes que a sondagem precisa fechar: o formato da URL devolvida por `glab mr create` (o `gh` usa o último token que começa com `http`); como extrair o `iid` da URL do MR; que o `:id` do `glab api` depende de o diretório de trabalho estar dentro do repositório; se `--fill` convive com `--yes`; e o comportamento do `mr merge` agendado (R6). Se o `glab` não estiver instalado nesta máquina, a etapa da sondagem para e pede a instalação ao usuário; as etapas seguintes ficam aguardando.
- Ver: `glab mr view <url|iid> --output json`, de onde vêm estado, conflito, pipeline e comentários.
- Comentários em linha: `glab api projects/:id/merge_requests/:iid/discussions --paginate`, com `position.new_path` e `position.new_line`. Respostas ficam agrupadas na discussão.
- Mergear: `glab mr merge <iid> [--squash] [--rebase] --remove-source-branch --yes`. Os métodos disponíveis dependem da configuração do projeto GitLab; o menu mostra só os permitidos e, se não souber, os três com a mensagem de erro do GitLab em caso de recusa.
- Mapeamento para o `PrStatus` neutro (valores a confirmar na sondagem):

| GitLab | `PrStatus` |
| --- | --- |
| `opened` / `merged` / `closed` | `OPEN` / `MERGED` / `CLOSED` |
| `detailed_merge_status`: `mergeable` | `mergeable = MERGEABLE` |
| `detailed_merge_status`: `conflict` | `mergeable = CONFLICTING` |
| outro valor ou ausente | `mergeable = UNKNOWN` |
| pipeline `success` | `SUCCESS` |
| pipeline `failed` ou `canceled` | `FAILURE` |
| pipeline `created`, `pending`, `running`, `preparing`, `waiting_for_resource` | `PENDING` |
| `detailed_merge_status`: `not_approved` | `reviewDecision = REVIEW_REQUIRED` (aprovação pendente; o GitLab bloqueia no servidor, o painel só avisa) |
| `draft_status`, `need_rebase`, `ci_must_pass`, `discussions_not_resolved`, `checking` e outros | `mergeable = UNKNOWN` |
| sem aprovação exigida | `reviewDecision` vazio |
| discussões não resolvidas | `openThreads` |

### R4 · Acompanhar
O `PrBabysitter` já só depende de `ReviewService.prView` e `pushIfAhead`; com a abstração ele funciona para os dois. Notificações usam "MR" ou "PR" conforme `requestLabel`.

### R5 · Diff e painel
Os comentários de MR são gravados como os da SPEC-009 (`ReviewCommentRow`, `author = pr`, ancorados por `AnchoredComment`), com `externalId` prefixado pelo hospedeiro (`gitlab:<id>`), ao lado do `github:<id>` da SPEC-009. Contratos esperados das outras specs: da SPEC-009, `externalId` em `review_comments`, `ReviewCommentRow` e `AnchoredComment`; da SPEC-011, que o painel consuma o `PrStatus` canônico (incluindo `openThreads` e `reviewDecision`). Se algum deles mudar, o R5 é revisado antes de implementar. O painel da SPEC-011 só precisa de `PrStatus`, que já é neutro.

### R6 · Fechar a sessão
`ReviewService.mergePr` já fecha sessão, spec e worktree depois do comando. A mensagem "Atualize a branch base com git pull" vale também aqui.

### R6 · `glab mr merge` agendado
Dependendo da configuração do projeto e da versão, o `glab mr merge` pode **agendar** o merge para quando o pipeline passar, em vez de mergear na hora. Nesse caso `MergeOutcome.pending = true` e o app **não** fecha sessão, spec nem worktree: relê o MR com `view` e só fecha quando o estado for `MERGED` (o `PrBabysitter` acompanha). O painel mostra "MR aguardando o pipeline". A sondagem confirma esse comportamento.

### Riscos
- **Saída do `glab` varia entre versões**; por isso a sondagem em `docs/pesquisa/` é pré-requisito, e o parse é tolerante (campo ausente = "não informado", nunca falha o painel).
- **Instâncias próprias** com certificado interno podem falhar no `glab`; o erro dele é mostrado como está.
- **Sem testes contra o GitLab real** nesta máquina: a suíte usa `glab` falso (como `gh` hoje) e a verificação real é manual.

## Critérios de aceite

- [ ] [R1] Para os remotes `git@github.com:o/r.git`, `https://gitlab.com/o/r.git` e `ssh://git@git.exemplo.com/o/r.git` (com e sem o host no `config.yml`), o hospedeiro identificado é, respectivamente, GitHub, GitLab, GitLab e "desconhecido". verificar: `flutter test test/features/review/review_host_test.dart` (a criar)
- [ ] [R1] A extração para `ReviewHost` não muda o comportamento no GitHub: a suíte existente de criar PR, acompanhar e mergear continua passando. verificar: `flutter test test/features/review`
- [ ] [R1] A migração que acrescenta `pr_host` mantém as sessões antigas com `pr_host` nulo, tratadas como GitHub. verificar: `flutter test test/data/migration_test.dart`
- [ ] [R6] Com `MergeOutcome.pending` verdadeiro, a sessão, a spec e o worktree não são fechados e o painel mostra "MR aguardando o pipeline"; fecham quando o MR é relido como `MERGED`. verificar: `flutter test test/features/review/review_host_test.dart` (a criar)
- [ ] [R1] A chave `hospedagem:` do `config.yml` (host e tipo) é lida e escrita sem perder as outras chaves. verificar: `flutter test test/features/project/project_config_test.dart`
- [ ] [R2] Com `glab` ausente, sem autenticação ou sem remote, "Criar MR" fica desabilitado com o motivo certo; com tudo certo, habilita. verificar: `flutter test test/features/review/review_host_test.dart` (a criar)
- [ ] [R3] "Criar MR" envia a branch, roda o comando de criação com título, descrição, base e `--draft` quando pedido, e guarda a URL e o hospedeiro na sessão. verificar: `flutter test test/features/review/review_host_test.dart` (a criar, com `glab` falso e remote bare real)
- [ ] [R4] Com `reviewHostProvider` substituído por um host falso e `PrBabysitter.check` chamado direto, um MR com comentário novo gera uma rodada na sessão e a mensagem enviada à sessão. verificar: `flutter test test/features/review/pr_babysitter_test.dart` (a criar)
- [ ] [R4] Com o mesmo host falso, um MR mergeado, fechado ou com conflito gera a notificação com "MR" (e "PR" no GitHub). verificar: `flutter test test/features/review/pr_babysitter_test.dart` (a criar)
- [ ] [R5] Comentários em linha de um MR aparecem nas linhas certas do diff e o painel "Pronto para merge?" mostra pipeline, conflito e discussões abertas do MR. verificar: `flutter test test/features/review/review_host_test.dart` (a criar)
- [ ] [R6] "Mergear MR" usa o método escolhido, fecha sessão, spec e worktree, e mostra o erro do GitLab quando o método não é permitido. verificar: `flutter test test/features/review/review_host_test.dart` (a criar)
- [ ] [R2] Existe `docs/pesquisa/glab-<versão>.md` com, para cada comando (`auth status`, `mr create`, `mr view --output json`, `api …/discussions`, `mr merge`), a versão, o comando, a saída e a confirmação de cada campo assumido (`detailed_merge_status`, status do pipeline, `position.new_line`, `--fill` e `--draft`). verificar: manual (abrir o arquivo e conferir a lista)
- [ ] [R1–R6] O código novo passa na análise estática e a suíte existente continua passando. verificar: `flutter analyze && flutter test`
- [ ] [R3–R6] Num repositório real no GitLab, criar o MR, comentar em linha, acompanhar e mergear pelo app. verificar: manual (`flutter run -d linux`, Review de uma spec num repositório GitLab)

## Ordem de implementação

Sequência de implementação das specs do Review e do canvas: SPEC-009 → SPEC-010 → SPEC-011 → SPEC-012 → SPEC-013, e a SPEC-008 (independente) por último.

**Esta é a 5ª das 5 do Review.** Dependências reais: SPEC-009 (comentários em linha e `externalId`) e SPEC-011 (painel e `PrStatus`). A SPEC-012 entra pela ordem, porque ambas tocam `ReviewService.merge`/`mergePr`. É a última do Review por ser a maior (abstrai o hospedeiro e exige a sondagem do `glab`).

## Perguntas em aberto

- Esta spec usa a CLI `glab`. A spec de contas GitHub e GitLab (`SPEC-002-configuracao-do-github-e-gitlab.md`) guarda um token no app. Devem compartilhar a autenticação (o app usar o token dela no lugar do `glab auth`)? A spec assume que não, para o Review do GitHub e o do GitLab terem o mesmo modelo.
- Os dois arquivos `SPEC-002-…` de `docs/specs/` repetem o id; a dependência dessa spec de contas não pôde ser declarada no frontmatter sem ambiguidade. Renumerar antes de aprovar.
- Para instâncias próprias, o host vem do `config.yml` do projeto ou pode ser detectado perguntando à API (`/api/v4/version`)? A spec assume o `config.yml`.
- Aprovações do GitLab (approvals exigidas) bloqueiam o merge no servidor. O painel deve mostrá-las como bloqueio ou como aviso? A spec assume **aviso** (a tabela mapeia `not_approved` para `REVIEW_REQUIRED`); a decisão final é do dono do projeto.
