import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/settings/git_accounts_view.dart';
import 'package:promptorium/features/settings/settings_screen.dart';
import 'package:promptorium/features/settings/settings_sections.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';

void main() {
  testWidgets('seção GitHub e GitLab: dois cartões "Não conectado"', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(
      overrides: [databaseOverride(memoryDatabase())],
    );
    addTearDown(c.dispose);
    await tester.runAsync(() => c.read(appSettingsProvider.notifier).load());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: SettingsScreen()),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('settings-nav-gitAccounts')));
    await tester.pump();
    expect(find.text('GitHub'), findsNothing); // titles are upper-cased
    expect(find.text('GITHUB'), findsOneWidget);
    expect(find.text('GITLAB'), findsOneWidget);
    expect(find.text('Não conectado'), findsNWidgets(2));
    expect(find.textContaining('Conectado como'), findsNothing);
  });

  testWidgets('mostra o usuário quando há conta salva', (tester) async {
    final c = ProviderContainer(
      overrides: [databaseOverride(memoryDatabase())],
    );
    addTearDown(c.dispose);
    await tester.runAsync(() async {
      await c.read(appSettingsProvider.notifier).load();
      await c
          .read(appSettingsProvider.notifier)
          .set(GitProvider.github.loginKey, 'octocat');
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: Column(
              children: [
                GitAccountCard(provider: GitProvider.github),
                GitAccountCard(provider: GitProvider.gitlab),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('Conectado como octocat'), findsOneWidget);
    expect(find.text('Não conectado'), findsOneWidget);
    expect(
      sectionChanged(
        SettingsSection.gitAccounts,
        c.read(appSettingsProvider),
        null,
      ),
      isTrue,
    );
  });
}
