import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/core/claude/readonly_run.dart';
import 'package:promptorium/core/process/process_runner.dart';
import 'package:promptorium/core/system/worktree_launcher.dart';
import 'package:promptorium/core/text/line_diff.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_rules.dart';
import 'package:promptorium/features/board/spec_runner.dart';
import 'package:promptorium/features/board/step_decision.dart';
import 'package:promptorium/features/board/step_decision_choices.dart';
import 'package:promptorium/features/board/step_decision_compiler.dart';
import 'package:promptorium/features/board/step_gate.dart';
import 'package:promptorium/features/board/widgets/spec_canvas.dart';
import 'package:promptorium/features/board/widgets/step_decision_dialog.dart';
import 'package:promptorium/features/board/widgets/step_decision_parts.dart';
import 'package:promptorium/features/review/review_service.dart'
    show reviewQueueProvider;
import 'package:promptorium/features/sessions/session_composer_draft.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/features/sessions/timeline_provider.dart';
import 'package:promptorium/features/sessions/widgets/composer.dart';
import 'package:promptorium/features/sessions/widgets/session_style.dart';
import 'package:promptorium/features/specs/spec_file.dart';
import 'package:promptorium/ui/shell/app_shell.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:promptorium/ui/theme/motion.dart';
import 'package:promptorium/ui/theme/tokens.dart';

import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';
import 'board_screen_test.dart' show pumpBoard;
import 'canvas_fixture.dart' hide pumpFor;

const requirement = 'O sistema deve gravar o id da imagem Docker.';
const summary = 'O agente perguntou se cria uma migração.';

const amend = StepDecisionOption(
  title: 'Criar a coluna image_id',
  kind: StepDecisionKind.amend,
  consequence: 'O R3 ganha um critério.',
  change:
      'O sistema deve gravar o id da imagem Docker na coluna nova.\n'
      '- [ ] A migração cria a coluna [R3]',
  suggested: true,
);
const answer = StepDecisionOption(
  title: 'Guardar em metadata',
  kind: StepDecisionKind.answer,
  consequence: 'Sem migração.',
);
const split = StepDecisionOption(
  title: 'Migração primeiro',
  kind: StepDecisionKind.split,
  consequence: 'A fila ganha duas subetapas.',
  split: ['Criar a migração', 'Gravar o id'],
);
const defer = StepDecisionOption(
  title: 'Esperar a SPEC-004',
  kind: StepDecisionKind.defer,
  consequence: 'O R3 vai para o fim.',
);

const first = StepDecision(
  question: 'Onde guardar o id?',
  options: [amend, answer, split, defer],
);
const second = StepDecision(
  question: 'Como mostrar o id?',
  options: [
    StepDecisionOption(title: 'Na lista', kind: StepDecisionKind.answer),
    StepDecisionOption(title: 'No detalhe', kind: StepDecisionKind.answer),
  ],
);

const one = StepDecisionResult(summary: summary, decisions: [first]);
const two = StepDecisionResult(summary: summary, decisions: [first, second]);

const waiting = StepView(
  id: 'R3',
  text: requirement,
  status: StepStatus.needsInput,
  sessionId: 's1',
);

/// Holds what the run would give, and records what the modal asks.
class FakeOptions extends StepDecisionOptions {
  FakeOptions([this.seed]);

  /// Null = still generating.
  final StepDecisionResult? seed;
  final generated = <String>[];
  final cancelled = <String>[];
  final retried = <String>[];

  @override
  Map<StepDecisionTarget, StepDecisionState> build() => {
    if (seed != null)
      for (final step in const ['R2', 'R3', 'R3.2'])
        (1, step): StepDecisionState(seed),
  };

  @override
  Future<StepDecisionResult> generate(Spec spec, StepView step) async {
    generated.add(step.id);
    return seed ?? const StepDecisionResult();
  }

  @override
  Future<StepDecisionResult> retry(Spec spec, StepView step) async {
    retried.add(step.id);
    deliver((spec.id, step.id), null);
    return const StepDecisionResult();
  }

  @override
  void cancel(int specId, String step) => cancelled.add(step);

  void deliver(StepDecisionTarget target, StepDecisionResult? result) =>
      state = {...state, target: StepDecisionState(result)};
}

class FakeManager extends SessionManager {
  FakeManager({this.alive = false});

  final bool alive;
  final resumed = <String>[];
  final sent = <String>[];
  final released = <String>[];

  /// Runs at each release, before it returns.
  void Function()? onRelease;

  @override
  SessionManagerState build() =>
      SessionManagerState(live: {if (alive) 's1': const LiveSession()});

  @override
  Future<void> resume(String id) async => resumed.add(id);

  @override
  Future<void> send(String id, String text) async => sent.add(text);

  @override
  Future<void> release(String id) async {
    released.add(id);
    onRelease?.call();
  }
}

/// Answers for the run: the text [after] gives, or the failure of [error].
class FakeCompiler extends StepDecisionCompiler {
  FakeCompiler(super.ref, this.file);

  final File? file;
  final calls = <List<StepDecisionChoice>>[];
  String Function(String before) after = amended;
  String message = 'Crie a coluna image_id.';
  Object? error;

  /// Holds the run until it completes.
  Completer<void>? hold;

  @override
  Future<StepCompilation> compile(
    Spec spec,
    StepView step,
    List<StepDecisionChoice> choices, {
    Future<void>? cancelled,
  }) async {
    calls.add(choices);
    await hold?.future;
    if (error case final e?) throw e;
    final before = file!.readAsStringSync();
    return StepCompilation(
      before: before,
      after: after(before),
      message: message,
    );
  }
}

class FakeRunner extends SpecRunner {
  FakeRunner(super.ref);

  final contexts = <String?>[];
  Object? error;

  @override
  Future<String> runNext(
    int specId, {
    ClaudePermissionMode? mode,
    String? provider,
    String? model,
    String? effort,
    String? agent,
    bool ignoreBlockers = false,
    bool reviewUnblocks = false,
    String? previousAttempt,
    String? context,
    bool duel = false,
    bool keepModel = false,
  }) async {
    if (error case final e?) throw e;
    contexts.add(context);
    return 's2';
  }
}

const specFile =
    '''---
id: SPEC-003
status: aprovada
---

# Imagem

## Requisitos

- R1 · Um
- R2 · Dois
- R3 · $requirement
- R4 · Quatro

## Critérios de aceite

- [ ] O id fica gravado [R3]
''';

String amended(String before) => before
    .replaceFirst(requirement, 'O sistema deve gravar o id na coluna nova.')
    .replaceFirst(
      '- [ ] O id fica gravado [R3]',
      '- [ ] O id fica gravado [R3]\n- [ ] A migração cria a coluna [R3]',
    );

String deferred(String before) => deferRequirement(before, 'R3');

class Harness {
  Harness(
    this.container,
    this.options,
    this.manager,
    this.spec,
    this.compiler,
    this.runner,
    this.file,
  );

  final ProviderContainer container;
  final FakeOptions options;
  final FakeManager manager;
  final Spec spec;
  final FakeCompiler? compiler;
  final FakeRunner? runner;

  /// The spec on the disk, with [pumpPage]'s `onDisk`.
  final File? file;

  Future<Map<String, SpecStep>> rows() async => {
    for (final r in await container.read(specStepsRepoProvider).bySpec(spec.id))
      r.step: r,
  };

  List<StepDecisionChoice> choices([String session = 's1']) =>
      container.read(stepDecisionChoicesProvider)[(session, 'R3')] ?? const [];
}

Finder byKey(String key) => find.byKey(ValueKey(key));

Finder get dialog => byKey('step-decision-dialog');

Finder row(int n) => byKey('step-decision-option-$n');

