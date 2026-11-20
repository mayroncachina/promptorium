---
id: SPEC-104
status: rascunho
versao: 0.24.0
tipo: melhoria
epico: 332
issue: 339
depende-de: [SPEC-093, SPEC-094, SPEC-096]
---

# Instruções (AGENTS.md) e skills

## Problema

O Codex lê `AGENTS.md`. O Claude Code lê `CLAUDE.md`. Todo projeto criado pelo Promptorium tem só o `CLAUDE.md` (`project_service.dart`, `create_step.dart`), e as skills ficam em `~/.claude/skills` e `<repo>/.claude/skills` (`skill_repository.dart`). Quando a pessoa conversa com o Codex no Prompt ou abre uma sessão Codex (SPEC-096), ele trabalha sem as regras do projeto e sem as skills que ela escreveu. E nada na tela avisa isso.

Exemplo: no projeto `vitrine`, o `CLAUDE.md` diz "rode `flutter analyze` antes de commitar; textos em português; nunca use `print`". Numa sessão Codex, o agente commita sem analisar e deixa um `print` de depuração. A skill `gerar-release`, que fica em `.claude/skills`, também não aparece para ele. Do lado de fora parece que "o Codex é pior". Na prática, ele só não recebeu as mesmas instruções.

A decisão 6 do épico #332 já definiu o caminho: **o `CLAUDE.md` é a fonte**. Se o Codex não conseguir lê-lo, o app gera um `AGENTS.md` na criação do projeto. Esta spec põe essa decisão em prática e faz o mesmo pelas skills, sem cópias que se desencontram.

## Requisitos

### Instruções do projeto

- R1 · **O `CLAUDE.md` chega ao Codex sem tocar no repositório.** Em toda execução Codex do app (Prompt, Sessões e os fluxos que a SPEC-094 liberar), o adaptador inclui o `CLAUDE.md` entre os arquivos de instrução do projeto por um override da execução (`-c project_doc_fallback_filenames=["CLAUDE.md"]` ou o mecanismo que a SPEC-093 comprovar). Nada é gravado em `~/.codex`, e nenhum arquivo do repositório é criado ou alterado. Se o repositório já tem `AGENTS.md`, vale a ordem do próprio Codex, e o app avisa (R4).
- R2 · **Prova pelo agente, não pela configuração.** O app guarda, por execução, os `instructionSources` que o App Server devolve no `thread/start`/`thread/resume` (os caminhos dos arquivos de instrução carregados). A interface diz "carregado pelo Codex" só com essa prova. Enquanto não houver uma execução, diz "previsto". Isso segue o princípio da SPEC-087 R4: uma configuração disponível não prova que foi carregada.
- R3 · **Plano B, quando o Codex não lê o `CLAUDE.md`.** Se a SPEC-093 mostrar que o override não funciona (ou se uma versão futura o remover, o que a conferência da R2 detecta), a capacidade `instructionsFallback` fica falsa e:
  - na criação de projeto, o passo Criar ganha a opção marcada "Gravar também o AGENTS.md (o Codex não lê o CLAUDE.md)";
  - em projetos existentes, a aba Instruções (R5) oferece "Gerar AGENTS.md".

  O `AGENTS.md` gerado é uma cópia do `CLAUDE.md` com um cabeçalho curto ("Gerado do CLAUDE.md pelo Promptorium. Edite o CLAUDE.md.") e um marcador com o hash da origem. O app nunca o atualiza sozinho.
- R4 · **Duas fontes, sem sobrescrever nada.** O app nunca sobrescreve um `AGENTS.md` que não gerou (sem o marcador). Quando os dois arquivos existem:
  - gerado e em dia: "AGENTS.md gerado · em dia";
  - gerado e o `CLAUDE.md` mudou depois: "AGENTS.md desatualizado", com a ação "Atualizar AGENTS.md", que mostra o diff antes de gravar;
  - escrito pela pessoa: "Duas fontes: o Codex lê o AGENTS.md, o Claude lê o CLAUDE.md", sem ação de escrita. Fica só "Abrir os dois".
