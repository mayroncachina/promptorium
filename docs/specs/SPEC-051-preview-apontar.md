---
id: SPEC-051
status: proposta
depende-de: SPEC-022
issue: 126
---

# Preview com apontar e pedir

## Objetivo

Hoje, numa sessão de spec, o cabeçalho tem "Abrir preview :porta". O botão só roda `xdg-open http://localhost:<porta>`. A pessoa precisa subir o servidor de desenvolvimento por conta própria, num terminal, no worktree certo e na porta certa. Para pedir uma mudança visual, ela descreve o elemento em texto ou cola um print.

Esta spec faz o app cuidar do servidor de desenvolvimento de cada worktree: ele sobe, mostra os logs e o estado, e derruba o servidor quando não precisa mais. Ela também traz o "Apontar e pedir". O app abre um Chromium controlado por ele, a pessoa clica num elemento da página, e o elemento vai para a sessão como anexo, com seletor, HTML, estilos e print, junto com o pedido.

A ideia vem do Vibe Kanban (vibekanban.com), que sobe o dev server dentro da ferramenta e tem um navegador com "clicar para editar". Aqui não há webview dentro do app, porque o webview do Flutter no Linux é frágil. O app controla um Chromium separado pelo protocolo de depuração (CDP), só em `127.0.0.1`.

