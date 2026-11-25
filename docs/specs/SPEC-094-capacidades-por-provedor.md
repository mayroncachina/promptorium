---
id: SPEC-094
status: concluida
versao: 0.23.0
tipo: melhoria
epico: 332
issue: 334
depende-de: [SPEC-093]
---

# Capacidades e opções por provedor

## Objetivo

As telas e os serviços do app falam hoje a língua do Claude Code: montam `maxBudgetUsd`, `agent`, `settingsFile`, aliases `opus`/`sonnet` e `ClaudePermissionMode`, e cada adaptador se vira com isso. Com o Codex selecionado, o resultado é uma de duas coisas: a execução nem começa, ou começa com a opção errada.

Exemplo concreto (DT-56): com o Codex como provedor, a pessoa liga o review automático de uma etapa. O revisor monta `maxBudgetUsd: 2`, `agent: revisor` e o modelo `sonnet`, e o `CodexProvider.validateOptions` recusa:

> Codex: opções ainda sem equivalente validado: limite monetário, perfil de agente Claude. Ajuste a configuração antes de executar.

Não há o que ajustar na tela: as opções vêm do serviço, não da pessoa. No caminho contrário, a Nova sessão aplicava o modelo e o esforço do Claude ao Codex sem avisar. E há 37 comparações `== 'claude'` / `!= 'claude'` espalhadas em 15 arquivos de `lib/` decidindo, caso a caso, o que cada provedor aceita.

Esta spec troca isso por **capacidades declaradas por provedor**. Cada provedor diz o que suporta; os serviços montam só intenções do app; o adaptador traduz; e a interface mostra "Só Claude Code" (ou "Só Codex") onde a opção não se aplica, em vez de esconder ou falhar no meio (decisão 1 do épico).

## Requisitos

### Capacidades

- R1 · **`ProviderCapabilities`.** Um tipo novo em `lib/core/providers/capabilities.dart`, por provedor e modelo, com pelo menos: `images`, `structuredOutput`, `budgetUsd`, `maxTurns`, `planMode`, `readOnlyEnforced`, `managedHooks`, `agentFiles`, `subagents`, `mcpConfig`, `appMcpServer`, `compactNow`, `steerMidTurn`, `liveApprovalChange`, `quota`, `costUsd`, `nativeReview`, `revertConversation`. Cada campo é `suportado`, `parcial` (com o motivo) ou `não suportado`.
- R2 · **De onde vem.** Claude Code: valores fixos no adaptador, como o app já usa hoje. Codex: a tabela "Capacidades comprovadas no 0.170" da SPEC-093 mais o `model/list` (modalidades e esforços de cada modelo). Agentes ACP: o mínimo (sem estruturado, sem cota, sem custo) até alguém provar mais. Uma capacidade "não testada" na sondagem conta como não suportada.
- R3 · **Por fluxo.** Um registro `providerFlows` diz em quais fluxos cada provedor está liberado: Prompt, Sessões, Executar spec, Review automático, execuções estruturadas (Projeto, Gerar tarefas, Nova skill…), Comparar, Protótipo de telas. O Codex nasce com todos desligados; cada spec do épico liga o seu (a SPEC-096 liga Prompt e Sessões). O registro substitui o interruptor global `codexEnabledProvider`.

### Opções