- R5 · **Aba Instruções em Ferramentas.** Uma aba nova, "Instruções", ao lado de Agentes, Skills e MCP. Ela mostra:
  - o arquivo-fonte (`CLAUDE.md`), com tamanho, data e "Abrir no editor";
  - uma linha por provedor, com o que ele lê e o estado (R2): "Claude Code · CLAUDE.md · carregado" e "Codex · CLAUDE.md via override · carregado na sessão de 14:32";
  - os arquivos de instrução de subpastas (`CLAUDE.md`/`AGENTS.md` aninhados), só para leitura;
  - os estados da R4 com as ações.

  Com o Codex indisponível ou incompatível (SPEC-094), a linha dele diz o motivo e não some.

### Skills

- R6 · **As skills do Claude servem ao Codex sem cópia.** Nas execuções Codex, o app aponta o Codex para `<repo>/.claude/skills` e `~/.claude/skills` por `skills/extraRoots/set`, na sessão do App Server que a execução abriu, se a SPEC-093 confirmar que o formato `SKILL.md` delas é aceito. Não há cópia, não há link simbólico e nada é gravado em `~/.codex`.
- R7 · **Quem enxerga cada skill.** Na aba Skills → Instaladas, cada skill ganha selos por provedor ("Claude", "Codex"), que vêm do `skills/list` do Codex (escopo, caminho, `enabled`). O painel da skill mostra "No Codex: via pasta extra · ativa" ou o motivo de não estar ("nome inválido para o Codex", "desligada no Codex", "Codex indisponível").
- R8 · **Skills do próprio Codex, só leitura.** As skills que o `skills/list` devolve com escopo `user`, `system` ou `admin`, ou de plugin, aparecem num grupo novo, "Do Codex", só para leitura. É o mesmo tratamento que "Plugins e embutidas" já tem para o Claude.
- R9 · **Erros e campos sem efeito.** Os `errors` do `skills/list` (caminho e mensagem) aparecem na skill correspondente, com "Abrir SKILL.md". Campos do frontmatter que o Codex não usa (como `allowed-tools`) ganham a marca "ignorado no Codex" no editor, sem bloquear a gravação.
- R10 · **Plano B das skills.** Se o `extraRoots` não funcionar, as skills do Claude ficam com a etiqueta "Só Claude Code" quando o provedor da execução é o Codex. Cada skill de projeto passa a ter a ação opcional "Disponibilizar no Codex", que cria, com confirmação, um link simbólico na pasta de skills de repositório que a SPEC-093 identificar. Nunca em pasta global.
- R11 · **Catálogo e criação seguem iguais.** Instalar do catálogo e "Nova skill" continuam gravando em `.claude/skills`. Pela R6, a skill nova aparece no Codex na próxima execução, e o selo da R7 confirma isso depois do próximo `skills/list`.
- R12 · **Leve e sem custo.** `skills/list` e a leitura dos `instructionSources` usam o App Server já aberto pela execução, ou uma consulta curta sem turno. Nenhuma das duas manda prompt ao modelo. A aba Skills não abre um App Server por tecla: a consulta é feita ao abrir a aba e com "Atualizar" (`forceReload`).

## Fora do escopo

- Agentes `.claude/agents` no Codex: SPEC-106.
- MCP por provedor: SPEC-105.
- Comandos de barra (`/comando`) do Claude no Codex.
- Ligar ou desligar skills do Codex (`skills/config/write` grava na configuração global do Codex).
- Sincronizar o `AGENTS.md` sozinho a cada mudança do `CLAUDE.md`, ou mesclar dois arquivos escritos à mão.
- Importar a configuração do Claude para o Codex com `externalAgentConfig/import`. Ela grava no `~/.codex`, o que contraria o princípio de não tocar nos arquivos globais.
- Memória (`CLAUDE.md` do usuário, auto memory, ai-memory): SPEC-098.

