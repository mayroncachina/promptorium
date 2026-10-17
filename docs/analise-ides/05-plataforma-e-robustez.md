# 05 — Plataforma e robustez

Itens que não aparecem numa demo, mas separam "funciona no meu PC" de "IDE que o time usa o dia
inteiro". Muitos já estão em `debito-tecnico.md`; aqui vai o que a comparação acrescenta e a ordem
que eu sugiro.

## 5.1 Estado durável

| Hoje | Proposta |
|---|---|
| Autopilot, rascunho do Review, fila de avisos ao agente e abas do Código em memória | Tudo no banco (`autopilot_state`, `review_drafts`, `pending_notices`, `open_tabs`) e restaurado no splash |
| Sessão viva vira "interrompida" ao reabrir | Retomar automática das sessões de spec com Autopilot ligado (ver 03 §3.7) |
| `session_events` sem `stream_event`/thinking | Gravar thinking recolhido (DT-20) e o custo do PTY `--resume` (DT-17: ler o `.jsonl` da transcrição é anti-padrão; alternativa é desencorajar o terminal e cobrir tudo pela timeline) |

## 5.2 Banco e migrações (DT-16)

Schema já está na v8+ com `onUpgrade` manual. Antes de crescer mais: `drift_dev schema dump` por
versão + `stepByStep` + teste gerado de migração v1→vN. Backup automático do `.sqlite` antes de
migrar (`promptorium.sqlite.bak-v8`) e "Restaurar backup" em Configurações. É barato e evita o pior
cenário (usuário perde o histórico de specs numa atualização do `.deb`).

## 5.3 Disco e arquivos

- **Observar o disco** (`inotify` via `FileSystemEntity.watch`) para `specs/`, `.claude/agents`,
  `.claude/skills`, `.promptorium/` e a árvore do Código (DT-32, DT-42): o Claude Code CLI edita
  arquivos e a tela só vê 10 s depois ou ao reabrir.
- **Gravação atômica** (DT-44): escrever em `arquivo.tmp` no mesmo diretório e `rename`; copiar
  o modo com `stat` + `Process.run('chmod')` quando diferente do padrão. Perder permissões é
  raro; truncar um arquivo é pior.
- **Lock de spec**: um arquivo de spec editado fora do app enquanto a spec roda deve gerar aviso no
  cartão ("arquivo mudou no disco") e bloquear o avanço automático até confirmar.

## 5.4 Processos

- **Supervisão dos processos `claude`**: registrar PID por sessão no banco; no splash, matar órfãos
  da execução anterior (hoje um app que caiu pode deixar `claude -p` rodando e gastando).
- **`claude mcp list` em segundo plano** depois do splash, com cache por workspace (DT-46, DT-48),
  e nunca na abertura da tela.
- **Timeouts** com `SIGTERM` → `SIGKILL` já existem no MCP; aplicar o mesmo padrão ao gate de testes
  e ao "preparar worktree" (02 §2.2).

## 5.5 Segredos e segurança

- MCP `add` com segredos pelo argv (DT-45): usar `claude mcp add-json` lendo de arquivo `0600`
  temporário; mascarar tudo que não for flag conhecida.
- **Sandbox de comandos**: hook `PreToolUse` com lista de bloqueio (03 §3.1) + o modo "sem
  perguntar" só com worktree (nunca na raiz) — hoje o aviso existe; a trava não.
- **Isolamento do worktree**: o CLI 2.1.222 corrigiu subagentes executando git destrutivo contra o
  checkout principal; conferir a versão mínima (README diz ≥ 2.1.300, ok) e bloquear no hook
  `git -C <raiz>` / `git worktree remove` vindos de uma sessão de spec.

## 5.6 Modo Perguntar e ferramentas

Lista de bloqueio fixa (DT-25) → lista de permitidos (`--tools`) + `--strict-mcp-config` no
Perguntar e no planner. Ferramentas MCP novas entram como "Pedir" por padrão. Reavaliar a cada
atualização do CLI vira desnecessário.

## 5.7 Provedores: ACP como interface

DT-08 prevê `AgentProvider` traduzindo cada CLI para `ClaudeEvent`. O Zed resolveu o mesmo problema
com o **Agent Client Protocol** (ACP), que Claude, Codex, Copilot, Cursor, OpenCode e Devin já falam.
Sugestão: quando chegar a hora do multi-provedor, implementar **um** cliente ACP no app em vez de
um tradutor por CLI; o Claude Code continuaria por stream-json (mais rico: aprovações, uso do
plano, hooks). Isso também abre o caminho inverso: o Promptorium como *agent server* ACP para o
Zed/VS Code usarem o Quadro. Fase tardia; registrar a decisão agora evita construir dois tradutores.

## 5.8 IDE básica

Sem isso o usuário sai para o VS Code no meio do fluxo (e perde os avisos ao agente):

- Painel Git mínimo na tela Código: status, stage, commit, branch atual (DT-01) — o merge já usa
  tudo isso por baixo.
- Busca global Ctrl+Shift+F no worktree (DT-02) com `rg` se existir, senão Dart.
- Paleta Ctrl+K real (DT-12): telas, specs por código, sessões, "Executar SPEC-003", "Aprovar
  pendente".
- Diagnósticos: começar por rodar `lint:` do `config.yml` ao salvar e listar na aba Problemas
  (DT-04); LSP fica para depois.
- Central de notificações (DT-05): histórico do que o app notificou, com "ir para".

## 5.9 Empacotamento e atualização

`.deb` + `tar.gz` existem. Adicionar **Flatpak** (Flathub é onde usuário Linux procura) e
**verificação de versão nova** ao abrir (GitHub Releases API, sem auto-update) com link da release.
`claude --version` mínimo já é checado no splash; mostrar também "versão recomendada" porque hooks e
flags novos dependem dele.

## 5.10 Testes do próprio Promptorium

284 testes com CLI falso + 3 de integração. Para o que este documento propõe, falta um
**"CLI falso com roteiro"** que simule: hook bloqueando, gate falhando, sessão que cai no meio,
marcador sem commit. E uma suíte de integração por fluxo (spec de 2 etapas com gate e revisor
automático, haiku, poucos centavos) rodando num workflow manual do GitHub Actions, não a cada PR.
