import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/specs/spec_file.dart';

/// SPEC-112 R6, R12: "→ DT-NN" / "→ DP-NN" in the answer of a question.
void main() {
  const spec = '''---
id: SPEC-033
status: rascunho
---

# Limite de arquivos

## Requisitos

- R1 · Limitar o tamanho.

## Perguntas em aberto

- P4 · Qual o limite de tamanho por arquivo?
  - Sugestão: 20 MB
- P5 · Guardar os arquivos recusados para auditoria?
  - Sugestão: guardar no S3 por 30 dias
- P7 · Arquivo acima do limite: recusar no envio ou comprimir?

## Critérios de aceite

- [ ] Recusa acima do limite [R1]
''';
  final at = DateTime(2026, 11, 24);

  test('an open question gets "→ débito técnico DT-09" and counts as '
      'answered (R6)', () {
    final out = SpecDocument.parse(spec).withQuestionAnnotated(
      'P5',
      SpecDocument.debtAnnotation('DT-09'),
      answer: 'só recusa por ora',
      at: at,
    )!;
    final doc = SpecDocument.parse(out);
    expect(doc.openQuestions.map((q) => q.id), ['P4', 'P7']);
    expect(
      out,
      contains(
        '## Decisões\n\n'
        '- P5 · só recusa por ora → débito técnico DT-09 (2026-11-24)',
      ),
    );
  });

  test('"Decidir depois" writes "→ DP-09" without an answer (R6)', () {
    final out = SpecDocument.parse(spec).withQuestionAnnotated(
      'P7',
      SpecDocument.decisionAnnotation('DP-09'),
      at: at,
    )!;
    expect(out, contains('- P7 · → DP-09 (2026-11-24)'));
    expect(SpecDocument.parse(out).openQuestions.map((q) => q.id), [
      'P4',
      'P5',
    ]);
  });

  test('the answer of the decision replaces "→ DP-09" in Decisões (R12)', () {
    final first = SpecDocument.parse(spec).withQuestionAnnotated(
      'P7',
      SpecDocument.decisionAnnotation('DP-09'),
      at: at,
    )!;
    final out = SpecDocument.parse(first).withQuestionAnnotated(
      'P7',
      SpecDocument.decisionAnnotation('DP-09', answer: 'Recusar  no envio.'),
      at: DateTime(2026, 11, 30),
    )!;
    expect(out, contains('- P7 · → DP-09: Recusar no envio. (2026-11-24)'));
    expect(out, isNot(contains('→ DP-09 (')));
    // Only that line changed.
    expect(out.split('\n').length, first.split('\n').length);
  });

  test('a question already answered by hand gets the annotation before the '
      'date', () {
    final answered = SpecDocument.parse(spec)
        .withAnswers({'P4': '20 MB fixo por hora'}, at);
    final out = SpecDocument.parse(answered).withQuestionAnnotated(
      'P4',
      SpecDocument.debtAnnotation('DT-09'),
      at: at,
    )!;
    expect(
      out,
      contains(
        '- P4 · 20 MB fixo por hora → débito técnico DT-09 (2026-11-24)',
      ),
    );
  });

  test('an unknown question gives null', () {
    expect(
      SpecDocument.parse(spec).withQuestionAnnotated('P9', '→ DP-01', at: at),
      isNull,
    );
  });
}
