import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/providers/agent_registry.dart'
    show providerFlowsProvider, ProviderFlows, AppFlow;
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
          providerFlowsProvider.overrideWithValue(
            ProviderFlows.defaults.copyWith('codex', {...AppFlow.values}),
          ),
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
          providerFlowsProvider.overrideWithValue(
            ProviderFlows.defaults.copyWith('codex', {...AppFlow.values}),
          ),
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
          providerFlowsProvider.overrideWithValue(
            ProviderFlows.defaults.copyWith('codex', {...AppFlow.values}),
          ),
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

  testWidgets('SPEC-094 R10, R7a: incompatible Codex with the orientation, '
      'newer version warns, no sandbox shows the command; Verificar de novo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var codex = const ProviderAvailability(
      ProviderStatus.incompatible,
      'Versão instalada 0.168.0, mínimo 0.170. Atualize o Codex CLI'
      ': codex update.',
      version: '0.168.0',
    );
    var checks = 0;
    final c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        providerAvailabilityProvider.overrideWith((ref, id) async {
          if (id != 'codex') {
            return const ProviderAvailability(ProviderStatus.ready, 'Pronto');
          }
          checks++;
          return codex;
        }),
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
    await tester.tap(find.byKey(const ValueKey('footer-provider-selector')));
    await tester.pumpAndSettle();
    expect(find.text('Codex · incompatível'), findsOneWidget);
    expect(find.textContaining('Versão instalada 0.168.0'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('footer-provider-copy-codex')),
      findsOneWidget,
    );
    final before = checks;
    codex = const ProviderAvailability(
      ProviderStatus.ready,
      'Pronto',
      version: '0.172.0',
      warning: 'versão mais nova que a testada (0.170)',
      sandboxWarning: 'bubblewrap',
    );
    await tester.tap(
      find.byKey(const ValueKey('footer-provider-recheck-codex')),
    );
    await tester.pumpAndSettle();
    expect(checks, greaterThan(before));
    await tester.tap(find.byKey(const ValueKey('footer-provider-selector')));
    await tester.pumpAndSettle();
    expect(find.text('Codex · conectado'), findsOneWidget);
    expect(find.text('versão mais nova que a testada (0.170)'), findsOneWidget);
    expect(
      find.textContaining('Sandbox do Codex indisponível'),
      findsOneWidget,
    );
    expect(
      find.textContaining('apparmor_restrict_unprivileged_userns=0'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('footer-provider-copy-codex')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
