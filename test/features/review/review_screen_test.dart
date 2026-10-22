import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/diff_parser.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/review/merge_options.dart'
    show ConflictPrediction;
import 'package:promptorium/features/review/merge_readiness.dart';
import 'package:promptorium/features/review/review_screen.dart';
import 'package:promptorium/features/review/review_service.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';
import 'review_logic_test.dart' show sampleDiff, session, task;

const secondFile = '''
diff --git a/test/ui/status_bar_test.dart b/test/ui/status_bar_test.dart
new file mode 100644
index 0000000..3333333
--- /dev/null
+++ b/test/ui/status_bar_test.dart
@@ -0,0 +1,2 @@
+void main() {}
+// fim
''';

Future<ProviderContainer> pumpReview(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  PrAvailability pr = const PrAvailability(
    available: false,
    reason: 'GitHub CLI (gh) não encontrado no PATH.',
  ),
  MergeReadiness? readiness,
}) async {
  tester.view.physicalSize = size;
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
  final s = session(taskId: 1);
  final t = task();
  final files = DiffParser.parse('$sampleDiff$secondFile');
  final container = ProviderContainer(
    overrides: [
      ...sessionOverrides(db: db, cli: FakeCli(), notifier: FakeNotifier()),
      reviewQueueProvider.overrideWith(
        (ref, id) async => [
          ReviewItem(session: s, task: t),
          ReviewItem(
            session: session(
              id: 's2',
              taskId: null,
            ).copyWith(title: const Value('Tema escuro e tokens')),
          ),
        ],
      ),
      reviewDetailProvider.overrideWith(
        (ref, id) async => ReviewDetail(
          session: s,
          task: t,
          baseBranch: 'main',
          mergeBase: 'abc',
          files: files,
          commitsAhead: 2,
          uncommitted: 1,
        ),
      ),
      prAvailabilityProvider.overrideWith((ref, id) async => pr),
      if (readiness != null) ...[
        mergeReadinessProvider.overrideWith((ref, id) async => readiness),
        reviewServiceProvider.overrideWith(_NoConflictReview.new),
      ],
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

void main() {
  testWidgets('fits the minimum window (1100×700) without overflow; queue, '
      'files, header and disabled "Criar PR"', (tester) async {
    // Shell: sidebar 56px, title bar + footer ≈ 72px.
    await pumpReview(tester, size: const Size(1044, 628));
    expect(tester.takeException(), isNull);
    expect(find.text('AGUARDANDO REVIEW · 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('review-item-s1')), findsOneWidget);
    expect(find.text('TASK-011 · implementer'), findsOneWidget);
    expect(find.text('Tema escuro e tokens'), findsOneWidget);
    expect(find.text('ARQUIVOS · 2'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('review-file-lib/ui/status_bar.dart')),
      findsOneWidget,
    );
    final subtitle = tester.widget<Text>(
      find.byKey(const ValueKey('review-subtitle')),
    );
    expect(
      subtitle.textSpan!.toPlainText(),
      'pr/status-bar → main · 2 arquivos · +4 −1 · 2 commits · '
      '1 não commitado',
    );
    // Criar PR disabled with the reason in the tooltip.
    final pr = tester.widget<Tooltip>(
      find.byKey(const ValueKey('review-create-pr-tooltip')),
    );
    expect(pr.message, contains('gh'));
    expect(
      tester
          .widget<InkWell>(
            find.descendant(
              of: find.byKey(const ValueKey('review-create-pr')),
              matching: find.byType(InkWell),
            ),
          )
          .onTap,
      isNull,
    );
    // Diff with line numbers.
    expect(find.byKey(const ValueKey('review-line-8')), findsOneWidget);
    expect(find.byKey(const ValueKey('review-line-o7')), findsOneWidget);

    // Other file.
    await tester.tap(
      find.byKey(const ValueKey('review-file-test/ui/status_bar_test.dart')),
    );
    await tester.pump();
    expect(find.text('// fim'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clicking a line number opens the comment box; "Comentar" '
      'adds a pending comment; "Aceitar hunk" marks it reviewed', (
    tester,
  ) async {
    final c = await pumpReview(tester, size: const Size(1044, 628));
    await tester.tap(find.byKey(const ValueKey('review-line-8')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('review-comment-box-0-4')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('review-comment-field')),
      'Use o tema do app.',
    );
    await tester.tap(find.byKey(const ValueKey('review-comment-submit')));
    await tester.pump();
    expect(find.byKey(const ValueKey('review-comment-box-0-4')), findsNothing);
    expect(
      find.text('Comentário pendente · lib/ui/status_bar.dart:8'),
      findsOneWidget,
    );
    expect(find.text('Pedir ajustes ao agente (1)'), findsOneWidget);
    final draft = c.read(reviewDraftProvider('s1'));
    expect(draft.comments.single.location, 'lib/ui/status_bar.dart:8');

    // Opening the comment box scrolls its submit button into view. Scroll
    // back to the hunk header before accepting it.
    await tester.ensureVisible(
      find.descendant(
        of: find.byKey(const ValueKey('review-diff-lib/ui/status_bar.dart')),
        matching: find.byKey(const ValueKey('review-accept-0')),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('review-diff-lib/ui/status_bar.dart')),
        matching: find.byKey(const ValueKey('review-accept-0')),
      ),
    );
    await tester.pump();
    expect(find.text('✓ Revisado'), findsOneWidget);

    // The dialog previews the single message.
    await tester.tap(find.byKey(const ValueKey('review-request-changes')));
    await tester.pump();
    final preview = tester.widget<SelectableText>(
      find.byKey(const ValueKey('review-adjust-preview')),
    );
    expect(
      preview.data,
      contains('lib/ui/status_bar.dart:8 — Use o tema do app.'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('one file / every file, unified / side by side', (tester) async {
    await pumpReview(tester, size: const Size(1044, 628));
    expect(find.byKey(const ValueKey('review-all-files')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('review-view-split')));
    await tester.pump();
    // Old lines on the left half, new ones on the right half.
    final old = tester.getTopLeft(find.byKey(const ValueKey('review-line-o7')));
    final now = tester.getTopLeft(find.byKey(const ValueKey('review-line-8')));
    expect(now.dx, greaterThan(old.dx + 200));
    await tester.tap(find.byKey(const ValueKey('review-view-one')));
    await tester.pump();
    expect(find.byKey(const ValueKey('review-all-files')), findsNothing);
    expect(find.byKey(const ValueKey('review-file-title')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the host band names the provider and its state; GitLab says '
      'MR and another host suggests no CLI', (tester) async {
    await pumpReview(
      tester,
      pr: const PrAvailability(
        available: false,
        host: 'gitlab',
        hostname: 'gitlab.com',
        remote: 'origin',
        reason: 'Integração de MR ainda indisponível (DT-55).',
      ),
    );
    String band() =>
        tester.widget<Text>(find.byKey(const ValueKey('review-host'))).data!;
    expect(
      band(),
      'GitLab · glab · gitlab.com · origin · '
      'Integração de MR ainda indisponível (DT-55).',
    );
    expect(find.text('Criar MR'), findsOneWidget);
    expect(
      tester
          .widget<Tooltip>(
            find.ancestor(
              of: find.byKey(const ValueKey('review-create-pr-draft')),
              matching: find.byType(Tooltip),
            ),
          )
          .message,
      contains('glab mr create'),
    );
    await tester.pumpWidget(const SizedBox());

    await pumpReview(
      tester,
      pr: const PrAvailability(
        available: false,
        host: 'unknown',
        hostname: 'bitbucket.org',
        remote: 'origin',
        reason: 'Integração com bitbucket.org ainda não disponível.',
      ),
    );
    expect(band(), startsWith('Hospedagem não identificada · bitbucket.org'));
    expect(find.text('Criar PR'), findsOneWidget);
    final draft = tester
        .widget<Tooltip>(
          find.ancestor(
            of: find.byKey(const ValueKey('review-create-pr-draft')),
            matching: find.byType(Tooltip),
          ),
        )
        .message!;
    expect(draft.contains('gh ') || draft.contains('glab'), isFalse);
    expect(band().contains('gh') || band().contains('glab'), isFalse);
    expect(tester.takeException(), isNull);
  });

  group('SPEC-011 · pronto para merge', () {
    String summary(WidgetTester t) => t
        .widget<Text>(find.byKey(const ValueKey('review-readiness-summary')))
        .data!;
    bool enabled(WidgetTester t, String key) =>
        t
            .widget<InkWell>(
              find.descendant(
                of: find.byKey(ValueKey(key)),
                matching: find.byType(InkWell),
              ),
            )
            .onTap !=
        null;

    testWidgets('the header shows ready, warnings or blocked with the count; '
        'the selected queue item shows the matching dot', (tester) async {
      await pumpReview(
        tester,
        readiness: evaluateReadiness(const ReadinessInputs()),
      );
      expect(summary(tester), 'Pronto para merge');
      final dot = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey('review-item-s1')),
          matching: find.byType(Icon),
        ),
      );
      expect(dot.icon, Icons.circle);
      final other = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey('review-item-s2')),
          matching: find.byType(Icon),
        ),
      );
      expect(other.icon, Icons.circle_outlined); // partial, never green
      await tester.pumpWidget(const SizedBox());

      await pumpReview(
        tester,
        readiness: evaluateReadiness(
          const ReadinessInputs(prProblem: 'check pendente', uncommitted: 2),
        ),
      );
      expect(summary(tester), 'Com avisos · 2');
      await tester.pumpWidget(const SizedBox());

      await pumpReview(
        tester,
        readiness: evaluateReadiness(
          const ReadinessInputs(rootProblem: 'raiz fora da main'),
        ),
      );
      expect(summary(tester), 'Bloqueado · 1 bloqueios · 0 avisos');
      await tester.tap(find.byKey(const ValueKey('review-readiness')));
      await tester.pumpAndSettle();
      for (final id in ['pr', 'empilhada', 'raiz', 'worktree']) {
        expect(find.byKey(ValueKey('review-readiness-$id')), findsOneWidget);
      }
    });

    testWidgets('with a blocker "Fazer merge" is disabled and its tooltip '
        'lists the blockers; with warnings the dialog lists them', (
      tester,
    ) async {
      await pumpReview(
        tester,
        readiness: evaluateReadiness(
          const ReadinessInputs(rootProblem: 'raiz fora da main'),
        ),
      );
      expect(enabled(tester, 'review-merge'), isFalse);
      final tip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.byKey(const ValueKey('review-merge')),
          matching: find.byType(Tooltip),
        ),
      );
      expect(tip.message, contains('raiz fora da main'));
      await tester.pumpWidget(const SizedBox());

      await pumpReview(
        tester,
        readiness: evaluateReadiness(
          const ReadinessInputs(prProblem: 'check lint falhando'),
        ),
      );
      expect(enabled(tester, 'review-merge'), isTrue);
      await tester.tap(find.byKey(const ValueKey('review-merge')));
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      // The merge dialog lists the warnings before confirming.
      expect(find.textContaining('check lint falhando'), findsOneWidget);
    });

    testWidgets('criteria as the only service blocker enable "Mergear mesmo '
        'assim…"; with another blocker both stay disabled', (tester) async {
      await pumpReview(
        tester,
        readiness: evaluateReadiness(
          const ReadinessInputs(hasSpec: true, pendingCriteria: ['R1 ok']),
        ),
      );
      expect(enabled(tester, 'review-merge'), isFalse);
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('review-merge-override')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());

      await pumpReview(
        tester,
        readiness: evaluateReadiness(
          const ReadinessInputs(
            hasSpec: true,
            pendingCriteria: ['R1 ok'],
            stackedOn: 'SPEC-001',
          ),
        ),
      );
      expect(enabled(tester, 'review-merge'), isFalse);
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('review-merge-override')),
            )
            .onPressed,
        isNull,
      );
    });
  });
}

class _NoConflictReview extends ReviewService {
  _NoConflictReview(super.ref);
  @override
  Future<ConflictPrediction> predictConflict(String sessionId) async =>
      const ConflictPrediction();
}
