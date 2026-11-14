---
id: SPEC-070
status: aprovada
tipo: bug
depende-de: SPEC-066
issue: 221
---

# Atualizar fecha e reabre o app, e a logo do Sobre só borbulha

## Objetivo

Dois defeitos no Sobre (F1).

**1. A atualização não reabre o app.** "Atualizar agora" baixa a versão nova, instala e deveria fechar o app e abri-lo de novo na versão nova. Na prática, a instalação acontece, mas o app fica aberto em "Instalando e reiniciando…" e nenhuma cópia nova sobe. A pessoa precisa fechar e abrir à mão, sem saber se a atualização deu certo.

Evidência da atualização para a 0.16.0, em 13/11, numa cópia do `.tar.gz` em `~/.local/share/promptorium/app`:

| Hora | O que aconteceu |
|---|---|
| 19:30:00–19:30:03 | As sessões em execução são encerradas (cartão "N sessões em execução serão encerradas") |
| 19:30:31 | O download começa em `/tmp/promptorium-update-*` |
| 19:30:54 | O `tar` grava os arquivos novos em `~/.local/share/promptorium/app` (a instalação funcionou) |
| 19:31:37 | O processo antigo termina pelo caminho normal da janela (`FlutterEngineRemoveView`), ou seja, foi fechado à mão, 43 s depois |
| — | Nenhuma instância nova aparece no `journalctl --user` até a pessoa abrir o app no dia seguinte |

O código hoje (`UpdateInstaller.installAndRestart`) faz `install` → `closeDatabase()` → `restart()`, e `restart()` faz `Process.start(executável, detached)` seguido de `exit(0)`. Depois da instalação, um desses passos não terminou. As suspeitas, em ordem:

- `AppDatabase.close()` não volta: o banco roda num isolate do `drift_flutter`, com dezenas de consultas observadas ainda vivas (Quadro, sessões, Review), e o fechamento espera por elas;
- o fechamento corre por fora do `_CloseHandler`: sessões, PTYs, servidores de desenvolvimento (SPEC-051), Chromium do preview e o servidor MCP (SPEC-052) continuam vivos e seguram o processo ou a cópia nova;
- a cópia nova sobe enquanto a antiga ainda tem o banco aberto, e morre sem log.

**2. A logo do Sobre não deve tocar a abertura de novo.** Pela SPEC-066 R5 e R6, clicar na logo (ou Enter/Espaço com foco) toca a abertura outra vez, e a logo tem a dica "Tocar a abertura de novo". A abertura é para tocar uma vez, quando o Sobre abre. Depois, a logo só fica borbulhando no ritmo calmo.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/EJJySojbvLABbm9JbKRyZL) (no canvas a logo borbulha no ritmo calmo). Capturas em `docs/mockups/spec-070/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-antes.png` | Hoje: o cartão parado em "Instalando e reiniciando…" e a logo com a dica "Tocar a abertura de novo" | — |
| `2-reiniciando.png` | Depois de instalar: "Reiniciando na 0.17.0…", os passos do fechamento e as linhas do log | R1, R2, R3, R5 |
| `3-nao-reabriu.png` | O lançador não iniciou: "A 0.17.0 foi instalada · Feche e abra o app para usar" e **Reiniciar agora** | R4, R5 |
| `4-atualizado.png` | A cópia nova aberta, com o aviso "Atualizado para a 0.17.0" e "Ver novidades" | R6 |
| `5-logo.png` | A logo do Sobre depois da abertura: só bolhas, sem dica nem anel de foco, e o que muda em relação à SPEC-066 | R7 |

