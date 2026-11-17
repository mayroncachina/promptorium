import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/specs/spec_draft.dart';
import 'package:promptorium/features/specs/spec_planner.dart';
import 'package:promptorium/features/specs/spec_lint.dart';
import 'package:promptorium/features/specs/spec_prints.dart';

import '../spec_planner_test.dart' show plannerOutput, resultLine;
import '../specs_screen_test.dart' show settleIo;
import 'print_harness.dart';
import 'print_test_utils.dart';

void main() {
  group('the draft (R8, R9)', () {
    setUpPrintHarness();

    testWidgets('R8, R9: a brand of the reference app in the draft blocks '
        '"Criar spec", is highlighted and the planner can rewrite', (
      tester,
    ) async {
      await pump(tester);
      final f = File('${tmp.path}/p.png')..writeAsBytesSync([1]);
      final done = <bool>[];
      c.read(specDraftsRepoProvider).start(ws.id).then((_) async {
        await c
            .read(specDraftsRepoProvider)
            .update(
              ws.id,
              SpecDraftsCompanion(
                data: Value(
                  SpecDraftData(
                        title: 'Comparar respostas',
                        objective: 'Ver duas respostas.',
                        requirements: const [
                          'As respostas ficam em colunas, como no Nimbo, e rolam '
                              'juntas.',
                        ],
                        prints: [
                          fakePrint(
                            f.path,
                            kind: PrintKind.reference,
                            description: 'Três colunas',
                            brands: const ['Nimbo'],
                          ),
                        ],
                        printsSent: true,
                      )
                      .withUserMessage('Ideia')
                      .withAnswer(
                        reply: 'ok',
                        draft: PlannerDraft(
                          title: 'Comparar respostas',
                          objective: 'Ver duas respostas.',
                          requirements: const [
                            'As respostas ficam em colunas, como no Nimbo, e '
                                'rolam juntas.',
                          ],
                        ),
                        suggestions: const [],
                        knownSpecs: const {},
                      )
                      .encode(),
                ),
              ),
            );
        done.add(true);
      });
      await settleIo(tester, until: () => done.isNotEmpty);
      c.read(newSpecFlowProvider.notifier).converse();
      await settleIo(tester, until: () => key('new-spec-create').present);
      expect(key('brand-warning-Nimbo'), findsOneWidget);
      expect(
        find.textContaining(
          'A spec cita “Nimbo” do app de referência',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(enabled(tester, 'new-spec-create'), isFalse);
      expect(
        find.text('Tire as citações ao app de referência (1)'),
        findsOneWidget,
      );

      await tester.tap(key('brand-rewrite'));
      await settleIo(tester, until: () => cli.processes.isNotEmpty);
      cli.last.emit(
        resultLine({
          ...plannerOutput(
            title: 'Comparar respostas',
            requirements: const [
              'As respostas ficam em colunas iguais e rolam juntas.',
            ],
          ),
          'prints': [
            {
              'nome': 'print-1.png',
              'descricao': 'Três colunas',
              'marcas': ['Nimbo'],
            },
          ],
        }),
      );
      await settleIo(tester, until: () => !key('brand-warning-Nimbo').present);
      await settleIo(tester, until: () => c.read(specPlannerProvider).isEmpty);
      expect(enabled(tester, 'new-spec-create'), isTrue);
      expect(key('brand-block-hint'), findsNothing);
    });
  });

  group('brandMentions (R9)', () {
    SpecDraftData draft({
      String title = 'Comparar respostas',
      String objective = 'Ver duas respostas lado a lado.',
      List<String> requirements = const [],
      List<String> outOfScope = const [],
      PrintKind kind = PrintKind.reference,
      String description = 'Três colunas iguais',
    }) => SpecDraftData(
      title: title,
      objective: objective,
      requirements: requirements,
      outOfScope: outOfScope,
      prints: [
        fakePrint(
          '/t/p.png',
          kind: kind,
          description: description,
          brands: const ['Nimbo', 'Plânus'],
        ),
      ],
    );

    test('finds the brand in the title, objective, requirements, out of '
        'scope and descriptions, ignoring case and accents', () {
      final d = draft(
        title: 'Tela como a do NIMBO',
        objective: 'Copiar o planus.',
        requirements: const [
          'O sistema deve mostrar colunas.',
          'As respostas ficam em colunas, como no Nimbo, e rolam juntas.',
        ],
        outOfScope: const ['Login do nimbo'],
        description: 'Planos do Nimbo',
      );
      final found = brandMentions(d);
      expect(found.map((m) => m.where), [
        'Título',
        'Objetivo',
        'R2',
        'Fora do escopo',
        'Print 1',
      ]);
      final r2 = found[2];
      expect(r2.text.substring(r2.start, r2.end), 'Nimbo');
      expect(found[1].brand, 'Plânus');
    });

    test('whole words only', () {
      final d = draft(
        objective: 'Nimbostrato e anímbolo não contam; o Nimbo, sim.',
        description: '',
      );
      final found = brandMentions(d);
      expect(found, hasLength(1));
      expect(findBrand('o nimbo-pro', 'Nimbo'), hasLength(1));
      expect(findBrand('nimbos', 'Nimbo'), isEmpty);
    });

    test('only the brands of reference prints count', () {
      final bug = draft(kind: PrintKind.bug, title: 'Nimbo');
      expect(referenceBrands(bug), isEmpty);
      expect(brandMentions(bug), isEmpty);
      expect(brandMentions(draft()), isEmpty, reason: 'no citation');
    });
  });

  group('spec_lint (R9)', () {
    const text = '''---
id: SPEC-087
status: rascunho
---

# Comparar

## Objetivo

Ver duas respostas.

## Requisitos

- R2 · As colunas seguem o Nimbo: título, texto e botão.
''';

    test(
      '"Cita o app de referência" on the line that cites a stored brand',
      () {
        final w = lintSpec(
          text,
          referenceBrands: const ['Nimbo'],
        ).where((w) => w.kind == SpecWarningKind.referenceBrand).toList();
        expect(w, hasLength(1));
        expect(w.single.line, 14);
        expect(w.single.message, startsWith('Cita o app de referência'));
        expect(w.single.message, contains('“Nimbo”'));
      },
    );

    test('no stored brands, no warning; tipo: is a known key', () {
      expect(
        lintSpec(text).where((w) => w.kind == SpecWarningKind.referenceBrand),
        isEmpty,
      );
      final typed = text.replaceFirst(
        'status: rascunho',
        'status: rascunho\ntipo: bug',
      );
      expect(
        lintSpec(typed)
            .where((w) => w.kind == SpecWarningKind.unknownFrontmatterKey),
        isEmpty,
      );
    });
  });
}
