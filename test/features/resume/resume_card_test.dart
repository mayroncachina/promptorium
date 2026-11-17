import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/activities/activity.dart';
import 'package:promptorium/features/board/board_screen.dart';
import 'package:promptorium/features/resume/activity_journal.dart';
import 'package:promptorium/features/resume/presence.dart' show AwaySpan;
import 'package:promptorium/features/resume/resume_state.dart';
import 'package:promptorium/features/resume/resume_summary.dart';
import 'package:promptorium/features/resume/widgets/resume_card.dart';
import 'package:promptorium/features/resume/widgets/resume_host.dart';
import 'package:promptorium/features/resume/widgets/since_last_visit.dart';
import 'package:promptorium/ui/shell/command_palette.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';
import '../activities/activities_screen_test.dart' show pumpScreen;
import '../board/board_screen_test.dart' show pumpBoard;

final now = DateTime.now();

ResumeItem item(
  String key,
  ResumeGroup g, {
  ResumeAction action = ResumeAction.open,
  String title = 'SPEC-077 · Copiar código',
  String line = 'passou no gate',
  JournalOutcome? mark,
  Activity? activity,
}) => ResumeItem(
  key: key,
  group: g,
  workspaceId: 1,
  tag: 'SPEC',
  title: title,
  line: line,
  action: action,
  seed: 'spec:1:$key',
  mark: mark ?? (g == ResumeGroup.finished ? JournalOutcome.ok : null),
  at: now.subtract(const Duration(minutes: 30)),
  activity: activity,
);

ResumeSummary summary({int waiting = 1, int finished = 2, int running = 1}) =>
    ResumeSummary(
      waiting: [
        for (var i = 0; i < waiting; i++)
          item(
            'w$i',
            ResumeGroup.waiting,
            action: ResumeAction.respond,
            title: 'SPEC-078 · Snippets $i',
            line: 'quer executar flutter test',
            mark: JournalOutcome.attention,
          ),
      ],
      finished: [
        for (var i = 0; i < finished; i++)
          item(
            'f$i',
            ResumeGroup.finished,
            action: ResumeAction.review,
            title: 'SPEC-07$i · Feita',
          ),
      ],
      running: [
        for (var i = 0; i < running; i++)
          item('r$i', ResumeGroup.running, title: 'SPEC-079 · Comparar'),
      ],
      autopilot: const ['Autopilot: 1 spec na fila'],
    );

Future<ProviderContainer> pumpOverlay(
  WidgetTester tester,
  ResumeSummary s, {
  Widget? extra,
}) async {
  tester.view.physicalSize = const Size(1366, 768);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseOverride(memoryDatabase()),
        resumeSummaryForProvider.overrideWith(
          (ref, since) => (summary: s, loading: false),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(1366, 768),
            disableAnimations: true,
          ),
          child: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: Column(
                    children: [
                      TextButton(
                        key: const ValueKey('behind'),
                        onPressed: () {},
                        child: const Text('Quadro'),
                      ),
                      ?extra,
                    ],
                  ),
                ),
                const Positioned.fill(child: ResumeOverlay()),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return ProviderScope.containerOf(tester.element(find.byType(ResumeOverlay)));
}

AwaySpan span(Duration d) => (since: now.subtract(d), away: d);

