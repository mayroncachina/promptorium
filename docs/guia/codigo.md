# Código

Um editor para mexer à mão nos mesmos arquivos que os agentes.

## Worktree e árvore

O seletor **Worktree** escolhe entre a raiz do repositório e o worktree de cada sessão. A árvore respeita o `.gitignore` e marca arquivos adicionados, modificados e apagados (A/M/D). Menu: Novo arquivo, Nova pasta, Renomear / mover… e Excluir….

## Editor

- Abas, Ctrl+S salva, Ctrl+W fecha, Ctrl+P vai para um arquivo.
- Busca e substituição (Ctrl+F/Ctrl+H) e zoom próprio.
- Status com linha e coluna, linguagem, codificação e fim de linha.
- Marcas na margem distinguem o que o agente alterou da sua edição não salva.
- Se o arquivo mudar no disco: "Recarregar" ou "Manter as minhas".

Quando uma sessão está trabalhando no mesmo worktree, uma faixa avisa, com "Pausar agente" e "Ver sessão". Ao salvar, o agente é avisado da sua alteração.

## Painel inferior

- **Terminal**: o seu `$SHELL` no worktree.
- **Problemas**: roda o comando `lint:` do projeto ao salvar ou em "Rodar agora".
- **Git**: stage, unstage e commit.
- **Busca**: em todos os arquivos, com ripgrep (Ctrl+Shift+F).
