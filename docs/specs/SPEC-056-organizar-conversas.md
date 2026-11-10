---
id: SPEC-056
status: aprovada
depende-de: SPEC-055
issue: 143
---

# Organizar as conversas do Prompt

## Objetivo

Com o uso, a lista de conversas do Prompt cresce sem controle. Hoje:
- não há como tirar da lista uma conversa que já serviu;
- o título vem da primeira mensagem e não pode ser trocado;
- o painel de Contexto da direita ocupa 280 px fixos, mesmo quando a pessoa só quer ler a conversa.

Esta spec traz três coisas:
- **arquivar e desarquivar** conversas;
- **renomear** a conversa;
- **recolher** o painel da direita numa faixa estreita.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/7v3vDHuZSWrqAXiNHXydL1). Capturas em `docs/mockups/spec-056/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-acoes.png` | Renomear e Arquivar na linha (hover), lápis no título e o menu ⋯ | R1, R2, R4 |
| `2-renomear.png` | Título em edição, edição na lista e título vazio | R2, R3 |
| `3-arquivar.png` | Aviso com Desfazer e o contador de arquivadas | R4, R5 |
| `4-arquivadas.png` | Abas Ativas/Arquivadas, Desarquivar e o aviso na conversa | R6, R7 |
| `5-recolhido.png` | Painel recolhido na faixa de 48 px | R8, R9 |
| `6-estreito.png` | 1100×700: painel recolhido por padrão, seção aberta por cima | R10 |

## Requisitos

- R1 · Ações da conversa:
  - ao passar o mouse ou focar uma linha da lista, aparecem os botões **Renomear** e **Arquivar** (28 px, com tooltip e rótulo para leitor de tela);
  - a linha selecionada mostra um botão ⋯;
  - o botão direito na linha e o ⋯ do cabeçalho abrem o mesmo menu: Renomear (F2), Arquivar, um separador, Transformar em spec e Continuar como sessão.
- R2 · Renomear:
  - começa pelo lápis ao lado do título, por F2 com a conversa aberta, pelo clique duplo na linha ou pelo menu;
  - o título vira um campo com o texto todo selecionado, com os botões salvar e cancelar e a dica "Enter salva · Esc cancela";
  - na lista, a edição acontece na própria linha;
  - perder o foco salva.
- R3 · O título:
  - não pode ficar vazio: o campo mostra "O título não pode ficar vazio. Esc volta ao anterior." e não salva;
  - tem no máximo 120 caracteres;
  - sem renomear, continua vindo da primeira mensagem, como hoje.
- R4 · Arquivar:
  - tira a conversa da lista de ativas na hora;
  - se ela estava aberta, a seleção passa para a conversa de cima (ou a de baixo, se era a primeira);
  - uma conversa que está respondendo também pode ser arquivada, e o processo continua.
- R5 · Depois de arquivar:
  - aparece o aviso "“<título>” arquivada", com o botão **Desfazer**, por 6 s;
  - Ctrl+Z também desfaz enquanto o aviso está na tela;
  - o rodapé da lista mostra "Arquivadas · n", que abre a aba de arquivadas.
- R6 · Arquivadas:
  - o topo da lista ganha as abas **Ativas · n** e **Arquivadas · n**, que só aparecem quando há alguma arquivada;
  - as arquivadas aparecem da mais recente para a mais antiga, com "arquivada <quando>" na linha;
  - na linha, o botão de hover é **Desarquivar**.
- R7 · Conversa arquivada aberta:
  - no topo da conversa aparece o aviso "Conversa arquivada. Ela não aparece entre as ativas. Mandar uma mensagem desarquiva." com o botão **Desarquivar**;
  - mandar uma mensagem desarquiva a conversa e volta para a aba Ativas.
- R8 · Recolher o painel da direita:
  - o cabeçalho do painel ganha o botão **Recolher painel** (Ctrl+Alt+B);
  - recolhido, o painel vira uma faixa de 48 px com: Mostrar painel (Ctrl+Alt+B), Contexto, Arquivos citados (com contador) e Prompts salvos, e o total de tokens na vertical;
  - a escolha fica guardada entre as sessões do app.
- R9 · Na faixa, clicar em Contexto, Arquivos ou Prompts salvos abre só aquela seção num balão por cima da conversa (260 px). Esc ou clicar fora fecha.
- R10 · Abaixo de 1100 px de largura, o painel começa recolhido. Abrir pelo botão vale até a janela mudar de faixa de largura.
- R11 · Acessibilidade:
  - todos os botões de ícone têm rótulo;
  - as abas são um `TabBar` com o estado de selecionada;
  - o aviso de arquivada é anunciado (`liveRegion`) sem tirar o foco.

## Fora do escopo

- Apagar conversas de vez.
- Pastas, etiquetas ou busca na lista de conversas.
- Recolher a lista de conversas da esquerda.

## Design

### O que já existe

- `lib/data/db/app_database.dart`:
  - a tabela `Conversations` com `title` e `updatedAt`;
  - `appSchemaVersion = 21`.
- `lib/features/prompt/widgets/conversation_list.dart`: `ConversationListPanel`, `_Tile` e `groupConversations`.
- `lib/features/prompt/prompt_screen.dart`:
  - o layout em três colunas;
  - o `_Header`, com o título e as ações.
