import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/claude/readonly_run.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_screen.dart';
import 'package:promptorium/features/board/orchestrator/orchestrator_rules.dart';
import 'package:promptorium/features/board/orchestrator/step_classifier.dart';
import 'package:promptorium/features/board/orchestrator/step_plan.dart';
import 'package:promptorium/features/board/widgets/run_spec_dialog.dart';
import 'package:promptorium/features/project/project_config.dart';
import 'package:promptorium/features/sessions/agent_names.dart';
import 'package:promptorium/features/settings/settings_sections.dart';
import 'package:promptorium/features/sessions/widgets/session_style.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:promptorium/ui/widgets/app_dialog.dart';

import '../../helpers/test_db.dart';

const _spec = Spec(
  hasPlan: false,
  inTray: false,
  kind: SpecKind.spec,
  id: 7,
  workspaceId: 1,
  code: 'SPEC-012',
  title: 'Relatório',
  status: SpecStatus.approved,
  path: 'specs/SPEC-012.md',
  stage: SpecStage.backlog,
  requirements: [
    (id: 'R1', text: 'Renomear as constantes de status'),
    (id: 'R2', text: 'Criar a tabela de relatórios'),
    (id: 'R3', text: 'Tela de filtros do relatório'),
    (id: 'R4', text: 'Exportar para CSV'),
  ],
  dependsOn: [],
  autoAdvance: false,
  reviewRounds: 0,
  gateResends: 0,
  rejectedHunks: 0,
);

Map<String, Object?> _kinds(Map<String, String> kinds) => {
  'steps': [
    for (final e in kinds.entries)
      {'id': e.key, 'kind': e.value, 'reason': 'motivo de ${e.key}'},
  ],
};

/// Answers each classification with the next completer of [answers].
class _FakeClassifier extends StepClassifier {
  _FakeClassifier(this.answers);

  final List<Completer<Object?>> answers;
  var calls = 0;

  @override
  Future<Object?> request(
    Spec spec,
    List<ClassifierTarget> targets,
    Future<void> cancelled,
  ) {
    final c = Completer<Object?>();
    answers.add(c);
    calls++;
    return c.future;
  }

  /// A new classification of [spec] arrives with other [kinds].
  void reclassify(Spec spec, Map<String, StepKind> kinds) => state = {
    ...state,
    spec.id: StepClassifierState(
      StepClassifierResult(
        kinds: {
          for (final e in kinds.entries)
            e.key: StepClassification(
              kind: e.value,
              reason: 'motivo de ${e.key}',
              hash: stepTextHash(
                spec.requirements.firstWhere((r) => r.id == e.key).text,
              ),
            ),
        },
      ),
    ),
  };
}

class _Settings extends AppSettingsController {
  _Settings(this.initial);

  final Map<String, String> initial;

  @override
  Map<String, String> build() => initial;

  @override
  Future<void> set(String key, String value) async =>
      state = {...state, key: value};
}

