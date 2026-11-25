# SPEC-101 · E2E de Executar spec com o Codex no app isolado

Data: 22/11/2026. Build release da branch `spec/101-executar-spec-codex`, Xephyr `:5` a 1366×768, `XDG_DATA_HOME` num diretório temporário. Os dados reais do usuário (`~/.local/share/promptorium`, `~/.codex`, `~/.claude`) não foram tocados.

## Sem turno pago do Codex

Nenhum turno real do Codex foi gasto. No `PATH` do app ficou um **Codex falso** (script Python, no molde dos E2E das SPECs 096 e 100). Ele responde à sondagem e ao App Server (`initialize`, `account/read`, `account/rateLimits/read`, `model/list`, `command/exec`, `thread/start|resume`, `turn/start`). Em cada turno de escrita, o falso:

- lê a etapa pedida em "ETAPA CONCLUÍDA: Rn";
- cria `rn.txt` com um `fileChange`;
- roda `git add -A && git commit` de verdade no worktree, com o ambiente que o app passou ao App Server;
- responde com o marcador e manda um `thread/tokenUsage/updated` (48 mil por turno, janela de 400 mil).

Na R2, o falso deixa um `quebrado.txt`, e o gate do projeto (`test ! -f quebrado.txt`) reprova. No reenvio, ele corrige e commita.

Projeto de teste: `loja-api`, com a SPEC-031 · Pagamento com Stripe (3 etapas e um subagente `spec-reviewer`). O config do projeto tem `agente: spec-implementer`, `verificacao.tentativas: 1` e `git.marcar-commits-de-agente: true`. Rodapé no Codex, "Executar spec" seguindo o rodapé, uma etapa por sessão e limite de continuação de 150 mil.

## Resultado

| # | Fluxo | O que se viu | Print |
|---|---|---|---|
| 1 | Executar (diálogo) | Provedor **Codex**, modelo `gpt-6.1-terra` do catálogo, esforços do modelo (low/medium/high), modo **Editar**. Automático com **Só Claude Code** e a dica; Agente `spec-implementer` com **Só Claude Code**; o aviso de que a spec fica no Codex até o Review | `app/1-executar-codex.png` |
| 1b | Modos | Só **Editar** e **YOLO · só em worktree**; Perguntar e Planejar não aparecem | `app/1b-modos-codex.png` |
| 2 | Quadro | Card com o selo **Codex** ao lado do robô, o balão "quer editar Edit r1.txt · pedido do Codex" e a aprovação | `app/2-quadro-codex.png` |
| 3 | Continuação (R10) | "R2 continua nesta sessão (contexto 48 mil de 400 mil, limite efetivo 150 mil)" na mesma thread | `app/3-sessao-etapa.png` |
| 4 | Gate e reenvio (R9) | Gate da R2 reprovado (testes), "Reenvio 1 de 1" na mesma sessão Codex, commit "SPEC-031 R2: correção do gate", gate aprovado e "R3 vai para uma sessão nova: a verificação precisou de reenvio" | `app/4-sessao-reenvio.png` |
| 5 | Início | "Orçamento do dia: indisponível" e "Hoje · Custo: indisponível": o Codex não soma US$ 0 | `app/5-orcamento-dia.png` |
| 6 | Autopilot com cota em 92% (R14) | "Executar tudo" com a SPEC-032 não abriu sessão e notificou "Autopilot parado: cota do Codex em 92% (janela de 5 h)…" | `app/6-autopilot-cota.png` |

Outras conferências, pelo banco isolado e pelo git do worktree:

- **Sessões:** as duas são `codex · gpt-6.1-terra · medium · acceptEdits`, sem `agent_name`. A primeira fez R1 e R2, e a segunda fez R3.
- **Timeline:** "O agente spec-implementer e os subagentes desta spec são só do Claude Code; o Codex executa sem eles." apareceu uma vez, só na primeira sessão. "Vigia de segredos sem hook nesta sessão (Codex)" também apareceu.
- **Commits (R11):** os quatro levam `Promptorium-Agente: gpt-6.1-terra · SPEC-031 R…`. O App Server recebeu `PROMPTORIUM_AGENTE=gpt-6.1-terra`.
- **`spec.<id>.provider` (P1):** foi gravado no Executar e removido quando a spec chegou ao Review.
- **Fim:** a SPEC-031 chegou ao Review só com o Codex. Nenhum processo do Claude foi aberto.

## Limites conhecidos

- **Sandbox (decisão 15).** Nesta máquina, o sandbox real do Codex não sobe. O falso responde ao `command/exec` como se o sandbox funcionasse, para mostrar o modo Editar. Sem sandbox, o diálogo deixa só o YOLO, com o aviso (teste de widget). A recusa de commit pelo sandbox (R8) está coberta em teste de unidade com a saída real do `bwrap`/Landlock.
- **Commit sem trailer (R11).** Neste E2E, o ambiente chegou ao git. O aviso "Commits desta etapa sem o trailer do agente" está coberto em `test/features/board/spec_runner_codex_test.dart`.
- **Corrigir CI e conflito (R9, R13).** Não foram disparados no E2E, porque não há PR remoto. Os dois mandam a mensagem para a sessão da spec, que retoma no próprio provedor.
