# Repositório

A tela **Repositório** fica na barra lateral depois de Review (Ctrl+7). Ela mostra o repositório principal do workspace, nunca um worktree. O cabeçalho tem o nome, o remoto e a branch padrão (`promptorium · origin · main`) e, à direita, a conta do `gh`. A tela tem as abas **Releases**, **Grafo**, **Atividade** e **Higiene**.

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

## Grafo

A aba **Grafo** desenha o histórico como um grafo de raias, uma por branch. Cada linha é um commit, com as raias à esquerda e, ao lado, as etiquetas, a mensagem, a spec, o autor, a data relativa e o SHA curto. O app calcula as raias e as curvas, sem ler o `git log --graph`. O grafo só lê: nenhuma ação de git sai daqui.

### Cores

- A branch padrão fica sempre na primeira raia, em cinza claro.
- Uma branch `spec/NNN-*` ganha a cor da spec. A mesma cor aparece no ponto da spec no painel e em Releases.
- As filhas de uma spec grande (`spec/NNN-tN-*`) ficam ao lado da pai, no mesmo tom, mais claro.
- As outras branches ficam em um tom neutro.

A spec de cada commit vem da branch que o contém primeiro. No merge de um PR, vem da branch que ele trouxe. Num commit da branch padrão, vem do `SPEC-NNN` da mensagem.

### Specs recolhidas

As specs já mergeadas começam **recolhidas**: a pai e as filhas viram uma linha só, como "SPEC-042 · Sprints no Quadro: 4 tarefas, 4 mergeadas, 11 commits". A etiqueta **recolhida** expande a spec. A etiqueta `SPEC-NNN` na primeira linha da raia recolhe de novo. As specs abertas, com branch ainda não mergeada na branch padrão local ou na remota, começam expandidas.

### Etiquetas

- **Tag de versão** (âmbar): um clique abre a versão em Releases.
- **Branch**: local, e a remota (`origin/…`) só quando aponta para outro commit.
- **PR aberto** na ponta da branch, com o estado do CI: rodando, passou ou falhou. Os PRs que o babysitter acompanha vêm dele, e os outros vêm de `gh pr list`. Com uma sessão na branch, o clique abre o card no Review. Sem sessão, abre o PR no navegador.
- **Agente trabalhando**, com um ponto pulsando, na ponta da branch de um worktree em que um agente está rodando.
- **Modelo**, ao lado do autor, nos commits marcados pela linha `Promptorium-Agente` (veja [Projeto](projeto.md)): `sonnet`, `opus`, `haiku` ou `app`, quando o próprio app commitou numa etapa. O ⓘ da etiqueta mostra a origem ("SPEC-042 T4") e a linha exata da mensagem. Sem a linha, só o autor aparece. As origens das linhas na tela são lidas de uma vez, num `git log` só.

Com o ponteiro sobre uma raia, a spec dela (pai e filhas) fica em destaque e o resto esmaece. Um balão mostra o nome da branch, quantas filhas e quantos commits ela tem a mais que a branch padrão e, se já foi mergeada, quando e por qual PR.

### Filtros e busca

- **Todas as branches** (padrão) mostra todas as branches e tags locais.
- **Só a main** (o nome da branch padrão) usa `--first-parent`, com um commit por merge.
- **Specs abertas** mostra a branch padrão e as `spec/*` ainda não mergeadas.
- **Branches só no remoto** acrescenta as branches remotas que não têm cópia local.

A busca procura na mensagem, no SHA (a partir de 4 caracteres), no autor ou por `SPEC-NNN`. Ela realça os resultados e mostra "2 de 13". O **Enter** pula para o próximo resultado.

Quando a Atividade abre o Grafo filtrado por um dia, o cabeçalho mostra "Só 7 nov 2026". O × volta para todos os dias.

### Painel do commit

Clicar num commit abre o painel à direita:

- a mensagem inteira, o autor, a data e o SHA, com **Copiar SHA**;
- os pais (dois num merge), com a branch de cada um;
- as branches e tags que contêm o commit;
- a spec, com **Abrir no Quadro**;
- o PR, com **Abrir no Review**, ou **Abrir no GitHub** quando não há sessão;
- os arquivos com `+` e `−`, contados contra o primeiro pai. Num merge, isso mostra o que o merge trouxe. Cada arquivo tem **diferença**.

