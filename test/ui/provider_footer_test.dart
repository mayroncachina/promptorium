import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/providers/agent_registry.dart'
    show codexEnabledProvider;
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/core/providers/provider_preferences.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/sessions/new_session_dialog.dart';
import 'package:promptorium/ui/shell/status_footer.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../helpers/test_db.dart';

void main() {
  testWidgets(
    'footer selects Codex, persists the global default and removes Claude usage',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = ProviderContainer(
        overrides: [
          codexEnabledProvider.overrideWithValue(true),
          databaseOverride(memoryDatabase()),
          providerAvailabilityProvider.overrideWith(
            (ref, id) async =>
                const ProviderAvailability(ProviderStatus.ready, 'Pronto'),
          ),
        ],
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: StatusFooter(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Claude Code CLI conectado'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('footer-provider-selector')));
      await tester.pumpAndSettle();
      expect(find.text('Padrão global'), findsOneWidget);
      expect(find.text('Aplicar às novas execuções'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('footer-provider-acp-gemini-cli')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('footer-provider-codex')));
      await tester.pumpAndSettle();
      expect(c.read(activeAgentProvider), 'codex');
      expect(
        await c.read(appSettingsRepoProvider).get(providerPreferenceKey(null)),
        'codex',
      );
      expect(find.text('Codex CLI conectado'), findsOneWidget);
      expect(find.text('Consumo indisponível'), findsOneWidget);
      expect(find.text('Uso 5h'), findsNothing);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: NewSessionDialog()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const ValueKey('new-session-provider')),
            )
            .initialValue,
        'codex',
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const ValueKey('new-session-model')),
            )
            .initialValue,
        'inherit',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
    },
  );

  testWidgets(
    'unavailable provider shows correction; Escape cancels; narrow footer fits',
    (tester) async {
      tester.view.physicalSize = const Size(600, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = ProviderContainer(
        overrides: [
          codexEnabledProvider.overrideWithValue(true),
          databaseOverride(memoryDatabase()),
          providerAvailabilityProvider.overrideWith(
            (ref, id) async => ProviderAvailability(
              id == 'codex'
                  ? ProviderStatus.loginRequired
                  : ProviderStatus.ready,
              'Execute codex login',
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: StatusFooter(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('footer-provider-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('footer-provider-codex')));
      await tester.pumpAndSettle();
      expect(find.text('Execute codex login'), findsOneWidget);
      expect(c.read(activeAgentProvider), 'claude');
      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('footer-provider-selector')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(c.read(activeAgentProvider), 'claude');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
    },
  );
  testWidgets(
    'keyboard selects Codex and a late Claude diagnostic cannot replace it',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final delayed = Completer<ProviderAvailability>();
      final c = ProviderContainer(
        overrides: [
          codexEnabledProvider.overrideWithValue(true),
          databaseOverride(memoryDatabase()),
          providerAvailabilityProvider.overrideWith(
            (ref, id) => id == 'claude'
                ? delayed.future
                : Future.value(
                    const ProviderAvailability(ProviderStatus.ready, 'Pronto'),
                  ),
          ),
        ],
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: StatusFooter(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Aplicar às novas execuções'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(c.read(activeAgentProvider), 'codex');
      delayed.complete(
        const ProviderAvailability(
          ProviderStatus.loginRequired,
          'Claude sem login',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Codex CLI conectado'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(Duration.zero);
    },
  );
}
