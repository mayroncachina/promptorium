---
id: SPEC-057
status: aprovada
depende-de: SPEC-039
issue: 144
---

# Importar arquivo no "Conte a ideia"

## Objetivo

Muitas ideias já chegam escritas: um briefing em PDF, uma proposta em Markdown, anotações em TXT. Hoje, para usar esse texto no "Conte a ideia", a pessoa precisa abrir o arquivo, copiar e colar. Com PDF isso costuma quebrar linhas e trazer lixo de cabeçalho.

Esta spec deixa **importar um arquivo PDF, Markdown ou TXT** e carregar o texto dele no campo. Isso vale nos dois lugares que têm o campo:
- a **Nova spec** (tela Specs);
- o passo **Visão** do Projeto.

O texto entra no campo e pode ser editado antes de planejar. Nada é enviado sozinho.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/3QhJ9SKKTfdTZMDj7YwgAM). Capturas em `docs/mockups/spec-057/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-importar.png` | Botão "Importar arquivo" no rodapé do campo | R1 |
| `2-arrastando.png` | O campo como área de soltar | R2 |
| `3-importado.png` | Texto carregado, cartão de origem e progresso do PDF | R3–R5 |
| `4-ja-tem-texto.png` | Escolha entre adicionar ao fim e substituir | R6 |
| `5-problemas.png` | Mensagens de erro e aviso | R7 |
| `6-projeto.png` | O mesmo componente no Projeto | R8 |

## Requisitos

- R1 · O campo "Conte a ideia" ganha um rodapé com:
  - o botão **Importar arquivo** (Ctrl+O com o campo em foco), que abre o seletor filtrado em `.pdf`, `.md`, `.markdown` e `.txt`;
  - a dica "PDF, Markdown ou TXT · ou arraste para o campo";
  - o contador "<n> / 40.000" quando o campo tem texto.

  A frase de apoio do título ganha "Já tem um documento? Importe o texto dele."
- R2 · Arrastar um arquivo sobre o campo transforma o campo inteiro numa área tracejada âmbar, com "Solte para carregar o texto". Soltar importa. Mais de um arquivo: importa o primeiro e avisa.
- R3 · Leitura:
  - **TXT e Markdown:** lidos como UTF-8; o Markdown entra como está;
  - **PDF:** convertido em texto com `pdftotext -layout` (poppler-utils), página a página. Depois, as linhas quebradas no meio da frase são juntadas e os cabeçalhos e rodapés repetidos em todas as páginas são tirados;
  - em todos os casos, o texto final tem as quebras normalizadas (`\n`) e espaços sobrando cortados.
- R4 · Durante a leitura de um PDF de mais de 5 páginas, um cartão mostra "Lendo o PDF… página x de n" com barra de progresso e **Cancelar**. Cancelar deixa o campo como estava.
- R5 · Depois de importar:
  - acima do campo aparece um cartão com o tipo, o nome do arquivo e "<n> páginas · <c> caracteres", com **Trocar** e **Remover**;
  - Remover tira do campo só o texto que veio do arquivo, se ele não foi editado; se foi, pergunta antes;
  - o foco vai para o campo.
- R6 · Se o campo já tem texto, uma escolha aparece junto do botão:
  - **Adicionar ao fim** (padrão): o texto do arquivo entra depois de uma linha em branco;
  - **Substituir**: troca o texto do campo. Ctrl+Z desfaz.

  Com o campo vazio, não pergunta.
- R7 · Problemas, sempre com a mensagem perto do campo:

  | Caso | Mensagem | O texto entra? |
  |---|---|---|
  | PDF sem texto (escaneado) | "Este PDF não tem texto para ler." e o que fazer | não |
  | Mais de 40.000 caracteres | "O arquivo tem <n> caracteres; o campo aceita 40.000.", com "Ver o que ficou de fora" | sim, cortado no fim do último parágrafo que cabe |
  | Formato não aceito (`.docx`, imagem…) | "Ainda não dá para importar .<ext>. Salve como PDF, Markdown ou TXT." | não |
  | PDF com senha | "O PDF tem senha." e o que fazer | não |
  | TXT fora de UTF-8 | "Alguns caracteres não foram reconhecidos." (lido como Latin-1; o que não der vira "?") | sim |
  | Arquivo maior que 20 MB | "O arquivo tem <n> MB; o limite é 20 MB." | não |
  | `pdftotext` não instalado | "Para ler PDF, instale o pacote poppler-utils." com o comando | não |

  Os erros saem quando a pessoa edita o campo ou importa outro arquivo.
