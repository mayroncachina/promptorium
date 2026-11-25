import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_cli.dart' show ClaudeCliInfo;
import 'package:promptorium/core/codex/codex_cli.dart';
import 'package:promptorium/core/codex/codex_quota.dart';
import 'package:promptorium/core/codex/codex_rpc.dart';
import 'package:promptorium/core/providers/agent_provider.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/core/providers/provider_preferences.dart';
import 'package:promptorium/core/providers/quota_source.dart';
import 'package:promptorium/data/providers.dart';

import '../../helpers/test_db.dart';
import 'codex_replay.dart' show codexFixtures;
import 'fake_codex.dart';

/// The recorded answer of `account/rateLimits/read` (handshake.jsonl).
Map<String, dynamic> recordedRead() {
  final t = readCodexTranscript('$codexFixtures/handshake.jsonl');
  final id = t
      .firstWhere(
        (l) => l.dir == 'send' && l.msg['method'] == 'account/rateLimits/read',
      )
      .msg['id'];
  return t
          .firstWhere(
            (l) =>
                l.dir == 'recv' && l.msg['method'] == null && l.msg['id'] == id,
          )
          .msg['result']
      as Map<String, dynamic>;
}

/// The recorded `account/rateLimits/updated` params (leitura.jsonl).
Map<String, dynamic> recordedUpdate() =>
    readCodexTranscript('$codexFixtures/leitura.jsonl')
            .firstWhere((l) => l.msg['method'] == 'account/rateLimits/updated')
            .msg['params']
        as Map<String, dynamic>;

