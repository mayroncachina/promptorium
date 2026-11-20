---
id: SPEC-107
status: rascunho
versao: 0.24.0
tipo: melhoria
epico: 332
issue: 342
estende: SPEC-087
depende-de: [SPEC-087, SPEC-093, SPEC-094, SPEC-095, SPEC-096]
---

# Contexto e compactação no Codex

## Problema

A SPEC-087 (0.22.0, concluída) criou o medidor de contexto, o painel Uso · Fontes · Evolução, o acompanhamento da compactação e o "Compactar agora". Tudo foi medido e provado no Claude Code. O `ContextTracker` lê eventos no formato do Claude (`usage` da mensagem, `system/compact_boundary`, `get_context_usage`), e o `compactAvailability` recusa qualquer provedor diferente de `claude` com "este agente não confirmou um comando nativo de compactação" (`compaction_controller.dart`).

Com o Codex nas Sessões e no Prompt (SPEC-096), o painel fica quase vazio. O adaptador atual também não ajuda:

- calcula o uso como `total − total do início do turno` (`codex_provider.dart`), que é o acumulado do turno, não o tamanho do contexto da última chamada. Exatamente a confusão que a SPEC-087 R1 proibiu;
- ignora `modelContextWindow`, os itens `contextCompaction` e o `thread/compact/start`, todos já disponíveis no App Server 0.170.

Exemplo: numa sessão Codex longa, depois de 30 comandos e leituras, o medidor fica em "Aguardando medição", ou mostra um número que cresce a cada turno sem nunca cair. O Codex compacta sozinho, e a timeline não registra nada. A pessoa clica em "Compactar agora" e lê que o agente "não confirmou um comando nativo", embora o Codex tenha um.

Esta spec liga o contrato da SPEC-087 aos dados do Codex. Ela não muda o comportamento no Claude.

## Requisitos

### Medição

- R1 · **Uma leitura por chamada, vinda do `last`.** Cada `thread/tokenUsage/updated` da thread principal vira uma `ContextReading`. A base é o `tokenUsage.last` (a última chamada), nunca o `total` nem a diferença entre totais. A fórmula de tokens no contexto (entrada nova, leitura de cache e escrita de cache, sem somar o que se sobrepõe) é a que a SPEC-093 registrar para o 0.170. Saída e raciocínio (`outputTokens`, `reasoningOutputTokens`) não entram. A leitura nova substitui a anterior.
- R2 · **Capacidade do agente.** `modelContextWindow` da mesma notificação é a capacidade. Sem esse campo, o medidor mostra o total sem porcentagem (SPEC-087 R2). O app nunca deduz a janela pelo nome do modelo.
- R3 · **Composição só quando medida.** O painel Uso mostra "entrada nova · leitura de cache · escrita de cache" quando as três partes vêm do `last` sem sobreposição. Se não vierem, mostra o total com "Detalhamento indisponível". O Codex não tem um equivalente do `get_context_usage`, então as categorias (prompt de sistema, ferramentas, skills) ficam fora do gráfico no Codex.
- R4 · **Turno, hora e reabertura.** Cada leitura guarda o `turnId`, o número do turno e a hora. As regras da SPEC-087 R3 valem iguais: "medido no fim do turno N" depois do `turn/completed`; ao reabrir, "última medição às HH:mm", nunca como leitura ao vivo.
- R5 · **Eventos neutros e gravados.** O adaptador emite as leituras e os marcadores como os eventos neutros de uso e compactação da SPEC-095, com `provider: codex`. Eles ficam gravados com os eventos da sessão ou da conversa, e o Replay e a Evolução usam esses registros. Eventos Codex antigos, gravados antes desta spec, mostram "Aguardando medição" e não inventam histórico.

### Compactação

