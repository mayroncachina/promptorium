---
id: SPEC-016
status: concluida
depende-de: []
---

# Prompt: salvar a spec escrita pelo agente

## Objetivo

Quando o agente entrega uma spec numa resposta do Prompt, o usuário deve poder salvá-la com um clique. Hoje o agente, sem ferramenta de escrita no modo da conversa, pede que o usuário copie o texto para a pasta de specs; e "Transformar em spec", no topo, compila a conversa inteira num modelo em vez de usar a spec pronta. Mockup aprovado: https://claude.ai/artifact/TWQB4uuSqgL6LdWW46DVUU

- Fora do escopo: dar ferramenta de escrita ao agente nos modos Perguntar/Planejar e mudar o fluxo do "Plano pronto".

## Requisitos

- R1 · Quando uma resposta concluída do agente contiver uma spec — um bloco de código cujo conteúdo tenha frontmatter com `id: SPEC-NNN` ou as seções `## Objetivo` e `## Requisitos`, ou o próprio texto da resposta nesse formato — o sistema deve mostrar abaixo da resposta a barra "Spec detectada" com a quantidade de requisitos e de critérios de aceite. Respostas ainda em streaming e de subagentes não são analisadas; com várias specs na mesma resposta vale a última.
- R2 · "Salvar como SPEC-NNN" deve gravar só o texto da spec, sem o texto do agente em volta, no próximo código livre da pasta configurada, com `id` igual ao código e `status: rascunho`, preservando as demais chaves do frontmatter. Depois de salvar, a barra deve indicar a spec criada e oferecer "Abrir em Specs".
- R3 · Quando o `id` do frontmatter for de uma spec existente no projeto, o botão principal deve ser "Aplicar na SPEC-NNN": substituir o arquivo pela nova versão mantendo o `id` e o status atuais, com "Salvar como nova" como alternativa. Aplicar deve ser recusado quando a spec já saiu do Backlog (está em execução, revisão ou concluída), orientando "Salvar como nova".
- R4 · "Prévia" deve mostrar título editável, caminho de destino, o que foi conferido (frontmatter, requisitos, critérios) e o que será ajustado ao salvar, a spec renderizada ou em Markdown editável e, ao aplicar numa spec existente, o diff com o arquivo. Se o arquivo mudou depois do início da conversa, a prévia e a barra devem avisar antes de aplicar.
- R5 · "Transformar em spec", no topo, deve usar a última spec detectada na conversa (salvar como nova ou aplicar, como em R2/R3); sem spec detectada, mantém o comportamento atual de compilar a conversa.
- R6 · Gravações devem usar o serviço de specs (criação exclusiva para specs novas; temporário + rename e conferência do texto esperado para aplicar), registrar a spec no banco sem duplicar e nunca sobrescrever um arquivo que mudou entre a prévia e a gravação.

## Design

- `lib/features/prompt/spec_from_answer.dart`: detecção pura (`detectAnswerSpec`, `lastAnswerSpec`), texto final para spec nova/existente e diff de linhas.
- `TimelineListView` ganha `answerFooter`, um widget opcional por resposta de nível superior; o Prompt o usa para a barra.
- Barra e prévia em `lib/features/prompt/widgets/answer_spec_bar.dart`; gravação por `SpecService.create`/`save`.

## Critérios de aceite

- [x] [R1] Bloco com frontmatter, bloco só com seções, resposta sem bloco, resposta comum sem spec e várias specs na mesma resposta são detectados corretamente. verificar: `flutter test test/features/prompt/spec_from_answer_test.dart`
- [x] [R2] Salvar grava apenas a spec, com o próximo código, `status: rascunho` e as outras chaves preservadas, e registra a spec. verificar: `flutter test test/features/prompt/spec_from_answer_test.dart`
- [x] [R3] Aplicar mantém id e status atuais; spec fora do Backlog é recusada. verificar: `flutter test test/features/prompt/spec_from_answer_test.dart`
- [x] [R1, R2, R4] Na tela do Prompt, a barra aparece na resposta com spec, a prévia salva com o título editado e a barra passa a mostrar a spec salva. verificar: `flutter test test/features/prompt/answer_spec_bar_test.dart`
- [x] [R5] "Transformar em spec" usa a spec detectada e, sem ela, compila a conversa. verificar: `flutter test test/features/prompt/answer_spec_bar_test.dart`
- [x] [R6] Arquivo alterado entre a prévia e a gravação não é sobrescrito. verificar: `flutter test test/features/prompt/spec_from_answer_test.dart`

## Perguntas em aberto

- O código da spec nova é sempre o próximo livre; a sugestão do agente é substituída. Vale permitir escolher outro código livre?
