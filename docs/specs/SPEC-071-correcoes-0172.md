---
id: SPEC-071
status: aprovada
tipo: bug
---

# Correções da 0.17.2

## Objetivo

Corrigir os defeitos que a revisão da `main` (106df7c) encontrou e que não pertencem à reforma da criação de projeto. Relatório: `~/Documentos/promptorium/erros-main.pdf`. Os códigos entre colchetes são os de lá (T = telas, N = núcleo, P = criação de projeto).

Nada disso aparecia no `flutter analyze` nem na suíte: os defeitos ficam onde os testes usam dublês (git e `gh` reais, a ordem real dos eventos de processo, duas ações ao mesmo tempo). Cada correção traz o teste que teria pego o defeito.

Ficam para a spec da reforma da criação de projeto: P4, P8 a P15 e P17.

## Requisitos

### Review, merge e PR (t1)

- R1 · "Mergear PR" não descarta trabalho: com alterações não commitadas ou commits à frente do remoto no worktree, o app recusa e oferece **Enviar e mergear**, que commita as pendências, faz push e só então mergeia. [T1]
- R2 · Verificar um PR que não está em "Acompanhar PR" só atualiza o status: não manda comentários ao agente nem grava rodada. Criar ou trazer um PR grava `pr.seen.<sessão>`, então acompanhar depois só envia o que chegar a partir dali. Duas verificações simultâneas da mesma sessão viram uma só. [T2, T12]
- R3 · Os PRs das filhas empilhadas só mudam de base depois que o merge da mãe deu certo. Se o merge falhar, nenhuma base muda. [T4]
- R4 · Um merge em andamento trava a lista do Review e os botões de merge de todo o workspace até terminar, e o fim do merge (aviso, atualização da fila) acontece mesmo se a pessoa trocou de item. [T5]
- R5 · VIBE: enquanto o gate roda ("Verificando…"), o composer da conversa não aceita pedidos novos, e o merge de uma VIBE com o agente trabalhando é recusado com o motivo. [T7]

### Sessões, Quadro e specs (t2)

- R6 · O Autopilot e "Executar SPEC-X" nunca arrancam a mesma spec duas vezes: uma spec que está arrancando conta no limite de paralelo e é ignorada por um segundo pedido, e os ticks do Autopilot de um workspace não se sobrepõem. [T3]
- R7 · Uma mensagem enviada no instante em que a sessão seria liberada por ociosidade mantém a sessão viva e chega ao agente. [T6]
- R8 · O editor de spec não sobrescreve uma alteração feita fora do app: salvar confere o texto que estava no disco e, se mudou, abre o diálogo de conflito que já existe. Com o editor sem alterações, a spec recarrega quando o arquivo muda. [T8]
- R9 · O Quadro só aceita transições válidas ao arrastar ou em "Mover para…": Feito só via merge, Em execução e Review só pelo runner, e VIBE nunca vai para Feito. Uma coluna inválida não destaca e diz o motivo. [T9]
- R10 · "Retomar" fica ocupado enquanto retoma e não manda a mensagem de continuar duas vezes. [T10]
- R11 · O elemento apontado no preview chega ao composer mesmo se a pessoa trocou de tela enquanto apontava. [T11]

### Processos (t3)

- R12 · Saída de processo fora de UTF-8 nunca derruba o app: git, `gh`, o runner padrão e os streams do `claude`, do Codex e dos agentes ACP decodificam com substituição de bytes inválidos. [N1, N7]
- R13 · O fim de um processo `claude` não espera o limite de 2 s quando o stderr fecha antes do stdout, e não grava a linha "stdout ainda aberto". [N2]
- R14 · A redação de credenciais do Codex age sobre os valores do JSON, nunca sobre o texto serializado, e `sk-` só casa no início de palavra. [N3]
- R15 · ACP: se a abertura falhar, o processo do agente é encerrado; o handshake tem limite de 30 s; erros de escrita no stdin e nos streams são tratados. [N4, N5]
- R16 · A consulta de uso (`claude -p /usage`) que passa do limite é encerrada, e nunca há mais de uma em voo. [N6]

### Diversos e criação de projeto (t4)

