---
id: SPEC-014
status: em-revisao
---

# Identificação da hospedagem e orientação de CLI

## Objetivo

Identificar se o projeto usa GitHub, GitLab ou outro hospedeiro a partir do remote e encaminhar cada ação para a ferramenta correspondente. Quando a ferramenta necessária não estiver instalada, orientar a instalação; quando faltar autenticação, orientar o login no host correto.

O Promptorium está hospedado no GitHub (`git@github.com:mayroncachina/promptorium.git`): suas ações de PR usam `gh`. A autenticação do `glab` não deve bloquear esse projeto. Projetos GitLab usam `glab`, conforme as capacidades efetivamente implementadas. Esta spec cobre detecção, seleção e diagnóstico; a integração completa de MR da SPEC-013 fica no DT-55.

## Requisitos

- R1 · Resolver o remote usado pela ação e identificar seu host em URLs HTTPS, SSH e scp (`git@host:grupo/projeto.git`). `github.com` identifica GitHub e `gitlab.com` identifica GitLab. Instâncias próprias usam o mapeamento explícito de `hospedagem` no config.yml. Hosts não reconhecidos ficam como outro/desconhecido, preservando o domínio para diagnóstico; ausência de remote, caminho local e URL inválida têm estados próprios.
- R2 · Encaminhar ações remotas pelo adaptador do hospedeiro identificado: GitHub → `gh`, GitLab → `glab`. Consultar instalação e autenticação apenas da ferramenta necessária, usando o host efetivo. Nunca tentar outra CLI como fallback. Operações locais de git continuam disponíveis independentemente dessas CLIs.
- R3 · Se a CLI estiver ausente, mostrar o nome, a ação afetada e a sugestão de instalação, com acesso à documentação oficial. Oferecer “Verificar novamente”. Se estiver instalada mas sem autenticação válida, orientar o login no host efetivo. Distinguir executável ausente, login inválido, incompatibilidade, falha de rede e integração ainda não implementada.
- R4 · Exibir o provedor e o estado junto às ações do Review, com PR para GitHub e MR para GitLab. Outro provedor sem adaptador deve informar que a integração não está disponível, sem sugerir `gh` ou `glab`. Não oferecer uma ação como disponível apenas porque a CLI está instalada e autenticada.
- R5 · Recalcular o diagnóstico ao trocar de projeto, mudar o remote/configuração ou pedir nova verificação. Descartar respostas atrasadas de outro projeto ou remote. Em projetos com vários remotes, usar o remote efetivo da ação e exibi-lo; se não houver seleção inequívoca, pedir a escolha entre os remotes existentes antes de executar.
- R6 · Requests já vinculados a uma sessão mantêm o hospedeiro e o destino originais, mesmo após mudança de remote. Usar a URL salva para identificar o destino quando possível; preservar o comportamento GitHub das sessões antigas. Uma incompatibilidade entre destino e configuração deve ter diagnóstico explícito, sem encaminhar a operação ao provedor errado.

## Design

### Resolução compartilhada

Reaproveitar `remoteHost`, `detectReviewHost`, `HostAvailability` e `ReviewService.prAvailability`. Centralizar a resolução em um resultado com remote, URL, hostname, tipo de hospedeiro, CLI e capacidades disponíveis. A mesma resolução deve alimentar o botão do Review e as ações remotas; não criar uma heurística diferente por tela.

Respeitar o remote explicitamente escolhido pela ação. Na ausência dele, usar o remote do upstream da branch; sem upstream, usar o único remote existente. Havendo mais de um candidato sem escolha inequívoca, apresentar seleção. Não presumir que `origin` é o destino de push em projetos com fork.

O mapeamento `hospedagem: {host: git.exemplo.com, tipo: gitlab}` já existe parcialmente. Estender a validação para os tipos suportados, incluindo GitHub em instância própria, e preservar as demais chaves ao salvar. O mapeamento só vale para o hostname configurado; não classificar qualquer host desconhecido como GitLab.

### Diagnóstico e encaminhamento

