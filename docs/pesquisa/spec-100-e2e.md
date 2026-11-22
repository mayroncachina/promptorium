# SPEC-100 · E2E das execuções estruturadas no app isolado

Data: 22/11/2026. Build release da branch `spec/100-t4-provedor-por-tipo`, Xephyr `:6` a 1366×768, `XDG_DATA_HOME` num diretório temporário. Os dados reais do usuário (`~/.local/share/promptorium`, `~/.codex`, `~/.claude`) não foram tocados.

## Sem turno pago do Codex

Nenhum turno real do Codex foi gasto. No `PATH` do app ficou um **Codex falso** (script Python), que responde:

- à sondagem: `--version` (`codex-cli 0.170.0`), `app-server --help`, `app-server generate-json-schema` e `login status`;
- ao App Server por JSON-RPC: `initialize`, `account/read`, `model/list`, `command/exec`, `thread/start|resume`, `turn/start` e `turn/interrupt`.

O catálogo tem dois modelos: `gpt-6.1-terra`, com `text` e `image`, e `gpt-6-luna`, só com `text`. No `turn/start`, o falso espera 6 s e devolve uma `agentMessage` com um JSON montado a partir do `outputSchema` recebido, mais um `thread/tokenUsage/updated` de 14,2 mil tokens. Cada pedido do app fica num log. O comportamento do protocolo segue as fixtures da SPEC-093.

Dois workspaces de teste: `loja-api`, um repositório com a SPEC-031, e `cupons-app`, criado pelo próprio app em Novo projeto. A preferência salva foi **Planner e assistentes = Codex** e o rodapé ficou no Claude Code.

## Resultado

| # | Fluxo | O que se viu | Print |
|---|---|---|---|
| 1 | Configurações → Modelo e consumo | Cartão Provedor por tipo: Planner e assistentes no Codex (`Codex · gpt-6-luna · medium`); Sessões e Prompt seguem o rodapé (Claude); Executar spec e Revisor com Só Claude Code; a ordem de resolução; Protótipo e Classificador em "Ficam no Claude Code" | `app/1-provedor-por-tipo.png` |
| 2 | Nova spec com print (`gpt-6.1-terra`) | Rodou no Codex: `thread/start` com `sandbox: read-only`, `approvalPolicy: never` e `developerInstructions`; o app-server subiu com `-c mcp_servers={}`; o `turn/start` levou o print como `{"type":"image"}`. O rascunho foi preenchido, e a linha mostrou `Codex · gpt-6.1-terra · 14 mil tokens · custo indisponível · 6 s` | `app/2-nova-spec-codex.png` |
| 3 | Verificar spec (SPEC-031) | O diálogo mostrou "Provedor: Codex", e a barra mostrou `Codex · gpt-6.1-terra · rodando`. Resultado: "pendências encontradas" (o falso marca `nao-verificavel`) | `app/3-verificar-codex.png` |
| 4 | Refinar a Nova spec (R7) | O segundo turno usou `thread/resume` na mesma thread, e a linha mostrou "Continua no Codex, onde a execução começou." | `app/4-refinar-no-mesmo-provedor.png` |
| 5 | Protótipo de telas (Só Claude Code) | Etiqueta **Só Claude Code** na barra do protótipo, com o motivo na dica. A geração não foi disparada, para não gastar a cota do Claude | `app/5-prototipo-so-claude-code.png` |
| 6 | Ledger (R12) | O painel de custo da SPEC-031 mostrou "custo indisponível · 12 mil tokens (Codex)", com origem Verificação | `app/6-uso-codex-no-ledger.png` |
| 7 | Projeto (planner, Visão) | Rodou no Codex. O plano foi preenchido, e a linha `Codex · gpt-6.1-terra · …` apareceu no painel lateral | `app/7-projeto-codex.png` |
| 8 | Modelo sem imagem (R6) | Com `gpt-6-luna`, o app não enviou o turno e avisou "O modelo gpt-6-luna do Codex não lê imagens.", com **Enviar sem os prints** e **Usar o Claude Code desta vez**. Em "Enviar sem os prints", o turno seguiu no Codex sem `image` no `turn/start` | `app/8-modelo-sem-imagem.png` |
| 9 | Codex sem login (R11) | `account/read` sem conta. A mensagem foi "O Codex não pôde rodar esta execução · Codex sem autenticação…", com **Tentar de novo** e **Usar o Claude Code desta vez**. A preferência continuou Codex | `app/9-codex-sem-login.png` |

"Usar o Claude Code desta vez" não foi clicado no app, para não gastar a cota do Claude. O efeito do botão está coberto em `test/features/settings/provider_kind_card_test.dart`: a escolha vale para uma execução e a preferência não muda. A troca está coberta em `test/core/providers/structured_run_test.dart`.

## Achados corrigidos durante o E2E

- As opções do cartão ocupavam a largura toda. Agora cada opção tem a largura do próprio texto.
- O texto do botão "Usar o … desta vez" tinha pouco contraste sobre o âmbar. Agora usa `onAmber`.
- No painel estreito do Projeto, a linha do provedor cortava os tokens. Agora quebra em até 2 linhas.

## Limites conhecidos

- **Sandbox.** Nesta máquina, o sandbox real do Codex não sobe (AppArmor, decisão 15). O app recusa execuções estruturadas no Codex quando a sondagem acusa "Sandbox do Codex indisponível", com a mesma mensagem do Prompt, e oferece o Claude Code desta vez. O E2E usou um Codex falso cujo `command/exec` passa.
- **MCP do usuário.** O app-server sobe com `-c mcp_servers={}`, como pede o R2. A SPEC-093 mostrou que isso não desliga os servidores do `config.toml` do usuário nem o `codex_apps`. O certo é `mcp_servers.<nome>.enabled=false` para cada servidor, mais `features.apps=false`, e isso fica para a SPEC-105.
- **Duração por rodada (P4).** A duração vai para o log de depuração (`planner: codex · gpt-6.1-terra · 72 s`). Não existe coluna em `usage_entries`, e esta spec não migra o banco.
