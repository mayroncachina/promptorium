import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/diff_parser.dart';
import 'package:promptorium/core/system/worktree_launcher.dart';
import 'package:promptorium/features/project/widgets/project_config_view.dart'
    show configFocusProvider;
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/review/merge_options.dart';
import 'package:promptorium/features/review/merge_readiness.dart';
import 'package:promptorium/features/review/restack.dart';
import 'package:promptorium/features/review/review_screen.dart';
import 'package:promptorium/features/review/review_service.dart';
import 'package:promptorium/features/review/widgets/spec_review_panel.dart'
    show pendingCriteriaProvider;
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';
import '../board/board_rules_test.dart' show spec;
import '../sessions/session_test_utils.dart';
import 'review_logic_test.dart' show sampleDiff, session;

/// SPEC-032 R1–R3, R5, R10, R14: the queue as stacks.
ReviewItem item(String id, Spec s, {String base = 'main'}) => ReviewItem(
  session: session(id: id).copyWith(
    branch: 'pr/$id',
    baseBranch: Value(base),
    specId: Value(s.id),
    title: Value(s.code),
  ),
  spec: s,
);

final a = spec(
  1,
  'SPEC-029',
  stage: SpecStage.review,
).copyWith(branch: const Value('pr/a'));
final b = spec(
  2,
  'SPEC-031',
  stage: SpecStage.review,
).copyWith(branch: const Value('pr/b'), baseBranch: const Value('pr/a'));
final x = spec(
  3,
  'SPEC-030',
  stage: SpecStage.review,
).copyWith(branch: const Value('pr/x'));

class _FakeReview extends ReviewService {
  _FakeReview(super.ref);
  final merged = <String>[];
  final root = <String>[];
  final calls = <String>[];
  RebaseStatus rebase = const RebaseStatus();
  @override
  Future<RebaseStatus> rebaseStatus(String sessionId) async =>
      sessionId == 'x' ? rebase : const RebaseStatus();
  @override
  Future<List<ConflictHunk>> conflictHunks(String sessionId) async => [
    const ConflictHunk(path: 'lib/a.dart', line: 3, base: ['Y'], spec: ['X']),
  ];
  @override
  Future<List<String>> resolveConflict(
    String sessionId, {
    String origin = 'pessoa',
  }) async {
    calls.add('agente $sessionId');
    return const [];
  }

  @override
  Future<RebaseStatus> startRebase(String sessionId) async {
    calls.add('rebase $sessionId');
    return rebase;
  }

  @override
  Future<void> abortRebase(String sessionId) async =>
      calls.add('abort $sessionId');
  @override
  Future<void> switchRoot(Workspace ws, String base) async =>
      root.add('switch $base');
  @override
  Future<void> stashRoot(Workspace ws) async => root.add('stash');
  final conflicts = <String, List<String>>{};
  @override
  Future<ConflictPrediction> predictConflict(String sessionId) async =>
      ConflictPrediction(files: conflicts[sessionId] ?? const []);
  @override
  Future<MergeFacts> mergeFacts(String sessionId) async =>
      const MergeFacts(rootBranch: 'main');
  @override
  Future<MergeResult> merge(
    String sessionId, {
    bool deleteBranch = true,
    String? override,
    MergeOptions options = const MergeOptions(),
  }) async {
    merged.add(sessionId);
    return const MergeResult(commit: 'abcdef1234');
  }
}

final launched = <(String, List<String>, String)>[];

