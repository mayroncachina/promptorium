import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_rules.dart' show StepView;
import 'package:promptorium/features/board/orchestrator/orchestrator_rules.dart';
import 'package:promptorium/features/board/orchestrator/quota_divert.dart';
import 'package:promptorium/features/board/orchestrator/quota_diverter.dart';
import 'package:promptorium/features/board/spec_runner.dart';
import 'package:promptorium/features/board/widgets/quota_widgets.dart';
import 'package:promptorium/ui/providers/provider_logos.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';

class _Runner extends SpecRunner {
  _Runner(super.ref);

  final ran = <StepRule>[];

  @override
  Future<List<StepRule>> runNowChoices(int specId) async => const [
    StepRule('opus', 'high'),
    StepRule('gpt-6.2-sol', 'high', provider: 'codex'),
  ];

  @override
  Future<String> runNow(int specId, StepRule rule) async {
    ran.add(rule);
    return 's';
  }
}

void main() {
  late ProviderContainer c;
  late _Runner runner;

  final renewClaude = DateTime.now().add(const Duration(hours: 3));
  final renewCodex = DateTime.now().add(const Duration(hours: 1));

  Future<void> show(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Center(child: SizedBox(width: 520, child: child)),
          ),
        ),
      ),
    );
  }

  Future<void> pump(WidgetTester tester, Widget child) async {
    c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        databaseOverride(memoryDatabase()),
        specRunnerProvider.overrideWith((ref) => runner = _Runner(ref)),
      ],
    );
    addTearDown(c.dispose);
    await tester.runAsync(() => c.read(appSettingsProvider.notifier).load());
    await show(tester, child);
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  // A step run needs its spec (foreign key): the first one of the
  // memory database, id 1.
  Future<void> seedSpec(WidgetTester tester) async {
    final id = await tester.runAsync(() async {
      final ws = await c
          .read(workspacesRepoProvider)
          .add(path: '/r', name: 'r');
      final spec = await c
          .read(specsRepoProvider)
          .insert(
            workspaceId: ws.id,
            code: 'SPEC-001',
            title: 'x',
            path: 'specs/x.md',
          );
      return spec.id;
    });
    expect(id, 1);
  }

  // The drift stream of the step runs answers outside the fake clock.
  Future<void> settleRuns(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
  }

  // The step runs are a drift stream: unmount and let its timer run.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('R8: the renewals of each provider and the three actions; the '
      'resume is scheduled for the first one and can be cancelled', (
    tester,
  ) async {
    await pump(tester, const QuotaWaitPanel(specId: 7));
    expect(key('quota-wait-7'), findsNothing);
    final d = c.read(quotaDiverterProvider);
    await tester.runAsync(
      () => d.setWait(
        7,
        SpecQuotaWait(
          step: 'R5',
          blocks: [
            QuotaBlock(
              'claude',
              out: QuotaOut('claude', minutes: 300, resetsAt: renewClaude),
            ),
            QuotaBlock(
              'codex',
              out: QuotaOut('codex', minutes: 300, resetsAt: renewCodex),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sem cota nos dois provedores.'), findsOneWidget);
    expect(find.text('renova ${quotaClockWords(renewClaude)}'), findsOneWidget);
    expect(find.byType(ProviderChip), findsNWidgets(2));
    expect(key('quota-wait-manual-7'), findsOneWidget);
    expect(
      find.text('Retomar quando renovar · ${quotaClock(renewCodex)}'),
      findsOneWidget,
    );
    await tester.runAsync(() async {
      await tester.tap(key('quota-wait-resume-7'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(d.waitOf(7)!.resumeAt!.difference(renewCodex).inSeconds, 0);
    await tester.runAsync(() async {
      await tester.tap(key('quota-wait-cancel-7'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(d.waitOf(7)!.resumeAt, isNull);

    // "Executar agora com…": the plan and the reserve, by name.
    await tester.tap(key('quota-wait-now-7'));
    await tester.pumpAndSettle();
    expect(find.text('Opus · high · plano'), findsOneWidget);
    expect(find.text('gpt-6.2-sol · high · reserva'), findsOneWidget);
    await tester.tap(key('quota-run-now-codex'));
    await tester.pumpAndSettle();
    expect(runner.ran.single.provider, 'codex');
  });

  testWidgets('R14: the line of a diverted step has text and the screen '
      'reader hears the reason', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(
      tester,
      const Column(
        children: [
          SpecDivertLine(specId: 7, step: 'R4', provider: true),
          SpecDivertLine(specId: 7, step: 'R5'),
        ],
      ),
    );
    final at = DateTime(2026, 11, 25, 18);
    await tester.runAsync(
      () => c
          .read(quotaDiverterProvider)
          .setDivert(
            7,
            SpecDivert(
              step: 'R4',
              from: 'claude',
              to: const StepRule('gpt-6.2-sol', 'high', provider: 'codex'),
              reason: DivertReason.quota,
              why: 'x',
              until: at,
            ),
          ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Codex'), findsOneWidget);
    expect(find.text('gpt-6.2-sol · high'), findsOneWidget);
    expect(find.textContaining('desviada: cota do Claude'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        RegExp(
          'R4 desviada para o Codex: cota do Claude esgotada, renova às 18 '
          'horas',
        ),
      ),
      findsOneWidget,
    );
    semantics.dispose();
    await unmount(tester);
  });

  testWidgets('R14: a step that ran diverted keeps the badge after the '
      'divert of the spec moves on or ends', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, const SizedBox());
    await seedSpec(tester);
    // Written before the lines watch them: the drift stream answers in the
    // fake zone, and writes under a live watch would wait on it.
    final repo = c.read(stepRunsRepoProvider);
    await tester.runAsync(() async {
      // R1: interrupted on the Claude, then passed on the Codex.
      await repo.add(
        specId: 1,
        step: 'R1',
        kind: 'mecanica',
        model: 'haiku',
        effort: 'low',
        result: StepRunResult.diverted,
        diverted: DivertReason.quota.stored,
      );
      await repo.add(
        specId: 1,
        step: 'R1',
        kind: 'mecanica',
        model: 'gpt-6.2-sol',
        effort: 'low',
        result: StepRunResult.passed,
        provider: 'codex',
        diverted: DivertReason.quota.stored,
      );
      // R2: back on its plan.
      await repo.add(
        specId: 1,
        step: 'R2',
        kind: 'implementacao',
        model: 'sonnet',
        effort: 'medium',
        result: StepRunResult.passed,
      );
    });
    await show(
      tester,
      const Column(
        children: [
          SpecDivertLine(specId: 1, step: 'R1', provider: true),
          SpecDivertLine(specId: 1, step: 'R2', provider: true),
          SpecDivertLine(specId: 1, step: 'R1'),
        ],
      ),
    );
    await settleRuns(tester);
    expect(key('step-divert-run-R1'), findsOneWidget);
    expect(key('step-divert-run-R2'), findsNothing);
    expect(find.text('Codex'), findsOneWidget);
    expect(find.text('gpt-6.2-sol · low'), findsOneWidget);
    expect(find.text('desviada: cota do Claude'), findsOneWidget);
    expect(
      find.bySemanticsLabel('R1 rodou no Codex, desviada: cota do Claude'),
      findsOneWidget,
    );

    // The divert of the spec now on R2: R1 keeps its line from the run, R2
    // shows the live one, once each.
    await tester.runAsync(
      () => c
          .read(quotaDiverterProvider)
          .setDivert(
            1,
            const SpecDivert(
              step: 'R2',
              from: 'claude',
              to: StepRule('gpt-6.2-sol', 'medium', provider: 'codex'),
              reason: DivertReason.quota,
              why: 'x',
            ),
          ),
    );
    await tester.pumpAndSettle();
    expect(key('step-divert-run-R1'), findsOneWidget);
    expect(key('spec-divert-1-step'), findsOneWidget);
    expect(find.text('Codex'), findsNWidgets(2));
    semantics.dispose();
    await unmount(tester);
  });

  testWidgets('R9: the Codex plan line gives way to the run that went to the '
      'Claude', (tester) async {
    await pump(
      tester,
      const StepPlanLine(
        specId: 1,
        step: StepView(
          id: 'R1',
          text: 't',
          status: StepStatus.done,
          planProvider: 'codex',
          planModel: 'gpt-6.2-sol',
          planEffort: 'low',
        ),
      ),
    );
    expect(key('step-plan-line-R1'), findsOneWidget);
    await seedSpec(tester);
    await tester.runAsync(
      () => c
          .read(stepRunsRepoProvider)
          .add(
            specId: 1,
            step: 'R1',
            kind: 'mecanica',
            model: 'haiku',
            effort: 'low',
            result: StepRunResult.passed,
            diverted: DivertReason.quota.stored,
          ),
    );
    await settleRuns(tester);
    expect(key('step-plan-line-R1'), findsNothing);
    await unmount(tester);
  });
}
