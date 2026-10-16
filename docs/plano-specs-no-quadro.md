# Plano — a spec é o cartão do quadro

> Status: **proposta para revisão** (2026-10-16). Branch de trabalho: a partir de `feat/consumo`.

## Por quê

Dados reais do projeto `migracao-db` (2026-10-15): 11 specs e 63 tarefas, em média uma tarefa por requisito
(a SPEC-011 sozinha tinha 17). Nenhuma tarefa saiu do Backlog. A sessão mais cara do dia (US$ 10,59, 97 turnos,
contexto de 321 mil tokens) recebeu "implemente todas as specs": o quadro foi ignorado porque tinha cartões
demais, e o trabalho virou uma conversa gigante.

## Decisões (combinadas com o usuário)

1. **A spec é a unidade de trabalho**: um cartão no quadro, uma branch, um worktree, um PR, um merge.
2. **Os requisitos da spec (R1…Rn) são as etapas do cartão**, com progresso "3/7". Não existe mais tarefa
   solta dentro de spec.
3. **Etapas rodam em sequência** dentro da spec, cada uma (ou grupo pequeno) numa **sessão nova** no mesmo
   worktree: contexto limpo a cada etapa = custo baixo. Specs diferentes continuam podendo rodar em paralelo.
4. **Specs do tamanho de um PR**: o planner gera no máximo ~6 requisitos por spec; o que passar disso vira
   outra spec, não etapa.
5. **Dados existentes**: as tarefas que pertencem a uma spec são absorvidas pelas etapas (já são 1:1 com os
   requisitos); as dependências entre tarefas viram dependências entre specs; as tarefas soltas (sem spec)
   viram specs.

## Modelo

### Arquivo da spec (fonte da verdade, versionado no git)

Igual ao de hoje, com um campo novo no frontmatter:

```markdown
---
id: SPEC-003
status: aprovada
fase: mvp
depende-de: [SPEC-001, SPEC-002]
---
# Extração do schema do Firebird
## Objetivo …
## Requisitos
- R1 · Extrair domains, tabelas e colunas …
- R2 · …
## Critérios de aceite
- [ ] …
```

### Banco (schema v8)

- `specs`: + `stage` (`backlog` / `running` / `review` / `done` — a coluna do quadro), + `depends_on` (JSON,
  espelho do frontmatter), + `agent_name`, + `worktree_path` / `branch` / `base_branch` (um worktree por spec,
  `pr/spec-003-<slug>`).
- `spec_steps` (nova): `spec_id`, `step` (`R1`), `status` (`pending` / `running` / `done` / `needs_input`),
  `session_id` da última sessão que trabalhou nela, `done_at`. A lista de etapas vem do arquivo (sincronizada
  ao ler a spec); o banco guarda só o estado.
- `sessions`: + `spec_id`, + `steps` (ex. `R2` ou `R2,R3`). `task_id` fica para o histórico.
- `tasks`: deixa de ser usada pela interface; fica no banco nesta versão (migração reversível) e sai numa
  versão seguinte.

`stage` (onde o cartão está) e `status` do documento (ideia/rascunho/em revisão/aprovada/concluída) continuam
separados: o quadro mostra só specs **aprovadas** ou concluídas; rascunhos e ideias ficam na tela Specs.

## Execução de uma spec

1. **Executar** (no cartão ou na tela Specs): cria o worktree/branch da spec se ainda não existir e abre uma
   sessão para a **próxima etapa pendente**. Spec com até 3 requisitos roda inteira numa sessão só (regra
   ajustável em Configurações).
2. **Prompt da etapa** (curto, sem histórico): `@specs/SPEC-003-….md`, quais etapas já estão feitas (com o
   resumo do commit de cada uma), "implemente agora R3", "rode os testes", "faça commit
   `SPEC-003 R3: <resumo>`" e "termine com a linha `ETAPA CONCLUÍDA: R3`".
3. **Fim da sessão**: com o marcador `ETAPA CONCLUÍDA: R3` na última resposta, a etapa vira `done`; sem ele
   (o agente perguntou algo, falhou ou parou), a etapa vira `needs_input` e o cartão mostra "aguardando você"
   com o botão para abrir a sessão e responder.
4. **Avanço automático** (padrão ligado, por spec): etapa concluída abre a sessão da próxima. A última etapa
   concluída leva o cartão para **Review**.
