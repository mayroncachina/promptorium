---
id: SPEC-007
status: concluida
depende-de: [SPEC-003, SPEC-004]
---

# Modo YOLO do Codex no lugar do bypass Claude

## Objetivo

Quando o provedor da execução for Codex e o usuário selecionar o modo de bypass de permissões, usar `codex --yolo` nos fluxos de CLI e a configuração equivalente no App Server. Substituir os rótulos e argumentos Claude desse modo pelos correspondentes do Codex, preservando o comportamento Claude quando ele for o provedor escolhido.

Selecionar Codex por si só não ativa YOLO: a substituição se aplica ao modo de bypass escolhido para a execução.

## Requisitos

- R1 · Com Codex selecionado, a opção hoje identificada como `bypassPermissions` / `--dangerously-skip-permissions` deve aparecer como “YOLO — sem aprovações e sem sandbox”, com referência a `codex --yolo`. Com Claude selecionado, deve continuar usando a identificação e a flag Claude.
- R2 · Ao executar Codex pelo CLI com bypass selecionado, o sistema deve incluir `--yolo` na posição aceita pelo comando utilizado, inclusive nos fluxos de terminal, retomada e fork que suportem esse modo. Nunca enviar `--dangerously-skip-permissions`, `--permission-mode` ou outros argumentos exclusivos do Claude ao Codex.
- R3 · Nas execuções integradas via App Server, o mesmo modo deve configurar aprovação `never` e sandbox `danger-full-access`, usando os campos suportados pelo protocolo instalado. Não adicionar `--yolo` ao subcomando `app-server` sem suporte verificado. A configuração efetiva deve ser conferida na criação e retomada da thread e não pode ser sobrescrita por um turno com política diferente.
- R4 · O modo deve acompanhar o provedor e a configuração persistidos da execução em sessões, conversas, etapas de specs, reenvios e retomadas. Alterar o provedor padrão do rodapé não deve modificar o modo de uma execução existente. Dados antigos Claude com `bypassPermissions` devem continuar sendo interpretados como bypass Claude.
- R5 · Os formulários, detalhes e avisos existentes devem identificar o modo conforme o provedor. Para Codex, explicar que YOLO permite comandos e alterações sem aprovação e sem sandbox, inclusive fora do worktree. Preservar as regras existentes de elegibilidade do bypass; modos Perguntar e Planejar não devem ser convertidos em YOLO nem perder suas restrições.
- R6 · O sistema deve validar o suporte do comando ou protocolo antes de executar. Se não puder aplicar YOLO, deve informar a incompatibilidade e bloquear essa execução, sem ignorar o modo, trocar para Claude ou substituir silenciosamente por outro perfil. Testes devem demonstrar que modos Codex sem bypass não recebem YOLO.

## Design

### Mapeamento por provedor e transporte

| Provedor e transporte | Modo de bypass efetivo |
| --- | --- |
| Claude CLI | `--dangerously-skip-permissions` |
| Codex CLI / terminal | `--yolo`, em posição validada para o comando |
| Codex App Server | `approvalPolicy: never` e sandbox `danger-full-access` nos campos correspondentes do protocolo |

Centralizar a tradução do modo para cada provedor, evitando substituir strings de comandos já montados. O valor legado `bypassPermissions` pode continuar como compatibilidade de leitura; rótulo e argumentos devem ser resolvidos com a identidade do provedor. Não reaproveitar o `cliValue` Claude diretamente no gerador de comandos Codex.

Pontos a revisar: `lib/core/claude/claude_args.dart`, `lib/core/providers/agent_provider.dart`, `lib/core/codex/codex_provider.dart`, `lib/features/sessions/new_session_dialog.dart`, `lib/features/sessions/widgets/composer.dart`, `lib/features/sessions/session_manager.dart` e os fluxos de terminal e execução de specs cobertos pela SPEC-005.

