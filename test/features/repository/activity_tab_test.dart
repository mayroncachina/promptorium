import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/agent_trailer.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_screen.dart'
    show boardSelectedSpecProvider;
import 'package:promptorium/features/project/project_config.dart';
import 'package:promptorium/features/repository/activity/activity_charts.dart';
import 'package:promptorium/features/repository/activity/activity_log.dart';
import 'package:promptorium/features/repository/activity/activity_stats.dart';
import 'package:promptorium/features/repository/activity/activity_tab.dart';
import 'package:promptorium/features/repository/graph/graph_tab.dart';
import 'package:promptorium/features/repository/repository_info.dart';
import 'package:promptorium/features/repository/repository_screen.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../core/git/git_test_utils.dart';
import 'activity_fixtures.dart';
import 'commit_log_test.dart' show buildHistory;
import 'graph_tab_test.dart' show specRow;

class _Settings extends AppSettingsController {
  @override
  Map<String, String> build() => {};

  @override
  Future<void> set(String key, String value) async =>
      state = {...state, key: value};
}

const _repo = RepositoryInfo(path: '/repo', defaultBranch: 'main');

/// [specHistory] plus marked commits and two tags.
ActivityLog markedLog() => logOf(
  [
    ac('n2', ['n1'], .5, 'feat: marcado', trailers: 'sonnet · SPEC-044 R1'),
    ac('n1', ['d'], .6, 'feat: do app', trailers: 'app · SPEC-044 R1'),
    ...specHistory(),
  ],
  tags: [ActivityTag('v0.1.0', daysAgo(5)), ActivityTag('v0.2.0', daysAgo(2))],
);

