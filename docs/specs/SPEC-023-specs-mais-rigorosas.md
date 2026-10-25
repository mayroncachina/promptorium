---
id: SPEC-023
status: aprovada
---

# Specs mais rigorosas

## Objetivo

O formato das specs e o gate já cobrem quase tudo o que o fluxo spec-driven precisa: requisitos com ID, design ligado às etapas, critérios com `verificar:` e gate de commit, árvore limpa, testes, lint e build. Faltam quatro proteções, inspiradas no `tlc-spec-driven` (tech-leads-club/agent-skills):

1. **Contagem de testes no gate.** Hoje o gate só confere se o comando `testes:` passou. Um agente que apaga ou pula um teste para passar não é pego.
2. **Fechar as perguntas antes de aprovar.** Uma spec com "Perguntas em aberto" pode ser aprovada e executada sem que ninguém responda. A SPEC-021 e a SPEC-022 foram aprovadas assim.
3. **Avisos de estrutura no editor.** Requisito sem critério, critério sem `[Rn]` ou sem `verificar:` e IDs repetidos só aparecem quando a execução já começou.
4. **"Fora do escopo" e "Perguntas em aberto" no modelo de spec nova.** O prompt de transformar uma resposta em spec já pede as duas seções (`prompt_actions.dart`), mas o modelo de "Nova spec" não as traz, e as sessões de etapa não recebem o que ficou fora do escopo.

Fora do escopo:
- Verificador com injeção de falhas (mutantes): fica para uma spec própria, por causa do custo em tokens.
- Registro de decisões de arquitetura (ADR).
- Reescrever specs já existentes para o modelo novo.
- Bloquear a aprovação por causa dos avisos do R8: eles só informam.

## Requisitos

- R1 · Quando o gate rodar o comando `testes:` com sucesso e a saída tiver um resumo reconhecido (`flutter test`/`dart test`, `pytest`, `jest`/`vitest`, `cargo test`), o sistema deve extrair o número de testes que passaram e o de pulados e gravá-los no relatório do gate da etapa.
- R2 · Quando o número de testes que passaram for menor, ou o de pulados for maior, do que no último gate aprovado da mesma spec, o sistema deve reprovar a etapa com o item "contagem de testes", mostrando os números de antes e de depois.
- R3 · Quando a única falha do gate for a contagem de testes, o sistema deve oferecer no painel da etapa a ação "Aceitar a redução", que aprova a etapa e registra na timeline da sessão os números e que a redução foi aceita pelo usuário.
- R4 · Quando a spec não tiver gate aprovado anterior com contagem, ou a saída não tiver resumo reconhecido, o sistema não deve reprovar pela contagem e deve registrar no relatório "contagem não conferida" com o motivo.
- R5 · Onde o `config.yml` tiver `verificacao: contar-testes: nao`, o sistema não deve conferir a contagem de testes.
- R6 · Quando o usuário acionar "Aprovar spec" e a seção "Perguntas em aberto" tiver itens, o sistema deve abrir, antes do diálogo de Design, um diálogo que lista as perguntas e oferece "Refinar com IA", "Aprovar assumindo premissas" e "Cancelar".
- R7 · Quando o usuário escolher "Aprovar assumindo premissas", o sistema deve mover cada pergunta para a seção `## Premissas` como "- (sem resposta, aceita em <data>) <pergunta>", deixar "Perguntas em aberto" vazia e seguir a aprovação normal.
- R8 · Enquanto uma spec estiver aberta no editor, o sistema deve mostrar uma lista de avisos de estrutura, atualizada ao editar, com:
  - requisito sem nenhum critério de aceite que o cite;
  - critério sem `[Rn]`, ou que cita um requisito que não existe;
  - critério sem `verificar:`;
  - ID de requisito repetido ou fora de sequência;
  - requisito sem "deve" (fora do estilo EARS).
