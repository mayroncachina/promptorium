# Configurações

Abertas pela engrenagem do pé da barra lateral. Têm busca ("Buscar configuração…") e marcam as seções diferentes do padrão.

## App

### Modelo e consumo

Modelo (Sonnet, Opus, Haiku, Fable ou padrão do CLI) e esforço padrão para Sessões, Conversas do Prompt e Planner, e a compactação automática (`--autocompact`) para todas as execuções. Uma nova sessão começa com esses valores; um agente com `model` ou `effort` próprios usa os dele.

### Execução de specs

- **Etapas numa sessão só**: specs com até N requisitos rodam numa sessão (padrão 3).
- **Continuar na mesma sessão até**: limite de contexto para emendar a próxima etapa na mesma sessão (padrão 60 mil tokens, ou desligado).
- **Plugins nas execuções do app** e **Servidores MCP nas execuções do app**: desligue os que as etapas não precisam, para gastar menos tokens. As listas vêm do último `system/init` do CLI. Vale só para as execuções do Promptorium.

### Sessões

**Suspender por inatividade**: 5, 15 (padrão), 30 ou 60 minutos, ou nunca.

### Automações (hooks)

Hooks gerenciados pelo app nas sessões: "Bloquear comandos perigosos", "Formatar ao editar" e "Registrar fim da sessão". Precisam de `python3`.

### Provedores

Agentes ACP, um por linha, no formato `nome = comando` (por exemplo, `Gemini CLI = gemini --experimental-acp`). O Codex está desligado.

### Banco e backups

Lista os backups `.bak` criados antes de cada migração do banco, com "Restaurar" ou "Restaurar ao reabrir".

### Atualizações

Aviso diário de versão nova (pode ser desligado), "Verificar agora", "Abrir página" e Sobre.

## Workspace

**Configuração do projeto**: editor do `.promptorium/config.yml` ([detalhes](projeto.md#promptoriumconfigyml)), com o resumo do que o gate exige ("A etapa só passa se: ✓ testes · …").
