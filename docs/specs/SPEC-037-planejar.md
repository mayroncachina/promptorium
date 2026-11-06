---
id: SPEC-037
status: rascunho
depende-de: SPEC-017, SPEC-024
---

# Planejar: novo nome do Gerar design, refino e plano automáticos ao criar projeto

## Objetivo

"Gerar design" escreve um plano de implementação, mas o nome faz esperar telas. O Promptorium também tem Protótipo e mockups, então a confusão é fácil. Além disso, o nome é longo e destoa das ações vizinhas.

Outro problema aparece ao criar um projeto. As specs do roadmap nascem aprovadas, sem refino e sem plano. A primeira execução já abre o aviso "não tem Design", e cada spec precisa ser aberta, refinada e planejada à mão. E um plano feito antes de existir código envelhece conforme as dependências da spec ficam prontas.

Esta spec faz três coisas:

- troca o nome da ação para **Planejar** e o da seção para `## Plano`;
- faz o Promptorium refinar e planejar sozinho as specs de um projeto recém-criado e gravar o resultado nelas;
- faz o Promptorium refinar e planejar de novo uma spec quando as dependências dela terminam.

Task: [#80 · Auto Designer nas Specs](https://github.com/mayroncachina/promptorium/issues/80).

Mockup: [canvas do Claude Design](https://claude.ai/artifact/SWqLgMzWmSgMeRjsne4cuH).

## Requisitos

- R1 · A ação "Gerar design" deve se chamar **Planejar** em todos os lugares:
  - no cabeçalho da spec, entre Refinar e Aprovar;
  - no aviso de aprovar spec sem plano;
  - no aviso de executar spec sem plano, no Quadro;
  - nos textos de Configurações e da Memória do projeto;
  - no guia (`docs/guia/`) e no README;
  - o tooltip diz "Escreve o plano de implementação a partir do código atual";
  - numa spec que já tem plano, o rótulo vira "Planejar de novo".
- R2 · Os textos ligados à ação devem falar em plano, não em design:
  - em andamento: "Planejando…" e "Planejando <código>…";
  - spec bloqueada: "Bloqueada: planejando";
  - falha: "Não foi possível planejar.";
  - ao sair durante a ação: "O plano ainda está sendo escrito.";
  - concluído: "Plano pronto. Revise e salve.";
  - avisos: "A spec não tem Plano", "<código> não tem Plano" e "Aprovar sem plano (spec trivial)".
- R3 · A seção gerada deve se chamar `## Plano`:
  - Planejar escreve `## Plano`, depois de `## Requisitos`, e `## Etapas`, depois de `## Plano`;
  - o modelo de spec nova traz `## Plano`, com a dica "Use Planejar";
  - o prompt do agente pede a seção Plano;
  - as sessões recebem o trecho com o título `## Plano (trecho ligado a …)`.
- R4 · Specs com `## Design` devem continuar funcionando, sem migração:
  - todo leitor da seção aceita `## Plano` e `## Design`, e `## Plano` vence quando há as duas;
  - uma spec com `## Design` não mostra os avisos de spec sem plano;
  - rodar Planejar numa spec com `## Design` troca essa seção por `## Plano`, sem deixar as duas;
  - `design: dispensado` no frontmatter continua valendo.
- R5 · Ao criar um projeto, o Promptorium deve refinar e planejar as specs do roadmap:
  - o trabalho começa logo depois de "Criar projeto", na etapa Revisar e criar;
  - a etapa ganha a opção "Refinar e planejar as specs automaticamente", ligada por padrão;
  - com a opção desligada, a criação funciona como hoje;
  - vale só para specs criadas nesse momento, nunca para specs que já existiam.
- R6 · As specs devem passar pela fila uma de cada vez, na ordem de execução do roadmap:
  - uma spec vem depois das specs de que depende;
  - o agente de cada spec recebe o `## Plano` das specs de que ela depende, porque o repositório ainda não tem esse código;
  - refino e plano acontecem numa única rodada do agente por spec;
  - cada rodada mantém o limite de custo atual da ação.
- R7 · O resultado deve ser gravado sem revisão manual:
  - cada spec é salva assim que a rodada termina, já refinada e com `## Plano` e `## Etapas`;
  - o status da spec continua aprovada;
  - no fim, um único commit "Plano das specs" grava as specs planejadas, se a opção de commit estiver ligada;
  - uma falha nesse commit aparece na tela e não desfaz os arquivos, como já acontece no commit do plano inicial.
- R8 · O andamento deve ficar visível na etapa "Projeto criado":
  - a tela mostra "Planejando 3 de 7 · SPEC-003";
  - cada spec aparece como na fila, planejando, pronta ou com falha;
  - sair da tela não interrompe o planejamento, e voltar mostra o estado atual;
  - "Parar a fila" para a rodada atual e mantém os planos já gravados, que entram no commit;
  - depois de parar, o título diz "Fila parada" e o resumo diz "3 de 7 planejadas · fila parada";
  - as specs que faltavam aparecem como "Sem plano", e os passos não feitos ficam sem marca de concluído;
  - "Retomar a fila" continua pelas specs que faltavam.
- R9 · A falha numa spec não deve parar as outras:
  - a spec fica sem plano e a fila continua;
  - as specs que dependem dela são planejadas sem o plano que faltou e aparecem como "Plano parcial", com ícone âmbar, e não como "Pronta";
  - o fim mostra "Concluído com pendências" e "6 de 7 planejadas", com o motivo de cada falha;
  - o painel de passos mostra "Refina e planeja: 6 de 7" com um alerta, nunca como concluído;
  - "Tentar de novo" aparece na linha de cada spec com falha, e o rodapé repete todas as falhas;
  - "Tentar de novo" refaz a spec e as specs que dependem dela;
  - "Tentar de novo" faz um novo commit "Plano das specs", só com as specs refeitas;
  - fechar o app no meio deixa as specs restantes sem plano, e Planejar à mão continua disponível nelas.
- R10 · O planejamento deve se combinar com a execução:
  - "Executar a primeira etapa" abre a sessão só depois que a fila termina;
  - a sessão não abre se a pessoa parou a fila;
  - com falhas, a sessão abre, e se a própria spec falhou vale o aviso de spec sem plano;
  - enquanto a fila roda, Executar e Planejar ficam indisponíveis nas specs da fila, com o motivo "Planejando as specs do projeto";
  - o editor mostra essas specs bloqueadas para edição, para que o agente não sobrescreva texto digitado.
- R11 · Em 1100×700, nenhum dos novos textos deve ser truncado nem estourar o layout.
- R12 · A rodada automática deve refinar a spec com as mesmas regras de Refinar com IA:
  - melhora o objetivo, deixa os requisitos verificáveis, completa os critérios de aceite e escreve "Fora do escopo";
  - uma dúvida sem resposta vira item de "Perguntas em aberto" e não para a fila, e a tela mostra quantas perguntas cada spec ganhou;
  - um requisito existente mantém o número: o agente pode reescrever o texto e acrescentar requisitos, mas não pode remover nenhum;
  - o limite de 6 requisitos por spec continua valendo;
  - `id`, `status` e `depende-de` não mudam;
  - uma resposta fora dessas regras conta como falha (R9), e a spec fica como estava.
- R13 · Quando a última dependência de uma spec terminar, o Promptorium deve refinar e planejar essa spec de novo:
  - vale só para spec com `plano: automatico` no frontmatter, que a fila grava;
  - salvar a spec à mão retira essa marca, e a spec não é mais sobrescrita;
  - vale só para spec que ainda está no Backlog, nunca para uma já iniciada;
  - roda uma vez por spec, quando todas as dependências terminam, e não a cada dependência;
  - a rodada lê o código real do repositório, então não recebe os planos das dependências;
  - specs liberadas juntas entram na mesma fila, uma de cada vez;
  - enquanto a rodada acontece, Executar e o autopilot esperam, com o motivo "Atualizando o plano";
  - o fim commita só o arquivo da spec, com a mensagem "Plano atualizado: <código>";
  - numa falha, a spec fica com o plano anterior, a execução é liberada e um aviso aparece no Quadro;
  - o card dessa spec mostra "Plano anterior" até uma nova rodada dar certo ou a spec começar.

## Fora do escopo

- Escolher o provider de Planejar. Hoje ele usa o Claude, e isso continua.
- Migrar as specs antigas de `## Design` para `## Plano`.
- Renomear classes e arquivos internos (`SpecDesigner`, `spec_design.dart`, `pendingDesignProvider`) e a chave `design: dispensado`.
- Mudar o modo Planejar do Prompt e das sessões.
- Gerar protótipos automaticamente ao criar o projeto.
- Retomar a fila ao reabrir o app.
- Refinar e planejar automaticamente specs criadas por fora de "Criar projeto".

## Design

### O que já existe

- `lib/features/specs/spec_design.dart`: `designPrompt`, `designSchema`, `applyDesignAnswer` e `SpecDesigner.generate`.
- `lib/features/specs/spec_file.dart`: `SpecDocument.design`, `withDesign`, `designWaived`, `withPrototype` e o modelo de spec nova.
- `lib/features/specs/spec_action.dart`: textos de andamento, bloqueio e falha da ação.
- `lib/features/specs/widgets/spec_header.dart`: botão e tooltip.
- `lib/features/specs/specs_screen.dart`: `_approve`, `_design` e o aviso de aprovar sem plano.
- `lib/features/board/widgets/run_spec_dialog.dart`: `needsDesignWarning` e `_NoDesignDialog`.
- `lib/features/board/spec_runner.dart`: monta o trecho da spec que vai para cada sessão.
- `lib/features/specs/widgets/step_trace_panel.dart`: parágrafos da seção ligados a uma etapa.
- `lib/features/project/project_service.dart`: `materialize` e `MaterializeOutcome`.
- `lib/features/project/widgets/create_step.dart`: etapa Revisar e criar, `_create` e a abertura da primeira sessão.
- `lib/features/project/project_planner.dart`: `ProjectPlanner`, referência de `Notifier` com atividade por workspace.
- `lib/features/specs/specs_screen.dart`: `refineSpecPrompt`, com as regras de Refinar com IA.
- `lib/features/specs/spec_service.dart`: `save` e `markDone`.
- `lib/features/review/review_service.dart`: conclusão da spec depois do review.
- `lib/features/board/autopilot.dart`: início automático da próxima spec.

### R1, R2 · Nome da ação

Trocar os rótulos e as mensagens nos arquivos acima. As chaves de teste (`spec-design`, `run-no-design-generate`) não mudam, porque não aparecem para a pessoa.

### R3, R4 · Seção

`SpecDocument` ganha um único ponto de leitura para a seção, que procura `Plano` e depois `Design`. `design`, `withPrototype`, `spec_runner.dart` e `step_trace_panel.dart` passam a usar esse ponto. `withDesign` remove `## Design` antes de escrever `## Plano`.

### R5–R7, R12 · Fila

Um novo `SpecAutoPlanner`, em `lib/features/project/spec_auto_planner.dart`, é um `Notifier` com o estado da fila por workspace, fora do widget, para sobreviver à troca de tela (R8). `create_step.dart` chama `start` depois de `materialize`.

As regras de `refineSpecPrompt` viram uma constante, usada também pela fila. Um novo `SpecDesigner.refineAndPlan` roda somente leitura, recebe `dependencyPlans` no prompt e devolve no JSON, além de `design` e `etapas`, as seções refinadas. Uma função pura aplica a resposta e valida o R12 antes de gravar. A fila segue a ordem de `roadmap.specs` depois de `normalized()`, confirmando que uma dependência vem antes da spec que depende dela. O texto é salvo por `SpecService.save`, com `expectedText` para não sobrescrever uma mudança no arquivo.

### R8–R10 · Tela e bloqueios

`create_step.dart` observa a fila e mostra o andamento. Specs e Quadro consultam a fila para aplicar o bloqueio do R10. `runSpec` da primeira etapa passa a aguardar o fim da fila.

### R13 · Replanejar

A conclusão de uma spec (`markDone` e o fim do review) avisa `SpecAutoPlanner`, que procura as specs dependentes com todas as dependências concluídas e as coloca na fila. O salvamento pelo editor retira `plano: automatico`. `runSpec` e `autopilot.dart` consultam a fila antes de iniciar uma spec.

Riscos:

- o refino e o plano numa rodada só podem estourar o limite de custo atual, que hoje cobre só o plano;
- uma spec aprovada ganha requisitos sem passar por uma pessoa (D3);
- sem o commit do arquivo da spec, a worktree da execução parte do plano antigo;
- `SpecService.save` precisa aceitar a gravação em spec aprovada sem mudar o status;
- com muitas specs, a fila leva vários minutos, e a sessão da primeira etapa espera por ela (D4).

## Critérios de aceite

- [ ] O cabeçalho mostra Planejar, e nenhum texto da interface diz "Gerar design" [R1] [R2] verificar: flutter test test/features/specs
- [ ] Planejar escreve `## Plano` e `## Etapas`, e as sessões recebem o trecho do plano [R3] verificar: flutter test test/features/specs/spec_design_test.dart
- [ ] Uma spec só com `## Design` não mostra os avisos e entrega o trecho às sessões [R4] verificar: flutter test test/features/board/run_spec_design_test.dart
- [ ] Planejar numa spec com `## Design` deixa só `## Plano` [R4] verificar: flutter test test/features/specs/spec_design_test.dart
- [ ] Criar um projeto com a opção ligada refina e planeja todas as specs do roadmap, e com ela desligada nenhuma [R5] verificar: flutter test test/features/project/spec_auto_planner_test.dart
- [ ] Uma spec é planejada depois das suas dependências e recebe o plano delas [R6] verificar: flutter test test/features/project/spec_auto_planner_test.dart
- [ ] Os planos ficam gravados, o status continua aprovada e há um único commit "Plano das specs" [R7] verificar: flutter test test/features/project/spec_auto_planner_test.dart
- [ ] O andamento continua certo depois de sair da tela e voltar [R8] verificar: flutter test test/features/project/project_screen_test.dart
- [ ] Parar a fila mantém os planos prontos no commit, mostra "Fila parada" e deixa sem marca os passos não feitos [R8] verificar: flutter test test/features/project/spec_auto_planner_test.dart
- [ ] Retomar a fila planeja só as specs que faltavam [R8] verificar: flutter test test/features/project/spec_auto_planner_test.dart
- [ ] Uma falha não para a fila, e "Tentar de novo" refaz a spec e as dependentes dela [R9] verificar: flutter test test/features/project/spec_auto_planner_test.dart
- [ ] Spec planejada sem o plano da dependência aparece como "Plano parcial", e o painel mostra "6 de 7" com alerta [R9] verificar: flutter test test/features/project/project_screen_test.dart
- [ ] A primeira sessão abre só depois do fim da fila, não abre com a fila parada, e as specs da fila ficam bloqueadas até lá [R10] verificar: flutter test test/features/project/project_screen_test.dart
- [ ] Em 1100×700 não há estouro de layout [R11] verificar: flutter test test/features/project/project_screen_test.dart
- [ ] A rodada grava a spec refinada, e os requisitos existentes mantêm o número [R12] verificar: flutter test test/features/project/spec_auto_planner_test.dart
- [ ] Uma resposta que remove requisito ou passa de 6 conta como falha e deixa a spec como estava [R12] verificar: flutter test test/features/project/spec_auto_planner_test.dart
- [ ] Concluir a última dependência replaneja a spec uma vez, e concluir as anteriores não [R13] verificar: flutter test test/features/project/spec_auto_planner_test.dart
- [ ] Spec salva à mão ou já iniciada não é replanejada [R13] verificar: flutter test test/features/project/spec_auto_planner_test.dart
- [ ] Executar e autopilot esperam a rodada, e uma falha mantém o plano anterior, libera a execução e marca o card com "Plano anterior" [R13] verificar: flutter test test/features/board

## Decisões

- D1 · O nome é "Planejar", e não "Gerar plano técnico", porque cabe na barra e combina com Refinar e Aprovar. O app já usa "Planejar" no modo do Prompt e no planejamento de projeto, mas a ação fica dentro da spec, onde o sentido é claro.
- D2 · O código interno mantém o nome `design`. Renomear aumentaria o diff sem mudar nada para quem usa.
- D3 · "Ajustado automaticamente" inclui refinar: o agente pode reescrever requisitos e critérios sem revisão manual, dentro dos limites do R12. As perguntas que sobrarem ficam visíveis na spec, sem parar a fila.
- D4 · A primeira sessão espera a fila inteira, e não só o plano da primeira spec. Assim, a sessão não concorre com o commit do plano nem parte de um repositório sem ele.
- D5 · A fila roda uma spec de cada vez porque cada plano alimenta o das specs dependentes (R6).
- D6 · A opção da etapa Revisar e criar vem ligada, mas pode ser desligada, porque a fila gasta uma rodada de agente por spec.
- D7 · A marca `plano: automatico` protege o que a pessoa editou: uma spec salva à mão nunca é sobrescrita pelo R13.
- D9 · A tela usa "Parar a fila", e não "Cancelar", porque abaixo de "Projeto criado" a palavra parecia desfazer o projeto.
- D10 · Parar a fila não abre a primeira sessão: quem parou quer decidir o próximo passo (R10). Com falhas a sessão abre, porque a fila terminou.
- D11 · A escala de espaçamento, o separador "·" e o texto de 11px seguem o app, mesmo com a validação apontando esses itens. Mudar só aqui criaria inconsistência.
- D8 · O R13 commita sozinho, mesmo sem a opção de commit da criação, porque a execução parte do repositório. Se o arquivo da spec nunca foi commitado, o commit falha e isso aparece no aviso.
- D12 · A rodada automática usa o mesmo limite de Planejar, US$ 1,00, como pede o R6. A constante própria (`SpecDesigner.autoPlanBudgetUsd`) permite mudar só esse valor. O limite é defensável porque a leitura do repositório domina o custo: na criação o repositório quase não tem código, e estourar o limite conta como falha (R9), sem gravar nada. Esse custo não foi medido com execução real.
- D13 · Parar a fila cancela de vez a primeira sessão: retomar a fila não a abre (D10).
- D14 · Executar e o editor ficam bloqueados até o fim da passada, inclusive nas specs já prontas, porque o commit só sai no fim. A faixa diz "até a fila passar por ela" nas specs que faltam e "até a fila terminar" nas prontas.
- D15 · O aviso de spec concluída sai de `SpecService._upsert`, na mudança do status para concluída. Isso cobre `markDone`, o fim do review, a verificação da implementação e uma conclusão feita no arquivo.
- D16 · "Uma vez por spec" e o aviso "Plano anterior" ficam em memória, como a fila. Reabrir o app apaga o aviso, e uma dependência reaberta e concluída de novo depois disso pode replanejar a spec.
- D17 · Além do salvamento pelo editor, salvar as respostas das perguntas e abrir Refinar com IA retiram a marca, porque são edições da pessoa. Clonar uma spec não copia a marca. Uma edição feita fora do app não é detectada.
- D18 · "Tentar de novo" não refaz uma dependente salva à mão ou já iniciada (D7). Ela fica como estava.
- D19 · A rodada automática conta como falha uma resposta sem objetivo, requisitos, critérios, "Fora do escopo", plano ou etapas, ou com um título `##` dentro do texto, que abriria uma seção nova na spec (R12).
- D20 · A primeira sessão abre por um widget do shell (`FirstRunHost`), porque a pessoa pode ter saído da tela: o diálogo aparece onde ela estiver.
- D21 · Uma falha só no commit do R13 mostra o aviso, mas não marca "Plano anterior", porque o plano novo já está no arquivo. O aviso não oferece "Tentar de novo".
- D22 · O arquivo gerado pelo roadmap não ganha o `## Plano` vazio do mockup 5, para que a criação com a opção desligada continue como hoje. O painel lateral mantém o título em maiúsculas de `SidePanel`, e a lista de arquivos da etapa mantém todas as specs, como antes.

## Perguntas em aberto

Nenhuma.
