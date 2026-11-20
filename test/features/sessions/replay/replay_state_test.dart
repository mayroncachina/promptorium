import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/sessions/replay/replay_state.dart';
import 'package:promptorium/features/sessions/replay/replay_step.dart';

import 'replay_fixtures.dart';

void main() {
  group('replayStateAt (SPEC-082 R6)', () {
    late TimelineBuilder b;
    late List<ReplayStep> steps;

    setUp(() {
      b = TimelineBuilder();
      b.user('faça');
      b.read('/w/a.dart'); // 1
      b.read('/w/a.dart'); // 2
      b.read('/w/t.dart'); // 3
      b.say('vou editar', contextTokens: 82000); // 4
      b.edit('/w/a.dart', 'x', 'y\nz'); // 5
      b.bash('flutter analyze'); // 6
      b.edit('/w/b.dart', 'q', 'r'); // 7: edited without reading
      b.write('/w/novo.dart', 'a\nb'); // 8: new file, no read needed
      b.bash('flutter test', error: true); // 9
      b.compact(); // 10
      b.edit('/w/a.dart', 'y', 'w', error: true); // 11: not applied
      steps = replaySteps(b.items);
    });

    test('already read, with counts', () {
      final s = replayStateAt(steps, 3);
      expect(
        [for (final f in s.read) (f.path, f.reads)],
        [('/w/a.dart', 2), ('/w/t.dart', 1)],
      );
      expect(s.edited, isEmpty);
    });

    test('already edited with the accumulated +/−', () {
      final s = replayStateAt(steps, 11);
      expect(
        [for (final f in s.edited) (f.path, f.added, f.removed)],
        [('/w/a.dart', 2, 1), ('/w/b.dart', 1, 1), ('/w/novo.dart', 2, 0)],
      );
    });

    test('"editou sem ler"', () {
      final s = replayStateAt(steps, 11);
      final byPath = {for (final f in s.edited) f.path: f};
      expect(byPath['/w/a.dart']!.editedWithoutRead, isFalse);
      expect(byPath['/w/b.dart']!.editedWithoutRead, isTrue);
      expect(byPath['/w/novo.dart']!.editedWithoutRead, isFalse);
    });

    test('last command is the last Bash before the step', () {
      expect(replayStateAt(steps, 6).lastCommand, isNull);
      expect(replayStateAt(steps, 7).lastCommand!.target, 'flutter analyze');
      final s = replayStateAt(steps, 10);
      expect(s.lastCommand!.target, 'flutter test');
      expect(s.lastCommand!.outcome, ReplayOutcome.error);
    });

    test('context tokens and compactions', () {
      expect(
        replayStateAt(steps, 3, context: b.t.contextTokens).contextTokens,
        isNull,
      );
      final s = replayStateAt(steps, 10, context: b.t.contextTokens);
      expect(s.contextTokens, 82000);
      expect(s.compactions, 1);
      expect(replayStateAt(steps, 9).compactions, 0);
    });
  });

  group('SPEC-087 R6: leitura do ponto, compactação no histórico', () {
    test(
      'o ponto usa a sua leitura; depois de compactar, aguardando medição',
      () {
        final b = TimelineBuilder();
        b.user('faça');
        b.read('/w/a.dart');
        b.say('lendo', contextTokens: 171000);
        b.bash('flutter test');
        b.compact();
        b.bash('git status');
        b.say('seguindo', contextTokens: 46000);
        b.bash('git diff');
        final steps = replaySteps(b.items);
        final ctx = b.t.context.snapshot;
        ReplayState at(int i) =>
            replayStateAt(steps, i, context: b.t.contextTokens, ctx: ctx);
        // Steps: 0 user, 1 read, 2 answer, 3 run, 4 compaction, 5 run,
        // 6 answer, 7 run.
        expect(at(3).contextTokens, 171000);
        expect(at(3).compactedSince, isFalse);
        expect(at(4).contextTokens, 171000, reason: 'a própria compactação');
        expect(at(5).compactedSince, isTrue);
        expect(at(5).contextTokens, isNull);
        expect(at(7).contextTokens, 46000);
        expect(at(7).compactedSince, isFalse);
        // The current state of the session (46 mil) never leaks into an
        // earlier point.
        expect(at(3).reading!.tokens, 171000);
      },
    );
  });

  group('filters (R9)', () {
    test('kinds, errors, search and file', () {
      final b = TimelineBuilder();
      b.read('/w/a.dart');
      b.edit('/w/a.dart', 'x', 'y');
      b.bash('flutter test', error: true);
      b.bash('git status');
      final steps = replaySteps(b.items);
      List<int> pick(bool Function(ReplayStep) f) => [
        for (final s in steps)
          if (f(s)) s.index,
      ];
      expect(pick((s) => replayStepVisible(s, filter: ReplayFilter.commands)), [
        2,
        3,
      ]);
      expect(pick((s) => replayStepVisible(s, filter: ReplayFilter.errors)), [
        2,
      ]);
      expect(pick((s) => replayStepVisible(s, query: 'GIT')), [3]);
      expect(pick((s) => replayStepVisible(s, file: '/w/a.dart')), [0, 1]);
    });
  });
}
