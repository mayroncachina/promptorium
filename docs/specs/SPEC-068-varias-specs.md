---
id: SPEC-068
status: aprovada
issue: 194
---

# Várias specs de uma conversa, revisadas e guardadas na Bandeja

## Objetivo

Uma conversa do Prompt costuma terminar em mais de uma spec: "o carrinho lembra os itens, aceita cupom e paga com Pix" são três. Hoje o app só enxerga **a última** spec de uma resposta (`detectAnswerSpec`), e "Transformar em spec" gera uma só. As outras ficam presas na conversa e precisam ser copiadas à mão, com números e `depende-de` escolhidos no olho.

Esta spec faz o Prompt **criar várias specs de uma vez**: acha todas as specs da resposta (ou pede ao Claude que divida a conversa), mostra uma **lista de revisão** e troca os códigos provisórios pelos números reais, também dentro do `depende-de`. As specs criadas entram como rascunho na **Bandeja** do Quadro. Lá você aprova as que quer e escolhe quais vão para o Backlog.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/MSbtTP5X5KuTDei7BcwFBZ). Capturas em `docs/mockups/spec-068/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-antes.png` | Hoje: a resposta tem três specs, e o app só salva a última | — |
| `2-varias-specs.png` | A barra "3 specs nesta resposta", com os códigos provisórios | R1 |
| `3-revisar.png` | A lista de revisão: desmarcou uma, e quem depende dela avisa | R3, R4, R5 |
| `4-de-novo.png` | A mesma resposta de novo: as já criadas não se repetem | R6 |
| `5-dividir.png` | "Dividir em specs" no menu da conversa, com o Claude dividindo | R2 |
| `6-bandeja.png` | A Bandeja no Quadro: rascunhos e aprovadas, marcar e levar | R7, R8 |
| `7-levou.png` | As marcadas entram no Backlog, com "Desfazer" | R8 |

## Requisitos

- R1 · **Várias specs na resposta.** O app acha todas as specs de uma resposta do Prompt (blocos cercados ou trechos com frontmatter `id:`), não só a última.
  - Com duas ou mais, a barra da resposta passa a dizer "N specs nesta resposta", com os códigos provisórios e "viram SPEC-021 a SPEC-023 ao criar", e tem os botões "Revisar e criar" e "Copiar".
  - Com uma, tudo fica como hoje (SPEC-016, SPEC-063).
- R2 · **Dividir em specs.** O menu da conversa e o "Plano pronto" ganham "Dividir em specs", ao lado de "Transformar em spec".
  - O app pede ao Claude, sem ferramentas de escrita, que divida a conversa em specs no formato do `/spec`, com códigos provisórios (`SPEC-A`, `SPEC-B`…) e `depende-de` entre elas.
  - Enquanto o Claude trabalha, a lista aparece com linhas de espera e "Nada é criado antes de você revisar", e "Cancelar" encerra a sessão. O resultado abre a lista de revisão (R3).
  - Se o Claude devolver uma spec só, abre o "Salvar spec" de hoje. Se não devolver nenhuma, o aviso diz isso e oferece "Tentar de novo".
- R3 · **Lista de revisão, obrigatória com duas ou mais.**
  - Cada linha tem uma caixa (todas marcadas), o código provisório → o número real, o título (editável no lugar), quantos requisitos, as dependências e "Prévia".
  - O botão diz quantas serão criadas ("Criar 2 specs"). O rodapé diz que elas entram como rascunho na Bandeja.
  - Esc ou "Cancelar" fecha sem criar nada.
- R4 · **Números e dependências.**
  - Ao criar, cada código que não existe no projeto (provisório ou não) vira o próximo número livre, na ordem da lista, e todo `depende-de` que o citava é reescrito.
  - Um código que já existe (ex.: `SPEC-012`) fica como está.
  - A criação é exclusiva: se outro processo ocupou o número, o app usa o seguinte e ajusta as referências. A lista mostra os números previstos, e o aviso final mostra os criados.
- R5 · **Avisos de dependência na lista.**
  - Uma spec marcada que depende de outra desmarcada mostra "Depende da SPEC-A, que você desmarcou", com "Marcar a SPEC-A" e "Tirar a dependência".
  - Um ciclo entre as specs da lista ou um código que não existe em lugar nenhum também avisam na linha.
  - Com um ciclo, "Criar" fica desligado e diz por quê. Os outros avisos não impedem criar.
