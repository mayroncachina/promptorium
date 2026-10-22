---
id: SPEC-015
status: em-revisao
---

# Descoberta de specs existentes e conclusão no Quadro

## Objetivo

Ao colocar specs existentes na pasta configurada do projeto, o Promptorium deve reconhecê-las e apresentá-las na tela Specs e no Quadro sem recriar os documentos ou executar novamente trabalho já feito. Specs declaradas concluídas devem entrar em Concluído. Specs implementadas cujo documento ainda esteja desatualizado devem poder ser verificadas contra o projeto e, com evidências suficientes, atualizadas para concluídas.

A pasta correta é `ProjectConfig.specsDir`, cujo padrão é `specs/`. Arquivos em `docs/specs/` só são descobertos quando essa for a pasta configurada ou quando forem colocados na pasta configurada. A interface deve mostrar esse caminho.

## Requisitos

- R1 · Fazer uma varredura inicial ao abrir ou ativar o projeto, inclusive quando o usuário abrir diretamente o Quadro. Observar adição, edição e renomeação de arquivos na pasta configurada, inclusive se ela for criada depois da abertura. Reconfigurar e varrer novamente quando a pasta de specs mudar. Oferecer “Sincronizar specs” para recuperação manual, sem exigir reinício.
- R2 · Importar specs Markdown com ID válido no frontmatter ou no nome do arquivo, preservando título, requisitos, dependências, fase e status. Usar a identidade projeto + código para atualizar registros existentes sem duplicar cartões, sessões ou etapas. Renomear ou mover uma spec para a pasta configurada deve atualizar seu caminho e manter os vínculos existentes. Conflitos de identidade e arquivos inválidos devem ter diagnóstico visível.
- R3 · Na importação ou sincronização, `status: concluida` e os aliases já aceitos devem resultar em `SpecStatus.done` e `SpecStage.done`: a spec aparece em Concluído nas Colunas e no estado equivalente do Canvas, mesmo sem sessão, worktree ou histórico de execução no Promptorium. Não criar execução, commit, merge ou métricas fictícios para justificar essa conclusão. Arquivadas mantêm o comportamento atual de arquivamento.
- R4 · Oferecer “Verificar implementação” para uma spec ou um conjunto de specs importadas. Usar o provedor de agente efetivo do projeto para comparar requisitos e critérios de aceite com código, testes e evidências existentes no repositório. Classificar cada requisito como implementado, parcial, pendente ou não verificável, citando arquivos, símbolos e verificações relevantes. Nome de commit, checklist marcado ou existência de arquivo isoladamente não comprovam implementação.
- R5 · Quando a verificação comprovar todos os requisitos e critérios aplicáveis, atualizar o frontmatter para `status: concluida` e mover a spec para Concluído. Se houver parte pendente, critério manual sem evidência, falha de análise ou resultado inconclusivo, manter o estado anterior e apresentar o que falta. Registrar a origem da conclusão e o relatório; conclusão declarada no documento deve ser distinguida de conclusão verificada pelo agente.
- R6 · Preservar trabalho em andamento durante a reconciliação. Specs com execução ativa, worktree com pendências ou revisão aberta devem apresentar o conflito antes de qualquer mudança de etapa que encerre o fluxo; sincronizar um arquivo não pode apagar worktrees, cancelar sessões ou simular merge. Resultados atrasados de outro projeto ou de uma versão anterior da spec/código não podem concluir a spec atual.

## Design

### Base existente e lacunas

`SpecService.sync` já lê arquivos `.md` diretamente na pasta configurada e faz upsert por código. `WorkspaceWatcher` já acompanha mudanças e `specStatusFromValue` reconhece `concluida`, `feita` e `done`. Reaproveitar esses componentes.

O documento controla `status`, mas o Quadro usa também `stage`. Centralizar as regras de reconciliação entre ambos para que um arquivo concluído importado não permaneça no backlog. Não manter uma segunda rotina de importação exclusiva do Quadro.

A varredura é dos arquivos diretamente na pasta configurada, conforme o comportamento atual; subpastas não entram neste escopo. Ignorar arquivos auxiliares sem identidade de spec, como README e relatórios de implementação. Mostrar a pasta observada na interface, com orientação para configurá-la ou colocar os arquivos nela.

### Identidade e estados

Tratar código duplicado em dois arquivos como conflito, em vez de escolher silenciosamente o primeiro. Quando ID e nome indicarem códigos diferentes, informar a divergência e aguardar correção. Leitura incompleta, YAML inválido ou status desconhecido não devem sobrescrever um registro válido nem marcar conclusão.

A sincronização deve ser idempotente e serializada por projeto, agrupando eventos de salvamento atômico. Um arquivo removido mantém o registro e seus vínculos com indicação de arquivo ausente; não apagar histórico. A mudança da pasta configurada não exclui automaticamente specs da pasta anterior.

