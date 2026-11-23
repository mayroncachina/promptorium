import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/codex/codex_agent_mapping.dart';
import 'package:promptorium/core/codex/codex_probe.dart';
import 'package:promptorium/core/providers/provider_preferences.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/settings/codex_agent_models.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';

/// SPEC-106 R6 and P1: Configurações → Provedores → Codex, "Modelos
/// equivalentes para agentes".
void main() {
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    List<CodexModelInfo>? models,
  }) async {
    tester.view.physicalSize = const Size(1000, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(
      overrides: [databaseOverride(memoryDatabase())],
    );
    addTearDown(c.dispose);
    final settings = c.read(appSettingsProvider.notifier);
    await tester.runAsync(() async {
      await settings.load();
      if (models != null) {
        await settings.set(
          codexModelsCacheKey,
          CodexModelsCache(
            version: '0.170.0',
            readAt: DateTime(2026, 11, 22),
            models: models,
          ).encode(),
        );
      }
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: SingleChildScrollView(child: CodexAgentModelsCard()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return c;
  }

  String? selected(WidgetTester tester, String key) => tester
      .widget<DropdownButtonFormField<String>>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(DropdownButtonFormField<String>),
        ),
      )
      .initialValue;

  const catalog = [
    CodexModelInfo('gpt-6.2-sol', ['low', 'medium', 'high', 'ultra'], []),
    CodexModelInfo('gpt-6.1-terra', ['low', 'medium', 'high'], []),
    CodexModelInfo('gpt-6-luna', ['low', 'high'], []),
  ];

  testWidgets('lists the models and efforts of model/list, suggests by '
      'position without applying, and saves in app_settings', (tester) async {
    final c = await pump(tester, models: catalog);
    expect(find.text('model/list · Codex 0.170.0 · 3 modelos'), findsOneWidget);
    // P1: visible suggestion, nothing saved.
    expect(
      find.byKey(const ValueKey('codex-agent-suggestion')),
      findsOneWidget,
    );
    expect(selected(tester, 'codex-agent-model-opus'), 'gpt-6.2-sol');
    expect(selected(tester, 'codex-agent-model-sonnet'), 'gpt-6.1-terra');
    expect(selected(tester, 'codex-agent-model-haiku'), 'gpt-6-luna');
    expect(find.text('sugerido'), findsNWidgets(3));
    final s = c.read(appSettingsProvider);
    expect(s.keys.where((k) => k.startsWith('codex.agentModel.')), isEmpty);
    expect(CodexAgentTable.fromSettings(s).models, isEmpty);
    // fable has no equivalent; inherit = the run kind's model.
    expect(selected(tester, 'codex-agent-model-fable'), '');
    expect(find.text('sem equivalente'), findsOneWidget);
    expect(find.text('modelo do tipo de execução'), findsOneWidget);
    // P2: xhigh and max = the highest of the model, with the cost warning.
    expect(selected(tester, 'codex-agent-effort-max'), codexHighestEffort);
    expect(selected(tester, 'codex-agent-effort-high'), 'high');
    expect(find.text('ultra gasta mais cota'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('codex-agent-use-suggestion')));
    await tester.pumpAndSettle();
    final after = c.read(appSettingsProvider);
    expect(after[codexAgentModelKey('opus')], 'gpt-6.2-sol');
    expect(after[codexAgentModelKey('sonnet')], 'gpt-6.1-terra');
    expect(after[codexAgentModelKey('haiku')], 'gpt-6-luna');
    expect(find.byKey(const ValueKey('codex-agent-suggestion')), findsNothing);

    // One row by hand: the selector offers only model/list ids.
    await tester.tap(find.byKey(const ValueKey('codex-agent-model-fable')));
    await tester.pumpAndSettle();
    expect(find.text('opus'), findsOneWidget); // the row label only
    await tester.tap(
      find
          .byKey(const ValueKey('codex-agent-model-fable-item-gpt-6-luna'))
          .last,
    );
    await tester.pumpAndSettle();
    expect(
      c.read(appSettingsProvider)[codexAgentModelKey('fable')],
      'gpt-6-luna',
    );

    // An effort by hand.
    await tester.tap(find.byKey(const ValueKey('codex-agent-effort-low')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('codex-agent-effort-low-item-medium')).last,
    );
    await tester.pumpAndSettle();
    expect(c.read(appSettingsProvider)[codexAgentEffortKey('low')], 'medium');
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Escolher um por um" hides the suggestion; with no catalog '
      'nothing is fixed in the code', (tester) async {
    final c = await pump(tester, models: catalog);
    await tester.tap(find.byKey(const ValueKey('codex-agent-one-by-one')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('codex-agent-suggestion')), findsNothing);
    expect(selected(tester, 'codex-agent-model-opus'), '');
    expect(
      c
          .read(appSettingsProvider)
          .keys
          .where(
            (k) =>
                k.startsWith('codex.agentModel.') &&
                k != codexAgentSuggestionKey,
          ),
      isEmpty,
    );
  });

  testWidgets('no model/list yet: only "padrão do Codex"', (tester) async {
    await pump(tester);
    expect(
      find.byKey(const ValueKey('codex-agent-no-catalog')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('codex-agent-suggestion')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('codex-agent-model-opus')));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is DropdownMenuItem<String> &&
            '${w.key}'.contains('codex-agent-model-opus-item-'),
      ),
      findsWidgets,
    );
    expect(find.textContaining('gpt'), findsNothing);
  });
}
