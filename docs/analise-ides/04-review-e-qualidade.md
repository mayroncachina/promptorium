# 04 — Review e qualidade

Hoje: a spec chega ao Review quando todas as etapas estão feitas; diff contra o merge-base,
rejeitar hunk, comentários por linha enviados à última sessão, Criar PR (`gh`), Fazer merge
(`--no-ff`). Estado dos comentários só em memória (DT-36), merge com limites (DT-37), PR sem
`gh auth status` (DT-38).

## 4.1 Review automático antes do humano

Cursor (Bugbot), Copilot (agentic code review, que devolve PRs de correção) e Codex revisam antes
de alguém olhar. No Promptorium o lugar é entre "última etapa concluída" e "Review":

1. Spec entra em **"Pré-review"** (sub-estado da coluna Review, ou coluna própria — sugiro
   sub-estado para não alongar o quadro).
2. Sessão **somente leitura** (`readonly_run`, modelo barato, `--max-budget-usd` baixo) com o agente
   `spec-reviewer` (embutido no app, sobrescrevível em `.claude/agents/`), que recebe: a spec, o
   diff da branch, a saída do último gate, e a `memoria.md`. Saída por `--json-schema`:
   `{veredito: aprovar|corrigir, comentarios: [{arquivo, linha, texto, severidade}]}`.
3. `corrigir` → os comentários viram uma **sessão de correção** na spec (mesmo worktree, etapa
   virtual `REV1`) e a spec volta para Em execução; limite de rodadas (padrão 2).
4. `aprovar` ou limite atingido → Review humano com os comentários do revisor já na lateral,
   marcados "revisor automático".

Isso reaproveita o que já existe (`readonly_run`, comentários por linha, `subagentes: quando:
fim-da-spec`) e define um padrão de qualidade com custo previsível. Desligável por projeto.

## 4.2 Diff e estado do Review

- **Persistir o rascunho** de comentários e hunks aceitos/rejeitados no banco (DT-36) — perder
  comentários ao fechar o app é o tipo de coisa que faz o usuário voltar para o terminal.
- **Histórico de rodadas**: rodada 1 (revisor automático) → rodada 2 (humano) → correções, com o
  commit de cada uma. Hoje a rastreabilidade para no commit de merge (DT-34).
- **Todos os arquivos numa página** com navegação lateral, realce de sintaxe (o `re_highlight` já
  está no app) e lado a lado opcional. Um arquivo por vez cansa em spec com 15 arquivos.
- **Diff por etapa**: filtrar o diff pelos commits `SPEC-003 R2:` — ajuda a revisar spec grande e
  a atribuir um comentário à etapa certa.
- **Checks no topo**: resultado do gate (testes, lint, build) e, se houver PR, o status do CI do
  GitHub (`gh pr checks`).

## 4.3 PR e merge

- `gh auth status` antes de Criar PR; PR como rascunho opcional; corpo do PR com as etapas (já
  existe) + link dos critérios de aceite marcados.
- **Babysit de PR** (Cursor `/babysit`, Copilot): depois de Criar PR, o app acompanha CI e
  comentários (`gh pr view --json`, polling) e oferece "Enviar comentários do PR ao agente" como
  nova rodada de correção. Fase posterior; depende de `gh`.
- **Merge mais seguro** (DT-37): fazer o checkout da base se necessário (com confirmação), ou
  mergear num worktree temporário da base e só depois `git push`/atualizar a raiz; oferecer
  **rebase/squash** como opções; em conflito, abrir uma sessão "resolver conflito" no worktree com o
  diff dos dois lados (Cursor e Copilot já fazem o agente resolver).
- **Specs empilhadas** (merge de A antes de B que depende de A) já existe; mostrar no Review a
  ordem obrigatória e bloquear o botão fora de ordem.

## 4.4 Critérios de aceite como verdade

Ligar o 02 §2.3 ao Review: cada critério `[R2]` aparece como checklist no painel lateral; os que
têm comando são marcados pelo gate; os sem comando o revisor automático tenta confirmar lendo o
diff; o resto o humano marca. **Merge só com todos marcados** (ou "mergear mesmo assim" com motivo
registrado). É o que transforma "a spec terminou" em "a spec foi cumprida".

## 4.5 Qualidade medida

Guardar por spec: rodadas de correção, turnos de correção automática, custo total, tempo
etapa-a-etapa, hunks rejeitados pelo humano. Mostrar na tela Projeto um resumo ("últimas 10 specs:
1,4 rodadas em média, US$ 2,10, 0 hunks rejeitados"). Sem isso não dá para saber se as mudanças
deste documento estão funcionando.
