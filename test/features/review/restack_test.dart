import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/review/restack.dart';
import 'package:promptorium/features/review/review_service.dart';

import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';

/// SPEC-032 R6, R7, R15: the base of a stacked spec is redone after its
/// mother entered `main`, in a real repository.
class Stack {
  Stack(this.c, this.ws, this.repo, this.mother, this.child, this.session);

  final ProviderContainer c;
  final Workspace ws;
  final String repo, mother, child;
  final Session session;

  ReviewService get review => c.read(reviewServiceProvider);
  String? mark() => c.read(appSettingsProvider)[restackMarkKey(session.id)];
  Future<List<String>> ownCommits(String base) async => (await gitIn(child, [
    'log',
    '--format=%s',
    '$base..HEAD',
  ])).trim().split('\n').where((l) => l.isNotEmpty).toList();
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('promptorium-stack-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// main ← pr/mae (SPEC-029, `m.txt`) ← pr/filha (SPEC-031, `c.txt`), each
  /// in its own worktree; the child's session is in Review.
  Future<Stack> setUpStack() async {
    final repo = await createRepo(tmp);
    final mother = '${tmp.path}/wt/mae', child = '${tmp.path}/wt/filha';
    await gitIn(repo, ['worktree', 'add', '-q', '-b', 'pr/mae', mother]);
    File('$mother/m.txt').writeAsStringSync('mãe\n');
    await gitIn(mother, ['add', '.']);
    await gitIn(mother, ['commit', '-q', '-m', 'SPEC-029 R1: mãe']);
    await gitIn(repo, [
      'worktree',
      'add',
      '-q',
      '-b',
      'pr/filha',
      child,
      'pr/mae',
    ]);
    File('$child/c.txt').writeAsStringSync('filha\n');
    await gitIn(child, ['add', '.']);
    await gitIn(child, ['commit', '-q', '-m', 'SPEC-031 R1: filha']);

    final db = memoryDatabase();
    final c = sessionContainer([
      ...sessionOverrides(
        db: db,
        cli: FakeCli(),
        notifier: FakeNotifier(),
      ).where((o) => o.origin != gitServiceFactoryProvider),
      gitServiceFactoryProvider.overrideWithValue(GitService.new),
      commandRunnerProvider.overrideWithValue(
        (exe, args, {workingDirectory}) async => ProcessResult(1, 1, '', ''),
      ),
    ]);
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    final ws = await c.read(workspacesRepoProvider).add(path: repo, name: 'r');
    final specs = c.read(specsRepoProvider);
    final m = await specs.insert(
      workspaceId: ws.id,
      code: 'SPEC-029',
      title: 'Mãe',
      path: 'docs/specs/SPEC-029.md',
    );
    await specs.update(
      m.id,
      const SpecsCompanion(
        branch: Value('pr/mae'),
        baseBranch: Value('main'),
        stage: Value(SpecStage.review),
      ),
    );
    final f = await specs.insert(
      workspaceId: ws.id,
      code: 'SPEC-031',
      title: 'Filha',
      path: 'docs/specs/SPEC-031.md',
    );
    await specs.update(
      f.id,
      const SpecsCompanion(
        branch: Value('pr/filha'),
        baseBranch: Value('pr/mae'),
        stage: Value(SpecStage.review),
      ),
    );
    final sessions = c.read(sessionsRepoProvider);
    await sessions.insert(
      id: 'mae',
      workspaceId: ws.id,
      worktreePath: mother,
      branch: 'pr/mae',
      model: 'sonnet',
      specId: m.id,
      baseBranch: 'main',
      status: SessionStatus.completed,
    );
    final s = await sessions.insert(
      id: 'filha',
      workspaceId: ws.id,
      worktreePath: child,
      branch: 'pr/filha',
      model: 'sonnet',
      specId: f.id,
      baseBranch: 'pr/mae',
      status: SessionStatus.completed,
    );
    return Stack(c, ws, repo, mother, child, s);
  }

  /// The mother enters `main` by squash (a new commit for git).
  Future<void> squashMother(Stack s) async {
    await gitIn(s.repo, ['merge', '-q', '--squash', 'pr/mae']);
    await gitIn(s.repo, ['commit', '-q', '-m', 'SPEC-029: Mãe']);
  }

  Future<void> saveOldBase(Stack s) async => gitIn(s.repo, [
    'update-ref',
    oldBaseRef('SPEC-031'),
    (await gitIn(s.repo, ['rev-parse', 'pr/mae'])).trim(),
  ]);

  test('R6 · after the squash of the mother the child sits on main with '
      'only its own commits; its base becomes main', () async {
    final s = await setUpStack();
    await saveOldBase(s);
    await squashMother(s);
    final r = await s.review.restackChildren(
      s.ws,
      [s.session],
      newBase: 'main',
      target: 'main',
    );
    expect(r.single.outcome, RestackOutcome.ok);
    expect(await s.ownCommits('main'), ['SPEC-031 R1: filha']);
    expect(s.mark(), isNull);
    expect(
      (await s.c.read(sessionsRepoProvider).getById('filha'))!.baseBranch,
      'main',
    );
    expect(await GitService(s.repo).resolveRef(oldBaseRef('SPEC-031')), isNull);
    expect(restackNotice(r), 'base da SPEC-031 refeita');
  });

  test('R7 · a real conflict aborts the rebase: the branch stays as it was '
      'and the child is marked', () async {
    final s = await setUpStack();
    await saveOldBase(s);
    final a = File('${s.child}/a.txt');
    a.writeAsStringSync(a.readAsStringSync().replaceFirst('linha 5\n', 'X\n'));
    await gitIn(s.child, ['commit', '-q', '-am', 'SPEC-031 R2: a.txt']);
    final before = (await gitIn(s.child, ['rev-parse', 'HEAD'])).trim();
    await squashMother(s);
    final b = File('${s.repo}/a.txt');
    b.writeAsStringSync(b.readAsStringSync().replaceFirst('linha 5\n', 'Y\n'));
    await gitIn(s.repo, ['commit', '-q', '-am', 'outra spec: a.txt']);

    final r = await s.review.restackChildren(
      s.ws,
      [s.session],
      newBase: 'main',
      target: 'main',
    );
    expect(r.single.outcome, RestackOutcome.conflict);
    expect(r.single.files, ['a.txt']);
    expect((await gitIn(s.child, ['rev-parse', 'HEAD'])).trim(), before);
    expect(await gitIn(s.child, ['status', '--porcelain']), isEmpty);
    expect(s.mark(), 'conflito\na.txt');
    expect(
      restackMessage(branch: 'pr/filha', base: 'main', oldBase: 'abc'),
      contains('git rebase --onto main abc'),
    );
  });

  test('R6 · a dirty worktree is not touched: "Base desatualizada"', () async {
    final s = await setUpStack();
    await saveOldBase(s);
    await squashMother(s);
    File('${s.child}/c.txt').writeAsStringSync('mexido\n');
    final r = await s.review.restackChildren(
      s.ws,
      [s.session],
      newBase: 'main',
      target: 'main',
    );
    expect(r.single.outcome, RestackOutcome.skipped);
    expect(s.mark(), startsWith('desatualizada'));
    expect(File('${s.child}/c.txt').readAsStringSync(), 'mexido\n');
  });

  group('R15 · mother merged outside the app', () {
    Future<void> mergeOnHost(Stack s, String remote) async {
      // The host squashes the mother and deletes its branch; locally it is
      // gone too (worktree and branch removed).
      await squashMother(s);
      await gitIn(s.repo, ['push', '-q', 'origin', 'main']);
      await gitIn(s.repo, ['worktree', 'remove', '--force', s.mother]);
      await gitIn(s.repo, ['branch', '-q', '-D', 'pr/mae']);
      // The local main stays behind: the rebase must use origin/main.
      await gitIn(s.repo, ['reset', '-q', '--hard', 'HEAD~1']);
    }

    Future<String> withRemote(Stack s) async {
      final remote = '${tmp.path}/origin.git';
      await Process.run('git', ['init', '-q', '--bare', remote]);
      await gitIn(s.repo, ['remote', 'add', 'origin', remote]);
      await gitIn(s.repo, ['push', '-q', 'origin', 'main']);
      return remote;
    }

    test('the queue saves the old base while the mother exists, then '
        'redoes the base on origin/main', () async {
      final s = await setUpStack();
      final remote = await withRemote(s);
      expect(await s.review.restackOrphans(s.ws), isEmpty);
      expect(
        await GitService(s.repo).resolveRef(oldBaseRef('SPEC-031')),
        isNotNull,
      );
      await mergeOnHost(s, remote);
      final r = await s.review.restackOrphans(s.ws);
      expect(r.single.outcome, RestackOutcome.ok);
      expect(await s.ownCommits('origin/main'), ['SPEC-031 R1: filha']);
      expect(
        (await s.c.read(sessionsRepoProvider).getById('filha'))!.baseBranch,
        'main',
      );
      // Nothing left to redo.
      expect(await s.review.restackOrphans(s.ws), isEmpty);
    });

    test('without the saved ref: "Base desatualizada", and "Refazer agora" '
        'uses git merge-base', () async {
      final s = await setUpStack();
      final remote = await withRemote(s);
      await mergeOnHost(s, remote);
      final r = await s.review.restackOrphans(s.ws);
      expect(r.single.outcome, RestackOutcome.skipped);
      expect(s.mark(), startsWith('desatualizada'));
      await gitIn(s.repo, ['merge', '-q', '--ff-only', 'origin/main']);
      final again = await s.review.restackNow('filha');
      expect(again.outcome, RestackOutcome.ok);
      // The mother's commit is already in main (same patch): dropped.
      expect(await s.ownCommits('main'), ['SPEC-031 R1: filha']);
      expect(s.mark(), isNull);
    });
  });
}
