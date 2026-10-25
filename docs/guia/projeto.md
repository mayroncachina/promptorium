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
```

## Apagar projeto

Pede para digitar o nome do projeto. Para sessões e conversas, remove os worktrees, manda a pasta para a lixeira (`gio trash`) e apaga do app o plano, specs, tarefas, sessões e conversas. Recusa `/`, a home e caminhos relativos.