- R6 · **Limiar enviado e visível.** A compactação automática do Codex usa o `model_auto_compact_token_limit` enviado por execução, como o adaptador já faz a partir da preferência, e o painel mostra esse valor: "Auto compactar: em 300 mil (enviado ao Codex)". Sem valor enviado, mostra "padrão do agente". Se o `config/read` da sessão devolver o limite efetivo, ele aparece no lugar do enviado. A preferência é **por provedor** (P1): mudar a do Codex não mexe na do Claude, e vice-versa. O que vale para a execução atual ou para as próximas segue a SPEC-087 R7.
- R7 · **Estados pelos itens do protocolo.** Um item `contextCompaction` em `item/started` vira "compactando"; em `item/completed`, "concluída", com o marcador na Evolução. Um erro do turno durante a compactação vira "falhou". A notificação antiga `thread/compacted` (obsoleta no 0.170) só serve de reserva, e o marcador é registrado uma vez por item ou turno, mesmo com repetição ou sessão reaberta (SPEC-087 R8). Depois de compactar, a leitura corrente fica "Contexto compactado · aguardando medição" até o próximo `tokenUsage`.
- R8 · **"Compactar agora" no Codex.** O botão fica disponível no Codex quando a capacidade `compactNow` (SPEC-094) é verdadeira, há ao menos uma leitura e a thread está ociosa. A ação chama `thread/compact/start` uma vez, com as mesmas regras da SPEC-087 R9: um pedido por vez, falha que não apaga o histórico, nada de prompt "resuma". O `compactAvailability` passa a decidir pela capacidade, e não mais por `provider == 'claude'`.
- R9 · **Foco do resumo.** O `thread/compact/start` não recebe foco. No Codex, o campo "foco" do Compactar agora some, com a nota "o Codex não aceita foco na compactação". O `compact_prompt` da configuração troca o prompt inteiro de compactação e não é usado como foco (P3).

### Fontes e contextos separados

- R10 · **Instruções carregadas, com prova.** Os `instructionSources` do `thread/start`/`thread/resume` (os arquivos de instrução que o Codex carregou: `AGENTS.md`, `CLAUDE.md` via SPEC-104) entram na aba Fontes como "carregamento informado pelo agente". Skills e MCP disponíveis aparecem como configuração, não como carregados (SPEC-087 R4).
- R11 · **Leituras observadas pelos comandos.** No Codex os arquivos são lidos por comandos. Um item `commandExecution` com `commandActions` do tipo `read`, `search` ou `listFiles` vira "leitura observada (comando)", com o caminho e um link para o item na timeline. `unknown` não vira leitura. Chamadas `mcpToolCall` aparecem no grupo Ferramentas/MCP. Nada disso tem peso em tokens: "peso indisponível".
- R12 · **Subagentes e troca de modelo.** Notificações de outras threads (`collabAgentToolCall`, `subAgentActivity`, `tokenUsage` com outro `threadId`) nunca entram na leitura principal e aparecem como "contexto separado · medição indisponível" (SPEC-087 R11). `model/rerouted` e uma troca de modelo em `thread/settings/updated` viram marcadores de troca de modelo e invalidam a capacidade. O redirecionamento feito pelo serviço é dito como tal: "modelo redirecionado pelo serviço".
- R13 · **Mesmas telas, mesmos avisos.** Prompt, Sessões, cada lado de Comparar e Replay mostram o Codex com os mesmos componentes da SPEC-087, incluindo o aviso em 85% do limiar (ou da capacidade), rearmado abaixo de 75%. A continuação de etapas por limiar de contexto (SPEC-017 R4), quando a execução de spec rodar no Codex (SPEC-101), usa estas mesmas leituras.

## Fora do escopo

- Mudar qualquer comportamento do Claude Code na SPEC-087.
- Detalhar o contexto do Codex por categorias (não há fonte no protocolo).
- Escopo do limiar (`model_auto_compact_token_limit_scope`) na interface. Ver P2.
- Agendar compactações pelo app ou compactar sozinho ao passar de um percentual.
- Restaurar a conversa (`thread/revert`): SPEC-110.
- Cota do plano do Codex: SPEC-097.

