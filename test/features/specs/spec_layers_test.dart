import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/board/board_rules.dart';
import 'package:promptorium/features/board/spec_runner.dart';
import 'package:promptorium/features/specs/spec_design.dart';
import 'package:promptorium/features/specs/spec_file.dart';

const layered = '''---
id: SPEC-003
status: aprovada
---

# Extração do schema

## Objetivo

Ler o schema do Firebird.

## Requisitos

- R1 · Quando o usuário conectar, o sistema deve listar as tabelas
- R2 · Quando houver índices, o sistema deve extraí-los

## Design

### R1 · Tabelas

Consulta em RDB\$RELATIONS em lib/schema/tables.dart.

### R2 · Índices

Novo extrator em lib/schema/indexes.dart.

### Comum

Erros viram SchemaError.

## Etapas

- R1 → lib/schema/tables.dart · verificar: `dart test test/tables_test.dart`
- R2 → lib/schema/indexes.dart

## Critérios de aceite

- [ ] Tabelas listadas [R1] · verificar: true
- [ ] Índices extraídos [R2]
''';

void main() {
  test('sections, design, step plans; requirements only from Requisitos', () {
    final d = SpecDocument.parse(layered);
    expect(d.objective, 'Ler o schema do Firebird.');
    expect(d.design, startsWith('### R1 · Tabelas'));
    expect(d.requirements.map((r) => r.id), ['R1', 'R2']);
    expect(d.stepPlans['R1']!.files, ['lib/schema/tables.dart']);
    expect(d.stepPlans['R1']!.verify, 'dart test test/tables_test.dart');
    expect(d.stepPlans['R2']!.verify, isNull);
    // The template's hint is not a design.
    expect(
      SpecDocument.parse(newSpecMarkdown(code: 'SPEC-9', title: 'x')).design,
      isNull,
    );
    expect(
      SpecDocument.parse(
        SpecDocument.parse(layered).withMeta(designWaived: true),
      ).designWaived,
      isTrue,
    );
  });

  test('focused prompt: objective, the linked design blocks, plan and '
      'criteria of the step only; whole spec without a link', () {
    const steps = [
      StepView(id: 'R1', text: 'listar tabelas'),
      StepView(id: 'R2', text: 'extrair índices'),
    ];
    final f = focusedSpecText(layered, steps: steps, todo: ['R2'])!;
    expect(f, contains('## Objetivo\n\nLer o schema do Firebird.'));
    expect(f, contains('- R2 · extrair índices'));
    expect(f, contains('Novo extrator em lib/schema/indexes.dart'));
    expect(f, isNot(contains('RDB\$RELATIONS')));
    expect(f, isNot(contains('SchemaError')));
    expect(f, contains('- R2 → lib/schema/indexes.dart'));
    expect(f, contains('- [ ] Índices extraídos [R2]'));
    expect(f, isNot(contains('Tabelas listadas')));
    // No design: the whole spec.
    expect(
      focusedSpecText(
        layered.replaceFirst(
          RegExp(r'## Design[\s\S]*?## Etapas'),
          '## Etapas',
        ),
        steps: steps,
        todo: ['R2'],
      ),
      isNull,
    );
    expect(stepVerifyCommands(layered, ['R1']), [
      'dart test test/tables_test.dart',
      'true',
    ]);
    expect(stepVerifyCommands(layered, ['R2']), isEmpty);
  });

  test('withDesign replaces or inserts Design and Etapas; the generator '
      'answer becomes the sections', () {
    const plain =
        '# A\n\n## Requisitos\n\n- R1 · x\n\n## Critérios de aceite\n\n- [ ] ok\n';
    final out = applyDesignAnswer(plain, {
      'design': '### R1\n\nFaça em lib/a.dart.',
      'etapas': [
        {
          'requisito': 'R1',
          'arquivos': ['lib/a.dart'],
          'verificar': 'make t',
        },
        {'requisito': 'lixo', 'arquivos': [], 'verificar': ''},
      ],
    });
    final d = SpecDocument.parse(out);
    expect(d.design, '### R1\n\nFaça em lib/a.dart.');
    expect(d.stepPlans.keys, ['R1']);
    expect(d.stepPlans['R1']!.verify, 'make t');
    expect(out.indexOf('## Design') < out.indexOf('## Critérios'), isTrue);
    final again = SpecDocument.parse(out).withDesign('Novo.');
    expect(SpecDocument.parse(again).design, 'Novo.');
    expect('## Design'.allMatches(again), hasLength(1));
    expect(() => applyDesignAnswer(plain, {'design': ' '}), throwsA(anything));
  });
}