Sequência: resolver destino → identificar hospedeiro → verificar CLI correspondente → verificar autenticação no host → verificar capacidade da ação. Usar execução com argumentos separados, timeout e erros tipados; não interpretar saída de autenticação como prova de suporte a operações ainda não implementadas. Não registrar tokens.

Uma ação sem implementação deve apresentar essa limitação mesmo se também houver um problema de instalação/login. No estado atual, GitLab pode ser identificado e diagnosticado, mas criação, acompanhamento e merge de MR continuam indisponíveis até o DT-55 ser resolvido. O contrato deve permitir conectar essas operações ao `GitlabHost` posteriormente.

A seleção e o diagnóstico não iniciam instalação nem login automaticamente. “Como instalar” abre a documentação oficial correspondente ao sistema operacional; “Verificar novamente” repete a sondagem. Comandos de login apresentados precisam ter sintaxe validada para a versão instalada e apontar ao host efetivo.

Exemplos de mensagens:

| Situação | Mensagem esperada |
| --- | --- |
| Projeto GitHub sem `gh` | “GitHub CLI (gh) não encontrado. Instale para usar as ações de PR.” |
| Projeto GitLab sem `glab` | “GitLab CLI (glab) não encontrado.”, com orientação de instalação e indicação das capacidades ainda pendentes |
| Login inválido | “Autenticação inválida em <host>.”, com orientação para a CLI correspondente |
| Outro provedor sem adaptador | “Integração com <host> ainda não disponível.” |
| Sem remote | “Configure um remote para usar ações de PR/MR.” |

As orientações de instalação e login devem apontar para documentação oficial validada durante a implementação. Falhas de rede não devem sugerir reinstalação nem afirmar que o token é inválido sem evidência.

### Requests existentes

Resolver o destino da URL salva do PR/MR antes de considerar o remote atual. A persistência completa de `sessions.pr_host` e a migração correspondente continuam no DT-55. Esta spec não anuncia suporte operacional a MR e não modifica requests no servidor para diagnosticar o projeto.

## Critérios de aceite

- [ ] [R1] URLs HTTPS, SSH e scp identificam GitHub/GitLab; instâncias próprias só recebem o tipo configurado quando o domínio coincide. Cobrir URL inválida, caminho local, sem remote e host desconhecido.
- [ ] [R2] Projeto GitHub com `glab` ausente ou inválido continua usando apenas `gh`; projeto GitLab não executa `gh`. Runner falso registra os comandos para comprovar o isolamento.
- [ ] [R3] CLI ausente oferece orientação oficial de instalação e nova verificação; login inválido orienta o host correto; falha de rede e incompatibilidade têm diagnósticos distintos.
- [ ] [R4] PR/MR e provedor aparecem corretamente. CLI autenticada sem operação implementada mantém a ação indisponível com motivo; outro host não recebe sugestão de ferramenta incompatível.
- [ ] [R5] Upstream e remote explícito são respeitados; múltiplos remotes ambíguos exigem seleção. Trocar de projeto ou remote invalida o diagnóstico anterior e respostas atrasadas são descartadas.
- [ ] [R6] Sessão com PR salvo no GitHub continua consultando o GitHub após o remote passar a GitLab; destinos incompatíveis não executam a CLI errada.
- [ ] [R1–R6] Testes de resolução/diagnóstico, widgets do Review e regressão GitHub passam; `flutter analyze` não introduz problemas. Validar manualmente as orientações com CLI ausente e autenticação inválida.

## Relação com a SPEC-013

Esta spec assume a detecção e o diagnóstico originalmente descritos em R1–R2 da SPEC-013 e acrescenta orientação de instalação, outros hospedeiros e isolamento por projeto. O restante da integração GitLab está adiado no [DT-55](../debito-tecnico.md#dt-55--integracao-completa-do-review-no-gitlab). A SPEC-013 permanece como referência técnica, sem requisito de concluí-la para entregar esta spec.


## Implementação

Implementação disponível no código local em 21/10/2026. Detalhes e validações em
[IMPLEMENTACAO-014-015.md](IMPLEMENTACAO-014-015.md). O status permanece em revisão
até a conferência manual de aceite; requisitos parcialmente implementados em
outras specs não são marcados como concluídos por esta entrega.
