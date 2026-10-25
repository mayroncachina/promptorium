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

Reúne tudo o que decide o merge: estado do revisor, critérios, verificações das etapas, checks e conflitos do PR, branch do repositório principal, alterações na raiz e specs empilhadas não mergeadas. Cada item aparece como Bloqueio, Aviso ou Não verificado, com a ação que o resolve e "Verificar de novo". "Mergear mesmo assim…" exige um motivo, que fica registrado na spec.

## Merge local guiado

"Preparar merge local…" escolhe o método (Merge commit, Squash ou Rebase; rebase não é oferecido se a branch já foi publicada) e as opções: trocar para a base, guardar alterações em stash, pular hooks e apagar a branch. Em conflito, o merge é abortado e nada fica pela metade.

Depois do merge, a spec vai para Feito, as etapas ficam concluídas e o `status: concluida` é commitado à parte; o worktree e a branch são removidos.

## GitHub e GitLab

O Review identifica a hospedagem pelo remote: "GitHub · gh", "GitLab · glab" ou "Hospedagem não identificada", com "Escolher remote", "Instalar / atualizar CLI" e diagnóstico. Instâncias próprias se declaram em `hospedagem: {host, tipo}` no `.promptorium/config.yml`.

- **GitHub** (com `gh`): Criar PR ou Rascunho (`gh pr create --draft`), e o painel **Acompanhar PR**, com checks, "Verificar agora", "Mergear PR" (`gh pr merge`) e "Resolver conflito com o agente".
- **GitLab**: a hospedagem é detectada, mas criar e acompanhar MR ainda não está disponível (SPEC-013 em rascunho, DT-55). O merge local funciona.
