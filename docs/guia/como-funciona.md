# Como funciona

## O Claude Code por baixo

O Promptorium é uma interface para o **Claude Code CLI** (`claude`) e, se você quiser, também para o **Codex CLI** ([Provedores](#provedores)). Ele não chama a API: cada execução é um processo do CLI. Esta seção descreve o Claude Code.

- **Sessões e etapas de spec**: `claude -p --input-format stream-json --output-format stream-json`. A timeline é montada a partir do stream-json, e os pedidos de permissão chegam e são respondidos pela própria stdin/stdout (`--permission-prompt-tool stdio`).
- **Planner, Planejar, verificar implementação, nova skill**: `claude -p` em modo somente leitura, com `--json-schema` quando o resultado precisa ser estruturado.
- **Terminal da sessão**: `claude --resume <id>` interativo, num PTY embutido.
- **Servidores MCP**: lidos e alterados só pelos comandos `claude mcp list/add/remove`. O app nunca escreve `~/.claude.json` nem `.mcp.json`.

Como o CLI é o seu, valem o seu login, o seu plano, os seus agentes (`~/.claude/agents`, `.claude/agents`), as suas skills e os seus servidores MCP. O rodapé mostra o uso do plano (janelas de 5 h e da semana) a partir dos eventos `rate_limit_event` do CLI.

Nas execuções que o próprio app dispara, dá para desligar plugins e servidores MCP (Configurações › Execução de specs). O app passa um `--settings` gerado por execução, em `~/.promptorium/run`, sem mexer na sua configuração do Claude Code.

O modo **"sem perguntar nada (perigoso)"** (`--dangerously-skip-permissions`) só é usado quando você o escolhe numa nova sessão ou execução; ele nunca vem pré-selecionado. O planner, as conversas do Prompt e as sondagens nunca usam.

## Provedores

O provedor padrão é o Claude Code. Agentes compatíveis com ACP (por exemplo, `gemini --experimental-acp`) podem ser cadastrados em Configurações › Provedores e escolhidos no rodapé e no Prompt.

O **Codex** é opcional: instale o Codex CLI 0.170 ou mais novo e rode `codex login` no terminal. O app conversa com o `codex app-server`, não faz login e não lê as suas credenciais. O provedor nunca troca sozinho: se o escolhido não puder rodar, a tela diz o motivo.

| Fluxo | Codex |
|---|---|
| Prompt e Sessões | sim |
| Planner e assistentes (Projeto, Nova spec, Dividir, Perguntas, Design, Verificar, Nova skill, Decidir na etapa) | sim |
| Executar spec, gate, Executar tudo e Autopilot | sim, no Manual e no Automático |
| Revisor automático | sim |
| Comparar (um provedor por lado) e Executar em dobro (A/B, um provedor por tentativa) | sim |
| Automático do Orquestrador | sim: provedor por etapa nas regras, com reserva e desvio por cota |
| Protótipo de telas | só Claude Code |

O que muda com o Codex:

- **Instruções e skills**: o `CLAUDE.md` e as skills do Claude valem também no Codex, só naquela execução. Nada é copiado para o repositório.
- **Agentes**: o app traduz os de `.claude/agents` (instruções, modelo, esforço e sandbox) e mostra o que foi ignorado. Subagentes da spec não rodam: a sessão principal faz o trabalho deles.
- **MCP**: valem os servidores do próprio Codex. O servidor do Promptorium entra só com as ferramentas de leitura.
- **Custo**: o Codex informa só tokens, e o app mostra "custo indisponível". Não há limite em US$ nem de turnos.
- **Hooks do app**: entram como hooks da sessão, e o app confere se o Codex os aceitou ([Automações](configuracoes.md#automações-hooks)).
- **Sandbox**: quando o sandbox do Codex não sobe na máquina (comum no Ubuntu 24.04), ele só roda em worktree, com acesso total, e o app commita no fim do turno. O Prompt mostra "Sandbox do Codex indisponível".

No **Automático**, as regras do Orquestrador (Configurações › Orquestrador) dizem o provedor de cada tipo de etapa, com uma reserva no outro. Com o desvio por cota ligado, quando a cota de um provedor acaba no meio da etapa, ela volta ao início e segue no outro; depois da renovação, as etapas seguintes voltam ao plano. O painel da spec mostra o selo do provedor de cada etapa, e o Histórico separa uso e tokens por provedor e modelo.

Em **Continuar no Codex** / **Continuar no Claude**, no cabeçalho da sessão, o trabalho passa para uma sessão nova do outro provedor, no mesmo worktree.

## O fluxo principal

```
Projeto ──► Specs ──► Quadro ──► Sessões ──► Review ──► merge
 planner    escrever   executar    etapa a     diff, PR,
            aprovar    por etapa   etapa       merge local
```

1. **Projeto**: o planner propõe stack e um roadmap de specs ([Projeto](projeto.md)).
2. **Specs**: cada spec é um Markdown com requisitos (as etapas), design e critérios de aceite; você refina e aprova ([Specs](specs.md)).
3. **Quadro**: specs aprovadas viram cartões. Executar cria o worktree da spec e abre uma sessão por etapa, com um gate entre elas ([Quadro](quadro.md)).
4. **Sessões**: você acompanha, aprova ferramentas e responde ao agente ([Sessões](sessoes.md)).
5. **Review**: diff da spec inteira, comentários ao agente, painel "Pronto para merge?", PR ou merge local ([Review](review.md)).

## Worktrees

Cada spec executada ganha um `git worktree` próprio em `~/.promptorium/worktrees/<repo>-<slug>`, na branch `pr/<slug>`. As etapas commitam ali (`SPEC-003 R2: …`), e a raiz do repositório fica livre para você. Sessões avulsas podem ter worktree isolado ou rodar na raiz; as conversas do Prompt sempre rodam na raiz.

Checkpoints de etapa ficam em refs `refs/promptorium/SPEC-x/Rn-inicio`, que permitem voltar ao início de uma etapa.

## Onde ficam os dados

| O quê | Onde |
|---|---|
| Banco local (workspaces, specs, sessões, conversas, preferências) | `~/.local/share/promptorium/promptorium.sqlite`, com backup `.bak-v<N>` antes de cada migração |
| Worktrees das specs e sessões | `~/.promptorium/worktrees/` |
| Settings e hooks temporários de cada execução | `~/.promptorium/run/` |
| Catálogos de skills clonados | `~/.promptorium/catalogs/` |
| Configuração do projeto (versionada) | `<repo>/.promptorium/config.yml` |
| Memória do projeto | `<repo>/.promptorium/memoria.md` |
| Planos salvos do modo Planejar | `<repo>/.promptorium/planos/` |
| Anexos de fora do workspace | `<repo>/.promptorium/attachments/<data>/` |
| Specs | a pasta configurada (padrão `specs/`; neste repositório, `docs/specs/`) |

Nenhum segredo (tokens e variáveis de servidores MCP) é gravado no banco.
