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

  group('SPEC-110 · base pelo ponto de restauração (R2)', () {
    const before = 'l1\nl2\nl3\nl4\n';
    late TimelineBuilder b;
    final shown = <String>[];

    setUp(() {
      shown.clear();
      b = TimelineBuilder();
    });

    Future<String?> show(String rev, String path) async {
      shown.add('$rev:$path');
      return switch ('$rev:$path') {
        'p1:lib/f.dart' => before,
        'p2:lib/f.dart' => 'l1\nL2\nl3\nl4\n',
        'p1:lib/velho.dart' => 'um\ndois\n',
        _ => null,
      };
    }

    FileBaseResolver resolver(
      List<RestoreBase> points, {
      Map<String, String> originals = const {},
    }) => FileBaseResolver(
      originalFiles: () async => originals,
      showAt: show,
      startSha: 'abcdef1234',
      root: '/w',
      points: () async => points,
    );

    Future<FileAtStep> at(
      FileBaseResolver r,
      String path,
      bool Function(ReplayStep) pick,
    ) async {
      final steps = replaySteps(b.items, root: '/w');
      final edits = editsOf(steps, path, root: '/w');
      final target = edits.firstWhere(pick);
      final base = await r.resolve(path, edits, target);
      return fileAtStep(base: base, edits: edits, target: target);
    }

    test('usa o ponto do turno do passo e aplica os hunks em ordem', () async {
      b.user('um');
      final s1 = b.seq;
      b.turn('t-1');
      b.patch('e1', [update('/w/lib/f.dart', '@@ -2,1 +2,1 @@\n-l2\n+L2\n')]);
      b.endTurn();
      b.user('dois');
      final s2 = b.seq;
      b.turn('t-2');
      b.patch('e2', [
        update('/w/lib/f.dart', '@@ -3,1 +3,2 @@\n-l3\n+L3\n+extra\n'),
      ]);
      b.patch('e3', [update('/w/lib/f.dart', '@@ -5,1 +5,1 @@\n-l4\n+L4\n')]);
      final points = [
        RestoreBase(turn: 1, seq: s1, sha: 'p1'),
        RestoreBase(
          turn: 2,
          seq: s2,
          sha: 'p2',
          at: DateTime(2026, 11, 25, 14, 30),
        ),
      ];
      final r = await at(
        resolver(points),
        '/w/lib/f.dart',
        (s) => s.tool!.id == 'e3',
      );
      expect(r.text, 'l1\nL2\nL3\nextra\nL4\n');
      expect(r.highlighted, {5});
      expect(shown, ['p2:lib/f.dart']);
      expect(r.base!.label, 'ponto de restauração do turno 2 (14:30)');
      final first = await at(
        resolver(points),
        '/w/lib/f.dart',
        (s) => s.tool!.id == 'e1',
      );
      expect(first.text, 'l1\nL2\nl3\nl4\n');
      expect(first.base!.label, 'ponto de restauração do turno 1');
    });

    test('um hunk que não se aplica diz o passo, o ponto e a linha', () async {
      b.user('um');
      final s1 = b.seq;
      b.turn('t-1');
      b.patch('e1', [
        update('/w/lib/f.dart', '@@ -2,2 +2,2 @@\n l2\n-outra\n+x\n'),
      ]);
      final r = await at(
        resolver([RestoreBase(turn: 3, seq: s1, sha: 'p1')]),
        '/w/lib/f.dart',
        (_) => true,
      );
      expect(r.ok, isFalse);
      expect(
        r.reason,
        'O diff do passo 2 não se aplica sobre a base (ponto do turno 3): a '
        'linha 3 já era diferente. O diff do passo continua abaixo.',
      );
    });

    test('arquivo movido: a base é o nome antigo, no ponto', () async {
      b.user('um');
      final s1 = b.seq;
      b.turn('t-1');
      b.patch('e1', [update('/w/lib/velho.dart', '@@ -1 +1 @@\n-um\n+UM\n')]);
      b.patch('e2', [
        update(
          '/w/lib/velho.dart',
          '@@ -2 +2 @@\n-dois\n+DOIS\n',
          move: '/w/lib/novo.dart',
        ),
      ]);
      final r = await at(
        resolver([RestoreBase(turn: 1, seq: s1, sha: 'p1')]),
        '/w/lib/novo.dart',
        (s) => s.tool!.id == 'e2',
      );
      expect(r.text, 'UM\nDOIS\n');
      expect(shown, ['p1:lib/velho.dart']);
    });

    test('arquivo criado no turno: não existe no ponto', () async {
      b.user('um');
      final s1 = b.seq;
      b.turn('t-1');
      b.patch('e1', [
        {
          'path': '/w/lib/n.dart',
          'kind': {'type': 'add'},
          'diff': 'a\n',
        },
      ]);
      b.patch('e2', [update('/w/lib/n.dart', '@@ -1 +1 @@\n-a\n+b\n')]);
      final r = await at(
        resolver([RestoreBase(turn: 1, seq: s1, sha: 'p1')]),
        '/w/lib/n.dart',
        (s) => s.tool!.id == 'e2',
      );
      expect(r.text, 'b\n');
      expect(r.base!.source, FileBaseSource.restorePoint);
    });

    test(
      'o ponto não tem o arquivo (ignorado pelo git): a próxima base',
      () async {
        b.user('um');
        final s1 = b.seq;
        b.turn('t-1');
        b.patch('e1', [update('/w/lib/x.dart', '@@ -1 +1 @@\n-a\n+b\n')]);
        final steps = replaySteps(b.items, root: '/w');
        final edits = editsOf(steps, '/w/lib/x.dart', root: '/w');
        final base = await resolver([RestoreBase(turn: 1, seq: s1, sha: 'p1')])
            .resolve('/w/lib/x.dart', edits, edits.single);
        expect(base!.source, FileBaseSource.startSha);
      },
    );

    test('P6: no Claude o ponto vem antes do originalFile', () async {
      b.user('um');
      final s1 = b.seq;
      final id = b.edit('/w/lib/f.dart', 'l2', 'L2');
      final r = await at(
        resolver(
          [RestoreBase(turn: 1, seq: s1, sha: 'p1')],
          originals: {id: 'da transcrição\nl2\n'},
        ),
        '/w/lib/f.dart',
        (_) => true,
      );
      expect(r.base!.source, FileBaseSource.restorePoint);
      expect(r.text, 'l1\nL2\nl3\nl4\n');
    });

    test('Claude: um formatador no meio do turno quebra a sequência, e o '
        'originalFile da edição resolve', () async {
      b.user('um');
      final s1 = b.seq;
      b.bash('dart format lib/f.dart');
      final id = b.edit('/w/lib/f.dart', 'formatado', 'F');
      final r = await at(
        resolver(
          [RestoreBase(turn: 1, seq: s1, sha: 'p1')],
          originals: {id: 'formatado\n'},
        ),
        '/w/lib/f.dart',
        (_) => true,
      );
      expect(r.base!.source, FileBaseSource.transcript);
      expect(r.text, 'F\n');
    });
  });

  group('SPEC-110 R3 · quem escreveu, pelos diffs', () {
    test('acha a última edição do Codex que adicionou a linha', () {
      final b = TimelineBuilder()..user('x');
      b.turn('t-1');
      b.patch('e1', [update('/w/f.dart', '@@ -1 +1 @@\n-a\n+nova\n')]);
      b.patch('e2', [
        update('/w/f.dart', '@@ -1,1 +1,2 @@\n nova\n+mais\n'),
        update('/w/g.dart', '@@ -1 +1 @@\n-a\n+nova\n'),
      ]);
      final steps = replaySteps(b.items);
      expect(whoWroteLine(steps, '/w/f.dart', '  nova')!.edit!.tool!.id, 'e1');
      expect(whoWroteLine(steps, '/w/f.dart', 'mais')!.edit!.tool!.id, 'e2');
    });

    test('nenhuma edição escreveu: o último Rodar antes de a linha aparecer '
        '(uma leitura por comando não conta)', () {
      final b = TimelineBuilder()..user('x');
      b.turn('t-1');
      final unknown = {'type': 'unknown', 'command': 'x'};
      b.command('c1', 'dart run gera.dart', [unknown]);
      b.command('c2', 'cat f.dart', [readAction('/w/f.dart')]);
      b.patch('e1', [
        update('/w/f.dart', '@@ -1,1 +1,2 @@\n gerada\n+depois\n'),
      ]);
      b.command('c3', 'dart test', [unknown]);
      final steps = replaySteps(b.items);
      final who = whoWroteLine(steps, '/w/f.dart', 'gerada')!;
      expect(who.fromCommand, isTrue);
      expect(who.command!.tool!.id, 'c1');
      // Nenhum diff a mostra: o último Rodar.
      expect(
        whoWroteLine(steps, '/w/f.dart', 'só no fim')!.command!.tool!.id,
        'c3',
      );
    });
  });
}
