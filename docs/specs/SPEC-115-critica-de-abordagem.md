---
id: SPEC-115
status: rascunho
versao: 0.29.0
tipo: recurso
issue: 463
depende-de: []
---

# Crítica de abordagem nos gates de decisão

[Issue #463](https://github.com/mayroncachina/promptorium/issues/463)

## Objetivo

Quando a pessoa chega a um **gate de decisão**, o Promptorium roda uma análise crítica das opções que estão na mesa e a mostra ao lado delas. A análise se apoia numa **base de conhecimento** de arquitetura: a que vem com o app (Clean Architecture, SOLID, DDD, testabilidade e simplicidade) e a que o projeto acrescenta. A crítica **só aconselha**. Ela nunca bloqueia, nunca escolhe e nunca altera a spec.

Hoje as decisões chegam sem contraponto. No modal de decisão da etapa (SPEC-033), a IA propõe de 2 a 4 opções e marca uma como sugerida, mas não diz o que cada uma custa. Nas Decisões P1…Pn de uma spec, a recomendação vem do mesmo agente que escreveu a spec. O mini planejamento e o plano das etapas seguem o mesmo padrão. Uma decisão que fere uma regra do projeto (por exemplo, a tela chamar o banco direto) só aparece depois, no review ou no débito técnico.

### Exemplo

> A etapa R3 de uma spec para em "aguardando você". O agente pergunta onde calcular o frete e propõe: (1) no widget do carrinho, (2) num caso de uso `CalcularFrete` no domínio, (3) no repositório que já lê os CEPs.
>
> Ao lado de cada opção aparece um selo. A opção 1 vem com **grave**: "a tela passa a conter regra de negócio e o cálculo não fica testável sem widget (CA-01 Regra de dependência, TS-02 Teste como sinal de design)". A opção 3 vem com **atenção**: "mistura acesso a dados com regra (SOLID-S); só vale se o frete for uma consulta, sem cálculo". A opção 2 vem com **ok**, e um risco: "mais um arquivo para um cálculo de três linhas; YAGNI se o frete não mudar". A pessoa escolhe a opção 2 e registra o risco como débito em um clique.

## Requisitos

### Núcleo

- R1 · **Execução de crítica.** É uma execução auxiliar, estruturada e somente leitura (`runStructured`, SPEC-100), com schema próprio. Ela recebe três coisas: o contexto do gate (as opções, as decisões ou o plano), o texto da spec e a base de conhecimento (R7–R9). Lê o repositório em somente leitura, com orçamento curto, para citar arquivos reais ("`cart_widget.dart` já chama o repositório"), e nunca grava nada (P11).
- R2 · **O que a crítica devolve.** Para cada opção:
  - um resumo de uma linha;
  - os pontos a favor;
  - os riscos;
  - os princípios envolvidos, cada um com o ID, a fonte (do app ou do projeto) e o motivo;
  - uma gravidade: **ok**, **atenção** ou **grave**.

  Além disso, uma leitura geral da abordagem em até três linhas. **Grave** só vale quando a opção fere uma regra do projeto ou um princípio com custo alto de reverter. A crítica deve dizer quando um princípio **não** se aplica ao caso, para não virar dogma.
- R3 · **Só aconselha.** A crítica não muda a ordem, o texto nem a opção sugerida pelo gate, e nunca impede uma escolha. As teclas e os botões do gate funcionam enquanto ela é gerada, mesmo que ela falhe.
- R4 · **Provedor.** Uma linha nova, "Crítica de abordagem", em Configurações › Provedores (o mesmo cartão de "Planner e assistentes"). O padrão é o Claude Code com Sonnet e esforço baixo. O provedor, o modelo e os tokens aparecem no rodapé da crítica.
- R5 · **Guardada e reaproveitada.** Cada crítica fica guardada junto com o gate: a spec, o tipo de gate, o hash da entrada, o JSON, o modelo, os tokens e a data. Com a mesma entrada, o app mostra a crítica guardada sem rodar de novo. **Criticar de novo** força uma nova execução.
- R6 · **Vira débito ou decisão.** Cada risco tem duas ações, **Registrar como débito** e **Registrar como decisão pendente**. As duas abrem o diálogo da SPEC-112 já preenchido, com o texto, o princípio e a origem ("crítica · R3 da SPEC-NNN"). O ID criado aparece no próprio risco.

### Base de conhecimento

- R7 · **Base do app.** São quatro temas em Markdown, que vêm com o app em `assets/knowledge/`:
  - `clean-architecture.md`, com IDs `CA-`;
  - `solid.md`, com IDs `SOLID-`;
  - `ddd.md`, com IDs `DDD-`;
  - `testabilidade-simplicidade.md`, com IDs `TS-`.

  Cada princípio tem ID, nome, o que diz, sinais de violação, quando não se aplica e uma pergunta de checagem. O texto é escrito pelo projeto, em português. São resumos próprios, sem trechos de livros.
- R8 · **Base do projeto.** Entram os arquivos `docs/arquitetura/*.md` do workspace e o `AGENTS.md` (SPEC-113). Princípios do projeto podem ter IDs próprios (`PRJ-`). Quando o projeto contradiz a base do app, **o projeto manda**, e a crítica cita o princípio do projeto.
- R9 · **Seleção sem embeddings.** Não há índice vetorial.
  - A base do app vai inteira no prompt, porque é pequena: no máximo 40 KB somando os temas ligados.
  - Da base do projeto vai um índice (arquivo, títulos e IDs), e a execução lê o que precisar com a ferramenta de leitura.
  - Um tema desligado no projeto não entra.
- R10 · **Tela da base.** Fica em Projeto › Configuração, na seção "Crítica de abordagem", e mostra:
  - os temas do app, cada um com um interruptor, a quantidade de princípios e "Ver";
  - os arquivos do projeto encontrados, com "Abrir no editor";
  - "Criar `docs/arquitetura/`", que grava um `README.md` de exemplo, quando a pasta não existe.

### Gates

- R11 · **Disparo por gate.** Também em Projeto › Configuração, cada gate tem três modos: **Automático**, **Botão** ou **Desligado**. O padrão é Automático no modal de decisão e nas Decisões da spec, e Botão nos outros dois. No modo Botão, o gate mostra "Criticar abordagem", com uma estimativa de tokens.
- R12 · **Modal de decisão da etapa (SPEC-033).**
  - A crítica começa assim que as opções aparecem, sem atrasar a abertura do modal.
  - Cada opção ganha o selo de gravidade, e a prévia ganha uma aba "Crítica" ao lado de "Como a etapa fica".
  - Em **Compilar**, a crítica da opção escolhida entra no resumo das decisões, mas não vai na mensagem ao agente. Ela só vai se a pessoa marcar "Enviar a crítica ao agente".
- R13 · **Decisões da spec (P1…Pn).** Onde a spec mostra as perguntas abertas com recomendação e a seção `## Decisões`, cada decisão ganha a crítica da sua recomendação e das alternativas. O topo da spec ganha uma leitura geral da abordagem. Uma decisão já tomada só é criticada a pedido.
- R14 · **Mini planejamento (Nova spec).** Cada bloco de pergunta do Planner (SPEC-091) ganha a crítica das suas opções, dentro do próprio bloco. Responder a pergunta não espera a crítica.
- R15 · **Plano antes de executar.**
  - Depois de **Planejar** (`## Plano` e `## Etapas`) e no diálogo **Executar spec**, a crítica avalia a abordagem do plano e aponta as etapas que ferem a base.
  - Uma etapa grave ganha o selo na lista de etapas.
  - Executar continua liberado.
- R16 · **Estados.**
  - **Gerando**: esqueleto nos selos.
  - **Falhou**: "Não consegui criticar: <motivo>", com "Tentar de novo".
  - **Sem base do projeto**: aviso discreto "Só a base do app", com o link para R10.
  - **Desligado**: nada aparece.

  Se o gate fechar no meio, a execução é cancelada.

## Decisões

- P1 · **Gates.** **Decidido (27/11):** os quatro: modal de decisão da etapa, Decisões da spec, mini planejamento e plano antes de executar. "Criar o mock" era o pedido do canvas das telas, não um gate.
- P2 · **Formato.** **Decidido (27/11):** só execução do app, sem SKILL.md. O app dispara a crítica no gate.
- P3 · **Base.** **Decidido (27/11):** Markdown curado do app mais o do projeto, sem embeddings.
- P4 · **Peso.** **Decidido (27/11):** só aconselha, com o selo de gravidade.
- P5 · **Disparo.** **Decidido (27/11):** cada gate pode ficar automático, sob demanda ou desligado. Os automáticos de fábrica são o modal de decisão e as Decisões da spec.
- P6 · **Temas de fábrica.** **Decidido (27/11):** Clean Architecture, SOLID e design de código, DDD, Testabilidade e simplicidade.
- P7 · **Provedor.** **Decidido (27/11):** linha própria em Provedores. O padrão é Sonnet com esforço baixo.
- P8 · **Guardar.** **Decidido (27/11):** sim, a crítica fica salva no gate, e cada risco pode virar débito ou decisão pendente (SPEC-112).
- P9 · **Pasta do projeto.** **Decidido (27/11):** `docs/arquitetura/`, visível no repositório.
- P10 · **Entrega.** **Decidido (27/11):** spec pai `spec/115-critica-de-abordagem` com filhas por tarefa. O canvas é validado antes de implementar.
- P11 · **A crítica lê o código.** **Decidido (27/11):** sim, em somente leitura e com orçamento curto (R1).

## Perguntas em aberto

Nenhuma.

## Fora do escopo

- Busca vetorial, embeddings e importação de PDFs ou livros.
- Uma SKILL.md para usar a crítica fora do app.
- Bloquear ou reordenar decisões.
- Criticar diffs de código no review, que já tem o revisor automático (SPEC-102).
- Editar a base de conhecimento dentro do app: o app abre o arquivo no editor.

## Design

- **Núcleo:** `lib/features/critique/`:
  - `critique_service.dart`: monta a entrada por gate, o hash e o `runStructured`;
  - `critique_schema.dart`;
  - `critique_models.dart`: `ApproachCritique`, `OptionCritique`, `CritiquePrinciple` e `CritiqueSeverity`;
  - `critique_state.dart`;
  - `widgets/critique_badge.dart`, `widgets/critique_panel.dart` e `widgets/critique_button.dart`.
- **Base:** `assets/knowledge/*.md` (registrados no `pubspec.yaml`) e `lib/features/critique/knowledge_base.dart`, que lê os temas e os IDs, monta o índice do projeto e aplica o limite de 40 KB.
- **Gates:**
  - `lib/features/board/widgets/step_decision_dialog.dart` e `step_decision_preview.dart` (R12);
  - a visão das decisões da spec, com `spec_answers.dart` e `spec_file.dart` (R13);
  - `lib/features/specs/new_spec_view.dart` e `spec_planner.dart` (R14);
  - `lib/features/specs/spec_design.dart` e `lib/features/board/widgets/run_spec_dialog.dart` (R15).
- **Provedor:** uma linha em `structured_run.dart` (`AppFlow.critique`) e em `provider_kind_card.dart` (R4).
- **Banco:** tabela `ApproachCritiques` (spec, gate, chave do item, hash da entrada, JSON, provedor, modelo, tokens e datas) e as preferências por gate em `app_settings` do projeto. Migração v40.
- **Débitos:** reaproveita o diálogo de registro da SPEC-112 (`lib/features/debts/`).
- **Mock:** [canvas no Claude Design](https://claude.ai/artifact/4LqW2yiNN2aj7mcwYKbfWx) com seis telas: 1 · modal de decisão, 2 · Decisões da spec, 3 · mini planejamento, 4 · plano antes de executar, 5 · base de conhecimento e disparo, e 6 · estados e registrar como débito. Ele fica em `docs/mockups/spec-115/` depois de validado.

## Tarefas

- T1 · **Núcleo** (R1–R5, R16): serviço, schema, modelos, tabela e migração v40, e a linha do provedor. Verificar: testes do serviço com um provedor falso, do hash e da reutilização, e da migração.
- T2 · **Base de conhecimento** (R7–R10): escrever os quatro temas, o leitor, o índice do projeto e a tela da base. Verificar: testes do leitor (IDs, limite e temas desligados) e de widget da tela.
- T3 · **Modal de decisão e Decisões da spec** (R11–R13): selos, a aba Crítica e a crítica no Compilar e na visão da spec. Verificar: testes de widget dos dois gates, com a crítica gerando, pronta e com falha.
- T4 · **Mini planejamento e plano** (R14, R15). Verificar: testes de widget dos dois gates.
- T5 · **Disparo por gate e registro** (R6, R11): a configuração por projeto e o "Registrar como débito/decisão". Verificar: testes das preferências e do diálogo preenchido.
- T6 · **Ponta a ponta** no app compilado, com dados isolados, e o guia de uso. Verificar: prints e relatório.

## Critérios de aceite

- [ ] No modal de decisão, cada opção mostra o selo e a crítica, com princípios citados por ID e fonte, sem atrasar a abertura nem bloquear as teclas `1`–`4`.
- [ ] Nas Decisões da spec, no mini planejamento e no plano, a crítica aparece no modo configurado: automático, botão ou desligado.
- [ ] Um princípio de `docs/arquitetura/` que contradiz a base do app prevalece na crítica.
- [ ] A mesma entrada não roda de novo; "Criticar de novo" roda.
- [ ] Um risco vira débito ou decisão pendente com o diálogo da SPEC-112 preenchido, e o ID aparece no risco.
- [ ] Com o gate desligado ou com a execução falhando, o gate funciona como hoje.
- [ ] A base do app não tem trechos copiados de livros.