- `lib/features/prompt/widgets/prompt_side_panel.dart`: `PromptSidePanel` (Contexto e Prompts salvos).
- `lib/data/providers.dart`: `conversationsProvider(workspaceId)`.
- `lib/ui/widgets/app_toast.dart`: `showAppToast`.

### Componentes

- **Schema v22:**
  - `Conversations.archivedAt` (nullable);
  - o repositório ganha `rename(id, title)`, `archive(id)` e `unarchive(id)`;
  - `conversationsProvider` passa a separar ativas e arquivadas (`ConversationLists`).
- **`ConversationListPanel`:**
  - as abas (R6) e o rodapé "Arquivadas · n";
  - na `_Tile`: as ações de hover e foco, a edição na linha e o menu de contexto.
- **`ConversationActions`** (novo, `lib/features/prompt/conversation_actions.dart`): renomear, arquivar com desfazer e desarquivar, usados pela lista, pelo cabeçalho e pelo envio (R7).
- **`_Header`:**
  - o lápis e o modo de edição (`TitleField`, reutilizável na lista);
  - o botão ⋯ com o menu.
- **`PromptSidePanel` / `PromptSideStrip`** (novo): a faixa de 48 px e os balões das seções. O estado recolhido fica em `app_settings` (`prompt.painelRecolhido`).
- **Atalhos:** F2 e Ctrl+Alt+B na tela Prompt; Ctrl+Z ligado ao aviso.

### Testes

- **Repositório:** migração v21→v22, `rename`, `archive` e `unarchive`.
- **Lista:**
  - ações no hover e no foco;
  - clique duplo e F2 renomeiam;
  - título vazio não salva;
  - arquivar tira da lista, move a seleção e mostra Desfazer;
  - Desfazer volta a conversa;
  - as abas aparecem só com arquivadas.
- **Conversa arquivada:** aviso visível e enviar desarquiva.
- **Painel:**
  - recolher e mostrar (botão e Ctrl+Alt+B);
  - a escolha fica guardada;
  - os balões das seções;
  - recolhido por padrão abaixo de 1100 px.

## Decisões

- **Recolher, não esconder.** A faixa de 48 px deixa claro como reabrir e ainda mostra os arquivos citados e os tokens.
- **Ctrl+Alt+B.** Ctrl+\ já é das Sessões lado a lado.
- **Mensagem desarquiva.** É o que a pessoa espera ao voltar a uma conversa antiga; deixá-la só para leitura obrigaria um passo a mais.
- **Arquivar sem confirmar.** Desfazer cobre o engano, e nada é apagado.

Tomadas na implementação:
- **t1 · `conversationsProvider` continua com todas.** A separação fica em `conversationListsProvider` (`ConversationLists`), lido só pela tela Prompt. A atividade da barra lateral, a caixa de entrada e o refino continuam vendo as arquivadas: uma conversa arquivada que ainda responde mantém o ponto "respondendo" e as aprovações (R4).
- **t1 · As abas aparecem sempre que há arquivada,** como diz R6, no lugar do título "CONVERSAS". Os mockups 1–3 mostram o título com 4 arquivadas; seguimos o texto da spec. O rodapé "Arquivadas · n" fica só na aba Ativas (na outra ele repetiria a aba).
- **t1 · Quem desarquiva ao enviar é o `ConversationManager.send`.** Assim vale para todo envio (composer, "Plano pronto", barra da spec na resposta). A lista volta para Ativas ao ver a conversa aberta sair das arquivadas, seja pelo envio ou por Desarquivar.
- **t1 · Ctrl+Z é ouvido pelo teclado inteiro enquanto o aviso está na tela** (`HardwareKeyboard`), porque depois de arquivar o foco pode estar em qualquer lugar. Quando o aviso sai (6 s, Desfazer ou outro aviso), o Ctrl+Z volta a ser do campo de texto.
- **t1 · Desfazer reabre a conversa** quando ela era a aberta.
- **t1 · O menu de uma conversa fechada** carrega a conversa antes de "Transformar em spec". Renomear entra no menu em t2.
- **t1 · A linha das arquivadas mostra o modelo** (`Sonnet · arquivada 3 nov`), como as ativas já fazem, em vez do modo dos mockups.

## Plano

1. **t1 · Arquivar e desarquivar** (R1, R4–R7, R11): schema v22, repositório, `ConversationActions`, ações na linha, menu, abas, aviso com Desfazer, aviso na conversa e testes.
2. **t2 · Renomear** (R2, R3): `TitleField` no cabeçalho e na lista, F2, clique duplo, validação e testes.
3. **t3 · Recolher o painel** (R8–R10): `PromptSideStrip`, balões, preferência guardada, Ctrl+Alt+B, regra de largura e testes.

## Critérios de aceite

- [x] Arquivar uma conversa a tira da lista e mostra o aviso com Desfazer; Desfazer a traz de volta.
- [x] A aba Arquivadas lista as conversas arquivadas e permite desarquivar.
- [x] Mandar uma mensagem numa conversa arquivada a desarquiva.
- [ ] F2, o lápis e o clique duplo renomeiam; título vazio não salva.
- [ ] O painel recolhe numa faixa de 48 px, reabre com Ctrl+Alt+B e lembra a escolha.
- [ ] Em 1100×700 o painel começa recolhido e as seções abrem num balão.