5. **Trava**: uma spec só tem uma sessão rodando por vez; outra spec pode rodar ao mesmo tempo.
6. Modelo, esforço e agente vêm da spec (agente escolhido no cartão) ou dos padrões de Configurações.

## Telas

- **Quadro** (hoje "Tarefas", Ctrl+4): colunas Backlog / Em execução / Review / Feito com um cartão por spec:
  código, título, fase, barra "3/7", etapa atual e seu estado, bloqueada por (SPEC-001…), agente, custo
  somado das sessões. Arrastar muda a coluna (como hoje). Abrir o cartão: lista de etapas com estado e sessão
  de cada uma, Executar próxima / Executar tudo / Pausar avanço, Abrir spec, Ver review.
- **Specs**: o painel "Tarefas" vira "Etapas" (o mesmo da abertura do cartão); some "Gerar tarefas com o
  planner"; rastreabilidade passa a ser requisito → sessão → commit → merge.
- **Review**: um item por spec (o diff da branch da spec contra o merge-base, com todas as etapas);
  comentários vão para a última sessão da spec; **Fazer merge** marca a spec como Feito, todas as etapas como
  `done` e grava `status: concluida` no arquivo.
- **Projeto (Roadmap)**: o planner gera só specs (com `depende-de` entre specs e no máximo ~6 requisitos);
  saem os editores de tarefa e entra o de dependências da spec; "ordem de execução" passa a ser por spec;
  "Revisar e criar" grava os arquivos e coloca as specs no quadro, e abre a sessão da 1ª etapa da 1ª spec.
  Ideias de "Depois" viram spec sem tarefas.
- **Prompt**: "Criar tarefa" sai (já existe "Transformar em spec").
- **Sessões**: a sessão mostra "SPEC-003 · R3" no título e no painel lateral.

## Migração dos dados existentes (v8)

- Para cada spec: etapas = requisitos do arquivo; estado de cada etapa = o da tarefa com o mesmo
  `requirement` (`done` → `done`, resto → `pending`); `stage` = o "pior" estado das tarefas dela.
- Dependências: tarefa da spec A que depende de tarefa da spec B ⇒ A depende de B (gravado no banco; o
  `depende-de` do arquivo é escrito na primeira vez que o app salvar a spec, não durante a migração).
- Tarefas soltas (sem spec — hoje 2): aviso no Quadro "2 tarefas antigas sem spec" com "Transformar em
  spec" (cria o arquivo em rascunho) ou "Descartar". A migração do banco nunca escreve arquivos no
  repositório.

## Fases de implementação

Cada fase termina com `flutter analyze` limpo, testes passando e um commit.

| # | Fase | Entrega |
|---|---|---|
| 1 | Dados | schema v8, repositórios, sincronização etapas ⇄ arquivo, `depende-de` no frontmatter, regras puras (bloqueio por spec, próxima etapa, estágio a partir das etapas), migração das tarefas + teste de migração |
| 2 | Execução | `SpecRunner`: worktree por spec, sessão por etapa no mesmo worktree, prompt da etapa, marcador `ETAPA CONCLUÍDA`, avanço automático, trava por spec; troca o `_syncTask` do `SessionManager` |
| 3 | Quadro | kanban de specs, cartão com etapas e ações, aviso de tarefas antigas |
| 4 | Specs | painel Etapas, remove Gerar tarefas e o `TaskPlanner` (o `runReadOnlyClaude` vai para `core/claude`) |
| 5 | Review | item por spec, merge fecha spec, etapas e arquivo |
| 6 | Projeto | roadmap só com specs, dependências e limite de requisitos; editores; ideias; criação |
| 7 | Limpeza | Prompt sem "Criar tarefa", Nova tarefa removida, README e `plano-implementacao.md` |
| 8 | Verificação | uma spec real de 2 etapas executada de ponta a ponta com haiku (alguns centavos), build release |

## Riscos

- **Marcador de conclusão**: o agente pode esquecer a linha `ETAPA CONCLUÍDA`. Mitigação: o prompt pede de
  forma explícita, e o pior caso é parar em `needs_input` (nunca avança errado); o usuário marca à mão.
- **Spec grande antiga** (SPEC-011, 17 requisitos): continua funcionando por etapa (17 sessões curtas);
  o cartão sugere dividir em specs menores.
- **Mudanças não commitadas** entre etapas: ficam no worktree e a próxima sessão as vê; o commit por etapa é
  pedido, não obrigatório.