Issue: [#126](https://github.com/mayroncachina/promptorium/issues/126) (mãe: [#124](https://github.com/mayroncachina/promptorium/issues/124)).

Mockup: [canvas do Claude Design](https://claude.ai/artifact/JuYPGhSJ1qxkPKxMkAaRir). Cópia dos quadros e capturas em `docs/mockups/spec-051/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-servidor-no-ar.png` | Sessão com o servidor no ar, aba Preview com estado e logs | R1–R5 |
| `2-porta-ocupada.png` | Servidor que não sobe: porta ocupada por outro processo, com as saídas | R3, R4, R9 |
| `3-apontar.png` | Chromium do app no modo Apontar, com o elemento destacado | R6, R7, R10 |
| `4-pedido.png` | Composer com o elemento anexado e o pedido da pessoa | R8, R11 |

## Requisitos

- R1 · O projeto deve poder declarar o servidor de desenvolvimento em `.promptorium/config.yml`:
  - forma curta: `dev: npm run dev -- --port $PROMPTORIUM_PORT`;
  - forma longa: `dev: {comando, pronto, caminho}`, em que `pronto` é a condição de "no ar" (`porta`, o padrão: a porta responde HTTP; ou um texto que aparece no log) e `caminho` é a página aberta no preview (padrão `/`);
  - o comando roda no worktree da spec, com as variáveis de `worktreeEnvironment` (`PROMPTORIUM_PORT`, `PROMPTORIUM_WORKTREE`…);
  - sem `dev:`, o botão "Abrir preview :porta" de hoje continua igual.
- R2 · Na sessão de spec com `dev:` e porta, o cabeçalho deve trocar "Abrir preview :porta" por um controle do servidor com quatro estados, com ícone e texto:
  - "Servidor parado", com **Iniciar servidor**;
  - "Iniciando… :porta", com **Parar**;
  - "No ar :porta", com **Abrir preview**, **Apontar** e **Parar**;
  - "Falhou", com o motivo curto e **Ver logs**.
- R3 · Antes de subir, o app deve conferir a porta:
  - se ela estiver livre, sobe;
  - se ela estiver ocupada por um servidor que o próprio app subiu para esse worktree, reaproveita;
  - se ela estiver ocupada por outro processo, não sobe e mostra o PID e o comando que estão nela (`ss -ltnp`), com **Usar o que está no ar** (abre o preview sem subir nada) e **Tentar de novo**. O app nunca mata um processo que não subiu.
- R4 · A sessão deve ganhar a aba **Preview**, ao lado de Timeline, Terminal, Diff e Log bruto, com:
  - o estado do servidor, o comando, a porta, o PID e há quanto tempo está no ar;
  - os logs (stdout e stderr), com as últimas 2.000 linhas, busca e "Copiar";
  - **Mandar erro para a sessão**, que envia as últimas linhas do log à sessão como mensagem, quando o servidor falha ou o log mostra um erro.
- R5 · O servidor deve morrer junto com o que o sustenta, sem deixar processo órfão:
  - o comando roda num grupo de processos próprio (`setsid`), e **Parar** manda SIGTERM ao grupo e, depois de 5 s, SIGKILL;
  - ao fechar o app, o `_CloseHandler` para todos os servidores, como já faz com as sessões e os PTYs;
  - ao apagar o worktree (merge, descarte da spec), o servidor dele para antes;
  - o app grava cada servidor em `~/.promptorium/run/dev/<pid>.json` (PID, grupo, worktree, porta). Ao abrir, ele confere esses registros e oferece encerrar os que sobraram de uma execução que caiu.
- R6 · **Abrir preview** com o servidor no ar deve abrir um Chromium do app:
  - perfil próprio por worktree em `~/.cache/promptorium/preview/<chave>`, nunca o perfil do navegador da pessoa;
  - `--remote-debugging-address=127.0.0.1` e `--remote-debugging-port` numa porta livre escolhida pelo app, com `--remote-allow-origins` restrito a essa porta;
  - janela `--app=<url>`, sem abas nem barra de endereço;
  - um segundo clique traz a mesma janela para frente, em vez de abrir outra.
- R7 · **Apontar** deve ligar o modo de seleção na janela do preview, pelo CDP:
  - uma faixa no topo da página: "Promptorium · clique num elemento · Esc cancela";
  - o elemento sob o mouse fica destacado, com o seletor e o tamanho;
  - o clique captura, sem disparar o clique na página: o seletor CSS mais curto e único, o `outerHTML` (até 4 KB), os estilos computados mais relevantes (tamanho, margens, cores, fonte, display), a caixa na página, a URL e dois PNGs (o elemento com uma margem e a página visível com o elemento marcado);
  - Esc ou um segundo **Apontar** desliga o modo sem capturar.
- R8 · O elemento capturado deve chegar ao composer da sessão como anexo:
  - um cartão com a miniatura, o seletor e a URL, que expande para mostrar HTML e estilos, e um botão para remover;
  - dá para apontar vários elementos antes de enviar;
  - ao enviar, a mensagem leva o pedido da pessoa e, para cada elemento, um bloco de texto com seletor, URL, HTML e estilos, além dos PNGs como `ImagePart`;
  - num provedor sem imagem (`codex_provider` sem a modalidade `image`), os PNGs vão como arquivos em `.promptorium/attachments/`, mencionados no texto, como o Prompt já faz.
- R9 · Sem Chrome nem Chromium (mesma busca de `headlessBrowsers` da SPEC-022), **Abrir preview** deve cair no `xdg-open` de hoje, e **Apontar** fica desligado com o motivo e a instrução de instalação (`headlessInstallHint`).
- R10 · O CDP nunca deve ficar exposto fora da máquina nem a outras páginas:
  - só em `127.0.0.1`, numa porta aleatória;
  - o script injetado roda só nas páginas de `localhost` e `127.0.0.1` da porta do preview, e não lê cookies, `localStorage` nem campos de senha;
  - o Chromium do preview fecha quando o servidor para, quando a sessão é apagada ou quando o app fecha.
- R11 · Depois que a sessão responder a um pedido com anexo, o preview deve recarregar sozinho quando o servidor não tiver recarga a quente. O app detecta isso quando o arquivo muda e a página não, em até 3 s.

## Fora do escopo

- Webview dentro da janela do app. O preview é sempre uma janela separada do Chromium.
- Editar o componente direto na página, sem o agente. O clique só gera contexto para o pedido.
- Achar o arquivo e a linha do componente (React DevTools, `data-source`). Fica em aberto em P3.
- Firefox, WebKit e outros navegadores. O CDP é só do Chrome e do Chromium.
- Emular celular, gravar vídeo e testes automatizados no navegador (Playwright).
- Servidor de desenvolvimento no Prompt, sem worktree (P5).
- Mais de um servidor por worktree, como API e front separados (P6).

## Design

### O que já existe

- `lib/features/sessions/sessions_screen.dart`:
  - `previewPortProvider` calcula `porta-base + worktreeIndex` da sessão;
  - `openPreview(port)` roda `xdg-open http://localhost:<porta>`;
  - o cabeçalho (`_Header`) mostra o `SmallButton` "Abrir preview :porta";
  - as abas da sessão estão em `enum SessionTab { timeline, terminal, diff, raw }`.
- `lib/features/project/project_config.dart`: `WorktreeConfig` (`copiar`, `preparar`, `porta-base`). A tela do projeto edita essas chaves em `widgets/project_config_view.dart`.
- `lib/core/git/worktree_setup.dart`: `WorktreeSetup` roda `preparar:` uma vez, e `worktreeEnvironment` monta `PROMPTORIUM_ROOT`, `PROMPTORIUM_WORKTREE`, `PROMPTORIUM_SPEC` e `PROMPTORIUM_PORT`.
- `lib/features/board/spec_runner.dart`: dá a porta de cada worktree e de cada tentativa.
- `lib/features/specs/prototype/prototype_thumbnails.dart`: `headlessBrowsers`, `findBrowser()` e `headlessInstallHint`, da SPEC-022.
- `lib/features/prompt/attachments.dart`: transforma arquivos em `ImagePart` ou em menções `@`, e grava o que fica fora do projeto em `.promptorium/attachments/<data>`.
- `lib/core/claude/claude_process.dart`: `ImagePart` vira um bloco `image` em base64 na mensagem. O `codex_provider.dart` só manda imagem quando o modelo tem a modalidade `image`.
- `lib/main.dart`: o `_CloseHandler` intercepta o fechamento da janela e para as sessões e os PTYs.

### Componentes

- `ProjectConfig` ganha `DevServerConfig? dev` (`comando`, `pronto`, `caminho`), lido nas duas formas de R1 e editável na tela do projeto, junto de `worktree:`.
- `lib/core/dev/dev_server.dart` (novo):
  - `DevServer`, com `start`, `stop` e um stream de estado (`parado`, `iniciando`, `noAr`, `falhou`) e de linhas de log, num buffer circular de 2.000 linhas;
  - roda `setsid sh -c <comando>` no worktree, com `worktreeEnvironment`;
  - `PortProbe`: porta livre, ocupada pelo próprio app ou ocupada por outro (`ss -ltnp`), e espera o HTTP responder;
  - `DevServerRegistry`: um servidor por worktree, gravado em `~/.promptorium/run/dev/` e conferido ao abrir o app (R5).
- `devServerProvider`, uma família por worktree, consumida pelo cabeçalho e pela aba Preview.
- `lib/core/dev/preview_browser.dart` (novo):
  - abre o Chromium com o perfil e as flags de R6 e guarda a porta do CDP;
  - fala com o CDP por WebSocket (`dart:io`), sem pacote novo: `Runtime.evaluate` para injetar o seletor, `Runtime.addBinding` para receber o clique, `DOM.describeNode` e `CSS.getComputedStyleForNode` para o HTML e os estilos, e `Page.captureScreenshot` com `clip` para os PNGs.
- `lib/core/dev/picker_script.dart`: o JavaScript injetado (faixa, destaque, seletor único e Esc), guardado como string e testado com um DOM falso.
- `SessionTab.preview` e `widgets/preview_tab.dart`: estado, logs e "Mandar erro para a sessão" (R4).
- O composer ganha `PickedElement` como anexo (R8). O envio reaproveita `ImagePart` e, no Codex sem imagem, o caminho de `attachments.dart`.
- `_CloseHandler` chama `DevServerRegistry.stopAll()` e fecha os Chromium do preview (R5, R10).

## Critérios de aceite

- [ ] `dev:` é lido na forma curta e na longa, e sem a chave o botão de hoje não muda [R1] verificar: flutter test test/features/project/project_config_test.dart
- [ ] O servidor passa por parado, iniciando, no ar e falhou, com a condição `pronto` de porta e de texto no log [R2] verificar: flutter test test/core/dev/dev_server_test.dart
- [ ] Porta ocupada por outro processo não sobe nada, mostra PID e comando e nunca mata o processo [R3] verificar: flutter test test/core/dev/dev_server_test.dart
- [ ] A aba Preview mostra estado, logs com limite de 2.000 linhas e manda o erro para a sessão [R4] verificar: flutter test test/features/sessions/preview_tab_test.dart
- [ ] Parar mata o grupo inteiro, inclusive os filhos do comando [R5] verificar: flutter test test/core/dev/dev_server_test.dart
- [ ] Os registros de uma execução que caiu são encontrados ao abrir e podem ser encerrados [R5] verificar: flutter test test/core/dev/dev_server_test.dart
- [ ] O Chromium do preview abre com perfil próprio e CDP só em 127.0.0.1, e um segundo clique reaproveita a janela [R6, R10] verificar: flutter test test/core/dev/preview_browser_test.dart
- [ ] O seletor gerado é único na página e o clique é capturado sem chegar à página [R7] verificar: flutter test test/core/dev/picker_script_test.dart
- [ ] O pedido sai com o texto do elemento e os PNGs, e no Codex sem imagem vai como arquivos [R8] verificar: flutter test test/features/sessions/composer_test.dart
- [ ] Sem Chrome nem Chromium, Abrir preview usa o xdg-open e Apontar fica desligado com o motivo [R9] verificar: flutter test test/core/dev/preview_browser_test.dart
- [ ] Um app Vite de exemplo sobe, um botão é apontado, o agente o muda e o preview mostra a mudança [R1–R8, R11] verificar: manual (projeto de teste com `dev: npm run dev -- --port $PROMPTORIUM_PORT`)
- [ ] Fechar o app com dois servidores no ar não deixa processo na porta [R5] verificar: manual (`ss -ltnp` depois de fechar)
- [ ] O projeto compila e a análise estática passa [R1–R11] verificar: flutter analyze

## Decisões

Perguntas em aberto, para decidir antes de implementar:

- P1 · Onde ficam o estado e os logs? Proposta: numa aba Preview da sessão (R4). A alternativa é um painel no painel lateral, que fica visível ao mesmo tempo que a Timeline.
- P2 · O servidor sobe sozinho? Proposta: não, só com **Iniciar servidor**. Uma opção `dev: {auto: true}` subiria ao abrir a sessão. Rodar vários worktrees com servidor ao mesmo tempo pesa na máquina, e o Autopilot roda até `paralelo` specs.
- P3 · Mandar o arquivo e a linha do componente? Só dá quando o framework expõe isso (React em modo de desenvolvimento, plugin `data-source` do Vite). Proposta: fica fora da primeira versão. O seletor, o HTML e o print bastam para o agente achar o componente com Grep.
- P4 · `dev:` sem `porta-base`? Proposta: o app escolhe uma porta livre e passa em `PROMPTORIUM_PORT`. A alternativa é exigir `porta-base` e avisar na tela do projeto.
- P5 · Servidor no Prompt, na raiz do projeto, sem worktree? Proposta: fora desta spec.
- P6 · Mais de um processo por worktree (front e API)? Proposta: fora. Quem precisa usa um comando que sobe os dois (`npm-run-all`, `concurrently`).
- P7 · Com mockups: o servidor no ar com a aba Preview, a porta ocupada, o modo Apontar no Chromium e o composer com o elemento anexado.
