import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/providers/agent_registry.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/core/providers/provider_preferences.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/sessions/new_session_dialog.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';

Future<ProviderContainer> _open(
  WidgetTester tester, {
  ProviderFlows flows = ProviderFlows.defaults,
  String? sandboxWarning,
}) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final c = ProviderContainer(
    overrides: [
      providerFlowsProvider.overrideWithValue(flows),
      databaseOverride(memoryDatabase()),
      providerAvailabilityProvider.overrideWith(
        (ref, id) async => ProviderAvailability(
          ProviderStatus.ready,
          'Pronto',
          sandboxWarning: id == 'codex' ? sandboxWarning : null,
        ),
      ),
    ],
  );
  addTearDown(c.dispose);
  await c.read(appSettingsProvider.notifier).load();
  await c
      .read(appSettingsProvider.notifier)
      .set(providerPreferenceKey(null), 'codex');
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
  return c;
}

Finder _key(String k) => find.byKey(ValueKey(k));

void main() {
  testWidgets('SPEC-094 R11: Codex shows "Só Claude Code" on the agent, with '
      'the reason', (tester) async {
    await _open(
      tester,
      flows: ProviderFlows.defaults.copyWith('codex', {AppFlow.sessions}),
    );
    expect(_key('new-session-agent'), findsNothing);
    expect(_key('new-session-agent-only'), findsOneWidget);
    expect(find.text('O Codex não lê .claude/agents.'), findsOneWidget);
    expect(_key('new-session-flow-locked'), findsNothing);
  });

  testWidgets('SPEC-094 R12: a locked flow never starts and offers Claude', (
    tester,
  ) async {
    // Codex switched off ("Desligar o Codex", SPEC-096 P1).
    await _open(tester, flows: ProviderFlows.defaults.copyWith('codex', {}));
    expect(_key('new-session-flow-locked'), findsOneWidget);
    expect(find.textContaining('Sessões ainda não roda com o Codex'), findsOne);
    await tester.tap(_key('new-session-provider'));
    await tester.pumpAndSettle();
    expect(find.text('Codex · Só Claude Code por enquanto'), findsWidgets);
    await tester.tap(find.text('Claude Code').last);
    await tester.pumpAndSettle();
    expect(_key('new-session-flow-locked'), findsNothing);
    expect(_key('new-session-agent'), findsOneWidget);
  });

  testWidgets('SPEC-094 R7a: without sandbox only YOLO in a worktree, with '
      'the command and "Verificar de novo"', (tester) async {
    final c = await _open(
      tester,
      flows: ProviderFlows.defaults.copyWith('codex', {AppFlow.sessions}),
      sandboxWarning: 'bubblewrap sem user namespaces',
    );
    expect(_key('new-session-no-sandbox'), findsOneWidget);
    expect(
      find.textContaining('Sandbox do Codex indisponível'),
      findsOneWidget,
    );
    expect(
      find.textContaining('apparmor_restrict_unprivileged_userns=0'),
      findsOneWidget,
    );
    await tester.tap(_key('new-session-mode'));
    await tester.pumpAndSettle();
    // Perguntar / Editar / Planejar are not offered; YOLO is.
    expect(
      find.textContaining('editar — escreve com confirmação'),
      findsNothing,
    );
    expect(find.textContaining('planejar — o sandbox'), findsNothing);
    await tester.tap(find.textContaining('YOLO').last);
    await tester.pumpAndSettle();
    final mode = tester.widget<DropdownButtonFormField<ClaudePermissionMode>>(
      _key('new-session-mode'),
    );
    expect(mode.initialValue, ClaudePermissionMode.skipPermissions);
    // "Verificar de novo" redoes the detection (no quota: no turn).
    var checks = 0;
    c.listen(
      providerAvailabilityProvider('codex'),
      (_, _) => checks++,
      fireImmediately: false,
    );
    await tester.tap(find.text('Verificar de novo'));
    await tester.pumpAndSettle();
    expect(checks, greaterThan(0));
  });
}
