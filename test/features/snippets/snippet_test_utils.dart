import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/snippets_repo.dart';
import 'package:promptorium/features/prompt/prompt_actions.dart';
import 'package:promptorium/features/prompt/conversation_manager.dart';
import 'package:promptorium/features/prompt/prompt_screen.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';
import '../prompt/prompt_test_utils.dart';
import '../sessions/session_test_utils.dart';

const atrasados = '''-- Pedidos atrasados há mais de 3 dias, por cliente
SELECT c.id, c.nome
FROM pedidos p
JOIN clientes c ON c.id = p.cliente_id;''';

/// A snippet row of workspace [ws] (`createdAt` [minutesAgo] before now).
Future<Snippet> addSnippet(
  AppDatabase db,
  int ws,
  String name, {
  String body = 'select 1;',
  String? language = 'sql',
  String description = '',
  int? conversation,
  String? originLabel,
  int minutesAgo = 0,
  int uses = 0,
  DateTime? lastUsedAt,
}) => db
    .into(db.snippets)
    .insertReturning(
      SnippetsCompanion.insert(
        workspaceId: ws,
        name: name,
        nameKey: snippetNameKey(name),
        body: body,
        bodyHash: snippetHash(body),
        language: Value(language),
        description: Value(description),
        originConversationId: Value(conversation),
        originLabel: Value(originLabel),
        uses: Value(uses),
        lastUsedAt: Value(lastUsedAt),
        createdAt: Value(
          DateTime.now().subtract(Duration(minutes: minutesAgo)),
        ),
      ),
    );

/// The Prompt screen of a workspace with one conversation ("Pedidos
/// atrasados no DBeaver", id 1), selected. [seed] adds rows before it opens.
Future<(AppDatabase, ProviderContainer, Workspace)> pumpPrompt(
  WidgetTester tester, {
  Future<void> Function(AppDatabase db, Workspace ws)? seed,
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = memoryDatabase();
  final cli = FakeCli();
  final ws = await addWorkspace(db, '/work/loja-api');
  await db
      .into(db.conversations)
      .insert(
        ConversationsCompanion.insert(
          workspaceId: ws.id,
          title: 'Pedidos atrasados no DBeaver',
          model: 'sonnet',
          claudeSessionId: const Value('sid-1'),
          messageCount: const Value(2),
        ),
      );
  await seed?.call(db, ws);
  final container = ProviderContainer(
    overrides: [
      ...sessionOverrides(db: db, cli: cli, notifier: FakeNotifier()),
      workspaceFilesProvider.overrideWith((ref, root) async => <String>[]),
    ],
  );
  await container.read(appSettingsProvider.notifier).load();
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
  container.read(selectedConversationProvider.notifier).select(1);
  await pumpFor(tester);
  return (db, container, ws);
}

Future<void> pumpFor(WidgetTester tester, [int times = 10]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Records what goes to the clipboard.
List<String> recordClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await pumpFor(tester);
}

String composerText(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const ValueKey('prompt-field')))
    .controller!
    .text;
