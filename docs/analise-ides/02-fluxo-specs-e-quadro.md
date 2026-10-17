# 02 — Fluxo de specs e Quadro

Hoje: planner → `specs/SPEC-NNN.md` (frontmatter + Requisitos R1…Rn + Critérios) → Aprovar → cartão
no Quadro → Executar (worktree `pr/spec-nnn`) → uma sessão por etapa (prompt curto, `ETAPA CONCLUÍDA: Rn`)
→ Review → merge. Autopilot executa specs desbloqueadas em ondas.

O ciclo está certo. As melhorias abaixo são para ele **não quebrar em silêncio** e para a spec ser
mais útil ao agente.

## 2.1 Gate de verificação por etapa (prioridade máxima)

**Problema.** A etapa vira `done` quando a última resposta contém `ETAPA CONCLUÍDA: Rn`. O agente pode
escrever a linha com testes quebrados, sem commit, ou com commit no lugar errado. O prompt "rode os
testes" é um pedido, não uma garantia. Conductor (checks por workspace), Codex/Copilot (CI) e o hook
`Stop` do Claude Code tratam isso como regra, não como pedido.

**Proposta.** `SpecRunner.onResult` só aceita o marcador se um *checklist* passar, rodado pelo app no
worktree, sem gastar tokens:

1. há pelo menos um commit novo desde o início da etapa com prefixo `SPEC-003 R2:` (já pedido no prompt);
2. a árvore está limpa (`git status --porcelain` vazio) — ou o app oferece "commitar o que sobrou";
3. `testes:` do `config.yml` roda com código 0 (com timeout e saída guardada);
4. opcional: `lint:` / `build:` do `config.yml` (mesma mecânica).

