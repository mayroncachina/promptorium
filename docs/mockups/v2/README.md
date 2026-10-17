# Mockups v2 — UX vinda da análise das IDEs

Canvas para aprovação: https://claude.ai/artifact/2nALCRdzQV6oyfneUQZXxN
Fonte: [`docs/analise-ides/`](../../analise-ides/00-README.md). Status: proposto (2026-10-17), nada implementado.

Barra lateral nova (Ctrl+1…9): Início · Projeto · Specs · Quadro · Sessões · Review · Código · Prompt · Ferramentas.
Os contadores laranja na barra são o que espera decisão humana.

| Tela | Arquivo | O que muda | Origem |
|---|---|---|---|
| 1 · Início "Para você" | `Main.dc.html` | Uma lista com tudo que espera decisão (aprovações, etapas sem resposta, specs em review, PR com CI falhando, sessões interrompidas) + painel "Agora" (em execução, Autopilot, custo do dia) | Codex app (fila de review), Conductor, Zed |
| 2 · Sessões lado a lado | `Sessoes.dc.html` | Dois painéis (ou grade 2×2); linha ao vivo da ferramenta na lista; "↶ voltar para aqui" por edição; thinking recolhido; subagente com custo; "Abrir preview :porta" | Cursor (Agent Tabs), Claude Code (`/rewind`) |
| 3 · Paleta Ctrl+K | `Paleta.dc.html` | Ações pendentes (Aprovar/Negar/Responder) na paleta, filtros `>` `#` `@` `:`, recentes | Cursor, Zed |
| 4 · Folha de atalhos | `Atalhos.dc.html` | Ctrl+/ com todos os atalhos por área (resto do DT-05) | — |
| 5 · Prompt, Planejar | `Prompt.dc.html` | Card "Plano pronto" com "Implementar como sessão" / "Transformar em spec"; conversa não vira Editar sozinha (DT-26); `@` `/` `#` no composer (DT-22) | Copilot (Plan → Implement) |
| 6 · Spec com rastreabilidade | `Specs.dc.html` | Clicar em Rn abre painel: critérios (quem marcou), gate, design usado, commits, sessão, "Ver diff da etapa", "Refazer a partir daqui" | Kiro |
| 7 · Projeto, saúde | `Projeto.dc.html` | Aba Saúde: métricas das últimas 10 specs, gate por spec, memória com autor e data, config detectada; "Analisar repositório" | Conductor (checks), 04 §4.5 |
| 8 · Novo projeto, Começar | `NovoProjeto.dc.html` | Sem modal: três origens (pasta existente, novo, clonar), modelo de stack, "Criar sem planejar" | — |
| 9 · Novo projeto, Proposta | `Planejar.dc.html` | Uma ideia → visão, stack e roadmap de uma vez, em três colunas editáveis; refinar é uma linha opcional; painel "Criar" com o que será gravado | Kiro, Copilot |
| 10 · Quadro | `Quadro.dc.html` | Painel lateral no clique do cartão (etapas, sessão ao vivo, gate, dependências) em vez de diálogo; cartões que pedem atenção sobem com borda laranja/vermelha; Backlog separa "prontas" de "bloqueadas" por onda; "Em execução 3 / 3" mostra o limite do Autopilot; barra de etapas segmentada; filtros e visão Linha do tempo | Conductor, Cursor |
| 11 · Configurações | `Configuracoes.dc.html` | Seções à esquerda com busca e marcador "alterado"; escopo App × Workspace na mesma tela (a config do projeto sai do diálogo do Projeto); cada seção abre com o efeito em linguagem simples ("a etapa só passa se…"); versão recomendada do CLI e versão nova do app no rodapé | VS Code, Zed |

## Quadro e Configurações: o que muda

**Quadro** (hoje: 4 colunas, cartão com chips e menu, diálogo "Etapas e sessões", toggle Grafo):
1. Clique no cartão abre um painel lateral fixo com etapas, sessão ao vivo (linha da ferramenta, custo, botões Abrir/Mensagem/Parar), último gate e dependências. O diálogo some.
2. Cartão que precisa de você sobe para o topo da coluna com borda laranja (aprovação) ou vermelha (gate recusou) e a ação principal no próprio cartão.
3. Backlog em dois grupos: "Prontas · onda N" (entram sozinhas quando liberar vaga) e "Bloqueadas" (diz o que espera).
4. Cabeçalho "Em execução 3 / 3" mostra o limite `autopilot.paralelo`; a faixa do Autopilot traz onda atual, orçamento do dia e agenda.
5. Barra de progresso por etapa (segmentos verde/laranja/cinza/vermelho) em vez de fração de texto.
6. Filtros "Precisam de mim", fase e agente; terceira visão "Linha do tempo" (ondas no tempo) além de Colunas e Grafo.

**Configurações** (hoy: página única rolável com 7 seções; config do projeto em diálogo na tela Projeto):
1. Seções à esquerda, em dois grupos: App e Workspace. A config do projeto (`config.yml`) passa a morar aqui, no mesmo lugar, com o nome do workspace visível.
2. Busca de configuração e ponto laranja nas seções com valor alterado do padrão; chip "alterado" na linha.
3. Cada seção abre com uma frase de efeito ("com estas opções, a etapa só passa se: ✓ testes ✓ lint ✓ commit"), para não precisar ler cada campo.
4. Linha = rótulo, explicação curta e controle à direita; "Restaurar padrões" por seção, não global.
5. Comandos bloqueados como chips, com os embutidos visíveis em cinza (hoje a lista embutida é invisível).
6. Rodapé mostra versão do CLI atual × recomendada e versão nova do app.
7. Seções novas que hoje não existem: Atalhos (personalizar), Notificações, Autopilot e agenda.

## Novo projeto: o que muda em relação ao fluxo atual

Hoje: diálogo (nome, pasta, remoto) → tela Projeto com 5 passos lineares (Pasta · Visão em chat · Stack · Roadmap · Revisar e criar). Repositório com código não passa pelo planner.

1. **Sem diálogo**: "Começar" é uma tela, com as três origens lado a lado e os recentes.
2. **Planejar é opcional**: "Criar sem planejar" existe desde o início; o planner pode ser chamado depois na aba Roadmap do Projeto.
3. **Uma ideia, uma proposta**: em vez de conversar primeiro, a pessoa escreve um parágrafo e o planner devolve visão, stack e roadmap juntos (uma chamada, custo mostrado). Refinar é uma linha de texto que atualiza só a coluna afetada.
4. **Modelos de stack** (Flutter app, Next.js, API Python, CLI Dart, Vazio) preenchem stack, comandos e CLAUDE.md; o planner só ajusta.
5. **Perguntas em aberto não bloqueiam**: viram nota na spec correspondente.
6. **Repositório existente ganha "Analisar repositório"**: detecta testes/lint, propõe CLAUDE.md, memória e primeiras specs.
7. **Criar mostra exatamente o que será gravado**, com cada item desmarcável, e "Executar SPEC-001 agora" como opção.
