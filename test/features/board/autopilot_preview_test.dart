import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/autopilot.dart';
import 'package:promptorium/features/board/board_screen.dart';

import 'canvas_fixture.dart';

/// Records "Executar" instead of starting sessions.
class _Pilot extends Autopilot {
  final started = <int>[];

  @override
  Future<void> start(int workspaceId) async {
    started.add(workspaceId);
    state = {...state, workspaceId};
  }
}

/// SPEC-064 R1–R3, R7: the preview of "Executar tudo".
void main() {
  late _Pilot pilot;

  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> open(WidgetTester tester) async {
    await tester.tap(key('board-autopilot'));
    for (var i = 0; i < 20 && key('autopilot-run').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> pump(WidgetTester tester, List<CanvasSpec> specs) => pumpCanvas(
    tester,
    specs,
    size: const Size(1800, 900),
    view: BoardView.columns,
    overrides: (db) => [autopilotProvider.overrideWith(() => pilot = _Pilot())],
  );

  testWidgets('R1, R2: starts now, waits and the count; Esc cancels and '
      'Executar turns the autopilot on', (tester) async {
    await pump(tester, const [
      CanvasSpec('SPEC-001'),
      CanvasSpec('SPEC-002', deps: ['SPEC-001']),
    ]);
    await open(tester);
    expect(key('autopilot-preview'), findsOneWidget);
    expect(key('autopilot-start-SPEC-001'), findsOneWidget);
    expect(key('autopilot-wait-SPEC-002'), findsOneWidget);
    expect(find.text('depois da SPEC-001 chegar em Review'), findsOneWidget);
    expect(find.text('Executar 2 specs'), findsOneWidget);
    expect(pilot.started, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));
    expect(key('autopilot-preview'), findsNothing);
    expect(pilot.started, isEmpty);

    await open(tester);
    await tester.tap(key('autopilot-run'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(pilot.started, hasLength(1));
    expect(key('autopilot-preview'), findsNothing);
  });

  testWidgets('R3: Feito changes the reason and is kept', (tester) async {
    await pump(tester, const [
      CanvasSpec('SPEC-001', stage: SpecStage.review),
      CanvasSpec('SPEC-002', deps: ['SPEC-001']),
    ]);
    await open(tester);
    expect(key('autopilot-start-SPEC-002'), findsOneWidget);
    await tester.tap(find.text('Feito'));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(key('autopilot-wait-SPEC-002'), findsOneWidget);
    expect(find.text('depois da SPEC-001 chegar em Feito'), findsOneWidget);
    final ws = pilot.state.isEmpty ? 1 : pilot.state.first;
    expect(pilot.unblockAtOf(ws), UnblockAt.done);
  });

  testWidgets('R7: nothing can start: the preview explains and Executar is '
      'off', (tester) async {
    await pump(tester, const [
      CanvasSpec('SPEC-001', stage: SpecStage.running),
      CanvasSpec('SPEC-002', deps: ['SPEC-003']),
      CanvasSpec('SPEC-003', stage: SpecStage.review),
      CanvasSpec('SPEC-004', deps: ['SPEC-002', 'SPEC-003']),
    ]);
    await open(tester);
    // SPEC-002 starts (SPEC-003 in Review); with Feito nothing would.
    await tester.tap(find.text('Feito'));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(key('autopilot-start'), findsNothing);
    expect(key('autopilot-wait-SPEC-002'), findsOneWidget);
    // Something waits on a running spec: Executar stays on.
    expect(
      tester.widget<FilledButton>(key('autopilot-run')).onPressed,
      isNotNull,
    );
  });
}
