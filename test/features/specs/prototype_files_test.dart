import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/specs/prototype/prototype_files.dart';
import 'package:promptorium/features/specs/spec_file.dart';

const spec = '''---
id: SPEC-022
status: em-revisao
---

# Protótipo

## Requisitos

- R1 · Lista
- R2 · Detalhe

## Design

texto

## Etapas

- R1 → lib/a.dart

## Critérios de aceite

- [ ] algo [R1]
''';

void main() {
  test('names: R<n>-<slug>.html is A, .<letter>.html the others; next free '
      'variation (R7)', () {
    final a = parseMockupName('R1-lista-de-prompts.html')!;
    expect(a.requirement, 'R1');
    expect(a.letter, 'a');
    expect(a.label, 'R1 · Lista de prompts');
    final b = parseMockupName('R1-lista-de-prompts.b.html')!;
    expect(b.letter, 'b');
    expect(b.label, 'R1 · Lista de prompts · B');
    expect(parseMockupName('index.json'), isNull);
    expect(parseMockupName('1-modo.png'), isNull);
    expect(nextVariationName([a], 'R1'), 'R1-lista-de-prompts.b.html');
    expect(nextVariationName([a, b], 'R1'), 'R1-lista-de-prompts.c.html');
    expect(nextVariationName([a], 'R2', slug: 'x'), 'R2-x.html');
    expect(mockupDir('SPEC-022'), 'docs/mockups/spec-022');
  });

  test('index.json round-trips descriptions, times and history', () {
    final at = DateTime(2026, 10, 24, 10, 41);
    final i = PrototypeIndex(
      screens: {
        'R1-lista.html': ScreenMeta(description: 'busca e filtros', createdAt: at),
      },
      history: [
        PrototypeRequest(
          request: 'mais denso',
          at: at,
          requirements: const ['R1'],
          answer: 'feito',
          files: const ['R1-lista.b.html'],
        ),
      ],
    );
    final back = PrototypeIndex.decode(i.encode());
    expect(back.screens['R1-lista.html']!.description, 'busca e filtros');
    expect(back.screens['R1-lista.html']!.createdAt, at);
    expect(back.history.single.files, ['R1-lista.b.html']);
    expect(PrototypeIndex.decode('lixo').screens, isEmpty);
  });

  test('R9: approving writes "## Protótipo", another variation of the same '
      'requirement replaces the line, the status does not change', () {
    final once = SpecDocument.parse(
      spec,
    ).withPrototype('R1', 'docs/mockups/spec-022/R1-lista.html');
    expect(
      once,
      contains('## Protótipo\n\n- R1 → docs/mockups/spec-022/R1-lista.html\n'),
    );
    // After "## Etapas", before the criteria.
    expect(once.indexOf('## Protótipo'), greaterThan(once.indexOf('## Etapas')));
    expect(
      once.indexOf('## Protótipo'),
      lessThan(once.indexOf('## Critérios')),
    );
    final twice = SpecDocument.parse(once)
        .withPrototype('R2', 'docs/mockups/spec-022/R2-detalhe.html');
    final replaced = SpecDocument.parse(
      twice,
    ).withPrototype('R1', 'docs/mockups/spec-022/R1-lista.b.html');
    final doc = SpecDocument.parse(replaced);
    expect(doc.prototypes, {
      'R1': 'docs/mockups/spec-022/R1-lista.b.html',
      'R2': 'docs/mockups/spec-022/R2-detalhe.html',
    });
    expect('## Protótipo'.allMatches(replaced), hasLength(1));
    expect(replaced, isNot(contains('R1-lista.html')));
    expect(doc.status, SpecStatus.review);
    expect(doc.rawStatus, 'em-revisao');
    expect(doc.stepPlans.keys, ['R1']);
    expect(parseCriteria(replaced), hasLength(1));
  });
}
