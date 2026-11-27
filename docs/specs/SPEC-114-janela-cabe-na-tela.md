---
id: SPEC-114
status: rascunho
versao: 0.28.1
tipo: correcao
depende-de: []
---

# Janela que cabe na tela (Windows)

## Objetivo

Abrir a janela do app inteira, centralizada e dentro da área útil da tela, em qualquer resolução e escala. E deixar maximizar sempre.

Hoje, no Windows, a janela abre maior que a tela e o botão Maximizar não funciona. A causa está em `lib/main.dart`: as `WindowOptions` têm tamanho fixo de 1440×900 e mínimo de 1100×700, em pixels lógicos. A conta não olha para a tela. Os tamanhos lógicos ficam pequenos justamente nas telas mais comuns no Windows:

| Tela | Escala | Área útil lógica (sem a barra de tarefas) |
|---|---|---|
| 1366×768 | 100% | ~1366×728 |
| 1920×1080 | 150% | ~1280×688 |
| 1536×864 (notebook 1920×1080 a 125%) | — | ~1536×824 |

Nos dois primeiros casos, o mínimo de 700 de altura é maior que a área útil. O Windows não deixa a janela ficar menor que o mínimo (`WM_GETMINMAXINFO`), então ela não cabe nem maximizada. A barra de título e a borda de baixo ficam fora da tela. No Linux, o GTK e o gerenciador de janelas limitam o tamanho, por isso o problema não aparecia ali.

## Requisitos

- R1 · **Medir a tela antes de abrir.** Antes do `waitUntilReadyToShow`, o app lê a área útil do monitor principal (`screenRetriever.getPrimaryDisplay()`, com `visibleSize` e `visiblePosition`, já em pixels lógicos). O pacote `screen_retriever` já vem com o `window_manager` e passa a ser dependência direta.
- R2 · **Tamanho inicial.** A janela abre com o menor valor entre o tamanho ideal (1440×900) e 90% da área útil, em cada eixo. Numa tela de 1920×1080 a 100%, nada muda: continua com 1440×900.
- R3 · **Tamanho mínimo.** O mínimo é o menor valor entre 1100×700 e a área útil. Assim, o mínimo nunca impede de maximizar nem de caber na tela. As telas que assumem 1100 px (o Quadro, a comparação) continuam funcionando a partir de 1100. Abaixo disso, o layout aperta, mas a janela fica utilizável.
- R4 · **Centralizada na área útil.** A janela fica centralizada na área útil, descontando a barra de tarefas (`visiblePosition` + metade da sobra). O `center: true` sozinho não basta, porque centraliza na tela inteira.
- R5 · **Maximizar funciona.** Com o mínimo de R3, Maximizar ocupa a área útil e Restaurar volta ao tamanho de R2.
- R6 · **Sem tela, sem erro.** Se a leitura falhar (sem monitor informado, `visibleSize` nulo, exceção no canal), o app usa os valores de hoje com `center: true`, sem travar a abertura.
- R7 · **Mesma regra em todas as plataformas.** A conta é a mesma no Windows e no Linux. No Linux, o `gtk_window_set_default_size(1440, 900)` de `my_application.cc` continua sendo só o tamanho antes do Flutter aplicar as opções.

## Decisões

- P1 · **Lembrar o tamanho e a posição da última sessão?** **Recomendado:** não nesta correção. Se fizer falta, vira uma spec própria, que também precisa tratar monitor desconectado.
- P2 · **Abrir maximizado quando a tela for pequena?** **Recomendado:** não. Com 90% da área útil, a janela já fica quase cheia e não esconde a área de trabalho. Maximizar fica a cargo da pessoa.
- P3 · **Monitor principal ou o monitor do cursor?** **Recomendado:** o principal (`getPrimaryDisplay`). É onde o Windows abre apps novos por padrão, e a conta fica simples.
- P4 · **Mock.** Não precisa de canvas, porque o layout das telas não muda. O PR leva prints do app no Windows antes e depois, em 1366×768 a 100% e em 1920×1080 a 150%.

## Fora do escopo

- Layout responsivo das telas abaixo de 1100 px de largura.
- macOS, que o projeto ainda não compila.
- O runner do Windows (`windows/runner/main.cpp`), que o CI gera com `flutter create` e não está versionado. A janela inicial de 1280×720 só aparece até o Flutter aplicar as opções, porque o `waitUntilReadyToShow` a mantém escondida.

## Tarefas

- T1 · Função pura `initialWindowBounds(Size? visible, Offset? origin)` em `lib/core/system/window_bounds.dart`, que devolve o tamanho, o mínimo e a posição (R2–R4, R6).
- T2 · `lib/main.dart`: ler o monitor principal e montar as `WindowOptions` com T1. Aplicar a posição com `setPosition` dentro do `waitUntilReadyToShow`, antes do `show` (R1, R5). Pôr `screen_retriever` no `pubspec.yaml`.
- T3 · Testes de T1: 1920×1080 a 100% (sem mudança), 1366×768, 1280×688 (1080p a 150%), barra de tarefas à esquerda ou em cima (`origin` ≠ 0), `visible` nulo.
- T4 · Conferir no Windows com o `.zip` do CI: abrir, maximizar e restaurar nas duas escalas de P4 e tirar os prints para `docs/mockups/spec-114/app/`.

## Critérios de aceite

- [ ] Em 1366×768 a 100%, a janela abre inteira na tela, com a barra de título visível, e centralizada acima da barra de tarefas.
- [ ] Em 1920×1080 a 150%, idem.
- [ ] Nas duas, Maximizar ocupa a área útil e Restaurar volta ao tamanho inicial.
- [ ] Em 1920×1080 a 100%, a janela continua abrindo com 1440×900, centralizada.
- [ ] Se a leitura da tela falhar, o app abre como hoje, sem erro.
- [ ] Linux sem regressão.
