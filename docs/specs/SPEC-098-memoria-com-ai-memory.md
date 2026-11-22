---
id: SPEC-098
status: concluida
versao: 0.24.0
tipo: integracao
epico: 332
relacionada: 83
issue: 337
depende-de: [SPEC-093, SPEC-094, SPEC-096]
---

# Memória com ai-memory

## Objetivo

Integrar o [ai-memory](https://github.com/akitaonrails/ai-memory) ao Promptorium como **integração opcional** (decisão 13 do épico #332): o app descobre se ele está instalado, liga os hooks e o MCP dele no Claude Code e no Codex com uma prévia, mostra as passagens pendentes do projeto com o dono de cada uma e abre o wiki. Quem não tem o ai-memory não vê diferença nenhuma.

O ai-memory é um binário Rust (MIT, versão 3.5.1 em 19/11/2026) que roda um servidor local (`127.0.0.1:49374`) e guarda a memória num wiki de markdown versionado com git. Os hooks de ciclo de vida de cada agente mandam o que acontece (pedidos, ferramentas, início e fim de sessão) para o servidor, sem chamar LLM. No fim de uma sessão ele grava uma **passagem** (*handoff*) com resumo, perguntas abertas, próximos passos e arquivos tocados. A próxima sessão, em qualquer agente, recebe essa passagem no `SessionStart` e a consome uma vez só. Cada passagem tem **dono** (quem a criou) e estado: aberta, aceita ou expirada.

Exemplo concreto:

> Você passa a manhã numa sessão do Claude no Promptorium refatorando `lib/core/spec_parser.dart`. A abordagem com regex falha nos testes de BOM e você troca para um leitor por linhas. Às 11h40 a cota de 5h acaba. Você abre uma sessão do Codex (SPEC-096) no mesmo worktree e ele começa do zero: não sabe que a regex já falhou nem que falta o teste de BOM.
>
> Com o ai-memory ligado, o fim da sessão do Claude grava a passagem "Parser trocado para leitor por linhas; falta `test/spec_parser_bom_test.dart`; regex descartada (falhava com BOM)". O Codex a recebe ao começar. No Promptorium, a aba **Memória** do projeto mostra a passagem enquanto ela está aberta, com "de Claude Code · 11h41 · dono: você".

Hoje há também um problema que existe **mesmo sem esta spec**: quem instalou o ai-memory por fora tem os hooks no `~/.claude/settings.json`. O app passa um `--settings` temporário, que **soma** às configurações da pessoa em vez de substituí-las. Por isso cada execução auxiliar do app (planner, verificador, revisor automático, títulos, decisões de etapa) dispara os hooks do ai-memory. Elas criam sessões falsas na memória e, pior, o `SessionStart` delas pode **consumir** a passagem que era da próxima sessão de verdade.

## Requisitos

### Detecção

- R1 · **Descobrir o ai-memory sem instalar nada.** Na abertura do app e ao pedir "Verificar de novo", procurar `ai-memory` no `PATH` e em `~/.local/bin`, rodar só `ai-memory --version` e perguntar ao servidor `GET /healthz` (endereço de `AI_MEMORY_SERVER_URL`, ou `http://127.0.0.1:49374` por padrão). Estados: **não instalado**, **instalado · servidor parado**, **versão antiga** (abaixo da mínima de P7), **conectado**. O app nunca instala, atualiza nem inicia o serviço do ai-memory. Para cada estado ruim mostra o que fazer, com o comando para copiar (`ai-memory setup`, `systemctl --user start ai-memory`, `ai-memory upgrade`).
- R2 · **Sem ai-memory nada muda.** Se o binário não existe, o app não roda processo extra, não passa variáveis novas aos agentes, não consulta nada em intervalo e não mostra nada novo nas telas de trabalho. A aba Memória do projeto continua igual à de hoje. Em Configurações aparece só um cartão "ai-memory · não encontrado", com o link do projeto.

### Ligar nos dois agentes

- R3 · **Estado da ligação por agente.** Em Configurações → Memória (ai-memory), um bloco para o Claude Code e outro para o Codex, cada um com **Hooks** e **MCP**: ligado, ausente ou desatualizado. O estado vem do próprio ai-memory (`ai-memory setup --plan --agent claude-code --agent codex`, que mostra o plano sem mudar nada) e não de uma leitura do app nos arquivos do agente. No Codex aparece também "aguardando confiança": o Codex pede para confiar nos hooks antes de rodá-los. O bloco do Codex só aparece quando o Codex está habilitado no app (SPEC-096).
- R4 · **Ligar com prévia.** "Ligar no Claude Code" e "Ligar no Codex" (e o atalho "Ligar nos dois") abrem uma prévia com os comandos que vão rodar (`ai-memory install-hooks --agent claude-code --apply` e `ai-memory install-mcp --client claude-code --apply`, ou os mesmos com `codex`), os arquivos que o ai-memory vai alterar (`~/.claude/settings.json`, `~/.claude.json`, `~/.codex/config.toml`, a pasta de hooks) e o aviso de que ele faz cópia de segurança com data ao lado de cada arquivo. Só depois da confirmação o app roda os comandos e mostra a saída. **O app nunca escreve nesses arquivos por conta própria**: quem escreve é o instalador do ai-memory, que só mexe no que é dele e pode ser rodado de novo sem efeito. O app não roda `install-instructions` nem `setup` completo, que mexeriam no `CLAUDE.md`/`AGENTS.md` do repositório ou em outros agentes.
- R5 · **Desligar.** "Desligar" de cada agente segue o mesmo caminho: prévia, confirmação e o desinstalador do ai-memory restrito àquele agente. Se a versão instalada não desinstala por agente, o app mostra o comando para a pessoa rodar e explica o que ele remove (P5).
- R6 · **Execuções do app não sujam a memória.** Quando o ai-memory está conectado, o app passa variáveis de ambiente por tipo de execução:
  - **auxiliares** (somente leitura e saída estruturada: planner, perguntas e design de spec, verificador, revisor automático, títulos, decisões e classificação de etapa, `vibe_guard`): sem captura e sem consumir passagem (`AI_MEMORY_CAPTURE_OWNER=promptorium`) e sem passagem automática no fim (`AI_MEMORY_AUTO_HANDOFF=off`);
  - **sessões de etapa** do Quadro: captura normal, sem passagem automática no fim (o app já passa o contexto de uma etapa para a outra) (P3);
  - **sessões livres e conversas do Prompt**: comportamento normal do ai-memory, com captura, passagem no fim e entrega no começo.
  Vale também para quem instalou o ai-memory por fora, mesmo antes de ligar pelo app. A sondagem confirma que essas variáveis fazem o que a documentação promete (ver Roteiro).
- R7 · **Codex dentro do app.** As execuções do Codex abertas pelo app (SPEC-096) precisam carregar os hooks e o MCP que o ai-memory gravou no `~/.codex`. Se o app isolar o `CODEX_HOME` (SPEC-093 R15, SPEC-103), ele replica as entradas do ai-memory no ambiente isolado ou desiste do isolamento quando o ai-memory está ligado. Nunca perder a captura em silêncio: se não der, o bloco do Codex mostra "Codex no app sem memória" com o motivo.

### Painel Memória no projeto

- R8 · **Duas seções na aba Memória.** A aba Memória do projeto ganha um seletor **Fatos do projeto** (o `.promptorium/memoria.md` de hoje, sem mudança) e **ai-memory**. A seção ai-memory só aparece com o ai-memory instalado. No topo, uma linha de estado: servidor, versão, o projeto do ai-memory que corresponde a este workspace (`workspace/projeto`) e a hora da última captura.
- R9 · **Passagens pendentes com dono.** Lista das passagens abertas do projeto, lida sem consumir (`memory_handoff_list`). Para cada uma: agente de origem (Claude Code, Codex ou outro, com o nome que o ai-memory informa), quando foi criada, **dono** ("você", "compartilhada" ou o usuário, quando o servidor é de time), origem (automática no fim da sessão ou manual) e diretório (o worktree, quando é um). Ao expandir: resumo, perguntas abertas, próximos passos e arquivos tocados. Um filtro "Mostrar aceitas e expiradas" mostra o histórico com quem aceitou e quando. A ordem é a mesma que o ai-memory usa para entregar: a manual primeiro, depois a automática mais nova do diretório, e um selo "será entregue à próxima sessão" na que ele vai entregar.
- R10 · **Sessão que terminou sem passagem.** Quando o ai-memory aponta uma sessão mais nova que não terminou nem deixou passagem (`newer_unended_session`, por exemplo uma sessão do Codex cortada pela cota), o painel mostra um aviso com o agente, a hora e o id curto, e explica que a próxima sessão vai ler essa sessão direto.
- R11 · **Ações sobre uma passagem.** "Copiar id"; "Continuar em…" leva à SPEC-099; "Descartar" marca uma passagem aberta como expirada (`memory_handoff_cancel`) depois de uma confirmação que diz que a ação não se desfaz. O painel **não aceita** passagens: quem aceita é a sessão do agente. Passagens de outro dono aparecem só com os metadados que o servidor libera, sem ações.
- R12 · **Atalho para o wiki.** "Abrir wiki" abre no navegador a página do projeto na interface web do ai-memory (`/web/w/<workspace>/<projeto>`), quando o servidor foi iniciado com a interface web. Sem ela, abre a pasta do projeto dentro do wiki no gerenciador de arquivos. Ao lado, contagens do `memory_briefing`: páginas, sessões e as cinco páginas mais recentes, cada uma abrindo no mesmo destino.

### Segurança e leveza

- R13 · **Texto da memória é dado, não instrução.** Resumo, perguntas e próximos passos vêm dos pedidos e das ferramentas da pessoa e são tratados como dado não confiável: o painel mostra texto puro (sem links ativos, sem markdown interpretado, sem executar nada) e nunca o manda para um modelo por conta própria. O app não lê nem mostra o token do ai-memory: as leituras passam pela CLI (`ai-memory call`), que se autentica sozinha. Logs do app guardam só o nome da ferramenta, o tempo e o código de saída.
- R14 · **Leve e tolerante a falhas.** A seção ai-memory atualiza ao abrir a aba, quando uma sessão do projeto termina e no botão "Atualizar". Sem consulta em intervalo. Cada chamada tem limite de 5 s; erro ou servidor parado vira uma linha de estado na seção, sem quebrar a aba nem as sessões. A detecção fica em cache até "Verificar de novo" ou até a próxima abertura do app.

## Fora do escopo

- Trocar o motor do app pelo ai-memory, ou migrar o `.promptorium/memoria.md` para o wiki. Os dois convivem; levar fatos de um para o outro fica para depois.
- Instalar, atualizar ou administrar o servidor do ai-memory (serviço, usuários, LLM, embeddings, servidor de time).
- Lançar as execuções do app por `ai-memory run` (SPEC-099 usa o `run` só no terminal embutido).
- Buscar na memória pelo app, editar páginas do wiki ou aceitar passagens pelo painel.
- `install-instructions` (bloco no `CLAUDE.md`/`AGENTS.md`) e `install-skills`.
- Outros agentes da matriz de suporte do ai-memory além do Claude Code e do Codex.
- Servidores remotos com login por OIDC: o app usa o que a CLI já tem configurado e mostra o erro dela quando não consegue.

## Decisões

- P1 · **Onde fica o painel.** (a) Seletor dentro da aba Memória (Fatos do projeto | ai-memory); (b) uma aba nova "ai-memory" no projeto. **Decidido:** (a). O pedido é "painel Memória no projeto", e a aba já existe com esse nome. Deixar as duas memórias lado a lado também ajuda a explicar a diferença entre elas.
- P2 · **Como o app lê o ai-memory.** (a) `ai-memory call <ferramenta> '<json>'` com o diretório do workspace como `cwd`: a CLI resolve o projeto e o token sozinha; (b) a API HTTP `/api/v1/.../handoffs`, com o app lendo o token. **Decidido:** (a), e HTTP só para o `/healthz`, que não pede token. Assim o app não toca em credenciais nem reimplementa a resolução de projeto (marcador `.ai-memory.toml`, remote do git, worktrees).
- P3 · **Passagem automática nas sessões de etapa.** **Decidido:** desligada (`AI_MEMORY_AUTO_HANDOFF=off`), com captura ligada. O Quadro já leva a memória e o contexto de uma etapa para a outra. Uma passagem por etapa empilharia batons que a próxima etapa consumiria no lugar da sessão livre da pessoa.
- P4 · **Como calar as auxiliares.** `AI_MEMORY_CAPTURE_OWNER` foi feito para um produtor externo de captura. Com ele, os hooks deixam de capturar e passam a entregar a passagem em modo oferta (`claim=0`), sem consumir. É o efeito que o app quer, mas por um caminho que não é o principal. **Decidido:** usar `AI_MEMORY_CAPTURE_OWNER=promptorium` mais `AI_MEMORY_AUTO_HANDOFF=off` e confirmar na sondagem. Se não funcionar, a alternativa é passar `--setting-sources project,local` nas auxiliares do Claude, que também tira os outros hooks da pessoa.
- P5 · **Desligar por agente.** A documentação mostra `ai-memory uninstall --apply`, que remove tudo o que o ai-memory instalou, de todos os agentes. **Decidido:** "Desligar" só roda o comando se a sondagem achar a forma por agente. Senão, o app mostra o comando completo com o aviso "remove de todos os agentes" e deixa a pessoa rodar.
- P6 · **Descartar pelo painel.** **Decidido:** permitir, com confirmação, só nas passagens abertas do próprio dono. É o caso "criei uma passagem por engano" que o ai-memory documenta.
- P7 · **Versão mínima.** **Decidido:** 3.1.0, a primeira com o histórico local da sessão anterior no `ai-memory run`, que a SPEC-099 usa. Abaixo dela, o estado é "versão antiga" e a ligação continua possível, com aviso.
- P8 · **Onde fica em Configurações.** **Decidido:** uma seção nova, "Memória (ai-memory)", no grupo do app, perto de "Provedores (ACP)" e de "Automações (hooks)".

## Design

### O que já existe

- `lib/features/project/project_memory.dart` e `widgets/project_memory_view.dart`: a aba Memória (fatos em `.promptorium/memoria.md`), que vira a seção "Fatos do projeto".
- `lib/features/project/project_screen.dart`: as abas Saúde, Configuração, Memória e Métricas.
- `lib/core/providers/provider_availability.dart`: padrão de detecção que só roda `--version` e status, com estados e mensagens.
- `lib/core/claude/readonly_run.dart` (`runReadOnlyClaude`) e `claude_process.dart`: onde o ambiente de cada execução é montado. As auxiliares já usam `strictMcpConfig`, mas os hooks da pessoa continuam valendo.
- `lib/core/claude/managed_hooks.dart` e `run_extensions.dart`: o `--settings` temporário, que soma às configurações da pessoa.
- `lib/features/settings/settings_sections.dart` e `providers_view.dart`: seções e cartões de Configurações.

### Componentes novos

| Arquivo | Papel |
|---|---|
| `lib/core/memory/ai_memory_cli.dart` | Detecção (R1), `--version`, `/healthz`, `setup --plan`, `install-*`, `call` com limite de 5 s e saída JSON |
| `lib/core/memory/ai_memory_state.dart` | Estado da integração e da ligação por agente (R1–R3), em cache |
| `lib/core/memory/ai_memory_env.dart` | Variáveis por tipo de execução (R6), usadas pelo Claude e pelo Codex |
| `lib/core/memory/handoff.dart` | Modelo da passagem: id, agente, quando, dono, estado, origem, diretório, resumo, perguntas, próximos passos, arquivos, se é a próxima a ser entregue |
| `lib/features/project/widgets/ai_memory_view.dart` | Seção ai-memory da aba Memória (R8–R12) |
| `lib/features/settings/ai_memory_view.dart` | Seção de Configurações com ligar e desligar (R3–R5) |

Arquivos alterados: `readonly_run.dart`, `claude_process.dart`, os chamadores das auxiliares, `spec_runner.dart` (sessões de etapa), o adaptador do Codex (R7), `project_memory_view.dart` (seletor), `project_screen.dart` e `settings_sections.dart`.

**Migração do banco:** não. As preferências (endereço do servidor quando não é o padrão, se a seção começa aberta) ficam em `app_settings`.

### Dependências

| O quê | Depende de | Por quê |
|---|---|---|
| Detecção, Configurações, ligar e desligar no **Claude**, painel, wiki, auxiliares do Claude fora da memória (R1–R6, R8–R14 no Claude) | nada do MVP | Usa só a CLI do ai-memory e o caminho do Claude que já existe. Pode começar antes da 0.22 fechar |
| Bloco do **Codex** em Configurações (R3–R5 no Codex) | SPEC-096 | Só aparece com o Codex habilitado no app |
| Codex dentro do app com memória (R7) | SPEC-093 (R15 e R16), SPEC-094, SPEC-096; conversa com a SPEC-103 | A sondagem mostra se os hooks do `~/.codex` rodam nas execuções do App Server e como isolar o `CODEX_HOME` sem perdê-los. A 094 dá o ambiente por provedor e a 096 abre as execuções |
| Auxiliares do Codex fora da memória (R6 no Codex) | SPEC-100 | As auxiliares só rodam no Codex depois da 100. Até lá, R6 vale só para o Claude |
| "Continuar em…" a partir de uma passagem (R11) | SPEC-099 | A ação é da 099; sem ela o botão não aparece |

### Roteiro para a sondagem (SPEC-093 R16 e decisão 9)

Num repositório temporário, com o binário do ai-memory baixado para uma pasta temporária (conferindo o SHA-256 da release), `AI_MEMORY_DATA_DIR`, `CLAUDE_CONFIG_DIR` e `CODEX_HOME` temporários (o `CODEX_HOME` temporário reaproveita o login sem copiar o `auth.json`, como na R15 da 093). Nada no ambiente da pessoa:

1. `ai-memory setup --plan --agent claude-code --agent codex`: guardar a saída; ver se dá para extrair o estado por agente (R3).
2. `install-hooks` e `install-mcp` para os dois com `--apply`: listar os arquivos criados ou alterados e as cópias de segurança.
3. Duas execuções curtas do Claude, como o app faz (`-p --output-format stream-json` com `--settings` temporário): uma normal e uma com `AI_MEMORY_CAPTURE_OWNER=promptorium` e `AI_MEMORY_AUTO_HANDOFF=off`. Conferir com `memory_handoff_list` e `memory_briefing`: a normal gera sessão e passagem; a auxiliar não gera nenhuma das duas e não consome uma passagem aberta (P4).
4. Uma thread do Codex pelo App Server, com os hooks do ai-memory no `CODEX_HOME`: o `SessionStart` entrega a passagem do passo 3? O `SessionEnd` grava uma nova? Precisa de confiança nos hooks (R7)?
5. `ai-memory call memory_handoff_list '{}'` com `cwd` no repositório e num worktree dele: mesmo projeto? Formato do JSON (dono, estado, `newer_unended_session`) (R9, R10).
6. `ai-memory call memory_handoff_cancel` numa passagem de teste (R11) e a forma de desinstalar por agente (P5).
7. `ai-memory status --json`: a pasta do wiki e se a interface web está ligada (R12).

Cerca de 4 turnos curtos (2 no Claude, 2 no Codex), contados no orçamento de turnos da 093.

## Tarefas

| Tarefa | Entrega | Requisitos |
|---|---|---|
| T1 · CLI e detecção | `ai_memory_cli.dart`, estado, cartão "não encontrado" e testes com um `ai-memory` falso | R1, R2, R14 |
| T2 · Execuções fora da memória | Variáveis por tipo de execução no Claude (e no Codex quando a 096 e a 100 existirem) | R6, R7 |
| T3 · Configurações | Estado por agente, prévia, ligar e desligar | R3–R5 |
| T4 · Painel | Seletor da aba Memória, passagens, aviso de sessão sem passagem, descartar, wiki | R8–R13 |
| T5 · Teste no app | App isolado com o ai-memory temporário do roteiro: ligar, sessão Claude → passagem → sessão Codex, painel | R1–R14 |

## Implementação

Branch `spec/098-memoria-ai-memory`, com as tarefas T1–T5 em PRs filhos.

| Arquivo | Papel |
|---|---|
| `lib/core/memory/ai_memory_cli.dart` | Acha o binário só olhando o disco; roda `--version`, `call`, `setup --plan --json`, os *dry-runs* de `uninstall`, `doctor --json`, `status --json` e os instaladores confirmados. Cada chamada tem limite de 5 s (30 s para instaladores e `doctor`), e o log guarda só o nome, o tempo e o código de saída |
| `lib/core/memory/ai_memory_state.dart` | Os quatro estados, com o comando de correção de cada um. Detecta ao abrir o app (`app_shell`) e guarda em cache até "Verificar de novo" |
| `lib/core/memory/ai_memory_wiring.dart` | Hooks e MCP por agente, os comandos de "Ligar", os arquivos mostrados na prévia e os comandos de "Desligar" |
| `lib/core/memory/ai_memory_env.dart` | Variáveis por tipo de execução: `runReadOnlyClaude`, `/usage`, `session_manager` |
| `lib/core/memory/handoff.dart` | Passagem, dono, ordem de entrega, sessão sem passagem e briefing |
| `lib/features/settings/ai_memory_view.dart`, `ai_memory_links.dart` | Configurações → Memória (ai-memory) |
| `lib/features/project/widgets/ai_memory_view.dart` | Seção ai-memory da aba Memória; seletor em `project_memory_view.dart` |

Decisões além do texto da spec:

- **Estado por agente (R3).** O `setup --plan --json` da 3.5.1 (format 1) diz o que seria ligado e por quê, mas não o que já está ligado. O estado junta três leituras, todas só de leitura: o próprio `--plan` (detecção e plugin), `uninstall --only hooks|mcp` **sem `--apply`** (que lista as entradas do ai-memory em cada arquivo) e `doctor --json` (Codex: `codex_hooks.skipped` vira "aguardando confiança"). Continua vindo do ai-memory, sem o app ler os arquivos dos agentes. "Desatualizado" só aparece se uma versão futura do plano disser.
- **Desligar (P5).** A 3.5.1 não desinstala por agente. "Desligar" mostra `ai-memory uninstall --only hooks --apply` e `--only mcp --apply` para copiar, com o aviso "remove de todos os agentes" e a lista do *dry-run*. O app não roda nada.
- **Variáveis com o binário presente (R6).** Valem sempre que o binário existe, mesmo com o servidor parado (os hooks guardam os eventos no *spool* e mandariam depois) e mesmo para hooks instalados por fora. A sessão com spec conta como sessão de etapa, também ao retomar; isso fica no `session_manager` e não só no `spec_runner`.
- **Codex no app (R7).** O app não isola o `CODEX_HOME`, então herda os hooks e o MCP do `~/.codex`. Quando o Codex ainda não confia nos hooks, o bloco do Codex mostra "Codex no app sem memória" com o motivo.
- **Histórico (R9).** `memory_handoff_list` só lista as abertas. O filtro "Mostrar aceitas e expiradas" mostra as fechadas que vierem na resposta e, se não vier nenhuma, avisa que esta versão só informa as abertas.
- **Dono (R9, P6).** Num servidor que não atribui dono, todas são "você". Quando atribui, a lista já vem filtrada (as suas e as compartilhadas): com dono é "você", sem dono é "compartilhada". Descartar só nas abertas de "você".
- **"Continuar em…" (R11).** O botão vem do `handoffContinueActionProvider`, que é nulo até a SPEC-099 preencher.

E2E: app compilado no Xephyr `:5`, com `XDG_DATA_HOME`, `HOME` isolado, um `ai-memory` falso no `PATH` e um `/healthz` local. Nada foi instalado e nenhum turno pago rodou. Capturas em `docs/mockups/spec-098/app/`.

## Critérios de aceite

- [x] Sem o binário do ai-memory, nenhuma tela de trabalho muda, nenhum processo extra roda e os agentes recebem o mesmo ambiente de hoje [R2] verificar: teste com `PATH` sem `ai-memory`, comparando o ambiente das execuções antes e depois.
- [x] Os quatro estados da detecção aparecem com o comando de correção e nenhum deles instala ou inicia nada [R1] verificar: testes com um `ai-memory` falso (ausente, versão 3.0.0, servidor parado, conectado).
- [x] O estado de hooks e MCP por agente vem do `setup --plan`, e o Codex mostra "aguardando confiança" quando cabe [R3] verificar: teste com saídas gravadas na sondagem.
- [x] Ligar mostra comandos e arquivos antes e só roda o instalador depois de confirmar; o app não abre para escrita nenhum arquivo do `~/.claude` ou do `~/.codex` [R4, R5] verificar: teste do fluxo e inspeção do código (nenhum `File.write` nesses caminhos).
- [x] Auxiliares rodam com `AI_MEMORY_CAPTURE_OWNER` e `AI_MEMORY_AUTO_HANDOFF=off`, sessões de etapa só com `AI_MEMORY_AUTO_HANDOFF=off` e sessões livres sem nenhuma das duas [R6] verificar: testes do ambiente montado por tipo de execução.
- [ ] Uma auxiliar não cria sessão nem consome uma passagem aberta [R6] verificar: passo 3 do roteiro registrado em `docs/pesquisa/codex-0170.md` e repetido no T5. — **conferido no código da 3.5.1** (`hooks/_lib.sh`: sem captura e `claim=0`), registrado em `docs/pesquisa/codex-0170.md`; a execução com o binário real fica pendente, porque o ai-memory não foi instalado nesta máquina
- [x] Uma sessão do Codex aberta pelo app recebe a passagem deixada por uma sessão do Claude, ou o bloco do Codex diz por que não [R7] verificar: T5 com capturas.
- [x] O painel lista as passagens abertas com agente, hora, dono, origem e o selo da próxima a ser entregue; o histórico mostra quem aceitou [R8, R9] verificar: teste de widget com JSON gravado e captura do T5.
- [x] Uma sessão cortada sem passagem aparece como aviso [R10] verificar: teste com `newer_unended_session`.
- [x] Descartar pede confirmação, só aparece nas passagens do próprio dono e não existe ação de aceitar [R11] verificar: teste de widget.
- [x] "Abrir wiki" abre a interface web quando ela responde e, senão, a pasta do projeto no wiki [R12] verificar: teste com os dois casos.
- [x] Texto da passagem com markdown, links e `<script>` aparece como texto puro; o token não aparece em tela nem em log [R13] verificar: teste de widget e busca nos logs do T5.
- [x] Servidor parado ou chamada lenta (mais de 5 s) vira linha de estado sem travar a aba [R14] verificar: teste com `ai-memory` falso que demora.

## Telas

Canvas: [SPEC-098 · Memória com ai-memory](https://claude.ai/artifact/1mjS6FvrDCFvnzn9Qjteof). Capturas em `docs/mockups/spec-098/`.

| PNG | O que mostra | Requisitos |
|---|---|---|
| `1-memoria-do-projeto.png` | Aba Memória do projeto com o seletor "Fatos do projeto · ai-memory", a linha de estado, duas passagens abertas (uma do Claude Code expandida, com o selo "será entregue à próxima sessão", e uma manual compartilhada), o aviso de uma sessão do Codex cortada sem passagem, "Abrir wiki" e as páginas recentes | R8–R12 |
| `2-configuracoes.png` | Configurações → Memória (ai-memory): versão, servidor, Claude Code com hooks e MCP ligados, Codex com MCP ligado e hooks aguardando confiança, e as execuções do app fora da memória | R1, R3, R6, R7 |
| `3-previa-ligar.png` | Prévia de "Ligar no Codex": comandos, arquivos que o ai-memory vai alterar, cópias de segurança e o aviso de que o Codex vai pedir confiança | R4 |
| `4-estados.png` | Antes e estados: aba Memória sem o ai-memory (igual a hoje), cartão "não encontrado", servidor parado, versão antiga e erro de leitura no painel | R1, R2, R14 |
