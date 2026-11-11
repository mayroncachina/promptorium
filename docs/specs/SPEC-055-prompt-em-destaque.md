---
id: SPEC-055
status: aprovada
depende-de: SPEC-034, SPEC-049
issue: 141
---

# Prompt em destaque

## Objetivo

O Prompt é o jeito mais simples de usar o Promptorium para quem não programa. Ele funciona como um chatbot: dá para perguntar sobre o projeto, pedir um plano ou mandar o agente fazer a mudança. Hoje ele fica perdido:
- é o 9.º item da barra lateral (Ctrl 9), com o mesmo peso dos outros;
- o ícone tem 20 px e traço fino;
- a tela vazia fala de "raiz do repositório" e "worktree";
- os três modos (Perguntar, Planejar, Editar) só aparecem num seletor pequeno, embaixo do campo de texto.

A ideia veio de um usuário: *"Vale a pena dar mais destaque ao Prompt, é uma das funcionalidades mais bacanas para quem não programa, pois é possível conversar (perguntar), planejar, editar (mandar ele executar) de maneira mais intuitiva e mais parecida com um chatbot… eu penso em colocar ele embaixo do projeto, colocar um ícone melhor e maior para destaque."*

Esta spec muda três coisas:
- o Prompt vai para logo abaixo do Projeto na barra lateral;
- o item fica maior, ganha nome e um ícone novo;
- a tela vazia explica os três modos em português simples, com exemplos que dá para clicar.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/3jkRzCnhFRQnWsoAnzf5a8). Capturas em `docs/mockups/spec-055/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-antes.png` | O Prompt hoje: 9.º item, tela vazia técnica, modos só no seletor | — |
| `2-depois.png` | Prompt abaixo do Projeto, item em destaque e a tela vazia nova | R1, R2, R3, R6, R7 |
| `3-trilho.png` | O item em detalhe: estados, ícone antigo e novo, nova ordem e atalhos | R2–R5, R8 |
| `4-andamento.png` | No Quadro, o item mostra que o agente ainda está respondendo no Prompt | R4 |
| `5-estreito.png` | Janela de 1100×700 no modo Planejar: os exemplos somem e a barra cabe | R7, R9 |

## Requisitos

- R1 · Nova ordem da barra lateral: **Início · Projeto · Prompt · Specs · Quadro · Sessões · Review · Repositório · Código · Ferramentas**. O Prompt fica entre dois separadores de 1 px (28 px de largura, `rgba(255,255,255,.1)`).
- R2 · O item do Prompt é diferente dos outros:
  - tem 48 × 58 px (os outros têm 44 × 44);
  - mostra o ícone com 24 px e o nome **"Prompt"** embaixo (10,5 px, peso 600);
  - tem fundo de vidro âmbar→teal e borda âmbar fraca mesmo em repouso.

  É o único item com rótulo, então o destaque vem do tamanho, do nome e do fundo, não só da cor.
- R3 · Estados do item:
  - **repouso:** fundo de vidro, ícone âmbar, rótulo em `text`;
  - **hover:** fundo e borda mais fortes (120 ms, os tokens `quick`/`quickExit` da SPEC-034);
  - **ativo:** brilho âmbar e rótulo em `#FFD08A`;
  - **foco do teclado:** anel de 2 px `#FFD08A`, afastado 3 px;
  - **pressionado:** a escala de 0,98 dos outros itens.
- R4 · O item mostra o que acontece no Prompt quando a pessoa está em outra tela:
  - **respondendo:** um ponto teal pulsa no canto enquanto alguma conversa está `busy`. O tooltip diz "Respondendo “<título>” · <modo>". Com movimento reduzido, o ponto fica fixo;
  - **precisa de você:** o contador âmbar conta as aprovações pendentes e os "Plano pronto" das conversas do Prompt. Esses itens deixam de entrar no contador de Sessões.