Com o painel aberto, a lista esconde as colunas de spec e autor. Um novo clique no commit, ou o ×, fecha o painel.

### Carregamento e atualização

A aba lê 300 commits por vez, em ordem topológica, e lê mais 300 ao chegar perto do fim da lista. As raias da página nova continuam as da anterior, sem recalcular o que já está na tela, e a lista desenha só as linhas visíveis. Quando HEAD, uma branch ou uma tag muda, a aba relê o log sozinha. O commit selecionado e a linha do topo continuam onde estavam.

## Atividade

A aba **Atividade** mostra o ritmo do projeto com números tirados só do git e das specs: em que dias se trabalhou, quanto foi funcionalidade e quanto foi correção, quanto tempo uma spec leva e quais arquivos mudam em quase toda spec. Ela lê a branch padrão (local e remota) e as branches `spec/*`. Os merges não contam como commits.

No topo, **30 dias**, **90 dias** (padrão) ou **1 ano** vale para a aba inteira. O app guarda a escolha.

### Resumo

Quatro números do período: **commits**, **specs mergeadas**, **releases** (as tags de versão, "v0.6.0 a v0.11.0") e o **ciclo mediano das specs**. Cada um é comparado com o período anterior de mesmo tamanho ("+38% que os 90 dias anteriores"). No ciclo, menos tempo aparece em verde.

### Commits por dia

Uma célula por dia, em colunas por semana (segunda no topo), com cinco tons pela quantidade de commits. Os dias com tag de versão ganham um anel. O balão diz a data, os commits e as specs que receberam commits naquele dia. Um clique abre o **Grafo** só com os commits do dia.

### Commits por tipo

Barras empilhadas por semana, com os grupos do `cliff.toml` do projeto (ou os do Promptorium, como no card Não lançado). Os commits fora do padrão de commit convencional ficam em **Outros**, e passados seis grupos, os menores também. Um clique na legenda esconde ou mostra o grupo.

### Ciclo das specs

O tempo do primeiro commit numa branch `spec/NNN-*` até o primeiro merge da spec na branch padrão. As filhas de uma spec grande contam dentro da pai. O cartão mostra a **mediana**, o **percentil 90**, as **cinco mais longas** (um clique abre a spec no Quadro) e, com sprints, a **mediana por sprint** concluída no período, em ordem. Um commit de spec feito direto na branch padrão (o arquivo da spec, por exemplo) não conta: ele mede o planejamento, que é outra pergunta.

Sem branches `spec/*`, o cartão diz "Este repositório não usa branches de spec" em vez de mostrar zero. Sem tags, o resumo diz "Sem tags no repositório" e o mapa não marca dias de release.

### Arquivos mais alterados

Os 15 arquivos com mais commits no período, com as linhas somadas (`+` e `−`) e quantas specs diferentes mexeram neles. Código gerado e lockfiles ficam de fora (`*.g.dart`, `*.freezed.dart`, `pubspec.lock`, `package-lock.json`…). Ao abrir um arquivo, o painel lista as specs que o alteraram, da mais nova para a mais antiga, cada uma com os seus commits (os três mais novos, e "+N anteriores"). A spec abre no Quadro e o commit abre no Grafo. **Ver no Grafo** seleciona o commit mais novo do arquivo e **Abrir no Código** abre o arquivo na tela Código.

### Quem fez os commits

Separa os commits do período em **você**, **agentes** e **app**, pela linha `Promptorium-Agente` que o app põe nos commits das sessões quando a marcação está ligada (veja [Projeto](projeto.md)). As barras por semana mostram as três origens. Ao lado, os totais com a porcentagem e os commits de agente por modelo. O ⓘ do título explica de onde vem a separação e desde quando o projeto marca.

As semanas antes do primeiro commit marcado ficam em cinza, como **sem marca**, e nunca contam como suas. Com a marcação desligada, o cartão diz "Este projeto não marca os commits dos agentes", e **Ligar neste projeto** abre a mesma confirmação da tela Projeto.

### Cálculo

