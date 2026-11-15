import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_screen.dart' show SpecCardData;
import 'package:promptorium/features/board/spec_runner.dart';
import 'package:promptorium/features/board/widgets/ci_badge.dart';
import 'package:promptorium/features/review/ci_fixer.dart';
import 'package:promptorium/features/review/pr_babysitter.dart';
import 'package:promptorium/ui/theme/tokens.dart';

import '../../helpers/test_db.dart';

PrStatus status({
  String sha = 'a1b2c3d4',
  List<(String, String, bool)> checks = const [
    ('test', 'FAILURE', true),
    ('lint', 'FAILURE', true),
    ('build', 'SUCCESS', true),
  ],
}) => parsePrView(
  jsonEncode({
    'state': 'OPEN',
    'headRefOid': sha,
    'statusCheckRollup': [
      for (final (name, state, log) in checks)
        log
            ? {
                'name': name,
                'conclusion': state,
                'detailsUrl': 'https://github.com/o/r/actions/runs/1/job/2',
              }
            : {'context': name, 'state': state},
    ],
  }),
)!;

CiFixState fix(
  CiFixPhase phase, {
  DateTime? since,
  String? pushed,
  int round = 1,
}) => CiFixState(
  phase: phase,
  since: since ?? DateTime(2026, 11, 15, 10),
  sha: 'a1b2c3d4',
  checks: 2,
  pushedSha: pushed,
  round: round,
);

class _Babysitter extends PrBabysitter {
  _Babysitter(this.watches);
  final Map<String, PrWatch> watches;
  @override
  Map<String, PrWatch> build() => watches;
}

class _Fixer extends CiFixer {
  _Fixer(this.states);
  final Map<String, CiFixState> states;
  @override
  Map<String, CiFixState> build() => states;
}

void main() {
  group('SPEC-073 R7 · ciBadgeOf', () {
    final now = DateTime(2026, 11, 15, 10, 3);

    test('falhou, corrigindo, rodando e corrigido', () {
      final failed = ciBadgeOf(status(), null)!;
      expect(failed.label, 'CI falhou · 2');
      expect(failed.color, AppColors.red);
      expect(failed.action, 'Corrigir CI');
      expect(failed.disabledReason, isNull);

      final fixing = ciBadgeOf(status(), fix(CiFixPhase.fixing), now: now)!;
      expect(fixing.label, 'Corrigindo CI · 3 min');
      expect(fixing.color, AppColors.amber);
      expect(fixing.action, isNull);

      final running = ciBadgeOf(
        status(),
        fix(CiFixPhase.running, pushed: 'b7e4f19aa'),
      )!;
      expect(running.label, 'CI rodando · b7e4f19');

      final fixed = ciBadgeOf(status(), fix(CiFixPhase.fixed))!;
      expect(fixed.label, 'CI corrigido · 1 rodada');
      expect(fixed.color, AppColors.teal);
    });

    test('na fila tem Cancelar; parado tem Corrigir CI', () {
      final q = ciBadgeOf(status(), fix(CiFixPhase.queued))!;
      expect(q.label, 'Na fila · sessão ocupada');
      expect(q.action, 'Cancelar');
      final stopped = ciBadgeOf(status(), fix(CiFixPhase.stopped))!;
      expect(stopped.label, 'CI falhou de novo · automático parado');
      expect(stopped.action, 'Corrigir CI');
    });

    test('nothing without the PR state or with green CI; only checks '
        'without log turn the button off', () {
      expect(ciBadgeOf(null, null), isNull);
      expect(
        ciBadgeOf(status(checks: [('build', 'SUCCESS', true)]), null),
        isNull,
      );
      final noLog = ciBadgeOf(
        status(checks: [('Vercel', 'FAILURE', false)]),
        null,
      )!;
      expect(noLog.disabledReason, 'Nenhum check com log do GitHub Actions');
    });
  });

  testWidgets('the card shows the badge of its PR session', (tester) async {
    final db = memoryDatabase();
    addTearDown(db.close);
    final spec = Spec(
      hasPlan: false,
      inTray: false,
      kind: SpecKind.spec,
      id: 1,
      workspaceId: 1,
      code: 'SPEC-021',
      title: 'Cupom',
      status: SpecStatus.approved,
      path: 'specs/a.md',
      stage: SpecStage.review,
      requirements: const [],
      dependsOn: const [],
      autoAdvance: false,
      reviewRounds: 0,
      gateResends: 0,
      rejectedHunks: 0,
    );
    final session = Session(
      provider: 'claude',
      id: 's1',
      workspaceId: 1,
      worktreePath: '/r',
      branch: 'spec/021',
      model: 'sonnet',
      status: SessionStatus.completed,
      prUrl: 'https://github.com/o/r/pull/57',
      startedAt: DateTime(2026),
      costUsd: 0,
      tokensIn: 0,
      tokensOut: 0,
    );
    final data = SpecCardData(
      spec: spec,
      steps: const [],
      sessions: [session],
      blockers: const [],
    );
    Future<void> pump(Map<String, CiFixState> fixes) async {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            databaseOverride(db),
            prBabysitterProvider.overrideWith(
              () => _Babysitter({'s1': PrWatch(status: status())}),
            ),
            ciFixerProvider.overrideWith(() => _Fixer(fixes)),
          ],
          child: MaterialApp(
            home: Scaffold(body: CiBadge(data: data)),
          ),
        ),
      );
      await tester.pump();
    }

    await pump(const {});
    expect(find.text('CI falhou · 2'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('board-ci-action-SPEC-021')),
      findsOneWidget,
    );
    await pump({'s1': fix(CiFixPhase.fixed)});
    expect(find.text('CI corrigido · 1 rodada'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('board-ci-action-SPEC-021')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
  });

  test('fixing the CI keeps the card in Review (P3)', () async {
    final db = memoryDatabase();
    addTearDown(db.close);
    Future<SpecStage> afterActive({required bool fixing}) async {
      final c = ProviderContainer(
        overrides: [
          databaseOverride(db),
          ciFixerProvider.overrideWith(
            () => _Fixer({if (fixing) 's1': fix(CiFixPhase.fixing)}),
          ),
        ],
      );
      addTearDown(c.dispose);
      final specs = c.read(specsRepoProvider);
      await specs.setStage(1, SpecStage.review);
      await c.read(specRunnerProvider).onActive('s1');
      return (await specs.getById(1))!.stage;
    }

    final c = ProviderContainer(overrides: [databaseOverride(db)]);
    addTearDown(c.dispose);
    final ws = await c.read(workspacesRepoProvider).add(path: '/r', name: 'r');
    final spec = await c
        .read(specsRepoProvider)
        .insert(
          workspaceId: ws.id,
          code: 'SPEC-021',
          title: 'Cupom',
          path: 'specs/a.md',
        );
    await c
        .read(sessionsRepoProvider)
        .insert(
          id: 's1',
          workspaceId: ws.id,
          worktreePath: '/r',
          branch: 'spec/021',
          model: 'sonnet',
          specId: spec.id,
        );
    expect(await afterActive(fixing: true), SpecStage.review);
    // Any other turn of the spec's session moves it, as before.
    expect(await afterActive(fixing: false), SpecStage.running);
  });
}