- R9 · Quando o usuário acionar um aviso, o sistema deve levar o editor à linha correspondente. Os avisos não devem impedir salvar nem aprovar.
- R10 · Quando o usuário acionar "Aprovar spec" com avisos de estrutura, o sistema deve mostrar quantos são no diálogo de aprovação, com "Ver avisos" e "Aprovar mesmo assim".
- R11 · Quando o usuário criar uma spec nova, o modelo deve trazer as seções Objetivo, Requisitos, Fora do escopo, Design, Critérios de aceite e Perguntas em aberto, nesta ordem.
- R12 · Quando "Refinar com IA" abrir a conversa, o prompt deve pedir também a seção "Fora do escopo" e que dúvidas sem resposta fiquem em "Perguntas em aberto", em vez de virarem requisitos.
- R13 · Quando a spec tiver "Fora do escopo" ou "Premissas", o sistema deve incluir essas seções no trecho da spec enviado a cada sessão de etapa.
- R14 · Os avisos e os diálogos novos devem ser operáveis por teclado, com foco visível e rótulos acessíveis.

## Design

### O que já existe

- **Gate:** `lib/features/board/step_gate.dart`. `StepGate.run` gera um `GateReport` com uma lista de `GateCheck` (`commit`, `arvore`, `testes`, `lint`, `build`, `verificar`), gravado em JSON em `spec_steps.gate_report`. `GateReport.onlyDirtyTree` já sustenta uma ação de saída parecida com a do R3: "Commitar o que sobrou" (`SpecRunner.commitLeftovers`, botão em `spec_steps_panel.dart`).
- **Configuração:** `VerificationConfig` em `lib/features/project/project_config.dart` lê `verificacao:` (`tentativas`, `timeout`, `exigir-commit`, `exigir-arvore-limpa`).
- **Aprovação:** `_approve` em `lib/features/specs/specs_screen.dart:347` abre o diálogo "A spec não tem Design" e chama `SpecService.approve`.
- **Parser:** `SpecDocument` em `lib/features/specs/spec_file.dart` (`section`, `requirements`, `stepPlans`), com `parseCriteria` e `newSpecMarkdown`.
- **Prompts:** `refineSpecPrompt` em `specs_screen.dart`. O trecho por etapa é montado por `focusedSpecText` em `spec_runner.dart`.

### R1–R5 · Contagem de testes

- Novo `lib/features/board/test_count.dart` com `TestCount? parseTestCount(String output)`, que guarda `passed` e `skipped`. Ele reconhece estes resumos e devolve null nos outros:
  - flutter e dart: a última linha `+N ~S: All tests passed!`;
  - pytest: `N passed, S skipped`;
  - jest e vitest: `Tests: … N passed`;
  - cargo: `test result: ok. N passed; … S ignored`.
- O `GateCheck` ganha `count` (JSON `contagem: {passaram, pulados}`), preenchido no item `testes`. Como `tailLines` corta a saída, o parse roda na saída completa, antes do corte.
- `StepGate.run` recebe `TestCount? baseline`. Com baseline e contagem, ele acrescenta o item `contagem`, com ok ou falha e a saída "antes: 751 passaram, 0 pulados · depois: 748 passaram, 3 pulados". Sem um dos dois, o item fica ok, com a saída "contagem não conferida: …" (R4).
- A baseline é a contagem do gate aprovado mais recente entre as etapas da spec (`SpecStepsRepo`). Ela é lida em `SpecRunner` antes de chamar o gate.
- `GateReport.onlyTestCount` segue o mesmo modelo de `onlyDirtyTree`. `SpecRunner.acceptTestDrop(specId)` marca as etapas como aprovadas e escreve uma nota na timeline (R3). O botão fica no painel de etapas, ao lado de "Commitar o que sobrou".
- `VerificationConfig.countTests` lê `contar-testes`, com padrão `sim` (R5).

### R6–R7 · Perguntas antes de aprovar

- `SpecDocument.openQuestions` lê os itens (lista com `-` ou numerada) de `## Perguntas em aberto`, aceitando variações de acento e de maiúsculas.
- `SpecDocument.withAssumptions(List<String>, DateTime)` move os itens para `## Premissas`, criando a seção antes de `## Critérios de aceite` quando não existir.
- Em `_approve`, o diálogo novo vem antes do de Design. "Refinar com IA" chama o `_refine` que já existe.

### R8–R10 · Avisos de estrutura