Future<ProviderContainer> pumpStack(
  WidgetTester tester, {
  Map<String, List<String>> conflicts = const {},
  RootStatus? root,
  RebaseStatus rebase = const RebaseStatus(),
  List<Override> extra = const [],
}) async {
  launched.clear();
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
  // Sessions order on purpose: top of the stack first.
  final items = [item('b', b, base: 'pr/a'), item('x', x), item('a', a)];
  final files = DiffParser.parse(sampleDiff);
  final container = ProviderContainer(
    // No retry timers for providers that fail on the fake paths.
    retry: (_, _) => null,
    overrides: [
      ...sessionOverrides(db: db, cli: FakeCli(), notifier: FakeNotifier()),
      reviewQueueProvider.overrideWith((ref, id) async => items),
      specsProvider.overrideWith((ref, id) => Stream.value([a, b, x])),
      pendingCriteriaProvider.overrideWith((ref, id) async => const []),
      reviewDetailProvider.overrideWith(
        (ref, id) async => ReviewDetail(
          session: items.firstWhere((i) => i.session.id == id).session,
          baseBranch: id == 'b' ? 'pr/a' : 'main',
          mergeBase: 'abc',
          files: files,
          commitsAhead: 1,
          uncommitted: 0,
        ),
      ),
      prAvailabilityProvider.overrideWith(
        (ref, id) async =>
            const PrAvailability(available: false, reason: 'sem gh'),
      ),
      mergeReadinessProvider.overrideWith(
        (ref, id) async => evaluateReadiness(
          ReadinessInputs(
            hasSpec: true,
            stackedOn: id == 'b' ? 'SPEC-029' : null,
          ),
        ),
      ),
      ...extra,
      rootStatusProvider.overrideWith((ref, id) async => root),
      worktreeLauncherProvider.overrideWithValue(
        WorktreeLauncher(
          start: (exe, args, cwd) async => launched.add((exe, args, cwd)),
          which: (exe) async => exe == 'gnome-terminal' || exe == 'code',
        ),
      ),
      reviewServiceProvider.overrideWith((ref) {
        final f = _FakeReview(ref);
        f.conflicts.addAll(conflicts);
        f.rebase = rebase;
        return f;
      }),
    ],
  );
  await container.read(appSettingsProvider.notifier).load();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: ReviewScreen()),
      ),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(Duration.zero);
  });
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  return container;
}

Finder card(String id) => find.byKey(ValueKey('review-item-$id'));

String stateOf(WidgetTester t, String id) => t
    .widget<Text>(
      find.descendant(
        of: find.byKey(ValueKey('review-item-state-$id')),
        matching: find.byType(Text),
      ),
    )
    .data!;