- R5 · O Prompt ganha um ícone novo: um balão de conversa com duas linhas de texto dentro e uma faísca **preenchida** fora do contorno, na grade de 24 com traço de 1,8. Ele substitui `AppIcons.prompt` em todos os lugares (barra, paleta, tela vazia, tooltip) e precisa ficar legível em 16 px.
- R6 · Atalhos: o Prompt passa a ser **Ctrl 3**. Specs, Quadro, Sessões, Review, Repositório e Código descem uma posição (Ctrl 4 a Ctrl 9), e Ferramentas continua no Ctrl 0.
  - `shortcutsVersion` passa de 4 para 5, e o app mostra uma vez o aviso de atalhos novos;
  - a folha de atalhos e a paleta mostram a ordem nova.
- R7 · A tela vazia do Prompt (com workspace) é uma tela de boas-vindas:
  - **título:** "Converse com o seu projeto", ao lado do ícone novo em 30 px;
  - **frase:** "Escreva como num chat. Escolha abaixo o quanto o agente pode mexer.";
  - **três cartões de modo**, um para cada `PromptMode` oferecido. Cada um tem ícone, nome, uma frase e um selo com texto (não só cor):

    | Modo | Frase | Selo |
    |---|---|---|
    | Perguntar | Tire dúvidas sobre o projeto. O agente lê, explica e não mexe em nada. | Nada muda nos arquivos (teal, cadeado) |
    | Planejar | Descreva o que quer. O agente monta um plano e espera o seu ok antes de agir. | Você aprova antes (âmbar, check) |
    | Editar | Peça a mudança e o agente faz direto na pasta do projeto. | Altera os arquivos (coral, alerta) |

  - os cartões formam um `radiogroup` e espelham o seletor de modo do campo de texto: escolher um cartão troca o modo e o seletor acompanha;
  - cada cartão tem **dois exemplos** que dá para clicar. Clicar num exemplo escolhe o modo do cartão e põe o texto no campo, sem enviar, para a pessoa poder ajustar.

  Sem workspace, a tela continua como hoje ("Nenhum workspace").
- R8 · A barra lateral precisa caber em 700 px de altura com o item maior. O destaque que desliza (SPEC-034 R3) passa a usar a posição e a altura reais de cada item, em vez de `índice × 48`, e fica do tamanho do Prompt quando ele está ativo.
- R9 · Em janelas com altura útil abaixo de 760 px, os exemplos dos cartões somem. Os cartões ficam com nome, frase e selo. Se a largura não comportar três colunas, os cartões quebram de linha.
- R10 · Acessibilidade:
  - o item da barra anuncia "Prompt", "Prompt · respondendo" ou "Prompt · n pendentes";
  - os cartões anunciam o nome e o selo do modo e o estado de selecionado;
  - os exemplos são botões, e o contraste do texto é de pelo menos 4,5:1 nos dois temas (Vidro e sólido).

## Fora do escopo

- Mudar o comportamento dos modos ou criar um modo novo.
- Mudar a lista de conversas, a linha do tempo ou o campo de texto, exceto para espelhar o modo (R7).
- Rótulos nos outros itens da barra lateral ou uma barra lateral larga.
- Exemplos gerados a partir do projeto: os exemplos são fixos por modo.

## Design

### O que já existe

- `lib/ui/shell/navigation.dart`: `AppSection.navItems` (ordem e atalhos), `shortcutsVersion` e `icon`.
- `lib/ui/shell/side_bar.dart`: `SideBar`, `SideBarItem` (44 px) e `_Highlight`, que calcula a posição com `navIndex * _itemStride`.
- `lib/ui/widgets/app_icon.dart`: `AppIcons.prompt`.
- `lib/features/home/home_inbox.dart`: `navBadgesProvider`. Hoje as aprovações (inclusive as do Prompt) vão para Sessões.
- `lib/features/prompt/conversation_manager.dart`: `LiveConversation.busy` e `approvals`.
- `lib/features/prompt/prompt_screen.dart`: `_Empty`, a tela vazia.
- `lib/core/providers/agent_provider.dart`: `PromptMode` (ask, plan, edit; `refine` não é oferecido).
- `lib/ui/shell/shortcut_sheet.dart`: a folha de atalhos.

### Componentes

