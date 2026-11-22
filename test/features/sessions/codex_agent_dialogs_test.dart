import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/codex/codex_agent_mapping.dart';
import 'package:promptorium/core/codex/codex_probe.dart';
import 'package:promptorium/core/providers/agent_registry.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/core/providers/provider_preferences.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/agents/agent_file.dart';
import 'package:promptorium/features/board/spec_run_provider.dart';
import 'package:promptorium/features/board/widgets/codex_subagents_dialog.dart';
import 'package:promptorium/features/sessions/agent_names.dart';
import 'package:promptorium/features/sessions/new_session_dialog.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';

/// SPEC-106 R8, R9: the agent in Nova sessão with the Codex and the
/// warning of a spec with subagents.
void main() {
  final flutterDev = AgentFile.parse(
    '---\nname: flutter-dev\ndescription: Dev\nmodel: sonnet\neffort: high\n'
    'tools: Read, Edit, Write, Bash, Grep, Glob\nmaxTurns: 40\n'
    'mcpServers:\n  - github\ncolor: amber\n---\nVocê é dev Flutter.\n',
  );

  testWidgets('R8: Nova sessão with the Codex shows the agent with "adaptado '
      '· N campos ignorados" and the detail; the hint has the fields', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(
      overrides: [
        providerFlowsProvider.overrideWithValue(
          ProviderFlows.defaults.copyWith('codex', {AppFlow.sessions}),
        ),
        databaseOverride(memoryDatabase()),
        providerAvailabilityProvider.overrideWith(
          (ref, id) async =>
              const ProviderAvailability(ProviderStatus.ready, 'Pronto'),
        ),
        agentListProvider.overrideWith(
          (ref, path) async => [
            AgentRef(
              name: 'flutter-dev',
              project: true,
              model: 'sonnet',
              effort: 'high',
              file: flutterDev,
            ),
          ],
        ),
      ],
    );
    addTearDown(c.dispose);
    final settings = c.read(appSettingsProvider.notifier);
    await settings.load();
    await settings.set(providerPreferenceKey(null), 'codex');
    await settings.set(
      codexModelsCacheKey,
      CodexModelsCache(
        version: '0.170.0',
        readAt: DateTime(2026, 11, 22),
        models: const [
          CodexModelInfo('gpt-6.1-terra', ['low', 'high'], ['text']),
          CodexModelInfo('gpt-6-luna', ['low'], ['text']),
        ],
      ).encode(),
    );
    await settings.set('codex.model.session', 'gpt-6-luna');
    await settings.set(codexAgentModelKey('sonnet'), 'gpt-6.1-terra');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: NewSessionDialog(initialAgent: 'flutter-dev'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('new-session-agent')), findsOneWidget);
    expect(find.byKey(const ValueKey('codex-agent-summary')), findsOneWidget);
    expect(find.text('adaptado'), findsOneWidget);
    expect(find.text('3 campos ignorados'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('codex-agent-detail')))
          .data,
      'Instruções aplicadas · sonnet → gpt-6.1-terra · workspace-write · '
      'maxTurns, mcpServers e color ignorados no Codex',
    );
    // The Codex model field keeps the run kind's (never "inherit (do
    // agente)", a Claude rule).
    expect(find.text('gpt-6-luna'), findsWidgets);
    expect(find.text('inherit (do agente)'), findsNothing);
    // The hint opens the field table (R7).
    final tip = tester.widget<Tooltip>(
      find.byKey(const ValueKey('codex-agent-summary')),
    );
    expect(tip.richMessage, isNotNull);
    expect(tester.takeException(), isNull);
  });

  group('R9: subagents on the Codex', () {
    test('the notice names them', () {
      expect(
        codexSubagentsNotice(['tester', 'docs']),
        'Esta spec define 2 subagentes (`tester`, `docs`). No Codex eles não '
        'rodam: a sessão principal faz o trabalho deles.',
      );
    });

    for (final (key, expected) in [
      ('codex-subagents-without', CodexSubagentsChoice.withoutSubagents),
      ('codex-subagents-claude', CodexSubagentsChoice.claude),
    ]) {
      testWidgets('the choice "$key" comes back to the run', (tester) async {
        CodexSubagentsChoice? got;
        const spec = Spec(
          issueCommentPending: false,
          hasPlan: false,
          inTray: false,
          kind: SpecKind.spec,
          id: 1,
          workspaceId: 1,
          code: 'SPEC-120',
          title: 'Carrinho',
          status: SpecStatus.approved,
          path: 'docs/specs/SPEC-120.md',
          stage: SpecStage.backlog,
          requirements: [],
          dependsOn: [],
          autoAdvance: false,
          reviewRounds: 0,
          gateResends: 0,
          rejectedHunks: 0,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async => got = await showDialog(
                    context: context,
                    builder: (_) => CodexSubagentsDialog(
                      spec: spec,
                      subagents: const ['tester', 'docs'],
                      agentLabel: 'flutter-dev · adaptado',
                    ),
                  ),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('abrir'));
        await tester.pumpAndSettle();
        expect(find.text('Subagentes não rodam no Codex'), findsOneWidget);
        expect(find.text('flutter-dev · adaptado'), findsOneWidget);
        expect(
          find.text('Codex · fixo até o fim desta execução'),
          findsOneWidget,
        );
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        expect(got, expected);
      });
    }
  });
}
