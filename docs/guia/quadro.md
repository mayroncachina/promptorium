# Quadro

Um cartão por spec aprovada ou concluída, em **Backlog · Em execução · Review · Feito**. O cabeçalho conta as specs em rascunho que ainda estão fora do quadro.

## Barra

- "Precisam de mim · N": filtra o que espera por você.
- **Ocultar concluídas · N**: esconde os cartões em Feito, nas Colunas e no Canvas. A escolha é lembrada por projeto.
- Filtros por Fase e Agente.
- **Colunas / Canvas**.
- **Agendar**: Autopilot diário, com horário e orçamento.
- **Executar tudo / Parar**: liga ou para o Autopilot, que executa as specs prontas respeitando dependências e o limite de paralelismo (`autopilot.paralelo`).

## Cartão

Mostra o progresso das etapas ("3/7"), a etapa atual, bloqueio por dependência (`depende-de`), agente, custo e a ação do momento: Executar, Continuar · Rn, Abrir aprovações, Responder na sessão, Confirmar alteração (a spec mudou no disco), Tentar de novo ou Ver review.

Menu do cartão: Executar com opções… (provedor, agente, modelo, esforço, modo de permissão), Executar em dobro (A/B), Ligar ou pausar o avanço automático, Etapas e sessões, Subir/Descer na coluna e Mover para….

## Execução por etapa

**Executar** cria o worktree da spec (`pr/spec-NNN-…`) e abre uma sessão com contexto limpo: a parte da spec relevante, as etapas já feitas e a de agora. O agente commita `SPEC-NNN Rn: …` e termina com a linha `ETAPA CONCLUÍDA: Rn`.

- Spec com até 3 requisitos (configurável) roda inteira numa sessão só.
- Quando o gate passa de primeira, a próxima etapa continua na mesma sessão enquanto o contexto estiver abaixo do limite (padrão 60 mil tokens), o que economiza tokens.
- Sem `## Design`, o app avisa antes: "Executar mesmo assim" ou "Gerar design".
- Com avanço automático ligado, a próxima etapa abre sozinha; com todas feitas, a spec vai para Review.
- Uma sessão por spec de cada vez; specs diferentes rodam em paralelo.

## Gate

Entre uma etapa e a seguinte, o gate confere commit, árvore limpa, testes, lint, build e os `verificar:` dos critérios da etapa. Se falhar: **Corrigir e verificar** (o agente corrige e o gate roda de novo), **Verificar de novo** ou **Commitar o que sobrou**.

O gate também conta os testes que passaram e os pulados no comando `testes:` (flutter/dart, pytest, jest, vitest, cargo) e reprova a etapa se, em relação ao último gate aprovado da mesma spec, passarem menos ou houver mais pulados. Quando essa é a única falha, **Aceitar a redução** aprova a etapa e registra os números na timeline. A primeira etapa de cada spec só registra a contagem. Desligue com `verificacao: contar-testes: false`. Critérios com `verificar: manual (…)` não rodam no gate. O diálogo da etapa ao vivo mostra o andamento.

## Checkpoints

O início de cada etapa é guardado numa ref (`refs/promptorium/SPEC-x/Rn-inicio`), incluindo arquivos não rastreados. No painel de etapas, o menu Marcar oferece "Marcar como concluída", "Voltar para pendente", "Voltar ao início da etapa…" e "Refazer etapa…".

## A/B

"Executar em dobro (A/B)" roda a spec duas vezes, em worktrees separados. Depois, "Comparar A/B" mostra as duas e você escolhe uma ou descarta as duas.

## Canvas

A visão Canvas mostra as specs como nós em ondas ("ONDA N · PRÓXIMA"), com as dependências e as referências a agentes e skills.

- Atenção · N, Camadas (Agentes, Skills, Concluídas), zoom (Aproximar, Afastar, 100%, Ajustar à tela, Ajustar à seleção) e Legenda.
- O inspetor da spec selecionada mostra de que ela depende, o que desbloqueia, as etapas e as referências, com "Abrir spec", "Ver nas colunas", "Marcar como finalizada" e "Reabrir".

## Tarefas antigas

Tarefas de versões anteriores, sem spec, aparecem num aviso com "Virar spec" ou "Descartar".
