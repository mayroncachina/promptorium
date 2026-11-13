---
id: SPEC-069
status: aprovada
issue: 196
---

# Modo vibe code: uma tarefa sem spec escrita, com card, gate e PR

## Objetivo

Nem toda mudança merece uma spec. "Deixa o botão Comprar verde" ou "corrige o typo do rodapé" são pedidos de uma linha. Hoje eles vão para o modo **Editar** do Prompt, que mexe direto na pasta do workspace (o checkout principal), sem branch, sem gate, sem Review e sem PR. A tarefa fica só na conversa: não aparece no Quadro e não deixa rastro no repositório.

Esta spec cria o **modo vibe code**:
- você pede direto ao agente, sem escrever uma spec, pelo botão **"Fazer como tarefa"**;
- o app cria uma **VIBE**, uma spec mínima gerada sozinha, com worktree e branch próprios;
- a VIBE aparece no Quadro, passa pelo gate e pelo Review e termina num PR, como qualquer spec.

O modo é marcado como **"Use com cuidado"**: ele pula a revisão dos requisitos e o canvas, mas mantém as proteções obrigatórias.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/SN6Vr7scmPenUgLaod5TTB). Capturas em `docs/mockups/spec-069/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-antes.png` | Hoje: o Editar mexe no checkout principal e não deixa rastro | — |
| `2-fazer-como-tarefa.png` | O botão "Fazer como tarefa" e o aviso "Use com cuidado" | R1, R2, R3 |
| `3-conversa.png` | A conversa da VIBE, com o medidor de tamanho e "Enviar para Review" | R4, R6, R7 |
| `4-outro-assunto.png` | Um pedido sem relação: "abrir VIBE nova?" | R5 |
| `5-teto.png` | O teto estourou: virar spec ou continuar | R6, R8 |
| `6-quadro.png` | As VIBEs no Quadro, uma delas parada há 8 dias | R9, R11 |
| `7-descartar.png` | Descartar uma VIBE, com confirmação | R10 |

## Requisitos

- R1 · **Fazer como tarefa.** O Prompt e o menu do "Nova spec" do Quadro ganham "Fazer como tarefa".
  - Ele abre um diálogo com o campo "O que fazer", o número reservado (`VIBE-007`), a branch (`vibe/007-<slug>`) e a base (`main`).
  - "Começar VIBE" cria o worktree, abre a conversa da VIBE e põe o card em Em execução.
- R2 · **"Use com cuidado".** O diálogo diz o que a VIBE pula (requisitos revisados antes, canvas validado antes de mexer em tela, critérios escritos por você) e o que continua obrigatório (R6).
  - O aviso aparece até você marcar "Entendi; não mostrar este aviso de novo". Depois disso, uma linha curta continua no diálogo.
- R3 · **A VIBE é uma spec mínima.**
  - O arquivo é `docs/vibe/VIBE-NNN-<slug>.md`, com frontmatter (`id`, `status`, `kind: vibe`), o pedido como **R1** e um critério ("o pedido foi feito e conferido no Review").
  - O `SpecService` lê `docs/vibe/` como lê a pasta de specs, e o resto do app recebe um `Spec` com `kind == vibe`.
  - A série `VIBE-` não ocupa números `SPEC-`.
- R4 · **Uma VIBE por conversa.** Os pedidos seguintes na mesma conversa continuam na mesma VIBE, no mesmo worktree.
  - O agente roda com permissão de edição **no worktree da VIBE**, nunca no checkout principal.
- R5 · **Pedido sem relação.** Quando o pedido novo não tem a ver com a VIBE, o app pergunta "Isso parece outro assunto", com "Abrir VIBE nova" e "Continuar nesta".
  - O pedido só é executado depois da escolha.
  - "Abrir VIBE nova" leva o pedido para uma VIBE nova. "Continuar nesta" executa na VIBE atual e não pergunta de novo sobre o mesmo assunto.
  - Quem julga é uma checagem leve do Claude, que só pergunta com alta confiança.
- R6 · **Proteções obrigatórias, sem desligar:**
  - o **gate** (testes e lint) roda como numa spec;
  - o **Review** vem antes do merge, sem atalho de mergear direto;
  - o **teto** é de 15 arquivos ou 400 linhas mudadas, ajustável em `vibe.teto` no `.promptorium/config.yml`;
  - se o diff mexer em tela, os **prints de antes e depois** entram no Review.
  - A barra da conversa mostra o tamanho o tempo todo ("2/15 arquivos · 13/400 linhas").
