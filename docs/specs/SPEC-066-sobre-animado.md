---
id: SPEC-066
status: aprovada
issue: 187
---

# O Sobre com a logo viva

## Objetivo

O Sobre (F1) toca a animação da abertura e, depois de 2,6 s, a logo para no estado final (SPEC-038 R2). A coluna da direita aparece de uma vez, junto com o diálogo. A tela fica parada demais para a única janela do app que fala da identidade dele.

Esta spec faz a logo **continuar viva** num ritmo calmo depois da abertura: o líquido balança devagar, sobe uma bolha de cada vez, o cursor pisca e o brilho respira. Passar o mouse agita o frasco, e clicar toca a abertura de novo. A coluna da direita **entra em cascata**: o cabeçalho, o cartão de atualização e as novidades, uma linha depois da outra.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/9SPRb9HhTJTW2FPG6EmNc2) (no canvas as animações rodam e a logo responde ao mouse e ao clique). Capturas em `docs/mockups/spec-066/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-antes.png` | Hoje: a logo parada depois da abertura | — |
| `2-logo-viva.png` | A logo no ritmo calmo, com as marcações do que se move | R2, R3 |
| `3-mouse.png` | O mouse sobre a logo: o frasco agitado e a dica | R4, R5 |
| `4-entrada.png` | A entrada da coluna da direita, quadro a quadro | R1 |
| `5-reduzido.png` | Movimento reduzido: tudo parado, sem cascata | R8 |
| `6-download.png` | Baixando: o líquido sobe junto com a barra do cartão | R10 |

## Requisitos

- R1 · Ao abrir o Sobre, a coluna da direita entra em cascata, depois do diálogo (SPEC-034):
  - a ordem é o cabeçalho, o cartão de atualização, o título "Novidades da …" e cada linha das novidades;
  - cada parte aparece em 220 ms (`AppMotion.emphasis`, curva `AppMotion.enter`), subindo 8 px e saindo da transparência;
  - o cartão começa 60 ms depois do cabeçalho, o título 60 ms depois do cartão e as linhas 40 ms uma da outra, até a sexta; da sétima em diante entram juntas com a sexta;
  - a cascata inteira cabe em 640 ms (`AppMotion.section`), e o foco vai para a ação do cartão na hora, sem esperar a cascata (SPEC-038 R11).
- R2 · A logo toca a abertura como hoje e, ao terminar, segue no **ritmo calmo**, sem parar enquanto o Sobre estiver aberto:
  - a onda do líquido anda na metade da velocidade do splash (um ciclo a cada 4,4 s);
  - sobe uma bolha por vez, a cada 2,4 s, alternando as três bolhas do desenho;
  - o cursor `_` pisca a cada 1 s, como no splash;
  - o brilho atrás do frasco respira entre 35% e 55% de opacidade em 4 s.
- R3 · O ritmo calmo é mais quieto que o splash: os nós e as ligações ficam parados, e nada da logo sai do quadrado dela. A versão e os links abaixo dela não se mexem.
- R4 · Com o mouse sobre a logo, o frasco fica **agitado** enquanto o mouse estiver ali:
  - a onda e as bolhas voltam ao ritmo do splash (onda a cada 2,2 s, três bolhas a cada 0,8 s);
  - os três nós acendem um depois do outro, do menor ao maior, a cada 0,9 s, com o contorno em âmbar-claro (`AppColors.amberLight`) e um brilho curto;
  - o cursor do mouse vira a mãozinha, e a dica "Tocar a abertura de novo" aparece depois de 500 ms;
  - ao tirar o mouse, a logo volta ao ritmo calmo em 400 ms, sem salto.
- R5 · Clicar na logo, ou apertar Enter ou Espaço com o foco nela, toca a abertura de novo, do contorno se desenhando ao brilho. Enquanto a abertura toca, novos cliques não fazem nada. No fim, a logo volta ao ritmo calmo (ou ao agitado, se o mouse ainda estiver em cima).
- R6 · A logo entra na ordem do Tab depois do cartão de atualização e antes dos links, com o anel de foco âmbar de sempre. O leitor de tela ouve "Ícone do Promptorium, botão, tocar a abertura de novo".
- R7 · A animação gasta só o que aparece:
  - com a janela do app fora de foco ou minimizada, a logo para onde está e continua quando a janela volta;
  - com a confirmação de cancelar o download aberta por cima (SPEC-038 R9), a logo para;
  - ao fechar o Sobre, o ticker para de vez; reabrir toca a abertura de novo, como hoje.
- R8 · Com movimento reduzido (o ajuste do sistema ou "Reduzir animações" do app), nada se move: a logo aparece no estado final, sem bolhas (SPEC-038 R3), a coluna da direita aparece de uma vez, o mouse não agita nada e a logo não é um botão (fica fora do Tab e o clique não faz nada).
- R9 · O splash não muda: continua com o próprio ritmo e sem responder ao mouse.
- R10 · Enquanto uma atualização baixa (cartão **Baixando**), o nível do líquido acompanha o progresso:
  - vazio em 0% e cheio (o nível de hoje) em 100%, subindo suave a cada atualização do progresso;
  - a onda e as bolhas seguem o ritmo da logo (calmo ou agitado), na superfície do líquido;
  - ao terminar o download, as três bolhas sobem juntas uma vez; ao cancelar, o líquido volta ao nível cheio em 400 ms;
  - com movimento reduzido, o nível também acompanha o progresso, sem onda nem bolhas.

## Fora do escopo

- O desenho da logo, as cores e o conteúdo do Sobre.
- O cartão de atualização e os estados dele (SPEC-038).
- O splash e a animação da abertura em si.

## Design

### O que já existe

