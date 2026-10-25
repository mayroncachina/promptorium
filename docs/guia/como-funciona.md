# Como funciona

## O Claude Code por baixo

O Promptorium é uma interface para o **Claude Code CLI** (`claude`). Ele não chama a API: cada execução é um processo do CLI.

- **Sessões e etapas de spec**: `claude -p --input-format stream-json --output-format stream-json`. A timeline é montada a partir do stream-json, e os pedidos de permissão chegam e são respondidos pela própria stdin/stdout (`--permission-prompt-tool stdio`).
- **Planner, gerar design, verificar implementação, nova skill**: `claude -p` em modo somente leitura, com `--json-schema` quando o resultado precisa ser estruturado.
- **Terminal da sessão**: `claude --resume <id>` interativo, num PTY embutido.
- **Servidores MCP**: lidos e alterados só pelos comandos `claude mcp list/add/remove`. O app nunca escreve `~/.claude.json` nem `.mcp.json`.

Como o CLI é o seu, valem o seu login, o seu plano, os seus agentes (`~/.claude/agents`, `.claude/agents`), as suas skills e os seus servidores MCP. O rodapé mostra o uso do plano (janelas de 5 h e da semana) a partir dos eventos `rate_limit_event` do CLI.

Nas execuções que o próprio app dispara, dá para desligar plugins e servidores MCP (Configurações › Execução de specs). O app passa um `--settings` gerado por execução, em `~/.promptorium/run`, sem mexer na sua configuração do Claude Code.

O modo **"sem perguntar nada (perigoso)"** (`--dangerously-skip-permissions`) só é usado quando você o escolhe numa nova sessão ou execução; ele nunca vem pré-selecionado. O planner, as conversas do Prompt e as sondagens nunca usam.

## Provedores

O provedor padrão é o Claude Code. Agentes compatíveis com ACP (por exemplo, `gemini --experimental-acp`) podem ser cadastrados em Configurações › Provedores e escolhidos no rodapé, no Prompt e ao executar.

O **Codex está desligado** desde 22/10/2026: aparece como "em breve" no Prompt e não é oferecido nos outros lugares. Ver [specs/README.md](../specs/README.md) e o DT-56 em [debito-tecnico.md](../debito-tecnico.md).

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