O adaptador Codex atual já mapeia `skipPermissions` para aprovação `never` e sandbox `danger-full-access`. A implementação desta spec deve validar esse caminho e completar a apresentação, os comandos CLI e a persistência nos demais fluxos. Trocas de modo que exigirem reiniciar o processo devem usar o mecanismo existente de reinício explícito, preservando o histórico e o identificador externo.

### Base técnica

A [documentação oficial de comandos](https://learn.chatgpt.com/docs/developer-commands?surface=cli), consultada em 2026-10-20, documenta `--yolo` como alias de `--dangerously-bypass-approvals-and-sandbox`, desativando aprovações e sandbox. A integração de threads permanece pelo [Codex App Server](https://learn.chatgpt.com/docs/app-server); flags da interface interativa não devem ser presumidas válidas nesse subcomando.

Sondagem local em 2026-10-20: `codex --version` retornou `codex-cli 0.163.0`; `codex --yolo --help` foi aceito com código zero, sem iniciar uma execução. `codex app-server --help` não lista `--yolo`. Essa sondagem verifica o parser do CLI principal, mas não comprova execução, retomada, fork ou equivalência de políticas: validar esses cenários durante a implementação e registrar os resultados em `docs/pesquisa/`.

## Implementação

- Tradução e apresentação por provedor em `lib/core/providers/permission_policy.dart`; o valor legado `bypassPermissions` permanece legível e a preferência de modo Codex usa chave própria.
- CLI interativo em `lib/core/codex/codex_command.dart`: criação, retomada e fork com `--yolo`; o terminal valida o parser antes de abrir a sessão e usa o identificador externo salvo.
- App Server em `lib/core/codex/codex_provider.dart`: políticas explícitas na thread e nos turnos e recusa quando a resposta não confirma YOLO.
- Sessões e Quadro preservam provedor e modo; os formulários exibem YOLO para Codex e a timeline identifica o modo. Trocas Codex exigem turno parado e reinício do processo.
- Evidência da sondagem instalada em [codex-yolo.md](../pesquisa/codex-yolo.md). A validação real usa thread efêmera sem executar modelo; retomada, fork e comandos irrestritos são verificados por testes com servidor falso e testes do gerador de argumentos.

Validação: 151 testes dos fluxos afetados passaram, incluindo sessões, Quadro, Prompt, shell, Projeto e Review; `flutter analyze` sem avisos.

Testes específicos: `test/core/codex/codex_yolo_test.dart`, `test/features/sessions/codex_session_test.dart`, `test/features/sessions/codex_permissions_ui_test.dart` e `test/features/sessions/timeline_test.dart`.

## Critérios de aceite

- [x] [R1] Trocar Claude por Codex em um formulário novo troca o texto do bypass para YOLO; voltar para Claude restaura sua identificação, sem ativar o modo automaticamente.
- [x] [R2] Testes do gerador de comandos cobrem criação, terminal, retomada e fork Codex suportados com `--yolo`, sem flags Claude; a execução Claude mantém `--dangerously-skip-permissions`.
- [x] [R3] Servidor falso verifica as políticas de criação, retomada e turnos em YOLO, sem flag inválida em `app-server`; sondagem controlada confirma a configuração efetiva na versão instalada.
- [x] [R4] Reiniciar o app e retomar uma execução Codex YOLO preserva provedor, thread e modo; sessão Claude antiga continua Claude; mudar o padrão no rodapé não altera nenhuma delas.
- [x] [R5] Avisos e detalhes Codex exibem YOLO e seu alcance real; as restrições de elegibilidade existentes permanecem e Perguntar/Planejar não recebem acesso irrestrito.
- [x] [R6] Versão ou transporte incompatível produz erro antes da execução; execução Codex normal não contém `--yolo` nem políticas de bypass; não há fallback de provedor ou modo.
- [x] Testes dos geradores de comandos, adaptadores, formulários e persistência passam; `flutter analyze` não apresenta novos avisos.
