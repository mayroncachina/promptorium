---
id: SPEC-062
status: aprovada
issue: 173
depende-de: SPEC-037
---

# "Planejar de novo" visível e "Planejada" na lista

## Objetivo

Duas coisas atrapalham depois de apertar **Planejar** numa spec:
- **O botão some em vez de virar "Planejar de novo".** Com o plano escrito, "Aprovar" vira o botão principal. Em janelas de até ~1366 px não cabem três botões, e a barra manda para o menu ⋯ primeiro o "Planejar de novo", porque "Refinar com IA" vem antes na ordem. Parece que o plano não pegou, e a pessoa aperta de novo.
- **A lista de specs não diz que a spec tem plano.** Planejada ou não, ela mostra "Rascunho". Só "Aprovada" tem cor própria.

Esta spec mantém "Planejar de novo" na barra e mostra **Planejada**, em amarelo, na lista e no cabeçalho.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/NfG6TyHujedGXjcMCUHNvp). Capturas em `docs/mockups/spec-062/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-antes.png` | Hoje, em 1366×768: "Planejar" some e a lista diz "Rascunho" | — |
| `2-planejar-de-novo.png` | "Planejar de novo" na barra e o chip "Planejada" | R1, R3 |
| `3-menu.png` | Sem espaço, "Refinar com IA" vai para o menu primeiro | R1 |
| `4-lista.png` | "Planejada" em amarelo na lista | R2 |
| `5-largo.png` | Janela larga: os três botões cabem | R1 |

## Requisitos

- R1 · Assim que o plano entra no editor, o botão vira **Planejar de novo**, antes mesmo de salvar. Quando não cabem todos os botões, a barra manda para o menu ⋯ primeiro "Refinar com IA" e só depois "Planejar de novo". O principal ("Aprovar" com plano, "Planejar" sem) nunca sai da barra (SPEC-037 R1, SPEC-039 R7).
- R2 · Na lista de specs, uma spec **com `## Plano`** e ainda não aprovada (Ideia, Rascunho ou Em revisão) mostra **Planejada** em amarelo, com um ponto antes do texto:
  - Aprovada, Concluída e Arquivada continuam como estão, mesmo com plano;
  - a lista lê o que está salvo no arquivo: a spec vira "Planejada" quando o plano é salvo e volta ao status anterior se o plano sair do arquivo;
  - "sem plano (spec trivial)" não conta como plano.
- R3 · O chip de status no cabeçalho da spec segue a mesma regra, a partir do texto do editor: mostra "Planejada" assim que o plano entra, mesmo antes de salvar.
- R4 · O amarelo de "Planejada" é uma cor própria (`AppColors.yellow`), diferente do âmbar de "Em revisão", com contraste de pelo menos 4,5:1 sobre o painel.

## Fora do escopo

- Mudar o status gravado no arquivo: "Planejada" é derivado do `## Plano`, não um novo valor de `status:`.
- Os cartões do Quadro.
- Mudar o que "Planejar" escreve.

## Design

### O que já existe

- `lib/features/specs/widgets/spec_header.dart`: `specHeaderActions` (ordem Refinar → Planejar → Aprovar) e `layoutSpecActions`, que guarda os secundários na ordem da lista até acabar o espaço.
- `lib/features/specs/specs_screen.dart`, por volta da linha 1765: `hasPlan: doc.design != null`, a partir do texto do editor.
- `lib/features/specs/widgets/spec_list.dart`: `specStatusColor` e o rótulo `specStatusLabel(s.status)` de cada item.
- `lib/features/specs/spec_service.dart`: a sincronização do arquivo para a tabela `Specs` (título, status, requisitos…).
- `SpecDocument.design` e `designWaived` em `spec_file.dart`.

### Componentes

- **`SpecAction.priority`** (ou a ordem de saída): `layoutSpecActions` tira do fim da fila de prioridade, não da ordem visual; "Refinar com IA" tem prioridade menor que "Planejar de novo". A ordem na barra continua Refinar → Planejar → Aprovar quando tudo cabe.
- **Coluna `Specs.hasPlan`** (schema v23, padrão `false`), preenchida pela sincronização a partir de `SpecDocument.design != null`; a migração preenche as specs que já existem na próxima leitura dos arquivos.
- **`specListStatus(Spec)`** em `spec_list.dart`: rótulo e cor ("Planejada" + amarelo quando `hasPlan` e o status vem antes de Aprovada); o cabeçalho usa a mesma regra com o `SpecDocument` do editor.

### Testes

- Barra: em 1366 px, com plano, "Planejar de novo" e "Aprovar" na barra e "Refinar com IA" no menu; em 1920 px, os três; sem plano, "Planejar" primário.
- O plano entra no editor: o rótulo muda no mesmo frame, antes de salvar.
- Lista: com plano salvo, "Planejada"; Aprovada com plano continua "Aprovada"; tirar o plano e salvar volta para "Rascunho"; "sem plano (spec trivial)" não conta.
- Cabeçalho: o chip "Planejada" antes de salvar.
- Migração v22 → v23.

## Decisões

- **"Refinar com IA" sai primeiro.** Depois de planejar, os próximos passos naturais são revisar o plano, planejar de novo ou aprovar; refinar o texto vem antes de planejar.
- **Planejada é derivado.** Não há `status: planejada` no arquivo; quem tem plano e ainda não foi aprovado é "Planejada". Assim nada muda para o Quadro, a aprovação e as specs antigas.
- **Lista pelo arquivo, cabeçalho pelo editor.** A lista mostra o estado salvo de todas as specs (como já faz com o status); o cabeçalho mostra o que está na tela.
- **Amarelo próprio.** O âmbar já é "Em revisão" e o botão principal; um amarelo distinto evita confundir os dois.

## Plano

1. **t1 · Barra e Planejada** (R1–R4): prioridade na barra, `Specs.hasPlan` (v23) e a sincronização, `AppColors.yellow`, "Planejada" na lista e no cabeçalho, e os testes.

## Critérios de aceite

- [ ] Depois de Planejar, o botão vira "Planejar de novo" e continua visível em 1366×768.
- [ ] Sem espaço, "Refinar com IA" vai para o menu antes de "Planejar de novo".
- [ ] A lista mostra "Planejada" em amarelo para specs com plano ainda não aprovadas.
- [ ] O cabeçalho mostra "Planejada" assim que o plano entra no editor.