- **`navigation.dart`:**
  - a nova ordem em `navItems`;
  - `shortcutsVersion = 5`;
  - `bool get featured => this == prompt`.
- **`SideBarFeaturedItem`** (novo, em `side_bar.dart`): o item de 48 × 58 com ícone e rótulo, os estados de R3 e o ponto "respondendo". Usa os mesmos `Tooltip` e `Semantics` do `SideBarItem`, e a `SideBar` desenha os separadores em volta dele.
- **`_Highlight`:** recebe a posição e a altura do item ativo, medidas por `GlobalKey`s ou por uma tabela de alturas (`_itemHeight(section)`), em vez de calcular `índice × stride`.
- **`promptActivityProvider`** (novo): diz se alguma conversa está `busy`, com o título e o modo dela, para o ponto e o tooltip.
- **`navBadgesProvider`:** separa as aprovações e os planos prontos das conversas do Prompt e conta isso em `AppSection.prompt`.
- **`AppIcons.prompt`:** troca pelos caminhos novos (o balão, as linhas e a faísca preenchida). O `AppIconData` precisa aceitar um caminho preenchido, ou a faísca vira um caminho com `fill`.
- **`PromptWelcome`** (novo, `lib/features/prompt/widgets/prompt_welcome.dart`): troca o `_Empty` quando há workspace. Recebe o modo atual e `onPickMode`/`onExample`, que preenchem o campo de texto via o controller do composer. Os exemplos ficam numa constante por `PromptMode`.

### Testes

- **Navegação:**
  - a ordem de `navItems` está certa;
  - Ctrl 3 abre o Prompt e Ctrl 9 abre Código;
  - o aviso de atalhos aparece uma vez com `shortcutsVersion` 5.
- **Barra lateral:**
  - o item do Prompt tem 58 px de altura e o rótulo "Prompt";
  - o destaque fica sobre o Prompt e sobre os itens abaixo dele;
  - o ponto aparece com uma conversa `busy` e some quando ela termina;
  - o contador do Prompt conta as aprovações da conversa, e o de Sessões não;
  - com 700 px de altura, nada transborda.
- **Boas-vindas:**
  - os três cartões aparecem;
  - escolher um cartão troca o modo do composer;
  - clicar num exemplo põe o texto no campo sem enviar;
  - abaixo de 760 px os exemplos somem;
  - sem workspace, aparece "Nenhum workspace".
- **Semântica:** os rótulos de R10.

## Decisões

- **Só o Prompt ganha rótulo.** Rotular todos os itens alargaria a barra e tiraria o destaque. Um item diferente dos outros é o próprio destaque.
- **O Prompt fica entre o Projeto e as Specs.** É o primeiro passo natural de quem não programa (abrir o projeto e conversar com ele), antes de escrever specs.
- **O exemplo não é enviado sozinho.** Ele só preenche o campo: a pessoa vê o que vai mandar e pode ajustar antes, o que importa principalmente no modo Editar.
- **O selo leva texto e ícone, não só cor.** O nível de permissão de cada modo é a informação mais importante para quem não programa.

