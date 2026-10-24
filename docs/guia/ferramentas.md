# Ferramentas: agentes, skills e servidores MCP

A seção Ferramentas (Ctrl+9) tem três abas.

## Agentes

Os agentes do Claude Code, em dois grupos: **Globais** (`~/.claude/agents`) e **Projeto** (`.claude/agents`). Um agente do projeto com o mesmo nome "sobrescreve o global".

O editor mostra o `.md` e preserva campos desconhecidos e comentários: nome, "Quando usar este agente", modelo, esforço, escopo, ferramentas, `permissionMode`, máximo de turnos, orçamento, servidores MCP e o prompt de sistema. Modelo, esforço, turnos e orçamento valem nas sessões que usam o agente.

Ações: Salvar, Excluir, Mover entre escopos e **Testar em sessão**.

## Skills

**Instaladas**: skills do projeto (`.claude/skills/<nome>/SKILL.md`) e globais (`~/.claude/skills`). O editor cuida do `SKILL.md` (nome, descrição com contador, `allowed-tools`, instruções com prévia) e mostra os arquivos, a origem e o uso nas sessões. Ações: Salvar, Remover, Copiar para Global ou para o projeto, Testar em sessão e Atualizar, quando o catálogo tem versão nova. Skills de plugins e embutidas aparecem só para leitura.

**Catálogo**: repositórios GitHub com uma pasta por skill (padrão `mayroncachina/promptorium-skills`; outros podem ser adicionados), clonados em `~/.promptorium/catalogs/` e sincronizados com git. Instalar no projeto ou global registra a origem e o hash em `.promptorium-origin.json`, para avisar de versão nova e de mudança local.

**Nova skill**: escrever com o Claude (a partir de uma descrição ou de uma sessão), ou em branco.

## Servidores MCP

Agrupados por escopo: Globais (`~/.claude.json`), Projeto (`.mcp.json`), Local (por projeto) e Outros (da sessão ou do claude.ai). Mostra quando um servidor é sobrescrito por outro escopo.

- **Adicionar servidor** roda `claude mcp add`: nome, escopo, tipo (stdio ou URL), variáveis de ambiente ou headers. Valores secretos não são guardados nem exibidos.
- No detalhe: Testar conexão, Reiniciar e Remover (`claude mcp remove`).
- **Ferramentas expostas**: uma regra por ferramenta, Permitido (`--allowedTools`), Pedir aprovação ou Bloqueado (`--disallowedTools`).
- "Usado por" mostra quais sessões usam o servidor.

O status vem de `claude mcp list`, que roda em segundo plano logo depois da splash.

Para desligar plugins e servidores MCP só nas execuções disparadas pelo app, veja [Configurações › Execução de specs](configuracoes.md#execução-de-specs).
