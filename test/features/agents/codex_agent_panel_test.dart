import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/codex/codex_probe.dart';
import 'package:promptorium/core/providers/provider_preferences.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/agents/codex_agent.dart';

import 'agents_screen_test.dart' show entries, pumpAgents, pumpFor, previewText;

/// SPEC-106 R7: the "No Codex" panel of the agent editor.
void main() {
  String target(WidgetTester tester, String key) {
    final row = find.byKey(ValueKey('codex-agent-field-$key'));
    final texts = tester
        .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
        .map((t) => t.data)
        .toList();
    return texts.join(' | ');
  }

  testWidgets('shows applied, adapted and ignored, follows the edits and '
      'never changes the .md', (tester) async {
    final c = await pumpAgents(tester, size: const Size(1400, 900));
    final settings = c.read(appSettingsProvider.notifier);
    await tester.runAsync(() async {
      await settings.set(
        codexModelsCacheKey,
        CodexModelsCache(
          version: '0.170.0',
          readAt: DateTime(2026, 11, 22),
          models: const [
            CodexModelInfo('gpt-6.1-terra', ['low', 'high'], ['text']),
          ],
        ).encode(),
      );
      await settings.set(codexAgentModelKey('sonnet'), 'gpt-6.1-terra');
    });
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('codex-agent-panel')), findsOneWidget);
    // implementer: sonnet, writes, permissionMode acceptEdits, hooks.
    expect(
      target(tester, 'prompt'),
      'prompt | 2 linhas | → | developerInstructions | aplicado',
    );
    expect(target(tester, 'model'), contains('gpt-6.1-terra | adaptado'));
    expect(
      target(tester, 'tools'),
      contains('workspace-write · confirma edições | adaptado'),
    );
    expect(target(tester, 'hooks'), endsWith('ignorado no Codex'));
    expect(target(tester, 'permissionMode'), endsWith('ignorado no Codex'));
    final before = previewText(tester);

    // Live: without the write tools it becomes read-only.
    for (final t in ['Edit', 'Write', 'Bash']) {
      await tester.tap(find.byKey(ValueKey('agent-tool-$t')));
      await pumpFor(tester, 3);
    }
    expect(target(tester, 'tools'), contains('só leitura · read-only'));
    // Opus has no equivalent: the run kind's model.
    await tester.tap(find.byKey(const ValueKey('agent-model-opus')));
    await pumpFor(tester, 3);
    expect(target(tester, 'model'), contains('padrão do Codex | adaptado'));
    // The panel writes nothing: only the form changed the preview, and
    // the file on "disk" (the entry) is the same.
    expect(previewText(tester), isNot(before));
    expect(previewText(tester), isNot(contains('codex')));
    expect(entries.first.file.model, 'sonnet');
    expect(tester.takeException(), isNull);
  });
}
