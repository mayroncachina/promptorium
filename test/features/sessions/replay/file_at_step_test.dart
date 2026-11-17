import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/sessions/replay/file_at_step.dart';
import 'package:promptorium/features/sessions/replay/replay_step.dart';

import 'replay_fixtures.dart';

const _base = 'a\nb\nc\n';

void main() {
  group('fileAtStep (SPEC-082 R7)', () {
    test('Edit, MultiEdit and Write in order over the base', () {
      final b = TimelineBuilder();
      b.edit('/w/f.txt', 'b', 'B1\nB2');
      b.tool('MultiEdit', {
        'file_path': '/w/f.txt',
        'edits': [
          {'old_string': 'a', 'new_string': 'A'},
          {'old_string': 'c', 'new_string': 'C'},
        ],
      });
      b.write('/w/f.txt', 'novo\n');
      final steps = replaySteps(b.items);
      final edits = editsOf(steps, '/w/f.txt');
      expect(edits, hasLength(3));
      const base = FileBase(text: _base, source: FileBaseSource.startSha);

      final first = fileAtStep(base: base, edits: edits, target: edits[0]);
      expect(first.text, 'a\nB1\nB2\nc\n');
      expect(first.highlighted, {2, 3});

      final second = fileAtStep(base: base, edits: edits, target: edits[1]);
      expect(second.text, 'A\nB1\nB2\nC\n');
      expect(second.highlighted, {1, 4});

      final third = fileAtStep(base: base, edits: edits, target: edits[2]);
      expect(third.text, 'novo\n');
    });

    test('a Write needs no base', () {
      final b = TimelineBuilder();
      b.write('/w/f.txt', 'x\ny');
      b.edit('/w/f.txt', 'y', 'z');
      final edits = editsOf(replaySteps(b.items), '/w/f.txt');
      final r = fileAtStep(base: null, edits: edits, target: edits[1]);
      expect(r.text, 'x\nz');
      expect(r.highlighted, {2});
    });

    test('no base: the reason', () {
      final b = TimelineBuilder();
      b.edit('/w/f.txt', 'b', 'B');
      final edits = editsOf(replaySteps(b.items), '/w/f.txt');
      final r = fileAtStep(base: null, edits: edits, target: edits[0]);
      expect(r.ok, isFalse);
      expect(r.reason, contains('Não há conteúdo anterior'));
    });

    test('an old_string that is not there gives the reason', () {
      final b = TimelineBuilder();
      b.edit('/w/f.txt', 'b', 'B');
      b.edit('/w/f.txt', 'nada disso', 'X');
      final edits = editsOf(replaySteps(b.items), '/w/f.txt');
      const base = FileBase(text: _base, source: FileBaseSource.baseBranch);
      final r = fileAtStep(base: base, edits: edits, target: edits[1]);
      expect(r.ok, isFalse);
      expect(r.reason, contains('não se aplica'));
      expect(r.reason, contains('passo 2'));
    });

    test('failed and denied edits are skipped; the target says so', () {
      final b = TimelineBuilder();
      b.edit('/w/f.txt', 'b', 'B', error: true);
      b.edit('/w/f.txt', 'c', 'C');
      final edits = editsOf(replaySteps(b.items), '/w/f.txt');
      const base = FileBase(text: _base, source: FileBaseSource.startSha);
      expect(
        fileAtStep(base: base, edits: edits, target: edits[1]).text,
        'a\nb\nC\n',
      );
      expect(
        fileAtStep(base: base, edits: edits, target: edits[0]).ok,
        isFalse,
      );
    });

    test('a transcript base starts at its own edit', () {
      final b = TimelineBuilder();
      b.edit('/w/f.txt', 'b', 'B');
      b.edit('/w/f.txt', 'formatado', 'F');
      final edits = editsOf(replaySteps(b.items), '/w/f.txt');
      const base = FileBase(
        text: 'formatado\n',
        source: FileBaseSource.transcript,
        fromStep: 1,
      );
      expect(
        fileAtStep(base: base, edits: edits, target: edits[1]).text,
        'F\n',
      );
    });
  });

  group('FileBaseResolver (P2)', () {
    late List<ReplayStep> edits;
    final shown = <String>[];

    setUp(() {
      shown.clear();
      final b = TimelineBuilder();
      b.edit('/w/lib/f.dart', 'b', 'B');
      b.edit('/w/lib/f.dart', 'c', 'C');
      edits = editsOf(replaySteps(b.items), '/w/lib/f.dart');
    });

    Future<String?> show(String rev, String path) async {
      shown.add('$rev:$path');
      return rev == 'missing' ? null : 'texto em $rev';
    }

    test('the transcript first, at the latest edit it has', () async {
      final r = FileBaseResolver(
        originalFiles: () async => {edits[0].tool!.id: 'orig'},
        showAt: show,
        startSha: 'abc',
        root: '/w',
      );
      final base = await r.resolve('/w/lib/f.dart', edits, edits[1]);
      expect(base!.source, FileBaseSource.transcript);
      expect((base.text, base.fromStep), ('orig', 0));
      expect(shown, isEmpty);
    });

    test('then the startSha, with the path relative to the root', () async {
      final r = FileBaseResolver(
        originalFiles: () async => const {},
        showAt: show,
        startSha: 'abcdef0123',
        baseBranch: 'main',
        root: '/w',
      );
      final base = await r.resolve('/w/lib/f.dart', edits, edits[1]);
      expect(base!.source, FileBaseSource.startSha);
      expect(base.label, 'início da etapa (abcdef0)');
      expect(shown, ['abcdef0123:lib/f.dart']);
    });

    test('then the base branch (merge-base)', () async {
      final r = FileBaseResolver(
        originalFiles: () => throw Exception('sem jsonl'),
        showAt: show,
        baseBranch: 'main',
        baseRef: () async => 'mb1',
        root: '/w',
      );
      final base = await r.resolve('/w/lib/f.dart', edits, edits[0]);
      expect(base!.source, FileBaseSource.baseBranch);
      expect(base.text, 'texto em mb1');
    });

    test('nothing: null', () async {
      final r = FileBaseResolver(
        originalFiles: () async => const {},
        showAt: show,
        root: '/w',
      );
      expect(await r.resolve('/w/lib/f.dart', edits, edits[0]), isNull);
    });
  });

  group('whoWroteLine (R8, P5)', () {
    test('the last edit whose new text has the line', () {
      final b = TimelineBuilder();
      b.edit('/w/f.dart', 'a', '  continue;\n  x();');
      b.edit('/w/f.dart', 'b', 'continue;');
      b.edit('/w/g.dart', 'b', 'continue;');
      b.edit('/w/f.dart', 'c', 'continue;', error: true);
      final steps = replaySteps(b.items);
      final who = whoWroteLine(steps, '/w/f.dart', '    continue;');
      expect(who!.edit!.index, 1);
      expect(whoWroteLine(steps, '/w/f.dart', 'x();')!.edit!.index, 0);
    });

    test('no edit: "veio de um comando", with the likely command', () {
      final b = TimelineBuilder();
      b.edit('/w/lib/f.dart', 'a', 'b');
      b.bash('git status');
      b.bash('dart format lib/');
      b.bash('ls');
      final steps = replaySteps(b.items);
      final who = whoWroteLine(steps, '/w/lib/f.dart', '_log.add(run);');
      expect(who!.fromCommand, isTrue);
      expect(who.command!.target, 'dart format lib/');
      expect(whoWroteLine(steps, '/w/lib/f.dart', '   '), isNull);
    });

    test('no command at all', () {
      final b = TimelineBuilder();
      b.edit('/w/f.dart', 'a', 'b');
      final who = whoWroteLine(replaySteps(b.items), '/w/f.dart', 'zzz');
      expect((who!.fromCommand, who.command), (true, null));
    });

    test('edits of a subagent count', () {
      final b = TimelineBuilder();
      final task = b.tool('Task', {'prompt': 'x'}, result: null);
      b.edit('/w/f.dart', 'a', 'linha do sub', parent: task);
      final steps = replaySteps(b.items);
      final who = whoWroteLine(steps, '/w/f.dart', 'linha do sub');
      expect(who!.edit!.parent, same(steps.single));
    });
  });
}
