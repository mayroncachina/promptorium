# Projeto

## Começar

Sem workspace aberto, ou em **Novo projeto…**, a tela Começar oferece três caminhos:

- **Abrir pasta existente**.
- **Criar projeto novo**: nome da pasta, onde criar, branch inicial (`main` por padrão), modelo de partida e remoto ("Só local por enquanto" ou "Conectar a" uma URL). Termina em "Criar e planejar com o planner" ou "Criar sem planejar".
- **Clonar de uma URL**.

Em "Abrir pasta existente" e "Clonar de uma URL", a coluna da direita mostra os projetos recentes.

Os **modelos** (Vazio, Flutter app, Next.js, API Python, CLI Dart) preenchem os comandos de testes, lint, formatação e preparação do `.promptorium/config.yml`, as decisões de stack e as instruções dos agentes: o texto vai no `AGENTS.md`, que o Claude Code e o Codex leem, e o `CLAUDE.md` só tem a linha `@AGENTS.md`. Os dois entram no commit inicial, e um arquivo que já é seu nunca é sobrescrito.

### Outra stack

Quando nenhum modelo serve, o último chip, **Outro…**, abre **Definir a stack com o Claude**. Descreva a stack em texto livre ("API em Go com Fiber e Postgres, testes com go test") e clique em **Propor stack**. O Claude, somente leitura, devolve uma prévia: nome curto, decisões com o porquê, os seis comandos (editáveis), o comando de scaffold e um CLAUDE.md base, que abre para ler.

- **Pedir ajuste** continua a mesma conversa e troca a prévia. **Cancelar**, enquanto ele pensa, encerra a chamada; um erro aparece no próprio modal, com "Tentar de novo".
- **Usar esta stack** fecha o modal e a stack vira o ponto de partida: o chip mostra o nome ("Go · Fiber") e um lápis que reabre a conversa. Fechar sem usar não muda nada.
- Ao criar, os comandos vão para o config.yml, o CLAUDE.md base é gravado como o de um modelo (o do plano o substitui), as decisões e os comandos entram fixados na etapa Stack, e o scaffold vai ao planner do roadmap como base da primeira spec da Fundação. O app não roda o scaffold.
- Cada proposta ou ajuste é uma chamada e soma no custo ("+1 chamada" em "O que acontece" e em Revisar e criar).
- A stack vale enquanto a tela Começar está aberta. Com o Claude Code vermelho no Ambiente, o chip fica desabilitado.

### Ambiente

Em "Criar projeto novo", o bloco **Ambiente** confere, antes de criar:

- **Git**: instalado e com nome e e-mail. Sem identidade, os campos Nome e E-mail e **Gravar no git** gravam no `git config --global` (os comandos aparecem escritos embaixo, para quem prefere o terminal).
- **Claude Code**: instalado, compatível e logado, com a versão e o plano. Deslogado, **Abrir terminal com claude auth login**; o item confere de novo quando a janela do app volta ao foco.
- **Hospedagem**: sai do "Repositório remoto". "Só local" é **Local**, sem checagem. Uma URL do `github.com` é **GitHub** e confere o `gh`; uma do `gitlab.com` é **GitLab** e confere o `glab` no host da URL. Outro host fica como "não reconhecido": PR e MR pelo app indisponíveis. A CLI da hospedagem é só aviso, nunca bloqueia.
- **Pasta**: "Criar dentro de" existe e é gravável, e o destino não existe (ou é sobra de uma criação que falhou).

Cada item mostra **ok**, **bloqueia** ou **aviso**. Git ou Pasta vermelhos, ou uma branch inválida, desabilitam os dois botões; Claude vermelho desabilita só "Criar e planejar". A checagem roda ao abrir, 300 ms depois de mudar o nome, a pasta ou o remoto, e em **Verificar de novo**. Um item que passa de 5 s fica como aviso e não bloqueia.

A branch inicial vira a branch do repositório e o `branch-base:` do `.promptorium/config.yml`, que nasce no commit inicial (também no modelo Vazio). Com GitHub ou GitLab, o config.yml também ganha `hospedagem:`.

### Custo e tempo

