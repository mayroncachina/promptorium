import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/providers/agent_registry.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/core/system/worktree_launcher.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/activities/activity.dart';
import 'package:promptorium/features/activities/widgets/activity_panel.dart';
import 'package:promptorium/features/prompt/widgets/conversation_list.dart';
import 'package:promptorium/features/settings/codex_consumption.dart';
import 'package:promptorium/ui/providers/provider_logos.dart';
import 'package:promptorium/ui/shell/status_footer.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';

/// SPEC-096 T1: Codex released in Prompt and Sessões, its state and login
/// orientation, the emergency switch and the provider in the lists.
void main() {
  const loginPending = ProviderAvailability(
    ProviderStatus.loginRequired,
    'Execute codex login no terminal e depois verifique novamente.',
    version: '0.170.0',
  );

  Future<ProviderContainer> pump(
    WidgetTester tester,
    Widget child, {
    ProviderAvailability codex = loginPending,
    WorktreeLauncher? launcher,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        providerAvailabilityProvider.overrideWith(
          (ref, id) async => id == 'codex'
              ? codex
              : const ProviderAvailability(ProviderStatus.ready, 'Pronto'),
        ),
        if (launcher != null)
          worktreeLauncherProvider.overrideWithValue(launcher),
      ],
    );
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets('R2: Provedores shows the login pending with "codex login", '
      'Abrir terminal opens a plain shell (never the login itself)', (
    tester,
  ) async {
    final opened = <(String, List<String>)>[];
    await pump(
      tester,
      const SingleChildScrollView(child: CodexStatusCard()),
      launcher: WorktreeLauncher(
        which: (_) async => true,
        start: (exe, args, cwd) async => opened.add((exe, args)),
      ),
    );
    expect(find.text('Codex 0.170.0 · login pendente'), findsOneWidget);
    expect(find.byKey(const ValueKey('codex-login-hint')), findsOneWidget);
    expect(
      find.textContaining('não faz login nem lê suas credenciais'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('codex-open-terminal')));
    await tester.pumpAndSettle();
    expect(opened, hasLength(1));
    // A shell only: the person runs `codex login`.
    expect(opened.single.$2, isEmpty);
  });

  testWidgets('R1 + P1: flows chips (Prompt and Sessões on, the others with '
      'the spec) and "Desligar o Codex" turns every Codex flow off', (
    tester,
  ) async {
    final c = await pump(
      tester,
      const SingleChildScrollView(child: CodexStatusCard()),
      codex: const ProviderAvailability(
        ProviderStatus.ready,
        'ok',
        version: '0.170.0',
      ),
    );
    expect(find.byKey(const ValueKey('codex-open-terminal')), findsNothing);
    expect(find.text('Prompt'), findsOneWidget);
    expect(find.text('Sessões'), findsOneWidget);
    // SPEC-101 R1: Executar spec is on for the Codex.
    expect(find.text('Executar spec'), findsOneWidget);
    expect(find.text('Executar spec · SPEC-101'), findsNothing);
    expect(find.byKey(const ValueKey('codex-flow-compare')), findsOneWidget);
    expect(
      c.read(providerFlowsProvider).allows('codex', AppFlow.prompt),
      isTrue,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('codex-kill-switch')));
    await tester.tap(find.byKey(const ValueKey('codex-kill-switch')));
    await tester.pumpAndSettle();
    expect(c.read(appSettingsProvider)[codexKillSwitchKey], '1');
    expect(c.read(providerFlowsProvider).anyFor('codex'), isFalse);
    expect(
      c.read(providerFlowsProvider).allows('claude', AppFlow.prompt),
      isTrue,
    );
  });

  testWidgets('R2: footer orients the Codex login and the switch hides it', (
    tester,
  ) async {
    final c = await pump(
      tester,
      const Align(alignment: Alignment.bottomCenter, child: StatusFooter()),
    );
    await tester.tap(find.byKey(const ValueKey('footer-provider-selector')));
    await tester.pumpAndSettle();
    expect(find.text('Codex · login pendente'), findsOneWidget);
    expect(find.text('rode codex login no terminal'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('footer-provider-copy-codex')),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await c.read(appSettingsProvider.notifier).set(codexKillSwitchKey, '1');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('footer-provider-selector')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('footer-provider-codex')), findsNothing);
    expect(
      find.byKey(const ValueKey('footer-provider-claude')),
      findsOneWidget,
    );
  });

  test('R3: provider and model labels', () {
    expect(providerModelLabel('codex', 'gpt-6.2-sol'), 'Codex · gpt-6.2-sol');
    expect(providerModelLabel('codex', 'inherit'), 'Codex · modelo padrão');
    expect(providerModelLabel('claude', 'sonnet'), 'Claude Code · Sonnet');
    Conversation conv(String provider, String model) => Conversation(
      id: 1,
      workspaceId: 1,
      title: 't',
      provider: provider,
      model: model,
      createdAt: DateTime(2026, 11, 21),
      mode: 'ask',
      tokensIn: 0,
      tokensOut: 0,
      costUsd: 0,
      messageCount: 3,
    );
    // Codex ids are shown as they are (no "Gpt-6.2-sol").
    expect(
      conversationMeta(conv('codex', 'gpt-6.2-sol')),
      'gpt-6.2-sol · 3 mensagens',
    );
    expect(conversationMeta(conv('claude', 'sonnet')), 'Sonnet · 3 mensagens');
  });

  testWidgets('R3: Atividades show "Codex · model" for a Codex session', (
    tester,
  ) async {
    const a = Activity(
      id: 'session:x',
      workspaceId: 1,
      workspaceName: 'w',
      kind: ActivityKind.spec,
      column: ActivityColumn.running,
      pose: ActivityPose.read,
      title: 'Ledger',
      subtitle: 'rodando',
      status: 'Editando',
      model: 'gpt-6.2-sol',
      provider: 'codex',
      seed: 'session:x',
      sessionId: 'x',
    );
    await pump(tester, ActivityPanel(activity: a, now: DateTime(2026, 11, 21)));
    expect(find.textContaining('Codex · gpt-6.2-sol'), findsOneWidget);
  });
}