Future<void> settle(WidgetTester tester, [int times = 10]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

/// A page with one button that opens the modal of [step], at a known place.
Future<Harness> pumpPage(
  WidgetTester tester, {
  StepDecisionResult? result = one,
  StepView step = waiting,
  bool reduceMotion = false,
  bool alive = false,
  Size size = const Size(1440, 900),
  bool onDisk = false,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = memoryDatabase();
  final root = onDisk
      ? Directory.systemTemp.createTempSync('promptorium-compile-')
      : null;
  addTearDown(() => root?.deleteSync(recursive: true));
  final file = root == null
      ? null
      : (File('${root.path}/specs/SPEC-003.md')
          ..createSync(recursive: true)
          ..writeAsStringSync(specFile));
  final ws = await db
      .into(db.workspaces)
      .insertReturning(
        WorkspacesCompanion.insert(
          path: root?.path ?? '/work/repo',
          name: 'repo',
        ),
      );
  final spec = await db
      .into(db.specs)
      .insertReturning(
        SpecsCompanion.insert(
          workspaceId: ws.id,
          code: 'SPEC-003',
          title: 'Imagem',
          path: 'specs/SPEC-003.md',
          status: const Value(SpecStatus.approved),
          stage: const Value(SpecStage.running),
          requirements: const Value([
            (id: 'R1', text: 'Um'),
            (id: 'R2', text: 'Dois'),
            (id: 'R3', text: requirement),
            (id: 'R4', text: 'Quatro'),
          ]),
        ),
      );
  await db
      .into(db.specSteps)
      .insert(
        SpecStepsCompanion.insert(
          specId: spec.id,
          step: 'R3',
          status: const Value(StepStatus.needsInput),
        ),
      );
  final options = FakeOptions(result);
  final manager = FakeManager(alive: alive);
  FakeCompiler? compiler;
  FakeRunner? runner;
  final c = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      databaseOverride(db),
      stepDecisionOptionsProvider.overrideWith(() => options),
      sessionManagerProvider.overrideWith(() => manager),
      if (onDisk) ...[
        stepDecisionCompilerProvider.overrideWith(
          (ref) => compiler = FakeCompiler(ref, file),
        ),
        specRunnerProvider.overrideWith((ref) => runner = FakeRunner(ref)),
      ],
      ...overrides,
    ],
  );
  if (onDisk) {
    c
      ..read(stepDecisionCompilerProvider)
      ..read(specRunnerProvider);
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 100,
                top: 400,
                child: StepFocusAnchor(
                  builder: (context, focus) => TextButton(
                    key: const ValueKey('open'),
                    focusNode: focus,
                    onPressed: () => showStepDecision(
                      context,
                      spec,
                      step,
                      origin: stepOrigin(context),
                      returnFocus: focus,
                    ),
                    child: const Text('abrir'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.pump(Duration.zero);
  });
  await settle(tester, 3);
  return Harness(c, options, manager, spec, compiler, runner, file);
}

Future<Harness> openModal(
  WidgetTester tester, {
  StepDecisionResult? result = one,
  StepView step = waiting,
  bool alive = false,
  bool reduceMotion = false,
  bool onDisk = false,
  List<Override> overrides = const [],
}) async {
  final h = await pumpPage(
    tester,
    result: result,
    step: step,
    alive: alive,
    reduceMotion: reduceMotion,
    onDisk: onDisk,
    overrides: overrides,
  );
  await tester.tap(byKey('open'));
  await settle(tester);
  return h;
}

/// A few turns of the real clock: the file operations of the app run out of
/// the fake clock of the test.
Future<void> drain(WidgetTester tester, [int times = 10]) async {
  for (var i = 0; i < times; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// [drain] until [done]: how long the disk takes depends on the machine.
Future<void> drainUntil(WidgetTester tester, bool Function() done) async {
  // Bounded by real time, not by turns: with the full suite running files in
  // parallel each turn takes longer.
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (!done() && DateTime.now().isBefore(deadline)) {
    await drain(tester, 1);
  }
  expect(done(), isTrue, reason: 'condição não atingida');
  await drain(tester, 2);
}

/// Waits for the buttons of the phase to come back, or for the modal to go.
Future<void> finished(WidgetTester tester) async {
  await tester.pump();
  await drainUntil(
    tester,
    () =>
        dialog.evaluate().isEmpty ||
        smallButton(tester, 'step-decision-submit').label != 'Retomando…',
  );
}

/// Presses "Desfazer" and waits for the notice that says how it went.
Future<void> undoAndWait(WidgetTester tester, String notice) async {
  await tester.tap(byKey('step-decision-undo'));
  await tester.pump();
  await drainUntil(tester, () => find.text(notice).evaluate().isNotEmpty);
}

const undone = 'Decisão desfeita: a spec e a fila voltaram ao que eram.';

/// The Compilar phase with option [row] of the single decision chosen, the
/// file of the spec on the disk and the compiler done.
Future<Harness> compileOption(
  WidgetTester tester,
  int row, {
  bool alive = true,
  StepDecisionResult? result = one,
  StepView step = waiting,
  void Function(Harness h)? before,
  List<Override> overrides = const [],
}) async {
  final h = await openModal(
    tester,
    alive: alive,
    result: result,
    step: step,
    onDisk: true,
    overrides: overrides,
  );
  await drain(tester);
  before?.call(h);
  await press(
    tester,
    const [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
    ][row - 1],
  );
  await ctrl(tester, LogicalKeyboardKey.enter);
  await drain(tester);
  return h;
}

SmallButton smallButton(WidgetTester tester, String key) =>
    tester.widget<SmallButton>(byKey(key));

Future<void> submit(WidgetTester tester) async {
  await tester.tap(byKey('step-decision-submit'));
  await finished(tester);
}

FocusNode openerFocus(WidgetTester tester) =>
    tester.widget<TextButton>(byKey('open')).focusNode!;

bool focusInsideDialog() =>
    FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<StepDecisionDialog>() !=
    null;

double opacityOf(WidgetTester tester, Finder child) => tester
    .widget<FadeTransition>(
      find.ancestor(of: child, matching: find.byType(FadeTransition)).first,
    )
    .opacity
    .value;

double riseOf(WidgetTester tester, Finder child) => tester
    .widget<Transform>(
      find.ancestor(of: child, matching: find.byType(Transform)).first,
    )
    .transform
    .getTranslation()
    .y;

Transform routeScale(WidgetTester tester) => tester.widget<Transform>(
  find.ancestor(of: dialog, matching: find.byType(Transform)).first,
);

String text(WidgetTester tester, String key) =>
    tester.widget<Text>(byKey(key)).data!;

GateReport gateFailure() => GateReport(
  at: DateTime(2026, 11, 4),
  attempt: 2,
  checks: [
    const GateCheck(name: 'commit', ok: true),
    GateCheck(
      name: 'testes',
      ok: false,
      command: 'flutter test test/data/machines_repo_test.dart',
      output: [for (var i = 1; i <= 9; i++) 'linha $i'].join('\n'),
    ),
  ],
);

void main() {
  group('R1 · entry points', () {
    testWidgets('the balloon opens the modal, another dot the step followed '
        'live; closing gives the focus back to the balloon', (tester) async {
      final options = FakeOptions(one);
      await pumpCanvas(
        tester,
        [
          const CanvasSpec(
            'SPEC-001',
            steps: [StepStatus.done, StepStatus.needsInput, StepStatus.pending],
          ),
        ],
        overrides: (_) => [
          stepDecisionOptionsProvider.overrideWith(() => options),
        ],
      );
      final balloon = byKey('canvas-step-SPEC-001-R2');
      await tester.tap(balloon);
      await settle(tester);
      expect(dialog, findsOneWidget);
      expect(byKey('step-live-dialog'), findsNothing);
      expect(options.generated, ['R2']);

      await press(tester, LogicalKeyboardKey.escape);
      await settle(tester);
      expect(dialog, findsNothing);
      expect(Focus.of(tester.element(balloon)).hasFocus, isTrue);

      await tester.tap(byKey('canvas-step-SPEC-001-R3'));
      await settle(tester);
      expect(byKey('step-live-dialog'), findsOneWidget);
      expect(dialog, findsNothing);
      await tester.tap(byKey('step-live-close'));
      await settle(tester);
    });

    testWidgets('a duel ready keeps its dialog', (tester) async {
      final (c, _) = await pumpCanvas(tester, [
        const CanvasSpec('SPEC-001', steps: [StepStatus.needsInput]),
      ]);
      final spec = await c.read(specsRepoProvider).getByCode(1, 'SPEC-001');
      await c
          .read(specDuelsRepoProvider)
          .insert(
            SpecDuelsCompanion.insert(
              specId: spec!.id,
              steps: 'R1',
              baseSha: 'abc',
              worktreeA: '/a',
              worktreeB: '/b',
              branchA: 'a',
              branchB: 'b',
              state: const Value('pronto'),
            ),
          );
      await settle(tester);
      await tester.tap(byKey('canvas-step-SPEC-001-R1'));
      await settle(tester);
      expect(dialog, findsNothing);
      expect(byKey('duel-dialog'), findsOneWidget);
    });

    testWidgets('the row of the steps panel opens it and keeps the trace '
        'selected; a row of another status only selects', (tester) async {
      final options = FakeOptions(one);
      await pumpBoard(
        tester,
        overrides: [stepDecisionOptionsProvider.overrideWith(() => options)],
      );
      await tester.tap(byKey('board-open-SPEC-002'));
      await settle(tester);
      await tester.tap(byKey('step-R1'));
      await settle(tester);
      expect(dialog, findsNothing);

      await tester.tap(byKey('step-R2'));
      await settle(tester);
      expect(dialog, findsOneWidget);
      await press(tester, LogicalKeyboardKey.escape);
      await settle(tester);
      expect(dialog, findsNothing);
    });

    testWidgets('the item of the inbox opens it, with no session too', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = memoryDatabase();
      final ws = await db
          .into(db.workspaces)
          .insertReturning(
            WorkspacesCompanion.insert(path: '/work/repo', name: 'repo'),
          );
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: AppSettingKeys.activeWorkspace,
              value: '${ws.id}',
            ),
          );
      final spec = await db
          .into(db.specs)
          .insertReturning(
            SpecsCompanion.insert(
              workspaceId: ws.id,
              code: 'SPEC-003',
              title: 'Imagem',
              path: 'specs/SPEC-003.md',
              status: const Value(SpecStatus.approved),
              stage: const Value(SpecStage.running),
              requirements: const Value([(id: 'R3', text: requirement)]),
            ),
          );
      await db
          .into(db.specSteps)
          .insert(
            SpecStepsCompanion.insert(
              specId: spec.id,
              step: 'R3',
              status: const Value(StepStatus.needsInput),
            ),
          );
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          processRunnerProvider.overrideWithValue(
            (exe, args) async => ProcessResult(0, 1, '', 'sem git aqui'),
          ),
          ...sessionOverrides(db: db, cli: FakeCli(), notifier: FakeNotifier()),
          reviewQueueProvider.overrideWith((ref, id) async => const []),
          stepDecisionOptionsProvider.overrideWith(() => FakeOptions(one)),
        ],
      );
      await c.read(appSettingsProvider.notifier).load();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(theme: AppTheme.dark(), home: const AppShell()),
        ),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        await tester.pump(Duration.zero);
      });
      await settle(tester);
      await tester.tap(byKey('home-action-needsAnswer-SPEC-003 · R3'));
      await settle(tester);
      expect(dialog, findsOneWidget);
      expect(tester.takeException(), isNull);
      await press(tester, LogicalKeyboardKey.escape);
      await settle(tester);
    });
  });

  group('R2 · opening', () {
    setUp(() => AppMotion.enabled = true);
    tearDown(() => AppMotion.enabled = false);

    /// Opens the modal and stops on the frame where the clocks start.
    Future<void> start(WidgetTester tester) async {
      await tester.tap(byKey('open'));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('220 ms in, 150 ms out, from 0.92 at the balloon, over a '
        'scrim of 0.6 in 160 ms', (tester) async {
      await pumpPage(tester);
      final button = tester.getRect(byKey('open'));
      await start(tester);

      final route = ModalRoute.of(tester.element(dialog))! as TransitionRoute;
      expect(route.transitionDuration, const Duration(milliseconds: 220));
      expect(route.reverseTransitionDuration, AppMotion.emphasisExit);
      final transform = routeScale(tester);
      expect(transform.transform.storage[0], closeTo(.92, .001));
      expect(opacityOf(tester, dialog), closeTo(0, .001));
      final alignment = transform.alignment! as Alignment;
      expect(alignment.x, closeTo(button.center.dx / 1440 * 2 - 1, .001));
      expect(alignment.y, closeTo(button.center.dy / 900 * 2 - 1, .001));

      Color scrim() =>
          tester
              .widget<AnimatedModalBarrier>(
                find.byType(AnimatedModalBarrier).last,
              )
              .color
              .value ??
          const Color(0x00000000);
      await tester.pump(const Duration(milliseconds: 80));
      expect(scrim().a, inExclusiveRange(0, .6));
      await tester.pump(const Duration(milliseconds: 81));
      expect(scrim().a, closeTo(.6, .01));
      expect(scrim(), AppColors.scrim);
      expect(
        routeScale(tester).transform.storage[0],
        lessThan(1),
        reason: 'the modal is still growing',
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(routeScale(tester).transform.storage[0], 1);

      await tester.pump(const Duration(milliseconds: 500));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      expect(dialog, findsOneWidget);
      expect(
        routeScale(tester).transform.storage[0],
        lessThan(.95),
        reason: 'it goes back the way it came',
      );
      await tester.pump(const Duration(milliseconds: 11));
      await tester.pump();
      expect(dialog, findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('options come in every 40 ms from 120 ms, rising 6 px, and '
        'the preview at 260 ms', (tester) async {
      await pumpPage(tester);
      await start(tester);
      final preview = byKey('step-decision-preview');
      for (final (i, finder) in [
        (0, row(1)),
        (1, row(2)),
        (2, row(3)),
        (3, row(4)),
      ]) {
        final startMs = 120 + 40 * i;
        final done = i == 0 ? 0 : 120 + 40 * (i - 1) + 5;
        await tester.pump(Duration(milliseconds: startMs - done - 1));
        expect(opacityOf(tester, finder), 0, reason: 'option ${i + 1}');
        expect(riseOf(tester, finder), 6);
        await tester.pump(const Duration(milliseconds: 6));
        expect(opacityOf(tester, finder), greaterThan(0));
        expect(riseOf(tester, finder), inExclusiveRange(0, 6));
      }
      // 245 ms so far: the first line ended at 280 and the preview is due.
      await tester.pump(const Duration(milliseconds: 14));
      expect(opacityOf(tester, preview), 0);
      await tester.pump(const Duration(milliseconds: 6));
      expect(opacityOf(tester, preview), greaterThan(0));
      await tester.pump(const Duration(milliseconds: 20));
      expect(riseOf(tester, row(1)), 0);
      expect(opacityOf(tester, row(1)), 1);
      await tester.pump(const Duration(milliseconds: 200));
      expect(opacityOf(tester, preview), 1);
      expect(opacityOf(tester, byKey('step-decision-other')), 1);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('the bubble pulses once when the modal is in place', (
      tester,
    ) async {
      await pumpPage(tester);
      await start(tester);
      Animation<double> pulse() =>
          tester.widget<CanvasStepDot>(byKey('step-decision-bubble')).pulse!;
      await tester.pump(const Duration(milliseconds: 200));
      expect(pulse().value, 0);
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pump(const Duration(milliseconds: 900));
      expect(pulse().value, inExclusiveRange(.4, .6));
      expect(pulse().status, AnimationStatus.forward);
      await tester.pump(const Duration(milliseconds: 1000));
      expect(pulse().status, AnimationStatus.completed);
      await tester.pump(const Duration(seconds: 2));
      expect(pulse().status, AnimationStatus.completed);
    });

    testWidgets('a key during the opening already counts', (tester) async {
      final h = await pumpPage(tester);
      await start(tester);
      await tester.pump(const Duration(milliseconds: 40));
      await press(tester, LogicalKeyboardKey.digit2);
      expect(h.choices().single.title, answer.title);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('options that arrive later come in sequence too', (
      tester,
    ) async {
      final h = await pumpPage(tester, result: null);
      await start(tester);
      await tester.pump(const Duration(seconds: 1));
      h.options.deliver((h.spec.id, 'R3'), one);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(opacityOf(tester, row(2)), 0);
      await tester.pump(const Duration(milliseconds: 60));
      expect(opacityOf(tester, row(2)), greaterThan(0));
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('R13 · reduced motion', () {
    setUp(() => AppMotion.enabled = true);
    tearDown(() => AppMotion.enabled = false);

    testWidgets('durations are zero, with no scale, no sequence, no pulse and '
        'a preview that swaps without a transition', (tester) async {
      await pumpPage(tester, reduceMotion: true);
      await tester.tap(byKey('open'));
      await tester.pump();
      final route = ModalRoute.of(tester.element(dialog))! as TransitionRoute;
      expect(route.transitionDuration, Duration.zero);
      expect(route.reverseTransitionDuration, Duration.zero);
      expect(routeScale(tester).transform.storage[0], 1);
      expect(opacityOf(tester, row(1)), 1);
      expect(opacityOf(tester, row(4)), 1);
      expect(riseOf(tester, row(4)), 0);
      expect(opacityOf(tester, byKey('step-decision-preview')), 1);
      expect(
        tester.widget<CanvasStepDot>(byKey('step-decision-bubble')).pulse,
        isNull,
      );
      expect(
        tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration,
        Duration.zero,
      );
      await tester.pump();
      await press(tester, LogicalKeyboardKey.escape);
      await tester.pump();
      expect(dialog, findsNothing);
    });

    testWidgets('the skeleton stands still', (tester) async {
      await pumpPage(tester, result: null, reduceMotion: true);
      await tester.tap(byKey('open'));
      await tester.pump();
      final skeleton = find.descendant(
        of: byKey('step-decision-skeleton-rows'),
        matching: find.byType(FadeTransition),
      );
      double opacity() =>
          tester.widget<FadeTransition>(skeleton.first).opacity.value;
      expect(opacity(), 1);
      await tester.pump(const Duration(milliseconds: 350));
      expect(opacity(), 1);
      await press(tester, LogicalKeyboardKey.escape);
    });

    testWidgets('with motion, the skeleton is the one that keeps moving', (
      tester,
    ) async {
      await pumpPage(tester, result: null);
      await tester.tap(byKey('open'));
      await tester.pump();
      await tester.pump();
      final skeleton = find.descendant(
        of: byKey('step-decision-skeleton-rows'),
        matching: find.byType(FadeTransition),
      );
      double opacity() =>
          tester.widget<FadeTransition>(skeleton.first).opacity.value;
      await tester.pump(const Duration(milliseconds: 350));
      final before = opacity();
      await tester.pump(const Duration(milliseconds: 200));
      expect(opacity(), isNot(before));
      await press(tester, LogicalKeyboardKey.escape);
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('R3 · header', () {
    testWidgets('shows the bubble, the step, the requirement, the summary and '
        'Fechar', (tester) async {
      await openModal(tester);
      expect(byKey('step-decision-bubble'), findsOneWidget);
      expect(find.text('SPEC-003'), findsOneWidget);
      expect(find.text('Etapa 3 · aguardando você'), findsOneWidget);
      final title = tester.widget<Text>(byKey('step-decision-requirement'));
      expect(title.data, 'R3 · $requirement');
      expect(title.maxLines, 2);
      expect(find.text('O que aconteceu'), findsOneWidget);
      final body = tester.widget<Text>(byKey('step-decision-summary'));
      expect(body.data, summary);
      expect(body.maxLines, 3);
      expect(find.byTooltip('Fechar (Esc)'), findsOneWidget);
      await tester.tap(byKey('step-decision-close'));
      await settle(tester);
      expect(dialog, findsNothing);
    });

    testWidgets('a sub-step keeps its number', (tester) async {
      await openModal(
        tester,
        step: const StepView(
          id: 'R3.2',
          text: 'Gravar',
          status: StepStatus.needsInput,
          sessionId: 's1',
        ),
        result: null,
      );
      expect(find.text('Etapa 3.2 · aguardando você'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.escape);
      await settle(tester);
    });
  });

  group('R5 · options', () {
    testWidgets('numbered rows with title, kind and consequence; the suggested '
        'one first; "Outra resposta" in 5', (tester) async {
      await openModal(tester);
      for (final (i, o) in first.options.indexed) {
        final line = row(i + 1);
        expect(
          find.descendant(of: line, matching: find.text('${i + 1}')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: line, matching: find.text(o.title)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: line,
            matching: find.textContaining(o.kind.label, findRichText: true),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: line,
            matching: find.textContaining(o.consequence, findRichText: true),
          ),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(of: row(1), matching: find.text('Sugerida')),
        findsOneWidget,
      );
      expect(find.text('Sugerida'), findsOneWidget);
      final other = byKey('step-decision-other');
      expect(
        find.descendant(of: other, matching: find.text('5')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: other, matching: find.text('Outra resposta')),
        findsOneWidget,
      );
    });

    testWidgets('the chosen row gets the icon and "Escolhida"', (tester) async {
      await openModal(tester);
      expect(find.text('Escolhida'), findsNothing);
      await tester.tap(row(2));
      await settle(tester);
      expect(
        find.descendant(of: row(2), matching: find.text('Escolhida')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row(2), matching: find.byIcon(Icons.check_circle)),
        findsOneWidget,
      );
      await press(tester, LogicalKeyboardKey.digit3);
      await settle(tester);
      expect(
        find.descendant(of: row(2), matching: find.text('Escolhida')),
        findsNothing,
      );
      expect(
        find.descendant(of: row(3), matching: find.text('Escolhida')),
        findsOneWidget,
      );
    });
  });

  group('R6 · keyboard', () {
    testWidgets('1–4 choose, a number with no option or with Ctrl does not', (
      tester,
    ) async {
      final h = await openModal(
        tester,
        result: const StepDecisionResult(
          decisions: [
            StepDecision(question: 'Q', options: [answer, defer]),
          ],
        ),
      );
      await press(tester, LogicalKeyboardKey.digit3);
      expect(h.choices(), isEmpty);
      await ctrl(tester, LogicalKeyboardKey.digit1);
      expect(h.choices(), isEmpty);
      await press(tester, LogicalKeyboardKey.numpad2);
      expect(h.choices().single.title, defer.title);
      await press(tester, LogicalKeyboardKey.digit1);
      expect(h.choices().single.title, answer.title);
    });

    testWidgets('↑ and ↓ move the focus and the preview; Enter chooses', (
      tester,
    ) async {
      final h = await openModal(tester);
      expect(
        tester.widget<StepDecisionOptionRow>(row(1)).focusNode.hasFocus,
        isTrue,
      );
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await settle(tester, 2);
      expect(
        tester.widget<StepDecisionOptionRow>(row(3)).focusNode.hasFocus,
        isTrue,
      );
      expect(
        text(tester, 'step-decision-preview-caption'),
        'opção 3 · dividir a etapa',
      );
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.enter);
      expect(h.choices().single.title, answer.title);
    });

    testWidgets('5 and Enter on its row open "Outra resposta"; what is written '
        'is the answer; Enter confirms it', (tester) async {
      final h = await openModal(tester, result: two);
      await press(tester, LogicalKeyboardKey.digit5);
      await settle(tester, 2);
      final field = byKey('step-decision-other-input');
      expect(field, findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.context?.widget, isNotNull);
      await tester.enterText(field, 'Use o campo novo');
      await tester.pump();
      expect(h.choices().single.isOther, isTrue);
      expect(h.choices().single.title, 'Use o campo novo');
      expect(h.choices().single.kind, StepDecisionKind.answer);
      await press(tester, LogicalKeyboardKey.enter);
      await tester.pump(stepDecisionAdvanceDelay);
      await tester.pump();
      expect(text(tester, 'step-decision-progress'), 'Decisão 2 de 2');
    });

    testWidgets('inside the text field the numbers, Backspace and the arrows '
        'stay with the field; Ctrl+O and Ctrl+Enter do not', (tester) async {
      final h = await openModal(tester, result: two);
      await press(tester, LogicalKeyboardKey.digit1);
      await tester.pump(stepDecisionAdvanceDelay);
      await settle(tester, 2);
      expect(text(tester, 'step-decision-progress'), 'Decisão 2 de 2');
      await press(tester, LogicalKeyboardKey.digit5);
      await settle(tester, 2);
      await tester.enterText(byKey('step-decision-other-input'), 'texto');
      await tester.pump();
      final before = h.choices().map((c) => c.title).toList();

      await press(tester, LogicalKeyboardKey.digit1);
      await press(tester, LogicalKeyboardKey.digit2);
      expect(h.choices().map((c) => c.title), before);
      await press(tester, LogicalKeyboardKey.backspace);
      await settle(tester, 2);
      expect(text(tester, 'step-decision-progress'), 'Decisão 2 de 2');

      await ctrl(tester, LogicalKeyboardKey.enter);
      await settle(tester, 2);
      expect(byKey('step-decision-compile'), findsOneWidget);
    });

    testWidgets('Ctrl+O works inside the text field', (tester) async {
      final h = await openModal(tester);
      await press(tester, LogicalKeyboardKey.digit5);
      await settle(tester, 2);
      await tester.enterText(byKey('step-decision-other-input'), 'texto');
      await tester.pump();
      await ctrl(tester, LogicalKeyboardKey.keyO);
      await settle(tester);
      expect(dialog, findsNothing);
      expect(h.container.read(selectedSessionProvider), 's1');
    });

    testWidgets('Backspace goes back to the previous decision', (tester) async {
      await openModal(tester, result: two);
      await press(tester, LogicalKeyboardKey.backspace);
      expect(text(tester, 'step-decision-progress'), 'Decisão 1 de 2');
      await press(tester, LogicalKeyboardKey.digit1);
      await tester.pump(stepDecisionAdvanceDelay);
      await tester.pump();
      expect(text(tester, 'step-decision-progress'), 'Decisão 2 de 2');
      await press(tester, LogicalKeyboardKey.backspace);
      await settle(tester, 2);
      expect(text(tester, 'step-decision-progress'), 'Decisão 1 de 2');
      expect(
        find.descendant(of: row(1), matching: find.text('Escolhida')),
        findsOneWidget,
      );
    });

    testWidgets('Compilar waits for every decision; the button and Ctrl+Enter '
        'open the phase, and Backspace leaves it', (tester) async {
      await openModal(tester, result: two);
      final button = byKey('step-decision-compile-button');
      expect(tester.widget<SmallButton>(button).onTap, isNull);
      expect(text(tester, 'step-decision-missing'), 'Faltam 2 decisões');
      await ctrl(tester, LogicalKeyboardKey.enter);
      await settle(tester, 2);
      expect(byKey('step-decision-compile'), findsNothing);

      await press(tester, LogicalKeyboardKey.digit1);
      await settle(tester, 2);
      expect(text(tester, 'step-decision-missing'), 'Falta 1 decisão');
      await tester.pump(stepDecisionAdvanceDelay);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.digit2);
      await settle(tester, 2);
      expect(byKey('step-decision-missing'), findsNothing);
      expect(tester.widget<SmallButton>(button).onTap, isNotNull);

      await ctrl(tester, LogicalKeyboardKey.enter);
      await settle(tester, 2);
      expect(byKey('step-decision-compile'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.backspace);
      await settle(tester, 2);
      expect(byKey('step-decision-compile'), findsNothing);
      expect(row(1), findsOneWidget);

      await tester.tap(button);
      await settle(tester, 2);
      expect(byKey('step-decision-compile'), findsOneWidget);
      await tester.tap(byKey('step-decision-compile-back'));
      await settle(tester, 2);
      expect(row(1), findsOneWidget);
    });

    testWidgets('the phase gets the choices and the hooks of T4', (
      tester,
    ) async {
      StepDecisionCompileRequest? request;
      var submitted = 0;
      final h = await pumpPage(tester, result: two);
      final navigator = Navigator.of(tester.element(byKey('open')));
      final route = MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: StepDecisionDialog(
            spec: h.spec,
            step: waiting,
            compileBuilder: (context, r) {
              request = r;
              return const SizedBox(key: ValueKey('t4'));
            },
          ),
        ),
      );
      navigator.push(route).ignore();
      await settle(tester);
      await press(tester, LogicalKeyboardKey.digit1);
      await tester.pump(stepDecisionAdvanceDelay);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.digit2);
      await ctrl(tester, LogicalKeyboardKey.enter);
      await settle(tester, 2);
      expect(byKey('t4'), findsOneWidget);
      expect(request!.choices.map((c) => c.title), [amend.title, 'No detalhe']);
      expect(request!.decisions, hasLength(2));
      expect(request!.summary, summary);

      request!.onSubmit.addListener(() => submitted++);
      await ctrl(tester, LogicalKeyboardKey.enter);
      expect(submitted, 1);

      request!.onChange(0);
      await settle(tester, 2);
      expect(text(tester, 'step-decision-progress'), 'Decisão 1 de 2');
      expect(byKey('t4'), findsNothing);
    });

    testWidgets('a click outside the text field does not kill the keys', (
      tester,
    ) async {
      final h = await openModal(tester);
      await press(tester, LogicalKeyboardKey.digit5);
      await settle(tester, 2);
      await tester.tap(byKey('step-decision-requirement'));
      await settle(tester, 2);
      FocusManager.instance.primaryFocus?.unfocus();
      await settle(tester, 2);
      await press(tester, LogicalKeyboardKey.digit1);
      expect(h.choices().single.title, amend.title);
    });

    testWidgets('"Tentar de novo" does not kill the keys', (tester) async {
      await openModal(
        tester,
        result: const StepDecisionResult(error: 'falhou'),
      );
      await press(tester, LogicalKeyboardKey.arrowDown);
      await settle(tester, 2);
      await tester.tap(byKey('step-decision-retry'));
      await settle(tester, 3);
      await press(tester, LogicalKeyboardKey.escape);
      await settle(tester);
      expect(dialog, findsNothing);
    });

    testWidgets('Esc closes, and the bar shows the keys', (tester) async {
      await openModal(tester);
      final legend = byKey('step-decision-keys');
      for (final key in ['1–4', '5', '↑↓', 'Enter', '⌫', 'Esc']) {
        expect(
          find.descendant(of: legend, matching: find.text(key)),
          findsOneWidget,
        );
      }
      expect(find.text('Ctrl+O'), findsOneWidget);
      expect(find.text('Ctrl+Enter'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.escape);
      await settle(tester);
      expect(dialog, findsNothing);
    });
  });

  group('R7 · preview', () {
    Finder inPreview(Finder f) =>
        find.descendant(of: byKey('step-decision-preview'), matching: f);

    testWidgets('Ajustar marks the swaps, with the new criterion', (
      tester,
    ) async {
      await openModal(tester);
      expect(
        text(tester, 'step-decision-preview-caption'),
        'opção 1 · ajustar o requisito',
      );
      final amended = tester.widget<Text>(byKey('step-preview-amended'));
      final spans = (amended.textSpan! as TextSpan).children!.cast<TextSpan>();
      final added = spans.where(
        (s) => s.style?.decoration == TextDecoration.underline,
      );
      final removed = spans.where(
        (s) => s.style?.decoration == TextDecoration.lineThrough,
      );
      expect(added.map((s) => s.text!), containsAll(['coluna', 'nova']));
      expect(removed, isEmpty);
      expect(inPreview(find.text('Critério novo')), findsOneWidget);
      expect(
        inPreview(find.text('- [ ] A migração cria a coluna [R3]')),
        findsOneWidget,
      );
      expect(inPreview(find.text('Fila de etapas: não muda')), findsOneWidget);
      expect(
        text(tester, 'step-preview-message'),
        'O agente retoma o R3 com a mensagem: “${amend.title}”',
      );
    });

    test('the word diff marks words and punctuation apart', () {
      String marked(DiffOp op) => [
        for (final t in wordDiff('grava o id.', 'salva o id, na coluna.'))
          if (t.op == op) t.text,
      ].join();
      expect(marked(DiffOp.del), 'grava');
      expect(marked(DiffOp.add), 'salva, na coluna');
      expect(
        wordDiff('a  b', 'a\nb').every((t) => t.op == DiffOp.same),
        isTrue,
      );
    });

    testWidgets('Dividir keeps the requirement and shows the sub-steps, the '
        'note and one more dot', (tester) async {
      await openModal(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await settle(tester, 2);
      expect(inPreview(find.text('Requisito: não muda')), findsOneWidget);
      expect(inPreview(find.text('R3 · $requirement')), findsOneWidget);
      expect(byKey('step-preview-sub-R3.1'), findsOneWidget);
      expect(byKey('step-preview-sub-R3.2'), findsOneWidget);
      expect(inPreview(find.text('Criar a migração')), findsOneWidget);
      expect(
        text(tester, 'step-preview-split-note'),
        'Critérios do R3 verificados ao fim do R3.2. O agente retoma pelo '
        'R3.1.',
      );
      final queue = byKey('step-preview-queue');
      expect(
        find.descendant(of: queue, matching: find.byType(CanvasStepDot)),
        findsNWidgets(5),
      );
      expect(
        find.descendant(of: queue, matching: find.text('R3')),
        findsNothing,
      );
    });

    testWidgets('Adiar sends the step to the end, pending', (tester) async {
      await openModal(tester);
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.arrowUp);
      await settle(tester, 2);
      expect(
        text(tester, 'step-decision-preview-caption'),
        'opção 4 · adiar a etapa',
      );
      final ids = tester
          .widgetList<Text>(
            find.descendant(
              of: byKey('step-preview-queue'),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data);
      expect(ids, ['R1', 'R2', 'R4', 'R3']);
      final dots = tester.widgetList<CanvasStepDot>(
        find.descendant(
          of: byKey('step-preview-queue'),
          matching: find.byType(CanvasStepDot),
        ),
      );
      expect(dots.last.status, StepStatus.pending);
      expect(dots.every((d) => !d.animate), isTrue);
      expect(byKey('step-preview-defer-note'), findsOneWidget);
    });

    testWidgets('Responder shows the message and "o requisito não muda"; '
        '"Outra resposta" shows what is written', (tester) async {
      await openModal(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await settle(tester, 2);
      expect(text(tester, 'step-preview-answer'), '“${answer.title}”');
      expect(byKey('step-preview-unchanged'), findsOneWidget);

      await press(tester, LogicalKeyboardKey.digit5);
      await settle(tester, 2);
      expect(text(tester, 'step-decision-preview-caption'), 'outra resposta');
      await tester.enterText(byKey('step-decision-other-input'), 'Faça assim');
      await tester.pump();
      expect(text(tester, 'step-preview-answer'), '“Faça assim”');
      expect(byKey('step-preview-unchanged'), findsOneWidget);
    });

    testWidgets('a choice stays in the preview when the focus leaves the list '
        'and the cross-fade takes 120 ms', (tester) async {
      AppMotion.enabled = true;
      addTearDown(() => AppMotion.enabled = false);
      await openModal(tester);
      expect(
        tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher)).duration,
        AppMotion.quick,
      );
      await press(tester, LogicalKeyboardKey.digit2);
      await tester.pump(const Duration(seconds: 2));
      expect(
        text(tester, 'step-decision-preview-caption'),
        'opção 2 · responder',
      );
      await press(tester, LogicalKeyboardKey.tab);
      await press(tester, LogicalKeyboardKey.tab);
      await press(tester, LogicalKeyboardKey.tab);
      await press(tester, LogicalKeyboardKey.tab);
      await tester.pump(const Duration(seconds: 2));
      expect(
        text(tester, 'step-decision-preview-caption'),
        'opção 2 · responder',
      );
      await press(tester, LogicalKeyboardKey.escape);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a narrow window drops the preview, as in the mockup', (
      tester,
    ) async {
      await pumpPage(tester, size: const Size(800, 700));
      await tester.tap(byKey('open'));
      await settle(tester);
      expect(byKey('step-decision-preview'), findsNothing);
      expect(row(1), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('R8 · decisions', () {
    testWidgets('one decision at a time; a choice advances after 250 ms', (
      tester,
    ) async {
      await openModal(tester, result: two);
      expect(text(tester, 'step-decision-progress'), 'Decisão 1 de 2');
      expect(text(tester, 'step-decision-question'), first.question);
      await press(tester, LogicalKeyboardKey.digit1);
      await tester.pump(const Duration(milliseconds: 249));
      expect(text(tester, 'step-decision-progress'), 'Decisão 1 de 2');
      expect(find.text('Escolhida'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2));
      await tester.pump();
      expect(text(tester, 'step-decision-progress'), 'Decisão 2 de 2');
      expect(text(tester, 'step-decision-question'), second.question);
      expect(row(3), findsNothing);
    });

    testWidgets('another key cancels the advance', (tester) async {
      await openModal(tester, result: two);
      await press(tester, LogicalKeyboardKey.digit1);
      await tester.pump(const Duration(milliseconds: 100));
      await press(tester, LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 400));
      expect(text(tester, 'step-decision-progress'), 'Decisão 1 de 2');
    });

    testWidgets('a single decision shows no progress and does not advance', (
      tester,
    ) async {
      await openModal(tester);
      expect(byKey('step-decision-progress'), findsNothing);
      await press(tester, LogicalKeyboardKey.digit1);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Escolhida'), findsOneWidget);
    });

    testWidgets('closing during the wait does not move the focus back in', (
      tester,
    ) async {
      await openModal(tester, result: two);
      await press(tester, LogicalKeyboardKey.digit1);
      await press(tester, LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);
      expect(dialog, findsNothing);
      expect(openerFocus(tester).hasFocus, isTrue);
    });

    testWidgets('closing and reopening keeps the choices and opens on the '
        'first open decision', (tester) async {
      final h = await openModal(tester, result: two);
      await press(tester, LogicalKeyboardKey.digit2);
      await press(tester, LogicalKeyboardKey.escape);
      await settle(tester);
      expect(dialog, findsNothing);
      expect(h.choices().single.title, answer.title);

      await tester.tap(byKey('open'));
      await settle(tester);
      expect(text(tester, 'step-decision-progress'), 'Decisão 2 de 2');
      await press(tester, LogicalKeyboardKey.backspace);
      await settle(tester, 2);
      expect(
        find.descendant(of: row(2), matching: find.text('Escolhida')),
        findsOneWidget,
      );
    });

    testWidgets('"Outra resposta" survives reopening too', (tester) async {
      await openModal(tester);
      await press(tester, LogicalKeyboardKey.digit5);
      await settle(tester, 2);
      await tester.enterText(byKey('step-decision-other-input'), 'Guardado');
      await tester.pump();
      await press(tester, LogicalKeyboardKey.escape);
      await settle(tester);
      await tester.tap(byKey('open'));
      await settle(tester);
      expect(find.text('Guardado'), findsWidgets);
      expect(find.text('Escolhida'), findsOneWidget);
    });

    test('a choice for an old stop does not fit the new questions', () {
      const old = StepDecisionChoice(
        decision: 0,
        question: 'Outra pergunta',
        option: answer,
      );
      expect(old.fits(first), isFalse);
      const same = StepDecisionChoice(
        decision: 0,
        question: 'Onde guardar o id?',
        option: answer,
      );
      expect(same.fits(first), isTrue);
      const gone = StepDecisionChoice(
        decision: 0,
        question: 'Onde guardar o id?',
        option: StepDecisionOption(
          title: 'Sumiu',
          kind: StepDecisionKind.answer,
        ),
      );
      expect(gone.fits(first), isFalse);
      const early = StepDecisionChoice(decision: 0, text: 'Antes das opções');
      expect(early.fits(first), isTrue);
      expect(early.fits(null), isTrue);
    });

    testWidgets('steps with no session do not share choices across specs', (
      tester,
    ) async {
      const lonely = StepView(
        id: 'R3',
        text: requirement,
        status: StepStatus.needsInput,
      );
      final h = await openModal(tester, step: lonely);
      await press(tester, LogicalKeyboardKey.digit1);
      expect(h.choices('spec-${h.spec.id}').single.title, amend.title);
      expect(h.choices(''), isEmpty);
    });
  });

  group('R9 · Compilar', () {
    testWidgets('shows the decisions, the diff and the editable message', (
      tester,
    ) async {
      final h = await compileOption(tester, 1);
      expect(h.compiler!.calls.single.single.title, amend.title);
      expect(find.text('Pronto para compilar'), findsOneWidget);
      expect(find.textContaining('Uma decisão tomada.'), findsOneWidget);
      expect(find.text('O que aconteceu'), findsNothing);

      final decided = byKey('step-decision-decided-1');
      for (final t in [
        '1 · Onde guardar o id?',
        amend.title,
        amend.kind.label,
      ]) {
        expect(
          find.descendant(of: decided, matching: find.text(t)),
          findsOneWidget,
        );
      }
      expect(byKey('step-decision-change-1'), findsOneWidget);

      expect(
        text(tester, 'step-decision-changes'),
        '1 requisito e 1 critério · +2 −1',
      );
      expect(find.text(h.spec.path), findsOneWidget);
      final semantics = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(
          RegExp('^linha removida, linha 12: - R3 · $requirement'),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(r'^linha adicionada, linha 12: - R3 · O sistema deve gravar'),
        ),
        findsOneWidget,
      );
      semantics.dispose();
      expect(find.textContaining('na mesma sessão'), findsOneWidget);

      final field = byKey('step-decision-message');
      expect(
        tester.widget<TextField>(field).controller!.text,
        'Crie a coluna image_id.',
      );
      await tester.enterText(field, 'Outra coisa');
      await tester.pump();
      expect(
        smallButton(tester, 'step-decision-submit').label,
        'Compilar e continuar',
      );
      expect(byKey('step-decision-only-spec'), findsOneWidget);
      expect(byKey('step-decision-open-session'), findsOneWidget);
      expect(find.text('Voltar'), findsOneWidget);
    });

    testWidgets('waits for the compiler, with nothing to send yet', (
      tester,
    ) async {
      final hold = Completer<void>();
      final h = await compileOption(
        tester,
        1,
        before: (h) => h.compiler!.hold = hold,
      );
      expect(byKey('step-decision-generating'), findsOneWidget);
      expect(byKey('step-decision-diff'), findsNothing);
      expect(smallButton(tester, 'step-decision-submit').onTap, isNull);
      expect(
        tester.widget<TextField>(byKey('step-decision-message')).enabled,
        isFalse,
      );
      await ctrl(tester, LogicalKeyboardKey.enter);
      await drain(tester);
      expect(h.manager.sent, isEmpty);

      hold.complete();
      await drain(tester);
      expect(byKey('step-decision-diff'), findsOneWidget);
      expect(smallButton(tester, 'step-decision-submit').onTap, isNotNull);
    });

    testWidgets('a failed compiler shows why, and "Tentar de novo" runs it', (
      tester,
    ) async {
      final h = await compileOption(
        tester,
        1,
        before: (h) =>
            h.compiler!.error = const PlannerException('O planner caiu.'),
      );
      expect(
        text(tester, 'step-decision-failure'),
        'Não consegui compilar: o planner caiu',
      );
      expect(smallButton(tester, 'step-decision-submit').onTap, isNull);
      expect(byKey('step-decision-only-spec'), findsNothing);

      h.compiler!.error = null;
      await tester.tap(byKey('step-decision-compile-retry'));
      await drain(tester);
      expect(h.compiler!.calls, hasLength(2));
      expect(byKey('step-decision-failure'), findsNothing);
      expect(byKey('step-decision-diff'), findsOneWidget);
    });

    testWidgets('only Responder: no run, no diff, "Enviar e continuar" (P3)', (
      tester,
    ) async {
      final h = await compileOption(tester, 2);
      expect(h.compiler!.calls, isEmpty);
      expect(byKey('step-decision-diff'), findsNothing);
      expect(text(tester, 'step-decision-unchanged'), 'O requisito não muda');
      expect(byKey('step-decision-only-spec'), findsNothing);
      expect(
        smallButton(tester, 'step-decision-submit').label,
        'Enviar e continuar',
      );
      expect(
        tester
            .widget<TextField>(byKey('step-decision-message'))
            .controller!
            .text,
        'Decidi pelo modal:\n'
        '1. Onde guardar o id? → Guardar em metadata.',
      );
      expect(find.textContaining('Revise a mensagem'), findsOneWidget);
    });

    testWidgets('Dividir does not go through the compiler: the spec stays', (
      tester,
    ) async {
      final h = await compileOption(tester, 3);
      expect(h.compiler!.calls, isEmpty);
      expect(byKey('step-decision-diff'), findsNothing);
      expect(byKey('step-decision-only-spec'), findsNothing);
      expect(
        smallButton(tester, 'step-decision-submit').label,
        'Compilar e continuar',
      );
      expect(
        text(tester, 'step-decision-queue'),
        contains('o R3 vira R3.1 e R3.2'),
      );
    });

    testWidgets('"Mudar" and "Voltar" go back to the decisions', (
      tester,
    ) async {
      final h = await openModal(tester, result: two, onDisk: true, alive: true);
      await drain(tester);
      await press(tester, LogicalKeyboardKey.digit2);
      await tester.pump(stepDecisionAdvanceDelay);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.digit1);
      await ctrl(tester, LogicalKeyboardKey.enter);
      await drain(tester);
      expect(find.textContaining('Duas decisões tomadas.'), findsOneWidget);

      await tester.tap(byKey('step-decision-change-1'));
      await settle(tester, 2);
      expect(byKey('step-decision-compile'), findsNothing);
      expect(text(tester, 'step-decision-progress'), 'Decisão 1 de 2');
      expect(h.choices(), hasLength(2));
    });

    testWidgets('a split out of the 2 to 4 sub-steps is refused', (
      tester,
    ) async {
      const wide = StepDecisionOption(
        title: 'Em três',
        kind: StepDecisionKind.split,
        split: ['a', 'b', 'c'],
      );
      const narrow = StepDecisionOption(
        title: 'Em duas',
        kind: StepDecisionKind.split,
        split: ['d', 'e'],
      );
      final h = await openModal(
        tester,
        onDisk: true,
        result: const StepDecisionResult(
          decisions: [
            StepDecision(question: 'A', options: [wide, answer]),
            StepDecision(question: 'B', options: [narrow, answer]),
          ],
        ),
      );
      await drain(tester);
      await press(tester, LogicalKeyboardKey.digit1);
      await tester.pump(stepDecisionAdvanceDelay);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.digit1);
      await ctrl(tester, LogicalKeyboardKey.enter);
      await drain(tester);
      expect(
        text(tester, 'step-decision-failure'),
        'Não dá para dividir: são 5 subetapas, e o limite é de 2 a 4',
      );
      expect(byKey('step-decision-compile-retry'), findsNothing);
      expect(smallButton(tester, 'step-decision-submit').onTap, isNull);
      expect(h.compiler!.calls, isEmpty);
    });

    testWidgets('a sub-step does not split again', (tester) async {
      await compileOption(
        tester,
        3,
        step: const StepView(
          id: 'R3.2',
          text: 'Gravar',
          status: StepStatus.needsInput,
          sessionId: 's1',
        ),
      );
      expect(
        text(tester, 'step-decision-failure'),
        'Não dá para dividir: R3.2 já é uma subetapa',
      );
    });

    testWidgets('fits a window as narrow as the modal goes', (tester) async {
      final h = await pumpPage(
        tester,
        size: const Size(700, 600),
        onDisk: true,
        alive: true,
      );
      await tester.tap(byKey('open'));
      await settle(tester);
      await drain(tester);
      await press(tester, LogicalKeyboardKey.digit1);
      await ctrl(tester, LogicalKeyboardKey.enter);
      await drain(tester);
      expect(byKey('step-decision-diff'), findsOneWidget);
      expect(h.compiler!.calls, hasLength(1));
    });
  });

  group('R10 · Compilar e continuar', () {
    testWidgets('live session: writes the spec, keeps its status, sends the '
        'edited message and marks the step as running', (tester) async {
      final h = await compileOption(tester, 1);
      await tester.enterText(byKey('step-decision-message'), 'Mensagem minha');
      await tester.pump();
      await submit(tester);

      expect(h.file!.readAsStringSync(), amended(specFile));
      expect(
        SpecDocument.parse(h.file!.readAsStringSync()).rawStatus,
        'aprovada',
      );
      expect(h.manager.sent, ['Mensagem minha']);
      expect(h.runner!.contexts, isEmpty);
      final rows = await h.rows();
      expect(rows['R3']!.status, StepStatus.running);
      expect(rows['R3']!.sessionId, 's1');
      expect(dialog, findsNothing);
      expect(
        text(tester, 'step-decision-toast'),
        'SPEC-003: etapa R3 retomada · requisito alterado',
      );
      expect(byKey('step-decision-undo'), findsOneWidget);
      expect(h.choices(), isEmpty);
    });

    testWidgets('Ctrl+Enter is the primary button, also in the field', (
      tester,
    ) async {
      final h = await compileOption(tester, 1);
      await tester.tap(byKey('step-decision-message'));
      await tester.pump();
      await ctrl(tester, LogicalKeyboardKey.enter);
      await finished(tester);
      expect(h.manager.sent, ['Crie a coluna image_id.']);
    });

    testWidgets('an empty message goes nowhere', (tester) async {
      final h = await compileOption(tester, 1);
      await tester.enterText(byKey('step-decision-message'), '  ');
      await tester.pump();
      expect(smallButton(tester, 'step-decision-submit').onTap, isNull);
      await ctrl(tester, LogicalKeyboardKey.enter);
      await drain(tester);
      expect(h.file!.readAsStringSync(), specFile);
    });

    testWidgets('session over: the next session starts with the message', (
      tester,
    ) async {
      final h = await compileOption(tester, 1, alive: false);
      expect(find.textContaining('A sessão terminou'), findsOneWidget);
      await submit(tester);
      expect(h.manager.sent, isEmpty);
      expect(h.manager.released, isEmpty);
      expect(h.runner!.contexts, ['Crie a coluna image_id.']);
      expect(h.file!.readAsStringSync(), amended(specFile));
    });

    testWidgets('only Responder sends without touching the file; the notice '
        'says no requirement changed', (tester) async {
      final h = await compileOption(tester, 2);
      final modified = h.file!.lastModifiedSync();
      await submit(tester);
      expect(h.manager.sent.single, contains('Guardar em metadata'));
      expect(h.file!.lastModifiedSync(), modified);
      expect(
        text(tester, 'step-decision-toast'),
        'SPEC-003: etapa R3 retomada',
      );
      expect(byKey('step-decision-undo'), findsOneWidget);
    });

    testWidgets('Dividir with a live session never sends to it: the session '
        'ends and the first sub-step gets a new one', (tester) async {
      final h = await compileOption(tester, 3);
      final message = tester
          .widget<TextField>(byKey('step-decision-message'))
          .controller!
          .text;
      await submit(tester);

      expect(h.manager.sent, isEmpty);
      expect(h.manager.released, ['s1']);
      expect(h.runner!.contexts, [message]);
      expect(h.file!.readAsStringSync(), specFile);
      final rows = await h.rows();
      expect(rows['R3']!.status, StepStatus.pending);
      expect(rows['R3.1']!.body, 'Criar a migração');
      expect(rows['R3.2']!.body, 'Gravar o id');
      expect(
        text(tester, 'step-decision-toast'),
        'SPEC-003: etapa R3 dividida em 2 subetapas',
      );
    });

    testWidgets('Adiar with a live session does not send either: the step is '
        'pending at the end of the list', (tester) async {
      final h = await compileOption(
        tester,
        4,
        before: (h) => h.compiler!.after = deferred,
      );
      expect(find.textContaining('o R3 vai para o fim'), findsOneWidget);
      await submit(tester);

      expect(h.manager.sent, isEmpty);
      expect(h.manager.released, ['s1']);
      expect(h.runner!.contexts, hasLength(1));
      expect((await h.rows())['R3']!.status, StepStatus.pending);
      final spec = (await h.container
          .read(specsRepoProvider)
          .getById(h.spec.id))!;
      expect(spec.requirements.map((r) => r.id), ['R1', 'R2', 'R4', 'R3']);
      expect(
        text(tester, 'step-decision-toast'),
        'SPEC-003: etapa R3 adiada para o fim da fila',
      );
    });

    testWidgets('"Só alterar a spec" writes and leaves the step waiting', (
      tester,
    ) async {
      final h = await compileOption(tester, 1);
      await tester.tap(byKey('step-decision-only-spec'));
      await finished(tester);
      expect(h.file!.readAsStringSync(), amended(specFile));
      expect(h.manager.sent, isEmpty);
      expect(h.runner!.contexts, isEmpty);
      expect((await h.rows())['R3']!.status, StepStatus.needsInput);
      expect(dialog, findsNothing);
      expect(byKey('step-decision-undo'), findsNothing);
      expect(
        find.text('SPEC-003: spec alterada · etapa R3 segue aguardando você'),
        findsOneWidget,
      );
    });

    testWidgets('a step that cannot resume puts everything back and stays '
        'in the phase', (tester) async {
      final h = await compileOption(tester, 3, alive: false);
      h.runner!.error = const SpecRunException('A spec tem um duelo aberto.');
      await submit(tester);
      expect(dialog, findsOneWidget);
      expect(
        text(tester, 'step-decision-failure'),
        'Não consegui retomar a etapa: A spec tem um duelo aberto. A spec e a '
        'fila voltaram ao que eram.',
      );
      final rows = await h.rows();
      expect(rows.keys, ['R3']);
      expect(rows['R3']!.status, StepStatus.needsInput);
      expect(h.choices(), hasLength(1));
      expect(smallButton(tester, 'step-decision-submit').onTap, isNotNull);
    });

    testWidgets('and a failure keeps the file of a compiled spec too', (
      tester,
    ) async {
      final h = await compileOption(tester, 1, alive: false);
      h.runner!.error = const SpecRunException('Ocupada.');
      await submit(tester);
      expect(h.file!.readAsStringSync(), specFile);
      expect(dialog, findsOneWidget);
    });

    group('Desfazer', () {
      testWidgets('stops the session that got the message and only then puts '
          'the file and the queue back', (tester) async {
        final h = await compileOption(tester, 1);
        await submit(tester);
        String? textAtStop;
        h.manager.onRelease = () => textAtStop = h.file!.readAsStringSync();

        await undoAndWait(tester, undone);

        expect(h.manager.released, ['s1']);
        expect(textAtStop, amended(specFile));
        expect(h.file!.readAsStringSync(), specFile);
        final row = (await h.rows())['R3']!;
        expect(row.status, StepStatus.needsInput);
        expect(h.choices().single.title, amend.title);
      });

      testWidgets('a split: the session started goes, the sub-steps too', (
        tester,
      ) async {
        final h = await compileOption(tester, 3);
        await submit(tester);
        expect((await h.rows()).keys, containsAll(['R3.1', 'R3.2']));

        await undoAndWait(tester, undone);

        expect(h.manager.released, ['s1', 's2']);
        final rows = await h.rows();
        expect(rows.keys, ['R3']);
        expect(rows['R3']!.status, StepStatus.needsInput);
      });

      testWidgets('leaves at the first event of the session', (tester) async {
        final h = await compileOption(tester, 1);
        await submit(tester);
        expect(byKey('step-decision-undo'), findsOneWidget);
        // The load of the stored events is not an event.
        await drain(tester);
        expect(byKey('step-decision-undo'), findsOneWidget);

        h.container
            .read(sessionTimelineProvider('s1').notifier)
            .push(const UnknownEvent({'type': 'assistant'}));
        await tester.pump();
        expect(byKey('step-decision-undo'), findsNothing);
        expect(byKey('step-decision-toast'), findsOneWidget);
      });

      testWidgets('watches the new session, not the old one', (tester) async {
        final h = await compileOption(tester, 1, alive: false);
        await submit(tester);
        h.container
            .read(sessionTimelineProvider('s1').notifier)
            .push(const UnknownEvent({'type': 'assistant'}));
        await tester.pump();
        expect(byKey('step-decision-undo'), findsOneWidget);
        h.container
            .read(sessionTimelineProvider('s2').notifier)
            .push(const UnknownEvent({'type': 'assistant'}));
        await tester.pump();
        expect(byKey('step-decision-undo'), findsNothing);
      });

      testWidgets('is there for 8 s', (tester) async {
        await compileOption(tester, 1);
        await submit(tester);
        await tester.pump(const Duration(seconds: 7));
        expect(byKey('step-decision-undo'), findsOneWidget);
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 1));
        expect(byKey('step-decision-undo'), findsNothing);
      });

      testWidgets('touches nothing when the file changed after compiling', (
        tester,
      ) async {
        final h = await compileOption(tester, 1);
        await submit(tester);
        h.file!.writeAsStringSync('${amended(specFile)}\n<!-- editado -->\n');
        await undoAndWait(
          tester,
          'A spec mudou depois de compilar: nada foi desfeito.',
        );

        expect(h.manager.released, isEmpty);
        expect(h.file!.readAsStringSync(), contains('editado'));
        expect((await h.rows())['R3']!.status, StepStatus.running);
      });
    });
  });

  group('R11 · spec changed on the disk', () {
    const edited = '$specFile\n<!-- editado -->\n';

    testWidgets('nothing is written and the modal says so', (tester) async {
      final h = await compileOption(tester, 1);
      h.file!.writeAsStringSync(edited);
      await submit(tester);

      expect(h.file!.readAsStringSync(), edited);
      expect(h.manager.sent, isEmpty);
      expect((await h.rows())['R3']!.status, StepStatus.needsInput);
      expect(dialog, findsOneWidget);
      expect(find.text('A spec mudou enquanto você decidia'), findsOneWidget);
      expect(byKey('step-decision-diff'), findsNothing);
      expect(smallButton(tester, 'step-decision-submit').onTap, isNull);
    });

    testWidgets('a change before Compilar counts, since the opening', (
      tester,
    ) async {
      final h = await compileOption(
        tester,
        1,
        before: (h) => h.file!.writeAsStringSync(edited),
      );
      await submit(tester);
      expect(byKey('step-decision-conflict'), findsOneWidget);
      expect(h.manager.sent, isEmpty);
    });

    testWidgets('the same text with a new mtime is a change too', (
      tester,
    ) async {
      final h = await compileOption(tester, 1);
      h.file!.setLastModifiedSync(DateTime(2020));
      await submit(tester);
      expect(byKey('step-decision-conflict'), findsOneWidget);
      expect(h.manager.sent, isEmpty);
    });

    testWidgets('"Só alterar a spec" stops at the conflict as well', (
      tester,
    ) async {
      final h = await compileOption(tester, 1);
      h.file!.writeAsStringSync(edited);
      await tester.tap(byKey('step-decision-only-spec'));
      await finished(tester);
      expect(h.file!.readAsStringSync(), edited);
      expect(byKey('step-decision-conflict'), findsOneWidget);
    });

    testWidgets('a split writes no file, and still does not touch the queue', (
      tester,
    ) async {
      final h = await compileOption(tester, 3);
      h.file!.writeAsStringSync(edited);
      await submit(tester);
      expect((await h.rows()).keys, ['R3']);
      expect(h.runner!.contexts, isEmpty);
      expect(byKey('step-decision-conflict'), findsOneWidget);
    });

    testWidgets('only Responder writes nothing, so nothing conflicts', (
      tester,
    ) async {
      final h = await compileOption(tester, 2);
      h.file!.writeAsStringSync(edited);
      await submit(tester);
      expect(h.manager.sent, hasLength(1));
      expect(h.file!.readAsStringSync(), edited);
    });

    testWidgets('"Recompilar" starts from the file as it is now', (
      tester,
    ) async {
      final h = await compileOption(tester, 1);
      h.file!.writeAsStringSync(edited);
      await submit(tester);
      await tester.tap(byKey('step-decision-recompile'));
      await drain(tester);
      expect(h.compiler!.calls, hasLength(2));
      expect(byKey('step-decision-conflict'), findsNothing);
      expect(byKey('step-decision-diff'), findsOneWidget);

      await submit(tester);
      expect(h.file!.readAsStringSync(), amended(edited));
      expect(h.manager.sent, hasLength(1));
    });

    testWidgets('"Abrir no editor" opens the file, from the workspace', (
      tester,
    ) async {
      final started = <(String, List<String>, String)>[];
      final h = await compileOption(
        tester,
        1,
        overrides: [
          worktreeLauncherProvider.overrideWithValue(
            WorktreeLauncher(
              which: (_) async => true,
              start: (exe, args, cwd) async => started.add((exe, args, cwd)),
            ),
          ),
        ],
      );
      h.file!.writeAsStringSync(edited);
      await submit(tester);
      await tester.tap(byKey('step-decision-open-editor'));
      await drain(tester);
      expect(started.single.$1, 'code');
      expect(started.single.$2, [h.file!.path]);
      expect(started.single.$3, h.file!.parent.parent.path);
    });
  });

  group('R12 · Abrir sessão', () {
    testWidgets('closes the modal, opens the session and leaves a draft of the '
        'decisions; a finished session is resumed', (tester) async {
      final h = await openModal(tester, result: two);
      await press(tester, LogicalKeyboardKey.digit1);
      await tester.pump(stepDecisionAdvanceDelay);
      await tester.pump();
      await ctrl(tester, LogicalKeyboardKey.keyO);
      await settle(tester);
      expect(dialog, findsNothing);
      expect(h.container.read(selectedSessionProvider), 's1');
      expect(h.container.read(navigationProvider), AppSection.sessions);
      expect(h.container.read(sessionComposerDraftProvider)['s1'], '''
Decidi pelo modal:
1. Onde guardar o id? → Criar a coluna image_id.
2. Como mostrar o id? (ainda não decidi; vamos ver juntos)''');
      expect(h.manager.resumed, ['s1']);
      expect(h.manager.sent, isEmpty);
      expect(
        openerFocus(tester).hasFocus,
        isFalse,
        reason: 'the focus belongs to the message field now',
      );
    });

    testWidgets('a live session is not resumed; with nothing decided there is '
        'no draft', (tester) async {
      final h = await openModal(tester, alive: true);
      await tester.tap(byKey('step-decision-open-session'));
      await settle(tester);
      expect(h.manager.resumed, isEmpty);
      expect(h.container.read(sessionComposerDraftProvider), isEmpty);
      expect(h.container.read(selectedSessionProvider), 's1');
    });

    testWidgets('a step with no session stays usable, with the button off', (
      tester,
    ) async {
      final h = await openModal(
        tester,
        result: const StepDecisionResult(error: 'sem sessão'),
        step: const StepView(
          id: 'R3',
          text: requirement,
          status: StepStatus.needsInput,
        ),
      );
      expect(find.byTooltip('Esta etapa ainda não tem sessão'), findsOneWidget);
      await ctrl(tester, LogicalKeyboardKey.keyO);
      await settle(tester);
      expect(dialog, findsOneWidget);
      expect(h.container.read(navigationProvider), isNot(AppSection.sessions));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the message field takes the draft without sending it', (
      tester,
    ) async {
      final manager = FakeManager();
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          databaseOverride(memoryDatabase()),
          sessionManagerProvider.overrideWith(() => manager),
        ],
      );
      addTearDown(c.dispose);
      c
          .read(sessionComposerDraftProvider.notifier)
          .put('s1', 'Decidi pelo modal:\n1. Sim.');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: SessionComposer(sessionId: 's1', permissionMode: null),
              ),
            ),
          ),
        ),
      );
      await settle(tester, 3);
      final field = tester.widget<TextField>(byKey('composer-field'));
      expect(field.controller!.text, 'Decidi pelo modal:\n1. Sim.');
      expect(byKey('composer-draft-note'), findsOneWidget);
      expect(c.read(sessionComposerDraftProvider), isEmpty);
      expect(manager.sent, isEmpty);

      // Already on screen: a new draft goes after what is written.
      c.read(sessionComposerDraftProvider.notifier).put('s1', 'Outro');
      await settle(tester, 3);
      expect(field.controller!.text, endsWith('\n\nOutro'));
      expect(manager.sent, isEmpty);

      field.controller!.clear();
      await settle(tester, 3);
      expect(byKey('composer-draft-note'), findsNothing);
    });

    test('stepDecisionDraft is empty with nothing decided and works with no '
        'options', () {
      expect(stepDecisionDraft(two.decisions, const []), '');
      expect(
        stepDecisionDraft(const [], const [
          StepDecisionChoice(decision: 0, text: 'Use metadata'),
        ]),
        'Decidi pelo modal:\n1. Use metadata.',
      );
    });
  });

  group('R14 · waiting and errors', () {
    testWidgets('generating: skeletons, the time, "Outra resposta" and "Abrir '
        'sessão" work, and closing cancels', (tester) async {
      final h = await openModal(tester, result: null);
      expect(h.options.generated, ['R3']);
      expect(byKey('step-decision-skeleton-summary'), findsOneWidget);
      expect(byKey('step-decision-skeleton-rows'), findsOneWidget);
      expect(
        text(tester, 'step-decision-generating'),
        'A IA está lendo a sessão…',
      );
      expect(text(tester, 'step-decision-elapsed'), '0 s');
      await tester.pump(const Duration(seconds: 3));
      expect(text(tester, 'step-decision-elapsed'), '3 s');
      expect(row(1), findsNothing);

      await press(tester, LogicalKeyboardKey.digit1);
      expect(h.choices(), isEmpty);
      await tester.tap(byKey('step-decision-other-button'));
      await settle(tester, 2);
      await tester.enterText(byKey('step-decision-other-input'), 'Faça X');
      await tester.pump();
      expect(h.choices().single.title, 'Faça X');
      await ctrl(tester, LogicalKeyboardKey.enter);
      await settle(tester, 2);
      expect(byKey('step-decision-compile'), findsOneWidget);
      await tester.tap(byKey('step-decision-compile-back'));
      await settle(tester, 2);

      await tester.tap(byKey('step-decision-close'));
      await settle(tester);
      expect(h.options.cancelled, ['R3']);
    });

    testWidgets('generation starts only when the modal opens', (tester) async {
      final h = await pumpPage(tester, result: null);
      expect(h.options.generated, isEmpty);
      await tester.tap(byKey('open'));
      await settle(tester);
      expect(h.options.generated, hasLength(1));
      await press(tester, LogicalKeyboardKey.escape);
      await settle(tester);
    });

    testWidgets('the options arrive and take the focus, unless the person is '
        'writing', (tester) async {
      final h = await openModal(tester, result: null);
      h.options.deliver((h.spec.id, 'R3'), one);
      await settle(tester, 3);
      expect(byKey('step-decision-skeleton-rows'), findsNothing);
      expect(text(tester, 'step-decision-summary'), summary);
      expect(
        tester.widget<StepDecisionOptionRow>(row(1)).focusNode.hasFocus,
        isTrue,
      );
    });

    testWidgets('options that arrive while writing leave the field alone', (
      tester,
    ) async {
      final h = await openModal(tester, result: null);
      await press(tester, LogicalKeyboardKey.digit5);
      await settle(tester, 2);
      await tester.enterText(byKey('step-decision-other-input'), 'Escrevendo');
      await tester.pump();
      h.options.deliver((h.spec.id, 'R3'), two);
      await settle(tester, 3);
      expect(byKey('step-decision-other-input'), findsOneWidget);
      expect(find.text('Escrevendo'), findsWidgets);
      expect(text(tester, 'step-decision-progress'), 'Decisão 1 de 2');
      expect(focusInsideDialog(), isTrue);
    });

    testWidgets('failure: the reason, "Tentar de novo", "Outra resposta" and '
        '"Abrir sessão"', (tester) async {
      final h = await openModal(
        tester,
        result: const StepDecisionResult(error: 'o planner não respondeu'),
      );
      expect(
        text(tester, 'step-decision-failure'),
        'Não consegui propor opções: o planner não respondeu',
      );
      expect(byKey('step-decision-other'), findsOneWidget);
      expect(byKey('step-decision-open-session'), findsOneWidget);
      await tester.tap(byKey('step-decision-retry'));
      await settle(tester, 3);
      expect(h.options.retried, ['R3']);
      expect(byKey('step-decision-skeleton-rows'), findsOneWidget);
      expect(text(tester, 'step-decision-elapsed'), '0 s');

      h.options.deliver((
        h.spec.id,
        'R3',
      ), const StepDecisionResult(error: 'de novo'));
      await settle(tester, 3);
      await press(tester, LogicalKeyboardKey.digit5);
      await settle(tester, 2);
      await tester.enterText(byKey('step-decision-other-input'), 'Assim');
      await tester.pump();
      await ctrl(tester, LogicalKeyboardKey.enter);
      await settle(tester, 2);
      expect(byKey('step-decision-compile'), findsOneWidget);
    });

    testWidgets('a failed gate shows the command and the last lines, with no '
        'wait for the AI', (tester) async {
      final gate = gateFailure();
      await openModal(
        tester,
        result: null,
        step: StepView(
          id: 'R3',
          text: requirement,
          status: StepStatus.needsInput,
          sessionId: 's1',
          gate: gate,
        ),
      );
      expect(
        text(tester, 'step-decision-gate-title'),
        'Verificação do R3 falhou · 3 de 3 tentativas',
      );
      final block = tester.widget<Text>(
        find.descendant(
          of: byKey('step-decision-gate'),
          matching: find.byType(Text),
        ),
      );
      expect(
        block.data,
        '\$ flutter test test/data/machines_repo_test.dart\n'
        '…\nlinha 7\nlinha 8\nlinha 9',
      );
      expect(byKey('step-decision-skeleton-summary'), findsNothing);
    });

    testWidgets('the gate of a sub-step is the one of its requirement', (
      tester,
    ) async {
      await openModal(
        tester,
        result: const StepDecisionResult(
          decisions: [
            StepDecision(
              question: 'Q',
              options: [
                StepDecisionOption(
                  title: 'Corrigir o teste',
                  kind: StepDecisionKind.amend,
                ),
                StepDecisionOption(
                  title: 'Marcar o critério como manual',
                  kind: StepDecisionKind.amend,
                ),
              ],
            ),
          ],
        ),
        step: StepView(
          id: 'R3.2',
          text: 'Gravar',
          status: StepStatus.needsInput,
          sessionId: 's1',
          gate: gateFailure(),
        ),
      );
      expect(
        text(tester, 'step-decision-gate-title'),
        'Verificação do R3 falhou · 3 de 3 tentativas',
      );
      expect(find.text('Corrigir o teste'), findsOneWidget);
      expect(find.text('Marcar o critério como manual'), findsOneWidget);
    });
  });

  group('R15 · accessibility', () {
    testWidgets('the modal is a named dialog and the options are radios', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await openModal(tester);
      expect(
        find.bySemanticsLabel('Decidir a etapa 3 da SPEC-003'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(row(1)),
        isSemantics(
          label:
              'Opção 1 de 4: Criar a coluna image_id. Ajustar o requisito. '
              'O R3 ganha um critério. sugerida',
          isInMutuallyExclusiveGroup: true,
          hasCheckedState: true,
          isChecked: false,
          isFocusable: true,
          isFocused: true,
        ),
      );
      expect(
        tester.getSemantics(row(2)),
        isSemantics(
          label: 'Opção 2 de 4: Guardar em metadata. Responder. Sem migração',
          isInMutuallyExclusiveGroup: true,
        ),
      );
      await press(tester, LogicalKeyboardKey.digit2);
      await settle(tester, 2);
      expect(tester.getSemantics(row(2)), isSemantics(isChecked: true));
      expect(find.bySemanticsLabel('Opção 5: outra resposta'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('every state of the list is valid for a screen reader', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final h = await openModal(tester, result: null);
      await press(tester, LogicalKeyboardKey.digit5);
      await settle(tester, 2);
      expect(find.bySemanticsLabel('Outra resposta'), findsWidgets);
      h.options.deliver((
        h.spec.id,
        'R3',
      ), const StepDecisionResult(error: 'falhou'));
      await settle(tester, 3);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('a change of decision is a polite notice, and the focus stays '
        'on the list', (tester) async {
      await openModal(tester, result: two);
      tester.takeAnnouncements();
      await press(tester, LogicalKeyboardKey.digit1);
      await tester.pump(stepDecisionAdvanceDelay);
      await settle(tester, 2);
      final notices = tester.takeAnnouncements();
      expect(notices.map((n) => n.message), ['Decisão 2 de 2']);
      expect(notices.single.assertiveness, Assertiveness.polite);
      expect(
        tester.widget<StepDecisionOptionRow>(row(1)).focusNode.hasFocus,
        isTrue,
      );
    });

    testWidgets('the focus stays in the modal and goes back when it closes', (
      tester,
    ) async {
      await openModal(tester);
      for (var i = 0; i < 25; i++) {
        await press(tester, LogicalKeyboardKey.tab);
        expect(focusInsideDialog(), isTrue, reason: 'tab $i');
      }
      await press(tester, LogicalKeyboardKey.escape);
      await settle(tester);
      expect(dialog, findsNothing);
      expect(openerFocus(tester).hasFocus, isTrue);
    });

    testWidgets('a click on the scrim also gives the focus back', (
      tester,
    ) async {
      await openModal(tester);
      await tester.tapAt(const Offset(5, 5));
      await settle(tester);
      expect(dialog, findsNothing);
      expect(openerFocus(tester).hasFocus, isTrue);
    });
  });
}
