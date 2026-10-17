# 03 — Sessões, agentes e o que o CLI já oferece

O Promptorium é um *front* do Claude Code CLI (`stream-json` + aprovações por stdio). Boa parte do
que as IDEs fazem de "robusto" o CLI já entrega e o app ainda não usa: hooks, checkpoints,
subagentes com isolamento, memória, agendamento. Esta parte lista o que aproveitar.

## 3.1 Hooks gerenciados pelo app

O CLI dispara hooks em `SessionStart`, `UserPromptSubmit`, `PreToolUse` (pode bloquear),
`PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `Stop`, `SessionEnd` e eventos de
worktree/compactação (ver docs de hooks). Kiro vende isso como "on save → gerar testes, pre-commit
→ scan de segurança".

**Proposta.** O app gera, para cada sessão, um `settings.json` temporário (passado por `--settings`)
com hooks que o Promptorium controla, sem tocar o `~/.claude/settings.json` do usuário:

| Evento | O que o app faz | Substitui |
|---|---|---|
| `PostToolUse` (Edit/Write) | roda `formatar:` do `config.yml` no arquivo (ex.: `dart format`) | pedir "formate o código" no prompt |
| `PreToolUse` (Bash) | bloqueia padrões perigosos (`git push --force`, `rm -rf /`, checkout na raiz) com mensagem ao agente | confiar só no modo de permissão |
| `PreToolUse` (Edit/Write) | checkpoint leve (ver 3.2) | DT-06 |
| `Stop` | gate de verificação da etapa (ver 02 §2.1) — devolve "testes falharam" ao agente antes de ele terminar | reenviar mensagem depois do `result` (gasta um turno) |
| `PermissionRequest` | regras por ferramenta já existentes da tela MCP, aplicadas também a Bash/Edit | lista fixa do modo Perguntar (DT-25) |
| `SessionEnd` | grava custo/tokens finais mesmo quando o app cai | perda de dados |

**Interface.** Em Configurações → "Automações": lista dos hooks gerados, ligar/desligar cada um,
"ver último resultado". Em `config.yml`: `formatar:`, `lint:`, `bloquear-comandos:`. Hooks do
próprio usuário (do `settings.json` dele) continuam valendo; o app só adiciona.

**Validar antes:** sondar que `--settings <arquivo>` com hooks funciona em `-p --input-format
stream-json` (anotar em `docs/pesquisa/`, como as outras sondas).

## 3.2 Checkpoints dentro da etapa

Com o hook `PreToolUse` em Edit/Write/MultiEdit o app pode gravar um snapshot sem interromper o
agente: `git stash create` (sem aplicar) ou cópia do arquivo em
`~/.promptorium/checkpoints/<sessão>/<n>/`. A timeline ganha um marcador "↶ voltar para aqui" em cada
card de edição; "Voltar" restaura os arquivos e, opcionalmente, faz fork da sessão naquele ponto
(`--resume` + mensagem "desfiz as edições a partir daqui porque …"). É o `/rewind` do Claude Code com
interface. Limite de tamanho e limpeza ao fechar a spec.

## 3.3 Subagentes: usar o isolamento do CLI

O `config.yml` já permite `subagentes: [{agente, quando}]`, injetados no prompt. O CLI suporta
`isolation: worktree` para subagentes e `Agent` em segundo plano. Duas melhorias:

- **Revisor por etapa** (padrão sugerido, desligável): no fim de cada etapa, um subagente
  `spec-reviewer` somente leitura compara o diff com o requisito `Rn` e os critérios; devolve
  "ok" ou uma lista de problemas que o agente principal corrige antes do marcador. Custo baixo
  (haiku), ganho alto. Ver 04 para a versão de spec inteira.
- **Timeline de subagentes com custo** e filtro "só o agente principal"; hoje aparecem aninhados
  mas sem custo próprio.

## 3.4 Best-of-N para etapas difíceis

Cursor 3 tem `/best-of-n`. No Promptorium cabe no cartão: "Executar etapa com 2 variantes" cria dois
worktrees temporários (`pr/spec-003-r3-a`, `-b`), roda a mesma etapa com modelos/esforços diferentes
(ou o mesmo), e o Review mostra os dois diffs lado a lado com "Escolher A/B". O escolhido vira o
commit da etapa; o outro worktree é descartado. Usar só quando a etapa falhou uma vez ou foi marcada
"difícil" na spec.

## 3.5 Memória do projeto

Windsurf (memórias), Claude Code (auto-memory) e Copilot (instructions) acumulam aprendizados.
O Promptorium tem `CLAUDE.md` do planner e nada entre sessões de etapas — cada etapa reaprende
"os testes rodam com X", "esse módulo é frágil".

**Proposta.** `.promptorium/memoria.md` (versionado, curto, no máximo ~60 linhas) alimentado por:

- o gate (2.1): "testes do projeto: `flutter test` leva ~40 s";
- o agente, via marcador `APRENDIZADO: …` na resposta (o app pede isso no prompt da etapa);
- o humano, editando.

Entra no prompt de toda etapa e no planner. Com botão "Limpar entradas antigas" (o risco citado nas
reviews do Windsurf: memória velha engana o agente). Mostrar quem gravou cada linha e quando.

## 3.6 Composer e modos

- `@arquivo` e `/prompt` no composer de **Sessões** (DT-22) — o do Prompt já tem; extrair o seletor.
- **Modo Perguntar por lista de permitidos** (`--tools Read,Glob,Grep,WebFetch,…`) em vez de lista de
  bloqueados (DT-25): ferramentas novas do CLI ficam fora por padrão.
- **Planejar**: negar `ExitPlanMode` automaticamente ou trocar a conversa para Editar ao aprovar
  (DT-26) — Copilot separa Plan/Implement de forma explícita; fazer o mesmo com um botão
  "Implementar este plano" que abre sessão/spec.
- **Thinking na timeline** (DT-20), recolhido por padrão.
- **Trocar modo com sessão viva**: sondar `control_request set_permission_mode` (DT-19).

## 3.7 Sessões longas e recuperação

- **Suspensão por inatividade** já existe; falta **retomar automática** ao chegar aprovação ou
  mensagem (hoje o usuário precisa clicar Retomar).
- Ao reabrir o app, sessões "interrompidas" de specs em Autopilot deveriam **retomar sozinhas** se o
  Autopilot estava ligado (persistir estado — ver 02 §2.6).
- **Fila de mensagens durante o turno** (DT-41): sondar envio de `user` no meio do turno; se seguro,
  avisos de edição e comentários do Review entram na hora.
- **Agendamento** (Claude Code desktop tem tarefas por hora/dia): "rodar Autopilot às 2h com orçamento
  X" cabe numa fase posterior; depende do app aberto, como no Claude Code.

## 3.8 Menos turnos por sessão

Cada reenvio de "os testes falharam" / "formate" / "faça commit" gasta um turno inteiro com a spec
no contexto. Com hooks (3.1) e gate (02 §2.1) a maior parte disso some. Medir: guardar por sessão
"turnos gastos em correção automática" e mostrar na aba de detalhes — vira o indicador de que o
fluxo está ficando mais robusto.