void main() {
  test(
    'R5: neighbour steps with the same model and effort are one session',
    () {
      const h = StepRule('haiku', 'low');
      const s = StepRule('sonnet', 'medium');
      const o = StepRule('opus', 'high');
      expect(planSessions(const []), 0);
      expect(planSessions(const [s, s, s]), 1);
      expect(planSessions(const [h, o, s, s, h]), 4);
      expect(planSessions(const [s, StepRule('sonnet', 'high')]), 2);
      expect(planSessionsLabel(1), startsWith('1 sessão:'));
      expect(planSessionsLabel(3), startsWith('3 sessões:'));
    },
  );

  test('storeRunPlan: Automático copies the plan to spec_steps; Manual '
      'removes it', () async {
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [databaseOverride(memoryDatabase())],
    );
    addTearDown(c.dispose);
    final ws = await c.read(workspacesRepoProvider).add(path: '/x', name: 'w');
    final spec = await c
        .read(specsRepoProvider)
        .insert(
          workspaceId: ws.id,
          code: 'SPEC-012',
          title: 'Relatório',
          path: 'specs/SPEC-012.md',
          requirements: _spec.requirements,
        );
    final repo = c.read(specStepsRepoProvider);
    RunSpecOptions options({required bool auto}) => (
      provider: 'claude',
      agent: '',
      model: 'haiku',
      effort: 'low',
      mode: ClaudePermissionMode.defaultMode,
      auto: auto,
      plan: auto
          ? const [
              StepPlanEntry(
                step: 'R1',
                title: 'a',
                kind: StepKind.mecanica,
                suggested: StepRule('haiku', 'low'),
                hash: 'h1',
                classReason: 'troca de nomes',
              ),
              StepPlanEntry(
                step: 'R2',
                title: 'b',
                kind: StepKind.altoRisco,
                suggested: StepRule('opus', 'high'),
                pick: StepRule('sonnet', 'high'),
                hash: 'h2',
              ),
            ]
          : const [],
      review: null,
    );
    await storeRunPlan(repo, spec.id, options(auto: true));
    final r1 = await repo.byStep(spec.id, 'R1');
    final r2 = await repo.byStep(spec.id, 'R2');
    expect(
      (r1!.kind, r1.planModel, r1.planEffort, r1.planHash, r1.userPicked),
      ('mecanica', 'haiku', 'low', 'h1', false),
    );
    expect((r1.planReason, r2!.planReason), ('troca de nomes', null));
    expect(
      (r2.kind, r2.planModel, r2.planEffort, r2.userPicked),
      ('altoRisco', 'sonnet', 'high', true),
    );

    await storeRunPlan(repo, spec.id, options(auto: false));
    for (final id in ['R1', 'R2']) {
      final r = await repo.byStep(spec.id, id);
      expect(
        (r!.kind, r.planModel, r.planReason, r.userPicked),
        (null, null, null, false),
      );
    }
  });

  group('RunSpecDialog', () {
    late List<Completer<Object?>> answers;
    late _FakeClassifier classifier;
    late ProviderContainer c;
    RunSpecOptions? result;
    var closed = false;

    Future<void> open(
      WidgetTester tester, {
      Map<String, String> settings = const {},
      ProviderAvailability claude = const ProviderAvailability(
        ProviderStatus.ready,
        'CLI instalado, autenticado e compatível.',
      ),
      bool knownAvailability = false,
      Future<ProviderAvailability>? checking,
      Workspace? workspace,
    }) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      answers = [];
      result = null;
      closed = false;
      classifier = _FakeClassifier(answers);
      c = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          appSettingsProvider.overrideWith(() => _Settings(settings)),
          stepClassifierProvider.overrideWith(() => classifier),
          specStepsProvider.overrideWith(
            (ref, ws) => Stream.value(const <SpecStep>[]),
          ),
          agentListProvider.overrideWith((ref, path) async => const []),
          providerAvailabilityProvider.overrideWith(
            (ref, id) => checking ?? Future.value(claude),
          ),
          if (workspace != null)
            activeWorkspaceProvider.overrideWithValue(workspace),
        ],
      );
      addTearDown(c.dispose);
      if (knownAvailability) {
        // As in the app, where the footer already checked the CLI.
        c.listen(providerAvailabilityProvider('claude'), (_, _) {});
      }
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  key: const ValueKey('open'),
                  onPressed: () async {
                    result = await showAppDialog<RunSpecOptions>(
                      context: context,
                      builder: (_) => const RunSpecDialog(spec: _spec),
                    );
                    closed = true;
                  },
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // The check of the Claude Code (R15), then the classification.
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> pump(WidgetTester tester) async {
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Finder key(String k) => find.byKey(ValueKey(k));

    Future<void> answer(WidgetTester tester, Map<String, String> kinds) async {
      answers.last.complete(_kinds(kinds));
      await pump(tester);
    }

    testWidgets('R1: opens in Manual with the fields of today', (tester) async {
      await open(tester);
      expect(key('run-spec-provider'), findsOneWidget);
      expect(key('run-spec-agent'), findsOneWidget);
      expect(key('run-spec-model'), findsOneWidget);
      expect(key('run-spec-effort'), findsOneWidget);
      expect(key('run-spec-mode'), findsOneWidget);
      expect(key('step-plan-list'), findsNothing);
      expect(key('run-spec-rules'), findsNothing);
      expect(classifier.calls, 0);

      await tester.tap(key('run-spec-submit'));
      await pump(tester);
      expect(closed, isTrue);
      expect(result!.auto, isFalse);
      expect(result!.plan, isEmpty);
      expect(result!.model, 'sonnet');
      expect(result!.effort, 'medium');
      await tester.pumpAndSettle();
    });

    testWidgets('R1, R3, R4, R5: with the preference on, opens in Automático; '
        'skeleton while classifying, then the plan', (tester) async {
      await open(
        tester,
        settings: {AppSettingKeys.orchestratorAutoByDefault: '1'},
      );
      expect(key('run-spec-provider'), findsNothing);
      expect(key('run-spec-model'), findsNothing);
      expect(key('run-spec-effort'), findsNothing);
      expect(key('run-spec-mode'), findsOneWidget);
      expect(key('run-spec-rules'), findsOneWidget);
      expect(key('step-plan-skeleton'), findsOneWidget);
      expect(find.text('Classificando as etapas com Haiku…'), findsOneWidget);
      expect(key('run-spec-use-manual'), findsOneWidget);
      expect(classifier.calls, 1);

      await answer(tester, {
        'R1': 'mecanica',
        'R2': 'altoRisco',
        'R3': 'implementacao',
        'R4': 'implementacao',
      });
      expect(key('step-plan-skeleton'), findsNothing);
      for (final id in ['R1', 'R2', 'R3', 'R4']) {
        expect(key('step-plan-$id'), findsOneWidget);
      }
      expect(find.text('Mecânica: motivo de R1'), findsOneWidget);
      expect(find.text('Alto risco: motivo de R2'), findsOneWidget);
      expect(find.text('Haiku · low'), findsOneWidget);
      expect(find.text('Opus · high'), findsOneWidget);
      expect(find.text('Sonnet · medium'), findsNWidgets(2));
      // R1 | R2 | R3+R4
      expect(find.textContaining('3 sessões:'), findsOneWidget);
      expect(find.text('você escolheu'), findsNothing);

      await tester.tap(key('run-spec-submit'));
      await pump(tester);
      expect(result!.auto, isTrue);
      expect(result!.provider, 'claude');
      expect(result!.model, 'haiku');
      expect(result!.effort, 'low');
      expect(result!.review, isNull);
      expect([for (final e in result!.plan) e.step], ['R1', 'R2', 'R3', 'R4']);
      expect(result!.plan[1].kind, StepKind.altoRisco);
      expect(result!.plan[1].rule, const StepRule('opus', 'high'));
      expect(
        result!.plan[1].hash,
        stepTextHash('Criar a tabela de relatórios'),
      );
      expect(result!.plan.any((e) => e.userPicked), isFalse);
      await tester.pumpAndSettle();
    });

    testWidgets('R4: changing a line shows "você escolheu" and a new '
        'classification keeps the choice', (tester) async {
      await open(tester);
      await tester.tap(key('run-spec-auto'));
      await pump(tester);
      expect(classifier.calls, 1);
      await answer(tester, {
        'R1': 'mecanica',
        'R2': 'altoRisco',
        'R3': 'implementacao',
        'R4': 'implementacao',
      });

      await tester.tap(key('step-plan-model-R2-Opus · high'));
      await pump(tester);
      await tester.tap(find.text('Sonnet · medium').last);
      await pump(tester);
      expect(key('step-plan-picked-R2'), findsOneWidget);
      // R1 | R2+R3+R4
      expect(find.textContaining('2 sessões:'), findsOneWidget);

      // A new classification arrives with other kinds.
      classifier.reclassify(_spec, {
        'R1': StepKind.mecanica,
        'R2': StepKind.documentacao,
        'R3': StepKind.altoRisco,
        'R4': StepKind.implementacao,
      });
      await pump(tester);
      expect(find.text('Documentação: motivo de R2'), findsOneWidget);
      expect(key('step-plan-picked-R2'), findsOneWidget);

      await tester.tap(key('run-spec-submit'));
      await pump(tester);
      final r2 = result!.plan[1];
      expect(r2.kind, StepKind.documentacao);
      expect(r2.rule, const StepRule('sonnet', 'medium'));
      expect(r2.userPicked, isTrue);
      expect(result!.plan[2].rule, const StepRule('opus', 'high'));
      await tester.pumpAndSettle();
    });

    testWidgets('R14: a failure shows "Tentar de novo" and "Executar com '
        '<modelo>" with the model of Sessões', (tester) async {
      await open(
        tester,
        settings: {
          AppSettingKeys.orchestratorAutoByDefault: '1',
          AppSettingKeys.runModel('session'): 'opus',
          AppSettingKeys.runEffort('session'): 'high',
        },
      );
      answers.last.completeError(
        const PlannerException('O planner terminou com erro (error).'),
      );
      await pump(tester);
      expect(key('run-spec-classify-failed'), findsOneWidget);
      expect(find.textContaining('Opus · high'), findsOneWidget);
      expect(key('run-spec-retry'), findsOneWidget);
      expect(find.text('Executar com Opus'), findsOneWidget);

      await tester.tap(key('run-spec-retry'));
      await pump(tester);
      expect(classifier.calls, 2);
      expect(key('step-plan-skeleton'), findsOneWidget);
      answers.last.completeError(const PlannerException('Falhou de novo.'));
      await pump(tester);

      await tester.tap(find.text('Executar com Opus'));
      await pump(tester);
      expect(result!.auto, isFalse);
      expect(result!.plan, isEmpty);
      expect(result!.provider, 'claude');
      expect(result!.model, 'opus');
      expect(result!.effort, 'high');
      await tester.pumpAndSettle();
    });

    testWidgets('R15: without the Claude Code, Automático is off with the '
        'reason and "Abrir Provedores"; Manual still works', (tester) async {
      await open(
        tester,
        settings: {AppSettingKeys.orchestratorAutoByDefault: '1'},
        knownAvailability: true,
        claude: const ProviderAvailability(
          ProviderStatus.missing,
          'CLI não encontrado.',
        ),
      );
      await pump(tester);
      expect(key('run-spec-auto-blocked'), findsOneWidget);
      expect(find.textContaining('CLI não encontrado.'), findsOneWidget);
      expect(key('run-spec-model'), findsOneWidget);
      expect(classifier.calls, 0);
      await tester.tap(key('run-spec-auto'));
      await pump(tester);
      expect(key('step-plan-skeleton'), findsNothing);
      expect(classifier.calls, 0);

      await tester.tap(key('run-spec-open-providers'));
      await pump(tester);
      expect(closed, isTrue);
      expect(result, isNull);
      expect(c.read(navigationProvider), AppSection.settings);
      expect(
        c.read(selectedSettingsSectionProvider),
        SettingsSection.providers,
      );
      await tester.pumpAndSettle();
    });

    testWidgets('R4: the review line comes last when the reviewer is on in '
        'the project, and is not a step', (tester) async {
      final tmp = Directory.systemTemp.createTempSync('promptorium-run-');
      addTearDown(() => tmp.deleteSync(recursive: true));
      File('${tmp.path}/${ProjectConfig.filePath}')
        ..createSync(recursive: true)
        ..writeAsStringSync('revisor:\n  ligado: true\n');
      await open(
        tester,
        settings: {AppSettingKeys.orchestratorAutoByDefault: '1'},
        workspace: Workspace(
          id: 1,
          path: tmp.path,
          name: 'w',
          createdAt: DateTime(2026),
        ),
      );
      // Skeleton: 4 steps + the review.
      await answer(tester, {'R1': 'mecanica'});
      expect(key('step-plan-review'), findsOneWidget);
      expect(
        find.text('Revisão: revisa o diff no fim, não é etapa da fila'),
        findsOneWidget,
      );
      final rows = tester.getTopLeft(key('step-plan-review')).dy;
      expect(rows, greaterThan(tester.getTopLeft(key('step-plan-R4')).dy));
      // R1 | R2+R3+R4 (the review does not count).
      expect(find.textContaining('2 sessões:'), findsOneWidget);

      await tester.tap(key('run-spec-submit'));
      await pump(tester);
      expect(result!.plan.map((e) => e.step), ['R1', 'R2', 'R3', 'R4']);
      expect(result!.review, const StepRule('sonnet', 'medium'));
      await tester.pumpAndSettle();
    });

    testWidgets('R4: the selector offers Haiku · low, Sonnet · medium and '
        'Opus · high, plus a rule changed in Configurações', (tester) async {
      await open(
        tester,
        settings: {
          AppSettingKeys.orchestratorAutoByDefault: '1',
          AppSettingKeys.orchestratorModel('implementacao'): 'sonnet',
          AppSettingKeys.orchestratorEffort('implementacao'): 'high',
        },
      );
      await answer(tester, {
        'R1': 'mecanica',
        'R2': 'altoRisco',
        'R3': 'implementacao',
        'R4': 'implementacao',
      });
      expect(
        stepPlanChoices(suggested: const StepRule('haiku', 'low')),
        stepPlanRungs,
      );
      expect(
        stepPlanChoices(
          suggested: const StepRule('sonnet', 'high'),
          current: const StepRule('opus', 'max'),
        ),
        [
          ...stepPlanRungs,
          const StepRule('sonnet', 'high'),
          const StepRule('opus', 'max'),
        ],
      );

      await tester.tap(key('step-plan-model-R3-Sonnet · high'));
      await pump(tester);
      final items = tester
          .widgetList<DropdownMenuItem<StepRule>>(
            find.byType(DropdownMenuItem<StepRule>),
          )
          .map((i) => i.value)
          .toSet();
      expect(items, {...stepPlanRungs, const StepRule('sonnet', 'high')});
      expect(find.text('Haiku · medium'), findsNothing);
      expect(find.text('Opus · max'), findsNothing);
      await tester.tap(find.text('Opus · high').last);
      await pump(tester);
      expect(key('step-plan-picked-R3'), findsOneWidget);

      await tester.tap(key('run-spec-submit'));
      await pump(tester);
      expect(result!.plan[2].rule, const StepRule('opus', 'high'));
      expect(result!.plan[3].rule, const StepRule('sonnet', 'high'));
      await tester.pumpAndSettle();
    });

    testWidgets('R3: Executar works while classifying: it waits for the plan '
        'and runs with it', (tester) async {
      await open(
        tester,
        settings: {AppSettingKeys.orchestratorAutoByDefault: '1'},
      );
      expect(key('step-plan-skeleton'), findsOneWidget);
      expect(
        tester.widget<AmberButton>(key('run-spec-submit')).onTap,
        isNotNull,
      );
      await tester.tap(key('run-spec-submit'));
      await pump(tester);
      expect(closed, isFalse);
      expect(tester.widget<AmberButton>(key('run-spec-submit')).busy, isTrue);
      expect(key('run-spec-use-manual'), findsOneWidget);

      await answer(tester, {'R1': 'mecanica', 'R2': 'altoRisco'});
      expect(closed, isTrue);
      expect(result!.auto, isTrue);
      expect(result!.plan.map((e) => e.step), ['R1', 'R2', 'R3', 'R4']);
      expect(result!.plan[1].rule, const StepRule('opus', 'high'));
      await tester.pumpAndSettle();
    });

    testWidgets('R14: a classification that fails while Executar waits shows '
        'the failure and does not run', (tester) async {
      await open(
        tester,
        settings: {AppSettingKeys.orchestratorAutoByDefault: '1'},
      );
      await tester.tap(key('run-spec-submit'));
      await pump(tester);
      answers.last.completeError(const PlannerException('Falhou.'));
      await pump(tester);
      expect(closed, isFalse);
      expect(key('run-spec-classify-failed'), findsOneWidget);
      expect(key('run-spec-retry'), findsOneWidget);
      expect(key('run-spec-submit'), findsNothing);
    });

    testWidgets('R15: with the preference on, it opens in Automático while '
        'the Claude Code is checked, never in Manual', (tester) async {
      final check = Completer<ProviderAvailability>();
      await open(
        tester,
        settings: {AppSettingKeys.orchestratorAutoByDefault: '1'},
        checking: check.future,
      );
      expect(key('run-spec-auto-checking'), findsOneWidget);
      expect(find.text('Verificando o Claude Code…'), findsOneWidget);
      expect(key('step-plan-skeleton'), findsOneWidget);
      expect(key('run-spec-rules'), findsOneWidget);
      expect(key('run-spec-model'), findsNothing);
      expect(key('run-spec-provider'), findsNothing);
      expect(key('run-spec-use-manual'), findsOneWidget);
      expect(tester.widget<AmberButton>(key('run-spec-submit')).onTap, isNull);
      // The classification waits for the CLI.
      expect(classifier.calls, 0);

      check.complete(
        const ProviderAvailability(ProviderStatus.ready, 'CLI ok.'),
      );
      await pump(tester);
      expect(key('run-spec-auto-checking'), findsNothing);
      expect(key('run-spec-auto-blocked'), findsNothing);
      expect(find.text('Classificando as etapas com Haiku…'), findsOneWidget);
      expect(classifier.calls, 1);
      await tester.tap(key('run-spec-manual'));
      await pump(tester);
      expect(key('run-spec-model'), findsOneWidget);
      await tester.tap(key('run-spec-submit'));
      await pump(tester);
      expect(result!.auto, isFalse);
      await tester.pumpAndSettle();
    });

    testWidgets('R15: when the check finds no Claude Code, it falls back to '
        'Manual with the reason and "Abrir Provedores"', (tester) async {
      final check = Completer<ProviderAvailability>();
      await open(
        tester,
        settings: {AppSettingKeys.orchestratorAutoByDefault: '1'},
        checking: check.future,
      );
      expect(key('run-spec-model'), findsNothing);
      check.complete(
        const ProviderAvailability(ProviderStatus.missing, 'CLI ausente.'),
      );
      await pump(tester);
      expect(key('run-spec-auto-blocked'), findsOneWidget);
      expect(find.textContaining('CLI ausente.'), findsOneWidget);
      expect(key('run-spec-open-providers'), findsOneWidget);
      expect(key('run-spec-model'), findsOneWidget);
      expect(key('step-plan-skeleton'), findsNothing);
      expect(classifier.calls, 0);
    });

    testWidgets('R15: in Manual, Automático is off while the Claude Code is '
        'checked', (tester) async {
      final check = Completer<ProviderAvailability>();
      await open(tester, checking: check.future);
      expect(key('run-spec-auto-checking'), findsOneWidget);
      expect(key('run-spec-model'), findsOneWidget);
      await tester.tap(key('run-spec-auto'));
      await pump(tester);
      expect(key('step-plan-skeleton'), findsNothing);
      expect(classifier.calls, 0);
      check.complete(
        const ProviderAvailability(ProviderStatus.ready, 'CLI ok.'),
      );
      await pump(tester);
      expect(key('run-spec-auto-checking'), findsNothing);
      await tester.tap(key('run-spec-auto'));
      await pump(tester);
      expect(key('step-plan-skeleton'), findsOneWidget);
      expect(classifier.calls, 1);
    });
  });
}
