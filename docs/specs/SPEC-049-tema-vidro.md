---
id: SPEC-049
status: aprovada
depende-de: SPEC-034
issue: 118
---

# Tema Vidro

## Objetivo

O Promptorium hoje é todo opaco: fundo `#0E1014`, painéis `#14171D` e bordas `#252B35`, sem profundidade. A pessoa quer uma interface mais limpa e futurista, com transparência e efeitos, sem perder a leitura nem o desempenho.

Esta spec troca o visual do app pelo tema **Vidro**:
- os painéis ficam translúcidos sobre um fundo escuro com duas manchas de luz (âmbar e teal) e uma grade de pontos discreta;
- a casca (barra lateral, cabeçalho e rodapé) vira cápsulas flutuantes;
- o brilho aparece só no que está vivo ou precisa da pessoa.

As cores, as fontes e a estrutura das telas continuam as mesmas. Não há troca de temas nesta spec: o Vidro substitui o visual atual, com uma opção para desligar os efeitos.

Issue: [#118](https://github.com/mayroncachina/promptorium/issues/118).

Mockup: [canvas do Claude Design](https://claude.ai/artifact/44UbgcC7UexHUpz5WUTw1d), linha "A · Vidro". Capturas em `docs/mockups/spec-049/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-quadro.png` | Quadro com a casca flutuante, colunas e cartões em vidro e o brilho do card em execução | R1–R4 |
| `2-repositorio.png` | Grafo com as raias e o painel do commit em vidro | R3, R4 |
| `3-sessao.png` | Sessão do agente: etapas, conversa, compositor e gate | R3, R4 |
| `4-linguagem.png` | A linguagem visual: níveis de vidro, borda e luz, cor, movimento e notas do Flutter | R1–R6 |

## Requisitos

- R1 · O fundo do app deve ser escuro, com duas manchas de luz suaves (âmbar no canto de cima à esquerda e teal no de baixo à direita) e uma grade de pontos discreta:
  - pintado uma vez atrás de tudo, sem repintar quando as telas mudam;
  - as manchas não podem baixar o contraste de nenhum texto abaixo de 4,5:1.
- R2 · A casca deve virar vidro flutuante:
  - a barra lateral, o cabeçalho e o rodapé ficam soltos das bordas da janela, com cantos arredondados;
  - o item ativo da barra lateral ganha borda e brilho âmbar;
  - a área das telas continua cabendo em 1100×700 sem cortar nada.
- R3 · Painéis e cartões devem ser translúcidos, em dois níveis:
  - **casca** (painéis, colunas, barras laterais das telas): fundo a cerca de 52%, borda de 1 px branca a 7% e um fio de luz de 1 px no topo;
  - **cartão** (cartões, campos, controles): fundo a cerca de 55%, um pouco mais claro;
  - um widget comum desenha os dois níveis, e as telas param de montar a decoração à mão;
  - onde o conteúdo rola por baixo de algo fixo (cabeçalhos grudados, sobreposições), a superfície continua opaca, para o texto de baixo não aparecer.
- R4 · O brilho deve marcar só estado vivo:
  - item ativo da navegação, sessão rodando, etapa em execução, "precisa de você" e foco do teclado;
  - nada decorativo brilha.
- R5 · Diálogos (inclusive a paleta de comandos, os atalhos e a central de notificações) devem desfocar o que está atrás; menus, dropdowns, avisos e tooltips, que flutuam sem diálogo, ficam opacos:
  - um único nível de desfoque por região;
  - listas longas (grafo, diff, conversa, terminal) nunca desfocam item por item.
- R6 · Configurações deve ter "Efeitos de vidro", ligado por padrão:
  - desligado, os painéis voltam a ser opacos (as cores atuais) e nada desfoca, sem mudar o layout;
  - a variável `PROMPTORIUM_SEM_VIDRO=1` também desliga os efeitos ao abrir o app.
- R7 · O desempenho deve ser medido antes e depois:
  - com `PROMPTORIUM_QUADROS=<arquivo>`, o app grava a cada 5 segundos o tempo de build e de raster dos quadros (p50, p90 e p99) e quantos passaram de 16,7 ms;
  - um script percorre as telas do app aberto, com rolagem, paleta e diálogos, e compara duas medições;
  - com o Vidro ligado, o p90 de raster não pode piorar mais de 2 ms em relação ao visual atual, na mesma máquina.
- R8 · O guia deve dizer o requisito mínimo do app:
  - medido também com renderização por software (`LIBGL_ALWAYS_SOFTWARE=1`) e com dois núcleos de CPU;
  - se o Vidro passar do limite numa máquina fraca, o guia diz quando desligar os efeitos.

## Fora do escopo

- Troca de temas em Configurações (escolher entre Vidro, Grafite, Porcelana…). Fica para outra spec, que pode partir dos tokens desta.
- Tema claro.
- Mudar a estrutura das telas, a navegação ou os textos.
- Desfoque com o conteúdo real da janela atrás do app (transparência da janela no desktop).

## Design

### O que já existe

- `lib/ui/theme/tokens.dart`: `AppColors` com 51 cores constantes, usadas 2.780 vezes em 145 arquivos.
- `lib/ui/theme/app_theme.dart`: o `ThemeData` escuro, fixo.
- `lib/ui/shell/app_shell.dart`: o `Scaffold` com `TitleBar`, `SideBar`, as telas e o `StatusFooter`.
- `lib/ui/shell/side_bar.dart`: a barra de 56 px com o destaque que desliza (SPEC-034).
- `lib/ui/widgets/app_dialog.dart` e `app_toast.dart`: o diálogo e o aviso padrão.
- 360 `BoxDecoration` montados à mão em 103 arquivos.

### Componentes

- `lib/ui/theme/glass.dart` (novo): `GlassBackdrop` (o fundo de R1, num `RepaintBoundary`), `AppGlass` (os dois níveis de R3, com `opaque` para as superfícies de R3 que não podem vazar) e `GlassBlur` (o desfoque de R5).
- `AppColors`: `background` e `panel` passam a ter versões translúcidas; `panelSolid` e `backgroundSolid` guardam as opacas para R3 e R6.
- `lib/core/perf/frame_monitor.dart` (novo): o registro de R7, ligado só pela variável.
- `scripts/medir_quadros.py` (novo): percorre as telas com `xdotool` e resume os registros.
- `glassEffectsProvider`: a opção de R6, salva em Configurações.

### Testes

- `test/ui/theme/glass_test.dart`: os dois níveis, o modo opaco, a opção desligada e `PROMPTORIUM_SEM_VIDRO`.
- `test/core/perf/frame_monitor_test.dart`: percentis e contagem de quadros lentos.
- Os testes atuais de cada tela continuam passando com o Vidro ligado.
- Teste do layout em 1100×700 com a casca flutuante.

## Decisões

- **Translucidez sem desfoque nos painéis.** O fundo atrás dos painéis é um degradê suave, então um painel translúcido já parece fosco sem `BackdropFilter`. O desfoque, que é o que custa GPU, fica só onde algo passa por cima de conteúdo (R5).
- **Um nível de desfoque por região.** Vidro sobre vidro multiplica o custo e embaça demais.
- **Superfícies opacas onde o conteúdo rola por baixo.** Um cabeçalho grudado translúcido mostraria o texto de baixo, o que fica pior que opaco.
- **Efeitos desligáveis.** Em placas de vídeo fracas, em compositores sem aceleração ou para quem prefere, o app volta ao visual opaco sem perder nada.

Decisões tomadas na implementação:

- **Tokens translúcidos calculados sobre o fundo de antes.** `panel` e `surfaceRaised` viraram vidro com valores que, sobre `#0E1014`, compõem exatamente as cores opacas de antes. Por isso nenhum dos 364 `const` mudou, e com os efeitos desligados (fundo liso) o app fica igual ao visual anterior. As versões opacas ficaram em `panelSolid`, `surfaceRaisedSolid` e `backgroundSolid`.
- **`background` é preto a 30%, não transparente.** Ele também é usado em poços (blocos de código, campos). Sobre um painel, o preto a 30% dá o `#0E1014` de antes e o poço mantém a profundidade; na página, só escurece um pouco o fundo de vidro.
- **O fundo é uma imagem.** A primeira versão redesenhava os degradês e cerca de 1.600 pontos a cada quadro e subiu o p90 de raster de 15,8 para 22,2 ms. O fundo agora é desenhado uma vez por tamanho de janela, e cada quadro só copia a imagem.
- **Menus, dropdowns, InfoTip e a pasta do Canvas são opacos.** Eles flutuam sobre conteúdo sem um diálogo por trás. No teste, a lista do dropdown "Modo de permissão" mostrava o campo e os botões através das opções. O desfoque de R5 ficou nos diálogos (que incluem a paleta, os atalhos e a central de notificações). Os tooltips do Material já eram opacos.
- **O desfoque do diálogo lê a opção sem depender do Riverpod** (`glassEffectsOf`), porque vários testes abrem diálogos sem `ProviderScope`.
- **A casca ganhou 8 px de folga, não 16.** Com 16 px, os 10 itens da barra lateral e a engrenagem não caberiam em 1100×700.
- **"Efeitos de vidro" fica em Configurações › Aparência**, uma seção nova do grupo App.

## Plano

1. Validar o mockup (tabela no início da spec).
2. Medidor de quadros e medição do visual atual (R7).
3. Fundo, tokens translúcidos e `AppGlass` (R1, R3).
4. Casca flutuante e brilho (R2, R4).
5. Desfoque das sobreposições e a opção de R6 (R5, R6).
6. Varredura visual de todas as telas, correções, medição do Vidro e requisito mínimo (R7, R8).
7. Aparência em `docs/guia/configuracoes.md` e requisito mínimo em `docs/guia/instalacao.md`.

## Critérios de aceite

- [x] O fundo tem as duas manchas e a grade, pintado uma vez [R1] verificar: flutter test test/ui/theme/glass_test.dart
- [x] Barra lateral, cabeçalho e rodapé flutuam em vidro, e as telas cabem em 1100×700 [R2] verificar: flutter test test/ui/shell
- [x] Painéis e cartões usam os dois níveis de vidro, e as superfícies sob rolagem continuam opacas [R3] verificar: flutter test test/ui/theme/glass_test.dart
- [x] Só estado vivo brilha [R4] verificar: manual (percorrer as telas com uma sessão rodando)
- [x] Diálogos desfocam o fundo, num nível só; menus, avisos e tooltips ficam opacos [R5] verificar: flutter test test/ui/theme/glass_test.dart
- [x] "Efeitos de vidro" desligado e `PROMPTORIUM_SEM_VIDRO=1` voltam ao visual opaco sem mudar o layout [R6] verificar: flutter test test/ui/theme/glass_test.dart
- [x] O medidor grava percentis de build e raster e os quadros lentos [R7] verificar: flutter test test/core/perf/frame_monitor_test.dart
- [x] Com o Vidro, o p90 de raster piora no máximo 2 ms em relação ao visual atual [R7] verificar: manual (scripts/medir_quadros.py antes e depois)
- [x] O guia traz o requisito mínimo, medido também com renderização por software e dois núcleos [R8] verificar: manual (ler docs/guia/instalacao.md)
- [x] Todas as telas abrem sem nada quebrado, testado num projeto Flutter de calculadora criado pelo app [R1–R6] verificar: manual (percorrer o app com o projeto de teste)
- [x] O projeto compila e a análise estática passa [R1–R8] verificar: flutter analyze
