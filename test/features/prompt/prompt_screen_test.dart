import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/providers/agent_registry.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/prompt/prompt_actions.dart';
import 'package:promptorium/features/prompt/prompt_screen.dart';
import 'package:promptorium/features/sessions/timeline.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';
import 'prompt_test_utils.dart';

const answer = 'Use `Process.start` e trate o stdout como um stream de linhas.';

Future<(AppDatabase, FakeCli, ProviderContainer)> pumpPrompt(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  bool withConversation = true,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = memoryDatabase();
  final cli = FakeCli();
  final ws = await addWorkspace(db, '/work/repo');
  if (withConversation) {
    final conv = await db
        .into(db.conversations)
        .insertReturning(
          ConversationsCompanion.insert(
            workspaceId: ws.id,
            title: 'Parser stream-json em Dart',
            model: 'sonnet',
            claudeSessionId: const Value('conv-sid'),
            messageCount: const Value(2),
            tokensIn: const Value(8000),
            tokensOut: const Value(400),
            updatedAt: Value(DateTime.now()),
          ),
        );
    final events = [
      AppEventTypes.userMessage(
        'Como leio o stream-json? Veja @lib/core/claude_process.dart',
        DateTime.now(),
      ),
      textLine(answer),
      resultLine(),
    ];
    var seq = 0;
    for (final e in events) {
      await db
          .into(db.conversationEvents)
          .insert(
            ConversationEventsCompanion.insert(
              conversationId: conv.id,
              seq: ++seq,
              type: '${e['type']}',
              json: jsonEncode(e),
            ),
          );
    }
  }
  final container = ProviderContainer(
    overrides: [
      ...sessionOverrides(db: db, cli: cli, notifier: FakeNotifier()),
      workspaceFilesProvider.overrideWith(
        (ref, root) async => [
          'README.md',
          'lib/core/claude/claude_process.dart',
          'lib/main.dart',
        ],
      ),
      ...overrides,
    ],
  );
  await container.read(appSettingsProvider.notifier).load();
  await seedSavedPrompts(
    container.read(savedPromptsRepoProvider),
    container.read(appSettingsProvider.notifier),
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: PromptScreen()),
      ),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(Duration.zero);
  });
  await pumpFor(tester);
  if (withConversation) {
    await tester.tap(find.byKey(const ValueKey('conversation-1')));
    await pumpFor(tester);
  }
  return (db, cli, container);
}