## Decisões em aberto

- P1 · **Preferência de limiar por provedor.** (a) Uma preferência para cada provedor (`codex.autocompact`, começando em "padrão do agente"); (b) a mesma do Claude (hoje 200 mil). **Recomendação: (a).** As janelas e o comportamento são diferentes: o Claude compacta em `janela − 33 mil` (SPEC-087, sonda), e reaproveitar os 200 mil no Codex seria um número sem base.
- P2 · **Escopo do limiar.** (a) Não expor e enviar só o limite; (b) expor "total" ou "corpo depois do prefixo". **Recomendação: (a).** Se o `config/read` informar o escopo, ele aparece como texto no painel, sem controle.
- P3 · **Foco no Compactar agora.** (a) Esconder no Codex; (b) mandar o foco como `compact_prompt` só daquela compactação. **Recomendação: (a).** O `compact_prompt` substitui o prompt inteiro de compactação do Codex, e um foco mal escrito pode piorar o resumo.
- P4 · **Leituras por comando.** (a) Usar só `commandActions` com tipo conhecido; (b) também interpretar o texto do comando (`cat`, `sed -n`, `rg`). **Recomendação: (a).** O texto do comando é frágil, e o protocolo já classifica as ações.
- P5 · **Leitura no meio do turno.** O Codex pode mandar várias `tokenUsage` por turno. (a) Mostrar todas na Evolução; (b) só a última de cada turno. **Recomendação: (b) no gráfico e (a) no detalhe do turno**, como a SPEC-087 faz com as várias chamadas do Claude.

## Design

### Arquivos tocados

- `lib/core/codex/codex_provider.dart`: usar o `last`, ler `modelContextWindow`, emitir leituras e marcadores neutros, tratar `contextCompaction`, `thread/compacted`, `model/rerouted` e `thread/settings/updated`, guardar `instructionSources` e chamar `thread/compact/start`.
- `lib/features/context/context_tracker.dart`: redutor dos eventos neutros (SPEC-095), além dos eventos do Claude; isolar threads de subagentes.
- `lib/features/context/context_snapshot.dart`: origem da leitura (`provider`, `source`) e a composição do Codex.
- `lib/features/context/compaction_controller.dart`: disponibilidade pela capacidade `compactNow`; envio por `thread/compact/start` no Codex; sem foco no Codex.
- `lib/features/context/context_sources.dart`: `instructionSources`, `commandActions` e `mcpToolCall`.
- Widgets do painel Contexto e do medidor (`lib/features/context/`, `prompt_side_panel.dart`, Sessões e Comparar): textos por provedor ("enviado ao Codex", "redirecionado pelo serviço").
- `lib/core/claude/run_prefs.dart`, `lib/features/settings/settings_screen.dart`: preferência de limiar do Codex (P1).

### Migração

Não há. As leituras e os marcadores são eventos gravados com a sessão ou a conversa (SPEC-095), e a preferência fica em `app_settings`.

### Dependências

- **SPEC-087 · Contexto visual e compactação** (main): o contrato, o redutor, o painel e as regras que esta spec estende.
- **SPEC-093 · Sondagem do Codex 0.170**: a fórmula do `last` (o que se sobrepõe entre `inputTokens` e `cachedInputTokens`), quantas `tokenUsage` chegam por turno, o `contextCompaction` em compactação automática e manual, o `thread/compact/start` no modo do app, o `config/read` com o limite efetivo e os `instructionSources`.
- **SPEC-094 · Capacidades e opções por provedor**: capacidade `compactNow` e preferências por provedor.
- **SPEC-095 · Eventos neutros**: os tipos de leitura e de compactação.
- **SPEC-096 · Codex no Prompt e nas Sessões**: as execuções em que o painel aparece.
- Relacionadas: SPEC-101 (continuação de etapas) e SPEC-104 (instruções carregadas).

