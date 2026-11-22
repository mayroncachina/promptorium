import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_cli.dart' show ClaudeCliInfo;
import 'package:promptorium/core/codex/codex_cli.dart';
import 'package:promptorium/core/codex/codex_quota.dart';
import 'package:promptorium/core/providers/agent_registry.dart'
    show providerFlowsProvider, ProviderFlows, AppFlow;
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/core/providers/provider_preferences.dart';
import 'package:promptorium/core/providers/quota_source.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/sessions/new_session_dialog.dart';
import 'package:promptorium/ui/shell/quota_detail.dart';
import 'package:promptorium/ui/shell/status_footer.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:promptorium/ui/theme/tokens.dart';

import '../helpers/test_db.dart';

/// Unix seconds of [t].
int _unix(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

/// The renewal of the 5 h window, today or after midnight (the CI clock is
/// UTC, so "in 2 h" can be tomorrow).
final _renewsAt = RegExp(r'renova (\S+ \d\d/\d\d )?às \d\d:\d\d');

/// A reading of the Codex like `account/rateLimits/read` (R1).
QuotaSnapshot codexReading({
  int five = 38,
  int week = 61,
  String? reached,
  String? error,
  DateTime? readAt,
}) {
  final now = DateTime.now();
  return codexSnapshotFromRead(
    {
      'rateLimits': {
        'limitId': 'codex',
        'primary': {
          'usedPercent': five,
          'windowDurationMins': 300,
          'resetsAt': _unix(now.add(const Duration(hours: 2))),
        },
        'secondary': {
          'usedPercent': week,
          'windowDurationMins': 10080,
          'resetsAt': _unix(now.add(const Duration(days: 3))),
        },
        'credits': {'hasCredits': false, 'unlimited': false, 'balance': '0'},
        'planType': 'plus',
        'rateLimitReachedType': reached,
      },
      'rateLimitsByLimitId': {
        'gpt-sol': {
          'limitId': 'gpt-sol',
          'limitName': 'gpt-6.2-sol',
          'primary': {'usedPercent': 12, 'windowDurationMins': 300},
        },
      },
      'ordinaryUsageAllowed': reached == null,
    },
    at: readAt ?? now.subtract(const Duration(minutes: 2)),
  ).copyWith(error: error, errorAt: error == null ? null : now);
}

String _claudeRate() => jsonEncode({
  'type': 'rate_limit_event',
  'rate_limit_info': {
    'status': 'allowed',
    'unifiedWindows': {
      'five_hour': {
        'utilization': 0.27,
        'resetsAt': _unix(DateTime.now().add(const Duration(hours: 3))),
      },
      'seven_day': {
        'utilization': 0.54,
        'resetsAt': _unix(DateTime.now().add(const Duration(days: 2))),
      },
    },
  },
});

Future<ProviderContainer> _container({
  required String active,
  QuotaSnapshot? codex,
  List<String>? reads,
}) async {
  final db = memoryDatabase();
  for (final (k, v) in [
    (providerPreferenceKey(null), active),
    (AppSettingKeys.lastRateLimit, _claudeRate()),
    if (codex != null)
      (AppSettingKeys.codexLastRateLimit, jsonEncode(codex.toJson())),
  ]) {
    await db
        .into(db.appSettings)
        .insert(AppSettingsCompanion.insert(key: k, value: v));
  }
  final c = ProviderContainer(
    overrides: [
      providerFlowsProvider.overrideWithValue(
        ProviderFlows.defaults.copyWith('codex', {...AppFlow.values}),
      ),
      databaseOverride(db),
      providerAvailabilityProvider.overrideWith(
        (ref, id) async => ProviderAvailability(
          ProviderStatus.ready,
          'Pronto',
          subscriptionType: id == 'claude' ? 'max' : null,
        ),
      ),
      codexCliInfoProvider.overrideWith(
        (ref) async =>
            const ClaudeCliInfo(executable: 'codex', version: '0.170.0'),
      ),
      codexQuotaReaderProvider.overrideWithValue(() async {
        reads?.add('read');
        return {
          'rateLimits': {
            'limitId': 'codex',
            'primary': {'usedPercent': 40, 'windowDurationMins': 300},
          },
        };
      }),
    ],
  );
  await c.read(appSettingsProvider.notifier).load();
  return c;
}

Future<ProviderContainer> _pumpFooter(
  WidgetTester tester, {
  required String active,
  QuotaSnapshot? codex,
  List<String>? reads,
}) async {
  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final c = await _container(active: active, codex: codex, reads: reads);
  addTearDown(c.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: Align(alignment: Alignment.bottomCenter, child: StatusFooter()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

String _tip(WidgetTester tester, String key) =>
    tester.widget<Tooltip>(find.byKey(ValueKey(key))).message!;

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

Finder _inKey(String key, Finder f) =>
    find.descendant(of: find.byKey(ValueKey(key)), matching: f);

// SPEC-097 R4–R7.
void main() {
  group('SPEC-097 · cota no rodapé', () {
    testWidgets('with the Codex active the bar shows its 5h and weekly '
        'windows (R5)', (tester) async {
      await _pumpFooter(tester, active: 'codex', codex: codexReading());
      expect(_inKey('footer-usage-5h', find.text('Uso 5h')), findsOneWidget);
      expect(_inKey('footer-usage-5h', find.text('38%')), findsOneWidget);
      expect(_inKey('footer-usage-week', find.text('Semana')), findsOneWidget);
      expect(_inKey('footer-usage-week', find.text('61%')), findsOneWidget);
      // Never the Claude reading (27% / 54%).
      expect(find.text('27%'), findsNothing);
      expect(find.text('Consumo indisponível'), findsNothing);
      expect(_tip(tester, 'footer-usage-5h'), contains('Codex'));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('with the Claude active nothing changes (R5)', (tester) async {
      await _pumpFooter(tester, active: 'claude', codex: codexReading());
      expect(_inKey('footer-usage-5h', find.text('27%')), findsOneWidget);
      expect(_inKey('footer-usage-week', find.text('54%')), findsOneWidget);
      expect(find.text('38%'), findsNothing);
      expect(
        _inKey('footer-usage-5h', find.text('· resta 73%')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a failed reading shows "cota indisponível" with the reason '
        'and the time of the old reading (R4)', (tester) async {
      // An hour ago, but never yesterday: a reading from another day shows
      // the date instead of "às HH:mm" (the CI clock is UTC, so this case
      // broke between 00:00 and 01:00).
      final now = DateTime.now();
      final hourAgo = now.subtract(const Duration(hours: 1));
      final read = hourAgo.day == now.day
          ? hourAgo
          : DateTime(now.year, now.month, now.day);
      await _pumpFooter(
        tester,
        active: 'codex',
        codex: codexReading(error: 'sem login: rode codex login', readAt: read),
      );
      expect(find.text('cota indisponível'), findsOneWidget);
      final tip = _tip(tester, 'footer-quota-unavailable');
      expect(tip, contains('sem login: rode codex login'));
      final hm =
          '${read.hour.toString().padLeft(2, '0')}:'
          '${read.minute.toString().padLeft(2, '0')}';
      expect(tip, contains('Última leitura às $hm'));
      expect(tip, contains('Uso 5h 38%'));
      expect(find.textContaining('última leitura às $hm'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a limit reached turns the bar red with the renewal and the '
        'kind in words (R7)', (tester) async {
      await _pumpFooter(
        tester,
        active: 'codex',
        codex: codexReading(five: 100, reached: 'rate_limit_reached'),
      );
      final limit = tester.widget<Text>(
        find.byKey(const ValueKey('footer-limit')),
      );
      // The 5 h window renews in 2 h: "renova às HH:mm" today, or
      // "renova dom 22/11 às HH:mm" when that crosses midnight.
      expect(limit.data, matches(_renewsAt));
      expect(limit.style?.color, AppColors.red);
      expect(_tip(tester, 'footer-usage-5h'), contains('limite do plano'));
      expect(
        _tip(tester, 'footer-usage-5h'),
        contains('não troca de provedor sozinho'),
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a click opens the detail with both providers: plan, windows, '
        'renewal, credits, other buckets and the time of the reading (R6)', (
      tester,
    ) async {
      final reads = <String>[];
      await _pumpFooter(
        tester,
        active: 'codex',
        codex: codexReading(),
        reads: reads,
      );
      await tester.tap(find.byKey(const ValueKey('footer-quota')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quota-detail')), findsOneWidget);
      expect(find.text('Cota dos planos'), findsOneWidget);
      // Claude Code.
      expect(_inKey('quota-plan-claude', find.text('Max')), findsOneWidget);
      expect(_inKey('quota-card-claude', find.text('27%')), findsOneWidget);
      expect(_inKey('quota-card-claude', find.text('54%')), findsOneWidget);
      // Codex.
      expect(
        _inKey('quota-plan-codex', find.text('ChatGPT Plus')),
        findsOneWidget,
      );
      expect(_inKey('quota-card-codex', find.text('ativo')), findsOneWidget);
      expect(_inKey('quota-card-codex', find.text('38%')), findsOneWidget);
      expect(_inKey('quota-card-codex', find.text('61%')), findsOneWidget);
      // Both windows with the renewal time: "renova às HH:mm" today or
      // "renova seg. HH:mm" another day (the 5 h one can cross midnight).
      expect(
        _inKey(
          'quota-card-codex',
          find.textContaining(RegExp(r'renova (às|\S+) \d\d:\d\d')),
        ),
        findsNWidgets(2),
      );
      expect(_text(tester, 'quota-credits-codex'), 'sem créditos extras');
      expect(
        _inKey(
          'quota-bucket-gpt-sol',
          find.text('gpt-6.2-sol · limite próprio'),
        ),
        findsOneWidget,
      );
      expect(_text(tester, 'quota-read-codex'), startsWith('lido às '));
      // "Atualizar" reads again, without a turn.
      await tester.tap(find.byKey(const ValueKey('quota-refresh-codex')));
      await tester.pumpAndSettle();
      expect(reads, ['read']);
      expect(_inKey('quota-card-codex', find.text('40%')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a provider without a reading says so (R6)', (tester) async {
      final c = await _container(active: 'claude');
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: Center(child: QuotaDetail())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quota-empty-codex')), findsOneWidget);
      expect(find.text('sem leitura ainda'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a new Codex session at the limit warns first and never '
        'switches by itself (R7)', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = await _container(
        active: 'codex',
        codex: codexReading(five: 100, reached: 'rate_limit_reached'),
      );
      addTearDown(c.dispose);
      final ws = await c
          .read(appDatabaseProvider)
          .into(c.read(appDatabaseProvider).workspaces)
          .insertReturning(WorkspacesCompanion.insert(path: '/r', name: 'r'));
      await c
          .read(appSettingsProvider.notifier)
          .set(AppSettingKeys.activeWorkspace, '${ws.id}');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: NewSessionDialog()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quota-limit-notice')), findsOneWidget);
      expect(find.text('O Codex atingiu o limite do plano'), findsOneWidget);
      expect(
        find.textContaining(
          'Janela de 5 h em 100% (limite do plano ChatGPT '
          'Plus)',
        ),
        findsOneWidget,
      );
      // The start waits for the choice; the provider stays the Codex.
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const ValueKey('new-session-provider')),
            )
            .initialValue,
        'codex',
      );
      final submit = find.byKey(const ValueKey('new-session-submit'));
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quota-limit-notice')), findsOneWidget);
      // The explicit choice of the Claude Code.
      await tester.ensureVisible(
        find.byKey(const ValueKey('quota-limit-use-claude')),
      );
      await tester.tap(find.byKey(const ValueKey('quota-limit-use-claude')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quota-limit-notice')), findsNothing);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const ValueKey('new-session-provider')),
            )
            .initialValue,
        'claude',
      );
      // The global default did not change.
      expect(c.read(activeAgentProvider), 'codex');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
    });
  });
}
