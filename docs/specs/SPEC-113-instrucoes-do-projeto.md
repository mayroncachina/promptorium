---
id: SPEC-113
status: rascunho
tipo: recurso
issue: 429
depende-de: []
---

# Instruções do projeto: AGENTS.md como fonte, com editor e entrevista

## Objetivo

Escrever as instruções dos agentes **num lugar só**. O `AGENTS.md` passa a ser a fonte, e o `CLAUDE.md` fica com a linha `@AGENTS.md` e, se precisar, com o que é só do Claude Code. A pessoa edita os dois no Projeto e pode pedir que a IA melhore o texto por uma entrevista no estilo `grill-me`.

Hoje a fonte é o `CLAUDE.md` (decisão 6 do épico #332, SPEC-104), e a aba Ferramentas › Instruções só mostra os arquivos. Três problemas:

1. Fora do Promptorium, o Codex não lê o `CLAUDE.md`: quem o entrega é um override do app.
2. Um repositório com os dois arquivos tem duas fontes. O Codex lê só o `AGENTS.md`, e o `CLAUDE.md` não chega a ele.
3. O par `AGENTS.md` + `@AGENTS.md`, que resolve isso, aparece hoje como "Duas fontes" (`AgentsMdState.personal`).

### O que já foi conferido

- O Claude Code expande `@AGENTS.md`; o Codex não tem import (SPEC-104, P2).
- No Codex 0.170, um `AGENTS.md` de 54 004 bytes entrou cortado em 32 768 bytes, no meio de uma linha e sem aviso ao modelo. O `CLAUDE.md` da mesma pasta não entrou. Conferido em 25/11/2026 com `codex debug prompt-input`, sem turno e com `CODEX_HOME` isolado.

## Requisitos

### Fonte única

- R1 · **Par reconhecido.** Um `CLAUDE.md` com uma linha `@AGENTS.md` (ou `@./AGENTS.md`), fora de bloco de código, e um `AGENTS.md` sem o marcador de gerado é o estado **fonte única**. Ele não mostra "Duas fontes".
- R2 · **Projeto novo.** A criação grava o texto no `AGENTS.md` e um `CLAUDE.md` com `@AGENTS.md`. Vale para o modelo de partida e para o plano (`materialize`), e os dois entram no commit inicial. Um arquivo da pessoa nunca é sobrescrito.
- R3 · **Projeto antigo.** Nada muda sozinho. Sem `AGENTS.md`, o override da SPEC-104 continua valendo. A aba oferece **Unificar instruções** quando há só `CLAUDE.md`, duas fontes ou um `AGENTS.md` gerado pelo app. Não há aviso ao abrir o projeto.
- R4 · **Unificar.** O diálogo lista as diferenças por seção e item. Cada uma vai para o `AGENTS.md`, fica no `CLAUDE.md` como trecho só do Claude ou é escolhida entre as duas versões. O resultado dos dois arquivos aparece antes de gravar. "Pedir ajuda da IA" sugere o destino das diferenças, sem decidir.
- R5 · **Gravação segura.** Os dois arquivos são gravados juntos, por arquivo temporário e `rename`. Se o segundo falhar, o primeiro volta. O app guarda a versão anterior para "Desfazer" e não grava se o arquivo mudou no disco depois da leitura.

### Tela

- R6 · **Projeto › Instruções.** Uma aba nova, ao lado de Configuração. No fluxo de planejamento, onde não há abas, ela abre em diálogo, como Memória e Métricas. Mostra os arquivos, o editor, quem lê cada um e o tamanho.
- R7 · **Ferramentas › Instruções vira atalho.** A aba e o item da paleta continuam e levam a Projeto › Instruções. Os estados, a prova e o plano B da SPEC-104 mudam para a tela nova, sem perda.
- R8 · **Editor.** Texto e prévia, Salvar e Descartar, marca de não salvo e "Abrir no editor". Se o arquivo mudar fora do app: sem edição, relê; com edição, pergunta antes de perder qualquer lado.
- R9 · **CLAUDE.md.** A linha do import aparece separada do trecho "Só para o Claude Code". "Mover seleção para o AGENTS.md" tira de um e põe no outro. Sem a linha do import, o app avisa e oferece "Recolocar o import".
- R10 · **Quem lê.** Uma linha por provedor, com a prova da SPEC-104 (`instructionSources` no Codex). "Carregado" só com prova; antes, "previsto".
- R11 · **Tamanho.** Mostra bytes e linhas contra o limite de 32 KiB do Codex. Avisa a partir de 80% e mostra onde o corte cai quando passa.
- R12 · **Subpastas.** `AGENTS.md` e `CLAUDE.md` aninhados continuam só leitura.

### Entrevista

- R13 · **Rodadas.** A IA lê o projeto em somente leitura e pergunta em rodadas: todas as perguntas cujos pré-requisitos já estão respondidos, numeradas (Q1, Q2…), com o motivo e uma resposta recomendada. As respostas abrem a próxima rodada.
- R14 · **Fato é da IA, decisão é da pessoa.** O que o código responde não vira pergunta: entra em "Achado no código", com o caminho.
- R15 · **Responder.** Escolher uma opção, escrever, aceitar a recomendação ou pular. "Aceitar as recomendadas que faltam" preenche a rodada, sem enviar.
- R16 · **Fim.** Sem perguntas abertas, o app mostra o resumo do que foi entendido e pede confirmação antes da proposta. "Encerrar e ver a proposta" termina antes, e o que ficou aberto não vira regra.
- R17 · **Provedor.** Segue "Planner e assistentes" (SPEC-100), com o provedor, o modelo e os tokens à vista. O provedor fica fixo até o fim da entrevista.
- R18 · **Pausar e retomar.** Uma entrevista por projeto fica guardada, com rodadas, respostas e rascunho, e sobrevive a fechar o app. Retomar usa a mesma thread; se ela não existir mais, começa outra com as respostas guardadas. Se os arquivos mudaram, a IA os relê.
- R19 · **Proposta por trecho.** Cada trecho mostra arquivo, seção, pergunta de origem e diff, com Aceitar, Editar, Recusar e Desfazer. "Aplicar" grava só os aceitos, e o que não casar mais com o arquivo volta como conflito.
- R20 · **Conferência.** O app verifica se os caminhos citados nos trechos existem e marca os que não existem.
- R21 · **Commit.** "Commitar ao aplicar" vem desmarcado. Marcado, commita só os arquivos de instruções na branch atual, sem push. Desmarcado, avisa que as worktrees das specs continuam com o texto antigo.

## Fora do escopo

- Editar arquivos de subpastas (P5), unificar sem pedir e avisar ao abrir o projeto.
- `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` e memória.
- Regras só do Codex: o formato não tem lugar para elas.
- Usar a skill `grill-me` instalada pela pessoa: as instruções da entrevista são do app e valem nos dois provedores.

## Decisões

- P1 · **Ferramentas › Instruções.** **Decidido (25/11):** vai para Projeto, e lá fica um atalho.
- P2 · **"Commitar ao aplicar".** **Decidido:** desmarcado.
- P3 · **Provedor da entrevista.** **Decidido:** o de "Planner e assistentes".
- P4 · **Pausar e retomar.** **Decidido:** sim, por projeto.
- P5 · **Subpastas.** **Decidido:** só leitura.

Esta spec troca a decisão 6 do épico #332 nos projetos novos e nos unificados. Nos outros, o `CLAUDE.md` continua como fonte.

## Perguntas em aberto

- P6 · **Versão.** A 0.27.0 já tem as SPECs 108–110. Entra nela ou na seguinte? **Recomendação:** na seguinte, se as três já ocuparem a 0.27.0.
- P7 · **Branch do commit.** E se a branch atual não for a base? **Recomendação:** commitar na atual e dizer qual é.

## Design

- `lib/core/providers/workspace_assets.dart`: estado `singleSource` em `AgentsMdState`, leitura do import, gravação segura dos dois arquivos.
- `lib/features/instructions/`: `instructions_view.dart` passa para a aba do Projeto; novos `instructions_editor.dart`, `unify_dialog.dart`, `interview_controller.dart`, `interview_view.dart` e `proposal_view.dart`.
- `lib/features/project/`: aba e botão em `project_screen.dart`; `project_service.dart`, `project_templates.dart`, `widgets/create_step.dart` e os textos do planner que hoje citam só o `CLAUDE.md`.
- `lib/core/git/repo_setup.dart`: o `AGENTS.md` entra nos arquivos aceitos do modelo de partida.
- Entrevista: `runStructured` (SPEC-100) com um schema por rodada (achados, perguntas, rascunho, fim) e outro para a proposta (arquivo, seção, texto antigo, texto novo, perguntas). A IA nunca grava; o app aplica os trechos.
- Banco: tabela `InstructionInterviews`, uma linha por workspace (JSON das rodadas, provedor, id da thread, hash dos arquivos e datas). Migração v38, a renumerar se as SPECs 108–110 usarem a v38 antes.

## Tarefas

- T1 · **Base da fonte única** (R1, R5, R11). Verificar: testes de `workspace_assets.dart`.
- T2 · **Criação de projeto** (R2). Verificar: testes de `project_service.dart` e do commit inicial.
- T3 · **Aba, editor e atalho** (R6–R10, R12). Verificar: testes de widget.
- T4 · **Unificar** (R3, R4). Verificar: testes do serviço e do diálogo.
- T5 · **Entrevista** (R13–R18). Verificar: testes com Claude e Codex falsos e da migração.
- T6 · **Proposta** (R19–R21). Verificar: testes de aplicação, conflito e commit.
- T7 · **Ponta a ponta** no app compilado, com dados isolados, e o guia de uso. Verificar: prints e relatório.

## Critérios de aceite

- [ ] `CLAUDE.md` com `@AGENTS.md` e um `AGENTS.md` da pessoa aparece como fonte única; um `@AGENTS.md` dentro de bloco de código não conta [R1] verificar: testes de unidade.
- [ ] Projeto novo sai com o texto no `AGENTS.md` e o import no `CLAUDE.md`, no commit inicial, sem sobrescrever arquivo da pessoa [R2] verificar: teste do serviço.
- [ ] Abrir um projeto antigo não grava nem avisa nada, e o override continua [R3] verificar: teste de widget e dos args do Codex.
- [ ] Unificar mostra o resultado antes, e uma falha no segundo arquivo devolve o primeiro [R4, R5] verificar: teste com falha simulada.
- [ ] Ferramentas › Instruções e a paleta abrem Projeto › Instruções, com todos os estados da SPEC-104 [R6, R7] verificar: testes de widget.
- [ ] Uma mudança externa com edição aberta não perde nenhum dos dois textos [R8] verificar: teste de widget.
- [ ] Apagar o import avisa e "Recolocar o import" resolve [R9] verificar: teste de widget.
- [ ] "Carregado" só aparece com prova, e 32 769 bytes mostram o corte [R10, R11] verificar: testes.
- [ ] Arquivos de subpastas não têm ação de escrita [R12] verificar: teste de widget.
- [ ] Uma rodada traz várias perguntas com recomendação, e a seguinte só depois das respostas [R13–R16] verificar: teste com provedor falso.
- [ ] A entrevista roda no Claude e no Codex, só leitura, e não grava arquivo [R13, R17] verificar: teste dos args e do repositório limpo.
- [ ] Fechar o app no meio e continuar mantém as respostas, com e sem a thread antiga [R18] verificar: teste do repositório e do controlador.
- [ ] Aplicar grava só os aceitos, e um trecho que não casa vira conflito [R19, R20] verificar: testes.
- [ ] O commit é opcional, desmarcado, e leva só os arquivos de instruções [R21] verificar: teste de git.

## Telas

Canvas: <https://claude.ai/artifact/JHbVvRnB2uSCernVSh2wwm> (cópia em `docs/mockups/spec-113/canvas/`).

| PNG | O que mostra | Requisitos |
|---|---|---|
| `1-editar-agents.png` | Projeto › Instruções com o editor, quem lê e o tamanho | R6, R8, R10, R11, R12 |
| `2-claude-importa.png` | `CLAUDE.md` com o import e o trecho só do Claude | R9 |
| `3-unificar.png` | Diálogo Unificar com as diferenças e o resultado | R3–R5 |
| `4-entrevista.png` | Rodada 2, com Q4–Q6, achados no código e rascunho | R13–R17 |
| `5-proposta.png` | Trechos aceitos, a decidir e recusados, e o commit desmarcado | R19–R21 |
| `6-retomar.png` | Entrevista pausada e o aviso de arquivo mudado | R18 |
| `7-ferramentas-atalho.png` | Ferramentas › Instruções como atalho | R7 |
