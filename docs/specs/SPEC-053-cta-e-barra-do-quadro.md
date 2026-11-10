---
id: SPEC-053
status: aprovada
depende-de: SPEC-049
issue: 132
---

# Botão "Nova spec" animado e barra do Quadro em três zonas

## Objetivo

O botão "Nova spec" é a ação principal da barra de título, mas não reage quando o mouse passa ou quando a pessoa clica. Ele fica igual a qualquer etiqueta âmbar. A barra do Quadro também mistura tudo em uma linha só:
- o título, as Sprints e os filtros ficam à esquerda;
- a troca de visão (Colunas, Grafo e Foco) fica colada a Agendar e Executar tudo, no canto direito.

O resultado é que a troca de visão e a execução parecem um bloco só.

Esta spec faz duas coisas:
- dá ao "Nova spec" uma resposta de movimento curta e com propósito: ao passar o mouse, ao clicar, ao receber o foco do teclado e quando o workspace ainda não tem nenhuma spec;
- separa a barra do Quadro em três zonas:
  - **esquerda:** o título, as Sprints e os filtros;
  - **centro:** a troca de visão Colunas, Grafo e Foco, num controle segmentado único;
  - **direita:** Agendar e Executar tudo.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/FxRMzU3yZ3qQUhqwSjfMT9), validado com `/validar-layouts` (nota média 86, "Pronto para entregar"; o relatório está na issue). Capturas em `docs/mockups/spec-053/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-antes.png` | O Quadro hoje, com a troca de visão colada a Agendar e Executar tudo | — |
| `2-depois.png` | O Quadro em três zonas, com o controle segmentado no centro | R7–R9 |
| `3-nova-spec-estados.png` | Os estados do "Nova spec": repouso, mouse em cima, pressionado, foco, atenção e movimento reduzido | R1–R6 |
| `4-vazio.png` | Workspace sem specs: só o "Nova spec" respira | R4 |
| `5-estreito.png` | O Quadro em 1100×700, com os filtros juntos no chip "Filtros" | R9 |

## Requisitos

- R1 · Quando o mouse entra no "Nova spec", o botão deve reagir em até 120 ms:
  - o fundo âmbar clareia (`#F6B662`);
  - surge um brilho âmbar suave em volta;
  - o "+" gira 90°;
  - um reflexo de luz cruza o botão uma vez, da esquerda para a direita, em cerca de 450 ms.

  Quando o mouse sai, tudo volta ao repouso em até 120 ms, sem repetir o reflexo.
- R2 · Ao pressionar o "Nova spec", o botão deve encolher para 97% e o brilho diminuir; ao soltar, volta ao tamanho e abre a nova spec. A animação nunca atrasa a abertura.
- R3 · Com o foco do teclado, o "Nova spec" deve mostrar um anel de foco de 2 px, separado do botão, com contraste de pelo menos 3:1 sobre o fundo. O anel não depende do mouse.
- R4 · Quando o workspace ativo não tem nenhuma spec e a tela é Specs ou Quadro, o "Nova spec" deve chamar a atenção com uma respiração do brilho:
  - o brilho sobe e desce em um ciclo de 2,4 s;
  - a respiração para de vez quando a pessoa passa o mouse, foca o botão ou cria a primeira spec;
  - só esse botão pode respirar na tela; nenhuma outra chamada à ação anima ao mesmo tempo.
- R5 · Com movimento reduzido (sistema ou app), o "Nova spec" não deve girar, encolher, refletir nem respirar. O mouse em cima e o pressionar só mudam a cor, e o anel de foco continua.
- R6 · As animações do "Nova spec" não podem pedir quadros quando nada muda:
  - o reflexo, o giro e o encolher são de uma vez só;
  - a respiração usa o relógio de ambiente (24 quadros/s, SPEC-049);
  - parado e sem a respiração, o botão não pede nenhum quadro.
- R7 · A barra do Quadro deve ter três zonas:
  - **esquerda:** "Quadro", o contador, as Sprints e os filtros;
  - **centro:** Colunas, Grafo e Foco, centralizados na largura da barra (e não no espaço que sobra);
  - **direita:** a linha de estado do automático, os rascunhos fora do quadro, Agendar e Executar tudo, alinhados à direita.

  Executar tudo continua sendo o único botão cheio da barra.
- R8 · Colunas, Grafo e Foco devem formar um controle segmentado único:
  - um grupo de vidro com um indicador que desliza até a visão escolhida em 200 ms (sem deslizar com movimento reduzido);
  - para o leitor de tela, o grupo se anuncia como "Visão do quadro", e cada opção como selecionada ou não;
  - as setas do teclado trocam de visão dentro do grupo.
- R9 · Em larguras estreitas (até 1100×700), as zonas não podem se sobrepor:
  - se a esquerda não couber, os filtros (Precisam de mim, Ocultar concluídas, Fase e Agente) se juntam num chip "Filtros", com o número de filtros ativos; o chip abre um menu com cada um;
  - se ainda faltar espaço, o controle segmentado sai do centro e fica logo depois da esquerda, ainda antes da zona da direita;
  - a linha de estado e os rascunhos encurtam com reticências antes de qualquer botão;
  - Agendar e Executar tudo nunca saem da tela.

## Fora do escopo

- Animar outros botões da barra de título ou das telas.
- Mudar o que Agendar, Executar tudo, Colunas, Grafo ou Foco fazem.
- Novos filtros no Quadro.
- Som ou vibração.

## Design

### O que já existe

- `lib/ui/shell/title_bar.dart`:
  - `_ActionButton` desenha o "Nova spec" sobre `_BarButton`, com fundo âmbar, o ícone `AppIcons.plus` e o texto em `onAmber`;
  - o rótulo vem de `AppSection.actionLabel`, em `navigation.dart`.