- R6 · **Sem duplicar.**
  - Cada spec criada guarda de onde veio: a conversa e o índice da spec na resposta.
  - Reabrir a lista da mesma resposta mostra essas specs desmarcadas e travadas, com "já criada · SPEC-021" e "Abrir".
  - Se a resposta for regenerada, uma spec com o mesmo título e o mesmo código provisório de uma já criada conta como já criada. Só as novas podem ser marcadas.
- R7 · **A Bandeja do Quadro.**
  - O texto "N em rascunho fora do quadro" vira o botão **Bandeja · N**, que abre um painel à esquerda do Backlog com as specs que ainda não estão no quadro: rascunhos e aprovadas que esperam.
  - O painel agrupa as specs pela conversa de origem ("Da conversa “Checkout novo da loja” · 3", e "Outras" para o resto).
  - Cada spec mostra o código, o título, o estado (Rascunho ou Aprovada) e as dependências. Clicar abre a spec.
  - O painel lembra se estava aberto, e o Quadro com a Bandeja aberta continua usável na largura mínima (1100 px).
- R8 · **Aprovar não põe no quadro; você escolhe.**
  - Uma spec aprovada fica na Bandeja, marcada "Aprovada", até você levá-la.
  - Na Bandeja, as aprovadas têm caixa de marcar. Um rascunho não tem ("aprove antes de levar"), e aprová-lo continua sendo na spec, depois do canvas validado.
  - "Levar N para o Backlog" põe as marcadas no Backlog, com o aviso "SPEC-021 e SPEC-022 no Backlog · Desfazer". "Executar tudo" (SPEC-064) só considera o que está no quadro.
  - O "Aprovar" da tela Specs avisa "Aprovada · na Bandeja do Quadro" e tem "Levar para o Backlog", para levar uma spec com um clique.
  - As specs que já estão no quadro hoje continuam lá.
- R9 · **Acessibilidade.**
  - A lista de revisão é um grupo de caixas operável pelo teclado: Espaço marca, Enter cria, e o foco vai para o primeiro aviso, se houver.
  - O botão da Bandeja anuncia "Bandeja, 4 specs fora do quadro" e se ela está aberta.
  - Os estados não dependem só da cor: "Rascunho" e "Aprovada" são texto.

## Fora do escopo

- Uma sessão gravar specs direto, com números reservados (o caminho C da discussão). As specs gravadas assim continuam entrando pelo vigia da pasta e caem na Bandeja.
- Aprovar várias specs de uma vez: aprovar continua sendo uma spec por vez, com o canvas validado.
- Editar o corpo da spec na lista; ali só se edita o título. O resto se edita na Prévia ou depois, em Specs.
- Mudar o formato do `/spec`, exceto para aceitar os códigos provisórios.

## Design

### O que já existe

- `lib/features/prompt/spec_from_answer.dart`: `detectAnswerSpec` (a última spec), `newSpecTextFromAnswer`, `saveAnswerSpecAsNew` (próximo código livre), `dependsOnAliasAdjust` (SPEC-063).
- `lib/features/prompt/widgets/answer_spec_bar.dart`: a barra "Spec detectada nesta resposta" e o "Salvar spec".
- `lib/features/prompt/conversation_actions.dart`: `conversationToSpec` ("Transformar em spec") e `lastAnswerSpec`.
- `lib/features/prompt/prompt_actions.dart`: `createSpecFromConversation` (criação exclusiva do arquivo).
- `lib/features/specs/spec_service.dart`: `sync`, que lê a pasta de specs e acusa códigos duplicados.
- `lib/features/board/board_screen.dart` e `board_rules.dart`: o texto "N em rascunho fora do quadro" e `isOnBoard` (hoje aprovada = no quadro).

### Componentes

