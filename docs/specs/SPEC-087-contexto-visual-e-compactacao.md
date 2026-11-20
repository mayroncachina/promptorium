---
id: SPEC-087
status: aprovada
versão: 0.22.0
tipo: melhoria
issue: 324
depende-de: []
---

# Contexto visual e compactação automática

## Objetivo

Mostrar quanto da janela de contexto de cada conversa está ocupado, o que o app consegue observar da sua composição e quando ela vai compactar. A pessoa precisa entender o crescimento e tomar uma ação antes de perder o fio do trabalho.

Hoje existem três números diferentes: o consumo acumulado da conversa, a cota do plano e o contexto da última chamada. O painel Contexto do Prompt mostra `tokensIn + tokensOut` da conversa, que é acumulado; as sessões já calculam uma medida de contexto por chamada; o Replay mostra medidas históricas. A compactação automática já é configurável, com padrão de 200 mil tokens, mas essa configuração fica distante da conversa.

Esta spec junta **Uso**, **Fontes** e **Compactação** no mesmo painel. O total medido vem do agente. A lista de fontes mostra evidências observadas pelo app; não afirma que um arquivo foi usado no raciocínio nem que continua inteiro na janela depois de compactar.

Exemplo ilustrativo, com números que devem vir da execução real:

> Contexto: 182 mil / 1 milhão · 18% ocupado
>
> Compactação automática: em 200 mil · faltam 18 mil tokens
>
> Última medição: fim do turno 12

## Requisitos

### Medição e gráfico

- R1 · **Uma medição por execução.** Reunir em um contrato único o tamanho atual, o limite da janela, o modelo, a hora, a origem da informação e o estado da compactação. O contexto observado substitui a medição anterior: não é a soma dos turnos. A conta de entrada inclui tokens novos, escrita e leitura de cache; a fórmula usada precisa corresponder à fonte documentada e verificada na versão instalada. Saída e reserva de resposta só entram quando o contrato do agente as informa com essa semântica. Cota semanal, custo e consumo acumulado continuam separados.
- R2 · **Barra de ocupação.** No Prompt e nas Sessões, um indicador compacto abre o painel Contexto, com total usado, limite e espaço restante. A barra mostra ocupado e livre. Categorias do agente podem subdividir o ocupado quando forem medidas compatíveis, sem sobreposição. Sem composição confiável, mostrar o total com “Detalhamento indisponível”, sem inventar fatias. Sem limite, mostrar o total sem porcentagem; sem medição, mostrar “Aguardando medição”, nunca 0%. O indicador não ocupa os cards do Quadro.
- R3 · **Número atual, com hora.** Informar “medido no turno N” ou “última medição às HH:mm”. Enquanto o agente trabalha, manter a última leitura identificada. Ao compactar, invalidar o valor corrente; até a próxima leitura, mostrar “Contexto compactado · aguardando medição” e o valor anterior apenas no histórico. Ao trocar o modelo, invalidar limites incompatíveis. Exibir leitura antiga identificada ao reabrir uma sessão, sem apresentá-la como medição ao vivo.

### O que entrou no contexto

- R4 · **Fontes com evidência.** A aba Fontes agrupa instruções e memória, spec e mensagens enviadas pelo app, arquivos citados ou lidos, anexos e ferramentas/MCP. Cada item informa a evidência e o estado: “enviado neste turno”, “leitura observada”, “carregamento informado pelo agente” ou “referência no histórico”. Uma configuração disponível não prova que foi carregada. Após compactar, fontes sem confirmação de permanência ficam identificadas como históricas. Exibir somente caminho/nome e metadados necessários; não copiar conteúdo de arquivos nem valores secretos para esse painel.
- R5 · **Detalhe sem falsa precisão.** Clicar em uma fonte abre o arquivo ou o evento que a originou. Tokens por fonte só aparecem como medição quando informados pelo agente; estimativas devem mostrar “≈”, método e escopo, separados do gráfico medido. Tamanho em bytes e número de linhas não viram tokens exatos. Categorias sobrepostas não são somadas. O painel pode listar uma fonte sem saber seu peso, dizendo “peso indisponível”. Anexos ainda não enviados ficam em “Próximo envio” e não aumentam o contexto medido.
- R6 · **Evolução por turno.** Um gráfico pequeno mostra as leituras de contexto ao longo da sessão, com marcadores de compactação e troca de modelo. Selecionar um ponto mostra sua medição e leva ao turno no histórico. Só comparar antes/depois quando houver duas leituras válidas da mesma execução; sem a leitura posterior, dizer “aguardando medição”. O Replay usa a leitura do ponto selecionado, nunca o estado atual da sessão. Não interpolar medições inexistentes como fatos.

