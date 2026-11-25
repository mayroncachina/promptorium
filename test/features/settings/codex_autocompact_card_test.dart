import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/run_prefs.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/settings/codex_autocompact_card.dart';

import '../../helpers/test_db.dart';

/// SPEC-107 P1: Configurações → Consumo → Codex has its own threshold.
void main() {
  testWidgets('the Codex threshold never changes Claude\'s', (tester) async {
    final db = memoryDatabase();
    final c = ProviderContainer(overrides: [databaseOverride(db)]);
    await c.read(appSettingsProvider.notifier).load();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await db.close();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(width: 900, child: CodexAutocompactCard()),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(c.read(runPrefsProvider).codexAutocompact, 'auto');
    expect(find.textContaining('model_auto_compact_token_limit'), findsOne);
    await tester.tap(
      find.byKey(const ValueKey('settings-codex-autocompact-300k')),
    );
    await tester.pump();
    final prefs = c.read(runPrefsProvider);
    expect(prefs.codexAutocompact, '300k');
    expect(prefs.autocompact, RunPrefs.defaultAutocompact);
  });
}