"O que acontece" não promete segundos nem dólares: mostra as 3 chamadas do planner (visão, stack e roadmap; cada mensagem a mais na Visão é mais uma) e a fila de refino em "1 rodada por spec". O app guarda a duração das últimas 20 rodadas da fila, de qualquer projeto; com 3 ou mais, a estimativa usa a mediana ("8 specs × ~2 min ≈ 16 min"), e sem histórico fica em "1–3 min" por spec.

No plano por assinatura (Pro, Max), o bloco **Uso** mostra a quota da janela de 5 h e da semana, com a hora em que renova, porque não há cobrança por chamada; o stepper mostra "Planner · N chamadas". Com chave de API, aparece o teto em dólares de cada chamada. Revisar e criar repete tudo na seção **Custo e tempo**, com as chamadas já feitas e, quando o projeto já tem specs executadas, o tempo médio de execução por spec.

## Planejar com o planner

O planejamento tem quatro etapas:

1. **Visão**: uma conversa com o planner. O plano (resumo, público, MVP, fora do escopo, dúvidas) é atualizado a cada resposta.
2. **Stack e convenções**: uma escolha por área, com alternativas clicáveis, o bloco **Comandos** e o `CLAUDE.md` editável.
3. **Roadmap**: specs da Fundação e do MVP com código, requisitos (as etapas, no máximo 6 por spec) e dependências, numa ordem de execução em ondas. Tudo é editável à mão; ideias para depois podem virar specs.
4. **Revisar e criar**: grava as instruções (o `AGENTS.md` e o `CLAUDE.md` que o importa) e as specs na pasta configurada, coloca as specs no Quadro, commita e, se você quiser, abre a sessão da primeira etapa.

O planner roda somente leitura. O rascunho do plano fica salvo no app até você criar ou descartar.

### Comandos

O bloco **Comandos** da etapa Stack traz os comandos que o CLAUDE.md lista, cada um com a chave do `.promptorium/config.yml` ao lado:

| Comando | Chave |
|---|---|
| instalar | `worktree.preparar` |
| rodar | `executar` |
| dev | `dev` |
| testes | `testes` |
| lint | `lint` |
| formatar | `formatar` |

- Um comando que o config.yml já tem aparece com o valor de lá, travado, e a marca "já existe". Os outros são editáveis: "novo" quando vão entrar, "não se aplica" quando estão vazios.
- Os comandos de um modelo de partida entram fixados, e o planner não os troca.
- Editar um comando marca o CLAUDE.md como desatualizado; **Atualizar** reescreve o CLAUDE.md mantendo as escolhas e os comandos.
- **Detectar do repositório** aparece quando a pasta tem um manifesto (`pubspec.yaml`, `package.json`…) e preenche só as linhas vazias.
- Em "Criar projeto", os comandos preenchem só as chaves vazias do config.yml (nunca sobrescrevem), `formatar` ganha ` {arquivo}` quando falta, e o config.yml entra no commit "Plano inicial do projeto". Em Revisar e criar, a linha do config.yml abre e mostra o que entra (`+`) e o que fica como estava (`=`).

O link **Saúde do projeto** do stepper abre a Saúde, com "Analisar repositório", também num projeto criado pelo planner.

## Refino e plano automáticos

A etapa **Revisar e criar** traz a opção "Refinar e planejar as specs automaticamente", ligada por padrão. Com ela, logo depois de "Criar projeto" o app passa as specs do roadmap por uma fila, uma de cada vez, na ordem de execução. Uma spec vem sempre depois das specs de que depende e recebe o plano delas, porque esse código ainda não existe.

