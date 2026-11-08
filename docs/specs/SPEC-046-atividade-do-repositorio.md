---
id: SPEC-046
status: rascunho
depende-de: SPEC-044, SPEC-042, SPEC-048
issue: 104
---

# Atividade do repositório

## Objetivo

O Promptorium sabe o que cada spec faz agora, mas não mostra o ritmo do projeto: em que dias se trabalhou, quanto do trabalho foi funcionalidade e quanto foi correção, quanto tempo uma spec leva da primeira branch ao merge e quais arquivos mudam em quase toda spec. Essas respostas ajudam a planejar as sprints (SPEC-042) e a achar o código que mais atrai conflito.

Esta spec acrescenta a aba **Atividade** à tela Repositório (SPEC-044), com números tirados só do git e das specs do workspace.

Issue: [#104](https://github.com/mayroncachina/promptorium/issues/104) (sub-issue de [#101](https://github.com/mayroncachina/promptorium/issues/101)).

Mockup: [canvas do Claude Design](https://claude.ai/artifact/HcFbQPFWcM9ZWttmCgcKDw), linha "SPEC-046 · Atividade". Capturas em `docs/mockups/spec-046/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-atividade.png` | Resumo do período, mapa de commits por dia, commits por tipo e ciclo das specs | R1, R2, R3, R4, R6 |
| `2-arquivo.png` | Arquivos mais alterados, com as specs que mexeram em um deles | R5 |
| `3-quem-fez.png` | "Quem fez os commits": pessoa, agentes e app por semana e por modelo, com o tooltip do ⓘ aberto | R8 |
| `4-quem-fez-desligado.png` | O cartão quando o projeto não marca os commits, com "Ligar neste projeto" | R8 |

## Requisitos

- R1 · A tela Repositório deve ganhar a aba **Atividade**, depois de Grafo. No topo, a escolha do período (**30 dias**, **90 dias** (padrão), **1 ano**) vale para a aba inteira. Uma linha de resumo mostra, no período: commits, specs mergeadas, releases e o ciclo mediano das specs (R4), cada número comparado com o período anterior de mesmo tamanho ("+12%").
- R2 · O **mapa de commits por dia** deve mostrar uma célula por dia em colunas por semana, com cinco tons pela quantidade de commits da branch padrão e das branches de spec. O balão de cada célula diz a data, os commits e as specs que receberam commits naquele dia. Um clique leva ao Grafo filtrado por aquele dia. Os dias de release ganham uma marca.
- R3 · **Commits por tipo** deve mostrar barras empilhadas por semana, com os grupos de commit convencional do `cliff.toml` do projeto (ou os do Promptorium, como na SPEC-044 R3). Os commits fora do padrão ficam em "Outros". A legenda permite esconder um grupo.
- R4 · **Ciclo das specs** deve mostrar, para cada spec mergeada no período, o tempo do primeiro commit da branch `spec/NNN-*` até o merge na branch padrão:
  - a mediana e o percentil 90 do período;
  - as cinco specs mais longas, com o tempo e um clique que abre a spec no Quadro;
  - com sprints (SPEC-042), a mediana por sprint concluída, em ordem.
  
  As filhas de uma spec grande contam dentro da pai, e não como specs à parte.
- R5 · **Arquivos mais alterados** deve listar os 15 arquivos com mais commits no período (`git log --numstat`, sem os arquivos gerados que o projeto ignora para a análise, como `*.g.dart` e `pubspec.lock`), com o número de commits, as linhas somadas e quantas specs diferentes mexeram neles. Ao abrir um arquivo, aparece a lista das specs e dos commits que o alteraram, do mais novo ao mais antigo, com links para o Quadro e para o Grafo.
- R6 · Os números são calculados a partir do git e guardados por SHA da ponta da branch padrão. Ao abrir a aba de novo sem commits novos, nada é recalculado. Com commits novos, só eles são lidos. O cálculo roda fora da thread da interface e a aba mostra os cartões com um esqueleto enquanto isso.
- R7 · Os números sem fonte confiável não aparecem: sem branches `spec/*`, o ciclo das specs diz "Este repositório não usa branches de spec", e sem tags os dias de release não são marcados.
- R8 · **Quem fez os commits** deve separar os commits do período em **pessoa**, **agentes** e **app**, pela marca da SPEC-048 (`commitOrigins`):
  - barras empilhadas por semana com as três origens, e a divisão dos commits de agente por modelo (`sonnet`, `opus`…), com a porcentagem;
  - um ícone de informação (ⓘ, o `InfoTip` da SPEC-048) no título. O tooltip explica que a separação vem da linha `Promptorium-Agente` que o app põe nos commits das sessões, que "app" é o commit feito pelo próprio app numa etapa e desde quando o projeto marca;
  - as semanas antes do primeiro commit marcado ficam em cinza, como **sem marca**, e nunca contam como pessoa;
  - com a opção desligada, o cartão diz "Este projeto não marca os commits dos agentes", com o mesmo ⓘ e o botão **Ligar neste projeto**, que abre a confirmação da SPEC-048 (R6).

## Fora do escopo

- Marcar commits antigos para preencher "Quem fez os commits" antes da opção ligada (SPEC-048, fora do escopo de lá também).
- Métricas por pessoa ou rankings de autores.
- Custo em dólar ou tokens por spec. O orquestrador de modelos (SPEC-035) é quem cuida disso.
- Exportar os gráficos.

## Design

### O que já existe

- `lib/features/repository/repository_screen.dart` (SPEC-044) e o agrupamento por tipo em `releases/unreleased.dart`.
- `lib/features/repository/graph/` (SPEC-045): o Grafo, que recebe o filtro por dia, e `spec_of_commit.dart`, que liga commit e spec.
- `lib/data/repos/sprints_repo.dart` (SPEC-042): sprints e as specs de cada uma.
- `GitService.commitOrigins`, `InfoTip` e a confirmação de ligar a marcação (SPEC-048).
- `lib/core/git/git_service.dart`: `git(args)`.

### Componentes

- `lib/features/repository/activity/activity_log.dart` (novo): lê `git log --numstat --format=…` da branch padrão e das `spec/*` e guarda o resultado num arquivo de cache por workspace, com o SHA da ponta (R6).
- `lib/features/repository/activity/activity_stats.dart` (novo): funções puras para o resumo, o mapa por dia, os tipos por semana, o ciclo das specs (mediana, p90, por sprint), os arquivos mais alterados e as origens por semana e por modelo (R8).
- `lib/features/repository/activity/activity_tab.dart` (novo): os cartões. Os gráficos são `CustomPainter` simples, sem pacote novo.
- O filtro "por dia" do Grafo entra como parâmetro de rota da aba.

### Testes

- `test/features/repository/activity_stats_test.dart`: períodos e comparação, mapa por dia, grupos e "Outros", ciclo com filhas dentro da pai, p90, por sprint, arquivos ignorados, origens com semanas sem marca.
- `test/features/repository/activity_log_test.dart`: cache por SHA, leitura só do que é novo.
- `test/features/repository/activity_tab_test.dart`: período, esqueleto, mensagens sem fonte, o clique que leva ao Grafo e ao Quadro, e o cartão Quem fez ligado e desligado, com o tooltip.

## Decisões

- **Só o git e as specs como fonte.** Os números ficam iguais em qualquer máquina com o mesmo repositório, sem depender do histórico local do app.
- **Ciclo da spec começa no primeiro commit da branch.** A data de criação do arquivo da spec mede o tempo de planejamento, que é outra pergunta.
- **Sem marca não é pessoa.** Antes da SPEC-048 ligada, todo commit tem o nome da pessoa. Contar esses como dela inflaria o número e esconderia o trabalho dos agentes.
- **Sem pacote de gráficos.** Os cinco gráficos são simples, e um pacote novo traria temas e dependências que o app não precisa.

## Plano

1. Validar o mockup (tabela no início da spec).
2. `activity_log` com cache e `activity_stats` com os testes.
3. Aba com resumo, mapa e commits por tipo.
4. Ciclo das specs com sprints e arquivos mais alterados.
5. Quem fez os commits, depois da SPEC-048.
6. Ligações com Grafo e Quadro; guia `docs/guia/repositorio.md`.

## Critérios de aceite

- [ ] O resumo compara com o período anterior nos três períodos [R1] verificar: flutter test test/features/repository/activity_stats_test.dart
- [ ] O mapa conta commits por dia, marca releases e leva ao Grafo do dia [R2] verificar: flutter test test/features/repository/activity_tab_test.dart
- [ ] Os tipos seguem os grupos do cliff.toml, com "Outros" [R3] verificar: flutter test test/features/repository/activity_stats_test.dart
- [ ] O ciclo das specs dá mediana, p90, as cinco mais longas e a mediana por sprint, com as filhas dentro da pai [R4] verificar: flutter test test/features/repository/activity_stats_test.dart
- [ ] Os arquivos mais alterados ignoram gerados e listam as specs de cada um [R5] verificar: flutter test test/features/repository/activity_stats_test.dart
- [ ] Sem commits novos nada é recalculado; com commits novos só eles são lidos [R6] verificar: flutter test test/features/repository/activity_log_test.dart
- [ ] Sem branches de spec ou sem tags a aba explica em vez de mostrar zero [R7] verificar: flutter test test/features/repository/activity_tab_test.dart
- [ ] Quem fez separa pessoa, agentes e app, por modelo, com as semanas sem marca em cinza e o tooltip explicando a origem [R8] verificar: flutter test test/features/repository/activity_stats_test.dart
- [ ] Desligado, o cartão explica e "Ligar neste projeto" abre a confirmação [R8] verificar: flutter test test/features/repository/activity_tab_test.dart
- [ ] A aba abre em menos de 2 s no Promptorium depois do primeiro cálculo [R6] verificar: manual (abrir Atividade duas vezes no próprio repositório)
- [ ] O projeto compila e a análise estática passa [R1–R8] verificar: flutter analyze
