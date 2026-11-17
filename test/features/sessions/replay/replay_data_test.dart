import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/text/line_diff.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/sessions/replay/replay_data.dart';

import '../../../helpers/test_db.dart';
import '../../../core/git/git_test_utils.dart';

void main() {
  late Directory tmp;
  late String repo;
  late ProviderContainer c;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-replay-result-');
    repo = await createRepo(tmp);
    final db = memoryDatabase();
    final ws = await db.into(db.workspaces).insertReturning(WorkspacesCompanion.insert(name: 'Replay', path: repo));
    final session = await db.into(db.sessions).insertReturning(SessionsCompanion.insert(id: 's1', workspaceId: ws.id, worktreePath: repo, branch: 'main', model: 'sonnet'));
    final base = (await gitIn(repo, ['rev-parse', 'HEAD'])).trim();
    c = ProviderContainer(overrides: [
      databaseOverride(db),
      replaySourceProvider('s1').overrideWith((ref) async => ReplaySource(session, startSha: base)),
    ]);
  });

  tearDown(() async {
    c.dispose();
    await tmp.delete(recursive: true);
  });

  test('R8: result includes command-only tracked edits and untracked generated files', () async {
    File('$repo/a.txt').writeAsStringSync('formatado\n');
    File('$repo/gerado.sql').writeAsStringSync('SELECT 1;\nSELECT 2;\n');
    final files = await c.read(replayResultFilesProvider('s1').future);
    expect(
      files.map((f) => f.path),
      containsAll(['$repo/a.txt', '$repo/gerado.sql']),
    );
    final generated = files.singleWhere((f) => f.path.endsWith('gerado.sql'));
    expect(generated.added, 2);
    final diff = await c.read(
      replayFinalDiffProvider(('s1', '$repo/gerado.sql')).future,
    );
    expect(diff.error, isNull);
    expect(diff.rows.map((r) => r.text), ['SELECT 1;', 'SELECT 2;']);
    expect(diff.rows.every((r) => r.op == DiffOp.add), isTrue);
  });

  test(
    'R8: committed command edits, deletions and binary files remain visible',
    () async {
      File('$repo/a.txt').deleteSync();
      File('$repo/generated.bin').writeAsBytesSync([0, 1, 2]);
      await gitIn(repo, ['add', '.']);
      await gitIn(repo, ['commit', '-qm', 'gerado pelo comando']);
      final files = await c.read(replayResultFilesProvider('s1').future);
      expect(
        files.map((f) => f.path),
        containsAll(['$repo/a.txt', '$repo/generated.bin']),
      );
      expect(
        files.singleWhere((f) => f.path.endsWith('generated.bin')).added,
        -1,
      );
    },
  );

  test(
    'R8: untracked symlinks cannot preview a file outside the worktree',
    () async {
      File('${tmp.path}/outside.txt').writeAsStringSync('fora do projeto');
      Link('$repo/link.txt').createSync('${tmp.path}/outside.txt');
      final diff = await c.read(
        replayFinalDiffProvider(('s1', '$repo/link.txt')).future,
      );
      expect(diff.error, contains('fora da worktree'));
      expect(diff.rows, isEmpty);
    },
  );
}
