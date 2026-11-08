# Início e navegação

## Barra lateral

Em ordem, com Ctrl+1 a Ctrl+9 e Ctrl+0: **Início · Projeto · Specs · Quadro · Sessões · Review · Repositório · Código · Prompt · Ferramentas**. Ferramentas agrupa Agentes, Skills e Servidores MCP (Ctrl+0 abre a última aba usada). Configurações fica na engrenagem do pé da barra.

Cada item mostra em âmbar quantas pendências há naquela tela.

## Barra de título

- Logo e seletor **Workspace** (nome e branch).
- Campo "Buscar ou executar comando… Ctrl K", que abre a paleta.
- Botão de ação da tela: Novo projeto, Nova sessão, Nova conversa, Nova spec, Novo agente, Nova skill ou Adicionar servidor.
- Sino de **notificações**: histórico de avisos (sessão terminou, aprovação pendente, versão nova), com "Ir para" e "Limpar".

### Seletor de workspace

Lista os workspaces, com "Remover da lista (não apaga arquivos)", "Adicionar pasta…" (digitando o caminho ou com "Procurar…") e "Novo projeto…". Numa pasta que ainda não é git, oferece "Iniciar repositório", "Iniciar e conectar" a um remoto ou "Clonar".

## Início

A tela **Para você** reúne o que espera por você em todos os workspaces:

- Aprovações pendentes (Aprovar, Negar, Sempre permitir, Ver plano).
- Precisam de resposta (Responder na sessão).
- Aguardando review e PR com problema (Abrir review).
- Interrompidas (Ver sessão, Retomar).

Ao lado, a coluna **Agora** mostra o que está em execução, o estado do Autopilot (Pausar/Ligar, paralelismo, orçamento do dia, agendamento), os números de hoje (custo, sessões, merges) e os últimos avisos.

## Paleta de comandos (Ctrl+K)

Busca em Recentes, Pendentes, Ações, Telas, Specs e Sessões. Prefixos: `>` ações e pendências, `#` specs, `:` sessões.

Ações: aprovar, responder ou negar pendências; abrir review; retomar; ligar ou parar o Autopilot; nova sessão; nova spec; executar uma spec; ir para uma tela; atalhos; sobre.

## Aprovações em qualquer tela

Pedidos de permissão de sessões e conversas que não estão na tela aparecem como cartões sobrepostos ("+N pendentes"). Ctrl+Shift+A aprova e Ctrl+Shift+D nega a mais antiga; se for uma pergunta do agente, abre a pergunta. Também chega uma notificação nativa.

## Rodapé

- **Provedor**: "Claude Code CLI conectado" ou "não encontrado". O menu escolhe o provedor padrão do projeto ou global para as novas execuções.
- Sessões ativas e aguardando, subagentes rodando, servidores MCP conectados e com falha.
- **Uso do plano**: barras "Uso 5h" e "Semana", com o quanto resta e quando reinicia. Com outro provedor, "Consumo indisponível".

## Ícone na bandeja (Linux)

Clicar no ícone mostra ou esconde a janela (no GNOME, duplo clique; é preciso a extensão AppIndicator). O menu tem "Abrir" e "Sair". Esconder a janela não para sessões, terminais nem agendamentos; "Sair" e o botão de fechar encerram tudo. Sem bandeja disponível, o app segue normalmente, sem ícone.

O ícone também funciona como radar, em todos os workspaces, mesmo com a janela escondida:

| Selo | Estado | Quando |
|---|---|---|
| Losango âmbar com exclamação | Precisa de você | Um agente espera aprovação ou resposta |
| Quadrado vermelho com X | Problema | Um PR tem check falhando, conflito ou mudanças pedidas |
| Círculo azul | Trabalhando | Alguma sessão está no meio de um turno |
| Nenhum | Parado | Nenhum dos anteriores |

O tooltip resume os números e o menu lista o que espera por você e o que está rodando. Clicar em um item traz a janela e abre o lugar certo, mas nunca aprova nem decide nada. Review e sessão interrompida aparecem no menu sem mudar o ícone.

## Sobre e atualizações

**F1** abre o Sobre, em duas colunas. À esquerda ficam a animação de abertura, que toca uma vez e para, a versão instalada e os links Repositório e Histórico completo. À direita ficam o cartão de atualização e as novidades da última versão, só Funcionalidades e Correções, disponíveis offline. Com atualização disponível, as novidades são as da versão nova.

O app verifica uma vez por dia se há release nova no GitHub e avisa. O cartão mostra um estado por vez: em dia, verificando, disponível, baixando, instalando, falhou ou sem resposta. Quando a consulta falha, ele diz que não foi possível verificar e oferece "Tentar de novo".

"Atualizar agora" já começa, tudo dentro do cartão: baixa o pacote só de github.com por HTTPS, confere o `.sha256` quando a release o publica, instala (`.deb` com `pkexec` para a cópia em `/opt/promptorium`; `.tar.gz` por cima das demais) e reinicia. Com sessão em execução, o cartão pergunta antes, porque reiniciar encerra as sessões. "Cancelar" interrompe o download e descarta o que veio. Fechar o Sobre durante o download pede o cancelamento, e durante a instalação ele não fecha.

O aviso diário pode ser desligado em Configurações › Atualizações.

## Splash

Ao abrir, o app verifica o Claude Code CLI, abre o banco, carrega os workspaces, lista os worktrees e restaura as sessões: processos órfãos são encerrados e sessões que estavam vivas viram "interrompidas", prontas para Retomar. Se o CLI não for encontrado, a splash diz como instalá-lo.
