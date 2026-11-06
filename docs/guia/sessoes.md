# Sessões

Cada sessão é um processo do Claude Code. As etapas do Quadro abrem sessões; você também pode criar uma avulsa com **Nova sessão** (Ctrl+N).

## Nova sessão

Título, prompt inicial, agente (`--agent`), provedor, modelo, esforço e modo de permissão:

- **perguntar** (padrão), **aceitar edições**, **planejar**;
- **sem perguntar nada (perigoso)**: `--dangerously-skip-permissions`, com aviso. A escolha é lembrada, mas nunca vem de um agente.

"Criar worktree isolado (branch `pr/<slug>`)" separa a sessão da raiz do repositório.

## Lista

Filtros Todas, Aguardando e Concluídas. "Uma / Lado a lado" (Ctrl+\\) mostra duas sessões juntas; "Abrir ao lado (painel B)" escolhe a segunda.

## A sessão

Abas **Timeline · Terminal · Diff · Log bruto**.

- **Timeline**: texto em streaming, cartões das ferramentas (Read, Edit, Bash…) e subagentes aninhados.
- **Terminal**: `claude --resume <id>` interativo no worktree, com "Parar e abrir no terminal", "Encerrar" e "Reabrir".
- **Diff**: `git diff HEAD` do worktree.
- **Log bruto**: o stream-json.

Cabeçalho: Abrir terminal, Fork (`--resume --fork-session` num worktree novo), Abrir preview :porta (a porta em `PROMPTORIUM_PORT`), Retomar e Parar.

Painel lateral:

- **Aprovações pendentes**: Aprovar, Negar ou "Sempre permitir" nesta sessão, no projeto ou em todos os projetos.
- **Detalhes**: spec, duração, tokens, custo e session id.
- **Arquivos alterados**, com "Abrir no Review".

## Perguntas do agente

Quando o agente usa AskUserQuestion, a pergunta aparece como cartão com as opções (escolha única ou múltipla) e "Outro", para texto livre. "Enviar respostas" devolve tudo ao agente.

## Composer

Ctrl+Enter envia. `@` insere um arquivo, `/` um prompt salvo, "Anexar spec" insere a spec. Dá para trocar o modo de permissão no meio da sessão. Se o processo não estiver vivo, a mensagem retoma a sessão.

## Suspender e retomar

Uma sessão parada há algum tempo (padrão 15 min; Configurações › Sessões) é suspensa para liberar recursos. "Retomar" continua de onde parou. Sessões vivas quando o app foi fechado aparecem como "interrompidas" ao reabrir.

## Ditado por voz

O botão de microfone fica à esquerda de **Enviar** no composer de Sessões e do Prompt, na etapa Visão, em Nova spec e nas respostas de perguntas. Só existe nos pacotes `.deb` e `.tar.gz` para Linux.

No primeiro uso, o app pede para baixar o modelo de voz, uma vez só. O download pode continuar em segundo plano, e o botão mostra a porcentagem.

Clique no microfone ou use `Ctrl+Shift+M` para gravar. O mesmo atalho para e transcreve, e `Esc` cancela. A gravação para sozinha em 5 minutos. O texto entra na posição do cursor e nunca é enviado sozinho: revise e clique em **Enviar**.

Se a transcrição falhar, o áudio fica guardado até você usar **Tentar de novo** ou **Descartar áudio**. Enquanto isso, o microfone fica indisponível.

Se o app disser "Nenhuma fala detectada", confira o volume do microfone no sistema. Um volume baixo faz a voz não ser reconhecida.
