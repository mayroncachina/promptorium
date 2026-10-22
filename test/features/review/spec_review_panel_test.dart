import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/step_gate.dart';
import 'package:promptorium/features/review/auto_reviewer.dart';
import 'package:promptorium/features/review/widgets/spec_review_panel.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:promptorium/ui/theme/tokens.dart';

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

  group('"Marcar todos" (SPEC-014)', batchTests);
}

/// Criteria of the batch tests: a and b eligible, c awaits the gate
/// ([R1] + verificar:), d has a verificar: but no step, e checked by the
/// gate, f by the reviewer.
const _criteria =
    '- [ ] a\n'
    '- [ ] b\n'
    '- [ ] c [R1] · verificar: true\n'
    '- [ ] d · verificar: true\n'
    '- [ ] e [R1] · verificar: true\n'
    '- [ ] f\n';

typedef _Panel = ({ProviderContainer c, int specId});

void batchTests() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  Future<_Panel> pumpPanel(
    WidgetTester tester, {
    String criteria = _criteria,
    Map<String, String> marks = const {'e [R1]': 'gate', 'f': 'revisor'},
    bool merged = false,
    bool auto = false,
  }) async {
    await tester.pumpWidget(const SizedBox());
    final tmp = Directory.systemTemp.createTempSync('promptorium-batch-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    Directory('${tmp.path}/specs').createSync();
    File('${tmp.path}/specs/SPEC-001.md').writeAsStringSync(
      '---\nid: SPEC-001\n---\n# A\n\n## Requisitos\n\n- R1 · x\n\n'
      '${criteria.isEmpty ? '' : '## Critérios de aceite\n\n$criteria'}',
    );
    final c = ProviderContainer(
      overrides: [databaseOverride(memoryDatabase())],
    );
    addTearDown(c.dispose);
    final id = await tester.runAsync(() async {
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
      for (final MapEntry(key: text, value: by) in marks.entries) {
        await c
            .read(reviewCommentsRepoProvider)
            .setCriterion(s.id, text, checked: true, by: by);
      }
      if (auto) {
        await c
            .read(specsRepoProvider)
            .setReview(s.id, phase: ReviewPhase.auto, rounds: 1);
      }
      return s.id;
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SpecReviewPanel(specId: id!, merged: merged),
          ),
        ),
      ),
    );
    await settle(tester);
    return (c: c, specId: id);
  }

  final master = find.byKey(const ValueKey('review-criteria-master'));
  String label(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('review-criteria-master-label')))
      .data!;
  String summary(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('spec-review-summary')))
      .data!;
  bool enabled(WidgetTester tester) =>
      tester.widget<Focus>(master).canRequestFocus;

  Future<Map<String, String?>> marksOf(WidgetTester tester, _Panel p) async {
    final rows = await tester.runAsync(
      () => p.c.read(reviewCommentsRepoProvider).criteria(p.specId),
    );
    return {
      for (final m in rows!)
        if (m.checked) m.criterion: m.checkedBy,
    };
  }

  Future<void> setMark(
    WidgetTester tester,
    _Panel p,
    String text,
    String by, {
    bool checked = true,
  }) async {
    await tester.runAsync(
      () => p.c
          .read(reviewCommentsRepoProvider)
          .setCriterion(p.specId, text, checked: checked, by: by),
    );
    await settle(tester);
  }

  Future<void> markAll(WidgetTester tester) async {
    await tester.tap(master);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('review-batch-confirm')));
    await settle(tester);
  }

  testWidgets('R1 · the control with its counts and tri-state; none in a '
      'spec without criteria', (tester) async {
    final sem = tester.ensureSemantics();
    final p = await pumpPanel(tester);
    expect(
      label(tester),
      'Marcar todos (2 elegíveis · 2 aguardam a verificação)',
    );
    expect(
      find.byKey(const ValueKey('review-criteria-master-null')),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(master),
      isSemantics(
        hasCheckedState: true,
        isCheckStateMixed: true,
        isEnabled: true,
      ),
    );
    await setMark(tester, p, 'e [R1]', 'gate', checked: false);
    await setMark(tester, p, 'f', 'revisor', checked: false);
    expect(
      find.byKey(const ValueKey('review-criteria-master-false')),
      findsOneWidget,
    );
    for (final t in ['a', 'b', 'c [R1]', 'd', 'e [R1]', 'f']) {
      await setMark(tester, p, t, 'gate');
    }
    expect(
      find.byKey(const ValueKey('review-criteria-master-true')),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(master),
      isSemantics(hasCheckedState: true, isChecked: true),
    );
    sem.dispose();

    await pumpPanel(tester, criteria: '', marks: const {});
    expect(find.byKey(const ValueKey('spec-review-panel')), findsOneWidget);
    expect(master, findsNothing);
  });

  testWidgets('R2/R3 · confirmation with the counts; cancel changes nothing, '
      'confirm checks only the eligible ones as humano', (tester) async {
    final p = await pumpPanel(tester);
    expect(find.textContaining('· aguarda a verificação'), findsOneWidget);
    expect(
      find.textContaining('sem etapa: o gate não o marca'),
      findsOneWidget,
    );
    await tester.tap(master);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('Marcar 2 critérios como verificados por você?'),
      findsOneWidget,
    );
    expect(find.textContaining('2 ficam de fora'), findsOneWidget);
    expect(find.text('Marcar 2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('review-batch-cancel')));
    await settle(tester);
    expect(await marksOf(tester, p), {'e [R1]': 'gate', 'f': 'revisor'});

    await markAll(tester);
    expect(await marksOf(tester, p), {
      'a': 'humano',
      'b': 'humano',
      'e [R1]': 'gate',
      'f': 'revisor',
    });
    expect(find.text('2 critérios marcados por você'), findsOneWidget);
    // c and d stay out of the batch but can be checked one by one.
    expect(label(tester), 'Desmarcar os meus (2 · 2 aguardam a verificação)');
    await tester.tap(find.byKey(const ValueKey('review-criterion-3')));
    await settle(tester);
    expect((await marksOf(tester, p))['d'], 'humano');
    expect(tester.takeException(), isNull);
  });

  testWidgets('R4 · "Desfazer" unchecks only the batch still by humano; the '
      'summary follows each step', (tester) async {
    final p = await pumpPanel(
      tester,
      criteria: '- [ ] a\n- [ ] b\n- [ ] c\n',
      marks: const {},
    );
    expect(summary(tester), contains('0/3 critérios'));
    expect(
      await tester.runAsync(
        () => p.c.read(pendingCriteriaProvider(p.specId).future),
      ),
      hasLength(3),
    );
    await markAll(tester);
    expect(summary(tester), contains('3/3 critérios'));
    expect(
      await tester.runAsync(
        () => p.c.read(pendingCriteriaProvider(p.specId).future),
      ),
      isEmpty,
    );
    expect(find.text('3 critérios marcados por você'), findsOneWidget);
    // The gate checks b again meanwhile: undo keeps it.
    await setMark(tester, p, 'b', 'gate');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Desfazer'));
    await settle(tester);
    expect(await marksOf(tester, p), {'b': 'gate'});
    expect(summary(tester), contains('1/3 critérios'));
    expect(
      await tester.runAsync(
        () => p.c.read(pendingCriteriaProvider(p.specId).future),
      ),
      ['a', 'c'],
    );
  });

  testWidgets('R4 · a single check drops the undo of the batch', (
    tester,
  ) async {
    final p = await pumpPanel(
      tester,
      criteria: '- [ ] a\n- [ ] b\n- [ ] c\n',
      marks: const {},
    );
    await markAll(tester);
    final undo = tester.widget<SnackBarAction>(find.byType(SnackBarAction));
    await tester.tap(find.byKey(const ValueKey('review-criterion-0')));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('3 critérios marcados por você'), findsNothing);
    undo.onPressed();
    await settle(tester);
    expect(await marksOf(tester, p), {'b': 'humano', 'c': 'humano'});
  });

  testWidgets('R4 · another item of the queue drops the undo of the batch', (
    tester,
  ) async {
    final p = await pumpPanel(
      tester,
      criteria: '- [ ] a\n- [ ] b\n',
      marks: const {},
    );
    await markAll(tester);
    final undo = tester.widget<SnackBarAction>(find.byType(SnackBarAction));
    // The Review keys its main pane by session: the panel is rebuilt.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: p.c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: SizedBox()),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    undo.onPressed();
    await settle(tester);
    expect(await marksOf(tester, p), {'a': 'humano', 'b': 'humano'});
  });

  testWidgets('R4 · the notice leaves after 8 s and "Desfazer" then does '
      'nothing', (tester) async {
    final p = await pumpPanel(
      tester,
      criteria: '- [ ] a\n- [ ] b\n',
      marks: const {},
    );
    await markAll(tester);
    final undo = tester.widget<SnackBarAction>(find.byType(SnackBarAction));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('2 critérios marcados por você'), findsNothing);
    undo.onPressed();
    await settle(tester);
    expect(await marksOf(tester, p), {'a': 'humano', 'b': 'humano'});
  });

  testWidgets('R5 · with no eligible one: "Desmarcar os meus" removes only '
      'the humano marks, with no confirmation', (tester) async {
    final p = await pumpPanel(
      tester,
      marks: const {
        'a': 'humano',
        'b': 'humano',
        'e [R1]': 'gate',
        'f': 'revisor',
      },
    );
    expect(label(tester), 'Desmarcar os meus (2 · 2 aguardam a verificação)');
    await tester.tap(master);
    await settle(tester);
    expect(find.byKey(const ValueKey('review-batch-dialog')), findsNothing);
    expect(await marksOf(tester, p), {'e [R1]': 'gate', 'f': 'revisor'});
    expect(
      label(tester),
      'Marcar todos (2 elegíveis · 2 aguardam a verificação)',
    );
  });

  testWidgets('R5 · nothing to check or uncheck: disabled, with the reason', (
    tester,
  ) async {
    final p = await pumpPanel(
      tester,
      criteria: '- [ ] a [R1] · verificar: true\n- [x] b\n',
      marks: const {},
    );
    expect(label(tester), 'Nada a marcar em lote · 1 aguarda a verificação');
    expect(enabled(tester), isFalse);
    await tester.tap(master);
    await settle(tester);
    expect(find.byKey(const ValueKey('review-batch-dialog')), findsNothing);
    await setMark(tester, p, 'a [R1]', 'gate');
    expect(label(tester), 'Todos marcados · nada meu para desmarcar');
    expect(enabled(tester), isFalse);
  });

  testWidgets('R6 · reached by Tab, focus decoration, Space opens the '
      'confirmation and Enter confirms', (tester) async {
    final p = await pumpPanel(tester, criteria: '- [ ] a\n', marks: const {});
    Color border() =>
        ((tester
                            .widget<Container>(
                              find.byKey(
                                const ValueKey('review-criteria-master-box'),
                              ),
                            )
                            .decoration!
                        as BoxDecoration)
                    .border!
                as Border)
            .top
            .color;
    expect(border(), isNot(AppColors.amber));
    final node = Focus.of(
      tester.element(
        find.descendant(of: master, matching: find.byType(Opacity)).first,
      ),
    );
    for (var i = 0; i < 10 && !node.hasFocus; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(node.hasFocus, isTrue);
    expect(border(), AppColors.amber);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('Marcar 1 critério como verificado por você?'),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    expect(await marksOf(tester, p), {'a': 'humano'});
  });

  testWidgets('R6 · disabled with the session merged or the reviewer working', (
    tester,
  ) async {
    await pumpPanel(tester, merged: true);
    expect(enabled(tester), isFalse);
    await tester.tap(master);
    await settle(tester);
    expect(find.byKey(const ValueKey('review-batch-dialog')), findsNothing);

    await pumpPanel(tester, auto: true);
    expect(find.byKey(const ValueKey('review-auto-label')), findsOneWidget);
    expect(enabled(tester), isFalse);
  });
}
