# Projeto

## Começar

Sem workspace aberto, ou em **Novo projeto…**, a tela Começar oferece três caminhos:

- **Abrir pasta existente**.
- **Criar projeto novo**: nome da pasta, onde criar, modelo de partida e remoto ("Só local por enquanto" ou "Conectar a" uma URL). Termina em "Criar e planejar com o planner" ou "Criar sem planejar".
- **Clonar de uma URL**.

Abaixo ficam os projetos recentes.

Os **modelos** (Vazio, Flutter app, Next.js, API Python, CLI Dart) preenchem os comandos de testes, lint, formatação e preparação do `.promptorium/config.yml`, as decisões de stack e um `CLAUDE.md` mínimo.

## Planejar com o planner

O planejamento tem quatro etapas:

1. **Visão**: uma conversa com o planner. O plano (resumo, público, MVP, fora do escopo, dúvidas) é atualizado a cada resposta.
2. **Stack e convenções**: uma escolha por área, com alternativas clicáveis, e o `CLAUDE.md` editável.
3. **Roadmap**: specs da Fundação e do MVP com código, requisitos (as etapas, no máximo 6 por spec) e dependências, numa ordem de execução em ondas. Tudo é editável à mão; ideias para depois podem virar specs.
4. **Revisar e criar**: grava o `CLAUDE.md` e as specs na pasta configurada, coloca as specs no Quadro, commita e, se você quiser, abre a sessão da primeira etapa.

O planner roda somente leitura. O rascunho do plano fica salvo no app até você criar ou descartar.

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

Num repositório que já tem código, a tela Projeto mostra quatro abas:

- **Saúde**: "Analisar repositório" inspeciona os arquivos (sem chamar o modelo) e detecta a stack. Mostra as últimas 10 specs, o gate por spec, custo médio, rodadas de correção, reenvios do gate, hunks rejeitados, tempo por etapa e como o Promptorium trabalha ali.
- **Configuração**: editor do `.promptorium/config.yml`.
- **Memória**: `.promptorium/memoria.md`, com Adicionar, Excluir e "Limpar entradas com mais de 30 dias". Linhas `APRENDIZADO:` que os agentes escrevem nas sessões entram aqui sozinhas e vão nos prompts seguintes.
- **Métricas**: tabela por spec.

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