## Tarefas

- T1 · Adaptador: leituras pelo `last`, capacidade, marcadores, `instructionSources`, `commandActions`, eventos neutros. Testes com *fixtures* da SPEC-093 e repetição de eventos.
- T2 · Redutor e snapshot: eventos neutros, isolamento de threads, invalidação por compactação e por troca de modelo. Testes de unidade.
- T3 · Compactação: preferência por provedor, limiar visível, "Compactar agora" pela capacidade, sem foco. Testes do controlador e de widget.
- T4 · Fontes, Comparar e Replay no Codex, e um teste manual com o app isolado: conversa longa, compactação automática e manual, reabertura.

## Critérios de aceite

- [ ] Leituras repetidas e turnos longos não acumulam: o medidor acompanha o `last`, e uma compactação faz o valor cair [R1, R7] verificar: testes do redutor com `tokenUsage` gravadas e teste manual.
- [ ] Sem `modelContextWindow`, o medidor mostra o total sem porcentagem [R2] verificar: teste de widget do medidor.
- [ ] A composição só aparece quando as partes não se sobrepõem; sem isso, "Detalhamento indisponível" [R3] verificar: testes do snapshot.
- [ ] Reabrir uma sessão Codex mostra a última leitura como histórica, e eventos antigos sem leitura não inventam histórico [R4, R5] verificar: teste com eventos gravados reabertos.
- [ ] O painel mostra o limiar enviado ao Codex, e a preferência do Codex não mexe na do Claude [R6] verificar: argumentos do `thread/start` e teste das preferências.
- [ ] `contextCompaction` gera "compactando" e "concluída" uma vez por item, e a leitura fica pendente até a próxima medição [R7] verificar: teste com itens repetidos e `thread/compacted` duplicado.
- [ ] "Compactar agora" chama `thread/compact/start` uma vez, só com a thread ociosa e a capacidade ligada, e não mostra o campo de foco [R8, R9] verificar: testes do controlador com o `fake_codex`.
- [ ] Fontes mostram as instruções carregadas, as leituras por `commandActions` e as chamadas MCP, todas com "peso indisponível" [R10, R11] verificar: teste das fontes com itens gravados.
- [ ] Subagentes não entram na leitura principal, e `model/rerouted` gera o marcador e invalida a capacidade [R12] verificar: testes do redutor.
- [ ] Comparar com um lado Codex mostra o medidor daquele lado, sem somar, e o Replay usa a leitura do ponto selecionado [R13] verificar: testes de widget e teste manual.

## Telas

Mockup: [canvas do Claude Design](https://claude.ai/artifact/QNKYhFPuR54B1ajkqtm1ZN). PNGs em `docs/mockups/spec-107/`. Os números e os nomes de modelo são exemplos coerentes entre si: janela de 400 mil, compactação automática em 300 mil, 241 mil medidos no fim do turno 18 e compactação no turno 11 (288 mil → 52 mil). No app, tudo vem da execução.

| PNG | O que mostra | Requisitos |
|---|---|---|
| `1-sessao-codex.png` | Sessão Codex com o medidor ("241 mil / 400 mil · 60% · compacta em 300 mil, faltam 59 mil · medido no fim do turno 18"), o marcador "Contexto compactado (automático)" na timeline e "Compactar agora" disponível | R1, R2, R4, R7, R8 |
| `2-painel-uso.png` | Painel Contexto, aba Uso, no Codex: composição medida pelo `last`, "Auto compactar: em 300 mil (enviado ao Codex)" com preferência própria do Codex, Evolução com compactação e o marcador "modelo redirecionado pelo serviço" | R3, R6, R7, R12 |
| `3-fontes-e-compactar.png` | Aba Fontes no Codex (instruções carregadas pelos `instructionSources`, leituras observadas por comando, MCP, subagente com "contexto separado") e o diálogo Compactar agora sem o campo de foco | R9–R12 |