Na importação inicial, specs não concluídas seguem as regras atuais de backlog/status documental. Em registros existentes, não regredir uma etapa operacional apenas porque o arquivo não declara conclusão. Uma mudança externa que retire explicitamente `concluida` de uma spec já concluída deve mostrar divergência com ação para reabrir; não reiniciar execução automaticamente.

### Verificação do que já foi implementado

A descoberta de arquivos é automática e local. A análise por agente é iniciada por “Verificar implementação”, com seleção das specs, indicação do provedor e possibilidade de acompanhar/cancelar. Não iniciar chamadas de IA a cada evento do watcher.

A verificação não implementa requisitos nem corrige código. Deve relacionar cada requisito e critério às evidências encontradas, registrar limitações e distinguir código existente de comportamento validado. Verificações executadas precisam ser pertinentes e seus resultados devem constar no relatório; critérios manuais não executados permanecem não verificáveis, salvo evidência registrada suficiente.

O relatório deve conter projeto, código e hash do conteúdo da spec, revisão do repositório e impressão das alterações locais relevantes, provedor, data e evidências por requisito/critério. Se os arquivos usados na análise mudarem antes da conclusão, invalidar o resultado e solicitar nova verificação. Persistir relatórios no armazenamento local do projeto com referência à spec; não acrescentar dados de consumo ou sessões artificiais ao histórico de implementação.

Uma análise completa e conclusiva pode marcar a spec como concluída sem uma segunda confirmação, pois essa é a finalidade explícita da ação. Apresentar esse efeito antes de iniciar a verificação. Manter a possibilidade de revisar o relatório e reabrir a spec. Specs parcialmente implementadas, como a integração de MR adiada no DT-55, não podem ser concluídas só porque a parte de detecção existe.

### Persistência e operações em curso

Atualizar frontmatter preservando o restante do documento, com gravação atômica, e reconciliar o banco de forma recuperável e idempotente. Uma falha de gravação não deve produzir um cartão concluído enquanto o documento permanece pendente. Ao reiniciar, a sincronização deve recuperar uma atualização interrompida.

Para specs sem operação ativa, status concluído no arquivo basta para posicionar o cartão, com origem “Declarada no arquivo”. Para specs em execução/revisão ou com worktree pendente, preservar o estado operacional e exibir a divergência para resolução explícita. Nenhuma conclusão importada remove recursos ou encerra uma integração remota.

## Critérios de aceite

- [ ] [R1] Com o app fechado, colocar specs na pasta configurada e abrir diretamente o Quadro: todas aparecem. Repetir com app aberto e pasta criada depois da abertura, sem reiniciar.
- [ ] [R1] Trocar `specs/` por `docs/specs/` na configuração dispara nova varredura; a interface mostra a pasta correta e a sincronização manual funciona quando o watcher não entrega um evento.
- [ ] [R2] Sincronizar repetidamente e renomear uma spec mantém um único registro/cartão e preserva sessões, etapas e dependências. IDs duplicados ou divergentes produzem diagnóstico, sem atualização arbitrária.
- [ ] [R2] README, relatório sem ID, arquivo temporário, Markdown sem identidade e YAML inválido não criam cartões incorretos nem sobrescrevem specs válidas.
- [ ] [R3] Uma spec importada com `status: concluida` aparece em Concluído nas Colunas e no Canvas, sem histórico fictício; aliases aceitos têm o mesmo efeito e arquivadas respeitam o filtro existente.
- [ ] [R4–R5] Com agente falso, uma spec inteiramente comprovada tem relatório persistido, frontmatter atualizado e cartão concluído. Resultado parcial, falha de agente ou aceite manual sem evidência mantém o estado anterior e mostra as pendências.
- [ ] [R4–R5] Uma spec com alguns requisitos implementados e outros adiados não é concluída; checklist marcado e mensagem de commit sem evidência não bastam. Watcher não inicia análise de IA automaticamente.
- [ ] [R6] Spec em execução/revisão ou com worktree pendente apresenta divergência sem encerrar sessão, apagar recursos ou mover silenciosamente o cartão para Concluído.
- [ ] [R5–R6] Mudança na spec, código relevante ou projeto durante a análise invalida o resultado atrasado. Falha entre gravação do arquivo e atualização do banco é recuperada na próxima sincronização.
- [ ] [R1–R6] Testes de serviço, watcher e Quadro cobrem os cenários acima; `flutter analyze` e testes dos fluxos afetados passam. Conferir manualmente importação, análise e conclusão no app.


## Implementação

Implementação disponível no código local em 21/10/2026. Detalhes e validações em
[IMPLEMENTACAO-014-015.md](IMPLEMENTACAO-014-015.md). O status permanece em revisão
até a conferência manual de aceite; requisitos parcialmente implementados em
outras specs não são marcados como concluídos por esta entrega.