- R7 · **Você decide quando termina.**
  - A VIBE fica em Em execução enquanto você conversa.
  - "Enviar para Review" (na barra da conversa e no card) roda o gate e move o card para Review.
  - Um pedido feito depois disso traz o card de volta para Em execução, com o aviso "o Review recomeça".
  - Os comentários do Review voltam para a mesma conversa, como já acontece com a sessão de uma spec.
- R8 · **O teto estourou.** O agente para antes de continuar e o app oferece duas saídas:
  - **"Virar spec"**: o app escreve um `SPEC-NNN` a partir da conversa (com o "Transformar em spec"), que **assume o worktree, a branch e o código já feito**, e o trabalho continua na hora.
    - A spec ganha `origem: VIBE-NNN` no frontmatter.
    - Se a VIBE mexeu em tela, os prints de antes e depois entram na spec como "Telas", no lugar do mock.
  - **"Continuar como VIBE"**: segue, e o teto volta a perguntar a cada 50% a mais.
- R9 · **No Quadro.**
  - A VIBE entra direto em **Em execução**, com a marca "VIBE" em roxo e o resumo ("conversando · 2 arquivos").
  - O **"Executar tudo"** e o **Autopilot** ignoram VIBEs.
  - Clicar no card abre a conversa da VIBE.
- R10 · **Descartar VIBE.** No menu do card e na barra da conversa.
  - A confirmação diz exatamente o que apaga: o worktree, a branch `vibe/…` e a conversa.
  - O número não é reutilizado e não dá para desfazer.
  - Uma VIBE já mergeada não pode ser descartada.
- R11 · **VIBE parada.** Depois de 7 dias sem mensagem, o card ganha o selo "parada há N dias". Nada é descartado sozinho.
- R12 · **Números.**
  - O número da VIBE e o da spec convertida são reservados no banco na hora em que nascem.
  - No merge, se o número já existir na `main`, o app renumera o arquivo e as referências antes de mergear.
- R13 · **Acessibilidade.**
  - O medidor de tamanho é um `meter` com o texto completo.
  - A pergunta de outro assunto e a do teto são diálogos de alerta, com o foco no botão principal.
  - "VIBE" é texto, não só cor.

## Fora do escopo

- Mudar o modo **Editar** do Prompt. Ele continua mexendo no checkout principal, e uma spec futura pode levá-lo para um worktree.
- Várias VIBEs numa conversa só, ou juntar VIBEs num PR.
- Atualizar a VIBE com a `main` automaticamente: continua sendo pelo "Atualizar com a main" do Review.
- Avisar, antes do merge, que uma spec em execução mexe nos mesmos arquivos (o conflito no merge continua com a SPEC-043).

## Design

### O que já existe

- `lib/core/providers/agent_provider.dart`: `PromptMode` (`edit` = `acceptEdits` na pasta do workspace).
- `lib/features/prompt/widgets/prompt_dialogs.dart`: "Levar para sessão" (worktree novo, `--resume <conversa> --fork-session`).
- `lib/features/prompt/conversation_manager.dart`: as conversas do Prompt e os eventos.
- `lib/features/prompt/conversation_actions.dart`: `conversationToSpec` ("Transformar em spec").
- `lib/features/specs/spec_service.dart`: `sync` lê a pasta `specsDir` e insere ou atualiza as specs.
- `lib/features/board/board_rules.dart`, `spec_runner.dart`, `step_gate.dart` e `autopilot.dart`: as colunas, a execução por etapa, o gate e o Autopilot.

### Componentes