- R8 · O mesmo componente vale no passo Visão do Projeto (`_IdeaBox`), com o mesmo limite. A frase de apoio ganha "Já tem uma proposta escrita? Importe o texto dela."
- R9 · Acessibilidade:
  - o botão e o cartão têm rótulos;
  - o progresso e os erros são anunciados (`liveRegion`);
  - a escolha do R6 é um grupo de rádio usável pelo teclado.

## Fora do escopo

- Word (`.docx`), planilhas, imagens e OCR.
- Mandar o arquivo como anexo para o planner. Só o texto entra no campo.
- Importar mais de um arquivo de uma vez.

## Design

### O que já existe

- `lib/features/specs/new_spec_view.dart`: `_Idea`, com o `TextField` `new-spec-idea` (até 8 linhas).
- `lib/features/project/widgets/vision_step.dart`: `_IdeaBox`, com o `TextField` `project-idea`.
- `file_selector` e `desktop_drop` no `pubspec.yaml` (o `DropTarget` já é usado no Prompt).
- `lib/core/process/process_runner.dart`: `processRunnerProvider`, para rodar o `pdftotext` testável.

### Componentes

- **`IdeaImport`** (novo, `lib/features/ideas/idea_import.dart`): lê um caminho e devolve `ImportedText` (texto, tipo, páginas, caracteres, avisos) ou um `ImportProblem`.
  - **TXT e Markdown:** leitura direta.
  - **PDF:** `pdftotext -layout -f i -l i` por página, para o progresso e o cancelamento, depois a limpeza do R3.
  - O limite e o corte em parágrafo do R7 também ficam aqui.
- **`IdeaField`** (novo, `lib/features/ideas/widgets/idea_field.dart`): o campo com o rodapé, o `DropTarget`, o cartão de origem, o cartão de progresso, a escolha do R6 e as mensagens. Recebe o `TextEditingController` de quem o usa.
- **`_Idea`** e **`_IdeaBox`** trocam o `TextField` pelo `IdeaField`.

### Testes

- **`IdeaImport`:**
  - TXT, Markdown e UTF-8 inválido;
  - PDF com um `ProcessRunner` falso: páginas, junção de linhas e cabeçalho repetido;
  - PDF vazio, PDF com senha e `pdftotext` ausente;
  - corte em 40.000 no fim do parágrafo;
  - arquivo grande e formato não aceito.
- **`IdeaField`:**
  - importar preenche o campo e mostra o cartão;
  - campo com texto pergunta, Adicionar ao fim e Substituir;
  - Remover;
  - os erros aparecem e somem ao editar;
  - soltar um arquivo;
  - Cancelar no progresso.
- **Telas:** Nova spec e Projeto mostram o botão e o limite.

## Decisões

- **`pdftotext`, não um pacote Dart.** O app é Linux, o poppler-utils já vem na maioria das distribuições e lê PDF melhor que as bibliotecas puras em Dart. Sem ele, a mensagem do R7 diz como instalar. `pdfrx` traria o PDFium inteiro para o build.
- **40.000 caracteres.** É bastante para um briefing e não toma o contexto do planner.
- **Só texto.** O planner trabalha com o campo; anexar o arquivo mudaria o fluxo do planner, que fica para outra spec.

## Plano

1. **t1 · Leitura dos arquivos** (R3, R7): `IdeaImport` com TXT, Markdown, PDF por página, limpeza, limites, problemas e testes.
2. **t2 · Campo com importação** (R1, R2, R4–R6, R9): `IdeaField` com botão, Ctrl+O, soltar, progresso, cartão de origem, escolha adicionar/substituir, mensagens e testes.
3. **t3 · Nas duas telas** (R8): Nova spec e Projeto usando o `IdeaField`, frases de apoio e testes das telas.

## Critérios de aceite

- [ ] Importar um TXT, um Markdown e um PDF com texto preenche o campo, e o cartão mostra o arquivo.
- [ ] Arrastar um arquivo para o campo importa.
- [ ] Com texto no campo, dá para adicionar ao fim ou substituir; Ctrl+Z desfaz a substituição.
- [ ] PDF escaneado, com senha, `.docx` e arquivo grande mostram a mensagem certa e não mexem no campo.
- [ ] Um texto acima de 40.000 caracteres entra cortado num parágrafo, com o aviso.
- [ ] O mesmo vale no passo Visão do Projeto.
