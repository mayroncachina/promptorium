---
id: SPEC-085
status: aprovada
versão: 0.20.0
tipo: recurso
issue: 273
---

# Vigia de segredos

## Objetivo

O agente commita e abre PR sozinho: nas etapas de spec, no Autopilot, nas VIBEs, no "Corrigir CI". Nada confere se o que vai no commit tem um segredo. Basta um `git add -A` com um `.env` que não está no `.gitignore`, uma chave que o agente colou num teste "só para funcionar", ou um `id_rsa` copiado para o projeto, e o segredo vai para o histórico. Depois do `push`, o segredo vazou: tem de ser trocado no provedor, e limpar o histórico dá muito trabalho.

Exemplo: na spec SPEC-031 · Pagamento com Stripe, a pessoa passa a chave de teste no prompt. O agente escreve `const stripeKey = 'sk_live_51Hx…'` em `src/config/pagamento.ts`, cria um `.env` com `DATABASE_URL=postgres://app:S3nh4@db…` e roda `git add -A && git commit -m "SPEC-031 R2: integra Stripe"`. Em seguida, o app faz o `push` e abre o PR. A chave fica pública no GitHub, e o PR já disparou a CI com ela.

Esta spec cria o **Vigia de segredos**:
- antes de um **commit, push ou PR do agente**, o app procura segredos no que vai entrar: chaves e tokens conhecidos, strings de alta entropia em atribuições, arquivos `.env` e chaves privadas;
- se achar, **bloqueia** e mostra os achados **mascarados**, com três saídas: **remover**, **ignorar com justificativa** ou **abrir o arquivo**;
- vale também para os commits e pushes que o **próprio app** faz (Criar PR, "arquivos restantes da etapa", VIBE) e para o **commit manual** da tela Código;
- o segredo **nunca** aparece inteiro, nem na tela, nem nos logs, nem no banco.

