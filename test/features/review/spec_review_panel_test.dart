import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/step_gate.dart';
import 'package:promptorium/features/review/widgets/spec_review_panel.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';

void main() {
  testWidgets('checks of each step, criteria checklist (a tap checks it) '
      'and the review rounds', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('promptorium-panel-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    Directory('${tmp.path}/specs').createSync();
    File('${tmp.path}/specs/SPEC-001.md').writeAsStringSync(
      '---\nid: SPEC-001\n---\n# A\n\n## Requisitos\n\n- R1 · x\n\n'
      '## Critérios de aceite\n\n- [ ] funciona [R1] · verificar: true\n'
      '- [x] documentado\n',
    );
    final db = memoryDatabase();
    final c = ProviderContainer(overrides: [databaseOverride(db)]);
    addTearDown(c.dispose);
    final spec = await tester.runAsync(() async {
      final ws = await c
          .read(workspacesRepoProvider)
          .add(path: tmp.path, name: 'w');
      final s = await c
          .read(specsRepoProvider)
          .insert(
            workspaceId: ws.id,
            code: 'SPEC-001',
            title: 'A',
            path: 'specs/SPEC-001.md',
            requirements: const [(id: 'R1', text: 'x')],
          );
      await c.read(specStepsRepoProvider).set(s.id, 'R1', StepStatus.done);
      await c.read(specStepsRepoProvider).setGate(
        s.id,
        ['R1'],
        report: GateReport(
          at: DateTime(2026),
          checks: const [
            GateCheck(name: 'commit', ok: true),
            GateCheck(name: 'testes', ok: true),
          ],
        ).encode(),
      );
      await c.read(reviewCommentsRepoProvider).insertAll([
        ReviewCommentsCompanion.insert(
          specId: s.id,
          round: 1,
          author: 'revisor',
          body: 'Falta teste.',
          verdict: const Value('corrigir'),
          commitSha: const Value('abcdef123456'),
        ),
        ReviewCommentsCompanion.insert(
          specId: s.id,
          round: 1,
          author: 'revisor',
          path: const Value('lib/a.dart'),
          line: const Value(3),
          body: 'sem teste',
          severity: const Value('alta'),
        ),
      ]);
      return s;
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: SpecReviewPanel(specId: spec!.id)),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.byKey(const ValueKey('review-gate-R1-testes')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('spec-review-summary')))
          .data,
      'SPEC-001 · verificação e critérios · 1/2 critérios · 1 rodada(s)',
    );
    expect(
      find.textContaining('Rodada 1 · Revisor automático'),
      findsOneWidget,
    );
    expect(find.textContaining('abcdef1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('review-criterion-0')));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    final marks = await tester.runAsync(
      () => c.read(reviewCommentsRepoProvider).criteria(spec.id),
    );
    expect(marks!.single.checkedBy, 'humano');
    expect(
      await tester.runAsync(
        () => c.read(pendingCriteriaProvider(spec.id).future),
      ),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });
}