### Compactar e continuar

- R7 · **Compactação automática visível e configurável.** Mostrar no painel o valor efetivamente enviado àquela execução: por exemplo, “Auto compactar: em 200 mil tokens” ou “padrão do agente”. Reaproveitar `RunPrefs.autocompact`, as opções existentes e `--autocompact`; não criar um segundo agendador que compita com o CLI. Manter preferências existentes. Quando o limiar for conhecido, marcá-lo na barra e mostrar quanto falta até ele, distinguindo-o da capacidade total da janela. A configuração global é editável pelo painel. Só afirmar que mudou na sessão atual se o protocolo confirmar aplicação em tempo de execução; caso contrário, informar “vale para as próximas execuções”, mantendo visível o valor efetivo da atual. Não reiniciar uma sessão viva para aplicar a alteração.
- R8 · **Acompanhar a compactação.** Representar “configurada”, “compactando”, “concluída”, “falhou” e “não informado”, conforme os eventos disponíveis. Registrar o marcador uma vez, mesmo com eventos repetidos ou sessão reaberta. O app não cria uma mensagem de resumo por turno nem pede ao modelo que compacte em laço. Sem evento de início, não simular o estado “compactando”. A configuração deve valer nos fluxos que já passam `autocompact`: Sessões, Prompt/VIBE, Comparar e chamadas somente leitura, respeitando as capacidades de cada agente.
- R9 · **Ações práticas.** Oferecer “Ajustar compactação automática”, “Revisar próximos anexos” e “Nova conversa”. “Compactar agora” só fica disponível depois de confirmar suporte no modo de execução usado pelo app e com o agente ocioso; sem suporte, explicar o motivo. A ação preserva as configurações de acesso e usa o comando nativo, com um pedido por vez. Um foco para o resumo pode ser informado quando o protocolo o aceitar. Falha mantém a conversa utilizável e não apaga seu histórico. Revisar/remover um anexo pendente afeta só o próximo envio; não promete remover material já lido. Nova conversa deixa explícito se começa vazia ou recebe um resumo e permite revisá-lo antes do envio. Compactar não restaura cota do plano nem garante preservar cada detalhe.
- R10 · **Avisar com uma ação.** Mostrar um aviso local quando a leitura atingir 85% do limiar configurado, se conhecido; caso contrário, 85% da capacidade conhecida, com texto que identifique qual limite se aproxima. Mostrar o motivo e oferecer o painel. Não bloquear o envio nem compactar por conta própria. Uma ocorrência por cruzamento, com histerese: rearmar após nova leitura abaixo de 75% da mesma referência ou após compactação confirmada. Mudança de referência reinicia a avaliação. Fonte ou limite indisponível não gera alarme. Sugestões sobre anexos grandes, instruções extensas e ferramentas só aparecem quando houver evidência identificável e apontam ao item correspondente, sem promessa numérica de economia.

### Mesma informação em todas as telas

