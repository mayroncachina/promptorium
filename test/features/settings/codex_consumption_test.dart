import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/codex/codex_probe.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/core/providers/provider_preferences.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/settings/settings_screen.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';

void main() {
  testWidgets('SPEC-094 R8, R9: Consumo → Codex lists the saved model/list '
      'with version and time; a vanished model shows as unavailable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var reads = 0;
    final c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        providerAvailabilityProvider.overrideWith((ref, id) async {
          if (id == 'codex') reads++;
          return const ProviderAvailability(ProviderStatus.ready, 'Pronto');
        }),
      ],
    );
    addTearDown(c.dispose);
    final settings = c.read(appSettingsProvider.notifier);
    await tester.runAsync(() async {
      await settings.load();
      await settings.set(
        codexModelsCacheKey,
        CodexModelsCache(
          version: '0.170.0',
          readAt: DateTime(2026, 11, 21, 14, 2),
          models: const [
            CodexModelInfo('gpt-6.2-sol', ['low', 'medium'], ['text', 'image']),
            CodexModelInfo('gpt-6-luna', ['low'], ['text']),
          ],
        ).encode(),
      );
      await settings.set('codex.model.conversation', 'gpt-5.9-sol');
      await settings.set('codex.model.session', 'gpt-6.2-sol');
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: SettingsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('consumption-tab-codex')));
    await tester.pumpAndSettle();

    expect(
      find.text('Lista lida do Codex 0.170.0 às 14:02 · 2 modelos'),
      findsOneWidget,
    );
    // Models and efforts come from model/list; no Claude alias.
    String? selected(String key) => tester
        .widget<DropdownButtonFormField<String>>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(DropdownButtonFormField<String>),
          ),
        )
        .initialValue;
    expect(selected('codex-model-session'), 'gpt-6.2-sol');
    expect(selected('codex-model-conversation'), 'inherit');
    await tester.tap(find.byKey(const ValueKey('codex-model-session')));
    await tester.pumpAndSettle();
    expect(find.text('gpt-6-luna'), findsWidgets);
    expect(find.text('opus'), findsNothing);
    await tester.tap(find.text('gpt-6-luna').last);
    await tester.pumpAndSettle();
    expect(c.read(appSettingsProvider)['codex.model.session'], 'gpt-6-luna');
    await tester.tap(find.byKey(const ValueKey('codex-effort-session')));
    await tester.pumpAndSettle();
    expect(find.text('low'), findsWidgets);
    await tester.tap(find.text('low').last);
    await tester.pumpAndSettle();
    expect(c.read(appSettingsProvider)['codex.effort.session'], 'low');
    // R9: the vanished model, and the default used instead.
    expect(
      find.byKey(const ValueKey('codex-model-missing-conversation')),
      findsOneWidget,
    );
    expect(
      find.textContaining('gpt-5.9-sol salvo antes: indisponível nesta versão'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('codex-model-missing-session')),
      findsNothing,
    );
    // R11: flows not released yet carry the tag (the planner runs on the
    // Codex since SPEC-100 R8), and the capabilities card says what the
    // Codex does here.
    expect(
      find.byKey(const ValueKey('codex-kind-locked-planner')),
      findsNothing,
    );
    expect(find.text('O QUE O CODEX FAZ NESTE APP'), findsOneWidget);
    expect(find.text('Só Claude Code'), findsWidgets);

    // "Atualizar lista" reads the catalog again (a new detection).
    final before = reads;
    await tester.tap(find.byKey(const ValueKey('codex-models-refresh')));
    await tester.pumpAndSettle();
    expect(reads, greaterThan(before));
  });
}