- Novo `lib/features/specs/spec_lint.dart` com `List<SpecWarning> lintSpec(String text)`. Cada `SpecWarning` tem `line`, `message` e `kind`. A função é pura e usa `SpecDocument.requirements` e `parseCriteria`, que precisam passar a expor o número da linha.
- Uma faixa recolhível abaixo do editor mostra "N avisos" e, aberta, a lista. A faixa é recalculada com um debounce de cerca de 300 ms a cada edição. Acionar um aviso move a seleção do `CodeLineEditingController` para a linha (R9).
- O diálogo do R6 também aparece quando só há avisos. Ele mostra a contagem e oferece "Ver avisos" (que abre a faixa) e "Aprovar mesmo assim" (R10).

### R11–R13 · Modelo e prompts

- `newSpecMarkdown` ganha `## Fora do escopo` e `## Perguntas em aberto`, cada uma com um comentário-guia curto.
- `refineSpecPrompt` passa a citar as duas seções (R12).
- `focusedSpecText` acrescenta `## Fora do escopo` e `## Premissas`, quando existirem, logo depois do Objetivo (R13).

## Etapas

- R1 → lib/features/board/test_count.dart, lib/features/board/step_gate.dart · verificar: `flutter test test/features/board/test_count_test.dart test/features/board/step_gate_test.dart`
- R2 → lib/features/board/step_gate.dart, lib/features/board/spec_runner.dart, lib/data/repos/spec_steps_repo.dart · verificar: `flutter test test/features/board/step_gate_test.dart test/features/board/spec_runner_test.dart`
- R3 → lib/features/board/spec_runner.dart, lib/features/board/widgets/spec_steps_panel.dart · verificar: `flutter test test/features/board`
- R4 → lib/features/board/step_gate.dart · verificar: `flutter test test/features/board/step_gate_test.dart`
- R5 → lib/features/project/project_config.dart · verificar: `flutter test test/features/project`
- R6 → lib/features/specs/spec_file.dart, lib/features/specs/specs_screen.dart · verificar: `flutter test test/features/specs`
- R7 → lib/features/specs/spec_file.dart, lib/features/specs/specs_screen.dart · verificar: `flutter test test/features/specs/spec_file_test.dart test/features/specs/specs_screen_test.dart`
- R8 → lib/features/specs/spec_lint.dart, lib/features/specs/spec_file.dart, lib/features/specs/specs_screen.dart · verificar: `flutter test test/features/specs`
- R9 → lib/features/specs/specs_screen.dart · verificar: `flutter test test/features/specs/specs_screen_test.dart`
- R10 → lib/features/specs/specs_screen.dart · verificar: `flutter test test/features/specs/specs_screen_test.dart`
- R11 → lib/features/specs/spec_file.dart · verificar: `flutter test test/features/specs/spec_file_test.dart`
- R12 → lib/features/specs/specs_screen.dart · verificar: `flutter test test/features/specs/specs_screen_test.dart`
- R13 → lib/features/board/spec_runner.dart · verificar: `flutter test test/features/board/spec_runner_test.dart`
- R14 → lib/features/specs/specs_screen.dart, lib/features/board/widgets/spec_steps_panel.dart · verificar: `flutter test test/features/specs test/features/board && flutter analyze`

## Critérios de aceite

