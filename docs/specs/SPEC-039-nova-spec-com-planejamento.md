---
id: SPEC-039
status: rascunho
depende-de: SPEC-037
---

# Nova spec com mini planejamento

## Objetivo

"Nova spec" pede só um título e abre um modelo vazio. Quem tem uma ideia precisa preencher as seções à mão ou abrir Refinar com IA depois, e o planejamento fica espalhado entre a spec, o Prompt e a tela Projeto.

Esta spec traz para a criação da spec a conversa que já existe na etapa Visão do projeto. A pessoa conta a ideia, o planner lê o repositório, faz poucas perguntas e preenche um rascunho ao lado. No fim, a spec nasce com objetivo, requisitos, fora do escopo, dependências e perguntas em aberto, e pode seguir direto para Planejar.

Task: [#88 · Melhorar criação de novas Specs](https://github.com/mayroncachina/promptorium/issues/88).

Mockup: [canvas do Claude Design](https://claude.ai/artifact/ReTbbrQhZicdwdktur58wu).

## Requisitos

- R1 · "Nova spec" deve abrir a tela de ideia, nos caminhos de hoje (botão da tela Specs, atalho e paleta de comandos):
  - a tela ocupa a área principal, com o caminho "Specs / Nova spec";
  - o título é "Conte a ideia", com um campo de texto e as ações **Planejar a spec** e **Criar em branco**;
  - **Planejar a spec** fica indisponível com o campo vazio.
- R2 · **Criar em branco** deve manter o fluxo de hoje:
  - pede o título e cria o arquivo com `newSpecMarkdown`, sem chamar o planner;
  - funciona sem o Claude Code instalado ou conectado.
- R3 · O mini planejamento deve mostrar a conversa à esquerda e o rascunho à direita, como a etapa Visão:
  - o título é "Mini planejamento", com a marca "planner · somente leitura";
  - a conversa tem campo de resposta e até 3 sugestões clicáveis para a pergunta principal;
  - cada resposta do planner mostra o que mudou, como "Rascunho atualizado · Objetivo · Requisitos +2";
  - a conversa rola até o fim a cada mensagem, resposta ou falha, e ao voltar para ela.
- R4 · O planner deve ler o repositório e conversar com as regras da etapa Visão:
  - roda somente leitura e nunca grava arquivos;
  - faz no máximo duas perguntas por vez, começando pelas que mais mudam a spec;
  - não inventa requisitos: uma dúvida sem resposta vira item de "Perguntas em aberto";
  - uma dúvida que não impede começar não segura a criação, e o planner diz quando a spec já pode ser criada;
  - cada resposta mantém o limite de custo da conversa da etapa Visão.
- R5 · O rascunho deve ser atualizado a cada resposta:
  - mostra o próximo código, a marca "rascunho", título, objetivo, requisitos, fora do escopo, dependências e perguntas em aberto;
  - seção sem conteúdo diz "Ainda vazio";
  - requisitos usam o formato `- R1 ·`, no estilo EARS, com a contagem "4 · máximo 6";
  - um item novo mostra a marca "novo" até a resposta seguinte;
  - o título pode ser editado à mão, e o planner não o sobrescreve depois disso;
  - o planner só sugere em `depende-de` specs que existem no workspace.
- R6 · Criar deve gravar a spec com o que o rascunho tem:
  - **Criar spec** fica disponível depois da primeira resposta do planner e indisponível enquanto ele responde;
  - a spec nasce com status rascunho, com o código disponível no momento de criar;
  - seções sem conteúdo ficam como no modelo de spec nova;
  - a spec é selecionada e abre no editor, e o rascunho é apagado;
  - uma falha ao gravar mostra "Não foi possível criar a spec", mantém a conversa e o rascunho, e **Criar spec** tenta de novo;
  - **Criar spec** fica indisponível com o título vazio.
- R7 · O rascunho deve ter a opção "Escrever o Plano em seguida", ligada por padrão, e a escolha fica salva:
  - com a opção ligada, o botão diz **Criar e planejar**;
  - depois de criar, a ação Planejar começa sozinha, com o andamento e o bloqueio que ela já tem;
  - uma falha ou **Cancelar** em Planejar não desfaz a spec criada, e o botão Planejar continua disponível;
  - enquanto a spec criada não tiver Plano, **Planejar** é a ação em destaque, e **Aprovar spec** fica neutro;
  - o Plano pronto fica no editor para revisar, com "Plano pronto. Revise e salve." e **Salvar**, como na ação Planejar de hoje;
  - com a opção desligada, a spec abre sem `## Plano` preenchido.
- R8 · O rascunho deve sobreviver à saída da tela:
  - **Sair e guardar**, voltar para Specs, trocar de seção ou fechar o app mantém a conversa e o rascunho, um por workspace;
  - o rascunho fica no banco do app, como o plano do projeto, e não no repositório;
  - **Sair e guardar** e "Specs" no caminho levam à tela Specs, que mostra "Rascunho guardado";
  - ao abrir "Nova spec" com rascunho guardado, a tela de ideia mostra "Você tem um rascunho", com título, requisitos e data, e as ações **Continuar** e **Descartar**;
  - **Continuar** volta à conversa e retoma a sessão do planner;
  - com rascunho guardado, **Planejar a spec** fica indisponível até a pessoa continuar ou descartar, e **Criar em branco** segue disponível;
  - **Descartar** pede confirmação quando o rascunho tem requisitos, com o foco em **Manter rascunho**, e `Esc` mantém o rascunho.
- R9 · Uma falha do planner não deve perder nada:
  - a conversa mostra "O planner não respondeu", com **Tentar de novo**, que reenvia a mensagem que falhou sem repeti-la na conversa;
  - a mensagem da pessoa, a conversa e o rascunho continuam na tela;
  - **Criar spec** continua disponível se o rascunho tiver conteúdo;
  - sem o Claude Code conectado, a tela de ideia mostra "Claude Code CLI não encontrado", com **Verificar de novo**, e deixa só **Criar em branco** disponível.
- R10 · A ideia que precisa de mais de 6 requisitos deve ser avisada:
  - o planner mantém no máximo 6 requisitos no rascunho;
  - o que sobrar vira item de "Fora do escopo", com a sugestão de uma próxima spec;
  - a spec não é dividida automaticamente.
- R11 · As ações Refinar com IA e Planejar devem continuar iguais e em destaque na spec já criada, inclusive na que veio do mini planejamento.
- R12 · A tela deve caber na janela mínima e funcionar por teclado:
  - em 1100×700, nenhum texto é truncado nem estoura o layout;
  - o campo de resposta e as ações do rascunho ficam fixos no rodapé, e só a conversa e o conteúdo do rascunho rolam;
  - o foco é visível em todos os controles;
  - os campos de texto têm borda com contraste de pelo menos 3:1 contra o fundo, com um token novo (`#626C7C`), sem mudar `SessionColors.selectedBorder`, que serve a outras telas.

## Fora do escopo

- Criar várias specs numa mesma conversa.
- Trocar o provider do planner. Ele usa o Claude, como na etapa Visão.
- Mudar Refinar com IA, Planejar ou o planejamento do projeto.
- Gerar telas do protótipo durante a conversa.
- Editar requisitos à mão dentro do rascunho. Isso acontece no editor, depois de criar.
- Mais de um rascunho por workspace.

## Plano

<!-- Como implementar: componentes, arquivos e decisões. Use "Planejar". -->

## Critérios de aceite

- [ ] "Nova spec" abre a tela de ideia pelo botão, pelo atalho e pela paleta [R1] verificar: flutter test test/features/specs/new_spec_flow_test.dart
- [ ] Criar em branco grava o modelo de hoje sem chamar o planner [R2] verificar: flutter test test/features/specs/new_spec_flow_test.dart
- [ ] A conversa mostra sugestões, e cada resposta mostra o que mudou no rascunho [R3] [R5] verificar: flutter test test/features/specs/new_spec_flow_test.dart
- [ ] A última mensagem fica à vista em 1100×700, depois de cada resposta e ao voltar à conversa [R3] [R12] verificar: flutter test test/features/specs/new_spec_flow_test.dart
- [ ] O planner roda somente leitura, e dúvida sem resposta vira pergunta em aberto [R4] verificar: flutter test test/features/specs/spec_planner_test.dart
- [ ] O título editado à mão não é sobrescrito, e dependências inexistentes são ignoradas [R5] verificar: flutter test test/features/specs/spec_planner_test.dart
- [ ] Criar grava o rascunho na spec, com status rascunho, e apaga o rascunho guardado [R6] verificar: flutter test test/features/specs/new_spec_flow_test.dart
- [ ] Uma falha ao gravar mantém o rascunho e permite criar de novo [R6] verificar: flutter test test/features/specs/new_spec_flow_test.dart
- [ ] Criar e planejar inicia Planejar, e falha ou Cancelar não desfazem a spec [R7] verificar: flutter test test/features/specs/new_spec_flow_test.dart
- [ ] Sem Plano, Planejar fica em destaque e Aprovar spec fica neutro [R7] verificar: flutter test test/features/specs/new_spec_flow_test.dart
- [ ] Sair, voltar e reabrir o app mantêm a conversa e o rascunho [R8] verificar: flutter test test/features/specs/new_spec_flow_test.dart
- [ ] Com rascunho guardado, Planejar a spec fica indisponível, e Descartar pede confirmação [R8] verificar: flutter test test/features/specs/new_spec_flow_test.dart
- [ ] Uma falha do planner mantém a conversa, Tentar de novo não repete a mensagem, e Criar segue disponível [R9] verificar: flutter test test/features/specs/new_spec_flow_test.dart
- [ ] Sem o Claude Code, só Criar em branco fica disponível [R9] verificar: flutter test test/features/specs/new_spec_flow_test.dart
- [ ] O rascunho nunca passa de 6 requisitos, e o excesso vai para Fora do escopo [R10] verificar: flutter test test/features/specs/spec_planner_test.dart
- [ ] Refinar com IA e Planejar seguem funcionando na spec criada [R11] verificar: flutter test test/features/specs
- [ ] A tela cabe em 1100×700 sem truncar textos, com o campo de resposta e Criar à vista [R12] verificar: flutter test test/features/specs/new_spec_flow_test.dart

## Perguntas em aberto

Nenhuma.