- R4 · **Intenção + extras.** `AgentStartOptions` passa a ter só intenções do app: pasta, modo de acesso (`PromptMode` + YOLO), modelo, esforço, retomar/bifurcar, instruções adicionais, schema de saída, imagens, ambiente e MCP do app. O que é de um provedor vai para extras tipados: `ClaudeExtras` (`maxBudgetUsd`, `maxTurns`, `agent`, `agentsJson`, `settingsFile`, `tools`, regras MCP, `autocompact`) e `CodexExtras` (`sandbox`, `approval`, `writableRoots`, overrides `-c`, limite de compactação).
- R5 · **Serviços montam só o que existe.** Quem monta opções consulta as capacidades do provedor resolvido e não monta o que ele não suporta: sem `maxBudgetUsd` sem `budgetUsd`, sem `agent` sem `agentFiles`, sem `jsonSchema` sem `structuredOutput`. O `readonly_run.dart` (`runReadOnlyClaude`) já aplica isso nesta spec, sem mudar os 16 chamadores (a migração deles é da SPEC-100).
- R6 · **Falhar fechado continua.** Extras de um provedor entregues ao adaptador de outro continuam sendo erro, agora de programação (teste falha), não de uso. O adaptador nunca descarta uma opção em silêncio.
- R7 · **Modo de acesso por provedor.** Uma função por adaptador traduz o acesso (decisão 3): Perguntar e Planejar = só leitura imposta pelo runtime (`read-only` + `never` no Codex); Editar = escreve com confirmação (`workspace-write` + `on-request`); Refinar = cada edição pede aprovação; YOLO = `danger-full-access` + `never`, só em worktree. A política do Codex usa os valores que a SPEC-093 comprovou (o `untrusted` sai se tiver sumido). `permission_policy.dart` vira essa função.

### Modelo e esforço

- R7a · **Sandbox disponível (decisão 15).** Capacidade nova por máquina, `osSandbox`, detectada sem gastar cota: `configWarning` do App Server logo após o `initialize` ou um `command/exec ["true"]` em `readOnly` (SPEC-093, achado 2). Sem sandbox (Ubuntu 24.04 padrão, AppArmor com `apparmor_restrict_unprivileged_userns=1`), Perguntar, Planejar e Editar do Codex ficam indisponíveis, porque todo comando falharia; o Codex só roda em **worktree com acesso total** (`danger-full-access` + `never`), e o app commita o que sobrar no fim do turno (SPEC-096 R10). O rodapé e Configurações → Provedores mostram "Sandbox do Codex indisponível" com o comando para liberar (`sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0` ou um perfil AppArmor para o `bwrap`) e o botão "Verificar de novo". O app nunca altera o sistema sozinho.

- R8 · **Modelos por provedor.** Configurações → Consumo ganha uma aba por provedor (Claude Code, Codex). Na aba Codex, os modelos e os esforços vêm do `model/list`, lidos sob demanda e guardados com a versão e a hora da leitura ("lista lida do Codex 0.170 às 14:02 · Atualizar"). As chaves `codex.model.<tipo>` e `codex.effort.<tipo>` já existem e continuam. Um alias do Claude nunca vai para o Codex, nem o contrário.
- R9 · **Modelo que sumiu.** Um modelo salvo que não está mais no `model/list` aparece como "indisponível nesta versão" e a execução usa o padrão do provedor, dizendo isso no cabeçalho da sessão ou conversa. Nada de nomes de modelo fixos no código.

### Versão e estado

- R10 · **Versão mínima.** Na detecção, `codex --version` abaixo de 0.170 (decisão 10) deixa o provedor como **incompatível**, com "versão instalada 0.168.0, mínimo 0.170. Atualize o Codex CLI (`codex update`)". Acima da última versão testada, o provedor funciona com o aviso "versão mais nova que a testada (0.170)". A lista de métodos do App Server usados pelo app (SPEC-093 R2) é conferida contra a versão instalada quando esta mudar; um método ausente também deixa o provedor incompatível, nomeando o método.
- R11 · **Etiqueta "Só Claude Code".** Controles que dependem de uma capacidade ausente ficam desabilitados com a etiqueta "Só Claude Code" (ou "Só Codex") e uma dica com o motivo em uma linha ("O Codex não tem limite em US$"). Fluxos não liberados (R3) aparecem no seletor de provedor do fluxo como "Codex · Só Claude Code por enquanto", não somem.
- R12 · **Nunca trocar em silêncio.** Se o provedor resolvido não serve para o fluxo, a execução não começa e a tela diz o motivo antes do clique, com a opção explícita de rodar com o outro provedor. Nenhum caminho cai para o Claude sozinho.
- R13 · **Fim das comparações soltas.** As decisões de `== 'claude'` / `!= 'claude'` fora dos adaptadores e do registro passam a consultar capacidades ou `providerFlows`. Sobram comparações só em `lib/core/claude/`, `lib/core/codex/` e `lib/core/providers/`.

