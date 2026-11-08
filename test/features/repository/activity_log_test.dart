import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/features/repository/activity/activity_log.dart';

import '../../core/git/git_test_utils.dart';
import 'commit_log_test.dart' show buildHistory, commitIn;

void main() {
  late Directory tmp;
  late String repo;
  late String cache;
  late List<List<String>> calls;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-activity-log-');
    repo = await createRepo(tmp);
    await buildHistory(repo);
    cache = '${tmp.path}/cache';
    calls = [];
    ActivityLogReader.clearMemory();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  ActivityLogReader reader({bool isolate = false}) => ActivityLogReader(
    GitService(
      repo,
      run: (exe, args) {
        calls.add(args);
        return Process.run(exe, args);
      },
    ),
    defaultBranch: 'main',
    remote: 'origin',
    cacheDir: cache,
    useIsolate: isolate,
  );

  /// `git log` calls made since the last [clear].
  int logCalls() => calls.where((a) => a.length > 2 && a[2] == 'log').length;

  test('reads the default branch and the spec/* branches with numstat, '
      'tags and the trailer', () async {
    await gitIn(repo, ['checkout', '-q', 'spec/043-conflito']);
    File('$repo/x.txt').writeAsStringSync('1\n2\n');
    await gitIn(repo, ['add', 'x.txt']);
    await gitIn(repo, [
      'commit',
      '-q',
      '-m',
      'feat: x',
      '--trailer',
      'Promptorium-Agente: sonnet · SPEC-043 R1',
    ]);
    await gitIn(repo, ['checkout', '-q', 'main']);
    // Not read: neither the default branch nor a spec branch.
    await gitIn(repo, ['checkout', '-q', '-b', 'outra']);
    await commitIn(repo, 'chore: fora');
    await gitIn(repo, ['checkout', '-q', 'main']);

    final load = await reader().load();
    expect(load.full, isTrue);
    final log = load.log;
    expect(log.tips.keys.toSet(), {
      'refs/heads/main',
      'refs/heads/spec/042-sprints',
      'refs/heads/spec/043-conflito',
    });
    final subjects = log.commits.map((c) => c.subject).toList();
    expect(subjects, isNot(contains('chore: fora')));
    expect(subjects.first, 'feat: x');
    expect(load.read, log.commits.length);
    final x = log.commits.first;
    expect(x.trailers, 'sonnet · SPEC-043 R1');
    expect(x.files.single.path, 'x.txt');
    expect(x.files.single.added, 2);
    final merge = log.commits.firstWhere(
      (c) => c.subject.startsWith('Merge pull request #94'),
    );
    expect(merge.isMerge, isTrue);
    expect(merge.files, isEmpty);
    expect(log.tags.map((t) => t.name), ['v0.1.0']);
  });

  test('R6 · sem commits novos nada é lido de novo (nem do arquivo, nem do '
      'git)', () async {
    final first = await reader().load();
    expect(first.full, isTrue);
    expect(File(reader().cacheFile!).existsSync(), isTrue);

    // A new reader (the tab opened again), memory cleared: only the file.
    ActivityLogReader.clearMemory();
    calls.clear();
    final again = await reader().load();
    expect(again.read, 0);
    expect(again.full, isFalse);
    expect(logCalls(), 0);
    expect(
      again.log.commits.map((c) => c.sha),
      first.log.commits.map((c) => c.sha),
    );

    // From memory as well.
    calls.clear();
    expect((await reader().load()).read, 0);
    expect(logCalls(), 0);
  });

  test('R6 · com commits novos só eles são lidos', () async {
    final first = await reader().load();
    final before = first.log.commits.length;

    final sha = await commitIn(repo, 'feat: novo na main');
    await gitIn(repo, ['checkout', '-q', '-b', 'spec/044-releases']);
    await commitIn(repo, 'docs: SPEC-044, releases');
    await commitIn(repo, 'feat(repo): releases');
    await gitIn(repo, ['checkout', '-q', 'main']);

    ActivityLogReader.clearMemory();
    calls.clear();
    final next = await reader().load();
    expect(next.full, isFalse);
    expect(next.read, 3);
    expect(next.log.commits.length, before + 3);
    expect(next.log.commits.map((c) => c.sha), contains(sha));
    // The old ones come from the cache, in the same order, after the new.
    expect(
      next.log.commits.skip(3).map((c) => c.sha),
      first.log.commits.map((c) => c.sha),
    );
    final log = calls.firstWhere((a) => a.length > 2 && a[2] == 'log');
    expect(log, contains('--not'));
  });

  test('R6 · uma branch reescrita lê tudo de novo', () async {
    await reader().load();
    await gitIn(repo, ['checkout', '-q', 'spec/043-conflito']);
    await gitIn(repo, ['commit', '-q', '--amend', '-m', 'docs: SPEC-043, v2']);
    await gitIn(repo, ['checkout', '-q', 'main']);
    final again = await reader().load();
    expect(again.full, isTrue);
    expect(
      again.log.commits.map((c) => c.subject),
      isNot(contains('docs: SPEC-043, conflito')),
    );
    expect(
      again.log.commits.map((c) => c.subject),
      contains('docs: SPEC-043, v2'),
    );
  });

  test('o cache é lido e gravado em outro isolate', () async {
    final first = await reader(isolate: true).load();
    ActivityLogReader.clearMemory();
    final again = await reader(isolate: true).load();
    expect(again.read, 0);
    expect(again.log.commits.length, first.log.commits.length);
    expect(
      again.log.commits.first.files.length,
      first.log.commits.first.files.length,
    );
  });

  test('um cache de outra versão é ignorado', () async {
    await reader().load();
    File(reader().cacheFile!).writeAsStringSync('{"versao": 0}');
    ActivityLogReader.clearMemory();
    expect((await reader().load()).full, isTrue);
    expect(ActivityLog.decode('não é json'), isNull);
  });
}
