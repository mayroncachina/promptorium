---
id: SPEC-038
status: rascunho
depende-de: SPEC-034
---

# Tela Sobre com a abertura do app, só a última novidade e atualização clara

## Objetivo

A tela Sobre hoje é uma lista: título, versão, link do repositório, dois botões e o `CHANGELOG.md` inteiro, com todas as versões, documentação, testes e hashes de commit. Ela tem três problemas:

- não tem a cara do app, embora a abertura já tenha uma identidade forte;
- o changelog completo esconde o que importa, que é o que mudou na última versão;
- atualizar passa por até três janelas empilhadas (Sobre, confirmação e download), e quem não tem atualização vê um botão solto.

Há também um defeito: quando a consulta ao GitHub falha, a tela diz "Você já está na versão mais recente", mesmo sem internet.

Esta spec refaz a tela em duas colunas. À esquerda fica a identidade, com a animação da abertura. À direita fica um cartão que mostra o estado da atualização e, abaixo, só as novidades da última versão.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/2cXphCGn4oWcYT19ukqWMV).

## Requisitos

- R1 · A tela Sobre deve ter duas colunas numa única janela de 820×560:
  - a coluna da esquerda, de 300 px, traz a identidade (R2 a R4);
  - a coluna da direita traz o cartão de atualização (R7) e as novidades (R5);
  - o botão Fechar fica no canto superior direito;
  - abre pelos caminhos de hoje: F1, paleta de comandos e Configurações.
- R2 · Ao abrir, a coluna da esquerda deve tocar a animação padrão da abertura:
  - é a mesma do splash, com contorno do frasco, líquido, moléculas e título, nos mesmos tempos;
  - depois da introdução, a marca fica parada no estado final, só com o brilho fixo;
  - toca do início a cada abertura;
  - o ticker para ao fim da introdução, ou antes, se a janela fechar;
  - ela nunca segura a tela: cartão, novidades e botões funcionam desde o primeiro quadro.
- R3 · Com animações desligadas no sistema, a marca aparece direto no estado final, parada e sem as bolhas. Isso vale também para o splash.
- R4 · A identidade deve mostrar:
  - o nome Promptorium e a frase "o laboratório de onde operam seus agentes";
  - a versão instalada e a plataforma, como no splash: `v0.9.0 · Linux`;
  - os links Repositório e Histórico completo.
- R5 · A tela deve mostrar só as novidades da última versão:
  - sem atualização disponível, mostra a seção do `CHANGELOG.md` da versão instalada;
  - sem essa seção, mostra a primeira seção de versão do arquivo;
  - com atualização disponível, mostra as notas da versão nova;
  - o título diz "Novidades da 0.8.0", com a data ao lado quando houver;
  - a área rola sozinha, e o cartão de atualização fica sempre visível.
- R6 · As novidades devem trazer só o que interessa a quem usa o app:
  - entram os grupos Funcionalidades e Correções;
  - ficam de fora Documentação, Testes, Manutenção e Build e CI;
  - os hashes de commit no fim das linhas são removidos;
  - o escopo do commit no começo das linhas, como `**specs:**`, também é removido;
  - sem nenhum desses grupos, a tela diz "Sem novidades para mostrar nesta versão." e mantém o link Histórico completo;
  - com o changelog indisponível, a tela diz "Novidades indisponíveis.".
- R7 · O cartão de atualização deve mostrar um estado por vez, com ícone e texto, sem depender só da cor:
  - **Em dia**: "Você está na versão mais recente", com a hora da última verificação e "Verificar agora";
  - **Verificando**: indicador e "Verificando…";
  - **Disponível**: "Versão 0.9.0 disponível", com data e tamanho do pacote, "Atualizar agora" como ação principal e a dica "Baixa, instala e reinicia o app";
  - **Baixando**: barra, porcentagem, tamanho baixado e "Cancelar";
  - **Instalando**: "Instalando e reiniciando…", com a dica "O sistema pode pedir sua senha";
  - **Falhou**: o motivo, "Tentar de novo" e "Abrir página da release";
  - **Sem resposta**: "Não foi possível verificar atualizações", com "Tentar de novo";
  - o cartão tem a mesma altura em todos os estados, então as novidades não mudam de lugar;
  - com duas ações, os botões ficam numa linha abaixo do texto.
