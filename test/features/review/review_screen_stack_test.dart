import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/diff_parser.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/review/merge_options.dart';
import 'package:promptorium/features/review/merge_readiness.dart';
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

Future<ProviderContainer> pumpStack(
  WidgetTester tester, {
  Map<String, List<String>> conflicts = const {},
}) async {
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
      reviewServiceProvider.overrideWith((ref) {
        final f = _FakeReview(ref);
        f.conflicts.addAll(conflicts);
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
}