- R11 · **Contextos separados.** Sessão, conversa e cada lado de Comparar têm suas próprias leituras, modelo, limite e limiar de compactação. Não somar porcentagens entre lados nem somar a janela dos subagentes à principal. Exibir dados de um subagente somente quando houver identidade e medição próprias; caso contrário, dizer “contexto separado · medição indisponível”. O painel do Prompt passa a chamar o número acumulado de “Tokens acumulados”, fora do medidor atual.
- R12 · **Acessibilidade e atualização leve.** Barra e gráfico têm resumo em texto, valores e estados que independem de cor. A lista de fontes e os pontos do gráfico funcionam pelo teclado. Atualizar por eventos, sem requisições ao modelo por quadro ou por tecla. Consultas de diagnóstico explícitas precisam indicar qualquer custo conhecido antes de executar; não usar um novo turno faturável só para atualizar o indicador. Falha no diagnóstico não interrompe a execução. Histórico grande usa carregamento limitado e lista virtualizada; não reprocessar toda a sessão a cada delta de texto.

## Fora do escopo

- Medir atenção interna do modelo ou afirmar quais arquivos causaram uma resposta.
- Mostrar como exato um mapa completo do contexto que o agente não expõe.
- Apagar seletivamente tokens de chamadas passadas, remover mensagens do histórico ou desativar proteções do CLI.
- Compactar sessões por um processo paralelo ou encerrar tarefas para caber em uma porcentagem.
- Mudar a cota/custo por spec da SPEC-081, o limiar de continuação de etapas da SPEC-017 ou o comportamento dos pontos de restauração da SPEC-084.
- Implementar novos provedores ou reativar a integração Codex adiada.
- Um grafo navegável de dependências entre todos os arquivos do projeto. Esta entrega mostra a composição observável da execução.

## Decisões

