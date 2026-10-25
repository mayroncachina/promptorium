# Specs

## O arquivo

Uma spec é um Markdown `SPEC-NNN-<titulo>.md` na pasta de specs do projeto (`specs:` no `.promptorium/config.yml`; padrão `specs/`). A barra da tela mostra qual é a pasta.

```markdown
---
id: SPEC-021
status: aprovada
depende-de: [SPEC-019]
---

# Título

## Objetivo
## Requisitos
- R1 · Quando …, o sistema deve …
## Design
## Etapas
- R1 → arquivos · verificar: `comando`
## Critérios de aceite
- [ ] [R1] … verificar: `flutter test test/…`
```

- **Status**: ideia, rascunho, em-revisao, aprovada, concluida, arquivada.
- Cada **requisito** é uma etapa de execução no Quadro.
- `## Design` diz como implementar; `## Etapas` liga cada requisito aos arquivos e ao comando que o verifica. As sessões recebem só a parte da spec relevante para a etapa.
- Os **critérios de aceite** com `verificar:` são checados pelo gate e podem ser marcados automaticamente.

## Editor

Modos **Editar**, **Dividido** e **Visualizar**, com realce, números de linha, busca e substituição (Ctrl+F/Ctrl+H) e zoom (Ctrl+= / Ctrl+- / Ctrl+0), salvo por tela. Ctrl+S salva.

Ações da spec:

- **Refinar com IA**: abre uma conversa de refino no [Prompt](prompt.md). Cada edição do agente pede aprovação, e "Voltar à spec" traz você de volta com o arquivo recarregado.
- **Gerar design**: o agente lê o repositório (somente leitura) e escreve `## Design`, com "O que já existe", e `## Etapas`.
- **Aprovar spec**: sem Design, oferece "Aprovar sem design (spec trivial)" ou "Gerar design". Aprovada, a spec vai para o Backlog do [Quadro](quadro.md).
- **Clonar para alterar**: uma spec já iniciada não é editável; clonar cria uma nova.
- **Arquivar** e **Excluir** (vai para a lixeira; só para spec nunca executada).
- Se o arquivo mudar no disco com alterações não salvas, o app pergunta: "Carregar do disco" ou "Manter minhas alterações".

O frontmatter também aceita subagentes por etapa, editados num painel próprio.

### Avisos de estrutura e perguntas em aberto

Uma faixa abaixo do editor lista os avisos da spec, atualizados enquanto você edita: requisito sem critério de aceite, critério sem `[Rn]` ou citando requisito que não existe, critério sem `verificar:` (use `verificar: manual (…)` quando não houver comando), ID repetido ou fora de sequência e requisito sem "deve" (fora do estilo EARS). Clicar num aviso leva o cursor à linha. Os avisos não impedem salvar nem aprovar.

Ao aprovar uma spec com itens em `## Perguntas em aberto`, o app lista as perguntas e oferece **Refinar com IA**, **Aprovar assumindo premissas** (as perguntas vão para `## Premissas`, com a data) ou **Cancelar**. Com avisos, o mesmo diálogo mostra quantos são, com **Ver avisos** e **Aprovar mesmo assim**.

Uma spec nova já vem com `## Fora do escopo` e `## Perguntas em aberto`. As sessões de etapa recebem "Fora do escopo" e "Premissas" junto com o objetivo.

## Protótipo de telas

O quarto modo do editor, **Protótipo**, mostra as telas da spec num canvas com zoom, uma por requisito.

- **Gerar telas da spec**: o agente cria um HTML autocontido por requisito com interface, em `docs/mockups/<spec>/R<n>-<slug>.html`, no visual do Promptorium. Ele só pode escrever nessa pasta; qualquer escrita fora dela é negada.
- **Miniaturas**: o app gera um PNG de 1440×900 com o Chrome ou Chromium headless e guarda em `~/.cache/promptorium/mockups/`. Sem navegador headless, cada tela aparece como cartão com "Abrir no navegador".
- Clique duplo numa tela abre o HTML no navegador padrão.
- **Pedir ao Claude**: selecione uma ou mais telas e descreva o que mudar; o agente cria uma variação nova de cada uma (`R<n>-<slug>.b.html`…), sem sobrescrever as anteriores.
- **Comparar variações**: as variações de um requisito lado a lado, com descrição e horário. **Aprovar e anexar à spec** grava a tela escolhida na seção `## Protótipo` (`- R1 → docs/mockups/…`), sem mudar o status da spec.
- **Versões**: lista as variações de cada requisito, marca a aprovada e remove as outras.

Na execução, a etapa de um requisito com tela aprovada recebe o caminho do HTML como referência visual. O histórico de pedidos e as descrições ficam em `docs/mockups/<spec>/index.json`, versionado junto com a spec.

## Sincronizar e verificar

A barra de sincronização (em Specs e no Quadro) mantém o banco igual aos arquivos:

- **Sincronizar specs**: lê a pasta, descobre specs novas e reconcilia o status.
- **Verificar implementação**: o agente confere, somente leitura, se o código já atende cada spec, e gera um relatório. "Verificar e concluir comprovadas" leva as comprovadas a Feito.
- **Reabrir**: devolve uma spec concluída ao estágio em que estava.

## Rastreabilidade por etapa

Selecionando uma etapa, o painel mostra os critérios (e quem os marcou), o resultado do gate, o design usado, os commits e a sessão. Ações: "Ver diff da etapa", "Abrir sessão" e "Refazer a partir daqui".

## Finalizar e reabrir à mão

No inspetor do Canvas do Quadro, "Marcar como finalizada" leva uma spec do Backlog a Feito (avisa se houver critérios sem marcar), e "Reabrir" a devolve. A escolha é gravada no frontmatter (`status: concluida`, com `estagio-anterior` e `status-anterior`), por isso a sincronização não a desfaz.
