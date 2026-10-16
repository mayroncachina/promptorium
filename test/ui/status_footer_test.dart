import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/ui/shell/footer_stats.dart';
import 'package:promptorium/ui/shell/status_footer.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

class _FixedFooter extends FooterStatsController {
  _FixedFooter(this.stats);

  final FooterStats stats;

  @override
  FooterStats build() => stats;
}

Future<void> _pump(WidgetTester tester, FooterStats stats) async {
  tester.view.physicalSize = const Size(1440, 200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [footerStatsProvider.overrideWith(() => _FixedFooter(stats))],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: Align(alignment: Alignment.bottomCenter, child: StatusFooter()),
        ),
      ),
    ),
  );
}

void main() {
  // Countdowns are computed when the widget builds: a margin of seconds
  // keeps the minute stable.
  DateTime inMinutes(int m) =>
      DateTime.now().add(Duration(minutes: m, seconds: 30));

  testWidgets('shows plan usage (used, left, reset) and no token counts', (
    tester,
  ) async {
    await _pump(
      tester,
      FooterStats(
        usage5h: 0.97,
        usage5hResetsAt: inMinutes(80),
        usageWeek: 0.41,
        usageWeekResetsAt: inMinutes(3 * 24 * 60 + 5 * 60),
      ),
    );
    expect(find.text('Uso 5h'), findsOneWidget);
    expect(find.text('97%'), findsOneWidget);
    expect(find.text('· resta 3%'), findsOneWidget);
    expect(find.text('· reinicia em 1h20'), findsOneWidget);
    expect(find.text('41%'), findsOneWidget);
    expect(find.text('· resta 59%'), findsOneWidget);
    expect(find.text('· reinicia em 3d05h'), findsOneWidget);
    expect(find.textContaining('Tokens'), findsNothing);
    expect(find.byKey(const ValueKey('footer-limit')), findsNothing);
  });

  testWidgets('limit reached: red notice until the reset', (tester) async {
    await _pump(
      tester,
      FooterStats(
        usage5h: 1.05,
        usage5hResetsAt: inMinutes(42),
        usageWeek: 0.42,
        limitRejected: true,
        limitResetsAt: inMinutes(42),
        limitType: 'five_hour',
      ),
    );
    expect(find.text('· limite atingido · volta em 42m'), findsOneWidget);
    expect(find.text('105%'), findsOneWidget);
    expect(find.text('· resta 58%'), findsOneWidget); // weekly window
    expect(find.textContaining('reinicia'), findsNothing);
  });

  testWidgets('a stored window that already reset shows "—"', (tester) async {
    final past = DateTime.now().subtract(const Duration(minutes: 5));
    await _pump(
      tester,
      FooterStats(
        usage5h: 1.05,
        usage5hResetsAt: past,
        usageWeek: 0.42,
        usageWeekResetsAt: inMinutes(600),
        limitRejected: true,
        limitResetsAt: past,
      ),
    );
    expect(find.byKey(const ValueKey('footer-limit')), findsNothing);
    expect(find.text('105%'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('footer-usage-5h')),
        matching: find.text('—'),
      ),
      findsOneWidget,
    );
    expect(find.text('42%'), findsOneWidget);
  });
}