- `lib/ui/widgets/app_pressable.dart`: `AppPressable` já faz o encolher ao pressionar (`pressedScale` 0,98), o tom ao passar o mouse e o "claim" para controles aninhados.
- `lib/ui/theme/ambient.dart`: `AmbientVsync`, o relógio de ambiente a 24 quadros/s (SPEC-049 t5).
- `lib/features/board/board_screen.dart`, barra do Quadro, nesta ordem:
  - a esquerda com as Sprints e os chips de filtro;
  - `board-strip`, com `Expanded(flex: 3)`;
  - os rascunhos;
  - três `ToggleBox` (`board-view-columns`, `-graph` e `-focus`);
  - `board-schedule` (Agendar) e `board-autopilot` (Executar tudo / Parar).
- `AppMotion` (`lib/ui/theme/motion.dart`) decide se há animação (`AppMotion.animate`).

### Componentes

- **`CtaButton`** (novo, em `lib/ui/widgets/`): o botão âmbar com os estados de R1 a R5. Ele substitui o miolo de `_ActionButton`:
  - o giro do "+" e o encolher usam um `AnimationController` de uma vez só;
  - o reflexo é um `ShaderMask` com um degradê que anda uma vez;
  - a respiração usa `AmbientVsync` e só existe enquanto `attention` for verdadeiro.
- **`TitleBar`**: passa `attention` ao `CtaButton` quando o workspace ativo não tem specs e a seção é Specs ou Quadro (de `specsProvider`).
- **`BoardViewSwitch`** (novo): o controle segmentado de R8, com `Semantics(label: 'Visão do quadro')`, um indicador animado e as setas do teclado. Ele substitui os três `ToggleBox` e mantém as chaves `board-view-*` em cada opção.
- **Barra do Quadro**: um `Stack` com o `BoardViewSwitch` centralizado por cima de uma `Row`:
  - a `Row` leva a esquerda e a direita, separadas por um `Spacer`;
  - quando a esquerda mede mais que (largura − controle) / 2, a barra troca o `Stack` por uma `Row` de três filhos (R9).

### Testes

- `CtaButton`:
  - mouse em cima: o "+" gira e o reflexo roda uma vez (não fica `hasRunningAnimations` depois de 600 ms);
  - pressionar: encolhe e solta;
  - foco: o anel aparece;
  - movimento reduzido: nada gira.
- **Atenção**: com 0 specs, `AmbientTicker.debugActive` é maior que 0; ao passar o mouse ou com uma spec criada, volta a 0.
- **Barra do Quadro**: em 1440 px, o centro do `BoardViewSwitch` fica a até 1 px do centro da barra, e Executar tudo é o último filho à direita.
- **Barra estreita**: em 1100 px, com todos os filtros, eles se juntam no chip "Filtros", nada se sobrepõe (retângulos sem interseção) e os dois botões ficam visíveis.
- **`BoardViewSwitch`**: as setas trocam de visão, e a semântica anuncia "Visão do quadro" e a opção selecionada.

## Decisões

Tomadas na implementação:
- **"+" em toda ação da barra de título.** Antes só "Nova sessão" tinha o ícone; o giro de R1 precisa dele, e o botão ficou igual em todas as seções.
- **Quatro áreas na barra, não três.** O `BoardBarLayout` posiciona a esquerda, o controle segmentado, a linha de estado e as ações. As ações (Agendar, Executar tudo) nunca encolhem; a linha de estado e os rascunhos ocupam o que sobra entre o centro e as ações, com reticências. Agendar mostra até 160 px do rótulo do agendamento, com o texto inteiro no tooltip.
- **Quando os filtros se juntam:** abaixo de 1120 px de barra (janela de cerca de 1240 px). Medir o texto dos chips falhava na fonte dos testes; a largura fixa é previsível. A esquerda guarda 400 px para as ações; dobrada, ela corta em vez de transbordar.
- **O controle segmentado é uma parada de Tab.** As setas trocam de visão, como num grupo de rádio; clicar numa opção também dá o foco ao grupo. O anel de foco é o mesmo do "Nova spec".

## Plano

1. `CtaButton` com repouso, mouse em cima, pressionado e foco (R1–R3, R5) e os testes. Trocar em `_ActionButton`.
2. A respiração de atenção (R4, R6) e a ligação com `specsProvider` na `TitleBar`.
3. `BoardViewSwitch` (R8) e a barra do Quadro em três zonas (R7, R9), com os testes de layout.
4. Capturas do app real em `docs/mockups/spec-053/app/` e o guia (`docs/guia/quadro.md`).

## Critérios de aceite

- [x] Passar o mouse no "Nova spec" faz o "+" girar e um reflexo cruzar o botão uma vez; ao sair, ele volta ao repouso sem repetir.
- [x] Pressionar encolhe o botão e soltar abre a nova spec, sem atraso.
- [x] O foco do teclado mostra o anel em volta do botão.
- [x] Num workspace sem specs, o botão respira até a pessoa interagir ou criar uma spec.
- [x] Com movimento reduzido, o botão só muda de cor.
- [x] Parado, o botão não pede quadros (`PROMPTORIUM_QUADROS`).
- [x] No Quadro em 1440×900, Colunas/Grafo/Foco ficam no centro da barra, e Agendar e Executar tudo à direita.
- [x] Em 1100×700, com todos os filtros, nada se sobrepõe e os dois botões ficam visíveis.
- [x] As setas trocam de visão, e o leitor de tela anuncia "Visão do quadro".

## Perguntas em aberto

- P1 · A respiração de atenção também deve aparecer na tela Início, quando não há workspace? Sugestão: não, porque lá a ação principal é adicionar um workspace.
