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
import 'package:promptorium/features/prompt/refine_origin.dart';
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
  String? applyRequest,
  List<Override> overrides = const [],
  List<Map<String, dynamic>> extraEvents = const [],
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
            mode: Value(applyRequest == null ? 'ask' : 'refine'),
            refineOrigin: Value(applyRequest == null ? null : 'board'),
            refineSpecCode: Value(applyRequest == null ? null : 'SPEC-020'),
            claudeSessionId: const Value('conv-sid'),
            messageCount: const Value(2),
            tokensIn: const Value(8000),
            tokensOut: const Value(400),
            updatedAt: Value(DateTime.now()),
          ),
        );
    final events = [
      AppEventTypes.userMessage(
        applyRequest ??
            'Como leio o stream-json? Veja @lib/core/claude_process.dart',
        DateTime.now(),
      ),
      textLine(answer),
      resultLine(),
      ...extraEvents,
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
  test('SPEC-088: the suggestion parses with old and current wording', () {
    const head =
        'Aplique à spec @docs/specs/SPEC-020-a.md (SPEC-020) a sugestão da '
        'sessão das etapas R7 : "Troque "a". Depois b';
    final current = parseApplySuggestion(
      '$head". $applySuggestionInstructions',
    );
    expect(current?.steps, 'R7');
    expect(current?.body, 'Troque "a". Depois b');
    final old = parseApplySuggestion('$head". Mantenha o formato.');
    expect(old?.body, 'Troque "a". Depois b');
    expect(parseApplySuggestion('Outro pedido qualquer'), isNull);
  });

  testWidgets('SPEC-088: the suggestion and full request are both readable', (
    tester,
  ) async {
    const prompt =
        'Aplique à spec @docs/specs/SPEC-020-teste.md (SPEC-020) a sugestão '
        'da sessão das etapas R7,R8,R9 : "Atualize o caminho do teste.". '
        '$applySuggestionInstructions';
    await pumpPrompt(tester, size: const Size(1100, 700), applyRequest: prompt);
    expect(find.text('Aplicar à spec · SPEC-020'), findsOneWidget);
    expect(find.text('Voltar à spec SPEC-020'), findsOneWidget);
    expect(find.text('Sugestão das etapas R7,R8,R9'), findsOneWidget);
    expect(find.text('Atualize o caminho do teste.'), findsOneWidget);
    expect(find.text(prompt), findsNothing);
    await tester.tap(find.text('Ver pedido completo'));
    await pumpFor(tester);
    expect(find.text(prompt), findsOneWidget);
    expect(find.text('Ocultar pedido completo'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('prompt-rename')));
    await pumpFor(tester);
    await tester.enterText(
      find.byKey(const ValueKey('title-field')),
      'Revisar caminho do teste',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await pumpFor(tester);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('prompt-title'))).data,
      'Revisar caminho do teste',
    );
    expect(find.text('Aplicar à spec · SPEC-020'), findsOneWidget);
    expect(find.text('Voltar à spec SPEC-020'), findsOneWidget);
  });

  testWidgets('SPEC-088: the suggestion renders its Markdown, no raw marks', (
    tester,
  ) async {
    const prompt =
        'Aplique à spec @docs/specs/SPEC-020-teste.md (SPEC-020) a sugestão '
        'da sessão das etapas R7 : "Troque `lib/a.dart` por **lib/b.dart**.". '
        '$applySuggestionInstructions';
    await pumpPrompt(tester, size: const Size(1100, 700), applyRequest: prompt);
    final body = find.byKey(const ValueKey('prompt-apply-suggestion-body'));
    expect(body, findsOneWidget);
    final shown = tester
        .widgetList<RichText>(
          find.descendant(of: body, matching: find.byType(RichText)),
        )
        .map((r) => r.text.toPlainText())
        .join();
    expect(shown, contains('lib/a.dart'));
    expect(shown, contains('lib/b.dart'));
    expect(shown, isNot(contains('`')));
    expect(shown, isNot(contains('**')));
  });

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
    // SPEC-068 R2: next to "Transformar em spec".
    expect(find.byKey(const ValueKey('plan-split')), findsOneWidget);
    expect(find.text('Dividir em specs'), findsOneWidget);

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

  group('SPEC-087 medidor de contexto', () {
    testWidgets('sem medição: aguardando, acumulado separado do medidor', (
      tester,
    ) async {
      await pumpPrompt(tester);
      final meter = find.byKey(const ValueKey('context-indicator'));
      expect(meter, findsOneWidget);
      final text = tester
          .widgetList<RichText>(
            find.descendant(of: meter, matching: find.byType(RichText)),
          )
          .map((r) => r.text.toPlainText())
          .join(' ');
      expect(text, contains('Aguardando medição'));
      expect(text, isNot(contains('%')));
      // R11: the accumulated number keeps its own label, out of the meter.
      expect(find.text('Tokens acumulados'), findsOneWidget);
      expect(find.text('acumulado ≠ contexto atual'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('medição real: o medidor abre o painel e Esc fecha', (
      tester,
    ) async {
      final assistant = {
        'type': 'assistant',
        'message': {
          'id': 'msg_2',
          'model': 'claude-sonnet-5-5',
          'content': [
            {'type': 'text', 'text': 'segunda'},
          ],
          'usage': {
            'input_tokens': 3100,
            'cache_creation_input_tokens': 9400,
            'cache_read_input_tokens': 169500,
            'output_tokens': 50,
          },
        },
        'parent_tool_use_id': null,
      };
      final result = {
        ...resultLine(),
        'modelUsage': {
          'claude-sonnet-5-5': {'contextWindow': 1000000},
        },
      };
      await pumpPrompt(
        tester,
        size: const Size(1366, 768),
        extraEvents: [
          AppEventTypes.userMessage('mais', DateTime.now()),
          assistant,
          result,
          {
            'type': 'promptorium_context_usage',
            'v': 1,
            'total': 182000,
            'threshold': 200000,
            'max': 233000,
            'model': 'claude-sonnet-5-5',
            'measured': true,
            'categories': [],
          },
        ],
      );
      final meter = find.byKey(const ValueKey('context-indicator'));
      final text = tester
          .widgetList<RichText>(
            find.descendant(of: meter, matching: find.byType(RichText)),
          )
          .map((r) => r.text.toPlainText())
          .join(' ');
      expect(text, contains('182 mil / 1 milhão'));
      expect(text, contains('18%'));
      // Rebuilt from the stored events, without a process: an old reading
      // (R3), never presented as live.
      expect(text, contains('não é ao vivo'));
      expect(text, isNot(contains('medido no turno')));
      // The accumulated stays the conversation's sum (8k), not 182 mil.
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('context-tokens'))).data,
        '8k',
      );
      await tester.tap(meter);
      await pumpFor(tester);
      expect(find.byKey(const ValueKey('context-usage')), findsOneWidget);
      expect(
        find.textContaining('capacidade da janela · 1 milhão'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('prompt-side-panel')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await pumpFor(tester);
      expect(find.byKey(const ValueKey('context-usage')), findsNothing);
      expect(find.byKey(const ValueKey('prompt-side-panel')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
