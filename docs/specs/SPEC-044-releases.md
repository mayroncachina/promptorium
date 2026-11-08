---
id: SPEC-044
status: rascunho
depende-de: SPEC-032, SPEC-038
issue: 102
---

# Releases na tela Repositório

## Objetivo

Hoje, para lançar uma versão do projeto, a pessoa sai do Promptorium: abre o GitHub, entra em Actions, roda o workflow de release, volta de vez em quando para ver se o build passou e depois procura o PR da versão. Antes disso, para saber o que entra na versão, ela compara a última tag com a main à mão ou roda o `git cliff --unreleased` no terminal.

Esta spec cria a tela **Repositório** e começa por **Releases**. A aba mostra a linha do tempo das versões, o que já entrou na main e ainda não foi lançado, uma prévia do changelog e um botão **Criar release**, que dispara o workflow do projeto e acompanha a execução até o fim. A tela vale para qualquer projeto aberto no app. O Promptorium, com o `create-release.yml` e o git-cliff, é só o primeiro caso.

É a primeira de quatro specs da tela Repositório. As abas Grafo (SPEC-045), Atividade (SPEC-046) e Higiene (SPEC-047) usam a casca criada aqui.

Issue: [#102](https://github.com/mayroncachina/promptorium/issues/102) (sub-issue de [#101](https://github.com/mayroncachina/promptorium/issues/101)).

Mockup: [canvas do Claude Design](https://claude.ai/artifact/HcFbQPFWcM9ZWttmCgcKDw), linha "SPEC-044 · Releases". Cópia dos quadros e capturas em `docs/mockups/repositorio/` e `docs/mockups/spec-044/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-releases.png` | Aba Releases: "Não lançado" com a versão sugerida, as specs e os commits por tipo, e a linha do tempo das versões | R1, R2, R3, R4 |
| `2-criar-release.png` | Diálogo "Criar release": versão, prévia do changelog e workflow que vai rodar | R5, R6 |
| `3-acompanhando.png` | Release em andamento: jobs e etapas ao vivo e o aviso na bandeja | R7, R8 |

## Requisitos

- R1 · A barra lateral deve ganhar o item **Repositório**, depois de Review. A tela tem abas, e esta spec entrega só **Releases**. Ela mostra o repositório principal do workspace, nunca um worktree, com o nome do remoto e a branch padrão no cabeçalho (`origin · main`).
- R2 · A aba deve mostrar a linha do tempo das versões, da mais nova para a mais antiga, juntando:
  - as tags locais (`git tag --sort=-creatordate`, só as que parecem versão: `v1.2.3` ou `1.2.3`, com sufixo opcional);
  - as releases do GitHub (`gh release list --json tagName,name,isDraft,isPrerelease,isLatest,publishedAt`).
  
  Cada item mostra a versão, a data, o estado (**Publicada**, **Rascunho**, **Pré-release** ou **Só tag**), quantos commits ela trouxe em relação à anterior e quantos pacotes anexou. Ao abrir um item, aparecem as notas da release (lidas com `parseChangelogSection` quando vêm do git-cliff, inteiras quando não), os pacotes com o tamanho e o botão "Abrir no GitHub".
- R3 · No topo da linha do tempo, o card **Não lançado** deve mostrar o que está na branch padrão depois da última tag:
  - quantos commits e a lista agrupada por tipo de commit convencional (Funcionalidades, Correções, Documentação…), nos mesmos grupos do `cliff.toml` do projeto ou, sem ele, nos grupos do Promptorium;
  - as specs mergeadas nesse intervalo, com código e título, reconhecidas pela branch `spec/NNN-*` do merge ou pelo `SPEC-NNN` na mensagem. Um clique abre a spec no Quadro;
  - a **versão sugerida**: `git cliff --bumped-version` quando o projeto tem git-cliff. Sem ele, o app calcula pelas regras do semver para commits convencionais (incompatível sobe a major, `feat` sobe a minor, o resto sobe a patch). Antes da 1.0, incompatível sobe a minor e `feat` sobe a patch, como no git-cliff.
  
  Sem nenhum commit novo, o card diz "Nada novo desde vX.Y.Z" e o botão fica desabilitado.
- R4 · O card deve ter **Ver changelog**, uma prévia do texto que a versão vai ganhar: `git cliff --unreleased --tag <versão>` quando há git-cliff, ou o texto montado pelo app no mesmo formato quando não há. Na prévia, o texto é só leitura, com "Copiar".
- R5 · **Criar release** deve abrir um diálogo com:
  - a versão, preenchida com a sugerida e editável. Ela é recusada se não for semver, se já existir como tag ou se não for maior que a última;
  - a prévia do changelog de R4 para essa versão;
  - o caminho que vai ser usado (R6), com o nome do workflow e a branch;
  - o botão **Disparar release**, que é o único que age. O diálogo diz em uma linha o que acontece no GitHub (tag, release e, se o workflow fizer, PR da versão).
- R6 · O caminho da release vem, nesta ordem:
  1. de `releases: workflow:` em `.promptorium/config.yml` (o arquivo em `.github/workflows/`), com `releases: input:` para o nome do campo da versão (padrão `version`);
  2. de um único workflow do repositório com `workflow_dispatch` e "release" no nome ou no arquivo, achado pelo app;
  3. sem workflow, de `gh release create <tag> --target <branch padrão> --draft --notes-file <prévia>`, que cria só um rascunho para a pessoa publicar no GitHub.
  
  Com mais de um workflow candidato e nada configurado, o diálogo pede a escolha e oferece salvar no `config.yml`. O disparo é `gh workflow run <arquivo> --ref <branch padrão> -f <input>=<versão>`.
- R7 · Depois do disparo, a aba deve acompanhar a execução até o fim:
  - acha o run com `gh run list --workflow <arquivo> --event workflow_dispatch`, o primeiro criado depois do disparo;
  - mostra os jobs e as etapas com o estado de cada um (`gh run view <id> --json status,conclusion,jobs`) e o tempo decorrido;
  - consulta a cada 10 s com a tela aberta e a cada 60 s fora dela. Se o app fechar no meio, a consulta volta ao abrir, pelo id guardado;
  - tem "Abrir no GitHub" e, com o run em andamento, "Cancelar execução" (`gh run cancel`), com confirmação.
- R8 · No fim da execução:
  - com sucesso: uma notificação e o aviso na bandeja (SPEC-041) dizem "vX.Y.Z publicada". A linha do tempo atualiza e, se o workflow abriu um PR da versão (head `release/vX.Y.Z` ou título com a versão), o card mostra o link e "Abrir no Review";
  - com falha: a notificação diz qual job falhou. O card mostra a etapa que falhou com as últimas 40 linhas de `gh run view <id> --log-failed`, e oferece "Abrir no GitHub" e "Disparar de novo".
- R9 · Sem `gh`, sem login no `gh` ou sem remoto no GitHub, a aba ainda mostra as tags locais, o card Não lançado e a prévia. O botão Criar release fica desabilitado com o motivo e o comando que resolve (`gh auth login`). Repositório sem nenhuma tag mostra tudo desde o primeiro commit e sugere `0.1.0`.
- R10 · A paleta de comandos deve ganhar "Criar release" e "Abrir Releases".

## Fora do escopo

- Apagar ou editar releases e tags já criadas. Continua no GitHub.
- Publicar um rascunho pelo app. O caminho sem workflow (R6.3) para no rascunho.
- GitLab e outros remotos. A linha do tempo local funciona, mas o disparo é só no GitHub.
- Escrever o workflow de release para quem não tem um.
- As outras abas: Grafo (SPEC-045), Atividade (SPEC-046) e Higiene (SPEC-047).

## Design

### O que já existe

- `lib/ui/shell/navigation.dart`: `AppSection`, `navItems`, `shortcutItems` e `shortcutsVersion`, que já avisa quando os atalhos mudam.
- `lib/core/update/changelog_section.dart`: `parseChangelogSection` lê o formato do git-cliff com os grupos do `cliff.toml` (SPEC-038).
- `lib/core/update/update_check.dart`: busca a release mais nova no GitHub e já trata `ReleaseAsset`.
- `lib/core/git/git_service.dart`: `git(args)`, `resolveRef` e `currentBranch`.
- `lib/features/review/review_service.dart` e `pr_babysitter.dart`: chamam o `gh` com `_run`, leem JSON do `gh pr view` e fazem o polling dos PRs. O mesmo padrão serve para `gh run`.
- `lib/core/tray_service.dart` e o radar da bandeja (SPEC-041): avisos fora da tela.
- `lib/features/project/project_config.dart`: `ProjectConfig`, onde entra `releases:`.

### Componentes

- `lib/features/repository/repository_screen.dart` (novo): a casca da tela com as abas. As SPEC-045 a 047 só acrescentam abas.
- `lib/features/repository/releases/release_timeline.dart` (novo): junta tags e releases do GitHub em `ReleaseEntry` (versão, data, estado, commits, pacotes, notas), com funções puras testáveis.
- `lib/features/repository/releases/unreleased.dart` (novo): `Unreleased` (commits por grupo, specs, versão sugerida) e `nextVersion(commits, last)` para quando não há git-cliff.
- `lib/features/repository/releases/release_dispatcher.dart` (novo): escolhe o caminho (R6), dispara, acha o run e faz o polling (R7, R8). O id do run em andamento fica nas configurações do app, por workspace.
- `lib/core/git/gh_cli.dart` (novo): um invólucro fino para o `gh`, com `ghAvailable()`, `ghAuthStatus()` e o JSON de `release list`, `workflow list`, `workflow run`, `run list` e `run view`. Os serviços do Review podem passar a usá-lo depois. Esta spec não os muda.
- `ProjectConfig.releases`: `workflow` e `input`.
- `AppSection.repository('Repositório', null)`, entre `review` e `code`. O atalho do décimo item passa a ser `Ctrl+0`, e `shortcutsVersion` sobe para 4.

### Testes

- `test/features/repository/release_timeline_test.dart`: junção de tag e release, estados, filtro do que é versão, contagem de commits.
- `test/features/repository/unreleased_test.dart`: grupos, specs reconhecidas, `nextVersion` antes e depois da 1.0, repositório sem tag.
- `test/features/repository/release_dispatcher_test.dart`: ordem dos caminhos, workflow ambíguo, achar o run, polling com o app reaberto, sucesso e falha com `--log-failed`, sem `gh`.
- `test/features/repository/releases_tab_test.dart`: card Não lançado, validação da versão no diálogo e botão desabilitado com o motivo.

## Decisões

- **Repositório é um item da barra, não uma aba de Código.** Código é o editor de um worktree. O repositório principal, as releases e o histórico são do projeto inteiro.
- **O app dispara o workflow do projeto, não refaz a release por conta própria.** A release continua reproduzível no GitHub, e o app não precisa saber compilar o projeto. O `gh release create` fica só como rascunho, para quem ainda não tem workflow.
- **A versão sugerida vem do git-cliff quando ele existe.** Assim o app e o workflow chegam ao mesmo número.
- **Disparar sempre pede confirmação no diálogo.** Criar tag e release é público e não se desfaz pelo app.
- **Linha do tempo sem cache próprio.** Tags e releases são poucas, e ler de novo ao abrir a aba evita dados velhos.

Decisões tomadas na implementação, onde a spec não batia com o código ou deixava espaço:

- **`Ctrl+0` vai para o décimo item, e o zoom 100% muda de tecla (T1).** O `Ctrl+0` era o zoom 100% do editor (Specs e Código). Ele passa para `Ctrl+Shift+0` e `Ctrl+Numpad0`, e a folha de atalhos mostra a mudança. O `Ctrl+0` do canvas do Quadro é local e continua igual.
- **As abas são uma lista de `RepositoryTab` (T1).** Cada aba tem `id`, `label`, `builder`, um contador opcional (`count`, lido no build com `ref.watch`) e um texto opcional à direita do cabeçalho (`headerTrailing`). As SPEC-045 a 047 acrescentam uma entrada em `repositoryTabs`. A aba aberta fica salva em `repo.tab`.
- **O repositório principal vem do `--git-common-dir` (T1).** Se o workspace for um worktree, a tela mostra o repositório de onde ele saiu. A branch padrão é a HEAD do remoto, depois `branch-base:` do config, depois `main` ou `master`, depois a branch atual.
- **As notas usam `latestChanges` (T2).** A spec cita `parseChangelogSection`, mas a função da SPEC-038 se chama `latestChanges`. Ela mostra só Funcionalidades e Correções quando o texto vem do git-cliff, como o Sobre, e o texto inteiro quando não vem.
- **As releases vêm de `gh api repos/{owner}/{repo}/releases` (T2).** O `gh release list --json` não traz os pacotes, o tamanho nem as notas, e pedir cada release com `gh release view` seriam N chamadas. A API devolve tudo de uma vez. "Mais recente" é a publicada mais nova que não é pré-release, como no GitHub.
- **A linha do tempo ordena por versão, não por data (T2).** Assim um rascunho criado agora e uma tag antiga ficam no lugar certo. A contagem de commits só existe para quem tem a tag local (`git rev-list --count anterior..tag`). Uma release cuja tag não foi baixada aparece sem contagem.
- **A última tag é a maior versão local, mesmo fora da main (T2).** No Promptorium, a tag nasce na branch `release/vX.Y.Z` e só entra na main com o merge do PR da versão. Se o app exigisse uma tag ancestral da main, o card contaria de novo tudo que já foi lançado.
- **O app não faz `git fetch` sozinho (T2).** O card usa a cópia do remoto (`origin/main`) quando ela existe e a branch local quando não existe. Abrir a aba não mexe na rede além do `gh`.
- **A versão sugerida sem o binário do git-cliff (T2).** Sem `cliff.toml`, valem as regras de R3 (antes da 1.0, incompatível sobe a minor e `feat` sobe a patch). Com `cliff.toml` e sem o `git-cliff` instalado, o app segue o `[bump]` do arquivo com os padrões do git-cliff 2.x (`features_always_bump_minor` e `breaking_always_bump_major` ligados). Isso contradiz o "como no git-cliff" de R3, mas é o que faz o app e o workflow chegarem ao mesmo número, que é o objetivo da terceira decisão acima.
- **Specs só pelo assunto do commit (T2).** O `SPEC-NNN` conta no assunto, e o `spec/NNN-*` conta no merge. O corpo fica de fora, porque cita outras specs ("depende da SPEC-032") sem ter mexido nelas.
- **Os workflows são lidos de `.github/workflows/` no disco (T3).** O arquivo diz o `name:`, se há `workflow_dispatch` e quais são os inputs, sem rede. O campo da versão é o `releases: input:` do config. Sem ele, é `version` quando o workflow tem esse campo ou não declara nenhum, e o único input quando há só um. O `gh workflow list` está no `gh_cli.dart`, mas o diálogo não depende dele.
- **O rascunho sem workflow não cria a tag (T3).** O `gh release create --draft --target` só cria a tag quando o rascunho é publicado. O diálogo diz isso, e o card mostra o link do rascunho.
- **Como o run é achado (T3).** O app pega o primeiro run do `gh run list` criado a partir de 30 s antes do disparo, porque o relógio do computador e o do GitHub diferem. Depois de 5 min sem achar o run, o card avisa e manda conferir em Actions.
- **O polling fica no `ReleaseDispatcher` (T3).** É um timer de 10 s com a aba Releases montada e de 60 s fora dela. O run em andamento fica em `releases.run.<workspace>` nas configurações do app, e a `AppShell` chama `resume()` depois do splash, quando as configurações já foram lidas.
- **O fim fica no card até "Fechar" (T3).** Sucesso, falha, cancelamento ou rascunho ficam no card e na bandeja até a pessoa fechar. A notificação vai para o sistema e para o sino do app (seção `repository`).
- **O PR da versão e o Review (T3).** O app procura o PR pela head `release/<tag>` e, sem ela, pelo título com a tag. "Abrir no Review" só aparece quando uma sessão do workspace é dona do PR, porque o Review acompanha PRs de sessões. Um PR aberto pelo workflow não tem sessão, e o card oferece "Abrir PR", que abre o navegador.
- **"Disparar de novo" reabre o diálogo com a mesma versão (T3).** Se o workflow chegou a criar a tag, o próprio workflow recusa a versão. O app só conhece as tags locais e as releases, não as tags remotas sem release.

## Plano

1. Validar o mockup (tabela no início da spec).
2. Casca da tela Repositório, item da barra, atalho e paleta.
3. `gh_cli.dart`, linha do tempo e card Não lançado com a prévia.
4. Diálogo Criar release e escolha do caminho.
5. Acompanhamento do run, fim com sucesso e com falha, bandeja e notificações.
6. Guia `docs/guia/repositorio.md` e `docs/debito-tecnico.md`, se sobrar algum item.

## Critérios de aceite

- [ ] A barra mostra Repositório depois de Review, com a aba Releases, e os atalhos avisam a mudança [R1] verificar: flutter test test/features/repository/releases_tab_test.dart
- [ ] A linha do tempo junta tags e releases com os quatro estados e os commits de cada versão [R2] verificar: flutter test test/features/repository/release_timeline_test.dart
- [ ] O card Não lançado agrupa os commits, reconhece as specs e sugere a versão com e sem git-cliff [R3] verificar: flutter test test/features/repository/unreleased_test.dart
- [ ] A prévia do changelog usa o git-cliff quando existe e o formato dele quando não existe [R4] verificar: flutter test test/features/repository/unreleased_test.dart
- [ ] O diálogo recusa versão inválida, repetida ou menor que a última [R5] verificar: flutter test test/features/repository/releases_tab_test.dart
- [ ] O caminho segue config, workflow achado e rascunho, e pede a escolha com dois candidatos [R6] verificar: flutter test test/features/repository/release_dispatcher_test.dart
- [ ] O run é achado, acompanhado e retomado depois de reabrir o app [R7] verificar: flutter test test/features/repository/release_dispatcher_test.dart
- [ ] Sucesso avisa e mostra o PR da versão; falha mostra a etapa e as linhas do log [R8] verificar: flutter test test/features/repository/release_dispatcher_test.dart
- [ ] Sem `gh` ou sem login, a aba funciona só leitura e explica o motivo [R9] verificar: flutter test test/features/repository/releases_tab_test.dart
- [ ] Uma release real do Promptorium é disparada e acompanhada pelo app até o PR da versão [R5–R8] verificar: manual (Criar Release do próprio repositório)
- [ ] O projeto compila e a análise estática passa [R1–R10] verificar: flutter analyze