Na primeira vez, a aba lê o histórico com `git log --numstat` e guarda o resultado em `~/.promptorium/atividade/`, com a ponta de cada branch lida. Ao abrir de novo sem commits novos, nada é lido do git. Com commits novos, só eles são lidos. Uma branch reescrita (rebase, amend) faz a aba ler tudo de novo. Os números são calculados fora da thread da interface, e os cartões aparecem como esqueleto enquanto isso.

## Sem gh

Sem o `gh`, sem login no `gh` ou sem remoto no GitHub, a aba continua mostrando as tags locais, o card Não lançado e a prévia. **Criar release** fica desabilitado, com o motivo e o comando que resolve (`gh auth login`). Um repositório sem nenhuma tag mostra tudo desde o primeiro commit e sugere `0.1.0`.

No Grafo, sem o `gh` só faltam as etiquetas de PR. O resto vem do git local.

## Higiene

Cada spec deixa rastros: a branch local, a remota, um worktree e as refs internas em `refs/promptorium/<spec>/`. Depois do merge, quase nada disso some sozinho. A aba **Higiene** mostra o que pode sair e o que precisa de atenção. A contagem no título (`Higiene · 89`) soma os itens dos quatro grupos.

A análise roda ao abrir a aba e com **Analisar de novo**. Ela só lê: nada é apagado sem você selecionar e confirmar.

### Os quatro grupos

- **Branches mergeadas**: as branches locais que já estão na branch padrão, local ou do remoto (`git branch --merged`). Entram também as mergeadas por squash, quando o `gh` diz que o PR da branch foi mergeado e a branch não tem commits depois dele. Cada linha mostra a spec, o PR e a data do último commit. Se a branch também existe no remoto e está mergeada lá, a coluna **também no remoto** tem uma caixa própria.
- **Worktrees**: os worktrees do repositório em três situações. **Órfão** é o que perdeu a pasta. **De spec fechada** é o que tem a branch mergeada ou apagada. **Parado** está sem commit há mais de 14 dias e sem sessão viva. Cada linha mostra o caminho, a branch e o espaço em disco.
- **Atrás da main**: as branches abertas com quantos commits estão atrás e à frente da branch padrão, da mais atrasada para a menos. Quando o merge daria conflito, a linha diz em quais arquivos e oferece **Abrir no Review**, onde a base é atualizada. Esse grupo só informa.
- **Refs internas**: as refs de specs já mergeadas ou apagadas, por spec. **Limpar** apaga as de uma spec, e **Limpar todas** apaga as do grupo.

### O que nunca sai

Ficam na lista, esmaecidos e sem caixa, com o motivo:

- a branch padrão e a branch atual do repositório;
- a branch de uma sessão viva;
- a branch em uso por outro worktree (`worktree em promptorium-wt/release`). Ao selecionar esse worktree, a branch é selecionada junto, porque o worktree sai primeiro;
- o worktree com alterações não commitadas, o de uma sessão viva e o bloqueado (`git worktree lock`).

### Limpar

**Limpar selecionados** abre uma confirmação com tudo o que vai sair: os worktrees com o tamanho e as branches locais. Se alguma caixa **também no remoto** estiver marcada, a confirmação tem mais uma caixa, **Apagar também no GitHub**. Sem ela, nada sai do remoto.

A ordem é worktree, branch local, branch remota e refs. O app nunca força nada:

- o worktree sai com `git worktree remove`, sem `--force`;
- a branch local sai com `git branch -d`, nunca `-D`. Se o git recusar, a linha mostra o motivo e a branch fica. Isso acontece, por exemplo, com uma branch mergeada por squash que nunca foi enviada ao remoto. Nesse caso, apague pelo terminal se tiver certeza;
- uma branch remota só sai se a local saiu.

Depois da limpeza, um aviso diz o que saiu e o espaço liberado, com **Desfazer** por 15 s. Ele recria as branches locais nos mesmos commits, com o upstream, e os worktrees das branches que voltaram. Branches apagadas no remoto e refs internas não voltam. Arquivos ignorados pelo git dentro do worktree, como `build/`, também não voltam.

### No Início

Quando a soma de branches mergeadas e worktrees de specs fechadas passa de 20, o Início mostra o card **Repositório com N itens para limpar**, que abre a aba. O × esconde o card por 30 dias.
