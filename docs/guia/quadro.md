# Quadro

Um cartão por spec aprovada ou concluída, em **Backlog · Em execução · Review · Feito**. O cabeçalho conta as specs em rascunho que ainda estão fora do quadro.

## Barra

- **Sprint**: escolhe o que Colunas, Grafo e Foco mostram. Veja [Sprints](#sprints).
- "Precisam de mim · N": filtra o que espera por você.
- **Ocultar concluídas · N**: esconde os cartões em Feito, nas Colunas, no Grafo e na pasta do Foco. A escolha é lembrada por projeto.
- Filtros por Fase e Agente. Numa janela estreita, os filtros se juntam no chip **Filtros · n**, que abre um menu com cada um.
- **Colunas / Grafo / Foco**, no centro da barra: um controle só. Com o foco nele (Tab), as setas trocam de visão.
- **Agendar**: Autopilot diário, com horário e orçamento.
- **Executar tudo / Parar**: liga ou para o Autopilot, que executa as specs prontas respeitando dependências e o limite de paralelismo (`autopilot.paralelo`). Agendar e Executar tudo ficam sempre à direita; a linha de estado do Autopilot encurta antes deles.

O botão **Nova spec** da barra de título reage ao mouse (o "+" gira e um reflexo cruza o botão), encolhe ao clicar e mostra um anel com o foco do teclado. Num workspace sem nenhuma spec, ele respira devagar até você passar o mouse ou criar a primeira. Com movimento reduzido no sistema, só a cor muda.

## Sprints

Sprints separam as specs para o Quadro não virar uma lista longa. Elas não têm prazo e ficam só no banco local: mover uma spec não muda nenhum arquivo.

- **Seletor**: mostra a sprint Ativa, as Planejadas, "Sem sprint" e "Todas", com o progresso de cada uma. A escolha é lembrada por projeto.
- **Nova sprint**: a primeira já nasce Ativa. Só uma sprint fica Ativa por vez.
- **Mover**: use "Mover para sprint" no menu do cartão ou "Organizar sprints" para mover várias de uma vez. Uma spec recém-aprovada entra em "Sem sprint".
- **Outras sprints**: uma faixa avisa quando algo em outra sprint espera por você. Início, a bandeja e as notificações mostram tudo, sem filtro.
- **Dependências**: no Grafo, uma dependência de outra sprint aparece tracejada, e em âmbar quando bloqueia. Clicar nela leva à sprint dela.
- **Concluir sprint**: as specs feitas ficam, e as não feitas vão para a sprint escolhida. Quem estiver em execução continua rodando. A próxima sprint só é ativada se você marcar.
- **Autopilot**: com uma sprint Ativa, ele só inicia specs dela. Executar manualmente continua possível em qualquer sprint.

## Cartão

Mostra o progresso das etapas ("3/7"), a etapa atual, bloqueio por dependência (`depende-de`), agente, custo e a ação do momento: Executar, Continuar · Rn, Abrir aprovações, Responder na sessão, Confirmar alteração (a spec mudou no disco), Tentar de novo ou Ver review.

Menu do cartão: Executar com opções… (provedor, agente, modelo, esforço, modo de permissão), Executar em dobro (A/B), Ligar ou pausar o avanço automático, Etapas e sessões, Subir/Descer na coluna e Mover para….

### Tremor de atenção

Um cartão que precisa de você dá um tremor curto (menos de meio segundo) nas Colunas, no Grafo e no Foco:
- **Quando:** assim que passa a esperar por você e, depois, um cartão a cada 5 s, revezando, nunca dois juntos.
- **Quando para:** quando você passa o mouse, foca ou seleciona o cartão; depois de 6 tremores seguidos (até o motivo mudar); durante um arraste, com um diálogo aberto ou com a janela sem foco.
- **Sem tremor:** com movimento reduzido no sistema ou com a opção desligada em [Configurações › Aparência](configuracoes.md#aparência), fica só o halo âmbar.

## Execução por etapa

**Executar** cria o worktree da spec (`pr/spec-NNN-…`) e abre uma sessão com contexto limpo: a parte da spec relevante, as etapas já feitas e a de agora. O agente commita `SPEC-NNN Rn: …` e termina com a linha `ETAPA CONCLUÍDA: Rn`.

- Spec com até 3 requisitos (configurável) roda inteira numa sessão só.
- Quando o gate passa de primeira, a próxima etapa continua na mesma sessão enquanto o contexto estiver abaixo do limite (padrão 60 mil tokens), o que economiza tokens.
- Sem `## Plano`, o app avisa antes: "Executar mesmo assim" ou "Planejar".
- Enquanto o app escreve o plano de uma spec, Executar e o autopilot esperam. O cartão mostra "Planejando as specs do projeto" ou "Atualizando o plano".
- Quando a atualização do plano falha, a spec mantém o plano anterior e pode ser executada. O Quadro mostra um aviso com "Tentar de novo", e o cartão diz "Plano anterior" até uma nova rodada dar certo ou a spec começar.
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

A visão Grafo mostra as specs como nós em ondas ("ONDA N · PRÓXIMA"), com as dependências e as referências a agentes e skills.

- Atenção · N, Camadas (Agentes, Skills, Concluídas), zoom (Aproximar, Afastar, 100%, Ajustar à tela, Ajustar à seleção) e Legenda.
- O inspetor da spec selecionada mostra de que ela depende, o que desbloqueia, as etapas e as referências, com "Abrir spec", "Ver nas colunas", "Marcar como finalizada" e "Reabrir".

## Tarefas antigas

Tarefas de versões anteriores, sem spec, aparecem num aviso com "Virar spec" ou "Descartar".

## Foco

A visão Foco mostra uma spec de cada vez. As specs ficam na pasta à esquerda, da mais nova para a mais antiga, e a seta do cabeçalho recolhe a pasta até sobrarem só os números.

- **Passar o mouse** numa linha mostra o card completo.
- **Buscar**: `/` ou `Ctrl+F` focam a busca, que compara número e título. `↑`/`↓` escolhem o resultado, `Enter` abre e `Esc` limpa.
- **Sprints**: a pasta mostra a sprint escolhida. Em "Todas", as specs ficam em seções recolhíveis. Uma busca sem resultado na sprint oferece "Buscar em todas", também por `Enter`.
- **Clicar numa spec** leva a spec ao palco, com as specs que dependem dela abaixo. Acima do card aparece de quem ela depende, e cada código leva aquela spec ao centro.
- **Clicar na spec do centro** abre o painel de detalhes.
- **Executando · N** mostra as specs em execução lado a lado, com a etapa atual de cada uma.
- **Voltar à pasta** ou `Esc` esvaziam o palco. Com o painel aberto, `Esc` fecha primeiro o painel.
