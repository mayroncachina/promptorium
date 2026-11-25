import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/features/debts/origin_debts.dart';
import 'package:promptorium/features/debts/widgets/message_debt.dart';
import 'package:promptorium/features/debts/widgets/review_comment_debt.dart';
import 'package:promptorium/features/review/comment_anchor.dart';
import 'package:promptorium/features/review/widgets/persisted_comment.dart';
import 'package:promptorium/features/sessions/timeline.dart';
import 'package:promptorium/features/sessions/widgets/timeline_view.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

/// SPEC-112 R8 (the seal and the buttons of a review comment) and R9
/// ("Virar débito" on a message of the agent).
void main() {
  group('R9 · message of the agent', () {
    const message =
        'O upload lê o arquivo inteiro na memória.\n\n'
        'Segundo parágrafo, com o detalhe.';
    final debtButton = find.byKey(const ValueKey('message-debt'));

    Future<List<MessageDebtRequest>> pump(
      WidgetTester tester, {
      bool scope = true,
    }) async {
      tester.view.physicalSize = const Size(1100, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final got = <MessageDebtRequest>[];
      final list = TimelineListView(
        items: [AssistantTextItem(message, at: DateTime.utc(2026, 11, 25, 9))],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: scope
                ? MessageDebtScope(onDebt: (_, r) => got.add(r), child: list)
                : list,
          ),
        ),
      );
      await tester.pump();
      return got;
    }

    Future<void> hover(WidgetTester tester) async {
      final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await g.addPointer(location: Offset.zero);
      addTearDown(g.removePointer);
      await g.moveTo(tester.getCenter(find.byType(SelectableRegion)));
      await tester.pump();
    }

    testWidgets('no scope, no button (compare cards, previews)', (
      tester,
    ) async {
      await pump(tester, scope: false);
      expect(debtButton, findsNothing);
    });

    testWidgets('without a selection the first paragraph fills "O quê"', (
      tester,
    ) async {
      final got = await pump(tester);
      await hover(tester);
      expect(
        tester
            .widget<Opacity>(
              find.ancestor(of: debtButton, matching: find.byType(Opacity)),
            )
            .opacity,
        1,
      );
      await tester.tap(debtButton);
      await tester.pump();
      expect(got, hasLength(1));
      expect(got.single.selection, isNull);
      expect(got.single.excerpt, 'O upload lê o arquivo inteiro na memória.');
      expect(got.single.messageId, '2026-11-25T09:00:00.000Z');
      final d = messageDebtDraft(
        got.single.message,
        selection: got.single.selection,
        origin: 'sessão x',
      );
      expect(d.title, 'O upload lê o arquivo inteiro na memória');
    });

    testWidgets('the selected excerpt fills "O quê"', (tester) async {
      final got = await pump(tester);
      await hover(tester);
      // Selects the second paragraph by dragging over it.
      final second = find.textContaining(
        'Segundo parágrafo',
        findRichText: true,
      );
      final box = tester.getRect(second);
      final drag = await tester.startGesture(
        box.centerLeft + const Offset(1, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await drag.moveTo(box.centerRight - const Offset(1, 0));
      await tester.pump();
      await drag.up();
      await tester.pump();
      await tester.tap(debtButton);
      await tester.pump();
      expect(got, hasLength(1));
      expect(got.single.selection, contains('Segundo parágrafo'));
      expect(got.single.excerpt, startsWith('Segundo parágrafo'));
      expect(got.single.excerpt, isNot(contains('upload')));
    });
  });

  group('R8 · review comment', () {
    final spec = Spec(
      issueCommentPending: false,
      hasPlan: false,
      inTray: false,
      kind: SpecKind.spec,
      id: 1,
      workspaceId: 1,
      code: 'SPEC-033',
      title: 'Limite',
      status: SpecStatus.approved,
      path: 'specs/33.md',
      stage: SpecStage.review,
      requirements: const [],
      dependsOn: const [],
      autoAdvance: true,
      reviewRounds: 0,
      gateResends: 0,
      rejectedHunks: 0,
      worktreePath: '/wt',
    );
    ReviewCommentRow row(int id, String body) => ReviewCommentRow(
      id: id,
      specId: 1,
      round: 1,
      author: 'revisor',
      path: 'a.py',
      line: 42,
      body: body,
      resolved: id == 1,
      createdAt: DateTime(2026, 11, 25),
    );

    Future<void> pump(
      WidgetTester tester, {
      bool scope = true,
      bool merged = false,
    }) async {
      final comments = [
        PersistedComment(comment: AnchoredComment(row(1, 'lê tudo'))),
        PersistedComment(comment: AnchoredComment(row(2, 'sem handler'))),
      ];
      final body = Column(children: comments);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            reviewCommentDebtCodesProvider.overrideWith(
              (ref) => Stream.value({1: 'DT-12'}),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: scope
                  ? ReviewDebtScope(
                      spec: spec,
                      workspaceId: 1,
                      merged: merged,
                      child: body,
                    )
                  : body,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('the comment that became a debt shows "→ DT-12" and '
        'Desfazer; the open one offers "Virar débito"', (tester) async {
      await pump(tester);
      final seal = find.byKey(const ValueKey('review-comment-debt-seal-1'));
      expect(seal, findsOneWidget);
      expect(
        find.descendant(of: seal, matching: find.text('→ DT-12')),
        findsOneWidget,
      );
      expect(
        find.text('Virou débito · não conta mais como aberto'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('review-comment-debt-undo-1')),
        findsOneWidget,
      );
      // No "Reabrir" on it: the way back is Desfazer.
      expect(find.text('Reabrir'), findsNothing);
      expect(
        find.byKey(const ValueKey('review-comment-debt-2')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('review-comment-debt-1')), findsNothing);
    });

    testWidgets('after the merge there is no Desfazer', (tester) async {
      await pump(tester, merged: true);
      expect(
        find.byKey(const ValueKey('review-comment-debt-seal-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('review-comment-debt-undo-1')),
        findsNothing,
      );
    });

    testWidgets('without a spec (a PR brought in) nothing changes', (
      tester,
    ) async {
      await pump(tester, scope: false);
      expect(
        find.byKey(const ValueKey('review-comment-debt-seal-1')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('review-comment-debt-2')), findsNothing);
      expect(find.text('Reabrir'), findsOneWidget);
    });
  });
}
