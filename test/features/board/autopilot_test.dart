import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/autopilot.dart';
import 'package:promptorium/features/specs/spec_service.dart';

import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';

Future<void> gitIn(String dir, List<String> args) async {
  final r = await Process.run('git', args, workingDirectory: dir);
  if (r.exitCode != 0) fail('git ${args.join(' ')}: ${r.stderr}');
}

void main() {
  late Directory tmp;
  late String repo;
  late FakeCli cli;
  late ProviderContainer c;
  late Workspace ws;
  late FakeNotifier notifier;

  Future<void> settle() async {
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-sprint-');
    repo = '${tmp.path}/repo';
    Directory('$repo/specs').createSync(recursive: true);
    await gitIn(repo, ['init', '-q', '-b', 'main']);
    await gitIn(repo, ['config', 'user.email', 't@t']);
    await gitIn(repo, ['config', 'user.name', 't']);
    for (final (code, deps) in [
      ('SPEC-001', ''),
      ('SPEC-002', 'depende-de: SPEC-003\n'),
      ('SPEC-003', ''),
    ]) {
      File('$repo/specs/$code.md').writeAsStringSync(
        '---\nid: $code\nstatus: aprovada\n$deps---\n\n# $code\n\n'
        '## Requisitos\n\n- R1 · a\n',
      );
    }
    await gitIn(repo, ['add', '.']);
    await gitIn(repo, ['commit', '-q', '-m', 'specs']);
    Directory('$repo/.promptorium').createSync();
    cli = FakeCli();
    c = sessionContainer(
      sessionOverrides(
        db: memoryDatabase(),
        cli: cli,
        notifier: notifier = FakeNotifier(),
        worktreesBase: '${tmp.path}/wt',
      ),
    );
    await c.read(appSettingsProvider.notifier).load();
    ws = await c.read(workspacesRepoProvider).add(path: repo, name: 'r');
    await c.read(specServiceProvider).sync(ws);
  });

  tearDown(() {
    c.dispose();
    tmp.deleteSync(recursive: true);
  });

  Future<Map<String, Spec>> specs() async => {
    for (final s
        in await c.read(specsRepoProvider).watchByWorkspace(ws.id).first)
      s.code: s,
  };

  test('R11: com sprint Ativa, só inicia specs dela e não puxa a dependência '
      'de outra sprint', () async {
    final repoS = c.read(sprintsRepoProvider);
    final a = await repoS.create(workspaceId: ws.id, name: 'Sprint 1');
    final b = await repoS.create(workspaceId: ws.id, name: 'Sprint 2');
    final all = await specs();
    await repoS.moveSpecs([all['SPEC-001']!.id, all['SPEC-002']!.id], a.id);
    await repoS.moveSpecs([all['SPEC-003']!.id], b.id);

    await c.read(autopilotProvider.notifier).start(ws.id);
    await settle();

    final after = await specs();
    expect(after['SPEC-001']!.stage, SpecStage.running);
    expect(after['SPEC-002']!.stage, SpecStage.backlog);
    expect(after['SPEC-003']!.stage, SpecStage.backlog);
    expect(cli.processes, hasLength(1));
  });

  test('SPEC-064 R6: the waiting spec starts when its dependency reaches '
      'Review, with a notice; the end too', () async {
    await c.read(autopilotProvider.notifier).start(ws.id);
    await settle();
    var now = await specs();
    expect(now['SPEC-002']!.stage, SpecStage.backlog);
    final repo = c.read(specsRepoProvider);
    await repo.setStage(now['SPEC-003']!.id, SpecStage.review);
    await c.read(autopilotProvider.notifier).tick(ws.id);
    await settle();
    now = await specs();
    expect(now['SPEC-002']!.stage, SpecStage.running);
    expect(
      notifier.shown.map((n) => n.$2),
      contains('SPEC-002 começou: a SPEC-003 chegou em Review.'),
    );
    // Everything in Review: the autopilot turns off and says so.
    for (final k in ['SPEC-001', 'SPEC-002']) {
      await repo.setStage(now[k]!.id, SpecStage.review);
    }
    await c.read(autopilotProvider.notifier).tick(ws.id);
    await settle();
    expect(c.read(autopilotProvider.notifier).isOn(ws.id), isFalse);
    expect(
      notifier.shown.map((n) => n.$2),
      contains('Executar tudo terminou: 3 specs em Review.'),
    );
  });

  test(
    'SPEC-064 R3: with Feito, a dependency in Review does not release',
    () async {
      final pilot = c.read(autopilotProvider.notifier);
      await pilot.setUnblockAt(ws.id, UnblockAt.done);
      await pilot.start(ws.id);
      await settle();
      final now = await specs();
      await c
          .read(specsRepoProvider)
          .setStage(now['SPEC-003']!.id, SpecStage.review);
      await pilot.tick(ws.id);
      await settle();
      expect((await specs())['SPEC-002']!.stage, SpecStage.backlog);
    },
  );

  test('R11: sem sprint Ativa, age como hoje', () async {
    await c.read(autopilotProvider.notifier).start(ws.id);
    await settle();
    final after = await specs();
    expect(after['SPEC-001']!.stage, SpecStage.running);
    expect(after['SPEC-003']!.stage, SpecStage.running);
  });
}