- Cada rodada refina a spec com as regras de Refinar com IA e escreve `## Plano` e `## Etapas`. A spec é salva na hora, continua aprovada e ganha `plano: automatico`.
- Um requisito existente mantém o número, e o limite de 6 requisitos continua valendo. Uma dúvida sem resposta vira item de "Perguntas em aberto" e não para a fila. Uma resposta fora dessas regras conta como falha, e a spec fica como estava.
- No fim, um commit "Plano das specs" grava as specs planejadas, se a opção de commit estiver ligada.
- Pode sair da tela: a fila continua, e voltar mostra o estado atual. Fechar o app deixa as specs restantes sem plano, e Planejar continua disponível nelas.
- **Parar a fila** encerra a rodada atual e commita o que já ficou pronto. As specs restantes aparecem como "Sem plano", e **Retomar a fila** continua por elas.
- Uma falha não para as outras specs. Quem depende da spec com falha aparece como "Plano parcial". **Tentar de novo** refaz a spec e as dependentes, com um novo commit só delas.
- Enquanto a fila roda, Executar, Planejar e o editor ficam bloqueados nessas specs. A sessão da primeira etapa abre quando a fila termina, mesmo com falhas, e não abre se você parou a fila.

### Atualização do plano

Quando a última dependência de uma spec termina, o app refina e planeja essa spec de novo, agora lendo o código real. Isso vale só para spec com `plano: automatico` que ainda está no Backlog, e roda uma vez por spec. O fim commita só o arquivo da spec, como "Plano atualizado: SPEC-NNN".

Salvar a spec à mão, ou abrir uma conversa de Refinar com IA, retira a marca, e o app não sobrescreve mais o que você escreveu. Uma edição feita fora do app não é detectada: tire a linha `plano: automatico` do frontmatter para proteger a spec.

## Repositório existente

Num repositório que já tem código, a tela Projeto mostra cinco abas:

- **Saúde**: "Analisar repositório" inspeciona os arquivos (sem chamar o modelo) e detecta a stack. Mostra as últimas 10 specs, o gate por spec, custo médio, rodadas de correção, reenvios do gate, hunks rejeitados, tempo por etapa e como o Promptorium trabalha ali.
- **Configuração**: editor do `.promptorium/config.yml`.
- **Instruções**: o `AGENTS.md` e o `CLAUDE.md` do projeto. Veja [Instruções](#instruções).
- **Memória**: `.promptorium/memoria.md`, com Adicionar, Excluir e "Limpar entradas com mais de 30 dias". Linhas `APRENDIZADO:` que os agentes escrevem nas sessões entram aqui sozinhas e vão nos prompts seguintes.
- **Métricas**: tabela por spec.

## Instruções

Projeto › Instruções mostra as instruções que os agentes leem neste repositório. O jeito recomendado é a **fonte única**: as regras ficam no `AGENTS.md`, que o Codex lê, e o `CLAUDE.md` tem a linha `@AGENTS.md`, que faz o Claude Code ler o mesmo texto. O que vale só para o Claude Code (subagentes, hooks, skills) fica no `CLAUDE.md`, abaixo do import.

- **Arquivos**: o `AGENTS.md` e o `CLAUDE.md` da raiz, editáveis. Os de subpastas aparecem só para leitura.
- **Editor**: Texto ou Prévia, Salvar e Descartar, e "Abrir no editor". Se o arquivo mudar fora do app, ele é relido; se você estava editando, o app pergunta antes de perder qualquer um dos dois textos.
- **CLAUDE.md**: a linha do import fica separada do trecho "Só para o Claude Code". "Mover seleção para o AGENTS.md" leva uma regra que vale para os dois. Sem o import, o app avisa e oferece **Recolocar o import**.
- **Quem lê**: uma linha por provedor. "Carregado" só aparece com prova; antes disso, "previsto".
- **Tamanho**: bytes e linhas contra o limite de 32 KiB do Codex, com aviso a partir de 80% e o ponto do corte quando passa.

Ferramentas › Instruções e o item "Instruções" da paleta (Ctrl+K) levam para esta aba.

### Unificar

Um projeto antigo não muda sozinho, e o app não mostra aviso ao abrir. Quando há só `CLAUDE.md`, duas fontes (um `AGENTS.md` seu e um `CLAUDE.md` sem o import) ou um `AGENTS.md` gerado pelo app, a aba oferece **Unificar instruções**.

O diálogo lista as diferenças por seção e item. Cada uma vai para o `AGENTS.md`, fica no `CLAUDE.md` como trecho só do Claude ou, quando os dois arquivos dizem coisas diferentes, você escolhe a versão. "Pedir ajuda da IA" sugere o destino, sem decidir. O resultado dos dois arquivos aparece antes de gravar. Os dois são gravados juntos e sem commit: se o segundo falhar, o primeiro volta ao que era, e o aviso depois de gravar tem **Desfazer**.

### Melhorar com IA

**Começar entrevista** abre uma entrevista no estilo grill-me, no provedor de "Planner e assistentes", em somente leitura. A cada rodada a IA lê o projeto e faz todas as perguntas que já dá para fazer, com uma resposta recomendada. O que o código já responde não vira pergunta: aparece em "Achado no código", com o caminho. À direita fica o rascunho do `AGENTS.md`.

- Responda escolhendo uma opção, escrevendo outra resposta ou pulando a pergunta (uma pergunta pulada não vira regra). "Aceitar as recomendadas que faltam" preenche a rodada, e **Enviar rodada** pede a próxima.
- **Pausar** guarda tudo, e a entrevista sobrevive a fechar o app. O cartão "Entrevista pausada" tem **Continuar**, que segue no mesmo provedor e na mesma conversa. Se os arquivos mudaram durante a pausa, o cartão avisa, e a IA os relê ao continuar.
- No fim, a IA mostra o que entendeu. **Confirmar e ver a proposta** (ou "Encerrar e ver a proposta", a qualquer momento) traz a proposta.

### Proposta

A proposta vem em trechos, por arquivo e seção, com as perguntas de origem. Cada trecho pode ser aceito, recusado ou editado. À direita, o tamanho de cada arquivo depois de aplicar e a conferência dos caminhos citados.

- **Aplicar** grava só os trechos aceitos. Um trecho cujo texto antigo não está mais no arquivo vira **conflito** e não é gravado: edite o texto antigo ou recuse o trecho.
- **Commitar ao aplicar** vem desmarcado. Marcado, o commit leva só os arquivos de instruções e vai para a branch atual, cujo nome aparece na caixa. Fora da branch base há um aviso; com HEAD solto a caixa fica desativada.
- **Concluir** volta ao editor com o texto novo. A mudança vale para as próximas sessões, não para as que já estão abertas.

## `.promptorium/config.yml`

Arquivo versionado com o repositório. Todas as chaves são opcionais:

```yaml
specs: docs/specs              # pasta das specs (padrão: specs)
testes: flutter test           # comando que as sessões de etapa rodam
lint: flutter analyze          # verificação extra do gate
build: make build              # verificação extra do gate
formatar: dart format {arquivo}  # depois de cada edição (hook gerenciado)
branch-base: main              # base dos worktrees e alvo do merge
agente: implementer            # agente padrão das sessões de etapa
subagentes:                    # chamados em toda spec
  - agente: spec-reviewer
    quando: fim-da-spec
verificacao:                   # gate da etapa
  tentativas: 1                # reenvios automáticos ao agente
  timeout: 600                 # por comando, em segundos
  exigir-commit: true
  exigir-arvore-limpa: true
  contar-testes: true          # reprova a etapa se passarem menos testes ou houver mais pulados
bloquear-comandos:             # comandos Bash recusados pelo hook
  - "git push --force*"
worktree:
  copiar: [.env]               # copiados da raiz para worktrees novos
  preparar: npm ci             # rodado uma vez num worktree novo
  porta-base: 4000             # PROMPTORIUM_PORT = porta-base + índice
revisor:                       # revisor automático da spec terminada
  ligado: true
  modelo: haiku
  orcamento: 0.30
  rodadas: 2
autopilot:
  paralelo: 3                  # specs em execução ao mesmo tempo
  orcamento-dia: 10
hospedagem:                    # GitHub/GitLab em instância própria
  host: git.exemplo.com
  tipo: gitlab
git:
  marcar-commits-de-agente: true  # trailer nos commits das sessões (padrão: false)
```

## Apagar projeto

Pede para digitar o nome do projeto. Para sessões e conversas, remove os worktrees, manda a pasta para a lixeira (`gio trash`) e apaga do app o plano, specs, tarefas, sessões e conversas. Recusa `/`, a home e caminhos relativos.
