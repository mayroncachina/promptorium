# Review

Specs e sessões terminadas entram na fila **Aguardando review**. Um item por spec, com o diff da branch inteira contra o merge-base (commits, alterações não commitadas e arquivos não rastreados).

## Diff

- "Um arquivo / Todos os arquivos" e "Unificado / Lado a lado".
- **Alterações desde…**: "Desde a última rodada" mostra só o que mudou depois da última revisão; "Diff completo" volta ao todo; "Todas as etapas" separa os commits por etapa.
- Aceitar ou **rejeitar hunk** (`git apply -R`).

## Comentários

Comente qualquer linha. O filtro Comentários mostra os seus, os do revisor automático e os do PR, com "Só abertos". "Tratado" é um estado local: não resolve a conversa no GitHub.

**Pedir ajustes ao agente** envia os comentários à sessão, e a spec volta para Em execução.

## Revisor automático

Ao chegar no Review, um agente revisor pode fazer uma rodada (REV1, REV2…) e deixar comentários. "Pular revisor" dispensa a rodada.

## Critérios de aceite

O painel da spec lista os critérios com quem os marcou. **Marcar N** marca de uma vez todos os que podem ser marcados, com "Desfazer"; critérios com `verificar:` ainda não confirmado ficam de fora.

## Pronto para merge?

Reúne tudo o que decide o merge: estado do revisor, critérios, verificações das etapas, resolução do conflito, checks e conflitos do PR, branch do repositório principal, alterações na raiz e specs empilhadas não mergeadas. Cada item aparece como Bloqueio, Aviso ou Não verificado, com a ação que o resolve e "Verificar de novo". "Mergear mesmo assim…" exige um motivo, que fica registrado na spec.

## Conflito resolvido pelo agente

Quando a spec conflita com a base, "Resolver com o agente" (no painel do conflito, no PR, depois de refazer a base de uma filha ou em "Passar para o agente", durante um rebase manual) guarda a ponta da branch em `refs/promptorium/<spec>/antes-da-resolucao` e pede ao agente que junte os dois lados e termine a resposta com `## Como resolvi`, uma linha por arquivo.

Quando o agente termina, o app confere o resultado no worktree, fora do agente, com o **gate da resolução**, nesta ordem: árvore limpa, nenhum marcador `<<<<<<<`/`=======`/`>>>>>>>` nos arquivos que estavam em conflito, a branch contém a ponta atual da base, `testes:`, `lint:` e `build:` do projeto, os `verificar:` dos critérios (menos os manuais) e a contagem de testes comparada com o último gate aprovado da spec. O gate para na primeira falha.

O card e o cabeçalho mostram o estado: "Agente resolvendo o conflito…", "Conferindo a resolução · testes", "Conflito resolvido · gate aprovado", "Resolução reprovada no gate · testes" ou "A base mudou · resolver de novo".

- **Reprovada**: o relatório mostra o item que falhou e três saídas. **Corrigir e verificar** envia o relatório ao agente e roda o gate de novo quando ele terminar. **Desfazer a resolução** volta a branch ao SHA de antes; se o worktree tiver alterações não commitadas, nada é feito e o motivo aparece. **Resolver eu mesmo** desfaz e começa o rebase manual, parado nos conflitos.
- **Aprovada**: "O que a resolução decidiu" mostra, para cada trecho, o lado da base, o lado da spec e o resultado do agente (`git show --remerge-diff` quando o agente fez um merge), ao lado da linha de `## Como resolvi` daquele arquivo. Sem a seção, aparece a resposta inteira. Em git anterior ao 2.36, a tela mostra `git show --cc` e avisa.
- **Desatualizada**: a base andou enquanto o agente resolvia, enquanto o gate rodava ou depois dele. O gate não aprova esse resultado: use "Resolver de novo".

Em "Pronto para merge?", o item **Resolução do conflito** bloqueia enquanto a resolução estiver em andamento, reprovada ou desatualizada, e passa quando o gate aprovou a ponta atual da branch. "Mergear mesmo assim…" continua disponível, com motivo. Cada resolução fica no histórico da spec (quem começou, arquivos, resultado de cada gate e SHA).

### Resolução automática

Com `review: resolver-conflitos: automatico` no `.promptorium/config.yml` (o padrão é `manual`), o app começa a resolução sozinho quando a previsão de conflito com a base acusa um conflito ou quando refazer a base de uma filha conflita: uma spec por vez, e só se não houver sessão rodando na spec. Se o gate reprovar a primeira resolução, o app pede "Corrigir e verificar" uma única vez; depois, as correções são com você. Uma notificação avisa o resultado. O merge nunca é feito sozinho.

```yaml
review:
  resolver-conflitos: automatico
```

## Merge local guiado

"Preparar merge local…" escolhe o método (Merge commit, Squash ou Rebase; rebase não é oferecido se a branch já foi publicada) e as opções: trocar para a base, guardar alterações em stash, pular hooks e apagar a branch. Em conflito, o merge é abortado e nada fica pela metade.

Depois do merge, a spec vai para Feito, as etapas ficam concluídas e o `status: concluida` é commitado à parte; o worktree e a branch são removidos.

## GitHub e GitLab

O Review identifica a hospedagem pelo remote: "GitHub · gh", "GitLab · glab" ou "Hospedagem não identificada", com "Escolher remote", "Instalar / atualizar CLI" e diagnóstico. Instâncias próprias se declaram em `hospedagem: {host, tipo}` no `.promptorium/config.yml`.

- **GitHub** (com `gh`): Criar PR ou Rascunho (`gh pr create --draft`), e o painel **Acompanhar PR**, com checks, "Verificar agora", "Mergear PR" (`gh pr merge`) e "Resolver conflito com o agente".
- **GitLab**: a hospedagem é detectada, mas criar e acompanhar MR ainda não está disponível (SPEC-013 em rascunho, DT-55). O merge local funciona.
