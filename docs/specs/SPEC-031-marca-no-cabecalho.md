---
id: SPEC-031
status: rascunho
depende-de: SPEC-029
---

# Marca do sistema no cabeçalho, animada enquanto as ondas executam

## Objetivo

O cabeçalho do app (44 px) mostra, ao lado do nome "Promptorium", um quadrado âmbar com um frasco preto genérico (`AppIcons.flask`). Esse desenho não é o ícone do sistema. Desde a SPEC-029, o dock, a bandeja e a janela usam a **marca**: o frasco sem fundo, com líquido verde-água, molécula e contorno âmbar.

Além disso, nada no cabeçalho indica que o app está trabalhando. Quando o Quadro executa uma onda, manualmente ou pelo autopiloto, só o Quadro e o rodapé mostram isso.

Esta spec troca o quadrado âmbar pela marca da SPEC-029. Enquanto houver specs em execução, a marca repete em loop a parte contínua da animação de abertura (`lib/features/splash/`): a onda do líquido corre, as bolhas sobem até o gargalo e as bolhas da molécula surgem.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/NRUsZY4t2xnsTXpX7R775h). Cópia dos artboards e capturas em `docs/mockups/spec-031/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `0-hoje.png` | O cabeçalho de hoje: quadrado âmbar com frasco preto | — |
| `1-proposta.png` | A marca parada e executando, com o tooltip da onda | R1, R3, R7 |
| `2-animacao.png` | Quatro quadros de um ciclo de 2,4 s, ampliados (a bolha de cima chega ao gargalo em 2,2 s), e os estados parado, executando e animação desligada | R4–R6 |
| `3-tamanho.png` | A marca no cabeçalho em 22, 24, 26 e 28 px (escolhido: 26) | R1 |

## Requisitos

- R1 · O cabeçalho (`TitleBar`) deve mostrar a **marca da SPEC-029** no lugar do quadrado âmbar com `AppIcons.flask`:
  - 26 px, com o desenho completo (frasco, líquido, `>_`, bolhas e molécula), sem fundo;
  - o nome "Promptorium" continua ao lado, como hoje.
- R2 · A marca deve ser desenhada em vetor por um widget próprio (`BrandMark`), com as mesmas formas e cores de `assets/icon/mark/mark.svg`. Assim, ela fica nítida em qualquer escala de tela e pode ser animada.
- R3 · A marca deve animar **enquanto alguma spec do projeto ativo estiver em execução**: com estágio `running` e uma sessão viva executando uma etapa ou a verificação. Isso vale para a execução manual e para o autopiloto.
- R4 · A animação segue a **animação de abertura** (`SplashTimeline`), num ciclo de 2,4 s:
  - **onda:** a superfície do líquido é uma onda que corre para a esquerda, um comprimento de onda por ciclo, recortada no interior do frasco, como o `pm-wave` da abertura;
  - **bolhas:** três bolhas nascem no líquido e sobem até o gargalo, onde fica a bolha de cima da marca. Elas são defasadas em 0,8 s, crescem de 0,6 para 1 com entrada acelerada e entram e saem com fade, como o `pm-bubble`;
  - **molécula:** as três bolhas do alto surgem uma depois da outra, com intervalo de 0,18 s, num pulso de 1 para 1,18 e de volta, como o `pm-pop`;
  - a silhueta, o contorno âmbar e o `>_` ficam parados. Nada pisca: o cursor da abertura não pisca aqui, e nenhuma cor nova aparece.
- R5 · Ao começar e ao terminar a execução, a marca troca entre o desenho parado e o animado com um fade de 0,3 s, sem salto. Ao terminar, a animação vai até o fim do ciclo atual antes do fade.
- R6 · Com a animação desligada no sistema (`MediaQuery.disableAnimations`), a marca fica sempre parada. O estado continua disponível no tooltip e no rótulo (R7).
- R7 · A marca deve ter tooltip e rótulo semântico:
  - parada: "Promptorium";
  - executando: "Executando a onda <i> de <n> · <k> specs em execução", com a mesma onda que a faixa do Quadro mostra (`nextWave`, `dependencyWaves`). Com uma onda só, fica apenas "<k> specs em execução".
- R8 · Desempenho: um único `AnimationController`, que só existe enquanto a marca anima, e a marca fica dentro de um `RepaintBoundary`. Parada, ela não repinta.
- R9 · Enquanto a marca anima, clicar nela deve abrir o Quadro do projeto ativo. Parada, ela não faz nada, como hoje. Ela é focável por Tab só enquanto anima.

## Fora do escopo

- O ícone da janela, do dock e da bandeja (SPEC-029).
- Animar a bandeja ou o dock.
- Mostrar no ícone que uma spec precisa de você (SPEC-030).
- A tela "Sobre", que não tem ícone hoje.

## Design

### O que já existe

- `lib/ui/shell/title_bar.dart`: `_Logo` (l.66), um `Container` âmbar de 26 px com `AppIcon(AppIcons.flask, size: 16, color: AppColors.onAmber)` e o texto "Promptorium".
- `assets/icon/mark/mark.svg` (SPEC-029): a marca em 256×256, feita só de linhas, curvas quadráticas e círculos. O líquido é o caminho `M80 168 Q104 154 128 164 T176 162 L211 213 …`, e as bolhas são círculos em (132, 134) e (114, 108).
- `lib/features/board/board_screen.dart`: a faixa do autopiloto calcula "onda <i> de <n>" com `dependencyWaves` e `nextWave` (l.~515), e conta as specs com `stage == running`.
- `sessionManagerProvider` (`isAlive`), `autopilotProvider` e `specsRepoProvider.watchByWorkspace`.
- O projeto não usa `flutter_svg`.

### R1, R2 · `BrandMark`

- `lib/ui/widgets/brand_mark.dart`: `BrandMark({double size = 26, Animation<double>? wave})` com um `CustomPainter` que escala o quadro de 256 para `size` e desenha, em ordem, o mesmo que o SVG faz: o contorno escuro, a molécula, o líquido com a superfície, as bolhas, o `>_` e o contorno âmbar.
- Sem `wave`, o painter desenha o quadro de repouso, igual ao SVG.
- `_Logo` passa a usar `BrandMark` e perde o `Container` âmbar.

### R3, R7 · Estado de execução

- `brandActivityProvider` (`Provider<BrandActivity?>`), em `lib/ui/shell/`: lê as specs do projeto ativo e devolve `null` quando nada roda, ou `(running: k, wave: i, waves: n)`.
- Uma spec conta como "em execução" quando tem `stage == SpecStage.running` e a última sessão está viva (`isAlive`) com `status == running`. Uma spec que espera você (`waitingApproval`, `needsInput`) não conta.

### R4–R6, R8 · Animação

- `_Logo` vira `ConsumerStatefulWidget` com `SingleTickerProviderStateMixin`. Quando `brandActivityProvider != null` e as animações estão ligadas, cria um `AnimationController(duration: 2.4 s)..repeat()`.
- Quando a atividade some, chama `controller.forward()` até 1,0, o fim do ciclo, e então troca para a marca parada com o fade de R5 e descarta o controller.
- O painter reaproveita as curvas da abertura, convertidas para o quadro de 256:
  - a onda é `M… Q… T…`, com comprimento de onda de 76 e amplitude de 7 no nível 164, deslocada em `−76·t`;
  - as bolhas saem de (128, 204), (114, 208) e (140, 210), com raios 11, 8 e 7, e sobem 104 com `easeIn`;
  - opacidade: 0 → 1 até 20% do caminho, 1 → 0,9 até 80%, depois 0;
  - os nós da molécula ficam em (132, 34), (180, 22) e (196, 60).
- Se der, `SplashTimeline.bubble` e a curva da onda viram funções compartilhadas em `lib/ui/widgets/brand_motion.dart`, para que a abertura e a marca não divirjam.
- O fade de R5 é um `AnimatedSwitcher` de 300 ms entre `BrandMark()` e `BrandMark(wave: controller)`.

### Testes

- `test/ui/widgets/brand_mark_test.dart`:
  - pinta sem erro em 16, 26 e 64 px;
  - sem `wave`, as bolhas ficam nas posições do SVG;
  - com `wave`, a onda se desloca, as bolhas sobem até y ≤ 110 em algum ponto do ciclo, e a molécula chega a 1,18.
- `test/ui/shell/title_bar_logo_test.dart`:
  - o cabeçalho mostra `BrandMark` e não mostra `AppIcons.flask` (R1);
  - sem specs rodando, não há controller e o rótulo é "Promptorium";
  - com uma spec `running` e uma sessão viva, há um controller de 2,4 s e o rótulo é "Executando a onda 1 de 2 · 1 spec em execução" (R3, R7);
  - ao terminar a execução, o controller anda até o fim do ciclo e some (R5);
  - clicar na marca animada abre o Quadro (`AppSection.board`); parada, o clique não muda a seção (R9);
  - com `disableAnimations`, não há controller, mas o rótulo de execução continua (R6).

## Critérios de aceite

- [ ] O cabeçalho mostra a marca de 26 px, sem o quadrado âmbar [R1] [R2] verificar: flutter test test/ui/shell/title_bar_logo_test.dart
- [ ] `BrandMark` desenha o repouso igual ao SVG e, animado, faz a onda correr, as bolhas subirem até o gargalo e a molécula pulsar [R2] [R4] verificar: flutter test test/ui/widgets/brand_mark_test.dart
- [ ] A marca anima só com spec em execução, num ciclo de 2,4 s, e para no fim do ciclo [R3] [R4] [R5] [R8] verificar: flutter test test/ui/shell/title_bar_logo_test.dart
- [ ] Com `disableAnimations` nada anima, e o rótulo mostra a execução [R6] [R7] verificar: flutter test test/ui/shell/title_bar_logo_test.dart
- [ ] Clicar na marca animada abre o Quadro; parada, não faz nada [R9] verificar: flutter test test/ui/shell/title_bar_logo_test.dart
- [ ] No app, com uma onda rodando, o líquido ondula no cabeçalho (verificação manual) [R3] [R4] verificar: manual (executar uma spec no Quadro e olhar o cabeçalho)
- [ ] A análise estática passa sem avisos novos [R1] [R2] [R3] [R4] [R5] [R6] [R7] [R8] [R9] verificar: flutter analyze

## Decisões

- (P1) "Executando as ondas" é qualquer spec do projeto ativo em execução, seja manual ou pelo autopiloto. Conversas do Prompt não contam (R3).
- (P2) 26 px, com o desenho completo da marca: é o mesmo tamanho do quadrado de hoje, e o desenho simples não tem bolhas para animar (R1).
- (P3) Enquanto anima, clicar na marca abre o Quadro do projeto ativo. Parada, ela não faz nada (R9).
- (P4) A marca não muda quando uma spec precisa de você. O sinal de atenção fica no Quadro e no sino de notificações.
- Implementação: o clique que abre o Quadro (R9) vale enquanto há specs em execução, mesmo com a animação desligada no sistema. Assim, quem usa "reduzir movimento" também tem o atalho.
- Implementação: a onda animada é recortada no formato do líquido parado (`_liquidBounds`, os lados e o fundo do líquido do SVG, prolongados até o gargalo). Por isso o fundo escuro do frasco aparece igual nos dois estados. As bolhas só são recortadas pelo interior do frasco, para chegarem ao gargalo.
- Implementação: as bolhas sobem 104 em vez de 100, para que a bolha visível passe do nível 110 do gargalo.
- Implementação: o estado vem de `brandActivityProvider` (`lib/ui/shell/brand_activity.dart`), que observa só quais sessões estão vivas, e não cada evento delas.

