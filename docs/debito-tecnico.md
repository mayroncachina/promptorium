# Débito técnico — Promptorium

Itens identificados durante o desenho dos mockups (2026-10-14) e ao longo das fases 1–12 que **não**
entraram no MVP, mas são necessários para o Promptorium ser uma IDE robusta. Itens riscados foram
resolvidos (a fase está indicada). Revisado na Fase 12 (2026-10-15).

Mockups: https://claude.ai/artifact/SjkEe4XHWMvccd1VaQGAua

| # | Item | Prioridade | Observações |
|---|------|-----------|-------------|
| DT-01 | **Painel Git** — status, stage, commit, branches, histórico | Alta | Hoje só existe o Review no fim do fluxo |
| DT-02 | **Busca global e substituição** (Ctrl+Shift+F) | Alta | Buscar em todos os arquivos do worktree |
| DT-03 | **Tela de Configurações** | Alta | Engrenagem já existe na barra lateral, sem tela. Caminho do CLI, tema, atalhos, provedores, orçamento padrão |
| DT-04 | **Diagnósticos via LSP** (erros e avisos no editor, aba "Problemas") | Média | No MVP pode ser só `flutter analyze`. Fase 10: aba "Problemas · 0" existe como stub |
| DT-05 | **Central de notificações** e **folha de atalhos** | Média | Histórico de "sessão terminou", "aprovação pendente" |
| DT-06 | **Checkpoints** — voltar o worktree para antes de uma alteração do agente | Média | |
| ~~DT-07~~ | ~~Uso do plano (5h / semanal) no rodapé~~ | — | **Resolvido na pesquisa:** vem no evento `rate_limit_event` do stream-json. Entra na Fase 5 |
| DT-08 | **Múltiplos provedores** (Codex, Gemini CLI) | Baixa | Codex: ver [DT-56](#dt-56--integracao-codex). Fase 6: interface `AgentProvider` + registro com Codex/Gemini CLI como "em breve" (desabilitados); ícone do botão segue o provedor ativo. Falta a implementação: cada provedor precisa traduzir sua saída para `ClaudeEvent` (vocabulário da timeline) e ter sua própria noção de modo somente leitura |
| DT-09 | **Ícone: arte vetorial / bordas** | Baixa | Fase 1 gerou os PNGs recortando `icon.webp` (1254px) com máscara de cantos arredondados aproximada via ffmpeg (raio ≈ 200px). Ideal: SVG de origem + ícone simbólico para o painel |
| ~~DT-10~~ | ~~Instalação desktop (`.desktop` + ícones hicolor)~~ | — | **Resolvido na Fase 12:** `scripts/install.sh` (bundle em `~/.local/share/promptorium/app/`, link `~/.local/bin/promptorium`, `.desktop` com `Exec` absoluto, ícones hicolor 32–512, caches; idempotente, nunca toca o banco) e `scripts/uninstall.sh`. `desktop-file-validate` OK. Falta: pacote do sistema (deb/Flatpak/AppImage) e ícone simbólico (DT-09) |
| DT-11 | **Splash em janela própria** (720×440, sem decoração) | Baixa | Fase 2 desenha o cartão 720×440 dentro da janela 1440×900. Redimensionar via `window_manager` (`setSize`/`setTitleBarStyle`) exige mexer também no runner GTK, que já abre em 1440×900 |
| DT-12 | **Paleta de comandos real** (Ctrl+K) e busca de arquivos (Ctrl+P na tela Código) | Média | Fase 2 só tem um stub com "Ir para …" de cada tela. **Fase 10:** Ctrl+P "Ir para arquivo" feito na tela Código (fuzzy simples, só o worktree selecionado); Ctrl+K continua stub |
| ~~DT-13~~ | ~~Persistir zoom por editor e última tela ativa~~ | — | **Resolvido na Fase 3:** `app_settings` (`editor.zoom.<editor>`, `ui.lastSection`) |
| ~~DT-14~~ | ~~Seletor de workspace na barra de título~~ | — | **Resolvido na Fase 3:** lista/seleciona/remove/adiciona pasta git; ativo em `app_settings` (`workspace.active`). Branch atual no botão: Fase 4 |
| DT-15 | **Seletor de pasta nativo** ao adicionar workspace | Baixa | Fase 3 usa campo de texto com caminho (sem pacote de file picker). Avaliar `file_selector` (registrar na tabela 0.4) |
| DT-16 | **Migrações do banco** | Média | Fase 5 subiu para v2 e a Fase 6 para v3 com `onUpgrade` manual (`addColumn`/`createTable`) + testes v1→v3 e v2→v3 com SQL escrito à mão. Falta `drift_dev schema dump` + `stepByStep` e testes gerados |
| DT-17 | **Terminal interativo fora da timeline** | Média | O que acontece em `claude --resume` no PTY não vira `session_events` (só seria visível lendo a transcrição `.jsonl`, formato interno — anti-padrão 0.5). Custo/tokens dessa parte não entram no banco |
| DT-18 | **Fork sem alterações não commitadas** | Média | Fork cria worktree a partir da branch do pai; arquivos sujos do pai não são copiados (a conversa do fork "acha" que estão lá). Avaliar `git stash create` + `stash apply` no novo worktree |
| DT-19 | **Mudar modo de permissão com a sessão viva** | Baixa | Hoje só vale ao retomar. Verificar se o stream-json aceita `control_request` `set_permission_mode` (não listado na 0.2) |
| DT-20 | **Thinking e deltas no log** | Baixa | `stream_event` não é gravado; blocos `thinking` não aparecem na timeline (só no log bruto, quando vêm no `assistant`) |
| DT-21 | **Excluir sessão / limpar worktrees** | Média | Fase 9: o merge do Review remove worktree e branch. Continua sem excluir sessão nem descartar worktree/branch de sessão abandonada (sem merge) |
| DT-22 | **Composer: `/comandos`, `@arquivos`** | Média | Fase 6 fez `@`/`/` no composer do **Prompt**; o composer de Sessões ainda não tem (extrair o seletor para reuso). "Anexar spec" feito na Fase 8 |
| ~~DT-23~~ | ~~Configurações por agente na sessão~~ | — | **Resolvido na Fase 7:** `SessionManager` passa `--max-budget-usd` (`agent_settings.budgetUsd` do escopo efetivo) e `--max-turns` (`maxTurns` do frontmatter) em create, `--resume` e fork; a Nova sessão pré-seleciona o `permissionMode` do agente. MCPs do agente ficam no frontmatter (`mcpServers`) — efeito com `--agent` não verificado (DT-31) |
| DT-24 | **Notificações: conferência manual** | Baixa | Clique da notificação depende do servidor de notificações (libnotify/GNOME); verificar no desktop real. Sem agrupamento/histórico (ver DT-05) |
| DT-25 | **Modo Perguntar: lista fixa de ferramentas bloqueadas** | Média | `--disallowedTools` com 10 nomes da 2.1.300 (4 testados ao vivo). Ferramentas novas de versões futuras do CLI não são bloqueadas. **Fase 11:** ferramentas MCP podem ser marcadas Bloqueado (`--disallowedTools mcp__srv__tool`, vale também no Perguntar) e o Perguntar ignora Permitido (continua pedindo aprovação); MCP sem regra ainda passa por aprovação inline. Reavaliar a cada atualização do CLI; alternativa: `--tools Read,Glob,Grep,…` e/ou `--strict-mcp-config` no Perguntar |
| DT-26 | **Planejar não é somente leitura** | Média | `--permission-mode plan` grava o plano em `~/.claude/plans/` sem pedir e, se o usuário aprovar `ExitPlanMode`, sai do modo plano e pode editar. Avaliar negar `ExitPlanMode` automaticamente no Planejar (ou trocar o modo da conversa para Editar ao aprovar) |
| DT-27 | **Conversas: gestão e avisos** | Baixa | Sem renomear/excluir/buscar conversa; aprovações pendentes da conversa não geram notificação nativa nem aparecem na fila de Sessões; mudar modo/modelo reinicia o processo (`--resume`) no próximo envio |
| DT-28 | **"Transformar em spec" sem resumo por IA** | Baixa | O corpo é a conversa cortada (600/1500 caracteres por mensagem) + seções vazias. Gerar com o planner (`--json-schema`) na Fase 8 |
| DT-29 | **"Continuar como sessão" — conferência manual** | Baixa | Coberto por teste com CLI falso; o fork de uma sessão iniciada na raiz para um worktree (`--resume` de outro cwd) só foi sondado separadamente na Fase 5 |
| DT-30 | **Editor de agentes: prompt sem editor de código** | Baixa | Prompt de sistema é `TextField` multilinha mono (sem realce Markdown, busca ou zoom). O componente `AppCodeEditor` (Fase 8, `lib/ui/widgets/code_editor/`) já existe — falta trocar. Sem “Adicionar” MCP manual (só chips dos nomes configurados) e sem `disallowedTools`/`color`/`effort` na UI (preservados no arquivo) |
| DT-31 | **Frontmatter com `--agent`: o que o CLI aplica** | Média | Sondado sem custo (2.1.300): `tools` e `model` aplicados; `permissionMode` **não** (o app passa `--permission-mode`). `maxTurns` e `mcpServers` não verificáveis sem chamar o modelo — `maxTurns` é repassado como `--max-turns`; `mcpServers` não é repassado. Semântica de `--max-budget-usd` no `--resume` (custo cumulativo da linhagem?) também não verificada. `claude agents --json` lista sessões, não definições |
| DT-32 | **Specs: gestão de arquivos** | Baixa | Sem renomear/excluir spec pela UI, sem observar o disco (arquivo editado fora só aparece ao reabrir a tela), linha de spec cujo arquivo sumiu fica no banco. "Transformar em spec" (Prompt) ainda sem resumo por IA (DT-28) |
| DT-33 | **Kanban: extras do mockup** | Média | Sem "Ver grafo de dependências", sem linha ao vivo da ferramenta em execução no card (`Bash · flutter test`), ordem dentro da coluna não é persistida, sem editar tarefa (só mover/excluir), sessão com falha deixa a tarefa em Em execução |
| DT-34 | **Planner** | Média | Usa `--append-system-prompt` (não `--agents planner`); um agente `planner` do projeto não é usado. Modelo = padrão do CLI e orçamento fixo US$ 0,50 (sem UI). Tarefas regeneradas não deduplicam semanticamente (o prompt lista as existentes). Rastreabilidade mostra o commit de merge desde a Fase 9 (commits intermediários / PR não aparecem) |
| DT-35 | **Refinar com IA no modo Editar** | ~~Baixa~~ Resolvido (F8) | A conversa de refino agora usa o modo interno `refine` → `--permission-mode default` sem `--disallowedTools`: leitura livre, mas toda edição/comando pede aprovação inline na conversa (antes era `acceptEdits`, que permitia editar qualquer arquivo sem aprovação). O modo não aparece no seletor do Prompt. Teste dos args em `conversation_manager_test.dart` |
| DT-36 | **Review: estado só em memória** | Média | Comentários pendentes e hunks aceitos (`reviewDraftProvider`) somem ao fechar o app; sem histórico das rodadas de review; diff mostra um arquivo por vez (sem "todos os arquivos", lado a lado ou realce de sintaxe); sem comentário em arquivo binário |
| DT-37 | **Merge do Review: limites** | Média | Exige a raiz **já** na branch base (não faz checkout); arquivos não rastreados na raiz não bloqueiam (se o merge os sobrescrever, o git recusa e a mensagem aparece); `worktree remove --force` descarta arquivos ignorados do worktree; o commit pendente roda os hooks do usuário; em conflito o commit pendente é desfeito com `reset HEAD~1` (o que estava *staged* volta como não *staged*); sem rebase/squash nem "resolver conflito" na UI |
| DT-38 | **Criar PR: conferência real pendente** | Média | `gh` não instalado na máquina de desenvolvimento — só testado com runner falso e remote bare local. Não verifica `gh auth status` antes; sem PR rascunho/revisores; se o push for rejeitado (branch remota divergente) só mostra o erro |
| DT-39 | **Lista "Aguardando review" roda git a cada mudança** | Baixa | `reviewQueueProvider` recalcula (status + `rev-list`) para cada sessão candidata sempre que `sessions`/`tasks` emitem (custo/tokens atualizam a linha). Com muitas sessões concluídas, considerar cache por HEAD/mtime |
| DT-40 | **Código: marcas na margem aproximadas** | Baixa | Verde = diff contra o merge-base da sessão (na raiz, `HEAD`): inclui edições do **usuário** já salvas e não distingue autor. Âmbar usa prefixo/sufixo comuns — várias regiões editadas viram um bloco contínuo. Linhas removidas não aparecem (só adicionadas/alteradas) |
| DT-41 | **Aviso de edição ao agente** | Média | Não envia no meio do turno (stream-json durante turno não verificado — sondar e, se seguro, enviar na hora); entregue após o `result` como nova mensagem (gasta um turno). Fila só em memória (some ao fechar o app); sessão ociosa (não ativa) não é avisada; editar pelo terminal não avisa |
| DT-42 | **Código: árvore e editor** | Média | Sem observar o disco (árvore atualiza a cada 10 s e após ações); pasta vazia criada fora do app não aparece; sem "mostrar ignorados"; sem arrastar/soltar ou multisseleção; symlink que aponta para fora do worktree não abre. Abas não são restauradas ao reabrir o app; sem "Salvar tudo"; BOM UTF-8 é removido ao salvar; reload por mudança externa perde o histórico de desfazer |
| DT-43 | **Código: terminal** | Baixa | Um terminal por worktree, altura fixa (160 px, recolhível, sem redimensionar), sem abas de terminal; `flutter run -d linux` no terminal ainda não conferido manualmente no app |
| DT-44 | **Código: gravação não atômica** | Baixa | Salvar grava **no lugar** (`writeAsString(flush: true)`) para manter permissões/dono/hard links (Dart não tem `chmod` para copiar o modo num temporário + rename). Uma falha no meio (disco cheio, E/S) pode deixar o arquivo truncado: o erro aparece no toast "Falha ao salvar", a aba continua suja com o texto completo (basta salvar de novo) e a checagem de `mtime` mostra "mudou no disco" — não é silencioso, mas não há rollback automático |
| DT-45 | **MCP: segredos em argv e em argumentos** | Média | `claude mcp add -e K=V` / `-H` passa os valores pela linha de comando (visíveis em `ps` durante a execução). Args mascarados só por heurística (flag com `token/key/secret/passw/auth`); um token posicional aparece. Avaliar `add-json` via arquivo temporário 0600 ou stdin |
| DT-46 | **MCP: status e processos** | Média | `claude mcp list` sobe todos os servidores (health-check) a cada abertura por workspace (timeout 90 s; no timeout o processo recebe SIGTERM e, após 3 s, SIGKILL — filhos que ignorem o sinal podem sobrar). O CLI também grava metadados no `~/.claude.json` ao rodar. Sem "Desativar" (não há comando no CLI 2.1.300 — só remover), sem aprovar servidor de `.mcp.json` pendente pela UI (só `claude` interativo), sem login OAuth (`claude mcp login`), sem editar servidor (remover + adicionar) |
| DT-47 | **MCP: regras e inventário** | Baixa | Regras globais por nome de servidor (não por workspace/escopo) e não removidas ao remover o servidor; o planner (Fase 8) não aplica as regras; inventário depende do truque do `--model` inexistente (pode mudar em versões futuras) e não mostra a descrição das ferramentas (o init só traz nomes); log recente faz LIKE em `session_events` (custo cresce com o banco) e não inclui as conversas do Prompt |
| DT-48 | **Splash: passo "Conectando servidores MCP…" é stub** | Baixa | `claude mcp list` sobe todos os servidores (pode levar dezenas de segundos), por isso a Fase 11 roda só ao abrir a tela MCP; o rodapé mostra MCP depois do primeiro `system/init`/list. Avaliar rodar em segundo plano após o splash |
| DT-49 | **Bandeja não implementada** | Baixa | `tray_manager` 0.8.0 está no `pubspec.yaml` (tabela 0.4, "opcional"), mas nenhum código o usa. Implementar (ícone + menu: mostrar janela, sessões aguardando) ou remover a dependência |

## Requisitos de UX já decididos

### Editor (Specs e Código)
O editor usado para criar e editar specs — e o editor da tela de Código — precisa ser um editor de código de verdade:

- Realce de sintaxe (Markdown nas specs, Dart/YAML/JSON no código)
- Números de linha, busca e substituição no arquivo (Ctrl+F / Ctrl+H)
- **Zoom in / out**: Ctrl+= aumenta, Ctrl+- diminui, Ctrl+0 volta ao padrão; controle visível no topo do editor (− 100% +)
- Zoom salvo por editor (specs e código podem ter tamanhos diferentes)
- Modo dividido (fonte + visualização) nas specs

> Fase 8: implementado em `AppCodeEditor` (`lib/ui/widgets/code_editor/`) + tela de Specs; Ctrl+H substitui, Ctrl+S salva, controle `− 100% +` no cabeçalho.

## Conferência manual pendente (Fase 12)

Coberto por testes automatizados (CLI falso / repositórios temporários / sondas reais isoladas),
mas **não conferido à mão no app rodando** — nenhuma fase tirou capturas de tela nem usou o app
contra a configuração real do usuário:

| Item | Onde | Referência |
|---|---|---|
| Janela abre escura, título, ícone na barra de tarefas/menu após `scripts/install.sh` | desktop real | F1, DT-10 (binário instalado inicia — rodado 6 s com dados isolados) |
| Splash com `claude` ausente do PATH mostra o erro do primeiro passo | app | F2 |
| Notificação nativa de aprovação/sessão concluída e o clique que foca a janela | GNOME/libnotify | F5, DT-24 |
| Fechar e reabrir o app → sessão "interrompida" → Retomar mantém o histórico | app + CLI real | F5 |
| Terminal `claude --resume` na aba da sessão | app + CLI real | F5, DT-17 |
| "Continuar como sessão" (Prompt) com contexto da conversa | app + CLI real | F6, DT-29 |
| Ctrl+F / Ctrl+H no editor de specs e de código | app | F8 |
| Criar PR com `gh` instalado e autenticado | app + GitHub | F9, DT-38 |
| Terminal da tela Código rodando `flutter run -d linux` no worktree | app | F10, DT-43 |
| Tela MCP com a config real (`claude mcp list` sobe todos os servidores) | app | F11, DT-46 |

## Atualização — plano de melhorias (2026-10-17, branch `teste`)

Resolvidos ou reduzidos pelo [plano de melhorias](plano-melhorias-ides.md):

- **DT-01** Painel Git na tela Código (F13). **DT-02** Busca global Ctrl+Shift+F (F13; sem substituir).
  **DT-04** Aba Problemas com o `lint:` do projeto ao salvar (F13; não é LSP). **DT-05** Central de
  notificações (F13; sem folha de atalhos).
- **DT-06** Checkpoint por etapa (F3). **DT-12** Ctrl+K real (F10). **DT-16** Migrações geradas de v8 em
  diante + backup (F11). **DT-18** Fork leva as alterações sem commit (F4). **DT-19** Modo trocado com a
  sessão viva (F12).
- **DT-25** Perguntar com `--tools` + `--strict-mcp-config` (F12). **DT-32** Specs observadas no disco
  (F11). **DT-33** Linha ao vivo, grafo, ordem persistida, falha de sessão (F9).
- **DT-36** Rascunho do Review persistido, todos os arquivos, lado a lado, realce, rodadas (F3, F6).
- **DT-37** Squash/rebase e "resolver conflito" (F16). **DT-38** `gh auth status` e PR rascunho (F6).
- **DT-41** Avisos no meio do turno e persistidos (F3). **DT-42** Watch de disco no Código (F11).
  **DT-44** Gravação atômica (F11). **DT-45** Mascaramento mais rígido (F12; argv continua, ver pesquisa).
  **DT-48** `mcp list` em segundo plano depois do splash (F12). **DT-08** Provedores ACP (F18).

Novos:

| Item | Descrição | Prioridade | Notas |
|---|---|---|---|
| DT-50 | **Hooks dependem de `python3`** | Baixa | Sem `python3`, os hooks gerenciados ficam desligados (aviso em Automações). Alternativa: executável Dart compilado junto |
| DT-51 | **Cliente ACP sem agente real** | Média | Testado com processo falso. Conferir com `gemini --experimental-acp` (Node 20 ou mais novo) e outros agentes ACP |
| DT-52 | **Flatpak não testado** | Média | Manifesto e wrapper escritos sem `flatpak-builder` |
| DT-53 | **`spec_runner.dart` grande** | Baixa | ~1500 linhas (gate, checkpoint, A/B). Separar em arquivos por assunto |
| DT-54 | **Babysit de PR: comentários por linha** | Baixa | `gh pr view --json` não traz comentários de linha (precisa de `gh api …/pulls/N/comments`) |


## DT-55 — Integração completa do Review no GitLab

**Prioridade: média. Adiado em 21/10/2026 por decisão de escopo.**

A detecção de GitHub, GitLab e outros hospedeiros, seleção da CLI correta e orientação de instalação/autenticação passam para a [SPEC-014](specs/SPEC-014-deteccao-de-hospedagem-e-cli.md). A [SPEC-013](specs/SPEC-013-review-no-gitlab.md) conserva o desenho técnico da integração de MR para retomada futura.

Pendências transferidas:

- Completar o contrato `ReviewHost` e extrair o comportamento GitHub para `GithubHost`, preservando os fluxos existentes.
- Persistir `sessions.pr_host` com migração e compatibilidade das sessões antigas.
- Implementar R3–R6 da SPEC-013: criar MR, acompanhar estado e comentários, mostrar discussões em linha, pipeline e bloqueios no painel, e mergear conforme os métodos permitidos pelo projeto.
- Tratar merge agendado sem fechar sessão/spec/worktree antes de confirmar `MERGED`.
- Validar comandos, campos, paginação e capacidades da versão instalada com um projeto/MR real no GitLab; considerar `glab api` quando não houver saída JSON no comando de alto nível.
- Cobrir os contratos com testes e executar a validação manual completa em GitLab.com e a validação aplicável a instância própria.

A sondagem de `glab` 1.36.0 registrou token inválido em gitlab.com e ausência de `mr view --output json`. São problemas distintos do remote deste repositório, que é GitHub. Não exigir acesso ao GitLab para validar fluxos GitHub ou entregar a SPEC-014. O aceite do DT-55 retoma os critérios operacionais da SPEC-013; instalar/autenticar `glab` isoladamente não conclui a integração.

## DT-56 — Integração Codex

**Prioridade: baixa. Desligada em 22/10/2026 por decisão de escopo: foco no Claude Code.**

O adaptador do Codex App Server (`lib/core/codex/`), o contrato `AgentProvider`/`AgentEvent`, as políticas de permissão e o YOLO continuam no código, mas `codexEnabledProvider` (`lib/core/providers/agent_registry.dart`) vale `false`. Com isso o registro lista Codex como “em breve” (`ComingSoonProvider`), os seletores de Nova sessão, Executar spec e rodapé mostram só Claude Code e os agentes ACP, a disponibilidade não sonda o CLI e um padrão `codex` salvo resolve para Claude. Sessões Codex já salvas não retomam e informam que o Codex está indisponível. Os testes do adaptador ligam o interruptor e continuam na suíte.

As SPEC-002 a SPEC-005 ficam em `rascunho`. A SPEC-006 e a SPEC-007 permanecem concluídas, mas a parte Codex delas fica inativa enquanto o interruptor estiver desligado. A auditoria de 22/10/2026 encontrou o seguinte, a retomar antes de religar:

- **Bloqueios práticos:** projeto, design, skills e review automático enviam `maxBudgetUsd` (e o revisor, `agent`/modelo Claude), que o Codex recusa ao iniciar; Nova sessão e Executar spec aplicam modelo/esforço Claude com Codex selecionado; imagens são recusadas com modelo `inherit`.
- **Opções ignoradas ou enfraquecidas:** hooks gerenciados não rodam em sessões Codex; custo ausente vira US$ 0; `dontAsk` vira “executar sem perguntar”.
- **SPEC-002:** interrupção do turno sem ligação na UI; cancelamento gravado como falha; processos filhos sem grupo de processos; fork sem vínculo estruturado com a sessão pai; “aprovar no escopo” ausente; testes de aprovação, deltas, erro JSON-RPC e fixtures Codex/ACP.
- **SPEC-003:** padrão global em Configurações e override do projeto; preferências de modelo/esforço Codex; provedor nas listas, timeline e notificações; transferência explícita ao trocar de provedor; `runConfig` materializado para conversas e sessões Claude.
- **SPEC-004:** orçamento, turnos, agentes, skills, MCP, ferramentas e modo auto sem equivalente comprovado; cada linha da matriz precisa de sondagem registrada em `docs/pesquisa/`.
- **SPEC-005:** duelo com provedor por lado; provedor próprio do revisor; limpeza de `codex app-server` órfão; escritor único também no `SessionManager`.

Para religar: corrigir os bloqueios práticos, trocar o valor de `codexEnabledProvider` e retomar as specs na ordem do [README](specs/README.md).
