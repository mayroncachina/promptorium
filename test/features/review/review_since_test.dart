import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/diff_parser.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/review/review_screen.dart';
import 'package:promptorium/features/review/review_service.dart';
import 'package:promptorium/features/review/widgets/spec_review_panel.dart'
    show reviewCommentsProvider;
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';
import 'review_logic_test.dart' show sampleDiff, session;
import 'review_screen_test.dart' show secondFile;

/// SPEC-010: "Alterações desde…" a review round.
final _spec = Spec(
  id: 7,
  workspaceId: 1,
  code: 'SPEC-007',
  title: 'Barra de status',
  status: SpecStatus.approved,
  path: 'specs/SPEC-007.md',
  stage: SpecStage.review,
  requirements: const [],
  dependsOn: const [],
  autoAdvance: false,
  reviewRounds: 5,
  gateResends: 0,
  rejectedHunks: 0,
);

ReviewCommentRow _row(
  int id,
  int round,
  String author, {
  String? verdict,
  String? sha,
  String body = 'resumo',
  String? path,
  int? line,
  bool resolved = false,
}) => ReviewCommentRow(
  id: id,
  specId: 7,
  round: round,
  author: author,
  body: body,
  path: path,
  line: line,
  verdict: verdict,
  commitSha: sha,
  resolved: resolved,
  createdAt: DateTime(2026, 10, 21, 14, round),
);

final _rows = [
  _row(1, 1, 'revisor', verdict: 'Aprovado', sha: 'same'),
  _row(
    2,
    2,
    'revisor',
    verdict: 'Correções pedidas',
    sha: 'aaa',
    body: 'Use o tema do app.',
    path: 'lib/ui/status_bar.dart',
    line: 8,
    resolved: true,
  ),
  _row(3, 3, 'humano', sha: 'bbb', body: 'Ajustes pedidos.'),
  _row(4, 4, 'pr'),
  _row(5, 5, 'revisor', verdict: 'Aprovado', sha: 'gone'),
];