Tomadas na implementação:
- **t1 · Tabela de alturas, não `GlobalKey`s.** A barra é uma coluna fixa: a posição de cada item sai de uma conta com as alturas reais (44 ou 58), o espaço de 4 px e os separadores (1 px + 4 px). Medir com `GlobalKey` pediria um quadro a mais e faria o destaque pular na primeira pintura.
- **t1 · O destaque anima um retângulo.** Ele desliza por `Transform` como antes e só muda de tamanho (e de raio, de 10 para 13 px) quando sai do Prompt ou chega nele. O brilho também cresce um pouco no Prompt, como no mockup.
- **t1 · O ícone do Prompt ativo também fica em `#FFD08A`,** igual ao rótulo, como no mockup (`Trilho.dc.html`). A cor ganhou o token `AppColors.amberLight`.
- **t1 · O anel de foco só aparece no teclado** (`FocusHighlightMode.traditional`), sem a demora do hover, como nos outros itens.
- **t2 · A faísca é um caminho preenchido.** `AppIconData` ganhou `fills`: caminhos pintados com `fill` antes do traço, na mesma grade de 24. Os outros ícones continuam só com traço.
- **t2 · A paleta passou a mostrar ícones** nos comandos "Ir para" (16 px), para o ícone novo aparecer nela como pede R5. Antes ela só tinha texto.
- **t2 · `promptActivityProvider` lê o banco, não o processo.** O título e o modo vêm da conversa (`conversations`) do workspace ativo; o `busy` vem do `ConversationManager`. Com várias conversas respondendo, vale a mais recente, como na lista do Prompt.
- **t2 · O contador ganha do ponto.** Os dois ficam no mesmo canto; quando há pendências, só o contador aparece, e o rótulo anuncia as duas coisas ("Prompt · respondendo · 1 pendente"). Na própria tela do Prompt o ponto some, porque a conversa já mostra que está respondendo.
- **t2 · Pendências pelo `conversationId`.** O `navBadgesProvider` separa as aprovações do Inbox: com `conversationId`, contam no Prompt (inclusive "Plano pronto"); sem, em Sessões. O Início continua contando todas.
- **t3 · O exemplo põe o cursor no fim e dá o foco ao campo.** A pessoa pode continuar escrevendo direto; outro exemplo troca o texto inteiro e o modo.
- **t3 · O cartão inteiro é clicável,** mas a semântica de rádio fica só no cartão (nome · selo, selecionado ou não) e cada exemplo é um botão à parte dentro dele. O grupo usa `SemanticsRole.radioGroup` com o rótulo "Modo da conversa".
- **t3 · Selecionado sem sombra.** Uma sombra aparecia através do vidro do cartão; o selecionado ganha só a borda âmbar mais forte (1,5 px em todos, para não mexer no layout).
- **t3 · Janela baixa (< 760 px):** além dos exemplos, somem a frase do título e a dica de rodapé, como no mockup `5-estreito.png`. Os cartões mantêm nome, frase e selo.
- **t3 · Em 1100 × 700 o terceiro cartão pede rolagem.** O mockup estreito esconde as colunas de conversas e de contexto; o app mantém as duas (mudar isso está fora do escopo), então a coluna do meio fica com ~490 px: os cartões quebram em duas colunas e a tela de boas-vindas rola.
- **t3 · Ícones dos cartões na grade de 20.** `AppIconData` ganhou `viewBox`, que escala para 24 os caminhos copiados do mockup.
- **t1 · A barra em 700 px:** os itens ocupam 564 px (9 × 48 + 62 + 2 × 5 + a engrenagem), e sobram cerca de 30 px na janela de 1100 × 700.

## Plano

1. **t1 · Barra lateral e atalhos** (R1–R3, R6, R8): nova ordem em `navItems`, `SideBarFeaturedItem`, separadores, `_Highlight` com altura variável, `shortcutsVersion` 5, folha de atalhos e testes.
2. **t2 · Ícone e sinais** (R4, R5, R10): `AppIcons.prompt` novo (com a faísca preenchida), `promptActivityProvider`, ponto "respondendo", contador do Prompt em `navBadgesProvider` e testes.
3. **t3 · Tela de boas-vindas** (R7, R9, R10): `PromptWelcome` no lugar do `_Empty` com workspace, cartões espelhando o modo, exemplos que preenchem o campo, ajuste abaixo de 760 px e testes.

## Critérios de aceite

- [x] O Prompt aparece logo abaixo do Projeto, entre separadores, com 48 × 58 px e o nome "Prompt".
- [x] Ctrl 3 abre o Prompt; Ctrl 9 abre o Código; o aviso de atalhos novos aparece uma vez.
- [x] O destaque da barra fica sobre o item certo, inclusive no Prompt e nos itens abaixo dele.
- [x] Em outra tela, o ponto teal aparece enquanto uma conversa responde, e o contador mostra as aprovações e os planos prontos do Prompt.
- [x] O ícone novo aparece na barra, na paleta e na tela vazia.
- [x] A tela vazia mostra os três modos; clicar num exemplo escolhe o modo e preenche o campo sem enviar.
- [x] Em 1100×700 a barra cabe e os exemplos somem.
