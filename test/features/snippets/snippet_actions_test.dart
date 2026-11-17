import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/snippets/snippet_actions.dart';
import 'package:promptorium/ui/shell/navigation.dart';

import '../../helpers/test_db.dart';

Snippet _snippet({String body = 'SELECT 1;', String? language = 'sql'}) =>
    Snippet(
      id: 1,
      workspaceId: 1,
      name: 'Atrasados',
      nameKey: 'atrasados',
      language: language,
      description: '',
      body: body,
      bodyHash: 'h',
      uses: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

TextEditingController _at(String text, int cursor) =>
    TextEditingController(text: text)
      ..selection = TextSelection.collapsed(offset: cursor);

void main() {
  group('insertFencedSnippet (R8, P4)', () {
    test('a fenced block with the language at the cursor', () {
      final c = _at('', 0);
      insertFencedSnippet(c, _snippet());
      expect(c.text, '```sql\nSELECT 1;\n```\n');
      expect(c.selection.baseOffset, c.text.length);
    });

    test('a blank line before when the cursor is not at a line start', () {
      final c = _at('roda essa query:', 16);
      insertFencedSnippet(c, _snippet());
      expect(c.text, 'roda essa query:\n\n```sql\nSELECT 1;\n```\n');
    });

    test('at the start of a line: nothing before; the rest stays after', () {
      final c = _at('antes\ndepois', 6);
      insertFencedSnippet(c, _snippet(language: null));
      expect(c.text, 'antes\n```\nSELECT 1;\n```\ndepois');
    });

    test('a body with ``` gets a longer fence', () {
      expect(fencedSnippet('a ``` b', 'md'), '````md\na ``` b\n````');
    });
  });

  testWidgets('insert goes to the composer of the open screen and counts a '
      'use; copy puts the exact code in the clipboard', (tester) async {
    final db = memoryDatabase();
    String? clip;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clip = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    late WidgetRef ref;
    final text = TextEditingController(text: 'veja:');
    final focus = FocusNode();
    addTearDown(text.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseOverride(db)],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, r, _) {
                ref = r;
                return TextField(controller: text, focusNode: focus);
              },
            ),
          ),
        ),
      ),
    );
    await db.customStatement(
      "INSERT INTO workspaces (id, path, name) VALUES (1, '/a', 'a')",
    );
    final s = await ref
        .read(snippetsRepoProvider)
        .save(
          workspaceId: 1,
          name: 'Atrasados',
          body: 'SELECT 1;',
          language: 'sql',
        );
    final unregister = ref
        .read(composerTargetProvider)
        .register(ComposerTarget(controller: text, focusNode: focus));
    text.selection = const TextSelection.collapsed(offset: 5);

    final messenger = tester.state<ScaffoldMessengerState>(
      find.byType(ScaffoldMessenger),
    );
    await tester.runAsync(() => insertSnippet(ref, s, messenger: messenger));
    await tester.pump();
    expect(text.text, 'veja:\n\n```sql\nSELECT 1;\n```\n');
    expect(find.text('Snippet inserido: Atrasados'), findsOneWidget);
    expect((await ref.read(snippetsRepoProvider).byId(s.id))!.uses, 1);

    await tester.runAsync(() => copySnippet(ref, s, messenger: messenger));
    await tester.pumpAndSettle();
    expect(clip, 'SELECT 1;');
    expect(find.text('Snippet copiado: Atrasados'), findsOneWidget);
    final used = (await ref.read(snippetsRepoProvider).byId(s.id))!;
    expect(used.uses, 2);
    expect(used.lastUsedAt, isNotNull);

    // No composer on screen: the Prompt opens and takes it.
    unregister();
    ref.read(navigationProvider.notifier).go(AppSection.home);
    await tester.runAsync(() => insertSnippet(ref, s));
    expect(ref.read(navigationProvider), AppSection.prompt);
    expect(ref.read(pendingSnippetInsertProvider)?.id, s.id);
    await tester.pumpWidget(const SizedBox());
  });

  test('the last focused composer is the target', () {
    final targets = ComposerTargets();
    final a = ComposerTarget(
      controller: TextEditingController(),
      focusNode: FocusNode(),
    );
    final b = ComposerTarget(
      controller: TextEditingController(),
      focusNode: FocusNode(),
    );
    final offA = targets.register(a);
    targets.register(b);
    expect(targets.current, b);
    offA();
    expect(targets.current, b);
  });
}