Se algo falhar: a etapa fica `needs_input` com o motivo ("testes falharam: 3 erros") e o app **reenvia
automaticamente** a saída para a mesma sessão uma vez ("os testes falharam, corrija e repita o
marcador") antes de pedir o humano. Limite de tentativas configurável (padrão 1). Isso cobre a maior
parte dos casos de "etapa marcada e quebrada" por centavos.

**Na interface.** O cartão mostra o resultado do gate (✓ testes · ✓ commit · ✗ lint) e a etapa tem
um botão "Ver saída da verificação".

## 2.2 Worktree pronto para rodar

**Problema.** `addWorktree` cria a pasta e a branch e nada mais. Projetos reais precisam de
`node_modules`/`.dart_tool`, `.env`, banco local, porta livre. Hoje o agente gasta turnos descobrindo
isso (ou falha). Conductor resolve com *files to copy* + *setup script* + `CONDUCTOR_PORT`.

**Proposta** no `.promptorium/config.yml`:

```yaml
worktree:
  copiar: [.env, .env.local, config/local.yml]   # arquivos ignorados pelo git
  preparar: |                                     # roda uma vez ao criar o worktree
    flutter pub get
  porta-base: 4000                                # PROMPTORIUM_PORT = base + índice do worktree
```

O app exporta `PROMPTORIUM_PORT`, `PROMPTORIUM_WORKTREE`, `PROMPTORIUM_SPEC` no ambiente da sessão e
do terminal embutido. O "preparar" roda com saída visível no cartão ("Preparando worktree…") e
bloqueia a sessão até terminar. Reutilizar no Fork (resolve parte do DT-18).

## 2.3 Spec em três camadas (inspirado no Kiro, sem copiar o formato)

**Problema.** A spec tem Objetivo, Requisitos e Critérios. Falta o **design** (decisões técnicas,
arquivos a tocar, contratos) e falta ligar cada critério a uma verificação. O agente de cada etapa
recebe a spec inteira e redecide o design a cada sessão (contexto limpo = redescoberta).

**Proposta.** Manter um arquivo só (não três como o Kiro; três arquivos pioram o Review e o git), mas
com seções com papel definido e um passo de planner a mais:

```markdown
## Objetivo
## Requisitos            ← R1…Rn em EARS: "Quando <evento>, o sistema deve <resposta>"
## Design                ← gerado pelo planner depois de aprovar os requisitos; arquivos, contratos,
                            decisões; editável; congelado ao iniciar a execução
## Etapas                ← R1 → arquivos/design envolvidos → como verificar (comando ou critério)
## Critérios de aceite   ← cada um marcado [R2] e, quando possível, com o comando que o prova
```

Mudanças de fluxo:

- Na tela Specs, **"Gerar design"** (planner somente leitura, lê o repositório) entre Refinar e
  Aprovar. Aprovar exige Design preenchido (ou "sem design" explícito para specs triviais).
- O prompt da etapa passa a incluir só o trecho do Design e os critérios ligados a `Rn` — contexto
  menor e mais preciso do que a spec inteira.
- Critérios com comando (`verificar: flutter test test/x_test.dart`) entram no gate do 2.1.

## 2.4 Checkpoint por etapa e "voltar"

**Problema.** DT-06 em aberto. Se a etapa R3 estragar o que R2 fez, a única saída é reverter à mão.

**Proposta** barata: no início de cada etapa o app grava uma `ref` (`refs/promptorium/SPEC-003/R3-inicio`)
apontando para `HEAD` do worktree e um `git stash create` do que estiver sujo. Botões no cartão:
"Voltar ao início da etapa" (reset `--hard` para a ref + reaplicar stash, com confirmação) e
"Refazer etapa" (voltar + abrir sessão nova com a saída da sessão anterior anexada como "o que deu
errado"). Checkpoint dentro da etapa (antes de cada Edit) fica para depois, via hook `PreToolUse`
(ver 03).

## 2.5 Spec grande demais / replanejar no meio

**Problema.** O planner limita a 6 requisitos, mas a execução pode revelar que R4 na verdade são
três etapas, ou que a spec depende de algo não previsto. Hoje a edição trava ao iniciar.

**Proposta.** Permitir que a **sessão da etapa** proponha mudanças na spec por um marcador
estruturado (`SPEC SUGESTÃO: dividir R4 em R4a/R4b`, `SPEC SUGESTÃO: depende-de SPEC-007`), que o app
transforma num aviso no cartão com "Aplicar" (edita o arquivo, recria etapas pendentes) / "Ignorar".
A spec continua travada para edição livre; só muda por sugestão aceita. Isso é o que o Copilot Plan
faz ao "perguntar antes de escrever", mas no meio da execução.

## 2.6 Quadro: o que falta para operar 10+ specs

Do DT-33 e da comparação com Agents Window (Cursor) e Threads Sidebar (Zed):

- **Linha ao vivo no cartão** com a ferramenta atual (`Bash · flutter test`, `Edit · lib/x.dart`) e o
  tempo na etapa — hoje é preciso abrir a sessão.
- **Grafo de dependências** (visualização simples: colunas por onda, setas) com a próxima onda
  destacada quando o Autopilot está ligado.
- **Autopilot persistente** (hoje some ao reabrir o app) com limite de specs em paralelo (padrão 3)
  e **orçamento por onda/dia** (`--max-budget-usd` somado) — Cursor e Codex deixam o custo
  escapar; o rodapé de uso do plano já dá a base.
- **Falha de sessão volta a etapa para `needs_input`** e não deixa o cartão em "Em execução"
  (DT-33).
- Ordem na coluna persistida; arrastar entre colunas respeitando regras (Backlog → Em execução só
  via Executar).

## 2.7 Sequência de menus proposta

Hoje: Sessões · Prompt · Specs · Quadro · Review · Código · Agentes · Skills · MCP · Projeto.
A ordem reflete a ordem em que as telas foram construídas, não o fluxo de trabalho. Proposta,
seguindo o ciclo de vida:

| Ctrl+ | Tela | Por quê nessa posição |
|---|---|---|
| 1 | **Projeto** | começa aqui: visão, stack, roadmap, config do projeto |
| 2 | **Specs** | o que vai ser feito |
| 3 | **Quadro** | o que está sendo feito (vira a tela inicial quando há specs em execução) |
| 4 | **Sessões** | o detalhe de cada execução |
| 5 | **Review** | o que terminou e espera decisão |
| 6 | **Código** | olhar/editar o resultado |
| 7 | **Prompt** | conversa livre, fora do ciclo |
| 8 | **Agentes · Skills · MCP** agrupados em "Ferramentas" (sub-abas) | configuração, usada com menos frequência |
| — | **Configurações** (engrenagem) | consumo, atalhos, tema, CLI |

Com isso a barra lateral conta a história: Projeto → Specs → Quadro → Sessões → Review → Código.
`Ctrl+K` (paleta, DT-12) resolve o "ir para" de quem já decorou a ordem antiga.
