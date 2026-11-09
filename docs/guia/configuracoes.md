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

### Aparência

O app usa o tema **Vidro**: painéis translúcidos sobre um fundo escuro com duas luzes (âmbar no alto à esquerda e teal embaixo à direita) e uma grade de pontos. A barra lateral, o cabeçalho e o rodapé flutuam soltos das bordas, e só o que está vivo brilha: o item ativo da barra lateral, a spec rodando, o que precisa de você. Diálogos abrem sobre um desfoque da tela.

**Efeitos de vidro**: Ligados (padrão) ou Desligados. Desligados, o fundo fica liso e nada desfoca. O layout e as cores dos painéis continuam os mesmos. Desligue numa placa de vídeo fraca, num desktop sem aceleração gráfica ou se preferir o visual opaco (veja o requisito mínimo em [Instalação](instalacao.md#requisito-mínimo)).

Para desligar só numa execução, abra o app com `PROMPTORIUM_SEM_VIDRO=1`.

### Automações (hooks)

Hooks gerenciados pelo app nas sessões: "Bloquear comandos perigosos", "Formatar ao editar" e "Registrar fim da sessão". Precisam de `python3`.

### Provedores

Agentes ACP, um por linha, no formato `nome = comando` (por exemplo, `Gemini CLI = gemini --experimental-acp`). O Codex está desligado.

### Banco e backups

Lista os backups `.bak` criados antes de cada migração do banco, com "Restaurar" ou "Restaurar ao reabrir".

### Atualizações

Aviso diário de versão nova (pode ser desligado), "Verificar agora", "Abrir página" e Sobre. Quando a consulta falha, o cartão diz que não foi possível verificar, e uma versão já encontrada continua disponível.

## Workspace

**Configuração do projeto**: editor do `.promptorium/config.yml` ([detalhes](projeto.md#promptoriumconfigyml)), com o resumo do que o gate exige ("A etapa só passa se: ✓ testes · …").

### Git: marcar commits feitos por agentes

No grupo **Git** da Configuração do projeto (também na aba Configuração do Projeto), a caixa **Marcar commits feitos por agentes** grava `git: marcar-commits-de-agente: true` no `.promptorium/config.yml`. Vem desligada. O ⓘ ao lado mostra um commit de exemplo; ele abre com o ponteiro ou com o foco do teclado (Tab).

Ligada, todo commit feito por uma sessão do app (Claude, Codex, ACP e o Prompt) ganha uma linha no fim da mensagem:

```
SPEC-042 R2: seletor de sprint no cabeçalho

Promptorium-Agente: sonnet · SPEC-042 R2
```

- A linha diz o modelo e a origem: `SPEC-042 R2` numa etapa, `SPEC-043 conflito` ao resolver conflito, `SPEC-042 base` ao refazer a base, `sessão <nome>` numa sessão livre e `Prompt` numa conversa. Quando a sessão usa o modelo padrão do provedor, a linha mostra o provedor (`claude`, `codex`).
- O "Commitar o que sobrou" e o commit das pendências na Review saem como `Promptorium-Agente: app · …`, porque podem juntar edição sua com edição do agente.
- O autor continua sendo você, e o GitHub não mostra coautor.
- Nada é instalado no repositório nem em `.git/hooks`. O app passa às sessões um `core.hooksPath` para `~/.promptorium/git-hooks/` só pelo ambiente (`GIT_CONFIG_COUNT`). O `prepare-commit-msg` dali chama o do repositório e acrescenta a linha; os outros hooks repassam para os do repositório com os mesmos argumentos. Husky, lefthook e hooks próprios continuam rodando.
- Seus commits no terminal, no terminal do Código e no painel do Código não são marcados.
- Num amend ou rebase do agente, a linha é trocada, não duplicada. Commits antigos não mudam.
- Desligar vale para as próximas sessões. As sessões abertas terminam marcadas, e o estado mostra "Desliga nas próximas sessões".

A linha de estado mostra "Ligado desde 8 nov · 37 commits marcados" (contados na branch base), "Desligado" ou "Precisa do git 2.32 ou mais novo".
