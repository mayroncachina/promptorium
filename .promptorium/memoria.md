# Memória do projeto

<!-- Escrita pelo Promptorium e por você. Uma linha por fato; vai no prompt das sessões de etapa. Máximo de 60 linhas. -->

- as colunas já rolam sozinhas (`ListView` dentro de `Expanded`) e o Grafo já tem rolagem vertical aninhada; o defeito real da R1 era a altura mínima do Quadro, então confirme no app quais visões ainda falham antes de mexer em R2 e R4.  <!-- SPEC-001 R1, 2026-10-19 -->
- `tester.runAsync` com inserts no drift trava o teste; faça `await db.into(...)` direto, como o `pumpBoard`. Larguras abaixo de ~1440 estouram a barra de ferramentas do Quadro nos testes. Não use `pkill -f "flutter test"` pela Bash, porque o padrão casa com o próprio shell.  <!-- SPEC-001 R2, 2026-10-19 -->
- uma coluna que ainda tem rolagem própria consome a roda antes de o gesto chegar ao Quadro; nos testes de rolagem por roda, envie vários eventos ou use um cartão de coluna sem overflow.  <!-- SPEC-001 R3, 2026-10-19 -->
- para testar a rolagem de uma coluna, pegue o primeiro `Scrollable` dentro de `board-column-<stage>` e passe a roda do mouse sobre um `SpecCard` dessa coluna; assim a rolagem de cada coluna é medida separadamente.  <!-- SPEC-001 R4, 2026-10-19 -->
- `flutter test` na suíte inteira passa de 2 minutos, então rode em background; `project_memory_test` falha de vez em quando na suíte completa e passa quando rodado sozinho.  <!-- SPEC-001 R6, 2026-10-19 -->