- `lib/ui/shell/about_dialog.dart`: `AboutPromptoriumDialog`, com `_Identity` (a coluna da esquerda, que usa `SplashStage(loop: false)`), `_Header`, `UpdateCard` e `_News`.
- `lib/features/splash/splash_stage.dart`: `SplashStage`, dono do ticker, com `loop`.
- `lib/features/splash/splash_painter.dart`: `SplashTimeline` (a introdução a 1,75×, a onda, as bolhas, o cursor e o brilho) e `SplashPainter`.
- `AppMotion` (`lib/ui/theme/motion.dart`): durações, curvas e `AppMotion.animate(context)`.

### Componentes

- **`SplashAmbient`** (novo enum): `none` (o estado final parado, o Sobre de hoje), `calm` (R2, R3), `lively` (o splash e o mouse em cima, R4). `SplashTimeline` recebe o modo e calcula a onda, as bolhas, o brilho e o acender dos nós a partir dele. `loop: true` vira `ambient: lively`; `loop: false` vira `ambient: none`.
- **`SplashStage`** ganha `ambient`, `interactive` e `replay()`. A troca de modo mistura os dois ritmos em 400 ms (R4). `replay()` zera o relógio da introdução e ignora chamadas enquanto ela toca (R5).
- **`AboutLogo`** (novo, em `about_dialog.dart`): envolve o `SplashStage` com `MouseRegion` (calmo ↔ agitado), `FocusableActionDetector` (Enter, Espaço e o anel de foco), `Tooltip` (500 ms), `Semantics(button: true)` e o clique que chama `replay()`. Com movimento reduzido, ele devolve só o `SplashStage` parado (R8).
- **Nível do líquido** (R10): `SplashStage` recebe `level` (0 a 1, ou nulo para o nível cheio de hoje); `SplashTimeline.liquidDy` soma o deslocamento do nível, animado em 300 ms. `AboutLogo` lê o `updateFlowProvider` e passa o progresso do `UpdateDownloading`.
- **Pausa** (R7): `SplashStage` observa `AppLifecycleState` (`inactive`, `hidden` ou `paused` param o ticker, `resumed` continua de onde parou) e recebe `paused: true` enquanto a confirmação do download está aberta.
- **`StaggeredEntrance`** (novo, em `lib/ui/widgets/`): um widget que recebe o índice da parte e anima a opacidade e o deslocamento com o atraso do R1, a partir de um único `AnimationController` do diálogo. Com movimento reduzido, mostra tudo de uma vez.

### Testes

- O ritmo calmo: onda com período de 4,4 s, uma bolha por vez a cada 2,4 s e o brilho entre 0,35 e 0,55; os nós parados.
- O agitado: com o mouse em cima, onda de 2,2 s e os nós acendendo em sequência; ao sair, volta ao calmo em 400 ms.
- O clique, o Enter e o Espaço tocam a abertura; um segundo clique no meio não reinicia.
- A ordem do Tab (cartão → logo → links) e o rótulo do leitor de tela.
- A pausa com a janela fora de foco e com a confirmação do download; nenhum ticker depois de fechar.
- A cascata: os atrasos de cada parte, o teto de 640 ms e o foco na ação do cartão no primeiro quadro.
- Movimento reduzido: logo parada e sem bolhas, sem cascata, a logo fora do Tab e o clique sem efeito.
- O splash continua igual (`ambient: lively`, sem mouse).

## Decisões

- **Revê a SPEC-038 D4.** Lá a logo parou porque "movimento contínuo ao lado do texto distrai". O ritmo calmo resolve isso com pouco movimento e lento (uma bolha a cada 2,4 s, onda na metade da velocidade), longe do texto e sem nada que pisque além do cursor.
- **Agitar com o mouse, não sozinho.** O movimento mais forte só acontece quando a pessoa aponta para a logo; parado, ela só respira.
- **Clique toca a abertura.** É o jeito de "ver de novo" que a D4 deixava só para quem reabria a tela.
- **Cascata curta.** 640 ms no total e o foco já na ação: quem abriu o Sobre para atualizar não espera a animação.
- **A logo vira botão só com movimento.** Com movimento reduzido o clique não teria o que mostrar, então ela fica um ícone comum, fora do Tab.
- **O frasco enche com o download (era P1).** O líquido já é a metáfora do laboratório trabalhando; enchê-lo com o progresso liga a logo ao cartão ao lado, sem texto novo.
- **O ritmo calmo não para sozinho (era P2).** Ele já para com a janela fora de foco (R7), e o custo de um `CustomPaint` de 148 px é pequeno.

## Plano

1. **t1 · Logo viva** (R2–R9): `SplashAmbient`, os modos calmo e agitado em `SplashTimeline`, `replay()`, a pausa, `AboutLogo` com mouse, clique, teclado e leitor de tela, e os testes.
2. **t2 · Entrada do Sobre** (R1, R8): `StaggeredEntrance`, a cascata da coluna da direita e os testes.
3. **t3 · O líquido do download** (R10): o nível do líquido em `SplashTimeline`, ligado ao `UpdateDownloading`, e os testes.

## Critérios de aceite

- [ ] Depois da abertura, a logo segue no ritmo calmo enquanto o Sobre estiver aberto.
- [ ] Com o mouse em cima, a logo fica agitada; ao sair, volta ao calmo sem salto.
- [ ] Clicar na logo, ou Enter e Espaço com o foco nela, toca a abertura de novo.
- [ ] A logo para com a janela fora de foco e com a confirmação do download por cima.
- [ ] A coluna da direita entra em cascata em até 640 ms, com o foco já na ação do cartão.
- [ ] Com movimento reduzido, nada se move e a logo não é um botão.
- [ ] Enquanto baixa uma atualização, o líquido do frasco acompanha o progresso.
- [ ] O splash continua igual.
