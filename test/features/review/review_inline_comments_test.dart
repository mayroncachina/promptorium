import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/diff_parser.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/review/comment_anchor.dart';
import 'package:promptorium/features/review/widgets/review_diff_view.dart';
import 'package:promptorium/features/review/widgets/spec_review_panel.dart';

import '../../helpers/test_db.dart';

import 'package:promptorium/features/review/review_screen.dart';
import 'package:promptorium/features/review/review_service.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../sessions/session_test_utils.dart';
import 'review_logic_test.dart' show sampleDiff, session;
import 'review_screen_test.dart' show secondFile;

void main() {
  testWidgets(
    'reviewer card follows its new line; resolved/reopened state comes from the database',
    (tester) async {
      final db = memoryDatabase();
      await db.customStatement(
        "INSERT INTO workspaces(path,name) VALUES('/r','r')",
      );
      await db.customStatement(
        "INSERT INTO specs(workspace_id,code,title,path) VALUES(1,'SPEC-001','a','specs/a.md')",
      );
      await db
          .into(db.reviewComments)
          .insert(
            ReviewCommentsCompanion.insert(
              specId: 1,
              round: 2,
              author: 'revisor',
              body: 'corrigir erro',
              path: const Value('a.dart'),
              line: const Value(12),
              severity: const Value('alta'),
              requirement: const Value('R1'),
            ),
          );
      final file = DiffParser.parse('''diff --git a/a.dart b/a.dart
--- a/a.dart
+++ b/a.dart
@@ -12 +12 @@
-old
+new
''').single;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseOverride(db)],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  final rows =
                      ref.watch(reviewCommentsProvider(1)).value ??
                      <ReviewCommentRow>[];
                  return ReviewFileDiff(
                    file: file,
                    comments: const [],
                    accepted: const {},
                    persisted: [
                      for (final row in rows) anchorOf(row, file, {}),
                    ],
                    commentTarget: null,
                    onOpenComment: (_) {},
                    onCancelComment: () {},
                    onSubmitComment: (_, _) {},
                    onRemoveComment: (_) {},
                    onRejectHunk: (_) {},
                    onToggleAccept: (_) {},
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('corrigir erro'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('corrigir erro')).dy,
        greaterThan(
          tester.getTopLeft(find.byKey(const ValueKey('review-line-12'))).dy,
        ),
      );
      await tester.tap(find.text('Tratado'));
      await tester.pumpAndSettle();
      expect(find.text('corrigir erro'), findsNothing);
      expect((await db.select(db.reviewComments).getSingle()).resolved, isTrue);
      await tester.tap(find.text('Reabrir'));
      await tester.pumpAndSettle();
      expect(find.text('corrigir erro'), findsOneWidget);
      expect(
        (await db.select(db.reviewComments).getSingle()).resolvedAt,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  group('Review screen', () {
    late AppDatabase db;

    Future<void> seed() async {
      db = memoryDatabase();
      await db.customStatement(
        "INSERT INTO workspaces(path,name) VALUES('/work/repo','repo')",
      );
      await db.customStatement(
        "INSERT INTO specs(workspace_id,code,title,path) "
        "VALUES(1,'SPEC-001','Barra','specs/a.md')",
      );
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: AppSettingKeys.activeWorkspace,
              value: '1',
            ),
          );
      ReviewCommentsCompanion row(
        String author,
        String body, {
        String? path,
        int? line,
        String? verdict,
        int round = 1,
      }) => ReviewCommentsCompanion.insert(
        specId: 1,
        round: round,
        author: author,
        body: body,
        path: Value(path),
        line: Value(line),
        verdict: Value(verdict),
        severity: Value(author == 'revisor' && (line ?? 0) > 0 ? 'alta' : null),
        requirement: Value(
          author == 'revisor' && (line ?? 0) > 0 ? 'R1' : null,
        ),
      );
      await db.batch(
        (b) => b.insertAll(db.reviewComments, [
          row('revisor', 'Correções pedidas.', verdict: 'corrigir'),
          row(
            'revisor',
            'Use o tema do app.',
            path: 'lib/ui/status_bar.dart',
            line: 8,
          ),
          row(
            'revisor',
            'Arquivo todo',
            path: 'lib/ui/status_bar.dart',
            line: 0,
          ),
          row('revisor', 'Comentário geral'),
          row('pr', '@ana: arquivo removido', path: 'removido.dart', line: 3),
          row('pr', '@bia: conversa geral'),
          row('humano', 'Ajustes pedidos.', verdict: 'corrigir', round: 2),
        ]),
      );
    }

    Future<ProviderContainer> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = session().copyWith(specId: const Value(1));
      final spec = (await db.select(db.specs).getSingle());
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          ...sessionOverrides(db: db, cli: FakeCli(), notifier: FakeNotifier()),
          reviewQueueProvider.overrideWith(
            (ref, id) async => [ReviewItem(session: s, spec: spec)],
          ),
          reviewDetailProvider.overrideWith(
            (ref, id) async => ReviewDetail(
              session: s,
              baseBranch: 'main',
              mergeBase: 'abc',
              files: DiffParser.parse('$sampleDiff$secondFile'),
              commitsAhead: 1,
            ),
          ),
          reviewAnchorProvider.overrideWith(
            (ref, key) async => <int, ({int? line, String? reason})>{},
          ),
          prAvailabilityProvider.overrideWith(
            (ref, id) async =>
                const PrAvailability(available: false, reason: 'sem gh'),
          ),
        ],
      );
      await c.read(appSettingsProvider.notifier).load();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: ReviewScreen()),
          ),
        ),
      );
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      return c;
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    String header(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const ValueKey('review-open-comments')))
        .data!;

    Future<void> close(WidgetTester tester, ProviderContainer c) async {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await tester.pump(Duration.zero);
    }

    testWidgets('line comments under their line, line 0 as a band on top of '
        'the file, no file in "Geral"; outdated ones in "Geral"; the header '
        'counts each open comment once and ignores verdicts and your own', (
      tester,
    ) async {
      await seed();
      final c = await pump(tester);
      expect(find.text('Revisor · rodada 1 · alta · R1'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Use o tema do app.')).dy,
        greaterThan(
          tester.getTopLeft(find.byKey(const ValueKey('review-line-8'))).dy,
        ),
      );
      expect(
        tester.getTopLeft(find.text('Arquivo todo')).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('review-line-5'))).dy,
        ),
      );
      expect(find.text('Geral'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.text('Comentário geral'),
        ),
        findsOneWidget,
      );
      expect(find.text('@ana: arquivo removido'), findsOneWidget);
      expect(find.text('PR · @ana · rodada 1'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.text('@bia: conversa geral'),
        ),
        findsOneWidget,
      );
      // Line 8, line 0, geral, PR on a gone file, PR conversation: 5.
      expect(header(tester), '5 comentários abertos');
      expect(find.text(' · 2 abertos'), findsOneWidget);
      await close(tester, c);
    });

    testWidgets('"Tratado" lowers the file and header counts, survives a new '
        'container, and "Reabrir" undoes it', (tester) async {
      await seed();
      final c = await pump(tester);
      final treat = find.descendant(
        of: find.ancestor(
          of: find.text('Use o tema do app.'),
          matching: find.byType(Card),
        ),
        matching: find.text('Tratado'),
      );
      await tester.ensureVisible(treat);
      await tester.pump();
      await tester.tap(treat);
      await settle(tester);
      expect(header(tester), '4 comentários abertos');
      expect(find.text(' · 1 abertos'), findsOneWidget);
      // "Só abertos" (default) hides it.
      expect(find.text('Use o tema do app.'), findsNothing);
      // A new provider reads the state back from the database.
      c.invalidate(reviewCommentsProvider(1));
      await settle(tester);
      expect(header(tester), '4 comentários abertos');
      await tester.tap(find.text('Só abertos'));
      await settle(tester);
      await tester.tap(find.text('Reabrir'));
      await settle(tester);
      expect(header(tester), '5 comentários abertos');
      await close(tester, c);
    });

    testWidgets('filters by state, by source and hiding them all keep the '
        'user\'s draft', (tester) async {
      await seed();
      final c = await pump(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('review-line-8')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('review-line-8')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('review-comment-field')),
        'Meu rascunho',
      );
      await tester.tap(find.byKey(const ValueKey('review-comment-submit')));
      await settle(tester);
      expect(find.text('Meu rascunho'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'revisor'));
      await settle(tester);
      expect(find.text('Use o tema do app.'), findsNothing);
      expect(find.text('@ana: arquivo removido'), findsOneWidget);
      expect(find.text('Meu rascunho'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'Comentários'));
      await settle(tester);
      expect(find.text('@ana: arquivo removido'), findsNothing);
      expect(find.text('Meu rascunho'), findsOneWidget);
      await close(tester, c);
    });
  });
}
