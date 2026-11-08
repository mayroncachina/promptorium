---
id: SPEC-048
status: aprovada
depende-de: SPEC-023
issue: 110
---

# Marcar commits feitos por agentes

## Objetivo

Os agentes do Promptorium commitam o tempo todo: em cada etapa de spec (o gate exige o commit `SPEC-NNN Rn: …`), ao resolver conflito, ao refazer a base de uma filha e no fim de um plano. Mas eles rodam no worktree com o `user.name` da pessoa. No histórico, todo commit parece feito por ela, e nada diz qual modelo, spec ou etapa gerou cada um. Nos últimos 400 commits do Promptorium, a única pista é o `Co-Authored-By` que o Claude Code põe em parte deles, e que a pessoa pediu para tirar.

Esta spec cria uma opção do projeto que acrescenta uma linha ao fim da mensagem dos commits feitos pelas sessões do app: `Promptorium-Agente: sonnet · SPEC-042 R2`. O autor continua sendo a pessoa, e o GitHub não mostra coautor. A Atividade (SPEC-046) e o Grafo (SPEC-045) passam a separar o trabalho dos agentes do trabalho da pessoa.

Issue: [#110](https://github.com/mayroncachina/promptorium/issues/110) (sub-issue de [#101](https://github.com/mayroncachina/promptorium/issues/101)).

Mockup: [canvas do Claude Design](https://claude.ai/artifact/HcFbQPFWcM9ZWttmCgcKDw), linha "SPEC-048 · Marcar commits de agentes". Capturas em `docs/mockups/spec-048/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-configuracao.png` | Opção ligada em Configuração do projeto, com o tooltip do ícone de informação aberto | R1, R2, R7 |
| `2-ligar-pela-atividade.png` | Confirmação ao ligar pela Atividade, com o que muda no repositório | R1, R6 |
| `3-grafo-etiqueta.png` | Etiqueta do modelo no Grafo, com o tooltip da origem e do trailer | R7 |

## Requisitos

- R1 · O projeto deve ter a opção `git: marcar-commits-de-agente` em `.promptorium/config.yml`, desligada por padrão. Em Configuração do projeto (no Projeto e em Configurações), ela aparece num grupo **Git**:
  - a caixa "Marcar commits feitos por agentes";
  - um ícone de informação (ⓘ) ao lado. Ao passar o ponteiro ou dar foco pelo teclado, um tooltip explica o que é, mostra um commit de exemplo com a linha e diz onde ela é usada (R7);
  - uma linha de estado: "Ligado · desde 8 nov", "Desligado" ou "Precisa do git 2.31 ou mais novo".
- R2 · Ligada a opção, toda sessão de agente que o app abrir no projeto (Claude, Codex e ACP) deve receber no ambiente:
  - `PROMPTORIUM_AGENTE`, com o modelo da sessão (`sonnet`, `opus`, `gpt-5`…), e `PROMPTORIUM_ORIGEM`, com o motivo: `SPEC-042 R2` numa etapa, `SPEC-043 conflito` numa resolução, `SPEC-042 base` ao refazer a base, `sessão <nome>` numa sessão livre, `Prompt` no fim de um plano;
  - `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_n`/`GIT_CONFIG_VALUE_n` com `core.hooksPath` apontando para a pasta de hooks do app (`~/.promptorium/git-hooks/`).
  
  Nada é escrito no repositório nem em `.git/hooks`. O terminal do Código, os terminais da pessoa e os commits do painel do Código não recebem essas variáveis e saem como hoje.
- R3 · A pasta de hooks do app deve ter:
  - `prepare-commit-msg`, que acrescenta `Promptorium-Agente: <modelo> · <origem>` com `git interpret-trailers --if-exists replace`. Assim, num amend ou rebase do agente, a linha é substituída e não duplica;
  - um repasse para cada um dos outros hooks do git, que chama o hook do repositório no caminho original (`core.hooksPath` do projeto ou `.git/hooks`), com os mesmos argumentos e o mesmo stdin. O `prepare-commit-msg` do repositório também é chamado antes da marcação. Husky, lefthook e hooks próprios continuam rodando como sem o app.
- R4 · O "Commitar o que sobrou" e os outros commits que o próprio app faz numa etapa devem sair com `Promptorium-Agente: app · SPEC-042 R2` (por `git commit --trailer`), porque podem juntar edição da pessoa com edição do agente.
- R5 · O `GitService` deve ler a marca: `commitOrigin(sha)` e, em lote, `%(trailers:key=Promptorium-Agente,valueonly)` no `git log`, que devolve **pessoa**, **agente** (modelo e origem) ou **app**. O "desde" é a data do primeiro commit marcado na branch padrão. Antes dele, os commits contam como **sem marca**, não como pessoa.
- R6 · A opção também deve poder ser ligada de onde ela é usada (o cartão "Quem fez os commits" da SPEC-046). O botão abre uma confirmação que diz:
  - a linha que vai entrar nos commits, com um exemplo;
  - que `.promptorium/config.yml` muda e entra no próximo commit, como qualquer configuração do projeto, e que quem clonar com o Promptorium herda a marcação;
  - que os commits antigos não mudam.
- R7 · Onde a marca aparece, a interface deve explicá-la com um ícone de informação e um tooltip, nunca com a linha crua:
  - no Grafo (SPEC-045), uma etiqueta com o modelo ao lado do autor. O tooltip mostra a origem e o texto exato do trailer;
  - na Atividade (SPEC-046), o ⓘ do cartão "Quem fez os commits" diz de onde vem a separação e desde quando ela vale.
- R8 · Desligar a opção deve parar de injetar as variáveis nas próximas sessões. As sessões vivas terminam como começaram, e o estado diz "Desliga nas próximas sessões". Os commits já marcados ficam como estão.

## Fora do escopo

- Marcar commits antigos ou reescrever histórico.
- Trocar o autor ou o committer do commit.
- Marcar commits de agentes rodados fora do app, como o Claude Code no terminal.
- Usar a marca para bloquear ou exigir alguma coisa no gate ou no Review.

## Design

### O que já existe

- `lib/core/claude/claude_process.dart`: `environment` ao iniciar o processo. O Codex e os provedores ACP têm o mesmo ponto em `lib/core/codex/` e `lib/core/providers/`.
- `lib/core/claude/managed_hooks.dart`: o padrão de arquivos gerados pelo app fora do repositório, numa pasta própria.
- `lib/features/board/spec_runner.dart`: a origem da etapa (`spec.code` e os ids) e o "Commitar o que sobrou" (`commitAll`).
- `lib/features/review/review_service.dart` e `restack.dart`: a origem da resolução de conflito e da base refeita.
- `lib/core/git/git_service.dart`: `commitAll` e `git(args)`.
- `lib/features/project/project_config.dart` e `widgets/project_config_view.dart`: a configuração do projeto e o formulário, que aparece no Projeto e em Configurações.

### Componentes

- `lib/core/git/agent_trailer.dart` (novo): monta o trailer, gera a pasta `~/.promptorium/git-hooks/` (`prepare-commit-msg` e os repasses), com a versão do conteúdo para regenerar quando o app atualizar, e devolve o mapa de ambiente para uma sessão (R2, R3).
- `ProjectConfig.git.markAgentCommits` (`git: marcar-commits-de-agente`).
- Os três pontos que abrem sessão recebem `agentCommitEnv(config, modelo, origem)` e o somam ao `environment`.
- `GitService.commitAll(message, {trailer})` (R4), `commitOrigin(sha)` e `commitOrigins(range)` (R5).
- `lib/ui/widgets/info_tip.dart` (novo): o ícone ⓘ com tooltip rico (título, texto, bloco de código), que abre com ponteiro e com foco. A Configuração, o Grafo e a Atividade usam o mesmo componente (R1, R7).
- `lib/features/project/widgets/agent_trailer_dialog.dart` (novo): a confirmação de R6.

### Testes

- `test/core/git/agent_trailer_test.dart`: trailer por origem, `--if-exists replace` num amend, repasse chamando o hook original com argumentos e stdin, husky com `core.hooksPath`, git antigo.
- `test/core/git/git_service_trailer_test.dart`: `commitAll` com trailer, `commitOrigins` com pessoa, agente, app e sem marca, e o "desde".
- `test/features/project/project_config_view_test.dart`: a caixa, o estado, o tooltip com foco pelo teclado e o diálogo de R6.
- Testes dos três provedores: ambiente com a opção ligada e desligada, e o terminal do Código sem as variáveis.

## Decisões

- **Variáveis de ambiente em vez de hook no repositório.** Com `GIT_CONFIG_COUNT`, o `core.hooksPath` só vale dentro das sessões do app. Nada é instalado em `.git/hooks`, não há conflito com husky e os commits da pessoa nunca passam pela marcação.
- **Desligado por padrão.** O Promptorium abre qualquer repositório, e escrever no histórico de um projeto alheio sem a pessoa pedir seria invasivo.
- **Trailer próprio, não `Co-Authored-By`.** Ele não credita ninguém no GitHub e não muda autoria. É só dado para o app ler.
- **"app" separado de agente.** O commit que o app faz pode misturar mãos, e contar isso como agente distorceria a Atividade.
- **A interface explica com ⓘ e tooltip.** A linha do trailer é detalhe técnico: quem quer saber passa o ponteiro, e quem não quer não vê.

Decisões tomadas na implementação:

- **Origem de uma sessão viva por arquivo.** O ambiente de um processo não muda depois que ele começa, mas a mesma sessão pode emendar a próxima etapa ou receber "Resolver conflito". Por isso a sessão também recebe `PROMPTORIUM_ORIGEM_ARQUIVO`, que aponta para `~/.promptorium/git-hooks/origens/<sessão>`. O app reescreve esse arquivo ao trocar as etapas (`setSteps`) e ao pedir a resolução de conflito (`setAgentOrigin`), e o `prepare-commit-msg` prefere o arquivo à variável. O arquivo some quando o processo termina.
- **git 2.32, não 2.31.** O `GIT_CONFIG_COUNT` é de 2.31, mas o `git commit --trailer` de R4 só existe a partir de 2.32. O estado diz "Precisa do git 2.32 ou mais novo", e abaixo disso nada é injetado.
- **Os hooks do repositório rodam sem o `core.hooksPath` do app.** A sessão recebe `PROMPTORIUM_GIT_CONFIG_BASE`, com quantas entradas `GIT_CONFIG_*` o app já herdou. O repasse lê o `core.hooksPath` do projeto (ou `git rev-parse --git-common-dir`/hooks) com essa contagem e roda o hook original com ela. Assim um husky que chama `git` dentro do hook vê a configuração de sempre. As entradas `GIT_CONFIG_*` herdadas são mantidas.
- **Modelo `inherit` vira o nome do provedor.** O modelo real só aparece depois que o processo começa. Uma sessão no padrão do CLI sai como `claude` ou `codex`.
- **Grafo e Atividade ficam para as SPEC-045 e SPEC-046.** As duas telas ainda não existem. Esta spec entrega o que elas vão usar: `InfoTip`, `GitService.commitOrigins` (com `CommitOrigin` e `CommitOriginLog`) e `showAgentTrailerDialog`. Em R7, só o ⓘ da Configuração fica pronto aqui.
- **"Desde" pela data do committer, na branch base.** `agentMarkSince` e `agentMarkCount` olham a `branch-base` do config (ou o HEAD da raiz). O estado segue o mockup ("Ligado desde 8 nov · 37 commits marcados"). Sem nenhum commit marcado ainda, ele diz "Ligado · nenhum commit marcado ainda". Com a caixa alterada e ainda não salva, diz "Liga nas próximas sessões, depois de salvar" ou "Desliga nas próximas sessões, depois de salvar".
- **Commits do app na Review também saem como `app`.** O commit das pendências em "Criar PR" e no merge junta o que estiver no worktree, como o "Commitar o que sobrou".
- **Conversas do Prompt marcadas em qualquer modo.** Só os modos que editam chegam a commitar, e a origem é sempre `Prompt`.
- **O ACP passa a repassar o ambiente.** O `starter` padrão do `AcpProvider` ignorava `environment`, e por isso nenhuma variável chegava às sessões ACP.

## Plano

1. Validar o mockup (tabela no início da spec).
2. `agent_trailer.dart` com a pasta de hooks e os testes de repasse.
3. Ambiente nos três provedores e o trailer do "Commitar o que sobrou".
4. Leitura no `GitService`.
5. `InfoTip`, grupo Git na configuração e diálogo de R6.
6. Guia `docs/guia/configuracoes.md`.

## Critérios de aceite

- [x] A opção fica em `git: marcar-commits-de-agente`, desligada por padrão, com caixa, ⓘ e estado na Configuração do projeto [R1] verificar: flutter test test/features/project/project_config_view_test.dart
- [x] O tooltip abre com ponteiro e com foco pelo teclado e mostra o commit de exemplo [R1, R7] verificar: flutter test test/features/project/project_config_view_test.dart
- [x] Sessões de agente recebem as variáveis só com a opção ligada; o terminal do Código nunca recebe [R2, R8] verificar: flutter test test/features/sessions/agent_commit_env_test.dart test/core/git/agent_trailer_test.dart
- [x] O commit do agente ganha a linha com modelo e origem, sem duplicar num amend [R3] verificar: flutter test test/core/git/agent_trailer_test.dart
- [x] Os hooks do repositório (inclusive husky) continuam rodando com os mesmos argumentos e stdin [R3] verificar: flutter test test/core/git/agent_trailer_test.dart
- [x] "Commitar o que sobrou" sai marcado como app [R4] verificar: flutter test test/core/git/git_service_trailer_test.dart
- [x] A leitura separa pessoa, agente, app e sem marca, com o "desde" [R5] verificar: flutter test test/core/git/git_service_trailer_test.dart
- [x] Ligar pela confirmação grava o config.yml e explica o que muda [R6] verificar: flutter test test/features/project/project_config_view_test.dart
- [ ] Uma etapa real do Promptorium gera um commit com `Promptorium-Agente: <modelo> · SPEC-NNN Rn`, e um commit no terminal sai sem a linha [R2–R4] verificar: manual (rodar uma etapa e commitar no terminal)
- [x] O projeto compila e a análise estática passa [R1–R8] verificar: flutter analyze