- **`SpecKind { spec, vibe }`**: coluna nova em `specs` (migração; as que já existem ficam `spec`) e `kind:` no frontmatter.
- **`SpecService`**: lê também `docs/vibe/` (`vibeDir` no `ProjectConfig`). A diferença entre spec e VIBE fica toda aqui: o prefixo, a pasta e o `kind`.
- **`VibeService`**: reserva o número, cria o worktree e a branch `vibe/NNN-<slug>`, grava o arquivo da VIBE no worktree e abre a conversa em modo de edição com `cwd` no worktree.
- **`VibeBar`**: a barra da conversa, com o medidor (o `git diff --numstat` do worktree contra a base), "Descartar" e "Enviar para Review".
- **`VibeGuard`**: confere o teto depois de cada resposta do agente. Ao estourar, bloqueia o próximo envio e mostra a escolha do R8.
- **`unrelatedRequest(vibe, pedido)`**: a checagem leve do R5 (Haiku, só o título da VIBE, o resumo do diff e o pedido), devolvendo "sim" ou "não" e a confiança.
- **`promoteVibe`**: o "Virar spec" do R8, que gera o `SPEC-NNN`, troca o `kind` e reaproveita o worktree e a branch.
- No Quadro: `kind == vibe` mostra a marca e é excluída do "Executar tudo" e do Autopilot. O `isOnBoard` não muda.

### Testes

- `SpecService` lê `docs/vibe/` e dá `kind: vibe`; a série `VIBE-` não colide com `SPEC-`.
- Começar VIBE: número reservado, worktree e branch criados, card em Em execução e o agente com `cwd` no worktree, nunca no checkout principal.
- Medidor e teto: abaixo do teto segue; acima, bloqueia o envio e mostra a escolha. "Continuar" volta a perguntar a 150%.
- Enviar para Review: o gate roda e o card vai para Review. Um pedido depois disso volta o card e avisa.
- Outro assunto: o pedido espera a escolha; "Continuar nesta" não pergunta de novo.
- Virar spec: a spec nasce com `origem`, no mesmo worktree, com os prints de tela quando houver.
- Descartar: apaga o worktree, a branch e a conversa; o número não volta; uma VIBE mergeada não pode ser descartada.
- Quadro: a marca "VIBE"; fora do "Executar tudo" e do Autopilot; o selo de parada aos 7 dias.
- Merge com número já ocupado: renumera.

## Decisões

- **VIBE é uma spec.** Uma entidade nova obrigaria o Quadro, o Review, o gate e o Autopilot a tratar dois tipos de card. Como spec mínima, tudo funciona sem mudança.
- **Outra pasta, outra série.** Misturar com `docs/specs/` encheria a tela Specs de tarefas de uma linha e consumiria números `SPEC-`. Só no banco perderia o rastro no repositório.
- **Botão explícito, não o Editar.** O Editar continua como está para quem quer um ajuste local. A VIBE é uma escolha consciente, com o aviso.
- **Uma VIBE por conversa, com a pergunta de outro assunto.** Uma VIBE por pedido traria a burocracia de volta. A pergunta separa assuntos sem obrigar.
- **Você decide o fim.** O agente concluir não manda para o Review. Senão, uma conversa de cinco ajustes viraria cinco rodadas de gate e de Review.
- **O teto vira spec no lugar.** Quem está no vibe code não quer parar. O preço, o mock vir depois, fica registrado em `origem` e nos prints.
- **Número reservado no banco.** Quem trabalha sozinho no repositório não precisa de nada mais complexo. A renumeração no merge cobre o resto.

## Plano

1. **t1 · A VIBE como spec** (R3, R12): `SpecKind`, a migração, o `SpecService` lendo `docs/vibe/`, a reserva de número e a renumeração no merge.
2. **t2 · Começar e conversar** (R1, R2, R4, R7, R13): "Fazer como tarefa", o aviso, o `VibeService`, a conversa no worktree, "Enviar para Review" e a volta dos comentários.
3. **t3 · Proteções** (R5, R6, R8): o medidor, o teto, os prints de tela, a pergunta de outro assunto e o "Virar spec".
4. **t4 · Quadro** (R9, R10, R11): a marca, a exclusão do "Executar tudo" e do Autopilot, "Descartar VIBE" e o selo de parada.

## Critérios de aceite

- [x] Um pedido feito por "Fazer como tarefa" vira um card no Quadro e termina num PR, sem escrever spec.
- [x] A VIBE nunca mexe no checkout principal.
- [x] Passar do teto para e oferece virar spec, sem perder o trabalho.
- [x] O gate e o Review são obrigatórios; os prints de antes e depois aparecem quando há tela.
- [x] Uma VIBE descartada some do Quadro, com o worktree e a branch.