## Decisões em aberto

- P1 · **Onde fica a tela de instruções.** (a) Aba "Instruções" em Ferramentas; (b) seção em Configurações → Provedores; (c) só um aviso no rodapé. **Recomendação: (a).** É onde estão Agentes, Skills e MCP, que são os outros recursos do projeto que o agente lê.
- P2 · **Formato do `AGENTS.md` gerado (plano B).** (a) Cópia integral com cabeçalho e marcador; (b) arquivo curto que manda o agente ler o `CLAUDE.md`. **Recomendação: (a).** O Codex não tem `@import`, e uma instrução do tipo "leia o outro arquivo" depende de o modelo obedecer.
- P3 · **Subpastas.** (a) Listar os arquivos aninhados só para leitura; (b) também gerar `AGENTS.md` por subpasta no plano B. **Recomendação: (a).** No plano B, gerar só o da raiz e mostrar os aninhados com "Só Claude Code".
- P4 · **Plano B das skills.** (a) Só a etiqueta "Só Claude Code"; (b) etiqueta mais "Disponibilizar no Codex" por skill (link simbólico no repositório, com confirmação); (c) copiar a pasta. **Recomendação: (b).** A cópia (c) desencontra com o tempo. O link aparece no `git status`, então a confirmação diz isso.
- P5 · **Ordem quando os dois arquivos existem e o `AGENTS.md` é da pessoa.** (a) Respeitar a ordem do Codex e só avisar; (b) forçar o `CLAUDE.md` primeiro. **Recomendação: (a).** O arquivo foi escrito para o Codex, e o app não decide por cima dele.

## Design

### Arquivos tocados

- `lib/core/codex/codex_provider.dart`: override de instruções no `app-server` (R1), leitura dos `instructionSources` (R2), `skills/extraRoots/set` antes do primeiro turno (R6).
- `lib/core/providers/capabilities.dart` (SPEC-094): capacidades `instructionsFallback` e `skillsExtraRoots`.
- `lib/core/providers/workspace_assets.dart` (novo, previsto no plano técnico): estado das instruções por provedor, hash do `CLAUDE.md`, marcador do `AGENTS.md` gerado e inventário de skills do Codex.
- `lib/features/instructions/instructions_view.dart` (novo): aba Instruções (R4, R5).
- `lib/ui/shell/navigation.dart`, `lib/ui/shell/tools_tabs.dart`: a quarta aba de Ferramentas.
- `lib/features/project/project_service.dart`, `lib/features/project/widgets/create_step.dart`: opção do `AGENTS.md` na criação (R3).
- `lib/features/skills/skill_repository.dart`, `skills_state.dart`, `skills_screen.dart`, `widgets/installed_view.dart`: selos, grupo "Do Codex", erros e campos ignorados (R7–R10).
- `lib/features/context/context_sources.dart`: os `instructionSources` viram fonte "carregamento informado pelo agente" no painel Contexto. O comportamento completo no Codex fica com a SPEC-107.

### Migração

Não há migração de banco. Os `instructionSources` vão num evento do app (`promptorium_run`, JSON versionado da SPEC-087) junto dos eventos da sessão ou da conversa. O hash do `CLAUDE.md` de origem fica no marcador dentro do próprio `AGENTS.md` gerado.

### Dependências

- **SPEC-093 · Sondagem do Codex 0.170**: confirma se o `project_doc_fallback_filenames` funciona por `-c`, a ordem com `AGENTS.md`, se o `skills/extraRoots/set` aceita `.claude/skills` e qual é a pasta de skills de repositório. É o que decide entre o caminho principal e os planos B (R3, R10).
- **SPEC-094 · Capacidades e opções por provedor**: as capacidades `instructionsFallback` e `skillsExtraRoots`, e o estado "incompatível".
- **SPEC-096 · Codex no Prompt e nas Sessões**: as execuções Codex em que R1, R2 e R6 se aplicam.
- Relacionadas: SPEC-106 (agentes) e SPEC-107 (fontes do contexto no Codex).