### Identidade visual do provedor

- R14 · **Identidade por provedor: cor, logo oficial e glifo.** Dois tokens novos: `providerClaude` = argila `#D97757` e `providerCodex` = porcelana `#E8E4DA` (ver Design). Três regras:
  1. **Só identidade, nunca estado.** A cor diz *quem* roda, não *como está*. Rodando, falhou, feita, aguardando e verificando continuam com as cores de hoje (`teal`, `red`, `CanvasColors.*`). Um seletor de provedor marca a opção escolhida com o âmbar de sempre, não com a cor do provedor.
  2. **Nunca só a cor.** A cor sempre vem com o nome e com o logo ou o glifo do provedor.
  3. **Logo oficial onde identifica, glifo onde é pequeno.**
     - (a) **Chip de marca:** logo oficial sem alterar a forma, sempre ao lado do nome ("Claude" / "Codex"), sobre fundo neutro (`#222732`, canto 5 px), com a borda do chip na cor do provedor (argila ou porcelana, translúcida). Claude = símbolo do Claude, sempre em argila `#D97757`; Codex = logo da OpenAI (Blossom) no branco oficial, como fornecido, nunca recolorido. A porcelana é a cor de identidade do Codex (marca de glifo, borda do Comparar, borda do chip), mas nunca pinta o logo. Logo com 16 px (14 px no mínimo, em listas).
     - (b) **Glifo próprio** onde um logo ficaria ilegível: Claude = arco aberto; Codex = livro aberto ("códice"). Aparece como marca de 14 px (bolinha com o glifo) ou como chip preenchido na cor do provedor com texto `#1A1206` (`onAmber`).
     - (c) **Borda** de cada lado no Comparar.
     - A forma de estado continua sendo a pílula translúcida com canto 10 px, então nenhuma das duas formas se confunde com ela.
  - O logo nunca vira ícone do Promptorium nem aparece de um jeito que sugira parceria ou endosso. Ver "Uso de marca" no Design.
- R15 · **Onde aparece.**
  - **Logo oficial (R14a):** seletor de provedor no rodapé, com o chip ao lado do estado do provedor ativo (o ponto de estado continua) e o menu do provedor; Configurações (Provedores, abas de Consumo, "O que o Codex faz neste app"); chip de sessão e de conversa (lista, cabeçalho, painel de detalhes, autor do turno na timeline e no replay, seletor do compositor); seletores da Nova sessão e do Executar spec; topo de cada lado do Comparar.
  - **Glifo (R14b):** ponto nos cards do Quadro, robôs dos agentes, Histórico, Custo por etapa e listas de specs.
  - Provedores sem token (agentes ACP, Gemini) aparecem só com o nome, sem cor e sem logo, até ganharem um.

## Fora do escopo

- Ligar o Codex em qualquer fluxo (SPEC-096 em diante).
- Migrar os chamadores de `runReadOnlyClaude` para um `runStructured` neutro (SPEC-100).
- Limites do lado do app que substituam orçamento e turnos no Codex (tempo, número de turnos). Ver P1.
- Provedor por tipo de execução (decisão 4) na UI de Consumo: os seletores de provedor por tipo entram com a SPEC-100; aqui a aba Codex só define modelo e esforço.
- Mudar o modelo de eventos (SPEC-095) ou a cota (SPEC-097).

## Decisões em aberto

