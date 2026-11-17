import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/sessions/replay/replay_step.dart';
import 'package:promptorium/features/sessions/timeline.dart';

import 'replay_fixtures.dart';

void main() {
  group('replaySteps (SPEC-082 R2)', () {
    test('each tool gets its kind and lane', () {
      final b = TimelineBuilder();
      const kinds = {
        'Read': ReplayKind.read,
        'Grep': ReplayKind.read,
        'Glob': ReplayKind.read,
        'LS': ReplayKind.read,
        'Edit': ReplayKind.edit,
        'MultiEdit': ReplayKind.edit,
        'Write': ReplayKind.edit,
        'NotebookEdit': ReplayKind.edit,
        'Bash': ReplayKind.run,
        'WebFetch': ReplayKind.web,
        'WebSearch': ReplayKind.web,
        'Task': ReplayKind.subagent,
        'Agent': ReplayKind.subagent,
        'TodoWrite': ReplayKind.plan,
        'ExitPlanMode': ReplayKind.plan,
        'mcp__github__get_me': ReplayKind.other,
      };
      for (final name in kinds.keys) {
        b.tool(name, {'file_path': '/w/a.dart'});
      }
      final steps = replaySteps(b.items);
      expect([for (final s in steps) s.kind], kinds.values.toList());
      expect(steps.first.lane, ReplayLane.read);
      expect(steps[4].lane, ReplayLane.edit);
      expect(steps[8].lane, ReplayLane.run);
      expect(steps[13].lane, ReplayLane.talk);
    });

    test('conversation steps, targets relative to the root, turns', () {
      final b = TimelineBuilder();
      b.note('Sessão iniciada');
      b.user('Implemente a R2\ncom cuidado');
      b.think('vou ler primeiro');
      b.read('/w/lib/a.dart');
      b.say('Pronto.');
      b.user('o gate reprovou: o CI fica verde');
      b.bash('flutter test');
      final steps = replaySteps(b.items, root: '/w');
      expect(
        [for (final s in steps) s.kind],
        [
          ReplayKind.mark,
          ReplayKind.user,
          ReplayKind.thinking,
          ReplayKind.read,
          ReplayKind.assistant,
          ReplayKind.user,
          ReplayKind.run,
        ],
      );
      expect([for (final s in steps) s.turn], [1, 1, 1, 1, 1, 2, 2]);
      expect(steps[1].target, 'Implemente a R2');
      expect(steps[3].target, 'lib/a.dart');
      expect(steps[6].target, 'flutter test');
      final starts = turnStarts(steps);
      expect(starts[2]!.target, 'o gate reprovou: o CI fica verde');
    });

    test('duration until the result or the next step; outcomes', () {
      final b = TimelineBuilder();
      b.bash('flutter test', took: const Duration(seconds: 48), error: true);
      b.say('falhou');
      final denied = b.tool('Edit', {
        'file_path': '/w/pubspec.yaml',
        'old_string': 'a',
        'new_string': 'b',
      }, result: null);
      b.denied(denied);
      b.tool('Bash', {'command': 'sleep 1'}, result: null);
      final steps = replaySteps(b.items);
      expect(steps[0].duration, const Duration(seconds: 48));
      expect(steps[0].outcome, ReplayOutcome.error);
      expect(steps[0].isProblem, isTrue);
      expect(steps[1].duration, const Duration(seconds: 1));
      expect(steps[2].outcome, ReplayOutcome.denied);
      expect(steps[2].isProblem, isTrue);
      expect(steps[3].outcome, ReplayOutcome.pending);
    });

    test('edit stats', () {
      final b = TimelineBuilder();
      b.edit('/w/a.dart', 'x\ny', 'a\nb\nc\nd\ne\nf');
      final s = replaySteps(b.items).single;
      expect((s.added, s.removed), (6, 2));
      expect(s.statsLabel, '+6 −2');
    });

    test('app marks: gate, compaction, resume, error', () {
      final b = TimelineBuilder();
      b.note('Verificação aprovada: ✓ commit');
      b.note('Verificação falhou: ✗ testes (12 s)', error: true);
      b.compact();
      b.note('Sessão retomada (--resume)');
      b.note('Falha ao iniciar claude: x', error: true);
      final steps = replaySteps(b.items);
      expect(
        [for (final s in steps) s.mark],
        [
          ReplayMarkKind.gatePassed,
          ReplayMarkKind.gateFailed,
          ReplayMarkKind.compaction,
          ReplayMarkKind.resume,
          ReplayMarkKind.error,
        ],
      );
      expect(steps[1].isProblem, isTrue);
      expect(steps[4].isProblem, isTrue);
      expect(steps[0].isProblem, isFalse);
      expect(steps[2].mark!.isFlag, isTrue);
      expect(steps.every((s) => s.lane == null), isTrue);
    });

    test('a subagent is one step with its own steps (P7)', () {
      final b = TimelineBuilder();
      final task = b.tool('Task', {
        'description': 'ache onde o CI é lido',
        'prompt': 'procure',
      }, result: null);
      b.tool('Grep', {'pattern': 'ciFixer'}, parent: task);
      b.read('/w/a.dart');
      final steps = replaySteps(b.items);
      expect(steps, hasLength(2));
      expect(steps[0].kind, ReplayKind.subagent);
      expect(steps[0].children, hasLength(1));
      expect(steps[0].children.single.parent, same(steps[0]));
      expect(steps[0].children.single.kind, ReplayKind.read);
      expect(flattenSteps(steps).length, 3);
    });

    test('long pauses are cut (P4)', () {
      final b = TimelineBuilder();
      b.read('/w/a.dart');
      b.pause(const Duration(hours: 2));
      b.read('/w/b.dart');
      final steps = replaySteps(b.items);
      final pauses = longPauses(steps);
      expect(pauses.keys, [1]);
      expect(shortDuration(pauses[1]!), '2 h');
    });

    test('the compaction notice is in the Timeline', () {
      final b = TimelineBuilder();
      b.compact();
      expect((b.items.single as NoticeItem).text, Timeline.compactionNotice);
    });
  });
}
