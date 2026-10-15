import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/diff_parser.dart';
import 'package:promptorium/core/git/git_service.dart';

import 'git_test_utils.dart';

void main() {
  late Directory tmp;
  late String repo;
  late GitService git;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-diff-');
    repo = await createRepo(tmp);
    git = GitService(repo, worktreesBase: '${tmp.path}/wt');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<ProcessResult> apply(String patch, List<String> flags) async {
    final f = File('${tmp.path}/hunk.patch')..writeAsStringSync(patch);
    return Process.run('git', ['-C', repo, 'apply', ...flags, f.path]);
  }

  /// Two separate hunks in a.txt, a new file, a deletion, a rename and a
  /// deleted line that starts with "--".
  Future<void> makeChanges() async {
    final a = File('$repo/a.txt');
    final lines = a.readAsLinesSync();
    lines[1] = 'linha DOIS';
    lines.insert(3, '-- parece cabeçalho');
    lines.removeAt(26); // "linha 26" (after the insert)
    a.writeAsStringSync('${lines.join('\n')}\n');

    File('$repo/sem-fim.txt').writeAsStringSync('um\n-- dois\n');
    File('$repo/vai-sumir.txt').writeAsStringSync('tchau\n');
    File('$repo/velho.txt').writeAsStringSync(
      [for (var i = 0; i < 20; i++) 'conteúdo $i'].join('\n'),
    );
    await gitIn(repo, ['add', '.']);
    await gitIn(repo, ['commit', '-q', '-m', 'mais arquivos']);

    File('$repo/sem-fim.txt').writeAsStringSync('um\n');
    File('$repo/vai-sumir.txt').deleteSync();
    await gitIn(repo, ['mv', 'velho.txt', 'novo nome.txt']);
    File('$repo/criado.txt').writeAsStringSync('novo\narquivo\n');
    await gitIn(repo, ['add', '-A']);
  }

  test('parses a real git diff (A/M/D/R, hunks, line numbers)', () async {
    // a.txt changes are committed above; diff the staged state vs HEAD~1
    // to see everything at once.
    await makeChanges();
    final files = DiffParser.parse(await git.diff(base: 'HEAD~1'));
    final byPath = {for (final f in files) f.path: f};

    expect(byPath.keys, containsAll(['a.txt', 'criado.txt', 'sem-fim.txt']));

    final added = byPath['criado.txt']!;
    expect(added.status, DiffFileStatus.added);
    expect(added.oldPath, isNull);
    expect(added.hunks.single.oldStart, 0);
    expect(added.hunks.single.newLen, 2);
    expect(added.hunks.single.lines.map((l) => l.newNo), [1, 2]);

    final a = byPath['a.txt']!;
    expect(a.status, DiffFileStatus.modified);
    expect(a.hunks, hasLength(2));
    final h1 = a.hunks.first;
    expect(h1.oldStart, 1);
    expect(h1.newStart, 1);
    final dois = h1.lines.firstWhere((l) => l.kind == DiffLineKind.add);
    expect(dois.text, 'linha DOIS');
    expect(dois.newNo, 2);
    expect(dois.oldNo, isNull);
    final del = h1.lines.firstWhere((l) => l.kind == DiffLineKind.del);
    expect(del.text, 'linha 2');
    expect(del.oldNo, 2);
    expect(
      h1.lines.where((l) => l.text == '-- parece cabeçalho').single.kind,
      DiffLineKind.add,
    );
    expect(a.hunks.last.deletions, 1);
    expect(
      a.hunks.last.lines.firstWhere((l) => l.kind == DiffLineKind.del).text,
      'linha 26',
    );

    // Staged changes vs HEAD: delete, rename, "--" deleted line.
    final staged = DiffParser.parse(
      await git.git(['diff', '--cached', '-M', '--unified=3']),
    );
    final s = {for (final f in staged) f.path: f};
    expect(s['vai-sumir.txt']!.status, DiffFileStatus.deleted);
    expect(s['vai-sumir.txt']!.newPath, isNull);
    final renamed = s['novo nome.txt']!;
    expect(renamed.status, DiffFileStatus.renamed);
    expect(renamed.oldPath, 'velho.txt');
    expect(renamed.hunks, isEmpty);
    final semFim = s['sem-fim.txt']!.hunks.single;
    expect(semFim.lines.map((l) => (l.kind, l.text)), [
      (DiffLineKind.context, 'um'),
      (DiffLineKind.del, '-- dois'),
    ]);
  });

  test('no-newline marker and quoted paths', () {
    const diff =
        'diff --git "a/caf\\303\\251.txt" "b/caf\\303\\251.txt"\n'
        'index 1..2 100644\n'
        '--- "a/caf\\303\\251.txt"\n'
        '+++ "b/caf\\303\\251.txt"\n'
        '@@ -1 +1 @@\n'
        '-velho\n'
        '\\ No newline at end of file\n'
        '+novo\n'
        '\\ No newline at end of file\n';
    final f = DiffParser.parse(diff).single;
    expect(f.path, 'café.txt');
    expect(f.oldPath, 'café.txt');
    final h = f.hunks.single;
    expect(h.oldLen, 1);
    expect(h.lines.every((l) => l.noNewlineAtEnd), isTrue);
    expect(DiffParser.hunkPatch(f, h), diff);
  });

  test(
    'single-hunk patch is accepted by git apply -R --check and reverts',
    () async {
      final a = File('$repo/a.txt');
      final lines = a.readAsLinesSync();
      lines[1] = 'linha DOIS';
      lines[25] = 'linha VINTE E SEIS';
      a.writeAsStringSync('${lines.join('\n')}\n');

      final file = DiffParser.parse(await git.diff()).single;
      expect(file.hunks, hasLength(2));
      final second = DiffParser.hunkPatch(file, file.hunks.last);
      expect(second, startsWith('diff --git a/a.txt b/a.txt\n'));
      expect(second, contains('@@ -23,7 +23,7 @@'));
      expect(second, isNot(contains('linha DOIS')));

      final check = await apply(second, ['-R', '--check']);
      expect(check.exitCode, 0, reason: '${check.stderr}');
      final rev = await apply(second, ['-R']);
      expect(rev.exitCode, 0, reason: '${rev.stderr}');

      final after = a.readAsStringSync();
      expect(after, contains('linha DOIS'));
      expect(after, contains('linha 26'));
      expect(after, isNot(contains('VINTE E SEIS')));

      // A new file's only hunk also reverts (removes the file contents).
      File('$repo/n.txt').writeAsStringSync('x\n');
      await gitIn(repo, ['add', '-N', 'n.txt']);
      final nf = DiffParser.parse(await git.diff(path: 'n.txt')).single;
      expect(nf.status, DiffFileStatus.added);
      final check2 = await apply(DiffParser.hunkPatch(nf, nf.hunks.single), [
        '-R',
        '--check',
      ]);
      expect(check2.exitCode, 0, reason: '${check2.stderr}');
    },
  );
}