- P1 · **Orçamento e turnos no Codex.** (a) Não mandar e mostrar "Só Claude Code" no campo; (b) limite do lado do app (tempo máximo + `turn/interrupt`). **Decidido:** (a) agora — não mandar orçamento nem turnos ao Codex e mostrar "Só Claude Code" no campo. O limite do app entra se a SPEC-101 precisar.
- P2 · **Onde guardar o `model/list`.** (a) `app_settings` com JSON e versão; (b) só em memória, lido a cada abertura. **Decidido:** (a) `app_settings` com JSON e versão, chave `codex.models.cache`. Abrir Configurações não depende do Codex responder.
- P3 · **Conferência de métodos.** (a) Rodar `generate-json-schema` a cada versão nova e guardar o resultado; (b) só comparar a versão. **Decidido:** (a) — a SPEC-093 mediu 0,05 s para o `generate-json-schema`; a conferência roda quando a versão muda e o resultado fica guardado por versão.
- P4 · **Etiqueta.** "Só Claude Code" em lilás (cor de recursos de IA) ou âmbar. **Decidido:** âmbar claro, mesma família dos avisos.
- P5 · **Capacidades por modelo ou por provedor.** **Decidido:** por provedor, com sobrescrita por modelo só para `images` e esforços.
- P6 · **Logo oficial ou glifo próprio nos pontos de identificação.** (a) Logos oficiais (Claude; OpenAI para o Codex) no seletor, no chip e no Comparar, e glifos só nos pontos pequenos; (b) glifos próprios em tudo, sem marca de terceiros. **Decidido:** (a) logos oficiais no seletor, no chip e no Comparar; glifos nos pontos pequenos. Volta para (b) no Codex se a OpenAI não autorizar.

## Design

### O que já existe

- `lib/core/providers/agent_provider.dart`: `AgentStartOptions` com flags Claude, `PromptMode`, `AgentRun`, `ManagedAgentRun`.
- `lib/core/codex/codex_provider.dart`: `validateOptions` (falha fechado), `model/list` paginado.
- `lib/core/providers/agent_registry.dart`: `codexEnabledProvider` e `ComingSoonProvider`.
- `lib/core/providers/provider_preferences.dart`: `providerModel`/`providerEffort` com as chaves `<provedor>.model.<tipo>`.
- `lib/core/providers/permission_policy.dart`: `codexPermissionPolicy` (com o `untrusted`).
- `lib/core/providers/provider_availability.dart`: `ProviderStatus.incompatible` já existe, sem regra de versão.
- `lib/core/claude/readonly_run.dart`: repassa `maxBudgetUsd` e `agent` a qualquer provedor.
- Configurações → Consumo: modelo e esforço por tipo, só Claude.

### Tokens novos (futuro `lib/ui/theme/tokens.dart`)

Ainda não entram no código; ficam registrados aqui para a tarefa T4.

```dart
// AppColors — identidade do provedor (R14). Nunca para estado.
static const providerClaude = Color(0xFFD97757); // argila
static const providerCodex = Color(0xFFE8E4DA);  // porcelana
// Texto e glifo sobre os dois: AppColors.onAmber (0xFF1A1206).
// Só para marca de glifo, borda e chip. Os logos têm cor fixa fora do tema
// (Claude 0xFFD97757, OpenAI 0xFFFFFFFF) e não usam estes tokens.
```

| Par | Contraste WCAG | Leitura |
|---|---|---|
| `#1A1206` sobre argila `#D97757` | 5,94:1 | AA para texto normal |
| `#1A1206` sobre porcelana `#E8E4DA` | 14,60:1 | AAA |
| argila sobre o painel `#14171D` | 5,75:1 | passa 3:1 de elemento gráfico (e 4,5:1) |
| porcelana sobre o painel `#14171D` | 14,14:1 | passa |
| logo argila sobre o fundo do chip de marca `#222732` | 4,79:1 | passa 3:1 de elemento gráfico |
| logo OpenAI branco `#FFFFFF` sobre o fundo do chip de marca | 14,95:1 | passa |
| argila × `running` `#F08A4B` | 1,26:1 · ΔE00 9,7 | perto demais como cor solta |
| argila × falhou `#F27A6E` | 1,16:1 · ΔE00 8,1 | perto demais como cor solta |