void main() {
  final ws = Workspace(
    id: 1,
    path: '/repo',
    name: 'repo',
    createdAt: DateTime(2026),
  );

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    Future<ActivityReports>? reports,
    ActivityLog? log,
    bool marking = true,
  }) async {
    tester.view.physicalSize = const Size(1440, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final r = reports ?? Future.value(reportsOf(log ?? markedLog()));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWith(_Settings.new),
          activeWorkspaceProvider.overrideWithValue(ws),
          activityProvider.overrideWith((ref, repo) => r),
          specsProvider.overrideWith(
            (ref, id) => Stream.value([
              specRow(1, 'SPEC-042', 'Sprints no Quadro'),
              specRow(2, 'SPEC-043', 'Conflito resolvido'),
            ]),
          ),
          sprintsProvider.overrideWith((ref, id) => Stream.value(const [])),
          projectConfigProvider.overrideWith(
            (ref, p) async =>
                ProjectConfig(git: GitConfig(markAgentCommits: marking)),
          ),
          gitVersionProvider.overrideWith(
            (ref) async => const GitVersion(2, 43),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: ActivityTab(repo: _repo)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return ProviderScope.containerOf(tester.element(find.byType(ActivityTab)));
  }

  String text(WidgetTester tester, Finder f) => tester
      .widgetList<Text>(
        find.descendant(of: f, matching: find.byType(Text), matchRoot: true),
      )
      .map((t) => t.data)
      .join(' ');

  testWidgets('R1 · a aba vem depois de Grafo; o período vale para a aba '
      'inteira e compara com o anterior', (tester) async {
    expect(repositoryTabs.map((t) => t.id), [
      'releases',
      'grafo',
      'atividade',
      'higiene',
    ]);
    expect(activityTab.label, 'Atividade');
    final container = await pump(tester);
    expect(container.read(activityPeriodProvider), ActivityPeriod.days90);
    expect(
      text(tester, find.byKey(const ValueKey('activity-caption'))),
      contains('últimos 90 dias, comparados com os 90 anteriores'),
    );
    expect(
      text(tester, find.byKey(const ValueKey('activity-summary-specs'))),
      'Specs mergeadas 2 +2',
    );
    expect(
      text(tester, find.byKey(const ValueKey('activity-summary-releases'))),
      'Releases 2 v0.1.0 a v0.2.0',
    );
    expect(
      text(tester, find.byKey(const ValueKey('activity-summary-cycle'))),
      startsWith('Ciclo mediano das specs 4,5 dias'),
    );
    await tester.tap(find.byKey(const ValueKey('activity-period-days30')));
    await tester.pump();
    expect(container.read(activityPeriodProvider), ActivityPeriod.days30);
    expect(
      text(tester, find.byKey(const ValueKey('activity-caption'))),
      contains('últimos 30 dias, comparados com os 30 anteriores'),
    );
    expect(find.text('30 dias · sem *.g.dart e pubspec.lock'), findsOneWidget);
  });

  testWidgets('R6 · esqueleto enquanto calcula', (tester) async {
    final pending = Completer<ActivityReports>();
    await pump(tester, reports: pending.future);
    expect(find.byKey(const ValueKey('activity-skeleton')), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-heatmap-card')), findsNothing);
    pending.complete(reportsOf(markedLog()));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('activity-skeleton')), findsNothing);
    expect(find.byKey(const ValueKey('activity-heatmap-card')), findsOneWidget);
  });

  testWidgets('R2 · o balão diz a data, os commits e as specs; o clique '
      'leva ao Grafo do dia', (tester) async {
    final container = await pump(tester);
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byKey(const ValueKey('activity-heatmap')),
        matching: find.byType(CustomPaint),
      ),
    );
    final painter = paint.painter! as HeatmapPainter;
    final day = dayOf(daysAgo(3));
    expect(painter.cells.firstWhere((c) => c.day == day).level, greaterThan(0));
    expect(
      painter.cells.firstWhere((c) => c.day == dayOf(daysAgo(5))).release,
      isTrue,
    );
    final origin = tester.getTopLeft(
      find.byKey(const ValueKey('activity-heatmap')),
    );
    final at = origin + painter.geometry.rectOf(day).center;

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(at);
    await tester.pump();
    expect(
      text(tester, find.byKey(const ValueKey('activity-day-balloon'))),
      allOf(contains('1 commit'), contains('SPEC-043')),
    );
    final report = reportsOf(markedLog())[ActivityPeriod.days90];
    expect(dayBalloon(report, dayOf(daysAgo(5))).last, 'Release v0.1.0');

    await tester.tapAt(at);
    await tester.pump();
    expect(container.read(graphRequestProvider)?.day, day);
    expect(container.read(repositoryTabProvider), 'grafo');
    expect(container.read(navigationProvider), AppSection.repository);
  });

  testWidgets('R3 · a legenda esconde um grupo', (tester) async {
    await pump(tester);
    StackedBarsPainter bars() =>
        tester
                .widget<CustomPaint>(
                  find.byKey(const ValueKey('activity-types-chart')),
                )
                .painter!
            as StackedBarsPainter;
    final before = bars().bars.last.length;
    await tester.tap(find.byKey(const ValueKey('activity-type-Documentação')));
    await tester.pump();
    expect(bars().bars.last.length, before - 1);
  });

  testWidgets('R4 · as mais longas abrem a spec no Quadro', (tester) async {
    final container = await pump(tester);
    expect(
      text(tester, find.byKey(const ValueKey('activity-cycle-median'))),
      '4,5 d mediana',
    );
    expect(
      text(tester, find.byKey(const ValueKey('activity-cycle-p90'))),
      '6,5 d percentil 90',
    );
    expect(
      text(tester, find.byKey(const ValueKey('activity-longest-SPEC-042'))),
      'SPEC-042 Sprints no Quadro 7,0 d',
    );
    await tester.tap(find.byKey(const ValueKey('activity-longest-SPEC-042')));
    await tester.pump();
    expect(container.read(boardSelectedSpecProvider), 1);
    expect(container.read(navigationProvider), AppSection.tasks);
  });

  testWidgets('R5 · ao abrir um arquivo, as specs e os commits, com links '
      'para o Quadro e o Grafo', (tester) async {
    final container = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('activity-file-lib/a.dart')));
    await tester.pump();
    final panel = find.byKey(const ValueKey('activity-file-panel'));
    expect(
      text(tester, panel),
      contains('2 commits · +15 −3 linhas · 2 specs em 90 dias'),
    );
    await tester.tap(find.byKey(const ValueKey('activity-file-commit-t1')));
    await tester.pump();
    expect(container.read(graphRequestProvider)?.select, 't1');
    await tester.tap(find.byKey(const ValueKey('activity-file-spec-SPEC-043')));
    await tester.pump();
    expect(container.read(boardSelectedSpecProvider), 2);
  });

  testWidgets('R7 · sem branches de spec e sem tags, a aba explica em vez '
      'de mostrar zero', (tester) async {
    await pump(
      tester,
      log: logOf([
        ac('c1', ['c0'], 1, 'feat: a'),
        ac('c0', [], 3, 'inicial'),
      ]),
    );
    expect(
      find.text('Este repositório não usa branches de spec.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('activity-no-tags')), findsOneWidget);
    expect(
      text(tester, find.byKey(const ValueKey('activity-summary-releases'))),
      'Releases — Sem tags no repositório',
    );
    expect(
      text(tester, find.byKey(const ValueKey('activity-summary-cycle'))),
      'Ciclo mediano das specs — Sem branches de spec',
    );
  });

  testWidgets('R8 · ligado: pessoa, agentes e app por modelo, com o ⓘ', (
    tester,
  ) async {
    await pump(tester);
    expect(
      text(tester, find.byKey(const ValueKey('activity-who-status'))),
      startsWith('Marcado desde'),
    );
    expect(
      text(tester, find.byKey(const ValueKey('activity-who-agent'))),
      'Agentes 1 50%',
    );
    expect(
      text(tester, find.byKey(const ValueKey('activity-who-app'))),
      'App 1 50%',
    );
    expect(
      text(tester, find.byKey(const ValueKey('activity-who-person'))),
      'Você 0 0%',
    );
    expect(
      text(tester, find.byKey(const ValueKey('activity-who-unmarked'))),
      startsWith('Sem marca 5 antes de'),
    );
    expect(
      text(tester, find.byKey(const ValueKey('activity-who-model-sonnet'))),
      'sonnet 1 · 100%',
    );
    final chart =
        tester
                .widget<CustomPaint>(
                  find.byKey(const ValueKey('activity-who-chart')),
                )
                .painter!
            as StackedBarsPainter;
    // The weeks before the first mark are only grey.
    final early = chart.bars.first;
    expect(
      early.where((p) => p.value > 0).map((p) => p.color),
      everyElement(OriginColors.unmarked),
    );

    await tester.ensureVisible(find.byKey(const ValueKey('activity-who-info')));
    await tester.tap(find.byKey(const ValueKey('activity-who-info')));
    await tester.pump();
    expect(find.text('De onde vem esta separação'), findsOneWidget);
    expect(
      find.text('Promptorium-Agente: sonnet · SPEC-042 R2'),
      findsOneWidget,
    );
    expect(find.textContaining('A marcação está ligada desde'), findsOneWidget);
  });

  testWidgets('R8 · desligado: o cartão explica e "Ligar neste projeto" abre '
      'a confirmação', (tester) async {
    await pump(tester, marking: false);
    expect(
      text(tester, find.byKey(const ValueKey('activity-who-status'))),
      'Marcação desligada',
    );
    expect(
      find.text('Este projeto não marca os commits dos agentes'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('activity-who-agent')), findsNothing);
    await tester.ensureVisible(
      find.byKey(const ValueKey('activity-who-enable')),
    );
    await tester.tap(find.byKey(const ValueKey('activity-who-enable')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('agent-trailer-dialog')), findsOneWidget);
  });

  test('o provedor lê o git, guarda por ponta e calcula em outro isolate '
      '(R6)', () async {
    final tmp = Directory.systemTemp.createTempSync('promptorium-activity-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = await createRepo(tmp);
    await buildHistory(repo);
    ActivityLogReader.clearMemory();
    final c = ProviderContainer(
      overrides: [activityCacheDirProvider.overrideWithValue('${tmp.path}/c')],
    );
    addTearDown(c.dispose);
    final info = RepositoryInfo(path: repo, defaultBranch: 'main');
    final sub = c.listen(activityProvider(info), (_, _) {});
    addTearDown(sub.close);
    final r = await c.read(activityProvider(info).future);
    final p = r[ActivityPeriod.days30];
    expect(p.summary.commits, 5);
    expect(p.summary.specsMerged, 1);
    expect(p.summary.releases, 1);
    expect(Directory('${tmp.path}/c').listSync(), hasLength(1));
  });
}