Issue: [#221](https://github.com/mayroncachina/promptorium/issues/221) · PR: [#222](https://github.com/mayroncachina/promptorium/pull/222)

## Requisitos

- R1 · Depois de instalar a atualização, o app **fecha e reabre sozinho** na versão nova, nas duas formas de instalação (`.tar.gz` sobre a própria pasta e `.deb` em `/opt/promptorium`).
- R2 · O fechamento da atualização usa o **mesmo encerramento do botão Fechar** da janela (`_CloseHandler.close`): para sessões, conversas, PTYs, servidores de desenvolvimento, Chromium do preview e o servidor MCP, e fecha o banco, com os mesmos limites de tempo de hoje.
  - O fechamento do banco tem limite próprio de 3 s. Se ele estourar, o app segue para a saída mesmo assim: o SQLite em WAL aguenta o processo terminar.
  - Depois do encerramento, o processo sai com `exit(0)`. Se ainda estiver vivo 10 s depois do pedido, sai à força.
- R3 · A cópia nova só sobe **depois que a antiga terminou**. Antes de sair, o app inicia um lançador destacado (`setsid sh -c …`) que espera o PID antigo sumir (no máximo 30 s) e então abre o executável instalado.
  - O executável é o da cópia que foi atualizada: `Platform.resolvedExecutable` para o `.tar.gz`, `/opt/promptorium/promptorium` para o `.deb`.
  - O lançador herda o ambiente, sem as variáveis `PROMPTORIUM_*` de execução, e sai no `journalctl` como `promptorium-update`.
- R4 · Se não der para iniciar o lançador, o app **não fecha**. O cartão mostra "A <versão> foi instalada · Feche e abra o app para usar" com o botão **Reiniciar agora**, que tenta de novo.
- R5 · Cada passo da atualização deixa uma linha no log, na ordem em que acontecem (`atualização: instalado`, `atualização: lançador iniciado`, `atualização: encerrando`, `atualização: banco fechado em N ms`, `atualização: saindo`), e a falha do lançador também (`atualização: o lançador não iniciou: <erro>`), para o próximo defeito ser diagnosticado pelo `journalctl`.
- R6 · Ao abrir, a cópia nova mostra uma vez o aviso "Atualizado para a <versão>", com "Ver novidades", que abre o Sobre. O aviso sai de uma marca gravada antes de fechar (`update.justInstalled` em `app_settings`) e é apagado depois de mostrado.
- R7 · A logo do Sobre toca a abertura **uma vez**, quando o Sobre abre, e depois fica no ritmo calmo (SPEC-066 R2) enquanto o Sobre estiver aberto. Isto substitui a SPEC-066 R5 e R6:
  - clicar na logo, ou apertar Enter ou Espaço, não faz nada;
  - a logo sai da ordem do Tab, não tem anel de foco nem cursor de mão;
  - a dica "Tocar a abertura de novo" some, e o leitor de tela ouve só "Ícone do Promptorium", como imagem;
  - o mouse sobre a logo continua agitando o frasco (SPEC-066 R4), e as bolhas do download (SPEC-066 R10) continuam.

## Fora do escopo

- Atualização no Windows: o pacote `.zip` não tem atualização pelo app.
- Mudar o download, a verificação do `.sha256` ou a escolha entre `.deb` e `.tar.gz`.
- Instalação silenciosa sem a senha do `pkexec`.

## Design

### O que já existe

- `lib/core/update/installer.dart`: `UpdateInstaller.installAndRestart(file, closeDatabase:)`, `install`, `restart` (`Process.start` destacado + `exit(0)`) e `prefersDeb`.
- `lib/ui/shell/update_flow.dart`: `UpdateFlow._install` chama `installAndRestart` com `db.close`. Os estados `UpdateInstalling` e `UpdateFailed`.
- `lib/ui/shell/about_update_card.dart`: os textos de cada estado do cartão.
- `lib/main.dart`: `_CloseHandler.close()`, o encerramento da janela e da bandeja.
- `lib/ui/shell/about_dialog.dart`: `_AboutLogoState`, com `_replay`, o `FocusableActionDetector`, o `Tooltip` e o `Semantics` da logo.
- `test/core/installer_test.dart` e `test/ui/about_dialog_test.dart`.

### Componentes

- `AppShutdown` (novo, em `lib/core/app_shutdown.dart`): a lógica de `_CloseHandler.close` sai do `main.dart` para um serviço com provider, usado pela janela, pela bandeja e pela atualização. Ganha o fechamento do banco com limite (R2).
- `UpdateInstaller`:
  - `installAndRestart(file, shutdown:)` passa a receber o encerramento completo, não só `closeDatabase`;
  - `relaunchCommand(pid, executable)` monta o comando do lançador (R3), testável sem processo;
  - `restart()` inicia o lançador, grava `update.justInstalled`, chama o encerramento e sai (R2, R3, R6). Se o lançador não iniciar, lança `RelaunchFailed` sem fechar nada (R4).
- `UpdateFlow`: o estado novo `UpdateInstalledNotRestarted(update)` e a ação `restartNow()` (R4).
- `AboutLogo`: sai o `_replay`, o `FocusableActionDetector`, o `Tooltip` e o `Semantics` de botão. Fica o `MouseRegion` só para a agitação (R7).

## Decisões

- P1 · Lançador em `sh` em vez de reabrir direto: a cópia nova nunca disputa o banco nem a bandeja com a antiga, e funciona igual para `.deb` e `.tar.gz`. A alternativa é um argumento `--wait-pid` no próprio app, que exigiria mexer no `main` e no runner em C++.
- P2 · O aviso "Atualizado para a <versão>" (R6) entra nesta spec, porque é o que confirma para a pessoa que a atualização deu certo. Se o app reabrir sem ele, fica a mesma dúvida de hoje.
- P3 · O mouse continua agitando a logo (R7). O pedido foi tirar o "tocar de novo", e a agitação não toca a abertura: só acelera as bolhas.
- P4 · Causa achada (t1, #223): era a primeira suspeita, por um motivo próprio. O `AppDatabase.close()` do drift espera cada stream de consulta entregar o "done", e o Riverpod 3 pausa o stream de um `StreamProvider` sem ouvintes, como o de uma tela que a pessoa deixou. O stream pausado nunca entrega o "done", e o `close()` nunca volta. O `AppShutdown` fecha só a conexão (`closeDatabaseForExit`), e o limite de 3 s fica como rede de segurança.

## Critérios de aceite

- [x] Instalar fecha o app pelo mesmo encerramento da janela e sai, mesmo com o banco demorando a fechar [R1, R2] verificar: flutter test test/core/installer_test.dart
- [x] O lançador espera o PID antigo sumir e abre o executável certo para `.tar.gz` e `.deb` [R3] verificar: flutter test test/core/installer_test.dart
- [x] Sem lançador, o app não fecha e o cartão oferece "Reiniciar agora" [R4] verificar: flutter test test/ui/about_dialog_test.dart
- [x] Cada passo da atualização aparece no log [R5] verificar: flutter test test/core/installer_test.dart
- [x] A cópia nova mostra "Atualizado para a <versão>" uma vez [R6] verificar: flutter test test/ui/shell
- [x] Clicar, Enter ou Espaço na logo não toca a abertura; ela não tem dica, não entra no Tab e o leitor de tela ouve "Ícone do Promptorium" [R7] verificar: flutter test test/ui/about_dialog_test.dart
- [ ] Atualizar de verdade, de um `.tar.gz` antigo para a release atual, fecha e reabre o app na versão nova [R1, R3, R6] verificar: manual (cópia isolada com `XDG_DATA_HOME` e uma release local)
  - Pendente: a atualização sai do código da versão instalada, então partir de um `.tar.gz` antigo (sem esta correção) ainda trava. O fluxo foi conferido no app real com duas compilações com a correção (cópia isolada, `XDG_DATA_HOME` próprio, `.tar.gz` local e um provider de tela deixado): fechou, reabriu e mostrou "Atualizado para a 0.17.0". Falta atualizar de uma release publicada com a correção para a seguinte.
- [x] O projeto compila e a análise estática passa [R1–R7] verificar: flutter analyze