## Tarefas

- T1 · Adaptador: override de instruções, captura dos `instructionSources`, `extraRoots`, capacidades. Testes com o `fake_codex` e *fixtures* da SPEC-093.
- T2 · `workspace_assets`: estado das instruções por provedor, hash e marcador, detecção de "duas fontes". Testes de unidade.
- T3 · Aba Instruções e o passo Criar do projeto (plano B, atrás da capacidade). Testes de widget.
- T4 · Skills: selos, grupo "Do Codex", erros, campos ignorados e "Disponibilizar no Codex" (plano B). Testes de widget e um teste manual com o app isolado.

## Critérios de aceite

- [ ] Uma sessão Codex num projeto só com `CLAUDE.md` carrega o arquivo, sem criar nem alterar arquivos no repositório ou em `~/.codex` [R1] verificar: `instructionSources` gravado no evento da execução e `git status` limpo, num repositório temporário.
- [ ] "Carregado pelo Codex" só aparece com `instructionSources` da execução; sem execução, a tela diz "previsto" [R2] verificar: teste de widget da aba Instruções com e sem o evento.
- [ ] Com a capacidade `instructionsFallback` falsa, Criar oferece o `AGENTS.md` marcado, e o arquivo gerado tem o cabeçalho e o marcador [R3] verificar: teste do `project_service` e teste de widget do passo Criar.
- [ ] Um `AGENTS.md` sem o marcador nunca é sobrescrito; o gerado e desatualizado mostra o diff antes de gravar [R4] verificar: testes de unidade do `workspace_assets` com os três casos.
- [ ] A aba Instruções mostra a fonte, uma linha por provedor e os arquivos aninhados; com o Codex indisponível, a linha diz o motivo [R5] verificar: teste de widget.
- [ ] Uma skill de `.claude/skills` aparece no `skills/list` da execução Codex sem cópia nem link [R6] verificar: teste com o `fake_codex` e sondagem real registrada.
- [ ] Selos por provedor, grupo "Do Codex", erros do `skills/list` e "ignorado no Codex" aparecem nas skills certas [R7–R9] verificar: teste de widget com resposta gravada do `skills/list`.
- [ ] Sem `extraRoots`, a skill fica "Só Claude Code", e "Disponibilizar no Codex" só cria o link depois da confirmação, e só no repositório [R10] verificar: teste de unidade e teste manual.
- [ ] A aba Skills não abre um App Server por tecla nem manda prompt ao modelo [R12] verificar: contagem de processos e de pedidos no `fake_codex`.

## Telas

Mockup: [canvas do Claude Design](https://claude.ai/artifact/P8aC6uzvr8FT7gsvMHp6GU). PNGs em `docs/mockups/spec-104/`, com dados de exemplo (projeto `vitrine`, Codex 0.170).

| PNG | O que mostra | Requisitos |
|---|---|---|
| `1-instrucoes.png` | Ferramentas → Instruções: `CLAUDE.md` como fonte, uma linha por provedor com o estado e a prova (`instructionSources` da sessão de 14:32), os arquivos aninhados e o caso de "duas fontes", em que o repositório tem um `AGENTS.md` escrito pela pessoa | R1, R2, R4, R5 |
| `2-skills.png` | Skills → Instaladas com selos Claude/Codex, o grupo "Do Codex", uma skill com erro do `skills/list` e o painel "No Codex: via pasta extra · `allowed-tools` ignorado no Codex" | R6–R9, R11 |
| `3-plano-b.png` | Plano B: o passo Criar do projeto com "Gravar também o AGENTS.md" e a aba Instruções com "AGENTS.md desatualizado" e o diff antes de gravar | R3, R4 |
