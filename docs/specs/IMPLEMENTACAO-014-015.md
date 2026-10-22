# Implementação das SPEC-014 e SPEC-015

## Hospedagem e CLI — SPEC-014

- Resolução do remote explícito, do upstream ou do único remote existente. Ambiguidade exige seleção no Review; a escolha fica vinculada à sessão.
- Detecção HTTPS, SSH e scp; GitHub/GitLab públicos, mapeamento por host de instâncias próprias, destinos locais/inválidos e provedores sem integração.
- Sondagem exclusiva da CLI correspondente, com autenticação no hostname efetivo, timeout e diagnósticos de instalação, login, rede e incompatibilidade. A autenticação do GitLab não bloqueia projetos GitHub.
- Faixa compacta do Review com hospedeiro, ferramenta, remote, orientação oficial de instalação/atualização, diagnóstico completo e nova verificação.
- Criação de PR explicita o repositório de destino. Requests salvos usam a URL original; operações de MR permanecem indisponíveis no DT-55. Push de acompanhamento recusa upstream cujo destino mudou em relação ao request salvo.

Código principal: `review_host.dart`, `review_service.dart`, `review_screen.dart`.
A integração operacional completa GitLab continua adiada, mesmo com `glab`
instalado e autenticado.

Fontes oficiais consultadas em 21/10/2026:

- [GitHub auth status](https://cli.github.com/manual/gh_auth_status) e [auth login](https://cli.github.com/manual/gh_auth_login).
- [GitLab auth status](https://docs.gitlab.com/cli/auth/status/) e [autenticação](https://docs.gitlab.com/cli/authentication/).
- Instalação: [GitHub CLI](https://github.com/cli/cli#installation) e [GitLab CLI](https://gitlab.com/gitlab-org/cli#installation). As páginas oficiais contêm orientações para os sistemas suportados; o app não instala nem autentica automaticamente.

## Descoberta e conclusão — SPEC-015

- Varredura ao ativar o workspace, inclusive abrindo diretamente o Quadro, e observação de pastas criadas depois e mudanças da configuração.
- Sincronização serializada, identidade por projeto/código, atualização de caminho sem duplicação, diagnóstico de YAML/identidade/status inválidos, códigos duplicados e arquivos ausentes.
- Importação de `status: concluida` reconcilia status e etapa para Concluído. Não cria sessões, etapas executadas, commits ou métricas fictícias.
- Operações em andamento e worktrees são preservados; divergências são apresentadas. Reabertura é explícita, sem reiniciar execução.
- Barra compartilhada em Specs e Quadro mostra a pasta configurada, permite sincronizar, selecionar uma ou várias specs para verificação, cancelar, consultar relatório/origem e reabrir.
- Verificação usa o provedor efetivo em modo somente leitura e saída estruturada. Claude recebe o orçamento interno de US$ 1 por análise; os demais provedores não recebem um controle monetário Claude incompatível. A interface informa o uso de IA antes de iniciar e não faz fallback de provedor.
- Cada requisito e critério de aceite precisa de uma classificação; citações de evidência são conferidas nos arquivos e critérios manuais exigem registro manual. Resultados parciais/inconclusivos não concluem a spec. O agente não implementa nem executa comandos durante a análise; critérios que exigem execução precisam de evidência registrada de resultado.
- SHA-256 da spec e impressão do HEAD/conteúdo rastreado e não ignorado invalidam alterações ocorridas durante a análise. Cancelamento, mudança de projeto ou início de execução impedem a publicação do resultado.
- Relatório persistido em `.promptorium/verifications/SPEC-NNN.json`, com a revisão do repositório (HEAD) e a impressão das alterações locais, também exibidas em “Relatório / origem”; a interface apresenta requisitos, classificações e evidências em texto. Conclusão declarada no documento é distinguida de conclusão verificada pelo agente.
- A gravação preserva o corpo da spec, usa arquivo temporário/rename e confere o conteúdo esperado antes de publicar a conclusão. A próxima sincronização recupera o banco se a atualização for interrompida depois de salvar o arquivo.

Código principal: `spec_service.dart`, `workspace_watcher.dart`, `spec_verifier.dart`,
`spec_sync_bar.dart`, `specs_repo.dart`. O executor de análise compartilhado ganhou
cancelamento, incluindo encerramento do processo e propagação do erro sem uma
exceção assíncrona solta. O diff rola a caixa de comentário para manter o botão de
envio acessível quando a altura disponível é pequena.

## Validação

Testes novos cobrem detecção e isolamento de CLI, escolha do remote, destino de
requests salvos, descoberta inicial e por watcher real, renomeação, pasta
configurada, conflitos de importação, preservação de operações, conclusão,
reabertura, evidências, invalidação, cancelamento e interação com a barra de
verificação. O executor Codex é exercitado com App Server simulado, incluindo
sandbox somente leitura, schema estruturado e cancelamento.

Resultado final em 21/10/2026:

- `flutter analyze --no-pub`: sem problemas.
- `flutter test --concurrency=2`: 555 testes passaram, 4 ignorados (2min16s).
- `git diff --check`: sem problemas.

A validação manual no desktop com contas reais GitHub/GitLab e provedores reais
continua pendente; os testes não criam PR/MR nem fazem merge em serviços externos.
As specs permanecem em revisão por esse motivo.