- R8 · Atualizar deve acontecer dentro do cartão, sem abrir outra janela:
  - "Atualizar agora" já é a confirmação e começa o download;
  - nada é baixado antes desse clique;
  - com sessão em execução, o cartão pergunta antes: "2 sessões em execução serão encerradas", com "Atualizar mesmo assim" e "Agora não";
  - "Cancelar" interrompe o download e volta para **Disponível**.
- R9 · Fechar a tela durante a atualização deve seguir estas regras:
  - em **Baixando**, Fechar e `Esc` pedem o cancelamento antes de fechar, com "Continuar baixando" como ação principal;
  - em **Instalando**, não é possível fechar, e o botão Fechar fica desabilitado com o motivo;
  - em todos os outros estados, a tela fecha direto.
- R10 · Uma consulta que falha não pode parecer "versão mais recente":
  - falha de rede, tempo esgotado ou resposta inválida vão para **Sem resposta**;
  - uma atualização já encontrada continua disponível depois de uma consulta que falhou;
  - o cartão de Atualizações em Configurações segue a mesma regra.
- R11 · A tela deve funcionar por teclado e leitor de tela:
  - o foco começa na ação principal do cartão;
  - F1 e `Esc` fecham, respeitando o R9;
  - a mudança de estado do cartão é anunciada sem mover o foco;
  - a animação fica fora da árvore de acessibilidade, e a marca tem o rótulo "Ícone do Promptorium".
- R12 · Em 1100×700, a janela cabe inteira, sem estouro de layout e sem rótulo truncado.

## Fora do escopo

- Mudar quando o app procura atualização ou o aviso que aparece fora do Sobre.
- Atualização no Windows: o fluxo continua como está em cada plataforma.
- Retomar um download interrompido.
- Mostrar notas de versões intermediárias quando há mais de uma versão de diferença.
- Mudar o formato gerado pelo git-cliff.

## Design

### O que já existe

- `lib/ui/shell/about_dialog.dart`: `AboutPromptoriumDialog`, `changelogProvider`, `_confirmUpdate`, `_DownloadDialog` e `_CheckNowButton`.
- `lib/features/splash/splash_screen.dart`: `_Stage`, com o ticker e o título.
- `lib/features/splash/splash_painter.dart`: `SplashTimeline`, que já trata `reducedMotion`, e `SplashPainter`.
- `lib/core/update/update_check.dart`: `UpdateChecker.check`, `fetchLatestRelease`, `AvailableUpdate` e `ReleaseAsset.size`.
- `lib/core/update/installer.dart`: `UpdateInstaller.download`, `installAndRestart` e `openReleasePage`.
- `lib/features/settings/providers_view.dart`: `UpdatesCard`.
- `lib/features/sessions/session_manager.dart`: `sessionManagerProvider`, para contar sessões em execução.
- `test/ui/about_dialog_test.dart` e `test/core/acp_and_update_test.dart`.

### R2, R3 · Animação

`_Stage` vira o widget público `SplashStage`, em `lib/features/splash/splash_stage.dart`, dono do próprio ticker, com a opção `loop`. O splash usa `loop: true`, como hoje. O Sobre usa `loop: false`, num tamanho menor, e para o ticker em `SplashTimeline.introDuration`. `SplashTimeline` passa a devolver as bolhas invisíveis com `reducedMotion`, em vez de paradas e visíveis, e ganha o mesmo estado final para `loop: false`.

### R5, R6 · Novidades

Uma função pura, `latestChanges(String markdown, {String? version})`, em `lib/core/update/changelog_section.dart`, devolve versão, data e grupos. As notas da release passam pelo mesmo filtro.

### R7–R9 · Cartão

Um `UpdateFlow`, `Notifier` com um estado selado, substitui `_CheckNowButton`, `_confirmUpdate` e `_DownloadDialog`. Fica fora do widget porque R9 e R11 dependem do estado. O download assina o stream de `UpdateInstaller.download`, e cancelar encerra a assinatura e apaga o arquivo parcial.

### R10 · Falha na consulta

