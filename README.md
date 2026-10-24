# Promptorium

> O laboratório de onde operam os comandos dos seus agentes.

IDE desktop para Linux, feita em Flutter, para trabalhar com o **Claude Code CLI** orientado por specs: você planeja o projeto, escreve e aprova specs, executa cada uma num `git worktree` próprio, etapa por etapa, e revisa e faz o merge sem sair do app.

O Promptorium não fala com a API diretamente. Cada sessão é um processo `claude -p --input-format stream-json --output-format stream-json`, com as aprovações de ferramenta pela própria stdin/stdout (`--permission-prompt-tool stdio`). Por isso ele usa a sua assinatura ou conta do Claude Code, com os seus agentes, skills e servidores MCP.

## O que dá para fazer

- **Planejar um projeto**: visão, stack e roadmap de specs com o planner, a partir de uma pasta existente, de um modelo ou de um clone.
- **Escrever specs** em Markdown com requisitos, design, etapas e critérios de aceite; refinar com IA, gerar o design, prototipar as telas e aprovar.
- **Executar specs no Quadro**: uma sessão por etapa (ou várias etapas numa sessão), com gate de testes, lint e critérios antes de seguir; Autopilot com limite de paralelismo, orçamento diário e agendamento.
- **Acompanhar sessões ao vivo**: timeline, aprovações, perguntas do agente, terminal, diff, fork e lado a lado.
- **Revisar e fazer o merge**: diff por rodada e por etapa, comentários enviados ao agente, painel "Pronto para merge?", merge local guiado ou PR no GitHub.
- **Conversar no Prompt** sem worktree: perguntar, planejar e editar, e transformar a resposta em spec.
- **Gerenciar agentes, skills e servidores MCP** do Claude Code, globais e do projeto.

Detalhes de cada tela em [Guia de uso](docs/guia/README.md).

## Instalação rápida

Baixe o pacote da [última release](https://github.com/mayroncachina/promptorium/releases/latest) (Ubuntu/Debian 22.04 ou mais novo, x64):

```bash
sudo apt install ./promptorium_<versão>_amd64.deb
```

O Claude Code CLI é instalado à parte, com o seu usuário:

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

Outras formas (`.tar.gz` portátil, `scripts/install.sh`, Flatpak) e o atualizador do app: [Instalação](docs/guia/instalacao.md).

## Desenvolvimento

```bash
flutter pub get
flutter run -d linux
flutter analyze && flutter test
```

Requisitos do sistema, pacotes, testes de integração, build e release: [Desenvolvimento](docs/guia/desenvolvimento.md).

## Documentação

| | |
|---|---|
| [Guia de uso](docs/guia/README.md) | Como funciona e o que cada tela faz |
| [Índice da pasta `docs/`](docs/README.md) | Specs, planos, pesquisa, débito técnico e mockups |
| [CHANGELOG](CHANGELOG.md) | Notas das versões |
