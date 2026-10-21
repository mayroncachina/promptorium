---
id: SPEC-006
status: concluida
depende-de: [SPEC-003]
---

# Seleção de provedor pelo indicador de conexão do rodapé

## Objetivo

Transformar o indicador “Claude Code CLI conectado”, no rodapé do app, em um seletor de provedor. Ao clicar nesse ponto, o usuário deve encontrar Claude Code, Codex e os agentes ACP configurados e escolher qual será usado nas próximas execuções. Hoje o indicador é apenas informativo e a seleção disponível no Prompt não fica evidente para quem procura trocar o CLI pelo rodapé.

Esta spec complementa a SPEC-003 com o ponto de entrada solicitado na interface. A cobertura dos fluxos continua definida na SPEC-005.

## Requisitos

- R1 · Clicar no indicador de CLI do rodapé deve abrir a lista de provedores registrados, incluindo Claude Code, Codex e os agentes ACP configurados. O controle deve indicar que abre um menu e funcionar também quando o CLI selecionado estiver indisponível.
- R2 · A lista deve marcar o provedor selecionado e apresentar a disponibilidade de cada opção. Provedores sem executável, sem autenticação ou incompatíveis devem ter diagnóstico e acesso às orientações de configuração; não devem aparecer como conectados nem poder iniciar execuções.
- R3 · Selecionar um provedor disponível deve atualizar imediatamente o indicador e persistir o padrão do projeto ativo; sem projeto ativo, deve atualizar o padrão global. O menu deve informar esse escopo antes da seleção e usar a precedência da SPEC-003 ao alternar projetos ou reiniciar o app.
- R4 · Novas conversas, sessões, execuções de specs e ações auxiliares devem receber o padrão selecionado, respeitando escolhas explícitas em seus formulários. Trocar pelo rodapé não deve modificar conversas, sessões ou execuções existentes, inclusive as pausadas ou aguardando aprovação. O menu deve informar “Aplicar às novas execuções”.
- R5 · O rodapé deve mostrar o nome e o estado reais do provedor selecionado, por exemplo “Codex CLI conectado”. Trocar para Codex deve atualizar as opções dos formulários novos para esse provedor e impedir que modelos, esforços ou métricas de uso Claude sejam apresentados como dados Codex. Quando uma métrica não estiver disponível, deve aparecer como indisponível.
- R6 · O seletor deve permitir abertura, navegação, seleção e fechamento por teclado, apresentar foco visível e manter o rodapé utilizável em janelas estreitas. Fechar o menu sem escolher uma opção não deve alterar a preferência.

## Design

O ponto de entrada é o primeiro grupo de `lib/ui/shell/status_footer.dart`, atualmente um ponto de estado seguido de um `Text` com a chave `footer-cli`. Substituir esse grupo por um controle de menu com nome, ponto de estado e indicador de expansão, preservando a identificação usada pelos testes quando possível.

Usar `agentProvidersProvider` como fonte da lista e o resolvedor de preferências da SPEC-003 como fonte da seleção. Não manter uma segunda preferência exclusiva do rodapé. O seletor do Prompt e os demais formulários devem observar o mesmo padrão ao criar uma execução; escolhas explícitas permanecem prioritárias.

Separar disponibilidade de seleção: `AgentProvider.enabled` sozinho não comprova instalação, autenticação ou compatibilidade. Consumir os diagnósticos independentes previstos na SPEC-002 e permitir consultar a correção de uma opção indisponível. Abrir o menu não deve iniciar processos de execução nem solicitar login automaticamente.

Adaptar `lib/ui/shell/footer_stats.dart` para identificar o provedor associado ao estado e às métricas exibidas. Durante uma sondagem, mostrar estado de verificação; descartar respostas atrasadas de outro provedor após uma troca. Uma sessão Claude ainda em execução continua vinculada ao Claude mesmo quando o rodapé passa a indicar Codex como padrão para novas execuções.

Reutilizar os controles de menu e estilos existentes. Manter a altura atual do rodapé, tooltip “Selecionar provedor” e rótulo acessível com nome, estado e escopo da escolha.

## Implementação

- O indicador do rodapé abre um menu com os provedores registrados, estado, seleção atual e escopo. O menu usa os controles nativos de foco, teclado e fechamento com Escape.
- O resolvedor compartilhado está em `lib/core/providers/provider_preferences.dart`: uma escolha explícita ou o vínculo salvo da execução prevalece sobre o padrão do projeto, que prevalece sobre o global e o padrão legado Claude. Preferências do projeto ficam no banco local por ID de workspace, sem modificar arquivos do repositório.
- `provider_availability.dart` verifica versão, interface e estado de login sem iniciar conversas ou autenticar automaticamente. O Codex ausente é um diagnóstico normal e não gera tentativas automáticas intermináveis. A ausência de Claude também não bloqueia mais a abertura do app.
- Prompt, novas sessões, execução de specs e o executor compartilhado de ações auxiliares recebem o provedor resolvido. Retomadas usam a identidade salva; mudar o padrão não transfere uma execução existente. Configurações sem equivalente validado continuam bloqueadas, conforme a SPEC-004, sem fallback para Claude.
- O rodapé identifica o provedor e apresenta consumo indisponível para provedores sem métricas integradas, sem reaproveitar os limites Claude.

### Limites da verificação ACP

ACP não define um comando universal de diagnóstico de login para os executáveis configurados. Por isso, sua sondagem confirma o executável e a resposta de versão e exibe “disponível · login verificado ao iniciar”, sem afirmar que está conectado. O adaptador valida autenticação/protocolo ao iniciar e informa falhas, sem substituir o provedor. Claude e Codex têm diagnósticos de login independentes antes da seleção.

Testes específicos: `test/core/provider_selection_test.dart`, `test/core/provider_auxiliary_test.dart`, `test/ui/provider_footer_test.dart` e os cenários Codex de `test/features/sessions/codex_session_test.dart`.

## Critérios de aceite

- [x] [R1] Clicar em “Claude Code CLI conectado” abre um menu com Claude Code, Codex e ACP configurados; o mesmo menu abre quando o provedor atual não é encontrado.
- [x] [R2] Fixtures de CLI ausente, login pendente e versão incompatível mostram diagnósticos distintos e orientação; nenhuma delas é apresentada como conectada ou inicia outro provedor silenciosamente.
- [x] [R3] Selecionar Codex atualiza o rodapé; reabrir o app preserva a escolha. Alterar o padrão de um projeto não muda outro projeto; sem projeto, a alteração fica no padrão global indicado no menu.
- [x] [R4] Após selecionar Codex, os formulários novos e ações auxiliares resolvem Codex como padrão; uma escolha explícita Claude prevalece. Uma conversa existente e uma execução de spec em andamento mantêm seu provedor e suas aprovações.
- [x] [R5] O indicador passa a mostrar “Codex CLI conectado” somente com diagnóstico correspondente; um formulário novo não herda modelo Claude e métricas Claude não aparecem como consumo Codex. Sondagem Claude atrasada não sobrescreve o estado Codex.
- [x] [R6] Teclado permite abrir, navegar, selecionar e fechar com Escape; cancelar preserva a preferência. Em janela estreita, o seletor permanece acessível e não causa overflow.
- [x] Testes do rodapé, resolução de preferências e formulários afetados passam; `flutter analyze` não apresenta novos avisos.

Validação: 187 testes dos fluxos afetados passaram; a descoberta independente de CLIs também passou em teste específico. Compilação Linux de debug concluída.
