import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/codex/codex_provider.dart';
import 'package:promptorium/core/codex/codex_cli.dart';
import 'package:promptorium/core/process/process_runner.dart';
import 'package:promptorium/core/providers/agent_registry.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/core/providers/provider_preferences.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/prompt/conversation_manager.dart';

import '../helpers/test_db.dart';

import 'package:promptorium/ui/shell/footer_stats.dart';

void main() {
  test('reading footer counters does not probe agent executables', () async {
    final calls = <String>[];
    final c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        processRunnerProvider.overrideWithValue((exe, args) async {
          calls.add(exe);
          throw StateError('Counters must not probe CLIs');
        }),
      ],
    );
    addTearDown(c.dispose);
    expect(c.read(footerStatsProvider).providerId, 'claude');
    await c.pump();
    await c
        .read(appSettingsProvider.notifier)
        .set(providerPreferenceKey(null), 'codex');
    expect(c.read(footerStatsProvider).providerId, 'codex');
    expect(c.read(footerStatsProvider).providerName, 'Codex');
    await c.pump();
    expect(calls, isEmpty);
  });

  test('project override, global fallback and restart preserve independent choices', () async {
    final db = memoryDatabase();
    addTearDown(db.close);
    var c = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    await c.read(appSettingsProvider.notifier).load();
    expect(c.read(defaultAgentProvider(1)), 'claude');
    await c
        .read(appSettingsProvider.notifier)
        .set(providerPreferenceKey(null), 'codex');
    await c
        .read(appSettingsProvider.notifier)
        .set(providerPreferenceKey(1), 'claude');
    expect(c.read(defaultAgentProvider(1)), 'claude');
    expect(c.read(defaultAgentProvider(2)), 'codex');
    c.dispose();
    c = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    expect(c.read(defaultAgentProvider(1)), 'claude');
    expect(c.read(defaultAgentProvider(2)), 'codex');
    expect(c.read(promptDraftProvider).providerId, 'codex');
    expect(c.read(promptDraftProvider).model, 'inherit');
    c
        .read(promptDraftProvider.notifier)
        .set(const PromptDraft(providerId: 'claude', model: 'sonnet'));
    await c
        .read(appSettingsProvider.notifier)
        .set(providerPreferenceKey(null), 'acp-other');
    expect(c.read(promptDraftProvider).providerId, 'claude');
  });

  test('Codex detection distinguishes missing, incompatible, login and ready without execution', () async {
    final provider = CodexProvider();
    for (final status in ProviderStatus.values) {
      final calls = <List<String>>[];
      final actual = await inspectProvider(provider, (exe, args) async {
        calls.add(args);
        if (status == ProviderStatus.missing) {
          throw const ProcessException('codex', []);
        }
        if (args.first == '--version') {
          return ProcessResult(1, 0, 'codex-cli 0.163.0', '');
        }
        if (args.first == 'app-server') {
          return ProcessResult(
            1,
            status == ProviderStatus.incompatible ? 1 : 0,
            'help',
            '',
          );
        }
        return ProcessResult(
          1,
          status == ProviderStatus.loginRequired ? 1 : 0,
          '',
          '',
        );
      });
      final expected = status == ProviderStatus.unknown
          ? ProviderStatus.ready
          : status;
      expect(actual.status, expected);
      expect(
        calls.any((a) => a.contains('exec') || a.contains('thread/start')),
        isFalse,
      );
    }
  });

  test(
    'Claude JSON auth status is required; a version alone is insufficient',
    () async {
      final result = await inspectProvider(ClaudeCodeProvider(), (
        exe,
        args,
      ) async {
        if (args.first == '--version') {
          return ProcessResult(1, 0, '2.1.300', '');
        }
        if (args.first == '--help') {
          return ProcessResult(1, 0, '--input-format --output-format', '');
        }
        return ProcessResult(1, 0, '{"loggedIn":false}', '');
      });
      expect(result.status, ProviderStatus.loginRequired);
    },
  );
  test(
    'independent provider probes survive Codex executable discovery',
    () async {
      final c = ProviderContainer(
        overrides: [
          databaseOverride(memoryDatabase()),
          codexExecutableCandidatesProvider.overrideWithValue(['/mock/codex']),
          processRunnerProvider.overrideWithValue((exe, args) async {
            if (exe != '/mock/codex') throw ProcessException(exe, args);
            if (args.first == '--version') {
              return ProcessResult(1, 0, 'codex-cli 0.163.0', '');
            }
            return ProcessResult(1, 0, 'help', '');
          }),
        ],
      );
      addTearDown(c.dispose);
      final codex = await c.read(providerAvailabilityProvider('codex').future);
      final claude = await c.read(
        providerAvailabilityProvider('claude').future,
      );
      expect(codex.status, ProviderStatus.ready);
      expect(claude.status, ProviderStatus.missing);
    },
  );
}
