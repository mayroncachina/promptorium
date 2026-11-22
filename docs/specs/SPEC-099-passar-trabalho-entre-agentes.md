---
id: SPEC-099
status: em implementação
versao: 0.24.0
tipo: recurso
epico: 332
relacionada: 83
issue: 338
depende-de: [SPEC-094, SPEC-095, SPEC-096, SPEC-098]
---

# Passar o trabalho entre agentes

## Objetivo

Dar à sessão uma ação **"Continuar no Codex"** (ou **"Continuar no Claude"**, quando a sessão é do Codex) que leva o trabalho para o outro agente sem perder o fio. A ação abre uma sessão nova do outro provedor **no mesmo worktree e na mesma branch** e entrega a ela o que a anterior deixou, ligando as duas sessões.

O épico (#332) já decidiu como trocar: o provedor nunca muda no meio de uma execução (decisão 4). Trocar é abrir uma execução nova com transferência explícita. Esta spec define essa transferência em três caminhos, do mais rico ao mais simples:

1. **Passagem do ai-memory** (com a SPEC-098 ligada): o fim da sessão de origem grava a passagem pelos hooks, sem chamar modelo, e o `SessionStart` da sessão nova a recebe;
2. **`ai-memory run` no terminal embutido**: o launcher do ai-memory abre o outro agente no worktree e pode trazer o histórico local da sessão anterior;
3. **Resumo do app**: sem o ai-memory, o app monta um resumo da sessão (como a "Nova conversa com resumo" da SPEC-087, que já está na main), e a pessoa o revisa antes de enviar.

Exemplo concreto:

> A sessão "Parser de front-matter" roda no Claude Code no worktree `spec-parser`. Às 11h40 a cota de 5h acaba no meio da tarefa: a sessão para com "limite de uso atingido · reinicia em 1h43". Há 5 arquivos alterados e não commitados, e a abordagem com regex já falhou nos testes de BOM.
>
> Hoje, para seguir no Codex, a pessoa abre uma sessão nova, escolhe o Codex, cai num worktree novo (ou na raiz) e cola um resumo escrito à mão. O Codex não sabe o que falhou.
>
> Com esta spec, a sessão mostra "Cota de 5h do Claude Code esgotada · Continuar no Codex". O diálogo mostra a passagem que o ai-memory gravou ("Parser trocado para leitor por linhas; falta `test/spec_parser_bom_test.dart`; regex descartada: falhava com BOM"), os 5 arquivos que ficam no worktree, o modelo e o acesso no Codex. A sessão nova "Parser de front-matter (Codex)" abre no mesmo worktree com "continuada de Parser de front-matter · Claude Code".

## Requisitos

### A ação

- R1 · **"Continuar no Codex" / "Continuar no Claude" na sessão.** Botão no cabeçalho da sessão, ao lado de Fork. O rótulo leva o nome do outro provedor. O botão só aparece com os dois provedores instalados e o destino habilitado nas Sessões (SPEC-096). Quando não pode ser usado, fica desabilitado com o motivo:
  - "Espere o turno acabar ou pare a sessão": a origem está trabalhando ou tem uma aprovação pendente (decisão 4);
  - "Codex não está ligado nas Sessões": o destino está desligado nesse fluxo ou falta login;
  - "Sessões de etapa trocam de provedor pela execução da spec (SPEC-101)": a sessão pertence a uma etapa do Quadro (P4).
- R2 · **Sugestão quando a cota acaba.** Quando a origem para por limite de uso (evento de limite do Claude ou `rateLimitReachedType` do Codex, SPEC-097), aparece uma faixa na sessão: "Cota de 5h do Claude Code esgotada · reinicia em 1h43 · Continuar no Codex". A faixa só aparece se o destino tiver cota disponível. O app **nunca** troca de provedor sozinho.
- R3 · **Diálogo "Continuar no Codex".** Antes de abrir a sessão nova, um diálogo mostra:
  - origem e destino, cada um com provedor, modelo e estado;
  - **o que vai junto**: worktree, branch e o número de arquivos alterados e não commitados, que continuam no worktree (nada é copiado nem guardado em stash);
  - **no destino**: modelo (padrão do provedor, que dá para trocar), esforço e acesso convertido pela decisão 3 (Perguntar = só leitura, Editar = escreve com confirmação, YOLO só porque a sessão está em worktree);
  - **fica para trás**: o que só existe na origem, como um agente de `.claude/agents` (decisão 7) ou um orçamento em US$, com a etiqueta "Só Claude Code";
  - **como passar o trabalho**: os três caminhos, com o recomendado marcado e os indisponíveis desabilitados com o motivo;
  - **mensagem inicial**: editável, vai para o composer da sessão nova (P1).

### Os três caminhos

- R4 · **Passagem do ai-memory.** Disponível quando a SPEC-098 mostra o ai-memory conectado com hooks nos dois provedores.
  1. Se a origem ainda tem processo (ociosa, esperando mensagem), o app a encerra de forma limpa para o `SessionEnd` gravar a passagem automática. Se ela já terminou, o app usa a passagem que existe.
  2. O app espera até 10 s pela passagem da sessão de origem (`memory_handoff_list`, pelo id nativo da sessão) e mostra no diálogo resumo, o que falhou, perguntas abertas, próximos passos e arquivos tocados, como texto puro (SPEC-098 R13).
  3. Se a origem foi cortada sem passagem (queda, cota no meio do turno, sem `SessionEnd`), o diálogo diz "Sem passagem: a sessão foi cortada. O Codex vai ler o que o ai-memory capturou dela". O ai-memory já aponta essa sessão para a próxima (`newer_unended_session`).
  4. A sessão nova recebe a passagem no próprio `SessionStart`. A mensagem inicial cita o id exato da passagem e pede ao agente que a aceite com `memory_handoff_accept` se ela não estiver no contexto. Assim a passagem certa é entregue mesmo com o servidor em modo oferta (`claim_on_session_start = false`).
  5. Depois do primeiro turno, o app confere no `memory_handoff_list` se a passagem foi aceita e por qual sessão, e mostra o resultado no cartão da timeline (R8).
- R5 · **Passagem manual concorrente.** O ai-memory entrega uma passagem manual do projeto antes de qualquer automática. Se houver uma aberta, o diálogo avisa ("Há uma passagem manual de 18/11, que o ai-memory entrega antes desta") e oferece "Descartar a manual" (com confirmação, SPEC-098 R11) ou "Seguir assim". A mensagem inicial com o id exato continua valendo nos dois casos.
- R6 · **`ai-memory run` no terminal.** Em "Mais opções", "Abrir no terminal com `ai-memory run codex`" abre o terminal embutido no worktree da sessão com `ai-memory run <destino> --no-autowire`, mais `--yolo` só quando a sessão já era YOLO em worktree. O `--no-autowire` impede o launcher de mudar a configuração do agente sem a prévia da SPEC-098. A opção fica marcada "fora da timeline": o app abre o terminal, mas não acompanha a conversa nem grava os eventos dela. Só aparece com o ai-memory na versão mínima (SPEC-098 P7) e o destino instalado (P3).
- R7 · **Resumo do app (sem o ai-memory).** Sempre disponível. É o único caminho quando o ai-memory não está instalado ou não está ligado nos dois provedores. O app monta, sem chamar modelo, um resumo da sessão:
  - o último pedido e um trecho da última resposta;
  - os arquivos alterados na sessão;
  - os comandos que falharam, com o código de saída;
  - a última lista de tarefas;
  - os arquivos não commitados do worktree.

  A pessoa edita o resumo no diálogo e ele vai para o composer da sessão nova. Reaproveita o `conversationSummary` e o `_SummaryDialog` da SPEC-087, generalizados para sessões. Com o ai-memory ausente, uma linha discreta explica que a passagem dele inclui o que falhou e as perguntas abertas, com link para Configurações → Memória.

### A sessão nova e o vínculo

- R8 · **Sessão continuada.** A sessão nova nasce no mesmo worktree e branch da origem (sem `git worktree add`) e ganha o título "<título da origem> (Codex)", que dá para editar. A nota de origem no topo da timeline diz "Continuada de <título> · Claude Code · 11h41". Abaixo dela vem um cartão:
  - com passagem: "Passagem do ai-memory", com o id curto, o dono, o resumo e o estado ("entregue no início", "aceita às 11h52" ou "não confirmada");
  - sem passagem: "Resumo do app", com o texto enviado.
- R9 · **Vínculo nos dois sentidos.** A origem mostra "Continuada no Codex → <título>" no cabeçalho e na lista, com o estado "Concluída". A nova mostra "continuada de <título> · Claude Code". As duas pontas abrem a outra sessão. Uma cadeia (Claude → Codex → Claude) mostra só o elo imediato de cada lado. Excluir uma das sessões não apaga a outra; o vínculo some.
- R10 · **Volta.** O caminho de volta é simétrico: na sessão do Codex, o botão é "Continuar no Claude", com os mesmos três caminhos. O resumo do app a partir de uma sessão do Codex usa os eventos neutros de arquivo e comando (SPEC-095).
- R11 · **Atividades e notificações.** A sessão nova aparece em Atividades com o robô e o provedor dela. A passagem fica registrada no diário de atividades ("Trabalho passado do Claude Code para o Codex · Parser de front-matter"). Nenhuma notificação extra.

### No Prompt e a partir da Memória

- R12 · **Conversas do Prompt.** A ação "Nova conversa" do painel Contexto (SPEC-087 R9) ganha a escolha do provedor ("no Claude Code" ou "no Codex") e, com o ai-memory ligado, a opção de usar a passagem no lugar do resumo do app. O menu da conversa ganha "Continuar no Codex", que abre o mesmo diálogo em versão curta: sem worktree e com o modo da conversa convertido. Vale só onde o Codex já roda no Prompt (SPEC-096).
- R13 · **A partir de uma passagem.** "Continuar em…" no painel Memória (SPEC-098 R11) abre este diálogo com aquela passagem já escolhida. Quando o diretório da passagem é o worktree de uma sessão conhecida, a origem é essa sessão. Quando não é, a sessão nova abre na raiz do workspace, com a passagem e sem vínculo.

## Fora do escopo

- Trocar de provedor no meio de um turno ou de uma execução de spec (decisão 4); sessões de etapa ficam com a SPEC-101.
- Trocar de provedor sozinho quando a cota acaba (isso é do orquestrador, SPEC-109).
- Lançar as sessões do app por `ai-memory run` ou acompanhar na timeline a conversa aberta no terminal.
- Converter o histórico de uma sessão de um provedor para o formato do outro, ou retomar a sessão do Claude dentro do Codex.
- Comparar as duas respostas lado a lado (SPEC-108).
- Outros agentes além do Claude Code e do Codex.

## Decisões em aberto

- P1 · **Mensagem inicial.** (a) Vai para o composer da sessão nova e só sai quando a pessoa envia; (b) é enviada sozinha ao abrir. **Decidido:** (a). A mensagem vai para o composer da sessão nova e só sai quando a pessoa envia, como na "Nova conversa com resumo" da SPEC-087. O primeiro turno pago só acontece quando ela quer.
- P2 · **Passagem caprichada.** Um turno extra da origem antes de encerrar, pedindo ao agente uma passagem manual (`memory_handoff_begin`) com o que falhou e os próximos passos. **Decidido:** opção "Pedir ao Claude uma passagem caprichada" desmarcada por padrão, habilitada só com a origem viva, ociosa e com cota. Custa um turno; a passagem automática dos hooks não chama modelo.
- P3 · **Terminal com `ai-memory run`.** O histórico local da sessão anterior só vem quando a origem é uma sessão que o `run` conhece; as sessões abertas pelo app não passam pelo `run`. **Decidido:** fica em "Mais opções" como experimental, com `--no-autowire`. A sondagem com o binário real fica pendente (o ai-memory não foi instalado nesta máquina); a opção é apresentada como "fora da timeline".
- P4 · **Sessões de etapa.** **Decidido:** a ação fica escondida nas sessões de etapa; a troca é da execução da spec (SPEC-101). O motivo "Sessões de etapa trocam de provedor pela execução da spec (SPEC-101)" aparece quando se chega ao diálogo por outro caminho (a passagem da Memória apontando o worktree de uma sessão de etapa).
- P5 · **Onde guardar o vínculo.** (a) Reaproveitar o vínculo com a sessão pai que a SPEC-096 cria para o fork, com um tipo "continuação"; (b) colunas próprias. **Decidido:** (a). O vínculo reaproveita `sessions.parentSessionId` (v35, SPEC-096) e o tipo "continuação" é um evento do app (`promptorium_handoff`) gravado no início da sessão nova, em `session_events`, com a origem, o caminho e o id da passagem. Sem migração: o fork não grava esse evento, então o tipo fica explícito e a nota do topo da timeline sai do mesmo registro.
- P6 · **Prompt nesta spec.** **Decidido:** incluir (R12). Nas conversas o vínculo fica só na nota de origem, sem coluna nova.
- P7 · **Worktree depois da troca.** As duas sessões apontam para o mesmo worktree. **Decidido:** o Review e "Abrir no Review" seguem a sessão mais nova da cadeia (a fila mostra uma sessão por worktree compartilhado), e a origem mostra "trabalho continuado em <título>". Merge e PR acontecem uma vez só, pela branch.
- P8 · **Encerrar a origem viva.** Fechar a entrada do processo deve disparar o `SessionEnd` no Claude (`-p` com `stream-json`) e no App Server do Codex, mas isso precisa de prova. **Decidido:** encerrar a origem com o fim limpo do processo e esperar a passagem; se ela não aparecer na primeira metade da espera, o app chama `ai-memory finalize-session --agent <agente> --session-id <id>` uma vez e continua esperando até os 10 s. A confirmação com o binário real fica para a sondagem.

## Design

### O que já existe

- `lib/features/sessions/session_manager.dart`: `StartRequest` já aceita `provider`, `worktreePath`, `branch`, `baseBranch`, `origin` (a nota no topo da timeline) e `environment`. O fork (`fork`) mostra como criar uma sessão a partir de outra. A continuação usa o mesmo worktree, sem `addWorktree` e sem stash.
- `lib/features/sessions/sessions_screen.dart`: cabeçalho com Abrir terminal, Fork, preview e Parar/Retomar, onde entra o botão (R1).
- `lib/features/prompt/prompt_actions.dart` (`conversationSummary`) e `lib/features/context/widgets/context_compaction.dart` (`_SummaryDialog`, "Nova conversa" vazia ou com resumo): base do resumo do app (R7, R12).
- `lib/features/sessions/session_changes.dart` e `timeline.dart`: arquivos alterados, resultados de comandos e tarefas, que alimentam o resumo.
- `lib/features/sessions/widgets/session_terminal.dart`: terminal embutido no worktree (hoje `claude --resume` ou `codex resume`), que ganha o comando do `ai-memory run` (R6).
- `RateLimit` no `session_manager.dart` e a cota da SPEC-097: o gatilho da faixa (R2).

### Componentes novos

| Arquivo | Papel |
|---|---|
| `lib/features/sessions/handoff/continue_controller.dart` | Valida as condições (R1), encerra a origem, espera a passagem, monta o `StartRequest` e grava o vínculo (R4, R8, R9) |
| `lib/features/sessions/handoff/session_summary.dart` | Resumo do app para sessões, a partir de eventos neutros (R7, R10) |
| `lib/features/sessions/handoff/continue_dialog.dart` | O diálogo (R3–R7), também na versão curta do Prompt (R12) |
| `lib/features/sessions/handoff/handoff_card.dart` | Cartão da passagem na timeline (R8), que reaproveita o modelo `Handoff` da SPEC-098 |
| `lib/features/sessions/widgets/quota_switch_banner.dart` | Faixa de cota esgotada (R2) |

Arquivos alterados: `sessions_screen.dart`, `session_manager.dart` (encerrar limpo, vínculo), `session_terminal.dart`, `session_list_panel.dart` (vínculo na lista), `context_compaction.dart` e `prompt_screen.dart` (R12), `ai_memory_view.dart` da SPEC-098 (R13) e o diário de atividades (R11).

**Migração do banco:** não (P5). O vínculo reaproveita `sessions.parentSessionId` (v35) e o tipo "continuação" fica num evento do app (`promptorium_handoff`) da sessão nova, com a origem, o caminho e o id da passagem (ou `resumo`).

### Dependências

| O quê | Depende de | Por quê |
|---|---|---|
| Qualquer sessão do Codex aberta pelo app (as duas direções) | **SPEC-096** (MVP) | É a 096 que abre sessões do Codex no worktree e tem o interruptor por fluxo |
| Converter acesso, modelo e esforço; "fica para trás" com "Só Claude Code" | **SPEC-094** (MVP) | Capacidades e opções por provedor |
| Resumo do app a partir de uma sessão do Codex (Codex → Claude) | **SPEC-095** (MVP) | Eventos neutros de arquivo e comando |
| Faixa de cota esgotada (R2) | **SPEC-097** (MVP) | Cota do Codex; sem ela a faixa só aparece quando a origem é o Claude |
| Encerrar limpo e `SessionEnd` no Codex (R4, P8) | **SPEC-093** (MVP) | Sondagem |
| Passagem do ai-memory, terminal com `ai-memory run` e "Continuar em…" (R4–R6, R13) | **SPEC-098** | Detecção, hooks nos dois provedores e leitura das passagens |
| Resumo do app, diálogo "Nova conversa" | SPEC-087 (na main) | Reaproveitados |
| Conversas do Prompt no Codex (R12) | SPEC-096 | O Codex precisa estar ligado no Prompt |

Sem o MVP (093–097), só existe a direção Claude → Claude, que não é o objetivo desta spec. Por isso ela entra na 0.23, depois da 0.22. Sem a 098, a ação funciona só com o resumo do app (R7).

### Roteiro para a sondagem

Junto com o roteiro da SPEC-098, no mesmo repositório temporário e com o mesmo isolamento:

1. Fechar a entrada de um `claude -p --input-format stream-json` ocioso: o hook `SessionEnd` roda? Quanto tempo até a passagem aparecer no `memory_handoff_list` (P8)?
2. O mesmo com uma thread do Codex no App Server: encerrar a thread ou o processo dispara o `SessionEnd`?
3. Sessão nova do outro provedor no mesmo diretório: a passagem chega no `SessionStart`, e o `memory_handoff_list` passa a mostrá-la como aceita pela sessão nova?
4. Com o servidor em `claim_on_session_start = false`: a mensagem inicial com o id exato faz o agente aceitar a passagem certa?
5. `ai-memory run codex --no-autowire` num worktree em que a sessão do Claude foi aberta fora do `run`: o Codex recebe só a passagem ou também o histórico local (`AI_MEMORY_PREVIOUS_SESSION_HISTORY`) (P3)?

## Tarefas

| Tarefa | Entrega | Requisitos |
|---|---|---|
| T1 · Controlador e vínculo | Condições, `StartRequest` no mesmo worktree, vínculo, migração ou vínculo da 096 | R1, R8, R9 |
| T2 · Resumo do app | Resumo de sessão com eventos neutros e diálogo no caminho sem ai-memory | R3, R7, R10 |
| T3 · Passagem do ai-memory | Encerrar limpo, esperar a passagem, aviso de passagem manual, cartão com confirmação, terminal com `ai-memory run` | R4–R6, R8 |
| T4 · Entradas | Faixa de cota, Prompt, "Continuar em…" a partir da Memória, Atividades | R2, R11–R13 |
| T5 · Teste no app | App isolado: Claude → Codex com passagem, Codex → Claude com resumo, cota esgotada simulada pelo evento gravado | R1–R13 |

## Critérios de aceite

- [ ] O botão mostra o nome do outro provedor e fica desabilitado com o motivo enquanto a origem trabalha, tem aprovação pendente, é de etapa ou o destino não está ligado [R1] verificar: testes de widget do cabeçalho.
- [ ] A faixa de cota esgotada aparece só depois do evento de limite e só com cota no destino; nada troca sozinho [R2] verificar: teste com evento de limite gravado.
- [ ] O diálogo mostra worktree, branch, arquivos não commitados, modelo, acesso convertido e o que fica para trás [R3] verificar: teste de widget com uma sessão de exemplo.
- [ ] A sessão nova abre no mesmo worktree e branch, sem `git worktree add` e sem stash, e a mensagem inicial fica no composer até a pessoa enviar [R3, R8, P1] verificar: teste do controlador com o git falso.
- [ ] Com o ai-memory ligado, a origem viva é encerrada, a passagem dela aparece no diálogo, a mensagem inicial cita o id e o cartão mostra "aceita" depois do primeiro turno [R4] verificar: T5 com capturas e o roteiro registrado.
- [ ] Sessão cortada sem passagem mostra o aviso e segue [R4] verificar: teste com `newer_unended_session`.
- [ ] Passagem manual aberta gera o aviso com "Descartar a manual" e "Seguir assim" [R5] verificar: teste de widget.
- [ ] O terminal roda `ai-memory run <destino> --no-autowire` no worktree e a opção diz "fora da timeline" [R6] verificar: teste do comando montado.
- [ ] Sem o ai-memory, o resumo do app traz último pedido, trecho da resposta, arquivos alterados, comandos que falharam e não commitados, sem chamar modelo [R7] verificar: teste do `session_summary` com uma timeline gravada (Claude e Codex).
- [ ] As duas sessões mostram o vínculo e uma abre a outra; excluir uma não apaga a outra [R9] verificar: teste do repositório e de widget.
- [ ] Codex → Claude funciona pelos mesmos caminhos [R10] verificar: T5.
- [ ] Atividades mostra a sessão nova com o provedor e o diário registra a passagem [R11] verificar: teste do diário.
- [ ] "Nova conversa" do Prompt escolhe o provedor e, com o ai-memory, a passagem; "Continuar em…" da Memória abre o diálogo com a passagem escolhida [R12, R13] verificar: testes de widget.

## Telas

Canvas: [SPEC-099 · Passar o trabalho entre agentes](https://claude.ai/artifact/WKLCUqNSE1tVP6ReenDK2Z). Capturas em `docs/mockups/spec-099/`.

| PNG | O que mostra | Requisitos |
|---|---|---|
| `1-sessao-cota-esgotada.png` | Sessão do Claude parada pela cota: "Continuar no Codex" no cabeçalho, ao lado de Fork, e a faixa "Cota de 5h do Claude Code esgotada · reinicia em 1h43 · Continuar no Codex" acima do composer; rodapé com as duas cotas | R1, R2 |
| `2-dialogo-passagem.png` | Diálogo "Continuar no Codex": origem e destino, a passagem do ai-memory (resumo, o que falhou, perguntas abertas, próximos passos, arquivos), o que vai junto, modelo e acesso no Codex, o que fica para trás, os três caminhos e a mensagem inicial | R3–R6 |
| `3-sessao-continuada.png` | Sessão nova do Codex no mesmo worktree: vínculo "continuada de", cartão "Passagem do ai-memory · aceita às 11h52", a mensagem inicial e a resposta do Codex; na lista, a origem com "continuada no Codex" | R8, R9, R11 |
| `4-sem-ai-memory-e-estados.png` | Diálogo no caminho do resumo do app (sem o ai-memory) e os estados: sessão trabalhando, Codex desligado, sessão de etapa, passagem manual concorrente e sessão cortada sem passagem | R1, R4, R5, R7 |
