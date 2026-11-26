import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/activities/automation_pause.dart';
import 'package:promptorium/features/board/autopilot.dart';
import 'package:promptorium/features/board/orchestrator/orchestrator_rules.dart';
import 'package:promptorium/features/board/orchestrator/quota_divert.dart';
import 'package:promptorium/features/board/orchestrator/quota_diverter.dart';
import 'package:promptorium/features/board/spec_runner.dart';
import 'package:promptorium/features/specs/spec_service.dart';

import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';
import 'orchestrator/orchestrator_fixture.dart' as orq;

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

  test('SPEC-063 R1: a spec with "depende:" waits for its dependency in '
      '"Executar tudo"', () async {
    File('$repo/specs/SPEC-004.md').writeAsStringSync(
      '---\nid: SPEC-004\nstatus: aprovada\ndesign: dispensado\n'
      'depende: [SPEC-001]\n---\n\n# SPEC-004\n\n## Requisitos\n\n- R1 · a\n',
    );
    await c.read(specServiceProvider).sync(ws);
    expect((await specs())['SPEC-004']!.dependsOn, ['SPEC-001']);
    await c.read(autopilotProvider.notifier).start(ws.id);
    await settle();
    final after = await specs();
    expect(after['SPEC-001']!.stage, SpecStage.running);
    expect(after['SPEC-004']!.stage, SpecStage.backlog);
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

  group('SPEC-071 R6: a spec never starts twice', () {
    test('two requests for the same spec open one session only', () async {
      final id = (await specs())['SPEC-001']!.id;
      final runner = c.read(specRunnerProvider);
      final results = await Future.wait([
        runner.runAuto(id).then<Object>((v) => v, onError: (Object e) => e),
        runner.runAuto(id).then<Object>((v) => v, onError: (Object e) => e),
        runner.runNext(id).then<Object>((v) => v, onError: (Object e) => e),
      ]);
      await settle();
      expect(results.whereType<String>(), hasLength(1));
      expect(
        results.whereType<SpecRunException>().map((e) => e.message),
        everyElement(contains('já está iniciando')),
      );
      expect(cli.processes, hasLength(1));
      expect(await c.read(sessionsRepoProvider).bySpec(id), hasLength(1));
      expect(runner.starting, isEmpty);
    });

    test('ticks that overlap respect the parallel limit', () async {
      File('$repo/.promptorium/config.yml')
          .writeAsStringSync('autopilot:\n  paralelo: 1\n');
      final pilot = c.read(autopilotProvider.notifier);
      // A second start of the same spec fails late (the worktree already
      // exists, or one more orphan worktree): no tick may even try it.
      final failed = <String>[];
      final print = debugPrint;
      debugPrint = (m, {wrapWidth}) {
        if (m != null && m.contains('não iniciada')) failed.add(m);
      };
      addTearDown(() => debugPrint = print);
      await Future.wait([
        pilot.start(ws.id),
        pilot.tick(ws.id),
        pilot.tick(ws.id),
      ]);
      await settle();
      expect(failed, isEmpty);
      expect(cli.processes, hasLength(1));
      final now = await specs();
      expect(
        now.values.where((s) => s.stage == SpecStage.running),
        hasLength(1),
      );
    });
  });

  group('SPEC-109 R12: the autopilot with both providers', () {
    late orq.OrchestratorFixture f;

    tearDown(() => f.dispose());

    Future<void> create() async {
      f = await orq.OrchestratorFixture.create(
        codex: true,
        classifier: orq.FakeClassifier(
          kinds: const {'R1': 'mecanica', 'R2': 'mecanica'},
        ),
      );
      await f.prefs.setAutoByDefault(true);
    }

    final hit = QuotaHit(
      provider: 'claude',
      at: DateTime.now(),
      minutes: 300,
      resetsAt: DateTime.now().add(const Duration(hours: 2)),
    );

    test('the rules decide the provider of each step, also with "Executar '
        'spec" on the Codex', () async {
      await create();
      await f.prefs.setRule(
        StepKind.mecanica,
        const StepRule('gpt-6-luna', 'low', provider: 'codex'),
      );
      await f.c
          .read(appSettingsProvider.notifier)
          .set('agent.provider.kind.runSpec', 'codex');
      await f.c.read(autopilotProvider.notifier).start(f.ws.id);
      await orq.waitFor(() async => f.servers.isNotEmpty);
      final s = (await f.sessions()).single;
      expect((s.provider, s.model, s.effort), ('codex', 'gpt-6-luna', 'low'));
      expect((await f.row('R1')).planProvider, 'codex');
      expect((await f.row('R3')).planProvider, isNull);
    });

    test('without quota on the Claude the spec starts with the reserve; '
        'paused, nothing starts nor diverts', () async {
      await create();
      await f.prefs.setDivertOnQuota(true);
      await f.c.read(quotaDiverterProvider).recordHit(hit);
      await f.c.read(automationPausedProvider.notifier).set(true);
      final pilot = f.c.read(autopilotProvider.notifier);
      await pilot.start(f.ws.id);
      await orq.settle();
      expect(f.servers, isEmpty);
      expect(f.cli.processes, isEmpty);

      await f.c.read(automationPausedProvider.notifier).set(false);
      await orq.waitFor(() async => f.servers.isNotEmpty);
      final s = (await f.sessions()).single;
      expect((s.provider, s.model, s.effort), ('codex', 'gpt-6.2-sol', 'low'));
      expect(
        (await f.notes(s.id)).first,
        contains('R1 começou no Codex · gpt-6.2-sol · low'),
      );
    });

    test('with the rules at the default and "Executar spec" on the Codex, it '
        'runs in Manual there, as before', () async {
      await create();
      await f.c
          .read(appSettingsProvider.notifier)
          .set('agent.provider.kind.runSpec', 'codex');
      await f.c.read(autopilotProvider.notifier).start(f.ws.id);
      await orq.waitFor(() async => f.servers.isNotEmpty);
      final s = (await f.sessions()).single;
      expect(s.provider, 'codex');
      expect((await f.row('R1')).planModel, isNull);
    });
  });
}