**Checagem com o `running`.** Como bolinha solta, a argila se confunde com o laranja de "Em execução" e com o vermelho de "Falhou". Lado a lado no mock 4, o chip com o logo e o nome contra a pílula translúcida de estado, e a marca com glifo contra o ponto pulsante, se distinguem bem no tamanho real. Por isso a argila fica `#D97757` e a regra 2 é obrigatória. Trocar o tom não resolveria: o que se afasta do `running` chega mais perto do vermelho. Exemplo: `#C96A55` vai a ΔE00 15 do `running`, mas fica a 9,4 do vermelho, e o contraste com o texto cai para 5,0:1.

### Uso de marca

- O símbolo do Claude é marca da Anthropic e o logo da OpenAI é marca da OpenAI. Aqui eles servem só para identificar qual provedor roda. Não indicam parceria, patrocínio nem endosso, e nunca são usados como ícone ou marca do Promptorium.
- Forma e cor intactas: sem distorcer, contornar, recolorir ou aplicar efeito. O Claude fica em argila (a cor da própria marca) e a OpenAI no branco oficial do pacote. O único ajuste é o enquadramento, que corta só a margem vazia do arquivo (ver abaixo). Sempre ao lado do nome, nunca maior que a marca do próprio app.
- **Antes da release:** conferir as regras em [anthropic.com/brand](https://www.anthropic.com/brand) e [openai.com/brand](https://openai.com/brand). A página da OpenAI pede o logo "exatamente como fornecido", sem modificação, e o uso dentro dos termos ou com permissão. Por isso o Blossom vai no branco oficial, sem recolorir. Se a OpenAI não permitir o uso, o Codex usa o glifo do livro em todos os pontos (um único ponto de troca, ver "Plano de implementação").

**Origem dos SVGs**

| Logo | Arquivo | Origem | Licença |
|---|---|---|---|
| Claude | `claude.svg` (viewBox 24×24, um `path`) | [Simple Icons 16.38.0](https://cdn.jsdelivr.net/npm/simple-icons@16.38.0/icons/claude.svg), slug `claude`, cor da marca `#D97757` nos metadados | O SVG do Simple Icons é CC0; a marca é da Anthropic |
| OpenAI (Codex) | `OAI_OpenAI-Blossom_White.svg` (viewBox 716×716, um `path`) | Pacote oficial [cdn.openai.com/brand/openai-logos.zip](https://cdn.openai.com/brand/openai-logos.zip), linkado em openai.com/brand. O Simple Icons 16.38.0 não tem mais o `openai.svg` (o CDN devolve 404) | Marca da OpenAI, uso sob os termos de openai.com/brand |

O Blossom ocupa cerca de metade da área do arquivo oficial. O enquadramento (viewBox `176 176 364 364`) corta só a margem vazia, sem mexer no desenho, para o logo ter 16 px de verdade dentro do chip. Em 14 px o Blossom ainda se reconhece, mas os traços internos já borram, por isso o mínimo é 14 px e o tamanho padrão é 16 px.

### Plano de implementação da identidade (T4)

1. **SVGs originais no repositório, sem alteração:** `assets/providers/claude.svg` e `assets/providers/openai-blossom.svg`, com `assets/providers/LICENSES.md` registrando a origem (Simple Icons 16.38.0, CC0, para o Claude; pacote oficial de marca da OpenAI para o Blossom) e que as marcas são da Anthropic e da OpenAI.
2. **Sem `flutter_svg`.** O app não tem essa dependência hoje e os dois logos são um `path` cada. `lib/ui/providers/provider_logos.dart` guarda o path copiado dos SVGs e pinta com um `CustomPainter`, como o `RobotPainter` (`lib/features/activities/widgets/robot_avatar.dart`). O enquadramento do Blossom (viewBox `176 176 364 364`) vira a escala do painter.
3. **Cores fixas fora do tema:** o logo do Claude é sempre `#D97757` e o da OpenAI sempre branco. Os tokens `providerClaude` / `providerCodex` (porcelana) do `tokens.dart` servem só para marca de glifo, borda e chip, nunca para o logo.
4. **Widgets:**
   - `ProviderLogo(provider, size: 16)`, mínimo 14;
   - `ProviderGlyph(provider, size: 14)`, com o arco e o livro, para os pontos pequenos;
   - `ProviderChip(provider)`, o chip neutro com logo e nome. As telas usam este.
5. **Um único ponto de troca:** se os termos da OpenAI não permitirem o uso, o `ProviderLogo` passa a desenhar o glifo do livro para o Codex, no app inteiro, sem mexer nas telas.
6. **Testes:** goldens em 14 e 16 px; o chip nunca mostra o logo sem o nome; a cor do logo não muda com o tema.
7. **Entrega:** T4 desta spec (0.23.0). As outras specs do épico adotam o `ProviderChip` à medida que forem implementadas.

### Arquivos tocados

| Arquivo | Mudança |
|---|---|
| `lib/core/providers/capabilities.dart` | Novo: `ProviderCapabilities`, `CapabilitySupport`, `providerFlows` |
| `lib/core/providers/run_intent.dart` | Novo: intenção, `ClaudeExtras`, `CodexExtras` |
| `lib/core/providers/agent_provider.dart` | `AgentStartOptions` = intenção + extras; `AgentProvider.capabilities` |
| `lib/core/providers/claude_code_provider.dart`, `lib/core/claude/claude_args.dart` | Traduzem intenção + `ClaudeExtras` |
| `lib/core/codex/codex_provider.dart`, `codex_command.dart` | Traduzem intenção + `CodexExtras`; `untrusted` conforme a SPEC-093 |
| `lib/core/providers/permission_policy.dart` | Acesso → política, por adaptador |
| `lib/core/providers/agent_registry.dart`, `provider_preferences.dart` | `providerFlows` no lugar de `codexEnabledProvider` |
| `lib/core/providers/provider_availability.dart`, `lib/core/codex/codex_cli.dart` | Versão mínima, última testada, métodos |
| `lib/core/claude/readonly_run.dart` | Monta só o suportado (R5) |
| `lib/features/settings/` (Consumo) | Abas por provedor, modelos do `model/list` |
| `lib/ui/widgets/only_provider_tag.dart` | Novo: etiqueta "Só Claude Code" |
| `lib/ui/theme/tokens.dart` | `providerClaude`, `providerCodex` (R14) |
| `lib/ui/providers/provider_logos.dart` | Novo: paths dos logos, `CustomPainter`, `ProviderLogo`, `ProviderGlyph`, `ProviderChip` (R14, R15) |
| `assets/providers/claude.svg`, `assets/providers/openai-blossom.svg`, `assets/providers/LICENSES.md` | SVGs originais sem alteração e origem/licença (R14a) |
| `test/ui/providers/` | Goldens 14 e 16 px, chip com nome, cor do logo fixa |
| Rodapé, Sessões, Prompt, timeline, replay, Quadro, robôs, Histórico, Custo | Usam o chip ou a marca no lugar do nome solto (R15) |
| Os 15 arquivos com `== 'claude'` (R13) | Consultam capacidades ou fluxos |

**Migração do banco:** não. As preferências ficam em `app_settings` (chaves existentes + `codex.models.cache`).

### Dependências

- Depende da SPEC-093 (capacidades comprovadas, métodos usados, `untrusted`).
- Destrava a SPEC-096 (fluxos e acesso), a SPEC-097 (capacidade `quota`) e a SPEC-100 (execuções estruturadas).
- Pode correr junto da SPEC-095; as duas tocam `agent_provider.dart` em partes diferentes (opções aqui, eventos lá).

## Tarefas

| Tarefa | Entrega | Requisitos |
|---|---|---|
| T1 · Capacidades e fluxos | `capabilities.dart`, valores por provedor, `providerFlows` | R1–R3 |
| T2 · Opções | Intenção + extras, adaptadores, acesso, `readonly_run` | R4–R7 |
| T3 · Modelo, versão e etiqueta | Aba Codex em Consumo, versão mínima, "Só Claude Code", sem troca silenciosa, fim das comparações | R8–R13 |
| T4 · Identidade do provedor | Plano de implementação da identidade (Design): SVGs originais e `LICENSES.md`, `provider_logos.dart` com `CustomPainter` (sem `flutter_svg`), tokens só para glifo, borda e chip, `ProviderLogo` / `ProviderGlyph` / `ProviderChip`, troca única para o glifo, goldens; telas de R15 usando o `ProviderChip` ou o glifo; termos de marca conferidos antes da release | R14, R15 |

## Critérios de aceite

- [x] Cada provedor expõe as capacidades de R1; o Codex usa a tabela da SPEC-093 e o `model/list`, e "não testada" conta como não suportada [R1, R2] verificar: `flutter test test/core/providers/capabilities_test.dart`.
- [x] Com o Codex, nenhum fluxo está liberado até a spec dele ligar; o interruptor global sumiu [R3] verificar: teste de `providerFlows`.
- [x] O review automático com o Codex selecionado não monta `maxBudgetUsd` nem `agent`, e o `validateOptions` não é mais o que barra [R4–R6] verificar: teste de `readonly_run` com capacidades do Codex.
- [x] Extras do Claude entregues ao Codex fazem um teste falhar [R6] verificar: teste do adaptador.
- [x] Perguntar e Planejar no Codex saem como `read-only` + `never`, Editar como `workspace-write` + `on-request`, YOLO só com worktree [R7] verificar: teste da política.
- [x] Sem sandbox na máquina, o Codex só aparece com worktree e acesso total, Perguntar/Planejar/Editar mostram "Sandbox do Codex indisponível" com o comando, e "Verificar de novo" refaz a detecção sem gastar cota [R7a] verificar: teste de `inspectProvider` com `configWarning` falso e teste de widget do rodapé.
- [x] A aba Codex de Consumo lista os modelos e esforços do `model/list` guardado, com a versão e a hora; um modelo salvo que sumiu aparece como indisponível [R8, R9] verificar: teste de widget da tela Consumo.
- [x] Codex 0.168 aparece como incompatível com a orientação; acima de 0.170 funciona com aviso; método ausente aparece nomeado [R10] verificar: teste de `inspectProvider` com versões falsas.
- [x] Controles sem suporte mostram "Só Claude Code" com o motivo, e nenhum fluxo troca de provedor sozinho [R11, R12] verificar: testes de widget da Nova sessão e do Executar spec.
- [x] `grep -rn "== 'claude'\|!= 'claude'" lib` só encontra adaptadores e registro [R13] verificar: o próprio grep.
- [ ] (parcial: robôs, Histórico e Custo sem glifo — ver "Implementação"; permissão da OpenAI concedida em 21/11) Nos pontos de identificação de R15, Claude e Codex aparecem com o logo oficial (sem alteração de forma) ao lado do nome; nos pontos pequenos, com o glifo; nenhuma cor de provedor aparece sem nome, logo ou glifo, nenhuma indica estado, e os estados (rodando, falhou, feita) mantêm as cores de hoje; os termos de marca da Anthropic e da OpenAI foram conferidos (ou o Codex caiu para o glifo) [R14, R15] verificar: testes de `ProviderChip` e `ProviderGlyph`, conferência das telas contra o mock `4-identidade-provedor.png` e registro da checagem de marca no PR.
- [x] Os SVGs originais estão em `assets/providers/` sem alteração, com `LICENSES.md`; o app não ganhou `flutter_svg`; o logo do Claude é sempre `#D97757` e o da OpenAI sempre branco, em qualquer tema; o chip nunca mostra o logo sem o nome; trocar o Codex para o glifo é uma mudança só no `ProviderLogo` [R14] verificar: goldens de `ProviderLogo` em 14 e 16 px, teste de tema (claro/escuro) com a mesma cor de logo, teste do `ProviderChip` sem nome falhando, `grep flutter_svg pubspec.yaml` vazio.

## Implementação (registro)

- **Pai e filhos:** T1 #354, T2 #356, T3 #358, T4 #360 (base `spec/094-capacidades-por-provedor`).
- **Decisões além da spec:**
  - O padrão salvo como Codex continua Codex mesmo com os fluxos desligados; cada fluxo diz por que não roda (R12). Antes ele virava Claude em silêncio.
  - Status `em implementação` no frontmatter é lido como aprovada (`spec_file.dart`), para a sincronização de issues não perder a spec.
  - Na aba Codex de Consumo os fluxos ainda fechados mostram "Só Claude Code por enquanto", mas o modelo e o esforço continuam editáveis: valem quando a spec do fluxo ligar.
  - A detecção do Codex faz um handshake sem turno (`initialize` + `model/list` + `command/exec ["true"]` em `readOnly`) e guarda o catálogo em `codex.models.cache`; "Atualizar lista" e "Verificar de novo" refazem a mesma detecção.
  - `Comparar` continua só com o Claude Code: a borda e o chip de cada lado usam a identidade dele.
- **Fora desta entrega (R15, pontos pequenos):** o glifo entrou no card do Quadro; robôs, Histórico e Custo por etapa adotam o `ProviderGlyph` quando as specs do épico tocarem neles (plano de identidade, item 7).
- **Marca:** a página de marca da OpenAI pede o logo "exatamente como fornecido" (cumprido) e **permissão** (`partnercomms@openai.com`) para o uso. **Permissão concedida em 21/11/2026**: o logo oficial fica (`codexUsesOfficialLogo = true`). Se um dia for retirada, trocar para `false` (o Codex passa ao glifo do livro). A página de marca da Anthropic (`anthropic.com/brand`) não respondeu (404) na conferência de 21/11.

## Telas

Canvas: [SPEC-094 · Capacidades e opções por provedor](https://claude.ai/artifact/HuGfpYA9AN3SBM1Hu1HhNZ)

| PNG | O que mostra | Requisitos |
|---|---|---|
| `docs/mockups/spec-094/0-antes.png` | Antes: o review automático com o Codex falha com "opções ainda sem equivalente validado", sem nada que a pessoa possa ajustar | — |
| `docs/mockups/spec-094/1-consumo-por-provedor.png` | Configurações → Consumo com as abas Claude Code e Codex: modelo e esforço por tipo vindos do `model/list`, versão e hora da leitura, e o quadro "O que o Codex faz neste app" | R1, R8, R9, R11 |
| `docs/mockups/spec-094/2-so-claude-code.png` | Nova sessão com o Codex: Agente e Orçamento desabilitados com "Só Claude Code", modelo do Codex, acesso com a política de cada modo | R5, R7, R11 |
| `docs/mockups/spec-094/3-versao-incompativel.png` | Menu do provedor no rodapé: Codex 0.168 incompatível com a orientação, e o aviso de versão mais nova que a testada; Executar spec com "Codex · Só Claude Code por enquanto" | R3, R10, R12 |
| `docs/mockups/spec-094/4-identidade-provedor.png` | Identidade do provedor: tokens argila e porcelana com os contrastes, logos oficiais (Claude em argila, OpenAI no branco oficial) e chips de marca em três tamanhos, glifos próprios para os pontos pequenos, onde aparece cada um (rodapé, sessão, seletor e Comparar com logo; card do Quadro, robô e Histórico com glifo) e a checagem lado a lado contra "Em execução" e "Falhou" | R14, R15 |

Todos os mocks mostram o provedor com o logo oficial ou o glifo de R14, conforme o ponto (R15).