Future<void> pumpFor(WidgetTester tester, [int times = 10]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Finder get field => find.byKey(const ValueKey('prompt-field'));

String fieldText(WidgetTester tester) =>
    tester.widget<TextField>(field).controller!.text;

void main() {
  testWidgets('history, conversation, context and saved prompts render', (
    tester,
  ) async {
    await pumpPrompt(tester);
    expect(find.text('Hoje'), findsOneWidget);
    expect(find.text('Sonnet · 2 mensagens'), findsOneWidget);
    expect(find.byKey(const ValueKey('prompt-title')), findsOneWidget);
    expect(find.textContaining('Como leio o stream-json?'), findsOneWidget);
    expect(find.textContaining('Claude Code · Sonnet'), findsOneWidget);
    // Actions under the last answer.
    expect(find.byKey(const ValueKey('answer-copy')), findsOneWidget);
    expect(find.byKey(const ValueKey('answer-save-prompt')), findsOneWidget);
    // Context panel.
    expect(find.text('repo/'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('context-access'))).data,
      'somente leitura',
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('context-tokens'))).data,
      '8k',
    );
    expect(
      find.byKey(const ValueKey('file-chip-lib/core/claude_process.dart')),
      findsOneWidget,
    );
    // Seeded saved prompts.
    for (final cmd in [
      'explicar',
      'testes',
      'revisar-seguranca',
      'spec',
      'commit',
    ]) {
      expect(find.byKey(ValueKey('saved-prompt-$cmd')), findsOneWidget);
    }
    // Mode hint.
    await tester.tap(find.byKey(const ValueKey('mode-plan')));
    await pumpFor(tester);
    expect(find.text('propõe um plano antes de agir'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"/" lists saved prompts; Enter inserts the body and counts '
      'a use', (tester) async {
    final (db, _, c) = await pumpPrompt(tester);
    await tester.enterText(field, '/tes');
    await pumpFor(tester, 3);
    expect(find.byKey(const ValueKey('prompt-suggestions')), findsOneWidget);
    expect(find.byKey(const ValueKey('suggest-prompt-testes')), findsOneWidget);
    expect(find.byKey(const ValueKey('suggest-prompt-commit')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await pumpFor(tester);
    final body = defaultSavedPrompts
        .firstWhere((p) => p.command == 'testes')
        .body;
    expect(fieldText(tester), body);
    expect(find.byKey(const ValueKey('prompt-suggestions')), findsNothing);
    expect(
      (await c.read(savedPromptsRepoProvider).getByCommand('testes'))!.uses,
      1,
    );
    expect(find.text('1 uso'), findsOneWidget);

    // Clicking a saved prompt of the panel inserts it at the cursor.
    await tester.enterText(field, 'Antes: ');
    await tester.tap(find.byKey(const ValueKey('saved-prompt-commit')));
    await pumpFor(tester);
    expect(
      fieldText(tester),
      startsWith('Antes: Escreva a mensagem de commit'),
    );
    expect(
      (await c.read(savedPromptsRepoProvider).getByCommand('commit'))!.uses,
      1,
    );
    expect(db, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"@" picks a workspace file and attaches it as a chip', (
    tester,
  ) async {
    await pumpPrompt(tester);
    await tester.enterText(field, 'explique @claude_pro');
    await pumpFor(tester, 3);
    final item = find.byKey(
      const ValueKey('suggest-file-lib/core/claude/claude_process.dart'),
    );
    expect(item, findsOneWidget);
    expect(find.byKey(const ValueKey('suggest-file-README.md')), findsNothing);
    await tester.tap(item);
    await pumpFor(tester);
    expect(fieldText(tester), 'explique @lib/core/claude/claude_process.dart ');
    // Chip in the composer and in the context panel.
    expect(
      find.byKey(
        const ValueKey('file-chip-lib/core/claude/claude_process.dart'),
      ),
      findsNWidgets(2),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Plano pronto": ExitPlanMode becomes a card; "Continuar '
      'planejando" denies it and the plan stays (UX v2, U4)', (tester) async {
    final (_, cli, _) = await pumpPrompt(tester);
    await tester.enterText(field, 'planeje o thinking');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await pumpFor(tester);
    cli.last.emit(
      '{"type":"control_request","request_id":"req-plan","request":'
      '{"subtype":"can_use_tool","tool_name":"ExitPlanMode","input":'
      '{"plan":"1. Gravar em `stream_parser.dart`\\n2. Card recolhido"}}}',
    );
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('plan-ready')), findsOneWidget);
    expect(find.text('Plano pronto'), findsOneWidget);
    expect(find.text('· 2 itens · 1 arquivo'), findsOneWidget);
    // No generic approval card for it.
    expect(find.byKey(const ValueKey('approve-req-plan')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('plan-keep-planning')));
    await pumpFor(tester);
    final resp = cli.last.writtenJson.last['response']['response'];
    expect(resp['behavior'], 'deny');
    expect(resp['message'], contains('continue planejando'));
    // Keep planning: the card goes away until the next plan.
    expect(find.byKey(const ValueKey('plan-ready')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('new conversation sends with the "Perguntar" args in the '
      'workspace root', (tester) async {
    final (db, cli, _) = await pumpPrompt(tester, withConversation: false);
    expect(find.text('Nova conversa'), findsWidgets);
    await tester.enterText(field, 'O que faz o main.dart?');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await pumpFor(tester);

    expect(cli.cwds.single, '/work/repo');
    expect(
      cli.args.single,
      containsAllInOrder([
        '--disallowedTools',
        ...ClaudeCodeProvider.readOnlyDisallowedTools,
      ]),
    );
    expect(
      cli.last.writtenJson.single['message']['content'],
      'O que faz o main.dart?',
    );
    final convs = await db.select(db.conversations).get();
    expect(convs.single.title, 'O que faz o main.dart?');
    expect(convs.single.mode, 'ask');
    expect(find.text('O que faz o main.dart?'), findsWidgets);
    expect(find.byKey(const ValueKey('prompt-stop')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the clip button picks files: chips, remove, and the drop '
      'target is there', (tester) async {
    await pumpPrompt(
      tester,
      withConversation: false,
      overrides: [
        filePickerProvider.overrideWithValue(
          ({initialDirectory}) async => ['/tmp/foto.png', '/tmp/relatorio.pdf'],
        ),
      ],
    );
    expect(find.byKey(const ValueKey('prompt-drop')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('prompt-attach')));
    await pumpFor(tester, 3);
    expect(
      find.byKey(const ValueKey('attached-chip-/tmp/foto.png')),
      findsOneWidget,
    );
    expect(find.text('relatorio.pdf'), findsOneWidget);
    // Removing one chip keeps the other.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('attached-chip-/tmp/foto.png')),
        matching: find.byType(InkWell),
      ),
    );
    await pumpFor(tester, 3);
    expect(
      find.byKey(const ValueKey('attached-chip-/tmp/foto.png')),
      findsNothing,
    );
    expect(find.text('relatorio.pdf'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits the minimum window (1100×700) without overflow', (
    tester,
  ) async {
    // The shell sidebar takes 56px; the title bar and footer the rest.
    await pumpPrompt(tester, size: const Size(1044, 628));
    expect(tester.takeException(), isNull);
    await tester.enterText(field, '/');
    await pumpFor(tester, 3);
    expect(find.byKey(const ValueKey('prompt-suggestions')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.enterText(field, '@');
    await pumpFor(tester, 3);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('answer-save-prompt')));
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('save-prompt-dialog')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