- R17 · Parar um servidor de desenvolvimento enquanto ele sobe encerra o processo que estava subindo. [N8]
- R18 · Abrir o preview duas vezes seguidas reaproveita a mesma abertura: uma só janela, rastreada e fechada ao sair. [N9]
- R19 · Parar o servidor MCP durante a partida não deixa socket escutando. [N10]
- R20 · A cópia de segurança da restauração inclui o `-wal` e o `-shm`. [N11]
- R21 · Criar projeto pode ser repetido depois de uma falha: uma pasta que só tem o que a própria criação gravou (`.git`, arquivos do modelo) é aceita. A identidade do git é conferida antes de criar a pasta, com a mensagem de como configurá-la. [P1]
- R22 · As specs gravadas pelo roadmap vão para o Backlog do Quadro, não para a Bandeja. Uma falha no meio da gravação não duplica specs ao tentar de novo. [P2, P7]
- R23 · Com um modelo de partida, "Gravar CLAUDE.md" nasce ligado e substitui o CLAUDE.md mínimo do modelo. O CLAUDE.md do modelo vai ao planner como base da etapa Stack. [P3]
- R24 · Uma pasta com só `CLAUDE.md`, `README*`, `LICENSE` ou `.gitignore` não conta como "já tem código". [P5]
- R25 · O repositório criado começa na branch `main` (`git init -b main`). [P6]
- R26 · Limpeza: a área fixada pelo modelo não duplica quando o planner usa um sinônimo; os botões ficam ocupados durante todo o "Gerar proposta completa"; Enter no nome cria o projeto; o `NewProjectDialog` morto sai, e `tildePath`/`defaultProjectParent` vão para `core/`. [P16, P18, P19, P20]

## Fora do escopo

- A reforma do fluxo de criação de projeto (relatório de novidades, faixas A a C), incluindo P4 e P8 a P15.
- As melhorias de arquitetura do relatório (transporte comum de JSON por linhas, `ProcessRunner` único, índices). R12 corrige o defeito sem unificar o transporte.

## Design

As telas tocadas reaproveitam componentes que já existem:
- o diálogo de conflito de spec (`showSpecConflictDialog`);
- os avisos (`showAppToast`);
- o destaque de arraste do Quadro.

Por isso a spec não tem mockup novo. A única ação nova na tela é **Enviar e mergear** (R1), que segue o padrão dos diálogos de merge do Review.

## Tarefas

| Tarefa | Requisitos | Branch |
|---|---|---|
| t1 · Review e merge | R1–R5 | `spec/071-t1-review` |
| t2 · Sessões, Quadro e specs | R6–R11 | `spec/071-t2-quadro` |
| t3 · Processos | R12–R16 | `spec/071-t3-processos` |
| t4 · Diversos e criação de projeto | R17–R26 | `spec/071-t4-criacao` |

## Critérios de aceite

- [ ] Mergear PR com commits não enviados ou pendências não perde nada [R1] verificar: flutter test test/features/review
- [ ] Verificar um PR não acompanhado não envia nada ao agente [R2] verificar: flutter test test/features/review
- [ ] Merge da mãe que falha não muda a base das filhas [R3] verificar: flutter test test/features/review
- [ ] Trocar de item durante o merge não perde o fim do merge nem permite outro merge [R4] verificar: flutter test test/features/review
- [ ] VIBE em gate não aceita pedidos e não é mergeada com o agente ocupado [R5] verificar: flutter test test/features/vibe
- [x] Dois pedidos para a mesma spec abrem uma sessão só [R6] verificar: flutter test test/features/board
- [x] Mensagem no instante da liberação por ociosidade chega ao agente [R7] verificar: flutter test test/features/sessions
- [x] Alteração externa não é sobrescrita pelo editor [R8] verificar: flutter test test/features/specs
- [x] Transições inválidas do Quadro são recusadas [R9] verificar: flutter test test/features/board
- [x] Retomar duas vezes manda uma mensagem só, e o apontar sobrevive à troca de tela [R10, R11] verificar: flutter test test/features/sessions
- [x] Git e streams com bytes fora de UTF-8 não derrubam nada [R12] verificar: flutter test test/core
- [x] O fim do `claude` não espera 2 s [R13] verificar: flutter test test/core/claude
- [x] A redação do Codex mantém o JSON válido [R14] verificar: flutter test test/core/codex
- [x] ACP sem processo órfão e com limite no handshake [R15] verificar: flutter test test/core
- [x] Uma consulta de uso por vez, encerrada no limite [R16] verificar: flutter test test/core/claude
- [x] Servidor parado ao subir, preview aberto duas vezes e MCP parado na partida não deixam processo, janela nem socket [R17–R19] verificar: flutter test test/core
- [x] A restauração guarda o WAL [R20] verificar: flutter test test/data
- [x] Criar projeto depois de uma falha de git funciona, na branch main, com as specs no Quadro [R21, R22, R25] verificar: flutter test test/features/project
- [x] CLAUDE.md do modelo e pasta "sem código" corretos [R23, R24] verificar: flutter test test/features/project
- [x] Limpeza do fluxo de criação [R26] verificar: flutter test test/features/project
- [ ] O projeto compila e a análise estática passa [R1–R26] verificar: flutter analyze