void main() {
  testWidgets('R1 R2 · the stack goes from the base to the top, then the '
      'loose specs; titles in normal case; position and mother', (
    tester,
  ) async {
    await pumpStack(tester);
    expect(find.text('Aguardando review · 3'), findsOneWidget);
    expect(find.text('Pilha · 2'), findsOneWidget);
    expect(find.text('Avulsas · 1'), findsOneWidget);
    final ya = tester.getTopLeft(card('a')).dy;
    final yb = tester.getTopLeft(card('b')).dy;
    final yx = tester.getTopLeft(card('x')).dy;
    expect(ya < yb && yb < yx, isTrue);
    expect(find.text('1 de 2'), findsOneWidget);
    expect(find.text('2 de 2 · sobre SPEC-029'), findsOneWidget);
    // The first item of the order is selected by default.
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('review-title'))).data,
      'SPEC-029',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('R3 R4 R14 · each card says its state in text, with the '
      'accessible label', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpStack(
      tester,
      conflicts: {
        'x': ['lib/a.dart'],
      },
    );
    expect(stateOf(tester, 'a'), 'Pronto para merge');
    expect(stateOf(tester, 'b'), 'Espera SPEC-029');
    expect(stateOf(tester, 'x'), 'Conflito em lib/a.dart');
    expect(
      find.bySemanticsLabel('SPEC-031, 2 de 2 na pilha, espera SPEC-029'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('SPEC-030, conflito em lib/a.dart'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('R8 R10 · clicking a card only selects it; the primary action '
      'follows its state', (tester) async {
    final c = await pumpStack(tester);
    await tester.tap(card('b'));
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(c.read(selectedReviewProvider), 'b');
    expect((c.read(reviewServiceProvider) as _FakeReview).merged, isEmpty);
    expect(find.text('Ir para SPEC-029'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('review-go-mother')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(c.read(selectedReviewProvider), 'a');
  });

  testWidgets('R5 · after the merge the child is selected and a notice says '
      'where the screen went', (tester) async {
    final c = await pumpStack(tester);
    await tester.tap(find.byKey(const ValueKey('review-merge')));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey('review-merge-confirm')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect((c.read(reviewServiceProvider) as _FakeReview).merged, ['a']);
    expect(c.read(selectedReviewProvider), 'b');
    expect(
      find.textContaining('SPEC-029 entrou na main · seguindo para SPEC-031'),
      findsOneWidget,
    );
  });

  testWidgets('R11 · root off main: fixed notice in the queue with "Voltar '
      'para a main"; with changes, "Guardar alterações" first', (tester) async {
    var c = await pumpStack(
      tester,
      root: const RootStatus(base: 'main', branch: 'spec/031-filha'),
    );
    expect(
      find.text('A raiz está em spec/031-filha, o merge vai para main.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('review-root-stash')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('review-root-switch')));
    await tester.pump();
    expect((c.read(reviewServiceProvider) as _FakeReview).root, [
      'switch main',
    ]);
    await tester.pumpWidget(const SizedBox());

    c = await pumpStack(
      tester,
      root: const RootStatus(
        base: 'main',
        branch: 'spec/031-filha',
        dirty: ['lib/a.dart'],
      ),
    );
    expect(find.textContaining('1 alteração não commitada'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('review-root-switch')));
    await tester.tap(find.byKey(const ValueKey('review-root-stash')));
    await tester.pump();
    expect((c.read(reviewServiceProvider) as _FakeReview).root, ['stash']);
    await tester.pumpWidget(const SizedBox());

    await pumpStack(
      tester,
      root: const RootStatus(base: 'main', branch: 'main'),
    );
    expect(find.byKey(const ValueKey('review-root-banner')), findsNothing);
  });

  testWidgets('R9 · Terminal and Editor open the spec worktree; Testar '
      'without "executar:" opens the project config on that field', (
    tester,
  ) async {
    final c = await pumpStack(tester);
    expect(find.textContaining('/wt · pr/a'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('review-wt-terminal')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('review-wt-editor')));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(
      [for (final (exe, args, cwd) in launched) '$exe ${args.join(' ')}@$cwd'],
      ['gnome-terminal @/wt', 'code /wt@/wt'],
    );
    await tester.tap(find.byKey(const ValueKey('review-wt-run')));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(c.read(navigationProvider), AppSection.settings);
    expect(c.read(configFocusProvider), 'executar');
  });

  test('middleEllipsis keeps the start and the end of a long path', () {
    expect(middleEllipsis('/curto'), '/curto');
    final long = middleEllipsis(
      '/home/mayron/.promptorium/worktrees/promptorium/spec-031-filha',
      max: 30,
    );
    expect(long.length, 30);
    expect(long, startsWith('/home/mayr'));
    expect(long, endsWith('spec-031-filha'));
  });

  Future<_FakeReview> selectX(WidgetTester tester, ProviderContainer c) async {
    await tester.tap(card('x'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    return c.read(reviewServiceProvider) as _FakeReview;
  }

  testWidgets('R17 · a conflict offers the agent (recommended) or a manual '
      'rebase, and shows both sides of each stretch', (tester) async {
    final c = await pumpStack(
      tester,
      conflicts: {
        'x': ['lib/a.dart'],
      },
    );
    final f = await selectX(tester, c);
    expect(find.byKey(const ValueKey('review-conflict-panel')), findsOneWidget);
    expect(find.text('Recomendado'), findsOneWidget);
    expect(find.text('Trecho 1 de 1 · a.dart, linhas 3–6'), findsOneWidget);
    expect(find.text('Nesta spec (SPEC-030)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('review-conflict-agent')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('review-conflict-start')));
    await tester.pump();
    expect(f.calls, ['agente x', 'rebase x']);
    // The notices leave after their 8 s.
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('R17 · during the manual rebase: state in the card, files with '
      'markers, "Continuar" only without markers, "Desistir"', (tester) async {
    final c = await pumpStack(
      tester,
      rebase: const RebaseStatus(
        inProgress: true,
        step: 1,
        total: 2,
        files: {'lib/a.dart': 3, 'lib/b.dart': 0},
      ),
    );
    final f = await selectX(tester, c);
    expect(stateOf(tester, 'x'), 'Rebase em andamento · 1 de 2');
    expect(find.text('Abrir no editor'), findsWidgets);
    expect(find.text('ainda tem marcadores'), findsOneWidget);
    expect(find.text('resolvido'), findsOneWidget);
    final cont = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const ValueKey('review-rebase-continue')),
        matching: find.byType(InkWell),
      ),
    );
    expect(cont.onTap, isNull);
    await tester.tap(find.byKey(const ValueKey('review-rebase-abort')));
    await tester.pump();
    expect(f.calls, ['abort x']);
    // The notices leave after their 8 s.
    await tester.pump(const Duration(seconds: 10));
  });
}
