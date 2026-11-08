# Repositório

A tela **Repositório** fica na barra lateral depois de Review (Ctrl+7). Ela mostra o repositório principal do workspace, nunca um worktree. O cabeçalho tem o nome, o remoto e a branch padrão (`promptorium · origin · main`) e, à direita, a conta do `gh`. Por enquanto a tela tem só a aba **Releases**. Grafo, Atividade e Higiene chegam nas próximas versões.

## Releases

A aba lê tudo ao abrir. Ela não guarda cópia, então o que aparece é sempre o estado atual.

### Não lançado

O card do topo mostra o que está na branch padrão depois da última tag:

- quantos commits e a lista por tipo (Funcionalidades, Correções, Documentação…), nos grupos do `cliff.toml` do projeto ou, sem ele, nos grupos do Promptorium;
- as **specs mergeadas** no intervalo, reconhecidas pela branch `spec/NNN-*` do merge ou pelo `SPEC-NNN` no assunto do commit. Um clique abre a spec no Quadro;
- a **versão sugerida**: a do `git cliff --bumped-version` quando o projeto tem git-cliff instalado. Sem ele, o app calcula pelos commits convencionais (incompatível sobe a major, `feat` sobe a minor, o resto sobe a patch). Antes da 1.0 sem `cliff.toml`, incompatível sobe a minor e `feat` sobe a patch. Com `cliff.toml`, vale o `[bump]` dele.

**Ver changelog** mostra o texto que a versão vai ganhar, no formato do git-cliff, com "Copiar". Sem commits novos, o card diz "Nada novo desde vX.Y.Z".

O card usa a cópia do remoto (`origin/main`) quando ela existe. O app não faz `git fetch` sozinho.

### Versões

A linha do tempo junta as tags locais que parecem versão (`v1.2.3`, `1.2.3`, com sufixo opcional) e as releases do GitHub, da versão mais nova para a mais antiga. Cada linha mostra o estado (**Publicada**, **Rascunho**, **Pré-release** ou **Só tag**), a data, os commits desde a versão anterior e os pacotes. Ao clicar numa versão, o painel da direita mostra as notas, os pacotes com o tamanho e "Abrir no GitHub".

## Criar release

**Criar release** abre um diálogo com:

- a **versão**, preenchida com a sugerida. Ela é recusada se não for X.Y.Z, se a tag já existir ou se não for maior que a última;
- **como a release vai ser feita**: o workflow, a branch e o comando exato;
- a **prévia do changelog** para a versão digitada;
- uma linha com o que acontece no GitHub. Tag e release não se desfazem pelo app.

Só **Disparar release** age. Ele também está na paleta (Ctrl+K, "Criar release").

### Qual caminho o app usa

1. O workflow de `releases:` no `.promptorium/config.yml`:

   ```yaml
   releases:
     workflow: create-release.yml   # em .github/workflows/
     input: version                 # campo da versão (padrão: version)
   ```

2. Sem config, o único workflow com `workflow_dispatch` e "release" no nome ou no arquivo. Com mais de um, o diálogo pede a escolha e oferece salvá-la no `config.yml`.
3. Sem workflow, um **rascunho** com `gh release create <tag> --target <branch> --draft`, com a prévia como notas. A tag nasce quando você publica o rascunho no GitHub.

O disparo é `gh workflow run <arquivo> --ref <branch padrão> -f <input>=<versão>`.

### Acompanhando

Depois do disparo, o card mostra a execução: os jobs, a etapa de cada um e o tempo. Ele atualiza a cada 10 s com a aba aberta e a cada 60 s fora dela. Se o app fechar no meio, o acompanhamento volta quando ele abre de novo. Com a execução em andamento, há "Abrir no GitHub" e "Cancelar execução", que pede confirmação.

A bandeja mostra a release numa seção **Releases** (`release v0.12.0 · 1 de 4 jobs`). Um clique abre a aba.

No fim:

- **com sucesso**, uma notificação diz "vX.Y.Z publicada", e a linha do tempo atualiza. Se o workflow abriu um PR da versão (head `release/vX.Y.Z` ou título com a versão), o card mostra o link;
- **com falha**, a notificação diz qual job falhou. O card mostra a etapa e as últimas 40 linhas do log (`gh run view --log-failed`), com "Abrir no GitHub" e "Disparar de novo".

"Fechar" tira o resultado do card e da bandeja.

## Sem gh

Sem o `gh`, sem login no `gh` ou sem remoto no GitHub, a aba continua mostrando as tags locais, o card Não lançado e a prévia. **Criar release** fica desabilitado, com o motivo e o comando que resolve (`gh auth login`). Um repositório sem nenhuma tag mostra tudo desde o primeiro commit e sugere `0.1.0`.
