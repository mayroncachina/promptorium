import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/secrets/secret_guard.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/settings/secrets_view.dart';
import 'package:promptorium/features/settings/settings_sections.dart';

import '../../helpers/test_db.dart';

/// SPEC-085 R12–R15: Configurações › Vigia de segredos.
void main() {
  testWidgets('motor, where it applies, the 11 rules; turning it off asks '
      'first', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        gitleaksVersionProvider.overrideWith((ref) async => '8.21.2'),
      ],
    );
    addTearDown(c.dispose);
    await tester.runAsync(() => c.read(appSettingsProvider.notifier).load());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: SecretsSettingsView()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Regras do Promptorium'), findsOneWidget);
    expect(
      find.textContaining('8.21.2 encontrado', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('REGRAS · 11'), findsOneWidget);
    expect(find.text('Commits e pushes do app'), findsOneWidget);
    expect(find.text('Commit manual na tela Código'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('secrets-rule-stripe')));
    await tester.pumpAndSettle();
    expect(c.read(appSettingsProvider)['secrets.rule.stripe'], '0');

    await tester.tap(find.byKey(const ValueKey('secrets-enabled')));
    await tester.pumpAndSettle();
    expect(find.text('Desligar o Vigia de segredos?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('secrets-off-confirm')));
    await tester.pumpAndSettle();
    expect(c.read(appSettingsProvider)[SecretSettingKeys.enabled], '0');
    expect(
      sectionChanged(
        SettingsSection.secrets,
        c.read(appSettingsProvider),
        null,
      ),
      isTrue,
    );
    expect(SettingsSection.secrets.matches('gitleaks'), isTrue);
  });
}
