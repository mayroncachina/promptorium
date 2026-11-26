import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/core/codex/codex_neutral.dart';
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

  group('SPEC-110 · estado com o Codex', () {
    test('R1: "Já leu" conta as leituras por comando e "editou sem ler" some '
        'quando o arquivo foi lido por sed -n', () {
      final b = TimelineBuilder()..user('x');
      b.turn('t-1');
      b.command('c1', 'sed -n 1,80p lib/t.dart', [
        readAction('/w/lib/t.dart', command: 'sed -n 1,80p lib/t.dart'),
      ]);
      b.command('c2', 'rg frete lib', [
        {
          'type': 'search',
          'command': 'rg frete lib',
          'query': 'frete',
          'path': 'lib/',
        },
      ]);
      // Uma leitura que falhou não conta.
      b.command('c3', 'cat lib/r.dart', [readAction('/w/lib/r.dart')], exit: 1);
      b.command('c4', 'cat lib/t.dart && dart test', [
        readAction('/w/lib/t.dart'),
        {'type': 'unknown', 'command': 'dart test'},
      ], exit: 1);
      b.patch('p1', [
        update('/w/lib/t.dart', '@@ -1 +1 @@\n-a\n+b\n'),
        update('/w/lib/r.dart', '@@ -1 +1 @@\n-a\n+b\n'),
        {
          'path': '/w/lib/n.dart',
          'kind': {'type': 'add'},
          'diff': 'x\n',
        },
      ]);
      final steps = replaySteps(b.items, root: '/w');
      final st = replayStateAt(steps, steps.length - 1, root: '/w');
      final t = st.read.firstWhere((f) => f.path == '/w/lib/t.dart');
      expect(t.reads, 2);
      expect(t.via, ['sed', 'cat']);
      final folder = st.read.singleWhere((f) => f.folder);
      expect(folder.path, '/w/lib');
      expect(folder.via, ['rg']);
      expect(st.read.any((f) => f.path == '/w/lib/r.dart'), isFalse);
      expect(
        {for (final f in st.edited) f.path: f.editedWithoutRead},
        {'/w/lib/t.dart': false, '/w/lib/r.dart': true, '/w/lib/n.dart': false},
      );
    });

    test('R5: o contexto do ponto vem da leitura do Codex, com a janela dela; '
        'sem leitura, aguardando medição', () {
      final b = TimelineBuilder()..user('x');
      b.turn('t-1');
      b.say('antes');
      void usage(int tokens, int window) => b.codexEvent(
        codexContextUsage({
          'turnId': 't-1',
          'tokenUsage': {
            'last': {'totalTokens': tokens, 'inputTokens': tokens},
            'modelContextWindow': window,
          },
        }, model: 'gpt')!,
      );
      usage(61000, 400000);
      b.say('meio');
      b.codexEvent(
        CompactionEvent.toJson(
          provider: 'codex',
          phase: CompactionEventPhase.completed,
          trigger: 'auto',
          key: 'k1',
        ),
      );
      b.say('compactado');
      usage(9000, 200000);
      b.say('fim');
      final steps = replaySteps(b.items);
      ReplayState at(String text) => replayStateAt(
        steps,
        steps.indexWhere((s) => s.target == text),
        context: b.t.contextTokens,
        ctx: b.t.context.snapshot,
      );
      expect(at('antes').contextTokens, isNull);
      expect(at('antes').measures, isTrue);
      expect(at('meio').contextTokens, 61000);
      expect(at('meio').capacity, 400000);
      expect(at('compactado').compactedSince, isTrue);
      expect(at('compactado').compactions, 1);
      expect(at('fim').contextTokens, 9000);
      expect(at('fim').capacity, 200000);
    });
  });
}