void main() {
  testWidgets('opening: the large card, not modal, focus on the first item '
      '(R10)', (tester) async {
    final c = await pumpOverlay(tester, summary());
    c.read(resumeProvider.notifier).showOpen(span(const Duration(hours: 13)));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('resume-card')), findsOneWidget);
    expect(find.text('Enquanto você esteve fora'), findsOneWidget);
    final header = tester.widget<Text>(
      find.byKey(const ValueKey('resume-header')),
    );
    expect(header.data, contains('13 h'));
    expect(header.data, contains('1 espera por você'));
    expect(header.data, contains('2 terminaram'));
    expect(header.data, contains('1 rodando'));
    expect(find.text('ESPERA POR VOCÊ'), findsOneWidget);
    expect(find.text('TERMINOU ENQUANTO VOCÊ ESTAVA FORA'), findsOneWidget);
    expect(find.text('CONTINUA RODANDO'), findsOneWidget);
    expect(find.text('Autopilot: 1 spec na fila'), findsOneWidget);
    // The first item is selected: its action is the amber one.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('resume-item-w0')),
        matching: find.text('Responder'),
      ),
      findsOneWidget,
    );
    // Not modal: what is behind takes the tap.
    await tester.tap(find.byKey(const ValueKey('behind')));
    await tester.pump();
    expect(c.read(resumeProvider).mode, ResumeMode.large);
  });

  testWidgets('Esc closes and leaves the band; Tudo visto marks the journal '
      '(R10, R12)', (tester) async {
    final c = await pumpOverlay(
      tester,
      summary(),
      extra: const SinceLastVisit(),
    );
    c.read(resumeProvider.notifier).showOpen(span(const Duration(hours: 2)));
    await tester.pump();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(c.read(resumeProvider).mode, ResumeMode.hidden);
    expect(
      c.read(appSettingsProvider)[AppSettingKeys.resumeBandSince],
      isNotNull,
    );
    // The band on the Início with what was not resolved.
    expect(find.byKey(const ValueKey('since-last-visit')), findsOneWidget);
    expect(find.text('Desde a sua última visita'), findsOneWidget);
    // The waiting item without an activity and the finished ones.
    expect(find.byKey(const ValueKey('resume-item-f0')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('since-last-visit-seen')));
    await tester.pump();
    final s = c.read(appSettingsProvider);
    expect(s[AppSettingKeys.resumeBandSince], isNull);
    expect(s[AppSettingKeys.resumeSeenUntil], isNotNull);
    expect(find.byKey(const ValueKey('since-last-visit')), findsNothing);

    c.read(resumeProvider.notifier).showOpen(span(const Duration(hours: 2)));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('resume-all-seen')));
    await tester.pump();
    expect(c.read(resumeProvider).mode, ResumeMode.hidden);
    expect(c.read(appSettingsProvider)[AppSettingKeys.resumeBandSince], isNull);
  });

  testWidgets('↑/↓ move the selection (R15)', (tester) async {
    final c = await pumpOverlay(tester, summary());
    c.read(resumeProvider.notifier).showOpen(span(const Duration(hours: 1)));
    await tester.pump();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('resume-item-f0')),
        matching: find.byType(FilledButton),
      ),
      findsNothing,
    );
    final sem = tester.getSemantics(
      find.byKey(const ValueKey('resume-item-f0')),
    );
    expect(sem, isNotNull);
  });

  testWidgets('more than 6: "+ N em Terminou" opens the rest', (tester) async {
    final c = await pumpOverlay(tester, summary(finished: 10));
    c.read(resumeProvider.notifier).showOpen(span(const Duration(hours: 1)));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('resume-item-f5')), findsOneWidget);
    expect(find.byKey(const ValueKey('resume-item-f6')), findsNothing);
    expect(find.text('+ 4 em Terminou'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('resume-more-finished')));
    await tester.pump();
    await tester.drag(
      find.byKey(const ValueKey('resume-item-f5')),
      const Offset(0, -400),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('resume-item-f9')), findsOneWidget);
  });

  testWidgets('back: the compact card; it leaves by itself only with nothing '
      'waiting (R11)', (tester) async {
    final c = await pumpOverlay(tester, summary(waiting: 0));
    c.read(resumeProvider.notifier).showBack(span(const Duration(minutes: 47)));
    await tester.pump();
    expect(find.byKey(const ValueKey('resume-compact')), findsOneWidget);
    expect(find.text('Voltou? Em 47 min:'), findsOneWidget);
    expect(find.text('✓ 2 terminaram'), findsOneWidget);
    await tester.pump(compactTimeout + const Duration(seconds: 1));
    expect(c.read(resumeProvider).mode, ResumeMode.hidden);
  });

  testWidgets('back with something waiting stays; Ver expands (R11)', (
    tester,
  ) async {
    final c = await pumpOverlay(tester, summary());
    c.read(resumeProvider.notifier).showBack(span(const Duration(minutes: 47)));
    await tester.pump();
    expect(find.text('! 1 espera por você'), findsOneWidget);
    await tester.pump(compactTimeout + const Duration(seconds: 5));
    expect(c.read(resumeProvider).mode, ResumeMode.compact);
    await tester.tap(find.byKey(const ValueKey('resume-compact-view')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('resume-card')), findsOneWidget);
  });

  testWidgets('nothing to say: a silent return (R2)', (tester) async {
    final c = await pumpOverlay(tester, const ResumeSummary());
    c.read(resumeProvider.notifier).showBack(span(const Duration(hours: 1)));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('resume-compact')), findsNothing);
    expect(c.read(resumeProvider).mode, ResumeMode.hidden);
    // Without a band either.
    expect(c.read(appSettingsProvider)[AppSettingKeys.resumeBandSince], isNull);
  });

  testWidgets('GitHub not reachable: the line and "Tentar de novo" (R7)', (
    tester,
  ) async {
    final c = await pumpOverlay(tester, summary());
    c.read(resumeProvider.notifier)
      ..setGithub(checking: false, failed: true)
      ..showOpen(span(const Duration(hours: 3)));
    await tester.pump();
    await tester.pump();
    expect(find.text('Não deu para conferir o GitHub agora.'), findsOneWidget);
    expect(find.byKey(const ValueKey('resume-github-retry')), findsOneWidget);
  });

  testWidgets('"O que aconteceu" on the Atividades opens the card of the '
      'last 24 h (R13)', (tester) async {
    final c = await pumpScreen(tester, items: const []);
    await tester.tap(find.byKey(const ValueKey('activities-what-happened')));
    await tester.pump();
    final st = c.read(resumeProvider);
    expect(st.mode, ResumeMode.large);
    expect(st.origin, ResumeOrigin.manual);
    expect(
      DateTime.now().difference(st.since!).inHours,
      inInclusiveRange(23, 24),
    );
  });

  testWidgets('the palette has "Retomar de onde parei" (R13)', (tester) async {
    final (c, _) = await pumpBoard(tester);
    final element = tester.element(find.byType(BoardScreen));
    final commands = paletteCommands(
      element,
      element as WidgetRef,
      onNavigate: (s) => c.read(navigationProvider.notifier).go(s),
    );
    commands.firstWhere((x) => x.label == 'Retomar de onde parei').run();
    expect(c.read(resumeProvider).mode, ResumeMode.large);
    expect(c.read(resumeProvider).origin, ResumeOrigin.manual);
  });
}
