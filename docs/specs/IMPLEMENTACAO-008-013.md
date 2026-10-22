# Implementação das SPEC-009 → 013 e SPEC-008

Ordem de trabalho: comentários, comparação por rodada, prontidão, merge local,
detecção do GitLab e Canvas. Os arquivos das specs conservam seu status e seus
critérios originais: este registro não substitui a revisão de aceite.

## Alterações disponíveis

- **SPEC-009:** esquema v16, estado tratado/reaberto, índice externo parcial,
  reconciliação de comentários anteriores, leitura paginada dos comentários em
  linha do GitHub com respostas agrupadas, cartões no diff, comentários gerais e
  fora do diff, filtros e seleção para envio. O envio precede a transação que
  grava a rodada e trata os selecionados. A ancoragem usa hunks de contexto zero
  e não tenta reaproveitar linhas alteradas, removidas ou renomeadas.
- **SPEC-010:** validação do commit e da ancestralidade, diff desde uma rodada
  incluindo pendências e arquivos novos, escolha da última rodada válida,
  contagens e identificação dos arquivos sem mudanças. As comparações são
  somente leitura e reutilizam a ancoragem dos comentários.
- **SPEC-011:** modelo puro de prontidão, identificação de bloqueios do serviço
  e da tela, avisos, falhas de leitura bloqueantes, painel, estado parcial na
  fila, ações e controles de merge. Branch e árvore limpa usam as mesmas
  funções do serviço de merge. A tela observa arquivos e refs dos repositórios
  do item selecionado, com debounce.
- **SPEC-012:** opções explícitas de troca/restauração de branch, stash por SHA,
  restauração do índice, métodos merge/squash/rebase, padrão no config.yml,
  previsão com merge-tree, tratamento tipado de conflitos e opção de enviar a
  resolução ao agente. Pular hooks afeta somente o commit de pendências.
- **SPEC-008:** Canvas com InteractiveViewer, zoom limitado, menu e atalhos,
  seleção, ondas, nós compactos, indicadores das etapas, referências realmente
  usadas, expansão das referências, cartões por mouse/foco, painel de detalhes,
  atenção e ações compartilhadas com as Colunas. Movimento reduzido desliga as
  animações.

## SPEC-013: restante adiado como débito técnico

Decisão de escopo em 21/10/2026: detecção e orientação de CLI passam para a
[SPEC-014](SPEC-014-deteccao-de-hospedagem-e-cli.md). A integração operacional
restante fica no [DT-55](../debito-tecnico.md#dt-55--integracao-completa-do-review-no-gitlab).
O estado técnico registrado abaixo continua válido, mas não é bloqueio para
entregar a SPEC-014 nem para usar projetos GitHub.

A detecção de remotes HTTPS/SSH/scp e a configuração `hospedagem` estão
implementadas. O botão usa MR para GitLab e informa problemas de CLI e
credenciais. A interface inicial de disponibilidade do hospedeiro está em
`review_host.dart`.

**R3–R6 não estão implementados.** Também permanecem pendentes a extração
completa do GitHub para ReviewHost e a migração `sessions.pr_host`, que fará
parte da integração de criação/acompanhamento de MR. Não há suporte operacional
a MR anunciado como disponível.

A sondagem está em [glab-1.36.0.md](../pesquisa/glab-1.36.0.md):

1. O glab instalado é 1.36.0 e não suporta `mr view --output json`.
2. A autenticação configurada informa `Invalid token provided`.
3. É necessário corrigir a autenticação e indicar um projeto/MR que possa ser
   consultado para confirmar os campos, a paginação e o merge agendado antes de
   implementar o restante, conforme exige a SPEC-013. Nenhum MR foi criado ou
   mergeado durante a sondagem.

## Validação

Os testes cobrem migrações, deslocamento de linhas, reconciliação e persistência
externa, classificação de prontidão, detecção de hospedeiro, zoom e extração de
skills. Testes com repositórios git temporários cobrem diff desde commit,
métodos de merge, restauração de branch/stash staged, conflito e rollback nos
três métodos, além de hooks que falham. A suíte existente do Quadro foi adaptada
para validar pan do Canvas no lugar dos dois Scrollables anteriores.

As verificações manuais das specs (GitHub/GitLab reais, desempenho com 60 specs,
renderização e fluxos completos numa sessão real) continuam pendentes. Não houve
publicação, push ou merge neste repositório.

Resultado da validação automatizada em 21/10/2026:

- `flutter analyze`: sem problemas.
- `flutter test --concurrency=2`: 533 testes passaram, 4 ignorados.
- Após os últimos ajustes da interface, 25 testes direcionados do Review e
  Quadro passaram, incluindo o teste novo de comentário tratado/reaberto.
- `git diff --check`: sem problemas.

A concorrência reduzida evita a instabilidade de timing observada nas fixtures
antigas de sessões ao executar duas suítes ao mesmo tempo.