Issue: [#273](https://github.com/mayroncachina/promptorium/issues/273) (sub-issue de [#278](https://github.com/mayroncachina/promptorium/issues/278))

Mockup: [canvas do Claude Design](https://claude.ai/artifact/EWDq9ALnW9HXQ15YvMd8nE). Capturas em `docs/mockups/spec-085/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-sessao.png` | A sessão com o commit do agente bloqueado: os achados mascarados e as três ações | R1–R4, R7–R10 |
| `2-ignorar.png` | Ignorar com justificativa: o motivo obrigatório e o alcance | R11, R12 |
| `3-app-e-manual.png` | "Criar PR" bloqueado no Review e o commit manual da tela Código | R5, R6 |
| `4-configuracoes.png` | Configurações › Vigia de segredos: motor, regras, onde vale e os ignorados | R13–R16 |

## Requisitos

### Onde o vigia olha

- R1 · **Commit e push do agente.** Um hook `PreToolUse` novo do app, **"Vigia de segredos"** (`ManagedHook.secrets`), olha cada comando `Bash` do agente. Ele age quando o comando tem `git commit`, `git push` ou `gh pr create` (inclusive dentro de `&&`, `;` e `git -C …`). O que ele confere:
  - no **commit**: tudo o que o comando pode pôr no commit, que é o diff do índice e do working tree contra o `HEAD` mais os arquivos não rastreados e não ignorados. É um superconjunto de propósito: `git add -A && git commit` roda o hook antes do `add`;
  - no **push** e no **`gh pr create`**: as linhas adicionadas nos commits que ainda não estão no remoto (`@{upstream}..HEAD`, ou `<remote>/<base>..HEAD` sem upstream).
  
  Com achado, o hook nega o comando (`permissionDecision: deny`). O motivo, que o agente lê, é este: "Promptorium: o Vigia de segredos bloqueou o commit: 2 achados (Stripe live key em src/config/pagamento.ts:12; arquivo .env). Não tente contornar nem mudar o comando; espere o usuário decidir.".
- R2 · **Sem o hook.** O hook depende do `python3` (como os outros hooks do app) e não roda no Codex. Nesses casos, o vigia confere ao fim de cada turno os commits novos do turno, antes de qualquer push feito pelo app (R5). Um commit local com segredo ainda não vazou: o bloqueio acontece no push. A timeline avisa uma vez por sessão: "Vigia de segredos sem hook nesta sessão (Codex): os commits são conferidos ao fim do turno e antes do push".
- R3 · **O que conta como achado.**
  - **Arquivos sensíveis** pelo nome, entrando no commit: `.env` e `.env.*` (menos `.env.example`, `.env.sample` e `.env.template`), `*.pem`, `*.key`, `*.p12`, `*.pfx`, `id_rsa`, `id_ecdsa`, `id_ed25519`, `credentials.json`, `service-account*.json`, `.npmrc` e `.pypirc` com token.
  - **Padrões conhecidos** nas linhas adicionadas: chave da AWS (`AKIA…`), tokens do GitHub (`ghp_`, `gho_`, `ghs_`, `ghu_`, `github_pat_`), GitLab (`glpat-`), Slack (`xox…`), Stripe live (`sk_live_`, `rk_live_`), Google API (`AIza…`), Anthropic (`sk-ant-`), OpenAI (`sk-…`), JWT, cabeçalho de chave privada (`-----BEGIN … PRIVATE KEY-----`) e URL com senha (`postgres://user:senha@`).
  - **Alta entropia em atribuição**: um valor entre aspas com 20 ou mais caracteres, atribuído a um nome como `password`, `secret`, `token`, `api_key`, `apikey` ou `auth`, com entropia de Shannon acima de 4,0 (base64) ou 3,0 (hex).
  
  Só as **linhas adicionadas** contam. As removidas e as de contexto não contam, e arquivos binários ficam de fora. Acima de 5 MB de diff, o vigia confere só os nomes dos arquivos e os padrões de chave privada, e avisa que a conferência foi parcial.
- R4 · **O que não conta.** Não contam:
  - uma linha com o comentário `promptorium:allow-secret` (ou `gitleaks:allow`);
  - os caminhos de `segredos.ignorar` no `.promptorium/config.yml` (globs, como `test/fixtures/**`);
  - os valores de exemplo óbvios: `xxx`, `changeme`, `your-api-key`, `<TOKEN>`, `${VAR}`, `process.env.X`;
  - os achados já ignorados com justificativa (R11).

### Commits do app e manuais

- R5 · **Commits e pushes do app.** Antes de cada commit ou push que o app faz, o vigia confere com as mesmas regras:
  - o "Criar PR" do Review (`createPr`: o `_commitPending` e o `push`);
  - o `pushIfAhead`;
  - "arquivos restantes da etapa" (`SpecRunner`, `commitAll`);
  - os commits da VIBE (`vibe_service`);
  - o push do "Corrigir CI".
  
  Com achado, a ação para antes do commit e abre a janela de achados (R7). Num fluxo automático (Autopilot, Corrigir CI automático), a spec fica parada em "precisa de você", com o pedido "Segredo encontrado" no Início, na Atividades (SPEC-076) e no balão do card do Quadro.
- R6 · **Commit manual da tela Código.** O "Commitar" do painel Git da tela Código também passa pelo vigia. Com achado, a mesma janela aparece antes do commit. Aqui, "Ignorar com justificativa" se chama **"Commitar mesmo assim…"**, porque quem commita é a própria pessoa. O vigia não olha os commits feitos fora do app, no terminal integrado ou num terminal externo.

### Mostrar sem vazar

- R7 · **O cartão do bloqueio.** Na timeline da sessão, o bloqueio vira um cartão âmbar: "Vigia de segredos bloqueou o commit · 2 achados". Cada achado mostra o arquivo e a linha, a regra (por exemplo "Stripe live key") e o valor mascarado (R8), e tem as ações do R9. A sessão passa a "precisa de você": o selo âmbar aparece na lista de sessões, no Início, na Atividades e na notificação.
- R8 · **Máscara.** O valor nunca aparece inteiro, em nenhum lugar: tela, timeline, notificação, log de hooks, `session_events`, `debugPrint`, motivo enviado ao agente ou banco. A máscara mostra:
  - o prefixo público da regra, quando existe (`sk_live_`, `ghp_`, `AKIA`); sem prefixo, os 2 primeiros caracteres;
  - pontos no lugar do resto;
  - o tamanho entre parênteses.
  
  Por exemplo, `sk_live_••••••••••••(107)` e `S3••••••(6)`. Uma chave privada vira `-----BEGIN RSA PRIVATE KEY----- •••• (1.679 caracteres)`. Para um arquivo sensível (`.env`), aparecem o nome e as chaves das variáveis, nunca os valores: `.env · DATABASE_URL, STRIPE_SECRET`. A linha do código é mostrada com o valor mascarado no lugar. Para reconhecer o mesmo segredo de novo (R11), o app guarda só uma impressão (`sha256` do valor com um sal local do app), nunca o valor.
- R9 · **As três ações** de cada achado (e "Para todos" no topo do cartão):
  - **Remover**: para um arquivo sensível, o app tira o arquivo do índice (`git rm --cached`), acrescenta o nome ao `.gitignore` e mantém o arquivo no disco. Para um segredo dentro do código, o app manda ao agente: "Tire o segredo de src/config/pagamento.ts:12 e leia de uma variável de ambiente (`STRIPE_SECRET`); depois repita o commit." Num commit do app ou manual, o "Remover" de um segredo no código abre o arquivo na linha (o app não reescreve código);
  - **Ignorar com justificativa…**: abre a janela do R11;
  - **Abrir o arquivo**: abre a tela Código no arquivo, na linha do achado, com a linha destacada.
  
  Quando nada sobra, o app avisa o agente ("Os achados foram resolvidos; pode repetir o commit.") ou, num commit do app, refaz a ação que tinha parado.
- R10 · **Teclado e leitor de tela.** O cartão e a janela são navegáveis pelo Tab. Cada achado anuncia "Stripe live key em pagamento.ts linha 12, valor oculto". O estado não depende só da cor: há ícone e texto.

### Ignorar com justificativa

- R11 · **A justificativa.** "Ignorar com justificativa…" pede um motivo de, no mínimo, 10 caracteres (por exemplo, "chave de teste revogada, usada só no fixture") e o alcance:
  - **só este valor**, pela impressão: o mesmo segredo em qualquer arquivo deste workspace;
  - **este arquivo**: qualquer achado da mesma regra neste caminho.
  
  O registro guarda o workspace, a regra, o caminho, a impressão, o motivo, a hora e quem pediu (sessão ou commit manual). Ele vai para a tabela `secret_waivers`, nunca para o repositório. A timeline mostra "Ignorado: Stripe live key em pagamento.ts:12 — chave de teste revogada…".
- R12 · **Ignorar não é para sempre.** Em Configurações › Vigia de segredos, a lista dos ignorados mostra a regra, o caminho, o motivo e a data, cada um com "Remover". Um ignorado que ficou 90 dias sem casar com nada sai sozinho.

### Configurações e motor

- R13 · **Motor.** O padrão são as **regras próprias** do app (R3), sempre disponíveis. As regras ficam num só lugar (`secret_rules.dart`) e são exportadas como dados para o hook (`hooks-config.json`). O Dart e o Python usam o mesmo conjunto, e um teste confere que os dois dão o mesmo resultado num corpus de exemplos. Com o **gitleaks** instalado (`gitleaks version` ≥ 8.18), a opção "Usar também o gitleaks" o roda junto, com `--redact` e `--no-banner`, e soma os achados. O app nunca lê a saída sem `--redact`.
- R14 · **Onde vale.** Em Configurações › Vigia de segredos:
  - "Commits e PRs do agente" (sempre ligado enquanto o vigia estiver ligado);
  - "Commits e pushes do app" (ligado);
  - "Commit manual na tela Código" (ligado);
  - o interruptor geral "Vigia de segredos", ligado por padrão. Desligar pede confirmação e fica registrado na timeline das sessões abertas.
- R15 · **Regras.** A lista das regras, cada uma com um interruptor e o nome, e o campo dos caminhos ignorados do workspace (gravado em `segredos.ignorar` no `.promptorium/config.yml`). Não há editor de regras novas (fora do escopo).
- R16 · **Rápido.** A conferência de um commit típico (até 200 arquivos e 1 MB de diff) leva menos de 1 s. Ela roda no hook, sem chamar o app. Se passar de 10 s, o hook libera o comando e registra "Vigia de segredos: tempo esgotado, commit não conferido" na timeline. O vigia nunca trava o agente para sempre.

## Fora do escopo

- Limpar segredos do histórico já enviado (`git filter-repo`, BFG) e revogar a chave no provedor. A janela só lembra: "Se o segredo já foi enviado, troque-o no provedor."
- Varrer o repositório inteiro ou o histórico antigo. O vigia só olha o que vai entrar agora.
- Mascarar o segredo no diff do Review, no editor da tela Código e no terminal. Ali é o arquivo da pessoa, mostrado como está.
- Regras escritas pela pessoa (regex própria). Fica para outra spec, se pedirem.
- Commits feitos no terminal (integrado ou externo) e hooks `pre-commit` do git no repositório da pessoa.
- Conferir o prompt e as respostas do Claude (segredo colado na conversa).

## Design

Canvas para validar: [Vigia de segredos](https://claude.ai/artifact/EWDq9ALnW9HXQ15YvMd8nE). Ele tem quatro artboards: a sessão com o bloqueio, a justificativa, o app e o commit manual, e as configurações.

### O que já existe

- `lib/core/claude/managed_hooks.dart`: `ManagedHook` (`block`, `format`, `end`), o `hookScript` em Python com `PreToolUse` em `Bash` e `permissionDecision: deny`, o log JSON por sessão e `HookActivity`, que vira nota na timeline. É o caminho do R1.
- `lib/features/sessions/session_manager.dart`: `_prepareHooks` e `_readHooks` (hooks por sessão, log → timeline), `notifyUserEdit` e `_notices` (mensagens do app ao agente).
- `lib/features/review/review_service.dart`: `createPr` (`_commitPending` + `push`), `pushIfAhead`.
- `lib/features/board/spec_runner.dart`: o `commitAll` de "arquivos restantes da etapa". `lib/features/vibe/vibe_service.dart`: os `commitAll` da VIBE.
- `lib/features/code/code_panels.dart`: `commit(message)` do painel Git da tela Código.
- `lib/core/git/git_service.dart`: `commitAll`, `diff`, `status`.
- `lib/features/home/home_inbox.dart` e `lib/features/activities/activity.dart`: os pedidos "precisa de você".

### Componentes

- **`lib/core/secrets/secret_rules.dart`**: `SecretRule` (id, nome, padrão, prefixo público, entropia mínima, tipo: arquivo, padrão ou entropia) e a lista padrão (R3, R4). `toHookJson()` exporta as regras para o hook.
- **`lib/core/secrets/secret_scanner.dart`**: `scanDiff(String diff, {rules, ignored, waivers})` → `List<SecretFinding>`. É uma função pura: lê o diff unificado, só as linhas `+`, aplica as regras, a entropia e as exceções. `SecretFinding` tem o caminho, a linha, a regra, `masked`, `fingerprint` e a linha mascarada, e **nenhum campo com o valor**.
- **`maskSecret(value, rule)`** e **`fingerprintOf(value)`** (R8).
- **`lib/core/secrets/gitleaks.dart`**: detecta a versão e roda `gitleaks git --staged --redact --report-format json` (ou `stdin`) (R13).
- **`hookScript`**: o ramo `secrets` em Python, com o mesmo algoritmo, os achados no log (`evento: segredo`, já mascarados) e o `deny` (R1, R16).
- **`lib/core/secrets/secret_guard.dart`**: `SecretGuard.check(worktree, kind)` (commit/push) para os fluxos do app e da tela Código (R5, R6). Ele lança `SecretsFound(findings)`, que a UI trata.
- **`lib/features/sessions/widgets/secret_block_card.dart`**: o cartão da timeline (R7, R9, R10). **`lib/ui/widgets/secret_findings_dialog.dart`**: a janela compartilhada pelo app, pelo Código e pela justificativa (R9, R11).
- **`lib/data/repos/secret_waivers_repo.dart`** e a tabela `secret_waivers` (R11, R12).
- Configurações: a seção **"Vigia de segredos"** em `settings_sections.dart` (R13–R15). `ProjectConfig`: `segredos.ignorar`.
- Pedidos: o tipo novo "Segredo encontrado" em `home_inbox.dart` e em `buildActivities`.

### Migração

**Precisa de migração**: a tabela nova `secret_waivers` (workspace, regra, caminho, impressão, alcance, motivo, origem, criado em, último uso), na v29 ou na próxima livre quando implementar. O sal da impressão e as preferências do R14 ficam em `app_settings`, sem migração.

### Testes

- `scanDiff`: cada regra acha o seu exemplo. Só as linhas `+` contam. As exceções (`promptorium:allow-secret`, os caminhos ignorados, os exemplos óbvios e as justificativas) funcionam. `.env.example` passa e `.env` não. Entropia: um hash de commit numa atribuição `sha` não conta; uma senha `token = "…"` de 32 caracteres aleatórios conta.
- `maskSecret`: nenhum resultado contém mais que o prefixo público ou 2 caracteres do valor. O tamanho aparece.
- **Nada vaza**: um teste roda o fluxo inteiro com segredos sentinela (`sk_live_SENTINELA…`) e confere que o valor não aparece no log de hooks, em `session_events`, na timeline renderizada, no banco nem na saída de `debugPrint`.
- Paridade Dart × Python: o mesmo corpus dá os mesmos achados no `scanDiff` e no `hookScript`.
- Hook: `git add -A && git commit` com um `.env` não rastreado é negado. `git push` com o segredo num commit anterior ainda não enviado é negado. Um comando sem commit, push ou PR passa direto. Tempo esgotado libera.
- `SecretGuard`: `createPr` com achado não faz commit nem push. "Arquivos restantes" para. O commit da tela Código abre a janela.
- Ações: "Remover" `.env` tira do índice e põe no `.gitignore`. "Ignorar" com menos de 10 caracteres não deixa confirmar. O ignorado não volta a bloquear.

## Critérios de aceite

- [x] As regras acham chaves, tokens, chaves privadas, `.env` e alta entropia só nas linhas adicionadas, com as exceções [R3, R4] verificar: flutter test test/core/secrets/secret_scanner_test.dart
- [x] Nenhum achado mostra mais que o prefixo público e o tamanho, e o valor não aparece em log, timeline, banco nem `debugPrint` [R8] verificar: flutter test test/core/secrets/secret_leak_test.dart
- [x] O hook nega `git commit`, `git push` e `gh pr create` com achado e libera o resto; tempo esgotado libera [R1, R16] verificar: flutter test test/core/claude/managed_hooks_secrets_test.dart
- [x] O Dart e o Python dão os mesmos achados no corpus [R13] verificar: flutter test test/core/secrets/secret_parity_test.dart
- [x] "Criar PR", "arquivos restantes", a VIBE e o commit da tela Código param com achado e abrem a janela [R5, R6] verificar: flutter test test/core/secrets/secret_guard_test.dart
- [x] Remover, ignorar com justificativa e abrir o arquivo funcionam, e o ignorado não volta a bloquear [R9, R11, R12] verificar: flutter test test/features/sessions/widgets/secret_block_card_test.dart
- [x] No app, uma sessão real que commita um `.env` e uma chave Stripe de mentira é bloqueada, o cartão mostra os valores mascarados e "Remover" deixa o commit passar [R1–R11] verificar: manual (app isolado com `XDG_DATA_HOME`, prints em `docs/mockups/spec-085/app/`)
- [x] O projeto compila e a análise estática passa [R1–R16] verificar: flutter analyze

## Decisões em aberto

- P1 · **Regras próprias ou gitleaks.** **Decidido:** **regras próprias como padrão**, sempre ligadas, com o **gitleaks como complemento opcional** quando estiver instalado (R13). O gitleaks não vem com o app nem com as distros mais comuns, então depender dele deixaria a maioria sem vigia. As regras próprias ficam como dados, então o hook em Python e o Dart usam as mesmas, e dá para testar sem binário externo. O gitleaks soma cobertura (centenas de regras) para quem já o tem, sempre com `--redact`.
- P2 · **Commit manual (tela Código) entra?** **Decidido:** **sim, ligado por padrão**, com "Commitar mesmo assim…" no lugar de "Ignorar" (R6). O custo é baixo (a mesma conferência) e o erro é o mesmo, seja do agente ou da pessoa. Quem não quer desliga em Configurações. Commits feitos no terminal ficam de fora: o app não os vê.
- P3 · **Bloquear o commit ou só o push.** **Decidido:** **bloquear já no commit** do agente (o pedido) e garantir no push. Bloquear só no push deixaria o segredo no histórico local, e tirá-lo depois exige reescrever commits. No Codex e sem `python3`, o push é a última barreira (R2).
- P4 · **Como a pessoa libera.** **Decidido:** o hook **nega** (`deny`), e o app mostra o cartão com as ações. Responder ao `deny` não é possível, então "Ignorar" grava a justificativa e manda ao agente "pode repetir o commit". A alternativa, `permissionDecision: ask`, viraria uma aprovação comum, que o "Sempre permitir" e o modo "Sem perguntar" poderiam pular.
- P5 · **Onde guardar as justificativas.** **Decidido:** **no banco do app** (`secret_waivers`), local, com a impressão e não o valor. Um arquivo no repositório (como o `.gitleaksignore`) espalharia as impressões pelo time e pelo histórico. Para o time, os caminhos de `segredos.ignorar` no `config.yml` cobrem o caso (fixtures de teste).
- P6 · **Máscara.** **Decidido:** o **prefixo público** da regra (ou 2 caracteres) e o **tamanho**, nunca o final. Mostrar os últimos 4 caracteres, como fazem alguns painéis, já ajudaria a adivinhar uma senha curta.
- P7 · **Fluxos automáticos.** **Decidido:** o Autopilot e o Corrigir CI automático **param** na spec com o achado ("precisa de você") e seguem com as outras specs. O vigia nunca ignora sozinho.
