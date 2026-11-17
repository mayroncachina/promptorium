import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/activity_events_repo.dart';
import 'package:promptorium/features/board/board_screen.dart'
    show specStepsProvider;
import 'package:promptorium/features/board/step_gate.dart';
import 'package:promptorium/features/prompt/conversation_manager.dart';
import 'package:promptorium/features/repository/releases/release_dispatcher.dart';
import 'package:promptorium/features/resume/activity_journal.dart';
import 'package:promptorium/features/review/ci_fixer.dart';
import 'package:promptorium/features/review/pr_babysitter.dart';
import 'package:promptorium/features/sessions/session_manager.dart';

import '../../helpers/test_db.dart';
import '../activities/activity_test.dart' show session, spec, step;

final now = DateTime(2026, 11, 17, 9);

SpecStep withGate(SpecStep s, {required bool ok, DateTime? doneAt}) =>
    s.copyWith(
      doneAt: Value(doneAt),
      gateReport: Value(
        GateReport(
          checks: [GateCheck(name: 'testes', ok: ok)],
          at: now,
        ).encode(),
      ),
    );

JournalSession js(String id, {Spec? spec, String? prUrl}) =>
    (id: id, workspaceId: 1, title: 'Sessão $id', spec: spec, prUrl: prUrl);

void main() {
  wiring();
  group('specTransitions (R6)', () {
    final s = spec(7, 'SPEC-077');

    test('the gate passed on steps: one event with the range', () {
      final before = [
        step(7, 'R1', StepStatus.verifying),
        step(7, 'R2', StepStatus.verifying),
      ];
      final after = [
        withGate(before[0], ok: true, doneAt: now),
        withGate(before[1], ok: true, doneAt: now),
      ];
      final out = specTransitions(
        workspaceId: 1,
        before: [s],
        after: [s],
        stepsBefore: before,
        stepsAfter: after,
        now: now,
      );
      expect(out, hasLength(1));
      expect(out.single.kind, JournalKind.gate);
      expect(out.single.outcome, JournalOutcome.ok);
      expect(out.single.detail, 'passou no gate · R1–R2');
      expect(out.single.title, 'SPEC-077 · Título SPEC-077');
      expect(out.single.seed, 'spec:1:SPEC-077');
      expect(out.single.groupKey, 'spec:7');
    });

    test('the gate failed and the spec went to Review / concluded', () {
      final before = [step(7, 'R3', StepStatus.verifying)];
      final after = [withGate(before[0], ok: false)];
      final out = specTransitions(
        workspaceId: 1,
        before: [s],
        after: [s.copyWith(stage: SpecStage.review)],
        stepsBefore: before,
        stepsAfter: after,
        now: now,
      );
      expect(out.map((e) => e.detail), [
        'falhou no gate em R3 · testes',
        'foi para Review',
      ]);
      expect(out.first.outcome, JournalOutcome.failed);

      final done = specTransitions(
        workspaceId: 1,
        before: [s.copyWith(stage: SpecStage.review)],
        after: [s.copyWith(stage: SpecStage.done)],
        stepsBefore: const [],
        stepsAfter: const [],
        now: now,
      );
      expect(done.single.detail, 'concluída');
    });

    test('a step done without a gate; nothing changed writes nothing', () {
      final before = [step(7, 'R1', StepStatus.running)];
      final after = [before[0].copyWith(doneAt: Value(now))];
      expect(
        specTransitions(
          workspaceId: 1,
          before: [s],
          after: [s],
          stepsBefore: before,
          stepsAfter: after,
          now: now,
        ).single.detail,
        'terminou a etapa R1',
      );
      expect(
        specTransitions(
          workspaceId: 1,
          before: [s],
          after: [s],
          stepsBefore: before,
          stepsAfter: before,
          now: now,
        ),
        isEmpty,
      );
    });
  });

  test('stepRange', () {
    expect(stepRange(['R1']), 'R1');
    expect(stepRange(['R3', 'R1', 'R2']), 'R1–R3');
    expect(stepRange(['R1', 'R3']), 'R1, R3');
    expect(stepRange(['REV1', 'R2']), 'REV1, R2');
  });

  test('sessionTransitions: the PR opened and the session failed (R6)', () {
    final s = spec(7, 'SPEC-077');
    final out = sessionTransitions(
      workspaceId: 1,
      before: [session('a', specId: 7), session('b')],
      after: [
        session('a', specId: 7, prUrl: 'https://github.com/o/r/pull/267'),
        session('b', status: SessionStatus.failed),
      ],
      specs: {7: s},
      now: now,
    );
    expect(out.map((e) => e.detail), ['PR #267 aberto', 'parou com erro']);
    expect(out.first.prNumber, 267);
    expect(out.first.groupKey, 'spec:7');
    expect(out.last.outcome, JournalOutcome.failed);
    expect(out.last.groupKey, 'session:b');
  });

  group('prTransitions (R6)', () {
    const url = 'https://github.com/o/r/pull/270';
    PrWatch w(
      String state, {
      List<PrCheck> checks = const [],
      String sha = 'a',
    }) => PrWatch(
      status: PrStatus(state: state, checks: checks, headSha: sha),
    );

    test('merged in GitHub and closed without merge', () {
      final sessions = {'a': js('a', prUrl: url), 'b': js('b', prUrl: url)};
      final out = prTransitions(
        before: {'a': w('OPEN'), 'b': w('OPEN')},
        after: {'a': w('MERGED'), 'b': w('CLOSED')},
        sessions: sessions,
        now: now,
      );
      expect(out.map((e) => e.detail), [
        'PR #270 mergeado',
        'PR #270 fechado sem merge',
      ]);
      expect(out.first.title, 'PR #270');
      expect(out.first.groupKey, 'pr:1:270');
      expect(out.last.outcome, JournalOutcome.attention);
    });

    test(
      'the CI failed (named checks) and then passed; running is not news',
      () {
        final sessions = {'a': js('a', spec: spec(7, 'SPEC-077'), prUrl: url)};
        const fail = PrCheck(name: 'test', state: 'FAILURE');
        const ok = PrCheck(name: 'test', state: 'SUCCESS');
        const run = PrCheck(name: 'test', state: 'IN_PROGRESS');
        final failed = prTransitions(
          before: {
            'a': w('OPEN', checks: [run]),
          },
          after: {
            'a': w('OPEN', checks: [fail]),
          },
          sessions: sessions,
          now: now,
        );
        expect(failed.single.kind, JournalKind.ci);
        expect(failed.single.outcome, JournalOutcome.failed);
        expect(failed.single.detail, 'CI do PR #270 falhou em `test`');
        expect(failed.single.groupKey, 'spec:7');
        final passed = prTransitions(
          before: {
            'a': w('OPEN', checks: [fail]),
          },
          after: {
            'a': w('OPEN', checks: [ok], sha: 'b'),
          },
          sessions: sessions,
          now: now,
        );
        expect(passed.single.detail, 'CI do PR #270 passou');
        expect(
          prTransitions(
            before: {
              'a': w('OPEN', checks: [fail]),
            },
            after: {
              'a': w('OPEN', checks: [run], sha: 'b'),
            },
            sessions: sessions,
            now: now,
          ),
          isEmpty,
        );
      },
    );
  });

  test('ciFixTransitions: fixed and gave up (R6)', () {
    CiFixState st(CiFixPhase p) => CiFixState(phase: p, since: now, round: 2);
    final out = ciFixTransitions(
      before: {'a': st(CiFixPhase.running), 'b': st(CiFixPhase.fixing)},
      after: {'a': st(CiFixPhase.fixed), 'b': st(CiFixPhase.noCommit)},
      sessions: {
        'a': js('a', prUrl: 'https://github.com/o/r/pull/9'),
        'b': js('b'),
      },
      now: now,
    );
    expect(out.map((e) => e.detail), [
      'Corrigir CI corrigiu na rodada 2',
      'Corrigir CI desistiu na rodada 2',
    ]);
    expect(out.map((e) => e.outcome), [
      JournalOutcome.ok,
      JournalOutcome.failed,
    ]);
  });

  test('releaseTransitions: published once, failed, cancelled ignored', () {
    ReleaseRun r(String tag, ReleaseRunStatus s) => ReleaseRun(
      workspaceId: 1,
      repoPath: '/r',
      version: tag.substring(1),
      tag: tag,
      branch: 'main',
      dispatchedAt: now,
      status: s,
      failedJob: s == ReleaseRunStatus.failure ? 'build' : null,
    );
    final published = releaseTransitions(
      before: {1: r('v0.18.0', ReleaseRunStatus.running)},
      after: {1: r('v0.18.0', ReleaseRunStatus.success)},
      now: now,
    );
    expect(published.single.detail, 'publicada');
    expect(published.single.releaseTag, 'v0.18.0');
    expect(published.single.groupKey, 'release:1:v0.18.0');
    expect(
      releaseTransitions(
        before: {1: r('v0.18.0', ReleaseRunStatus.success)},
        after: {1: r('v0.18.0', ReleaseRunStatus.success)},
        now: now,
      ),
      isEmpty,
    );
    expect(
      releaseTransitions(
        before: {1: r('v0.19.0', ReleaseRunStatus.running)},
        after: {1: r('v0.19.0', ReleaseRunStatus.failure)},
        now: now,
      ).single.detail,
      'falhou em `build`',
    );
    expect(
      releaseTransitions(
        before: {1: r('v0.19.0', ReleaseRunStatus.running)},
        after: {1: r('v0.19.0', ReleaseRunStatus.cancelled)},
        now: now,
      ),
      isEmpty,
    );
  });

  test('turnTransitions: only long turns of sessions out of the Quadro', () {
    final start = now.subtract(const Duration(minutes: 4));
    final short = now.subtract(const Duration(minutes: 1));
    final out = turnTransitions(
      before: SessionManagerState(
        live: {
          'a': LiveSession(busySince: start),
          'b': LiveSession(busySince: short),
          'c': LiveSession(busySince: start),
        },
      ),
      after: const SessionManagerState(
        live: {'a': LiveSession(), 'b': LiveSession(), 'c': LiveSession()},
      ),
      sessions: {
        'a': js('a'),
        'b': js('b'),
        'c': js('c', spec: spec(7, 'SPEC-077')),
      },
      now: now,
    );
    expect(out.single.sessionId, 'a');
    expect(out.single.detail, 'terminou um turno de 4 min');
  });

  test('conversationTransitions: a long Prompt turn; VIBE uses the spec', () {
    final start = now.subtract(const Duration(minutes: 3));
    final out = conversationTransitions(
      before: ConversationManagerState(
        live: {
          1: LiveConversation(busy: true, busySince: start),
          2: LiveConversation(busy: true, busySince: start),
        },
      ),
      after: const ConversationManagerState(
        live: {1: LiveConversation(), 2: LiveConversation()},
      ),
      conversations: {
        1: (id: 1, workspaceId: 1, title: 'Pedidos', spec: null),
        2: (
          id: 2,
          workspaceId: 1,
          title: 'x',
          spec: spec(9, 'SPEC-090', kind: SpecKind.vibe),
        ),
      },
      now: now,
    );
    expect(out.map((e) => e.title), ['Pedidos', 'SPEC-090 · Título SPEC-090']);
    expect(out.first.kind, JournalKind.conversation);
  });

  test('the Autopilot started a spec and finished the queue', () {
    final s = spec(8, 'SPEC-078');
    expect(autopilotStarted(1, s, now: now).detail, 'Autopilot começou');
    expect(autopilotStarted(1, s, now: now).groupKey, 'spec:8');
    final end = autopilotFinished(1, 2, now: now);
    expect(end.detail, 'terminou a fila · 2 specs em Review');
    expect(end.groupKey, 'autopilot:1');
  });

  group('the repository', () {
    late AppDatabase db;
    late ActivityEventsRepo repo;
    setUp(() async {
      db = memoryDatabase();
      repo = ActivityEventsRepo(db);
      await db.customStatement(
        "INSERT INTO workspaces (id, path, name) VALUES (1, '/r', 'r')",
      );
    });
    tearDown(() => db.close());

    test('writes, reads since a time and keeps the row whole', () async {
      final e = autopilotStarted(1, spec(8, 'SPEC-078'), now: now);
      await writeJournal(repo, e);
      final rows = await repo.since(now.subtract(const Duration(hours: 1)));
      final back = JournalEntry.fromRow(rows.single);
      expect(back.kind, JournalKind.autopilot);
      expect(back.groupKey, 'spec:8');
      expect(back.seed, 'spec:1:SPEC-078');
      expect(await repo.since(now), isEmpty);
    });

    test('deletes what is older than 14 days (P6)', () async {
      for (final days in [1, 13, 15, 30]) {
        await writeJournal(
          repo,
          autopilotFinished(1, 0, now: now.subtract(Duration(days: days))),
        );
      }
      expect(await repo.purgeOlderThan(now: now), 2);
      expect(await repo.since(DateTime(2000)), hasLength(2));
    });
  });
}

