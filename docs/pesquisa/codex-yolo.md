# Codex YOLO — SPEC-007

Sondagem em 2026-10-20, Linux, `codex-cli 0.163.0`.

## CLI

Os comandos abaixo terminaram com código zero. `--help` valida o parser sem executar um modelo:

```text
codex --yolo --help
codex resume --yolo --help
codex fork --yolo --help
```

`codex app-server --help` não anuncia `--yolo`. O adaptador usa políticas JSON-RPC, sem passar essa flag ao App Server.

## App Server

Um subprocesso `codex app-server` recebeu `initialize`, `initialized` e `thread/start`, com diretório temporário, `ephemeral: true`, `approvalPolicy: never` e `sandbox: danger-full-access`. A resposta confirmou:

```json
{"approvalPolicy":"never","sandbox":{"type":"dangerFullAccess"},"ephemeral":true}
```

O subprocesso foi encerrado e o diretório temporário removido. Nenhum `turn/start` foi enviado, nenhum modelo foi executado e nenhum comando gerado por agente foi autorizado pela sondagem.

O schema gerado pelo CLI (`app-server generate-json-schema`) confirma `turn/start.sandboxPolicy`, incluindo `dangerFullAccess`, e `approvalPolicy: never`. Testes com servidor falso cobrem criação, retomada, fork, políticas por turno, recusa de política divergente e preservação do modo na sessão.

## Limites

A sondagem real confirma o parser dos comandos e a configuração efetiva de uma thread efêmera. Não executa comandos irrestritos, não mede efeitos fora do worktree e não comprova retomada/fork reais de uma thread persistida; esses fluxos têm cobertura automatizada com servidor falso.

## Fontes

- [Comandos oficiais do Codex](https://learn.chatgpt.com/docs/developer-commands?surface=cli).
- [Protocolo do App Server](https://learn.chatgpt.com/docs/app-server).
