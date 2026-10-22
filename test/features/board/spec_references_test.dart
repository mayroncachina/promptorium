import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/spec_references.dart';

import 'canvas_fixture.dart';

/// SPEC-008 R3: agents and skills referenced by the selected spec.
void main() {
  const specs = [
    CanvasSpec(
      'SPEC-001',
      agent: 'implementador',
      skills: ['simplify', 'code-review', 'grill-me', 'deploy', 'docs'],
    ),
    CanvasSpec('SPEC-002', agent: 'spec-reviewer', skills: ['simplify']),
  ];

  testWidgets('only the selected spec shows its agents and skills; with no '
      'selection none is shown', (tester) async {
    await pumpCanvas(tester, specs);
    expect(byKey('canvas-ref-agent-implementador'), findsNothing);
    expect(byKey('canvas-ref-skill-simplify'), findsNothing);

    await selectSpec(tester, 'SPEC-002');
    expect(byKey('canvas-ref-agent-spec-reviewer'), findsOneWidget);
    expect(byKey('canvas-ref-skill-simplify'), findsOneWidget);
    expect(byKey('canvas-ref-agent-implementador'), findsNothing);
    // "simplify" is used by both specs on the board.
    expect(find.text('2 specs'), findsOneWidget);
  });

  testWidgets('5 skills show 3 and "+2 mais"; tapping it shows the 5 and '
      'tapping again goes back to 3', (tester) async {
    await pumpCanvas(tester, specs);
    await selectSpec(tester, 'SPEC-001');
    int skills() => find
        .byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('canvas-ref-skill'),
        )
        .evaluate()
        .length;
    expect(skills(), 3);
    expect(find.text('+2 mais'), findsOneWidget);
    await tester.tap(byKey('canvas-more-skill'));
    await pumpFor(tester, 20);
    expect(skills(), 5);
    expect(find.text('recolher'), findsOneWidget);
    await tester.tap(byKey('canvas-more-skill'));
    await pumpFor(tester, 20);
    expect(skills(), 3);
  });

  testWidgets('skills come only from the Skill tool in the sessions of the '
      'spec; skills only listed by system/init do not count', (tester) async {
    final (c, db) = await pumpCanvas(tester, specs);
    final spec = (await tester.runAsync(
      () => c.read(specsRepoProvider).watchByWorkspace(1).first,
    ))!.firstWhere((s) => s.code == 'SPEC-002');
    await tester.runAsync(
      () => db
          .into(db.sessionEvents)
          .insert(
            SessionEventsCompanion.insert(
              sessionId: 'sess-SPEC-002',
              seq: 99,
              type: 'system',
              json: jsonEncode({
                'type': 'system',
                'subtype': 'init',
                'skills': ['only-available'],
              }),
            ),
          ),
    );
    final refs = await tester.runAsync(
      () => c.read(specReferencesProvider(spec.id).future),
    );
    expect(refs!.agents, {'spec-reviewer'});
    expect(refs.skills, {'simplify'});
  });
}
