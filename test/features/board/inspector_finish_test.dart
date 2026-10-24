import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/specs_repo.dart';
import 'package:promptorium/features/review/widgets/spec_review_panel.dart'
    show pendingCriteriaProvider;
import 'package:promptorium/features/specs/spec_service.dart';

import 'canvas_fixture.dart';

/// Files do not run in widget tests: the service only moves the row, as
/// the real one does after writing the frontmatter (covered in
/// test/features/specs/spec_mark_done_test.dart).
class _FakeService extends SpecService {
  _FakeService(AppDatabase db) : _specs = SpecsRepo(db), super(SpecsRepo(db));
  final SpecsRepo _specs;
  final calls = <String>[];

  @override
  Future<Spec> markDone(Workspace ws, Spec spec) async {
    calls.add('done ${spec.code}');
    await _specs.update(
      spec.id,
      const SpecsCompanion(
        stage: Value(SpecStage.done),
        status: Value(SpecStatus.done),
      ),
    );
    return (await _specs.getById(spec.id))!;
  }

  @override
  Future<Spec> reopen(Workspace ws, Spec spec) async {
    calls.add('reopen ${spec.code}');
    await _specs.update(
      spec.id,
      const SpecsCompanion(
        stage: Value(SpecStage.backlog),
        status: Value(SpecStatus.approved),
      ),
    );
    return (await _specs.getById(spec.id))!;
  }
}

void main() {
  Future<_FakeService> pump(
    WidgetTester tester,
    List<CanvasSpec> specs, {
    List<String> pending = const [],
  }) async {
    late _FakeService service;
    await pumpCanvas(
      tester,
      specs,
      overrides: (db) => [
        specServiceProvider.overrideWithValue(service = _FakeService(db)),
        pendingCriteriaProvider.overrideWith((ref, id) async => pending),
      ],
    );
    return service;
  }

  String chipText(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(
          of: byKey('board-filter-hide-done'),
          matching: find.byType(Text),
        ),
      )
      .data!;

  testWidgets('"Marcar como finalizada" moves the spec to Feito; "Reabrir" '
      'only shows on a finished spec and takes it out (R8, R9, R5)', (
    tester,
  ) async {
    final service = await pump(tester, const [
      CanvasSpec('SPEC-001'),
      CanvasSpec('SPEC-002', stage: SpecStage.done),
    ]);
    await selectSpec(tester, 'SPEC-001');
    expect(byKey('inspector-mark-done'), findsOneWidget);
    expect(byKey('inspector-reopen'), findsNothing);
    await tester.tap(byKey('inspector-mark-done'));
    await pumpFor(tester, 20);
    expect(service.calls, ['done SPEC-001']);
    expect(byKey('inspector-mark-done'), findsNothing);
    expect(byKey('inspector-reopen'), findsOneWidget);

    // With the filter on, N follows the finish and the reopening.
    await tester.tap(byKey('board-filter-hide-done'));
    await pumpFor(tester, 20);
    expect(chipText(tester), 'Ocultar concluídas · 2');
    await tester.tap(byKey('board-filter-hide-done'));
    await pumpFor(tester, 20);

    await selectSpec(tester, 'SPEC-001');
    await tester.tap(byKey('inspector-reopen'));
    await pumpFor(tester, 20);
    expect(service.calls, ['done SPEC-001', 'reopen SPEC-001']);
    expect(byKey('inspector-mark-done'), findsOneWidget);
    await tester.tap(byKey('board-filter-hide-done'));
    await pumpFor(tester, 20);
    expect(chipText(tester), 'Ocultar concluídas · 1');

    // In Colunas the finished spec is in Feito.
    await tester.tap(byKey('board-filter-hide-done'));
    await pumpFor(tester, 20);
    await tester.tap(byKey('board-view-columns'));
    await pumpFor(tester, 20);
    expect(
      find.descendant(
        of: byKey('board-column-done'),
        matching: byKey('board-card-SPEC-002'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: byKey('board-column-backlog'),
        matching: byKey('board-card-SPEC-001'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a running spec offers neither action (R9)', (tester) async {
    await pump(tester, const [
      CanvasSpec('SPEC-001', stage: SpecStage.running),
    ]);
    await selectSpec(tester, 'SPEC-001');
    expect(byKey('inspector-mark-done'), findsNothing);
    expect(byKey('inspector-reopen'), findsNothing);
  });

  testWidgets('pending criteria ask before finishing; cancel changes nothing '
      '(R8)', (tester) async {
    final service = await pump(
      tester,
      const [CanvasSpec('SPEC-001')],
      pending: ['a', 'b'],
    );
    await selectSpec(tester, 'SPEC-001');
    await tester.tap(byKey('inspector-mark-done'));
    await pumpFor(tester, 20);
    expect(byKey('inspector-mark-done-confirm'), findsOneWidget);
    expect(
      find.text('2 critérios de aceite sem marcar. Finalizar mesmo assim?'),
      findsOneWidget,
    );
    await tester.tap(byKey('inspector-mark-done-cancel'));
    await pumpFor(tester, 20);
    expect(service.calls, isEmpty);
    expect(byKey('inspector-mark-done'), findsOneWidget);

    await tester.tap(byKey('inspector-mark-done'));
    await pumpFor(tester, 20);
    await tester.tap(byKey('inspector-mark-done-yes'));
    await pumpFor(tester, 20);
    expect(service.calls, ['done SPEC-001']);
    expect(byKey('inspector-reopen'), findsOneWidget);
  });
}