void wiring() {
  test('ActivityJournal follows the specs and writes the gate (R6)', () async {
    final db = memoryDatabase();
    await db.customStatement(
      "INSERT INTO workspaces (id, path, name) VALUES (1, '/r', 'r')",
    );
    final ws = Workspace(id: 1, path: '/r', name: 'r', createdAt: now);
    final steps = StreamController<List<SpecStep>>();
    final s = spec(7, 'SPEC-077');
    final container = ProviderContainer(
      overrides: [
        databaseOverride(db),
        workspacesProvider.overrideWith((ref) => Stream.value([ws])),
        specsProvider.overrideWith((ref, id) => Stream.value([s])),
        specStepsProvider.overrideWith((ref, id) => steps.stream),
        sessionsProvider.overrideWith((ref, id) => Stream.value(const [])),
        conversationsProvider.overrideWith((ref, id) => Stream.value(const [])),
      ],
    );
    addTearDown(container.dispose);
    final journal = ActivityJournal(container)..start();
    addTearDown(journal.dispose);
    final before = step(7, 'R1', StepStatus.verifying);
    steps.add([before]);
    await pumpEventQueue();
    steps.add([withGate(before, ok: true, doneAt: now)]);
    await pumpEventQueue();
    final rows = await ActivityEventsRepo(db).since(DateTime(2000));
    expect(rows.single.detail, 'passou no gate · R1');
    expect(rows.single.kind, 'gate');
  });
}