- [x] `parseTestCount` extrai passaram e pulados de saídas reais de flutter, pytest, jest, vitest e cargo, e devolve null para uma saída sem resumo [R1] verificar: flutter test test/features/board/test_count_test.dart
- [x] O relatório do gate guarda a contagem no item `testes` e sobrevive a `encode`/`decode` [R1] verificar: flutter test test/features/board/step_gate_test.dart
- [x] Com baseline de 10 passaram e saída com 9, o gate reprova com o item "contagem de testes" e mostra antes e depois [R2] verificar: flutter test test/features/board/step_gate_test.dart
- [x] Com baseline sem pulados e saída com 1 pulado, o gate reprova [R2] verificar: flutter test test/features/board/step_gate_test.dart
- [x] A baseline vem do gate aprovado mais recente da mesma spec, e não de outra spec [R2] verificar: flutter test test/features/board/spec_runner_test.dart
- [x] Com só a contagem reprovada, o painel mostra "Aceitar a redução"; acioná-la aprova a etapa e escreve a nota na timeline [R3] verificar: flutter test test/features/board
- [x] Com outra falha junto (por exemplo, lint), "Aceitar a redução" não aparece [R3] verificar: flutter test test/features/board
- [x] Na primeira etapa da spec, ou com saída sem resumo, o gate passa e registra "contagem não conferida" [R4] verificar: flutter test test/features/board/step_gate_test.dart
- [x] `verificacao: contar-testes: nao` desliga a conferência, e o `toYaml` preserva a chave [R5] verificar: flutter test test/features/project
- [x] Com perguntas em aberto, "Aprovar spec" abre o diálogo com as perguntas antes do diálogo de Design; "Cancelar" não muda o arquivo [R6] verificar: flutter test test/features/specs/specs_screen_test.dart
- [x] "Refinar com IA" no diálogo abre a conversa de refino da spec [R6] verificar: flutter test test/features/specs/specs_screen_test.dart
- [x] "Aprovar assumindo premissas" move as perguntas para `## Premissas` com a data, esvazia "Perguntas em aberto" e aprova [R7] verificar: flutter test test/features/specs/spec_file_test.dart test/features/specs/specs_screen_test.dart
- [x] `lintSpec` aponta, com a linha certa, cada um dos cinco tipos de aviso, e não aponta nada na SPEC-021 [R8] verificar: flutter test test/features/specs
- [x] Editar a spec atualiza a lista de avisos sem salvar [R8] verificar: flutter test test/features/specs/specs_screen_test.dart
- [x] Acionar um aviso posiciona o cursor na linha dele; salvar e aprovar continuam disponíveis com avisos [R9] verificar: flutter test test/features/specs/specs_screen_test.dart
- [x] Com avisos, o diálogo de aprovação mostra a contagem, "Ver avisos" abre a lista e "Aprovar mesmo assim" aprova [R10] verificar: flutter test test/features/specs/specs_screen_test.dart
- [x] Uma spec nova traz as seis seções na ordem do R11 [R11] verificar: flutter test test/features/specs/spec_file_test.dart
- [x] O prompt de refino cita "Fora do escopo" e "Perguntas em aberto" [R12] verificar: flutter test test/features/specs/specs_screen_test.dart
- [x] O trecho enviado à etapa inclui "Fora do escopo" e "Premissas" quando existem, e não muda quando não existem [R13] verificar: flutter test test/features/board/spec_runner_test.dart
- [x] A faixa de avisos, os avisos, os botões dos diálogos e "Aceitar a redução" recebem foco por Tab, acionam com Enter e têm rótulo de acessibilidade [R14] verificar: flutter test test/features/specs test/features/board
- [x] A análise estática passa sem avisos novos [R1] [R2] [R3] [R4] [R5] [R6] [R7] [R8] [R9] [R10] [R11] [R12] [R13] [R14] verificar: flutter analyze

## Decisões

- Os avisos de estrutura só informam: não bloqueiam salvar nem aprovar.
- A contagem só compara gates da mesma spec. A primeira etapa apenas registra a contagem, para não rodar a suíte inteira (mais de 2 minutos neste repositório) antes de começar.
- Só o comando `testes:` é contado, porque os `verificar:` das etapas rodam subconjuntos da suíte.
- A conferência de EARS é tolerante: só exige "deve" no texto do requisito, porque os requisitos gerais ("A ação deve ser operável…") também são válidos em EARS.
- (Pergunta 1) Ao aprovar assumindo premissas, as perguntas vão para `## Premissas`, como no R7, e "Perguntas em aberto" fica vazia.
- (Pergunta 2) A conferência de EARS entra já, no modo tolerante: só exige "deve" (ou "devem") no texto do requisito.
- O item `contagem` não interrompe os comandos seguintes do gate (lint, build, `verificar:`): assim "Aceitar a redução" só aparece quando todo o resto passou.
- A redução aceita grava o relatório como aprovado, com "redução aceita" na saída do item; a contagem dele vira a baseline seguinte.
- A faixa de avisos fica abaixo do editor, mas vem antes dele na ordem do Tab, porque o editor usa Tab para indentar. Em specs já iniciadas (somente leitura) a faixa não aparece.
- Um critério cujo `verificar:` tem crases (que o parser não separa) não gera o aviso "sem verificar:".
