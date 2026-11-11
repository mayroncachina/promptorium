---
id: SPEC-063
status: rascunho
issue: 176
---

# Dependências que o app entende e avisa

## Objetivo

Uma spec com `depende: [SPEC-001]` no cabeçalho rodou junto com a SPEC-001 no "Executar tudo". O app só lê a chave `depende-de`. Qualquer outro nome é ignorado em silêncio, e a spec passa a não depender de nada. O mesmo silêncio vale para uma dependência que cita uma spec que não existe.

O `depende:` não veio do app, que sempre grava `depende-de`. Veio de texto escrito livremente pelo Claude: o comando `/spec` do Prompt, "Transformar em spec", que guarda o cabeçalho como veio, ou uma edição direta no arquivo. Nenhum prompt ensina o nome da chave.

Esta spec faz o app entender as variações comuns da chave, avisar o que ele não entende e ensinar o formato aos prompts que escrevem spec.

Mockup: [canvas do Claude Design](https://claude.ai/artifact/QpHSDa4KLroKNdik5WwyeT). Capturas em `docs/mockups/spec-063/`:

| Captura | O que mostra | Requisitos |
|---|---|---|
| `1-antes.png` | Hoje: `depende:` ignorado e a lista sem "espera" | — |
| `2-variacao.png` | A variação lida como `depende-de`, com o aviso e "Trocar agora" | R1, R2 |
| `3-corrigido.png` | Salvo com o nome certo | R2 |
| `4-avisos.png` | Avisos de código inexistente e de chave desconhecida | R3, R4 |
| `5-transformar.png` | "Transformar em spec" mostra o cabeçalho ajustado | R5 |

## Requisitos

- R1 · O app lê como `depende-de` as variações da chave: `depende`, `depends`, `depends-on`, `depends_on`, `dependsOn`, `depende_de`, `dependencias` e `dependências`, sem diferença de maiúsculas. A dependência vale na hora: no Quadro, no "Executar tudo", na lista ("espera SPEC-001") e na sincronização com o banco.
- R2 · Com uma variação no cabeçalho, o editor mostra acima do texto o aviso "A chave `<variação>` foi lida como `depende-de`: a SPEC-NNN espera a SPEC-MMM. Ao salvar, o nome fica certo no arquivo." e o botão **Trocar agora**:
  - "Trocar agora" troca a linha no editor, sem salvar;
  - ao salvar, o app grava `depende-de` no lugar da variação;
  - com `depende-de` e uma variação ao mesmo tempo, valem as duas listas juntas, sem repetir códigos, e a variação sai ao salvar.
- R3 · Os avisos de estrutura (a faixa abaixo do editor) ganham:
  - "`depende-de` cita `SPEC-009`, que não existe neste workspace: a spec não vai esperar por ela.", na linha da chave, com "Ir para a linha";
  - "`depende-de` cita a própria spec.", quando ela depende de si mesma.
- R4 · Uma chave do cabeçalho que o app não conhece vira o aviso "Chave desconhecida no cabeçalho: `<chave>`. Para dependência, o app lê `depende-de`." com o botão **Trocar para depende-de**. As chaves conhecidas são as que o app lê ou escreve (id, status, depende-de, fase, design, plano, issue e as internas, como status-anterior), além das variações do R1.
- R5 · Os textos que viram spec saem no formato certo:
  - o prompt salvo `/spec` do Prompt passa a pedir o cabeçalho `id`, `status` e `depende-de` (quando houver), e diz que dependência é sempre `depende-de: [SPEC-NNN]`;
  - "Transformar em spec" e "Aplicar na spec" trocam variações do R1 por `depende-de`, e a confirmação mostra o que mudou no cabeçalho, linha por linha.

## Fora do escopo

- Mostrar no "Executar tudo" quem começa e quem espera (SPEC-064).
- Mudar quando uma dependência libera a spec (Review ou Feito, SPEC-064).
- Validar outras chaves além de dependência e chave desconhecida.

## Design

### O que já existe

- `lib/features/specs/spec_file.dart`: `dependsOnKey = 'depende-de'`, `SpecDocument.dependsOn`, `hasDependsOn` e `withMeta(dependsOn: …)`.
- `lib/features/specs/spec_service.dart`: a sincronização (`deps = doc.hasDependsOn ? doc.dependsOn : existing.dependsOn`).
- `lib/features/specs/spec_lint.dart`: `SpecWarningKind` e `lintSpec`; a faixa `spec_warnings_bar.dart`.
- O aviso acima do editor da SPEC-028 R3 (formato de "Perguntas em aberto"), com botão de correção: o mesmo modelo para o R2.
- `lib/features/prompt/spec_from_answer.dart`: `newSpecTextFromAnswer` e `appliedSpecText`, que guardam as outras chaves.
- `lib/features/prompt/prompt_actions.dart`: o prompt salvo `/spec`.

### Componentes

- **`SpecDocument.dependsOnAlias`** (a variação encontrada, ou nulo) e `dependsOn` lendo `depende-de` mais a variação; `hasDependsOn` vale para as duas.
- **`SpecDocument.withCanonicalDependsOn()`**: o texto com a variação trocada por `depende-de` (listas juntas). O salvar chama antes de gravar.
- **`lintSpec`** recebe os códigos do workspace e ganha `SpecWarningKind.unknownDependency`, `selfDependency` e `unknownFrontmatterKey`.
- **Aviso da variação** acima do editor, no lugar onde a SPEC-028 põe o do formato das perguntas.

### Testes

- Cada variação do R1 vira dependência; maiúsculas; as duas chaves juntas.
- Salvar troca a variação; "Trocar agora" troca no editor sem salvar.
- A dependência pela variação bloqueia no "Executar tudo" (o mesmo cenário que falhou: SPEC-002 com `depende: [SPEC-001]`).
- Avisos: código inexistente, a própria spec e chave desconhecida; nenhum aviso para as chaves conhecidas.
- `/spec` pede `depende-de`; "Transformar em spec" troca a variação e mostra a diferença.

## Decisões

- **Aceitar e corrigir, em vez de só avisar.** A spec que falhou estava aprovada e pronta para rodar. Só avisar deixaria a execução errada até alguém ler o aviso. Lendo a variação, o comportamento fica certo na hora, e o aviso explica a troca.
- **Variações fechadas.** Uma lista fixa evita adivinhar: `requer` ou `apos` podem significar outra coisa, e viram aviso de chave desconhecida (R4).
- **Chave desconhecida é aviso, não erro.** O cabeçalho pode ter metadados de quem usa o projeto; o aviso não impede salvar nem aprovar, como os outros avisos de estrutura.

## Plano

1. **t1 · Ler e corrigir a variação** (R1, R2): `dependsOnAlias`, a leitura, a troca ao salvar, o aviso com "Trocar agora" e os testes, incluindo o cenário do "Executar tudo".
2. **t2 · Avisos e prompts** (R3–R5): os três avisos novos, o `/spec`, "Transformar em spec" e "Aplicar na spec" com a diferença do cabeçalho, e os testes.

## Critérios de aceite

- [ ] Uma spec com `depende: [SPEC-001]` espera a SPEC-001 no "Executar tudo".
- [ ] Ao salvar, `depende:` vira `depende-de:` no arquivo.
- [ ] Uma dependência para uma spec que não existe aparece como aviso.
- [ ] Uma chave desconhecida no cabeçalho aparece como aviso, com "Trocar para depende-de".
- [ ] O `/spec` e "Transformar em spec" produzem `depende-de`.