void main() {
  setUp(CodexRpc.live.clear);

  group('reading (R1)', () {
    test(
      'a short-lived App Server reads the quota without thread or turn',
      () async {
        final fake = FakeCodex.replay(
          readCodexTranscript('$codexFixtures/handshake.jsonl'),
        );
        final result = await readCodexRateLimits(
          executable: 'codex',
          starter: (exe, args, {workingDirectory, environment}) async {
            expect(args, ['app-server']);
            return fake;
          },
        );
        final methods = [for (final m in fake.writtenAll) m['method']];
        expect(methods, [
          'initialize',
          'initialized',
          'account/rateLimits/read',
        ]);
        expect(methods, isNot(contains('thread/start')));
        expect(methods, isNot(contains('turn/start')));
        expect(fake.unmatched, isEmpty);
        final s = codexSnapshotFromRead(result);
        expect(s.main.plan, 'plus');
        expect(s.window(300)?.usedPercent, 0);
        expect(s.window(10080)?.usedPercent, 15);
        expect(s.main.credits?.hasCredits, isFalse);
        expect(s.ordinaryUsageAllowed, isTrue);
        expect(s.via, QuotaVia.read);
        // The process ended: no connection is left open.
        expect(CodexRpc.live, isEmpty);
      },
    );

    test('a live connection answers instead of a new process', () async {
      final fake = FakeCodex.replay(
        readCodexTranscript('$codexFixtures/handshake.jsonl'),
      );
      final rpc = CodexRpc(fake);
      await rpc.request('initialize', {});
      expect(CodexRpc.live, contains(rpc));
      expect(CodexRpc.runAlive, isTrue);
      final result = await readCodexRateLimits(
        executable: 'codex',
        starter: (exe, args, {workingDirectory, environment}) =>
            throw StateError('não deveria abrir um processo'),
      );
      expect(result['rateLimits'], isA<Map>());
      await rpc.stop(timeout: const Duration(milliseconds: 50));
      expect(CodexRpc.live, isEmpty);
    });

    test(
      'the bucket shown is `codex`; the others are listed apart (R5, R6)',
      () {
        final s = codexSnapshotFromRead({
          'rateLimits': {
            'limitId': 'outro',
            'primary': {'usedPercent': 90, 'windowDurationMins': 300},
          },
          'rateLimitsByLimitId': {
            'codex': {
              'limitId': 'codex',
              'primary': {'usedPercent': 38, 'windowDurationMins': 300},
              'secondary': {'usedPercent': 61, 'windowDurationMins': 10080},
              'planType': 'pro',
            },
            'gpt-sol': {
              'limitId': 'gpt-sol',
              'limitName': 'gpt-6.2-sol',
              'primary': {'usedPercent': 12, 'windowDurationMins': 300},
            },
          },
          'ordinaryUsageAllowed': null,
        });
        expect(s.main.id, 'codex');
        expect(s.window(300)?.usedPercent, 38);
        expect(quotaPlanName(s.main.plan), 'ChatGPT Pro');
        expect([for (final o in s.others) o.label], ['gpt-6.2-sol']);
        expect(s.ordinaryUsageAllowed, isNull);
      },
    );

    test('failures say why in words (R4)', () {
      expect(
        codexQuotaFailure(const ProcessException('codex', [])),
        'Codex CLI não encontrado',
      );
      expect(codexQuotaFailure(TimeoutException('x')), 'o Codex não respondeu');
      expect(
        codexQuotaFailure(
          const AgentUnavailable('Codex: {message: authentication required}'),
        ),
        'sem login: rode codex login',
      );
      expect(
        codexQuotaFailure(const AgentUnavailable('Codex: network error')),
        'sem rede',
      );
      expect(codexQuotaFailure(StateError('?')), 'erro do App Server');
    });
  });

  group('merge (R2)', () {
    test('a sparse update keeps the fields it does not bring', () {
      final read = codexSnapshotFromRead(recordedRead());
      final merged = codexMergeUpdate(read, {
        'rateLimits': {
          'limitId': 'codex',
          'primary': {'usedPercent': 42},
          'planType': null,
          'credits': null,
        },
      });
      final five = merged.window(300)!;
      expect(five.usedPercent, 42);
      // The duration and the reset of the reading stay.
      expect(five.minutes, 300);
      expect(five.resetsAt, read.window(300)!.resetsAt);
      expect(merged.window(10080)?.usedPercent, 15);
      expect(merged.main.plan, 'plus');
      expect(merged.main.credits?.balance, '0');
      expect(merged.via, QuotaVia.update);
    });

    test('the recorded update merges into the recorded reading', () {
      final read = codexSnapshotFromRead(recordedRead());
      final merged = codexMergeUpdate(read, recordedUpdate());
      expect(merged.window(300)?.usedPercent, 0);
      expect(
        merged.window(300)?.resetsAt,
        DateTime.fromMillisecondsSinceEpoch(1795242731 * 1000, isUtc: true),
      );
      expect(merged.window(10080)?.usedPercent, 15);
    });

    test('an update of another bucket goes to its own line', () {
      final read = codexSnapshotFromRead(recordedRead());
      final merged = codexMergeUpdate(read, {
        'rateLimits': {
          'limitId': 'gpt-sol',
          'limitName': 'gpt-6.2-sol',
          'primary': {'usedPercent': 12, 'windowDurationMins': 300},
        },
      });
      expect(merged.window(300)?.usedPercent, 0);
      expect(merged.others.single.label, 'gpt-6.2-sol');
    });
  });

  group('store (R3, R4)', () {
    test('survives a restart and renews after resetsAt', () async {
      final db = memoryDatabase();
      final c = ProviderContainer(
        overrides: [
          databaseOverride(db),
          codexQuotaReaderProvider.overrideWithValue(
            () async => recordedRead(),
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(appSettingsProvider.notifier).load();
      await c.read(codexQuotaProvider.notifier).refresh();
      expect(
        c.read(quotaSnapshotProvider('codex'))?.window(10080)?.usedPercent,
        15,
      );
      // Apart from the Claude reading.
      expect(c.read(appSettingsProvider)[AppSettingKeys.lastRateLimit], isNull);

      final again = ProviderContainer(overrides: [databaseOverride(db)]);
      addTearDown(again.dispose);
      await again.read(appSettingsProvider.notifier).load();
      final s = again.read(codexQuotaProvider)!;
      expect(s.window(10080)?.usedPercent, 15);
      expect(s.readAt, isNotNull);
      final reset = s.window(300)!.resetsAt!;
      // A window at 100% is a limit until it resets, then it renewed.
      final full = s.copyWith(
        main: s.main.merge(
          codexBucket({
            'primary': {'usedPercent': 100},
          }),
        ),
      );
      expect(full.limit(reset.subtract(const Duration(minutes: 1))), isNotNull);
      expect(full.limit(reset.add(const Duration(minutes: 1))), isNull);
    });

    test('a failed reading keeps the old values and says why', () async {
      final db = memoryDatabase();
      var fail = false;
      final c = ProviderContainer(
        overrides: [
          databaseOverride(db),
          codexQuotaReaderProvider.overrideWithValue(() async {
            if (fail) {
              throw const AgentUnavailable('Codex: authentication required');
            }
            return recordedRead();
          }),
        ],
      );
      addTearDown(c.dispose);
      await c.read(appSettingsProvider.notifier).load();
      await c.read(codexQuotaProvider.notifier).refresh();
      final readAt = c.read(codexQuotaProvider)!.readAt;
      fail = true;
      await c.read(codexQuotaProvider.notifier).refresh();
      final s = c.read(codexQuotaProvider)!;
      expect(s.error, 'sem login: rode codex login');
      expect(s.readAt, readAt);
      expect(s.window(10080)?.usedPercent, 15);
      // A good reading clears the reason.
      fail = false;
      await c.read(codexQuotaProvider.notifier).refresh();
      expect(c.read(codexQuotaProvider)!.error, isNull);
    });

    test('the updates of the runs merge into the store', () async {
      final db = memoryDatabase();
      final c = ProviderContainer(
        overrides: [
          databaseOverride(db),
          codexQuotaReaderProvider.overrideWithValue(
            () async => recordedRead(),
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(appSettingsProvider.notifier).load();
      await c.read(codexQuotaProvider.notifier).refresh();
      codexRateLimitUpdates.add({
        'rateLimits': {
          'limitId': 'codex',
          'primary': {'usedPercent': 55},
        },
      });
      await pumpEventQueue();
      final s = c.read(codexQuotaProvider)!;
      expect(s.window(300)?.usedPercent, 55);
      expect(s.window(10080)?.usedPercent, 15);
    });
  });

  group('when to read (R1, P1)', () {
    ProviderContainer container({
      required String active,
      required List<String> reads,
      ProviderStatus status = ProviderStatus.ready,
    }) {
      final c = ProviderContainer(
        overrides: [
          databaseOverride(memoryDatabase()),
          activeAgentProvider.overrideWithValue(active),
          codexCliInfoProvider.overrideWith(
            (ref) async =>
                const ClaudeCliInfo(executable: 'codex', version: '0.170.0'),
          ),
          providerAvailabilityProvider.overrideWith(
            (ref, id) async => ProviderAvailability(status, ''),
          ),
          codexQuotaReaderProvider.overrideWithValue(() async {
            reads.add('read');
            return recordedRead();
          }),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('reads at start with the Codex logged in', () async {
      final reads = <String>[];
      final c = container(active: 'claude', reads: reads);
      await c.read(appSettingsProvider.notifier).load();
      await c.read(codexQuotaPollerProvider).start();
      expect(reads, hasLength(1));
    });

    test(
      'the 5-minute tick only reads with the Codex active or running',
      () async {
        final reads = <String>[];
        final idle = container(active: 'claude', reads: reads);
        await idle.read(appSettingsProvider.notifier).load();
        await idle.read(codexQuotaPollerProvider).tick();
        expect(reads, isEmpty);

        final active = container(active: 'codex', reads: reads);
        await active.read(appSettingsProvider.notifier).load();
        await active.read(codexQuotaPollerProvider).tick();
        expect(reads, hasLength(1));

        // A run open counts as running, even with the Claude active.
        final fake = FakeCodex.replay(
          readCodexTranscript('$codexFixtures/handshake.jsonl'),
        );
        final rpc = CodexRpc(fake);
        await rpc.request('initialize', {});
        await idle.read(codexQuotaPollerProvider).tick();
        expect(reads, hasLength(2));
        await rpc.stop(timeout: const Duration(milliseconds: 50));
      },
    );

    test('without login nothing is read and the reason is kept', () async {
      final reads = <String>[];
      final c = container(
        active: 'codex',
        reads: reads,
        status: ProviderStatus.loginRequired,
      );
      await c.read(appSettingsProvider.notifier).load();
      await c.read(codexQuotaPollerProvider).start();
      expect(reads, isEmpty);
      expect(c.read(codexQuotaProvider)?.error, 'sem login: rode codex login');
    });
  });

  test('names of plans, windows and limits (R5, R7, P5)', () {
    expect(quotaPlanName('plus'), 'ChatGPT Plus');
    expect(quotaPlanName('team'), 'Team');
    expect(quotaPlanName('sci_plus'), 'sci_plus');
    expect(quotaPlanName('unknown'), isNull);
    expect(quotaWindowTitle(300), 'Uso 5h');
    expect(quotaWindowTitle(10080), 'Semana');
    expect(quotaWindowTitle(1440), 'Janela de 24 h');
    expect(quotaLimitWords('rate_limit_reached'), 'limite do plano');
    expect(
      quotaLimitWords('workspace_owner_credits_depleted'),
      'créditos do workspace esgotados',
    );
  });

  test('a null ordinaryUsageAllowed is never read as allowed (R7)', () {
    final now = DateTime.utc(2026, 11, 21, 12);
    const base = QuotaSnapshot(
      provider: 'codex',
      main: QuotaBucket(
        id: 'codex',
        reached: 'rate_limit_reached',
        windows: [],
      ),
    );
    // The kind reported stays a limit; times do not clear it.
    expect(base.limit(now)?.words, 'limite do plano');
    const blocked = QuotaSnapshot(
      provider: 'codex',
      main: QuotaBucket(id: 'codex'),
      ordinaryUsageAllowed: false,
    );
    expect(blocked.limit(now), isNotNull);
    const unknown = QuotaSnapshot(
      provider: 'codex',
      main: QuotaBucket(id: 'codex'),
    );
    expect(unknown.limit(now), isNull);
  });
}
