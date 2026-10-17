@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/claude/claude_cli.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_rules.dart';
import 'package:promptorium/features/board/spec_runner.dart';
import 'package:promptorium/features/board/step_gate.dart';
import 'package:promptorium/features/review/review_service.dart';
import 'package:promptorium/features/sessions/app_notifier.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/features/specs/spec_service.dart';

import '../core/git/git_test_utils.dart';
import '../helpers/test_db.dart';

/// Real end-to-end run of a spec with two steps (docs/plano-specs-no-quadro,
/// fase 8): one session per step in the spec's worktree, `ETAPA CONCLUÍDA`
/// read from the real answers, auto-advance, Review and merge. haiku, effort
/// low, budget US$ 0.10 per session.
///   flutter test --run-skipped -t integration test/integration/spec_runner_integration_test.dart
void main() {
  test('SpecRunner with the real CLI: two steps, review, merge', () async {
    final home = Platform.environment['HOME'] ?? '';
    final cli = await detectClaudeCli(
      run: Process.run,
      candidates: ['claude', '$home/.local/bin/claude'],
    );
    final tmp = Directory.systemTemp.createTempSync('promptorium-spec-e2e-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = await createRepo(tmp);
    Directory('$repo/specs').createSync();
    File('$repo/specs/SPEC-001-saudacoes.md').writeAsStringSync('''
---
id: SPEC-001
status: aprovada
---

# Saudações

## Objetivo

Dois arquivos de texto com uma saudação cada.

## Requisitos

- R1 · Criar o arquivo ola.txt com o texto exato "ola" (uma linha).
- R2 · Criar o arquivo tchau.txt com o texto exato "tchau" (uma linha).

## Critérios de aceite

- [ ] ola.txt e tchau.txt existem na raiz.
''');
    await gitIn(repo, ['add', '.']);
    await gitIn(repo, ['commit', '-q', '-m', 'spec']);

    final c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        appNotifierProvider.overrideWithValue(const NoopAppNotifier()),
        claudeExecutableProvider.overrideWithValue(cli.executable),
        gitServiceFactoryProvider.overrideWithValue(
          (root) => GitService(root, worktreesBase: '${tmp.path}/wt'),
        ),
      ],
    );
    addTearDown(c.dispose);
    c.listen(sessionManagerProvider, (_, _) {});
    await c.read(appSettingsProvider.notifier).load();
    final settings = c.read(appSettingsProvider.notifier);
    await settings.set(AppSettingKeys.singleSessionSteps, '1');
    final ws = await c.read(workspacesRepoProvider).add(path: repo, name: 'r');
    await c.read(specServiceProvider).sync(ws);
    final spec = (await c
        .read(specsRepoProvider)
        .getByCode(ws.id, 'SPEC-001'))!;
    final m = c.read(sessionManagerProvider.notifier);

    await c
        .read(specRunnerProvider)
        .runNext(spec.id, model: 'haiku', effort: 'low');

    Future<List<StepView>> steps() async => stepsOf(
      (await c.read(specsRepoProvider).getById(spec.id))!,
      await c.read(specStepsRepoProvider).bySpec(spec.id),
    );

    var approved = 0;
    final deadline = DateTime.now().add(const Duration(minutes: 6));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      for (final a in c.read(sessionManagerProvider).approvals) {
        approved++;
        await m.approve(a.sessionId, a.requestId);
      }
      final s = await steps();
      final stage = (await c.read(specsRepoProvider).getById(spec.id))!.stage;
      if (stage == SpecStage.review ||
          s.any((x) => x.status == StepStatus.needsInput)) {
        break;
      }
    }

    final sessions = await c.read(sessionsRepoProvider).bySpec(spec.id);
    final cost = sessions.fold(0.0, (a, s) => a + s.costUsd);
    // ignore: avoid_print
    print(
      'sessões=${sessions.length} aprovações=$approved custo=US\$ $cost '
      'etapas=${(await steps()).map((s) => '${s.id}:${s.status.name}').join(' ')}',
    );
    expect((await steps()).map((s) => s.status).toSet(), {
      StepStatus.done,
    }, reason: 'ambas as etapas devem terminar com ETAPA CONCLUÍDA');
    expect(sessions, hasLength(2));
    expect(sessions.map((s) => s.steps), ['R1', 'R2']);
    expect(sessions.map((s) => s.worktreePath).toSet(), hasLength(1));
    final row = (await c.read(specsRepoProvider).getById(spec.id))!;
    expect(row.stage, SpecStage.review);
    final wt = row.worktreePath!;
    expect(File('$wt/ola.txt').readAsStringSync().trim(), 'ola');
    expect(File('$wt/tchau.txt').readAsStringSync().trim(), 'tchau');
    final log = await gitIn(wt, ['log', '--format=%s', '-5']);
    // ignore: avoid_print
    print('commits do worktree:\n$log');
    expect(log, contains('SPEC-001'));

    // Review: one item for the spec; merge closes it.
    final all = await c
        .read(sessionsRepoProvider)
        .watchByWorkspace(ws.id)
        .first;
    final specs = await c.read(specsRepoProvider).watchByWorkspace(ws.id).first;
    final queue = await c
        .read(reviewServiceProvider)
        .queue(ws, all, const [], specs);
    expect(queue, hasLength(1));
    final r = await c
        .read(reviewServiceProvider)
        .merge(queue.single.session.id);
    expect(r.warnings, isEmpty);
    expect(File('$repo/ola.txt').existsSync(), isTrue);
    expect(File('$repo/tchau.txt').existsSync(), isTrue);
    expect(
      (await c.read(specsRepoProvider).getById(spec.id))!.stage,
      SpecStage.done,
    );
    expect(
      File('$repo/specs/SPEC-001-saudacoes.md').readAsStringSync(),
      contains('status: concluida'),
    );
    expect((await gitIn(repo, ['status', '--porcelain'])).trim(), isEmpty);
    for (final s in await c.read(sessionsRepoProvider).bySpec(spec.id)) {
      await m.stop(s.id);
    }
  }, timeout: const Timeout(Duration(minutes: 9)));

  // Wave 1 of docs/plano-melhorias-ides.md: the gate refuses R2 once (a
  // check the spec does not mention) and the agent fixes it by itself.
  // 2026-10-17, haiku: 2 sessions, 1 resend, US$ 0.010. haiku may also run
  // the tests itself, see the failure and ask instead of writing the marker
  // (R2 then waits for the user) — the prompt allows that.
  //   flutter test --run-skipped -t integration --plain-name 'gate' test/integration/spec_runner_integration_test.dart
  test('gate with the real CLI: R2 refused, fixed after the resend', () async {
    final home = Platform.environment['HOME'] ?? '';
    final cli = await detectClaudeCli(
      run: Process.run,
      candidates: ['claude', '$home/.local/bin/claude'],
    );
    final tmp = Directory.systemTemp.createTempSync('promptorium-gate-e2e-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = await createRepo(tmp);
    Directory('$repo/specs').createSync();
    File('$repo/specs/SPEC-001-saudacoes.md').writeAsStringSync('''
---
id: SPEC-001
status: aprovada
---

# Saudações

## Requisitos

- R1 · Criar o arquivo ola.txt com o texto exato "ola" (uma linha).
- R2 · Criar o arquivo tchau.txt com o texto exato "tchau" (uma linha).
''');
    // The test only fails once tchau.txt exists and assinatura.txt does not.
    File('$repo/check.sh').writeAsStringSync('''
if [ -f tchau.txt ] && [ ! -f assinatura.txt ]; then
  echo "FALHOU: com tchau.txt, crie também assinatura.txt com o texto fim"
  exit 1
fi
echo "ok"
''');
    await gitIn(repo, ['add', '.']);
    await gitIn(repo, ['commit', '-q', '-m', 'spec']);
    Directory('$repo/.promptorium').createSync();
    File(
      '$repo/.promptorium/config.yml',
    ).writeAsStringSync('testes: sh check.sh\nverificacao:\n  tentativas: 2\n');

    final c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        appNotifierProvider.overrideWithValue(const NoopAppNotifier()),
        claudeExecutableProvider.overrideWithValue(cli.executable),
        gitServiceFactoryProvider.overrideWithValue(
          (root) => GitService(root, worktreesBase: '${tmp.path}/wt'),
        ),
      ],
    );
    addTearDown(c.dispose);
    c.listen(sessionManagerProvider, (_, _) {});
    await c.read(appSettingsProvider.notifier).load();
    await c
        .read(appSettingsProvider.notifier)
        .set(AppSettingKeys.singleSessionSteps, '1');
    final ws = await c.read(workspacesRepoProvider).add(path: repo, name: 'r');
    await c.read(specServiceProvider).sync(ws);
    final spec = (await c
        .read(specsRepoProvider)
        .getByCode(ws.id, 'SPEC-001'))!;
    final m = c.read(sessionManagerProvider.notifier);
    await c
        .read(specRunnerProvider)
        .runNext(
          spec.id,
          model: 'haiku',
          effort: 'low',
          mode: ClaudePermissionMode.acceptEdits,
        );

    Future<List<SpecStep>> rows() =>
        c.read(specStepsRepoProvider).bySpec(spec.id);
    final deadline = DateTime.now().add(const Duration(minutes: 8));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      for (final a in c.read(sessionManagerProvider).approvals) {
        await m.approve(a.sessionId, a.requestId);
      }
      final stage = (await c.read(specsRepoProvider).getById(spec.id))!.stage;
      final r = await rows();
      if (stage == SpecStage.review ||
          r.any((x) => x.status == StepStatus.needsInput)) {
        break;
      }
    }
    final r = {for (final x in await rows()) x.step: x};
    final sessions = await c.read(sessionsRepoProvider).bySpec(spec.id);
    final cost = sessions.fold(0.0, (a, s) => a + s.costUsd);
    // ignore: avoid_print
    print(
      'sessões=${sessions.length} custo=US\$ $cost '
      'R1=${r['R1']?.status.name} R2=${r['R2']?.status.name} '
      'reenvios R2=${r['R2']?.gateAttempts} '
      'gate R2=${GateReport.decode(r['R2']?.gateReport)?.summary}',
    );
    expect(r['R1']!.status, StepStatus.done);
    expect(r['R2']!.status, StepStatus.done);
    final wt = (await c.read(specsRepoProvider).getById(spec.id))!
        .worktreePath!;
    expect(File('$wt/assinatura.txt').existsSync(), isTrue);
    for (final s in sessions) {
      await m.stop(s.id);
    }
  }, timeout: const Timeout(Duration(minutes: 9)));
}
