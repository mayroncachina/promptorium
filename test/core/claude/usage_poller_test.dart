import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/usage_poller.dart';
import 'package:promptorium/core/claude/usage_tracker.dart';
import 'package:promptorium/data/providers.dart';

import '../../features/sessions/session_test_utils.dart';
import '../../helpers/test_db.dart';

const usageText = '''
You are currently using your subscription to power your Claude Code usage

Current session: 79% used · resets Oct 16, 2:09pm (America/Fortaleza)
Current week (all models): 56% used · resets Oct 19, 7:59am (America/Fortaleza)

What's contributing to your limits usage?
''';

void main() {
  final now = DateTime(2026, 10, 16, 11, 40);

  test('parseUsageReset: date + time, time only, year rollover', () {
    expect(
      parseUsageReset('Oct 16, 2:09pm', now),
      DateTime(2026, 10, 16, 14, 9),
    );
    expect(
      parseUsageReset('Oct 19, 7:59am', now),
      DateTime(2026, 10, 19, 7, 59),
    );
    expect(parseUsageReset('2pm', now), DateTime(2026, 10, 16, 14));
    expect(parseUsageReset('9am', now), DateTime(2026, 10, 17, 9)); // next one
    expect(parseUsageReset('Jan 2, 3pm', now), DateTime(2027, 1, 2, 15));
    expect(parseUsageReset('12am', now), DateTime(2026, 10, 17, 0));
    expect(parseUsageReset('qualquer coisa', now), isNull);
  });

  test('parseUsageText: both windows, as a RateLimit', () {
    final r = parseUsageText(usageText, now)!;
    expect(r.fiveHourUtilization, closeTo(0.79, 1e-9));
    expect(r.sevenDayUtilization, closeTo(0.56, 1e-9));
    expect(r.fiveHourResetsAt!.toLocal(), DateTime(2026, 10, 16, 14, 9));
    expect(r.sevenDayResetsAt!.toLocal(), DateTime(2026, 10, 19, 7, 59));
    expect(r.status, 'allowed');
    expect(parseUsageText('nada aqui', now), isNull);
    expect(
      parseUsageText('Current session: 100% used · resets 2pm', now)!.status,
      'rejected',
    );
  });

  test(
    'refresh feeds the footer without a run; a failure keeps the old one',
    () async {
      var text = usageText as String?;
      final c = sessionContainer([
        ...sessionOverrides(
          db: memoryDatabase(),
          cli: FakeCli(),
          notifier: FakeNotifier(),
          worktreesBase: '/tmp/wt',
        ),
        usageRunnerProvider.overrideWithValue(() async => text),
      ]);
      addTearDown(c.dispose);
      await c.read(appSettingsProvider.notifier).load();
      final poller = c.read(usagePollerProvider);
      await poller.refresh(now: now);
      expect(
        c.read(rateLimitProvider)!.fiveHourUtilization,
        closeTo(0.79, 1e-9),
      );
      text = null;
      await poller.refresh(now: now);
      expect(
        c.read(rateLimitProvider)!.fiveHourUtilization,
        closeTo(0.79, 1e-9),
      );
    },
  );
  group('SPEC-071 R16', () {
    late Directory tmp;
    setUp(
      () => tmp = Directory.systemTemp.createTempSync('promptorium-usage-'),
    );
    tearDown(() => tmp.deleteSync(recursive: true));

    /// Fake `claude`: an executable shell script.
    String fakeClaude(String body) {
      final f = File('${tmp.path}/claude')
        ..writeAsStringSync('#!/bin/sh\n$body\n');
      Process.runSync('chmod', ['+x', f.path]);
      return f.path;
    }

    bool alive(int pid) {
      final stat = File('/proc/$pid/stat');
      if (!stat.existsSync()) return false;
      // A zombie waiting to be reaped is already dead.
      return !stat.readAsStringSync().contains(') Z ');
    }

    test('/usage que passa do limite é encerrado, com o que iniciou', () async {
      final pids = File('${tmp.path}/pids');
      final exe = fakeClaude('sleep 30 & echo "\$\$ \$!" > ${pids.path}; wait');
      final sw = Stopwatch()..start();
      final text = await runUsage(
        exe,
        timeout: const Duration(milliseconds: 300),
        killGrace: const Duration(milliseconds: 500),
      );
      sw.stop();
      expect(text, isNull);
      expect(sw.elapsed, lessThan(const Duration(seconds: 3)));
      final ids = pids.readAsStringSync().trim().split(' ').map(int.parse);
      for (var i = 0; i < 20 && ids.any(alive); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(ids.where(alive), isEmpty);
    });

    test('/usage que termina devolve o texto', () async {
      final exe = fakeClaude(
        "echo '{\"result\":\"Current session: 5% used\"}'",
      );
      expect(await runUsage(exe), 'Current session: 5% used');
    });

    test('nunca há mais de uma consulta em voo', () async {
      var calls = 0;
      final gate = Completer<String?>();
      final c = sessionContainer([
        ...sessionOverrides(
          db: memoryDatabase(),
          cli: FakeCli(),
          notifier: FakeNotifier(),
          worktreesBase: '/tmp/wt',
        ),
        usageRunnerProvider.overrideWithValue(() {
          calls++;
          return gate.future;
        }),
      ]);
      addTearDown(c.dispose);
      await c.read(appSettingsProvider.notifier).load();
      final poller = c.read(usagePollerProvider);
      final first = poller.refresh(now: now);
      await poller.refresh(now: now);
      await poller.refresh(now: now);
      expect(calls, 1);
      gate.complete(usageText);
      await first;
      await poller.refresh(now: now);
      expect(calls, 2);
    });
  });
}
