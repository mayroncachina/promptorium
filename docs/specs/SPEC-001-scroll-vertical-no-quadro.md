---
id: SPEC-001
status: concluida
design: dispensado
---

# Scroll vertical no Quadro

## Objetivo

Permitir rolar o Quadro na vertical para que o usuário alcance todas as specs, mesmo quando há muitas ondas de dependência. Hoje, com várias ondas, o conteúdo passa da área visível e não rola, então as specs que ficam fora da tela não podem ser vistas.

## Requisitos

- R1 · Quando o conteúdo do Quadro for mais alto que a área visível, o sistema deve permitir rolar na vertical até a última spec.
- R2 · Quando o Quadro estiver na visão Grafo (ondas) e o grafo for mais alto que a área visível, o sistema deve rolar o grafo na vertical sem perder a rolagem horizontal existente.
- R3 · Quando o usuário rolar com a roda do mouse ou o touchpad sobre um cartão de spec, o sistema deve rolar o Quadro em vez de ignorar o gesto.
- R4 · Quando uma coluna do Quadro tiver mais cartões do que cabem na altura, o sistema deve rolar essa coluna na vertical sem rolar as outras colunas.
- R5 · Enquanto o conteúdo couber na área visível, o sistema não deve exibir barra de rolagem nem alterar o layout atual.
- R6 · Quando o usuário arrastar um cartão para reordenar ou mudar de coluna, o sistema deve continuar aceitando o arraste, sem que a rolagem o interrompa.
- R7 · Quando houver rolagem vertical possível, o sistema deve exibir uma barra de rolagem visível.

## Design

<!-- Como implementar: componentes, arquivos e decisões. Use "Gerar design". -->

## Critérios de aceite

- [ ] [R1] Com a altura da área visível menor que o mínimo das colunas, o Quadro rola até o fim e a última spec fica visível. verificar: flutter test test/features/board/board_screen_test.dart
- [ ] [R2] Na visão Grafo com mais de 8 specs em uma onda, rolar para baixo revela a última linha, e a rolagem horizontal continua funcionando. verificar: flutter test test/features/board/board_screen_test.dart
- [ ] [R3] Rolar com a roda do mouse sobre um cartão move o conteúdo do Quadro, quando a coluna sob o cursor já estiver no fim ou não rolar. verificar: flutter test test/features/board/board_screen_test.dart
- [ ] [R4] Em uma coluna com muitos cartões, rolar move só essa coluna; as demais ficam na mesma posição. verificar: flutter test test/features/board/board_screen_test.dart
- [ ] [R5] Com poucas specs, nenhuma barra de rolagem aparece e o layout é idêntico ao atual. verificar: flutter test test/features/board/board_screen_test.dart
- [ ] [R6] Reordenar um cartão com os botões ou por arraste continua funcionando após a mudança. verificar: flutter test test/features/board/board_ops_test.dart
- [ ] [R7] Com rolagem possível, a barra de rolagem vertical aparece (conferir manualmente no app). verificar: flutter test test/features/board/board_screen_test.dart
- [ ] [R1] [R2] [R3] [R4] [R5] [R6] [R7] `flutter analyze` sem novos avisos. verificar: flutter analyze

## Perguntas em aberto

- O texto original diz "scroll lateral", mas o título diz "vertical". A necessidade é rolagem vertical (ver mais specs), horizontal, ou as duas?
- Em qual visão o problema acontece: nas colunas (Backlog com grupos "Prontas · onda N") ou no Grafo? Pelo código, o Grafo e as colunas já têm alguma rolagem, então falta reproduzir o defeito.
- A rolagem deve ser do Quadro inteiro (todas as colunas juntas) ou por coluna, como é hoje?
- Existe um número de specs ou ondas a partir do qual o problema aparece, para usar como caso de teste?
- Quer barra de rolagem sempre visível ou só ao rolar?
