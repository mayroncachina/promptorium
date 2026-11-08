---
id: SPEC-043
status: rascunho
depende-de: SPEC-032, SPEC-023
issue: 99
---

# Conflito resolvido pelo agente, conferido pelo gate

## Objetivo

Quando uma spec entra em conflito com a base, o Review já oferece "Resolver conflito com o agente" (SPEC-032 R17), no PR, depois de refazer a base de uma filha (R7) e durante o rebase manual ("Passar para o agente"). O agente junta os dois lados, diz que rodou os testes e commita. Hoje o app confia nessa resposta: nada confere o resultado fora do agente, e o merge fica liberado assim que a sessão termina.

Esta spec faz o app conferir a resolução com o mesmo gate das etapas (SPEC-023), rodado no worktree, fora do agente, antes de liberar o merge. Ela também mostra exatamente o que o agente decidiu em cada trecho em conflito, e permite que o app comece a resolução sozinho quando o projeto pedir.

A ideia vem do gitai (github.com/feder-cr/git-ai), uma versão aberta do Scion, o sistema de versionamento para agentes descrito pela Anthropic: a resolução de um modelo é só uma proposta, e só vale se a verificação configurada passar na árvore exata que vai entrar. Aqui, quem decide o merge continua sendo a pessoa.

Issue: [#99](https://github.com/mayroncachina/promptorium/issues/99).

Mockup: [canvas do Claude Design](https://claude.ai/artifact/WVLos1yqpJaJ6pZCN6x6zG). Cópia dos quadros e capturas em `docs/mockups/spec-043/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-conferindo.png` | Gate rodando na resolução, estados no card e aviso da resolução automática | R1, R2, R6 |
| `2-reprovada.png` | Resolução reprovada, com o relatório e as três saídas | R3, R6 |
| `3-o-que-decidiu.png` | Gate aprovado e o que o agente decidiu em cada trecho | R4, R8 |
| `4-desatualizada.png` | "Pronto para merge?" com a resolução desatualizada | R5, R7 |

## Requisitos

- R1 · Quando o agente terminar uma resolução de conflito (`resolveConflict`, "Passar para o agente" ou a resolução automática de R6), o sistema deve rodar o gate no worktree da spec, fora do agente, com estes itens em ordem:
  - árvore limpa e nenhum marcador `<<<<<<<`, `=======` ou `>>>>>>>` nos arquivos que estavam em conflito;
  - a branch contém a ponta atual da base (`git merge-base --is-ancestor <base> HEAD`);
  - os comandos `testes:`, `lint:` e `build:` do projeto;
  - os `verificar:` de todos os critérios da spec, menos os `manual (…)`;
  - a contagem de testes, comparada com o último gate aprovado da spec (SPEC-023 R2).
- R2 · O card da fila e o cabeçalho da spec devem mostrar o estado da resolução, com ícone e texto:
  - "Agente resolvendo o conflito…";
  - "Conferindo a resolução…", com o item do gate que está rodando;
  - "Conflito resolvido · gate aprovado";
  - "Resolução reprovada no gate", com o primeiro item que falhou.
- R3 · Com a resolução reprovada, a tela deve oferecer:
  - **Corrigir e verificar**: envia o relatório do gate à sessão e roda o gate de novo quando ela terminar;
  - **Desfazer a resolução**: volta a branch ao SHA de antes da resolução, guardado em `refs/promptorium/<chave>/antes-da-resolucao`, sem tocar no worktree se houver alterações não commitadas (nesse caso, explica o motivo e não faz nada);
  - **Resolver eu mesmo**: o caminho manual da SPEC-032 R17.
- R4 · Com o gate aprovado, o Review deve mostrar "O que a resolução decidiu":
  - para cada arquivo que estava em conflito, a diferença entre o merge automático do git e o resultado do agente (`git show --remerge-diff`), mostrando os dois lados e a versão final;
  - ao lado, a explicação do agente para aquele arquivo, tirada da seção `## Como resolvi` da resposta. Se a seção faltar, mostra a resposta inteira.
- R5 · "Pronto para merge?" deve ganhar o item **Resolução do conflito**:
  - Bloqueio enquanto a resolução estiver em andamento, reprovada ou desatualizada (R7);
  - aprovado quando o gate passou na ponta atual da branch;
  - "Mergear mesmo assim…" continua disponível, com motivo registrado, como hoje.
- R6 · O projeto deve poder ligar a resolução automática em `.promptorium/config.yml`, com `review: resolver-conflitos: automatico`. O padrão é `manual`. Ligada:
  - quando o rebase de uma filha conflitar (SPEC-032 R7) ou a previsão de conflito com a base (`predictConflict`) acusar conflito, o sistema começa a resolução sozinho, uma spec por vez, se não houver sessão viva na spec;
  - se o gate reprovar a primeira resolução, o sistema roda "Corrigir e verificar" sozinho uma única vez. Depois disso, as correções são só manuais;
  - aprovada ou reprovada, uma notificação avisa o resultado;
  - o sistema nunca faz o merge sozinho.
- R7 · Se a base andar enquanto o agente resolve ou o gate roda, o resultado deve ficar como **desatualizado** ("A base mudou · resolver de novo"), e o gate não pode aprová-lo.
- R8 · As mensagens enviadas ao agente (`conflictMessage`, `restackMessage` e "Passar para o agente") devem pedir que a resposta termine com `## Como resolvi`, com uma linha por arquivo: `caminho: o que foi mantido de cada lado`.
- R9 · O histórico de review da spec deve registrar cada resolução: quem começou (a pessoa ou o automático), os arquivos em conflito, o resultado de cada gate e o SHA aprovado.

## Fora do escopo

- Merge sem a pessoa. No gitai, uma resolução verificada entra sozinha. Aqui, o gate só libera o botão.
- Resolver com regras determinísticas ou com outro provedor, como o `resolve.toml` do gitai.
- Editor de três vias dentro do app (continua fora, como na SPEC-032).
- Testar a base depois do merge e reverter a spec que quebrou. Fica para outra spec.
- GitLab: o rebase local vale, mas o push e o MR continuam na SPEC-013.

## Design

### O que já existe

- `lib/features/review/review_service.dart`: `resolveConflict` envia `conflictMessage` ou `restackMessage` à sessão e move a tarefa para Em execução. "Passar para o agente" fica no mesmo serviço (R17). `predictConflict` prevê o conflito com a base.
- `lib/features/review/pr_babysitter.dart`: `conflictMessage`. O babysitter envia ao PR os commits que o agente faz.
- `lib/features/review/restack.dart`: `RestackResult`, `oldBaseRef` e as marcas `review.restack.<sessão>` (`conflito\n<arquivos>`).
- `lib/features/review/review_stack.dart`: os estados de merge do card, como `rebaseManual`.
- `lib/features/board/step_gate.dart`: `StepGate.run` roda árvore limpa, `testes:`, `lint:`, `build:` e os `verificar:`, com a contagem de testes. `GateReport` e as views `GateChips` e `gate_report_view.dart` já mostram o relatório.
- "Pronto para merge?" reúne os itens que bloqueiam o merge, com "Mergear mesmo assim…".

### Componentes

- `lib/features/review/conflict_resolution.dart` (novo):
  - `ConflictResolution`, um valor imutável com estado (`resolvendo`, `conferindo`, `aprovada`, `reprovada`, `desatualizada`), arquivos, SHA de antes, SHA conferido e `GateReport`;
  - `conflictResolutionProvider`, uma família por sessão, guardada nas configurações do app como as marcas do restack;
  - `parseHowResolved(texto)`, que lê `## Como resolvi` (R4, R8).
- `StepGate` ganha `runResolution(...)`, que soma aos itens atuais a checagem de marcadores e de ancestralidade (R1), sem exigir commit novo de etapa.
- `ReviewService`:
  - grava `antes-da-resolucao` antes de enviar a mensagem;
  - escuta o fim da sessão e chama o gate;
  - implementa "Desfazer a resolução" (R3) e o item de "Pronto para merge?" (R5).
- `GitService.remergeDiff(sha)`: `git show --remerge-diff --format= <sha>`, que existe desde o git 2.36. Sem ele, a tela mostra `git show --cc` e avisa.
- `ProjectConfig`: `review.resolverConflitos` (`manual` | `automatico`) (R6).
- Resolução automática: a fila que já roda `predictConflict` em segundo plano (SPEC-032 R4) dispara a resolução, com no máximo uma por vez.

## Critérios de aceite

- [ ] O gate roda sozinho quando o agente termina a resolução, nas três origens [R1] verificar: flutter test test/features/review/conflict_resolution_test.dart
- [ ] Marcador de conflito esquecido ou base fora da branch reprovam a resolução [R1] verificar: flutter test test/features/review/conflict_resolution_test.dart
- [ ] A contagem de testes compara com o último gate aprovado da spec [R1] verificar: flutter test test/features/review/conflict_resolution_test.dart
- [ ] O card mostra os quatro estados com ícone e texto [R2] verificar: flutter test test/features/review/review_stack_test.dart
- [ ] "Corrigir e verificar" envia o relatório e roda o gate de novo [R3] verificar: flutter test test/features/review/conflict_resolution_test.dart
- [ ] "Desfazer a resolução" volta ao SHA de antes e recusa com alterações não commitadas [R3] verificar: flutter test test/features/review/conflict_resolution_test.dart
- [ ] "O que a resolução decidiu" mostra o remerge-diff por arquivo com a explicação do agente, e a resposta inteira sem `## Como resolvi` [R4, R8] verificar: flutter test test/features/review/conflict_resolution_test.dart
- [ ] "Pronto para merge?" bloqueia a resolução pendente, reprovada ou desatualizada [R5, R7] verificar: flutter test test/features/review/merge_readiness_test.dart
- [ ] Com `resolver-conflitos: automatico`, um conflito previsto inicia uma resolução por vez, corrige sozinho só na primeira reprovação e nunca faz merge [R6] verificar: flutter test test/features/review/conflict_resolution_test.dart
- [ ] O histórico registra origem, arquivos, gates e SHA aprovado [R9] verificar: flutter test test/features/review/conflict_resolution_test.dart
- [ ] Um conflito real entre duas specs é resolvido, conferido e mergeado no app [R1–R5] verificar: manual (projeto de teste com duas specs que mexem no mesmo arquivo)
- [ ] O projeto compila e a análise estática passa [R1–R9] verificar: flutter analyze

## Decisões

- P1 · Na resolução automática, "Corrigir e verificar" roda sozinho só na primeira reprovação. Depois, só manual (R6).
- P2 · A resolução sempre passa pelo gate inteiro, porque é ele que libera o merge (R1).
- P3 · Com mockups: o estado no card, o relatório reprovado, "O que a resolução decidiu" e "Pronto para merge?" com a resolução desatualizada.