`ReleaseFetcher` passa a distinguir falha de "sem release". `UpdateChecker.check` não limpa `state` numa falha e registra o resultado em `lastCheck`, que o cartão e o `UpdatesCard` leem.

Riscos:

- o stream de `download` pode não apagar o arquivo parcial ao ser cancelado;
- as notas da release podem não seguir o formato do `CHANGELOG.md`, e nesse caso o filtro mostra o texto inteiro sem os grupos (D3);
- `Process.run('xdg-open', …)` dos links não funciona no Windows, então eles passam a usar o mesmo caminho de `openReleasePage`.

## Critérios de aceite

- [ ] A tela abre com duas colunas e mantém as chaves `about-dialog`, `about-version` e `about-repo` [R1] [R4] verificar: flutter test test/ui/about_dialog_test.dart
- [ ] O splash e o Sobre usam o mesmo `SplashStage`, os botões respondem durante a introdução e o ticker do Sobre para ao fim dela [R2] verificar: flutter test test/ui/about_dialog_test.dart
- [ ] Com animações desligadas, a marca aparece no estado final, sem bolhas, e nenhum ticker roda [R3] verificar: flutter test test/ui/about_dialog_test.dart
- [ ] `latestChanges` escolhe a versão instalada e, sem ela, a primeira seção [R5] verificar: flutter test test/core/changelog_section_test.dart
- [ ] Só Funcionalidades e Correções aparecem, sem os hashes e sem o escopo do commit [R6] verificar: flutter test test/core/changelog_section_test.dart
- [ ] Com atualização disponível, a tela mostra as notas da versão nova [R5] verificar: flutter test test/ui/about_dialog_test.dart
- [ ] Cada estado do cartão mostra seu texto e suas ações [R7] verificar: flutter test test/ui/about_dialog_test.dart
- [ ] O cartão tem a mesma altura em todos os estados, e com duas ações os botões ficam abaixo do texto [R7] verificar: flutter test test/ui/about_dialog_test.dart
- [ ] "Atualizar agora" baixa sem abrir outra janela, e nada é baixado antes do clique [R8] verificar: flutter test test/ui/about_dialog_test.dart
- [ ] Com sessão em execução, o cartão pergunta antes de baixar [R8] verificar: flutter test test/ui/about_dialog_test.dart
- [ ] Cancelar volta para Disponível, e fechar durante o download pede o cancelamento [R8] [R9] verificar: flutter test test/ui/about_dialog_test.dart
- [ ] Durante a instalação, a tela não fecha [R9] verificar: flutter test test/ui/about_dialog_test.dart
- [ ] Uma consulta que falha mostra Sem resposta, mantém a atualização já encontrada e vale também em Configurações [R10] verificar: flutter test test/core/acp_and_update_test.dart
- [ ] Teclado e leitor de tela seguem o R11 [R11] verificar: flutter test test/ui/about_dialog_test.dart
- [ ] Em 1100×700 não há estouro de layout [R12] verificar: flutter test test/ui/about_dialog_test.dart

## Decisões

- D1 · A tela continua sendo uma janela sobre o app, e não uma seção da navegação: ela é consultada de vez em quando, e F1 já a abre e fecha.
- D2 · "Atualizar agora" não abre mais confirmação, porque o texto da dica já diz o que acontece. Só a sessão em execução pede confirmação, pois ali a pessoa perde trabalho.
- D3 · Se as notas da release não tiverem os grupos esperados, a tela mostra o texto inteiro, sem filtro. É melhor mostrar demais do que esconder a novidade.
- D4 · A animação para depois da introdução, ao contrário do splash. O Sobre é uma tela de leitura, e movimento contínuo ao lado do texto distrai. Quem quiser ver de novo reabre a tela.
- D5 · Documentação, Testes e Manutenção ficam fora, mesmo com o pedido de mostrar o último changelog, porque não dizem nada a quem usa o app. O texto completo continua em Histórico completo.

- D6 · O aviso de sessões aparece só ao clicar em "Atualizar agora", e não em repouso. Ele importa na hora de atualizar, não de quem só abriu o Sobre.

## Perguntas em aberto

Nenhuma.
