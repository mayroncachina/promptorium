import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/autopilot.dart';
import 'package:promptorium/features/board/board_screen.dart';

import 'canvas_fixture.dart';

/// On from the start, without starting sessions.
class _OnPilot extends Autopilot {
  @override
  Set<int> build() => {1};

  @override
  Future<void> tick(int workspaceId) async {}
}

/// SPEC-064 R4, R5: while "Executar tudo" runs.
void main() {
  Future<void> pump(WidgetTester tester, List<CanvasSpec> specs) async {
    await pumpCanvas(
      tester,
      specs,
      size: const Size(1800, 900),
      view: BoardView.columns,
      overrides: (db) => [autopilotProvider.overrideWith(_OnPilot.new)],
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('R4, R5: the waiting card says for whom, and the bar sums up', (
    tester,
  ) async {
    await pump(tester, const [
      CanvasSpec('SPEC-001', stage: SpecStage.running),
      CanvasSpec('SPEC-002', deps: ['SPEC-001']),
      CanvasSpec('SPEC-003'),
    ]);
    expect(find.text('espera SPEC-001'), findsOneWidget);
    expect(find.text('bloqueada por SPEC-001'), findsNothing);
    expect(
      find.textContaining('Executando · 1 rodando · 1 esperando'),
      findsOneWidget,
    );
  });

  testWidgets('R4: a dependency in Review releases with Review', (
    tester,
  ) async {
    await pump(tester, const [
      CanvasSpec('SPEC-001', stage: SpecStage.review),
      CanvasSpec('SPEC-002', deps: ['SPEC-001']),
    ]);
    expect(find.text('espera SPEC-001'), findsNothing);
    expect(
      find.textContaining('Executando · 0 rodando · 0 esperando'),
      findsOneWidget,
    );
  });
}
