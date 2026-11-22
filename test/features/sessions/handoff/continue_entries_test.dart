import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/memory/handoff.dart';
import 'package:promptorium/core/claude/claude_event.dart' show QuotaWindow;
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/core/providers/quota_source.dart';
import 'package:promptorium/features/context/compaction_controller.dart';
import 'package:promptorium/features/context/widgets/context_compaction.dart';
import 'package:promptorium/features/project/widgets/ai_memory_view.dart';
import 'package:promptorium/features/sessions/handoff/handoff_from_memory.dart';
import 'package:promptorium/features/sessions/timeline.dart';
import 'package:promptorium/features/sessions/widgets/quota_switch_banner.dart';

import '../../../core/memory/fake_ai_memory.dart';
import '../../context/context_compaction_test.dart' show assistant, feed, pump;
import '../sessions_screen_test.dart' show pumpFor, pumpScreen, storedEvents;

QuotaSnapshot _codex(double used) => QuotaSnapshot(
  provider: 'codex',
  main: QuotaBucket(
    id: 'codex',
    windows: [
      QuotaWindow(id: 'primary', label: '5 h', usedPercent: used, minutes: 300),
    ],
  ),
  ordinaryUsageAllowed: true,
  readAt: DateTime.now(),
);

Future<void> _screen(WidgetTester tester, QuotaSnapshot? codex, {
  bool limit = true,
}) async {
  await pumpScreen(
    tester,
    events: [
      ...storedEvents,
      if (limit)
        AppEventTypes.limitEvent(
          provider: 'claude',
          minutes: 300,
          resetsAt: DateTime.now().add(const Duration(hours: 1, minutes: 43)),
        ),
    ],
    overrides: [
      providerAvailabilityProvider.overrideWith(
        (ref, id) async =>
            const ProviderAvailability(ProviderStatus.ready, 'ok'),
      ),
      quotaSnapshotProvider('codex').overrideWithValue(codex),
    ],
  );
  final c = ProviderScope.containerOf(
    tester.element(find.byKey(const ValueKey('session-header-title'))),
  );
  for (final id in ['claude', 'codex']) {
    c.listen(providerAvailabilityProvider(id), (_, _) {});
  }
  await pumpFor(tester);
  // The header and the banner watch the session: a new selection rebuilds.
  await tester.tap(find.byKey(const ValueKey('session-tile-s1')));
  await pumpFor(tester);
}

void main() {
  group('R2 · quota banner', () {
    testWidgets('after the limit event, with quota in the Codex: the banner '
        'suggests; nothing switches by itself', (tester) async {
      await _screen(tester, _codex(22));
      expect(find.textContaining('Limite de uso atingido · cota de 5h do '
          'Claude Code'), findsOneWidget);
      final text = tester.widget<Text>(
        find.byKey(const ValueKey('quota-switch-text')),
      );
      expect(text.data, startsWith('Cota de 5h do Claude Code esgotada · '
          'reinicia em 1h4'));
      expect(text.data, endsWith('· Codex com 78% livre'));
      expect(find.byKey(const ValueKey('quota-switch-go')), findsOneWidget);
      // Close: gone for this session.
      await tester.tap(find.byKey(const ValueKey('quota-switch-close')));
      await pumpFor(tester);
      expect(find.byKey(const ValueKey('quota-switch-banner')), findsNothing);
    });

    testWidgets('no banner when the Codex has no quota either', (tester) async {
      await _screen(tester, _codex(100));
      expect(find.byKey(const ValueKey('quota-switch-banner')), findsNothing);
    });

    testWidgets('no banner without the limit event', (tester) async {
      await _screen(tester, _codex(10), limit: false);
      expect(find.byKey(const ValueKey('quota-switch-banner')), findsNothing);
    });

    test('words', () {
      expect(untilWords(const Duration(hours: 1, minutes: 43)), '1h43');
      expect(untilWords(const Duration(minutes: 12)), '12 min');
      expect(freePercent(_codex(22)), 78);
    });
  });

  group('R12 · Nova conversa', () {
    testWidgets('chooses the provider and, with ai-memory, starts with the '
        'handoff message', (tester) async {
      final s = feed([assistant(1000)]);
      final started = <String?>[];
      final chosen = <String>[];
      await pump(
        tester,
        ContextActions(
          snapshot: s,
          availability: CompactAvailability.available,
          onCompact: (_) async {},
          onAdjust: () {},
          onNewConversation: started.add,
          summary: () => 'Resumo',
          providers: const ['claude', 'codex'],
          provider: 'claude',
          onProvider: chosen.add,
          handoff: () async => 'Continue a partir da passagem 01JDX4',
        ),
      );
      expect(find.text('Nova conversa em'), findsOne);
      await tester.tap(find.byKey(const ValueKey('context-new-provider-codex')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('context-new-handoff')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('context-new-go')));
      await tester.pumpAndSettle();
      expect(find.text('Continue a partir da passagem 01JDX4'), findsOne);
      await tester.tap(find.byKey(const ValueKey('context-summary-use')));
      await tester.pumpAndSettle();
      expect(chosen, ['codex']);
      expect(started, ['Continue a partir da passagem 01JDX4']);
    });

    testWidgets('without ai-memory nor the Codex in the Prompt: as before', (
      tester,
    ) async {
      final s = feed([assistant(1000)]);
      await pump(
        tester,
        ContextActions(
          snapshot: s,
          availability: CompactAvailability.available,
          onCompact: (_) async {},
          onAdjust: () {},
          onNewConversation: (_) {},
          summary: () => 'Resumo',
        ),
      );
      expect(find.text('Nova conversa em'), findsNothing);
      expect(find.byKey(const ValueKey('context-new-handoff')), findsNothing);
    });
  });

  group('R13 · Continuar em… from the Memória', () {
    final list = HandoffList.parse(jsonDecode(handoffListJson()));
    final h = list.handoffs.first;

    test('the action fills the panel button: "Continuar no Codex" for a '
        'handoff of the Claude Code', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final action = c.read(handoffContinueActionProvider);
      expect(action, isNotNull);
      expect(action!.label(h), 'Continuar no Codex');
      expect(action.label(list.handoffs[1]), 'Continuar no Claude');
    });

    test('the origin is the session whose worktree is the handoff folder; '
        'else none (root, no link)', () {
      Session s(String id, String path, DateTime at) => Session(
        id: id,
        workspaceId: 1,
        provider: 'claude',
        title: id,
        worktreePath: path,
        branch: 'b',
        status: SessionStatus.completed,
        model: 'opus',
        costUsd: 0,
        tokensIn: 0,
        tokensOut: 0,
        startedAt: at,
      );
      final sessions = [
        s('old', '/repo/promptorium-wt/spec-parser', DateTime(2026, 11, 19)),
        s('new', '/repo/promptorium-wt/spec-parser', DateTime(2026, 11, 20)),
        s('other', '/repo/promptorium-wt/x', DateTime(2026, 11, 21)),
      ];
      expect(sessionOfHandoff(h, sessions)?.id, 'new');
      expect(sessionOfHandoff(h, sessions.sublist(2)), isNull);
      expect(handoffTarget(h), 'codex');
    });
  });
}
