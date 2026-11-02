import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/specs/spec_lint.dart';

const _spec = '''---
id: SPEC-009
---

# Avisos

## Requisitos

- R1 · Quando o usuário salvar, o sistema deve gravar o arquivo
- R2 · O botão fica azul
- R2 · Quando repetir, o sistema deve reclamar
- R5 · Quando pular, o sistema deve avisar

## Critérios de aceite

- [ ] Grava [R1] verificar: flutter test
- [ ] Sem requisito verificar: true
- [ ] Cita um que não existe [R9] verificar: true
- [ ] Sem comando [R5]
- [ ] Manual com crases [R1] verificar: manual (`flutter run -d linux`, abrir)
''';

void main() {
  test('each of the five kinds, at its line (SPEC-023 R8)', () {
    expect(lintSpec(_spec), const [
      SpecWarning(
        line: 10,
        message: 'R2 sem critério de aceite',
        kind: SpecWarningKind.uncoveredRequirement,
      ),
      SpecWarning(
        line: 10,
        message: 'R2 sem "deve" (fora do estilo EARS)',
        kind: SpecWarningKind.ears,
      ),
      SpecWarning(
        line: 11,
        message: 'R2 repetido',
        kind: SpecWarningKind.requirementId,
      ),
      SpecWarning(
        line: 12,
        message: 'R5 fora de sequência (esperado R3)',
        kind: SpecWarningKind.requirementId,
      ),
      SpecWarning(
        line: 17,
        message: 'Critério sem [Rn]',
        kind: SpecWarningKind.criterionRequirement,
      ),
      SpecWarning(
        line: 18,
        message: 'Critério cita R9, que não existe',
        kind: SpecWarningKind.criterionRequirement,
      ),
      SpecWarning(
        line: 19,
        message: 'Critério sem verificar:',
        kind: SpecWarningKind.criterionVerify,
      ),
    ]);
  });

  test('"devem" also counts; no Requisitos section → the body', () {
    expect(
      lintSpec(
        '# X\n\n- R1 · Os botões devem ter foco\n\n## Critérios de aceite\n\n'
        '- [ ] Foco [R1] · verificar: true\n',
      ),
      isEmpty,
    );
  });

  test('a well-formed real spec (SPEC-021) has no warning', () {
    final text = File('docs/specs/SPEC-021-voltar-a-spec-ao-refinar.md')
        .readAsStringSync();
    // Only the SPEC-028 R3 notice: its questions have no `P<n>`.
    expect(lintSpec(text).map((w) => w.kind), [
      SpecWarningKind.openQuestionsFormat,
    ]);
  });

  test('SPEC-028 R3: suggestions counted as questions give the notice with '
      'both counts; the R1 format gives none', () {
    const old = '''# X

## Perguntas em aberto

1. Como adicionar?
2. Sugestão: pela seleção.
3. Lembrar o filtro?
4. Sugestão: não.
''';
    final w = lintSpec(old).single;
    expect(w.kind, SpecWarningKind.openQuestionsFormat);
    expect(w.line, 6);
    expect(
      w.message,
      'Em "Perguntas em aberto", 2 itens são sugestões, não perguntas. A spec '
      'tem 2 perguntas, não 4. As linhas marcadas são sugestões.',
    );
    const ok = '''# X

## Perguntas em aberto

- P1 · Como adicionar?
  - Sugestão: pela seleção.
- P2 · Lembrar o filtro?
''';
    expect(lintSpec(ok), isEmpty);
  });
}