- **`detectAnswerSpecs(text)`** (novo): todas as specs da resposta, em ordem. `detectAnswerSpec` passa a ser a última delas.
- **`SpecBatch`** (novo): os itens da resposta (código provisório, título, corpo, dependências) e **`planBatch(items, existing)`**, que dá o número previsto de cada item, reescreve os `depende-de` e lista os avisos (desmarcada, ciclo, código desconhecido). É uma função pura.
- **`createSpecBatch`**: grava os arquivos na ordem, com criação exclusiva e retentativa no número seguinte, e insere as specs como rascunho com a origem (`conversaId`, `respostaIdx`, `itemIdx`).
- **`AnswerSpecsBar`** e **`SpecBatchDialog`**: a barra "N specs nesta resposta" e a lista de revisão.
- **"Dividir em specs"**: uma conversa auxiliar em modo Perguntar, com o prompt do `/spec` para várias specs e códigos provisórios. A resposta passa por `detectAnswerSpecs` e abre `SpecBatchDialog`.
- **`Spec.inTray`** (coluna nova, migração): `isOnBoard` passa a ser `approved && !inTray` (ou fora do Backlog). Toda spec nova entra com `inTray = true`, e a migração deixa `false` nas que já existem.
- **`BoardTray`**: o painel da Bandeja, com a seleção das aprovadas e "Levar para o Backlog", que faz `inTray = false` e tem desfazer.

### Testes

- `detectAnswerSpecs` com uma, três e nenhuma spec; blocos cercados e frontmatter solto.
- `planBatch`: números em ordem, `depende-de` reescrito, código existente mantido, desmarcada avisa, ciclo bloqueia, número ocupado na hora de criar pula para o seguinte.
- Barra: "N specs" só com duas ou mais; com uma, a barra de hoje.
- Lista: marcar, desmarcar, editar título, "Marcar a SPEC-A" e "Tirar a dependência", e Esc sem criar.
- Já criadas: reabrir a lista mostra "já criada"; resposta regenerada só deixa marcar as novas.
- Dividir: cancelar encerra a sessão; uma spec abre o "Salvar spec"; nenhuma mostra o aviso.
- Bandeja: agrupa por conversa; aprovada marca e rascunho não; levar põe no Backlog e "Desfazer" devolve; aprovar em Specs não põe no quadro e oferece "Levar"; specs já no quadro continuam lá depois da migração.

## Decisões

- **A lista é obrigatória com duas ou mais specs.** Ela já vem toda marcada, então quem confia no resultado só clica em "Criar". O clique a mais evita ter que limpar specs repetidas ou indesejadas da Bandeja depois.
- **O Claude decide a ordem; o app confere.** O `depende-de` é o que o Claude escreveu. O app só renumera e avisa (desmarcada, ciclo, código desconhecido), sem inventar dependências.
- **Rascunho, sempre.** Aprovar em lote pularia a validação do canvas. Aprovar continua sendo uma spec por vez.
- **Aprovar não é pôr no quadro.** Hoje aprovada = Backlog. Com várias specs chegando de uma vez, isso encheria o Quadro e o "Executar tudo". A Bandeja separa as duas coisas: aprovar diz que a spec está pronta, e levar diz que é hora de executá-la.
- **A Bandeja substitui "N em rascunho fora do quadro".** O texto já dizia que havia specs fora do quadro, mas não deixava fazer nada com elas.
- **A origem fica no banco, não no arquivo.** A conversa é do app, não do repositório. O arquivo da spec continua limpo.

## Plano

1. **t1 · Várias specs na resposta** (R1, R3–R6, R9): `detectAnswerSpecs`, `planBatch`, `createSpecBatch`, a barra e a lista de revisão.
2. **t2 · Dividir em specs** (R2): a ação no menu da conversa e no "Plano pronto", a conversa auxiliar e o estado de espera. Depende da t1.
3. **t3 · Bandeja no Quadro** (R7, R8, R9): `Spec.inTray` e a migração, `isOnBoard`, o painel, levar e desfazer, e o aviso do "Aprovar".

## Critérios de aceite

- [x] Uma resposta com três specs oferece criar as três, com os números e o `depende-de` certos.
- [x] "Dividir em specs" transforma uma conversa em várias specs, revisadas antes de criar.
- [x] Pedir de novo não cria a mesma spec duas vezes.
- [x] As specs criadas ficam na Bandeja do Quadro; as aprovadas só vão para o Backlog quando você as leva.
