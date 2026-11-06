---
id: SPEC-040
status: rascunho
---

# Ditado por voz

## Objetivo

Escrever uma mensagem longa para o Claude toma tempo, e falar costuma ser mais rápido. Hoje todo campo do app exige digitação.

Esta spec coloca um botão de microfone nos campos que conversam com o Claude. A pessoa clica, fala, e o texto aparece no campo para revisar e enviar. A transcrição roda no computador, com o whisper.cpp incluído no pacote: não há Python, Ollama nem ambiente para montar. O único passo a mais é baixar o modelo de voz uma vez, no primeiro uso.

O Claude não faz a transcrição. A documentação da API lista só texto e imagem como entrada, e o ditado do Claude Code só existe no terminal interativo.

Task: [#87 · Audio para criação de Specs e Sessões](https://github.com/mayroncachina/promptorium/issues/87).

Mockup: [canvas do Claude Design](https://claude.ai/artifact/LA2UneaMELRuqtkwhuXpfs).

## Requisitos

- R1 · O botão de microfone deve aparecer nos campos que conversam com o Claude:
  - composer de Sessões, composer do Prompt (que também atende Refinar com IA) e conversa da etapa Visão;
  - respostas das perguntas, em `question_card` e `spec_questions_panel`;
  - tela de ideia da SPEC-039, quando ela existir;
  - fica à esquerda de **Enviar**, com a dica "Ditar por voz (Ctrl+Shift+M)";
  - é um componente só, ligado ao `TextEditingController` de cada campo;
  - busca, formulários e demais campos não recebem o botão.
- R2 · O primeiro uso deve baixar o modelo de voz, uma vez só:
  - sem modelo, o clique abre "Ativar o ditado por voz", com o tamanho e as ações **Agora não** e **Baixar modelo**;
  - o download mostra a barra, os MB baixados e a porcentagem, com **Cancelar** e **Continuar em segundo plano**;
  - o modelo vem de uma URL fixa, e a tela "Conferindo o arquivo" confere o `sha256` antes de ele ser usado, com **Cancelar** e **Continuar em segundo plano**;
  - a conferência tem limite de 30 segundos, e passar disso conta como falha no download;
  - `Esc` no download ou na conferência continua em segundo plano, e o foco inicial é definido uma vez, sem mudar a cada avanço do progresso;
  - o arquivo fica na pasta de dados do app, fora do repositório;
  - uma falha mostra "Não foi possível baixar o modelo", com **Tentar de novo**, e o download continua de onde parou;
  - ao terminar com o diálogo aberto, a tela mostra "Modelo pronto" até a pessoa fechar, com **Fechar** e **Falar agora**;
  - o app não começa a gravar sozinho, e em Configurações o fim oferece só **Fechar**.
- R3 · Gravar deve deixar claro que o microfone está ligado:
  - o clique no botão ou `Ctrl+Shift+M` começa a gravar no campo em foco;
  - a linha de ações mostra "Gravando", o tempo e o nível do áudio, com **Cancelar** e **Parar e transcrever**;
  - `Ctrl+Shift+M` para e transcreve, e `Esc` cancela, com atalhos no nível da tela, onde quer que esteja o foco;
  - só uma gravação existe por vez;
  - a gravação para sozinha em 5 minutos e segue para a transcrição;
  - sair da tela cancela a gravação e avisa "Gravação cancelada.";
  - a animação do nível respeita o movimento reduzido.
- R4 · Transcrever deve rodar no computador, sem enviar o áudio a nenhum serviço:
  - usa o `whisper-cli` incluído no pacote, com o idioma das Configurações;
  - a linha de ações mostra "Transcrevendo…", com **Cancelar** ao lado do texto, longe de onde estava **Parar e transcrever**, e o campo fica travado até terminar;
  - o arquivo de áudio é temporário e é apagado depois de virar texto ou de ser descartado;
  - nada de áudio é gravado no banco nem no repositório.
- R5 · O texto transcrito deve ir para o campo, nunca direto para o Claude:
  - entra na posição do cursor, sem apagar o que já estava escrito, com um espaço quando precisar;
  - a tela mostra "Texto inserido. Revise e envie.", até o próximo envio ou edição;
  - o foco volta ao campo, e o envio continua sendo uma ação da pessoa;
  - **Enviar** fica indisponível por 800 ms depois de inserir o texto, para um clique atrasado não enviar sem revisão.
- R6 · Falhas não devem perder o que foi falado:
  - sem microfone, o campo mostra "Nenhum microfone encontrado", com **Tentar de novo**;
  - uma gravação sem fala mostra "Nenhuma fala detectada";
  - uma falha ao transcrever mostra "Não foi possível transcrever", guarda o áudio e oferece **Tentar de novo** e **Descartar áudio**;
  - com áudio guardado, o microfone fica indisponível, para uma nova gravação não apagar o anterior;
  - **Descartar áudio** pede confirmação, com o foco em **Manter gravação**, e `Esc` mantém;
  - o texto que já estava no campo continua lá em todos os casos.
- R7 · As Configurações devem ter a seção "Ditado por voz":
  - modelo: "Melhor qualidade" (190 MB, padrão) ou "Mais rápido" (60 MB);
  - idioma: Português (padrão) ou detectar automaticamente;
  - microfone: padrão do sistema ou um dos encontrados;
  - mostra se o modelo está instalado, com **Remover modelo** ou **Baixar modelo**;
  - **Remover modelo** pede confirmação, com o foco em **Manter modelo**, e `Esc` mantém;
  - a seção diz que o áudio não sai da máquina.
- R8 · O pacote deve instalar tudo sem passo manual:
  - o `.deb` e o `.tar.gz` trazem o `whisper-cli` em `/opt/promptorium` e na pasta do app;
  - o `.deb` declara `libgomp1` e `alsa-utils` em `Depends`, resolvidos pelo `apt`;
  - o modelo não entra no pacote;
  - sem o `whisper-cli`, como em `flutter run`, o botão não aparece.
- R9 · O botão deve funcionar em 1100×700 e por teclado, com foco visível, sem truncar textos nem esconder **Enviar**.
- R10 · O download em segundo plano deve deixar o app livre:
  - **Continuar em segundo plano** fecha o diálogo, e a pessoa segue digitando e enviando;
  - o botão de microfone de todas as telas mostra o progresso e a porcentagem, e o clique reabre o diálogo;
  - as Configurações mostram "Baixando · 47%", com **Ver progresso**;
  - ao terminar, o app avisa "Modelo pronto. Clique no microfone para falar." sem abrir diálogo nem tirar o foco;
  - o aviso fica fora do composer, não cobre controles em 1100×700, tem **Fechar** e some sozinho em 6 segundos;
  - uma falha avisa sem abrir diálogo, com **Ver detalhes** e **Fechar**, fica até a pessoa agir e deixa o botão com sinal de erro;
  - **Ver detalhes** e o clique no botão abrem "Não foi possível baixar o modelo";
  - fechar o app pausa o download, e o próximo clique no microfone continua de onde parou.

## Fora do escopo

- Windows. O botão não aparece lá nesta spec.
- Transcrever enquanto a pessoa fala.
- Enviar a mensagem por comando de voz.
- Serviços de transcrição na nuvem.
- Ler as respostas do Claude em voz alta.
- Mudar o que o app envia ao Claude.

## Plano

<!-- Como implementar: componentes, arquivos e decisões. Use "Planejar". -->

## Critérios de aceite

- [ ] O botão aparece nos campos listados e não aparece nos demais [R1] verificar: flutter test test/features/dictation/dictation_button_test.dart
- [ ] Sem modelo, o clique pede o download, mostra a porcentagem e termina em Modelo pronto, sem gravar sozinho [R2] verificar: flutter test test/features/dictation/dictation_flow_test.dart
- [ ] Em segundo plano, o app segue usável, o botão mostra o progresso, e o aviso final não cobre controles e some sozinho [R10] verificar: flutter test test/features/dictation/dictation_flow_test.dart
- [ ] Uma falha em segundo plano marca o botão, e o clique oferece Tentar de novo [R10] verificar: flutter test test/features/dictation/dictation_flow_test.dart
- [ ] Um modelo com `sha256` errado é recusado e apagado [R2] verificar: flutter test test/features/dictation/model_store_test.dart
- [ ] Um download interrompido continua de onde parou [R2] verificar: flutter test test/features/dictation/model_store_test.dart
- [ ] `Ctrl+Shift+M` grava e transcreve, e `Esc` cancela com o foco em qualquer lugar [R3] verificar: flutter test test/features/dictation/dictation_flow_test.dart
- [ ] A gravação para sozinha em 5 minutos e transcreve [R3] verificar: flutter test test/features/dictation/dictation_flow_test.dart
- [ ] O áudio temporário é apagado depois da transcrição e do descarte [R4] verificar: flutter test test/features/dictation/dictation_flow_test.dart
- [ ] O texto entra no cursor, mantém o que havia e não é enviado sozinho [R5] verificar: flutter test test/features/dictation/dictation_flow_test.dart
- [ ] Sem microfone, sem fala e falha ao transcrever mantêm o texto do campo [R6] verificar: flutter test test/features/dictation/dictation_flow_test.dart
- [ ] Uma falha ao transcrever guarda o áudio, trava o microfone e só descarta com confirmação [R6] verificar: flutter test test/features/dictation/dictation_flow_test.dart
- [ ] Enviar não aceita clique nos 800 ms depois de inserir o texto [R5] verificar: flutter test test/features/dictation/dictation_flow_test.dart
- [ ] Uma conferência que passa de 30 segundos vira falha no download [R2] verificar: flutter test test/features/dictation/model_store_test.dart
- [ ] As Configurações trocam modelo, idioma e microfone, e removem o modelo só com confirmação [R7] verificar: flutter test test/features/settings
- [ ] O `.deb` traz o `whisper-cli` e declara `libgomp1` e `alsa-utils` [R8] verificar: scripts/package.sh
- [ ] Sem o `whisper-cli`, o botão não aparece [R8] verificar: flutter test test/features/dictation/dictation_button_test.dart
- [ ] O composer cabe em 1100×700 gravando e com erro [R9] verificar: flutter test test/features/dictation/dictation_button_test.dart

## Perguntas em aberto

- P1 · "Melhor qualidade" (`small-q5_1`) deve ser o modelo padrão?
  - Sugestão: sim, se um teste com voz real em português confirmar antes de implementar. A velocidade foi medida em inglês: 33 s de áudio em 14 s com o `small` e em 3,5 s com o `base`, no processador de um computador de 12 núcleos. A qualidade em português ainda não foi medida.