- P1 · **Gráfico e fontes juntos.** A proposta combina o medidor de ocupação com uma lista agrupada de fontes. O medidor é a entrada; Fontes e Evolução ficam no painel, sem transformar a conversa num dashboard permanente.
- P2 · **Automático primeiro.** A compactação fica a cargo do agente e usa a configuração já existente. “Compactar agora” depende da sondagem do protocolo; não será implementado como um prompt comum que diz “resuma”.
- P3 · **Preservar a preferência atual.** A instalação existente mantém sua escolha, inclusive o padrão atual de 200 mil tokens. Não adotar um percentual fixo nem fixar capacidade por nome de modelo sem evidência da execução.
- P4 · **Sem números inventados.** O gráfico usa dados medidos; a lista pode mostrar fontes observadas sem tamanho conhecido. A interface distingue medição, estimativa, dado antigo e dado ausente.
- P5 · **Versão e visual.** 0.22.0. O mockup em [Telas](#telas) foi validado e aprovado em 20/11/2026, junto com as decisões P1–P4.

## Telas

Mockup: [canvas do Claude Design](https://claude.ai/artifact/NTFEEHXmwEsxiSgE24i5P3). Capturas em `docs/mockups/spec-087/`, com números de exemplo coerentes entre si: janela de 1 milhão, compactação automática em 200 mil, 182 mil medidos no fim do turno 12, compactação no turno 7 (171 mil → 46 mil) e troca de modelo no turno 9.

| PNG | O que mostra | Requisitos |
|---|---|---|
| `1-prompt-medidor.png` | Prompt com o medidor compacto acima do composer (“182 mil / 1 milhão · 18% · compacta em 200 mil, faltam 18 mil · medido no turno 12”), em âmbar por ter passado de 85% do limiar. O painel lateral troca “Tokens” por “Tokens acumulados”, separado do medidor | R2, R3, R7, R11 |
| `2-painel-uso.png` | Painel Contexto, aba Uso: barra ocupado/livre com o limiar de 200 mil tracejado e distinto da capacidade, resumo em texto, composição medida (entrada, escrita e leitura de cache), “Auto compactar” editável com “vale para as próximas execuções” e o gráfico Evolução com os marcadores de compactação e troca de modelo e o ponto selecionado | R1–R3, R6, R7, R12 |
| `3-painel-fontes.png` | Aba Fontes: grupos instruções e memória, spec e mensagens do app, arquivos lidos ou citados, anexos e MCP; cada item com a evidência, “peso indisponível” ou “≈ estimado”, itens históricos após a compactação, foco pelo teclado e a seção “Próximo envio” com os anexos pendentes | R4, R5, R12 |
| `4-compactacao.png` | Aviso aos 85% do limiar com ação, estados “compactando”, “concluída”, “Contexto compactado · aguardando medição”, “falhou” e “não informado”; ações Ajustar compactação, Revisar próximos anexos e Nova conversa (vazia ou com resumo) e “Compactar agora” desabilitado com o motivo | R3, R8–R10 |
| `5-estados.png` | Estados especiais: “Aguardando medição” nas Sessões e leitura antiga ao reabrir, limite desconhecido (total sem %), “Detalhamento indisponível” e Comparar com dois lados, cada um com o seu medidor, sem somar, e o subagente com “contexto separado · medição indisponível” | R2, R3, R5, R11 |

## Design

### O que já existe

- `lib/features/sessions/session_manager.dart`: `contextTokens`, cálculo na mensagem `AssistantMessage` e identidade da execução.
- `lib/features/sessions/timeline.dart`: amostras em `Timeline.contextTokens` e evento `system/compact_boundary` com a mensagem “Contexto compactado”.
- `lib/features/prompt/widgets/prompt_side_panel.dart`: seção Contexto, tokens acumulados e lista de arquivos citados.
- `lib/features/prompt/conversation_manager.dart` e `compare/compare_controller.dart`: fluxos do Prompt, VIBE e comparações.
- `lib/features/sessions/replay/`: medição histórica e posição no turno (SPEC-082).
- `lib/core/claude/run_prefs.dart`, `claude_args.dart` e `lib/features/settings/settings_screen.dart`: opções globais de compactação e geração de `--autocompact`.
- `lib/features/board/spec_runner.dart`: regra de continuar etapas conforme contexto (SPEC-017); o limiar dessa regra é diferente do limiar de compactação.
- `lib/features/cost/`: ledger de consumo acumulado por spec (SPEC-081), mantido separado deste medidor.

### Sondagem obrigatória antes de implementar

Registrar em `docs/pesquisa/contexto-e-compactacao.md` a versão do CLI, comandos, payloads sanitizados e resultado de cada cenário: primeira resposta, leitura de arquivo, cache, troca de modelo, compactação automática, retomada e dois forks. Confirmar as diferenças entre o modo interativo, `--print` com `stream-json` e a integração de status line.

A documentação oficial apresenta dados para status line e diagnóstico por `/context`, mas isso não prova que os mesmos campos e comandos chegam ao transporte usado pelo Promptorium. Primeiro verificar `modelUsage`/metadados e eventos disponíveis; uma ponte local de status line só entra após validar que funciona nesse modo e preserva a configuração da pessoa. Não sobrescrever `~/.claude/settings.json` nem executar dois escritores no mesmo arquivo.

Se o total for conhecido e a capacidade não, entregar o total sem porcentagem. Se o diagnóstico detalhado não estiver acessível, entregar Fontes com as evidências do app e manter pesos indisponíveis. Se o comando manual não for suportado, a compactação automática permanece como caminho funcional e a ação manual explica a limitação. Não usar dados simulados para declarar suporte real.

### Componentes propostos

- `ContextSnapshot`: execução, modelo, tokens atuais, capacidade, limiar efetivo de compactação, hora/turno, fonte e qualidade da informação; composição opcional.
- `ContextSource`: categoria, referência local, evidência, estado após compactação e peso opcional com método de medição/estimativa.
- `ContextTracker`: reduz eventos em ordem, isola execuções, invalida dados após compactação/troca e controla deduplicação e avisos.
- `ContextIndicator` e `ContextPanel`: seções Uso, Fontes e Evolução, com ações de compactação e preparação do próximo envio.
- `CompactionController`: acompanha o estado nativo e envia um comando manual somente quando a capacidade tiver sido comprovada. Não decide automaticamente por conta própria quando compactar.

### Persistência

Preferir reconstruir leituras dos eventos já persistidos de sessão e conversa. Metadados adicionais podem usar um evento do app com JSON versionado, sem copiar conteúdo de fontes. As preferências continuam em `app_settings`. Não presumir migração de banco; caso a sondagem demonstre necessidade de índice/tabela, documentar antes de definir o esquema. Retomada não transforma amostra antiga em atual.

### Etapas propostas

- T1 · Sondagem, contrato e redutor: arquivos em `lib/core/claude/`, `lib/core/providers/` e novo módulo `lib/features/context/`. Verificar com eventos gravados e amostras do CLI instalado.
- T2 · Indicador e painel no Prompt/Sessões; separar acumulado de atual. Verificar estados sem dados, fonte parcial, modelo novo e navegação por teclado.
- T3 · Configuração e acompanhamento da compactação, avisos e ações. Verificar limiar efetivo da sessão, mudança para próximas execuções, falha e eventos duplicados.
- T4 · Comparar, Replay e retomada. Verificar isolamento dos lados, compactação na evolução histórica e reabertura com amostra antiga.

## Critérios de aceite

- [x] A sondagem registra os recursos efetivamente disponíveis no CLI instalado e suas limitações no modo usado pelo app [R1, R7–R9] verificar: relatório técnico com payloads sanitizados.
- [x] Turnos repetidos e leituras de cache não acumulam o tamanho da janela; limite ausente não produz uma porcentagem inventada [R1–R3] verificar: testes do redutor e do indicador.
- [x] Tokens acumulados, cota do plano e contexto atual têm rótulos e cálculos distintos [R1, R11] verificar: testes de widgets do Prompt e das Sessões.
- [x] Fontes mostram evidência, anexos pendentes ficam separados e itens históricos após compactação não são apresentados como certamente presentes [R4, R5] verificar: testes com envio, leitura e compactação.
- [x] O gráfico histórico usa medições reais e leva ao turno correto; não reaproveita a leitura atual no Replay [R6] verificar: testes do painel e do Replay.
- [ ] A compactação automática usa o valor efetivo da execução, preserva preferências existentes e distingue seu limiar da capacidade da janela [R7] verificar: argumentos do CLI e teste manual.
- [x] Acompanhamento e retomada não duplicam compactações; a leitura corrente fica pendente até chegar uma nova medição [R3, R8] verificar: eventos gravados com duplicação e reabertura.
- [ ] Compactar agora só executa com suporte comprovado, uma vez e com a execução ociosa; falha não apaga o histórico [R9] verificar: testes do controlador e cenário manual quando suportado.
- [x] Os avisos respeitam 85%/75%, identificam a referência usada e não acionam com dados ausentes; retirar anexo afeta só o próximo envio [R9, R10] verificar: testes do redutor e da preparação do envio.
- [x] Lados de Comparar e contextos de subagentes não são somados ao principal [R11] verificar: testes de isolamento.
- [x] Teclado, texto alternativo e atualização por eventos funcionam sem chamadas faturáveis para atualizar o gráfico [R12] verificar: testes de widgets e inspeção dos pedidos ao agente.
- [ ] No app isolado, acompanhar uma conversa longa, compactar automaticamente e conferir antes/depois, fontes, retomada e Comparar [R1–R12] verificar: capturas reais e relatório manual; pendente de execução com cota disponível.

## Fontes técnicas

Consultadas em 17/11/2026; descrevem o CLI e não garantem por si só a disponibilidade dos dados no transporte do app.

- [Status line: capacidade, medição atual, campos opcionais e fórmula de ocupação](https://code.claude.com/docs/en/statusline#context-window-fields).
- [Janela de contexto: composição, diagnóstico e compactação](https://code.claude.com/docs/en/context-window).
- [SPEC-017: consumo e continuação de etapas](SPEC-017-consumo-de-tokens-nas-etapas.md), [SPEC-081: consumo por spec](SPEC-081-custo-por-spec.md) e [SPEC-082: Replay](SPEC-082-replay-da-sessao.md).
