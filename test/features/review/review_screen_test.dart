import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/diff_parser.dart';
import 'package:promptorium/data/providers.dart';
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
      prAvailabilityProvider.overrideWith(
        (ref, id) async => const PrAvailability(
          available: false,
          reason: 'GitHub CLI (gh) não encontrado no PATH.',
        ),
      ),
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

    // Every file is on the page: the hunk of the first one.
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
}
