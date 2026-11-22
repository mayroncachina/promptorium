import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/memory/ai_memory_cli.dart';
import 'package:promptorium/core/memory/ai_memory_state.dart';
import 'package:promptorium/core/memory/ai_memory_wiring.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/sessions/handoff/continue_controller.dart';
import 'package:promptorium/features/sessions/handoff/continue_dialog.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../../core/memory/fake_ai_memory.dart';
import '../../../helpers/test_db.dart';

class _Controller extends ContinueController {
  _Controller(super.ref);

  @override
  Future<List<String>> uncommitted(String worktree) async => const ['a'];

  @override
  Future<void> endOrigin(String id) async {}
}

Session _origin({String? externalId = 'sess-claude-1'}) => Session(
  id: 's1',
  workspaceId: 1,
  provider: 'claude',
  title: 'Parser de front-matter',
  worktreePath: '/repo/promptorium-wt/spec-parser',
  branch: 'spec/parser-linhas',
  status: SessionStatus.completed,
  model: 'opus',
  costUsd: 0,
  tokensIn: 0,
  tokensOut: 0,
  startedAt: DateTime(2026, 11, 20, 11),
  externalId: externalId,
  permissionMode: 'acceptEdits',
);

const _on = AiMemoryWiring(
  claude: AiMemoryAgentWiring(
    agent: AiMemoryAgent.claude,
    hooks: AiMemoryLink.on,
    mcp: AiMemoryLink.on,
  ),
  codex: AiMemoryAgentWiring(
    agent: AiMemoryAgent.codex,
    hooks: AiMemoryLink.on,
    mcp: AiMemoryLink.on,
  ),
);

/// The dialog with the ai-memory of 3.5.1 answered by a fake runner.
Future<List<List<String>>> _pump(
  WidgetTester tester, {
  required String Function() handoffs,
  AiMemoryWiring wiring = _on,
  Session? origin,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final calls = <List<String>>[];
  Future<ProcessResult> run(
    String exe,
    List<String> args, {
    String? workingDirectory,
    required Duration timeout,
  }) async {
    calls.add(args);
    final out = args.length > 1 && args[1] == 'memory_handoff_list'
        ? handoffs()
        : '{}';
    return ProcessResult(0, 0, out, '');
  }

  final container = ProviderContainer(
    overrides: [
      databaseOverride(memoryDatabase()),
      providerAvailabilityProvider.overrideWith(
        (ref, id) async =>
            const ProviderAvailability(ProviderStatus.ready, 'ok'),
      ),
      continueControllerProvider.overrideWith(_Controller.new),
      aiMemoryDetectionProvider.overrideWith(
        (ref) async => const AiMemoryDetection(
          status: AiMemoryStatus.connected,
          executable: '/fake/ai-memory',
          version: '3.5.1',
        ),
      ),
      aiMemoryWiringProvider.overrideWith((ref) async => wiring),
      aiMemoryCliProvider.overrideWith(
        (ref) async => AiMemoryCli(executable: '/fake/ai-memory', run: run),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: ContinueDialog(origin: origin ?? _origin())),
      ),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return calls;
}

void main() {
  testWidgets('R4: the handoff of the origin shows as plain text and is the '
      'recommended path; the first message cites its id', (tester) async {
    await _pump(tester, handoffs: handoffListJson);
    expect(find.byKey(const ValueKey('continue-handoff')), findsOneWidget);
    expect(find.text('01JDX4…'), findsOneWidget);
    expect(
      find.textContaining('Parser trocado de regex para leitor por linhas'),
      findsOneWidget,
    );
    expect(find.text('• Escrever test/spec_parser_bom_test.dart'), findsOneWidget);
    expect(find.text('Passagem do ai-memory · recomendado'), findsOneWidget);
    final message = tester.widget<TextField>(
      find.byKey(const ValueKey('continue-message')),
    );
    expect(message.controller!.text, contains('01JDX4AUTO0000000000000000'));
    // R6: the terminal option says it is out of the timeline.
    expect(find.textContaining('fora da timeline'), findsOneWidget);
    // No line about ai-memory missing.
    expect(find.byKey(const ValueKey('continue-no-ai-memory')), findsNothing);
  });

  testWidgets('R4.3: cut without a handoff shows the notice and goes on', (
    tester,
  ) async {
    final calls = await _pump(
      tester,
      handoffs: () => handoffListJson(unended: true),
      origin: _origin(externalId: '019a3f2c-0000-4000-8000-000000000000'),
    );
    // The 10 s wait, with finalize-session halfway (P8).
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.byKey(const ValueKey('continue-cut')), findsOneWidget);
    expect(
      find.textContaining('a sessão foi cortada. O Codex vai ler'),
      findsOneWidget,
    );
    expect(
      calls.where((a) => a.first == 'finalize-session'),
      hasLength(1),
    );
    expect(
      calls.firstWhere((a) => a.first == 'finalize-session'),
      containsAllInOrder([
        '--agent',
        'claude-code',
        '--session-id',
        '019a3f2c-0000-4000-8000-000000000000',
      ]),
    );
    final go = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const ValueKey('continue-go')),
        matching: find.byType(InkWell),
      ),
    );
    expect(go.onTap, isNotNull);
  });

  testWidgets('R5: a concurrent manual handoff offers "Descartar a manual" '
      '(with confirmation) and "Seguir assim"', (tester) async {
    String json() {
      final j = jsonDecode(handoffListJson()) as Map<String, dynamic>;
      (j['handoffs'] as List).insert(0, {
        'id': '01JDX0MANUAL0000000000000',
        'from_session_id': null,
        'from_agent': 'claude-code',
        'summary': 'Decidir o formato do changelog da 0.23',
        'state': 'open',
        'created_at': '2026-11-18T10:00:00Z',
      });
      return jsonEncode(j);
    }

    final calls = await _pump(tester, handoffs: json);
    expect(find.byKey(const ValueKey('continue-manual')), findsOneWidget);
    expect(find.textContaining('Há uma passagem manual de 18/11'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('continue-manual-discard')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('continue-manual-discard-confirm')),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      calls.any((a) => a.length > 2 && a[1] == 'memory_handoff_cancel' &&
          a[2].contains('01JDX0MANUAL0000000000000')),
      isTrue,
    );
    expect(find.byKey(const ValueKey('continue-manual')), findsNothing);
  });

  testWidgets('without hooks in both agents the app summary is the path', (
    tester,
  ) async {
    await _pump(
      tester,
      handoffs: handoffListJson,
      wiring: const AiMemoryWiring(
        claude: AiMemoryAgentWiring(
          agent: AiMemoryAgent.claude,
          hooks: AiMemoryLink.on,
        ),
        codex: AiMemoryAgentWiring(
          agent: AiMemoryAgent.codex,
          hooks: AiMemoryLink.awaitingTrust,
        ),
      ),
    );
    expect(find.byKey(const ValueKey('continue-handoff')), findsNothing);
    expect(
      find.textContaining('hooks do ai-memory não ligados nos dois agentes'),
      findsOneWidget,
    );
    final message = tester.widget<TextField>(
      find.byKey(const ValueKey('continue-message')),
    );
    expect(message.controller!.text, startsWith('Continuação da sessão'));
  });
}
