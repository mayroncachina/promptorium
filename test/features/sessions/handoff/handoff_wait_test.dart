import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/memory/handoff.dart';
import 'package:promptorium/features/sessions/handoff/continue_controller.dart';
import 'package:promptorium/features/sessions/handoff/continue_link.dart';
import 'package:promptorium/features/sessions/handoff/handoff_wait.dart';

import '../../../core/memory/fake_ai_memory.dart';

HandoffList _list({bool unended = false}) =>
    HandoffList.parse(jsonDecode(handoffListJson(unended: unended)));

HandoffList _withManual() {
  final j = jsonDecode(handoffListJson()) as Map<String, dynamic>;
  (j['handoffs'] as List).insert(0, {
    'id': '01JDX0MANUAL0000000000000',
    'from_session_id': null,
    'from_agent': 'claude-code',
    'summary': 'Decidir o formato do changelog da 0.23',
    'state': 'open',
    'created_at': '2026-11-18T10:00:00Z',
  });
  return HandoffList.parse(j);
}

void main() {
  group('R4.2, P8 · waiting for the handoff', () {
    test('finds the automatic handoff of the origin by its native id', () async {
      var reads = 0;
      final r = await waitForHandoff(
        nativeId: 'sess-claude-1',
        list: () async {
          reads++;
          return reads < 3 ? const HandoffList() : _list();
        },
        delay: (_) async {},
      );
      expect(r.handoff?.id, '01JDX4AUTO0000000000000000');
      expect(r.cut, isFalse);
      expect(r.finalized, isFalse);
      expect(reads, 3);
    });

    test('calls finalize-session once after half the wait, then finds it', () async {
      var finalized = 0;
      final r = await waitForHandoff(
        nativeId: 'sess-claude-1',
        list: () async => finalized > 0 ? _list() : const HandoffList(),
        finalize: () async => finalized++,
        timeout: const Duration(milliseconds: 40),
        finalizeAfter: const Duration(milliseconds: 10),
        interval: const Duration(milliseconds: 5),
        delay: Future<void>.delayed,
      );
      expect(finalized, 1);
      expect(r.finalized, isTrue);
      expect(r.handoff, isNotNull);
    });

    test('R4.3: cut without a handoff after the wait (newer_unended_session)',
        () async {
      final r = await waitForHandoff(
        nativeId: '019a3f2c-0000-4000-8000-000000000000',
        list: () async => _list(unended: true),
        timeout: const Duration(milliseconds: 20),
        finalizeAfter: const Duration(milliseconds: 5),
        interval: const Duration(milliseconds: 5),
        finalize: () async {},
      );
      expect(r.handoff, isNull);
      expect(r.cut, isTrue);
      expect(r.list?.unended?.sessionId, '019a3f2c-0000-4000-8000-000000000000');
    });

    test('R5: a manual handoff is delivered before the automatic one', () {
      final list = _withManual();
      final r = HandoffWaitResult(
        handoff: handoffOfSession(list, 'sess-claude-1'),
        list: list,
      );
      expect(r.manualBefore?.id, '01JDX0MANUAL0000000000000');
      expect(list.nextDelivered?.manual, isTrue);
    });
  });

  test('R4.5: accepted, delivered at start or not confirmed', () {
    final open = _list();
    expect(
      handoffAcceptance(open, '01JDX4AUTO0000000000000000').state,
      HandoffAcceptance.unconfirmed,
    );
    expect(
      handoffAcceptance(const HandoffList(), '01JDX4AUTO0000000000000000').state,
      HandoffAcceptance.delivered,
    );
    final history = HandoffList.parse(
      jsonDecode(handoffListJson(history: true)),
    );
    final a = handoffAcceptance(history, '01JDX1OLD00000000000000000');
    expect(a.state, HandoffAcceptance.accepted);
    expect(a.at, isNotNull);
  });

  test('R4.4: the first message cites the exact handoff id', () {
    final h = handoffOfSession(_list(), 'sess-claude-1')!;
    final m = continueMessage(
      originTitle: 'Parser de front-matter',
      originProvider: 'claude',
      path: ContinuePath.aiMemory,
      handoff: h,
    );
    expect(m, contains('A passagem 01JDX4AUTO0000000000000000 do ai-memory'));
    expect(m, contains('memory_handoff_accept'));
    expect(m, contains('handoff_id "01JDX4AUTO0000000000000000"'));
    final cut = continueMessage(
      originTitle: 'Parser',
      originProvider: 'claude',
      path: ContinuePath.aiMemory,
    );
    expect(cut, contains('cortada sem passagem'));
  });

  test('R6: ai-memory run with --no-autowire, --yolo only when it was YOLO', () {
    expect(aiMemoryRunArgs('codex'), ['run', 'codex', '--no-autowire']);
    expect(
      aiMemoryRunArgs('claude', yolo: true),
      ['run', 'claude', '--no-autowire', '--yolo'],
    );
    expect(aiMemoryAgentKind('claude'), 'claude-code');
    expect(aiMemoryAgentKind('codex'), 'codex');
  });
}