Future<void> pumpFor(WidgetTester tester, [int times = 10]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<ProviderContainer> pumpSince(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1600, 1000);
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
  final s = session();
  final c = ProviderContainer(
    // Providers this screen doesn't need here may fail (no repository);
    // no retry timer may outlive the test.
    retry: (_, _) => null,
    overrides: [
      ...sessionOverrides(db: db, cli: FakeCli(), notifier: FakeNotifier()),
      reviewQueueProvider.overrideWith(
        (ref, id) async => [ReviewItem(session: s, spec: _spec)],
      ),
      reviewDetailProvider.overrideWith(
        (ref, id) async => ReviewDetail(
          session: s,
          baseBranch: 'main',
          mergeBase: 'abc',
          files: DiffParser.parse('$sampleDiff$secondFile'),
          commitsAhead: 4,
        ),
      ),
      reviewCommentsProvider.overrideWith((ref, id) => Stream.value(_rows)),
      reviewAnchorProvider.overrideWith(
        (ref, key) async => <int, ({int? line, String? reason})>{},
      ),
      reviewRoundAvailabilityProvider.overrideWith(
        (ref, key) async => switch (key.$2) {
          null => 'esta rodada não registrou o commit revisado',
          'gone' => 'o commit da rodada não existe mais nesta branch',
          _ => null,
        },
      ),
      reviewSinceProvider.overrideWith(
        (ref, key) async => key.$2 == 'same'
            ? ReviewDetail(session: s)
            : ReviewDetail(
                session: s,
                files: DiffParser.parse(sampleDiff),
                uncommitted: 1,
              ),
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
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.pump(Duration.zero);
  });
  await pumpFor(tester, 15);
  return c;
}

Finder byKey(String k) => find.byKey(ValueKey(k));

DropdownMenuItem<int> item(WidgetTester tester, int round) => tester
    .widgetList<DropdownMenuItem<int>>(find.byType(DropdownMenuItem<int>))
    .firstWhere((i) => i.value == round);

Future<void> choose(WidgetTester tester, int round) async {
  await tester.tap(byKey('review-since-filter'));
  await pumpFor(tester);
  await tester.tap(find.textContaining('Rodada $round ·').last);
  await pumpFor(tester, 15);
}

void main() {
  testWidgets('the filter lists every round with author, verdict and date; '
      'rounds without verdict say so; "Desde a última rodada" picks the most '
      'recent available one', (tester) async {
    await pumpSince(tester);
    await tester.tap(byKey('review-since-filter'));
    await pumpFor(tester);
    expect(
      find.text('Rodada 2 · revisor · Correções pedidas · 21/10 14:02'),
      findsWidgets,
    );
    expect(
      find.text('Rodada 3 · humano · sem veredito · 21/10 14:03'),
      findsWidgets,
    );
    expect(
      find.text('Rodada 4 · pr · sem veredito · 21/10 14:04'),
      findsWidgets,
    );
    await tester.tapAt(const Offset(5, 5));
    await pumpFor(tester);

    await tester.tap(byKey('review-since-latest'));
    await pumpFor(tester, 15);
    expect(
      tester.widget<Text>(byKey('review-since-header')).data,
      '0 commits · 1 arquivo desde a rodada 3',
    );
  });

  testWidgets('a PR round and a round whose commit left the branch are '
      'disabled, each with its own reason', (tester) async {
    await pumpSince(tester);
    await tester.tap(byKey('review-since-filter'));
    await pumpFor(tester);
    expect(item(tester, 4).enabled, false);
    expect(item(tester, 5).enabled, false);
    expect(item(tester, 3).enabled, true);
    String reason(int round) => tester
        .widget<Tooltip>(
          find.ancestor(
            of: find.textContaining('Rodada $round ·').last,
            matching: find.byType(Tooltip),
          ),
        )
        .message!;
    expect(reason(4), 'esta rodada não registrou o commit revisado');
    expect(reason(5), 'o commit da rodada não existe mais nesta branch');
  });

  testWidgets('the header counts commits and files; unchanged files are '
      'marked; view controls apply and hunk actions are disabled', (
    tester,
  ) async {
    await pumpSince(tester);
    await choose(tester, 3);
    expect(
      tester.widget<Text>(byKey('review-since-header')).data,
      '0 commits · 1 arquivo desde a rodada 3',
    );
    expect(find.text('sem alterações'), findsOneWidget);
    expect(byKey('review-accept-0'), findsNothing);
    await tester.tap(byKey('review-view-split'));
    await pumpFor(tester);
    final old = tester.getTopLeft(byKey('review-line-o7'));
    final now = tester.getTopLeft(byKey('review-line-8'));
    expect(now.dx, greaterThan(old.dx + 200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('with nothing new the screen says "Nada mudou desde a rodada '
      'N"', (tester) async {
    await pumpSince(tester);
    await choose(tester, 1);
    expect(find.text('Nada mudou desde a rodada 1'), findsOneWidget);
  });

  testWidgets('the comments of the chosen round show over the diff with '
      'their current state, treated ones included', (tester) async {
    await pumpSince(tester);
    await choose(tester, 2);
    expect(find.text('Revisor · rodada 2'), findsOneWidget);
    expect(
      find.textContaining('Use o tema do app.', findRichText: true),
      findsWidgets,
    );
    expect(find.text('Reabrir'), findsOneWidget); // already treated
    expect(
      find.textContaining('Ajustes pedidos.', findRichText: true),
      findsNothing,
    ); // other round
  });

  test('header singular and plural', () {
    expect(sinceHeader(1, 1, 2), '1 commit · 1 arquivo desde a rodada 2');
    expect(sinceHeader(3, 2, 2), '3 commits · 2 arquivos desde a rodada 2');
    expect(roundDate(DateTime(2026, 1, 2, 3, 4)), '02/01 03:04');
  });
}
