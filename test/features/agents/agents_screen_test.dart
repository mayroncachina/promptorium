import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/agents/agent_file.dart';
import 'package:promptorium/features/agents/agent_repository.dart';
import 'package:promptorium/features/agents/agents_screen.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';
import '../prompt/prompt_test_utils.dart' show addWorkspace;

const home = '/home/u';
const wsPath = '/work/repo';

AgentEntry entry(
  AgentScope scope,
  String src, {
  bool overrides = false,
  bool overridden = false,
}) {
  final f = AgentFile.parse(src);
  final dir = scope == AgentScope.global
      ? '$home/.claude/agents'
      : '$wsPath/.claude/agents';
  return AgentEntry(
    scope: scope,
    path: '$dir/${f.name}.md',
    file: f,
    overridesGlobal: overrides,
    overriddenByProject: overridden,
  );
}

final entries = [
  entry(
    AgentScope.global,
    '---\nname: implementer\ndescription: Implementa tarefas a partir de uma '
    'spec aprovada, com testes.\ntools: Read, Edit, Write, Bash, Glob, Grep\n'
    'model: sonnet\npermissionMode: acceptEdits\nhooks:\n  x: 1\n---\n\n'
    'Você é um engenheiro Flutter sênior.\nLeia a spec vinculada antes.\n',
  ),
  entry(
    AgentScope.global,
    '---\nname: reviewer\ndescription: Revisa diffs\nmodel: opus\n---\nR\n',
    overridden: true,
  ),
  entry(
    AgentScope.project,
    '---\nname: reviewer\ndescription: Revisor do projeto\nmodel: haiku\n---\nP\n',
    overrides: true,
  ),
];

Future<ProviderContainer> pumpAgents(
  WidgetTester tester, {
  Size size = const Size(1100, 700),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = memoryDatabase();
  await addWorkspace(db, wsPath);
  final container = ProviderContainer(
    overrides: [
      databaseOverride(db),
      agentHomeProvider.overrideWithValue(home),
      agentEntriesProvider.overrideWith((ref, ws) async => entries),
      mcpServerNamesProvider.overrideWith(
        (ref, ws) async => ['context7', 'youtrack'],
      ),
    ],
  );
  await container.read(appSettingsProvider.notifier).load();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: AgentsScreen()),
      ),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(Duration.zero);
  });
  await pumpFor(tester);
  return container;
}

Future<void> pumpFor(WidgetTester tester, [int times = 10]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

String previewText(WidgetTester tester) => tester
    .widget<SelectableText>(find.byKey(const ValueKey('agent-preview')))
    .textSpan!
    .toPlainText();

void main() {
  testWidgets('list groups, override marks and editor render without overflow '
      'at 1100×700', (tester) async {
    await pumpAgents(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Globais'), findsOneWidget);
    expect(find.text('Projeto · repo'), findsOneWidget);
    expect(find.text('sobrescreve o global'), findsOneWidget);
    expect(find.text('sobrescrito no projeto'), findsOneWidget);
    // First agent selected.
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('agent-title'))).data,
      'implementer',
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('agent-path'))).data,
      '~/.claude/agents/implementer.md',
    );
    expect(previewText(tester), entries.first.file.serialize().trimRight());
    expect(find.text('6 de 8'), findsOneWidget);
    // Scroll to the bottom: still no overflow.
    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -2000),
    );
    await pumpFor(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('toggling a tool updates the live preview', (tester) async {
    await pumpAgents(tester);
    expect(
      previewText(tester),
      contains('tools: Read, Edit, Write, Bash, Glob, Grep\n'),
    );
    await tester.tap(find.byKey(const ValueKey('agent-tool-WebFetch')));
    await pumpFor(tester, 3);
    expect(
      previewText(tester),
      contains('tools: Read, Edit, Write, Bash, Glob, Grep, WebFetch\n'),
    );
    expect(find.text('7 de 8'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('agent-tool-Bash')));
    await pumpFor(tester, 3);
    expect(
      previewText(tester),
      contains('tools: Read, Edit, Write, Glob, Grep, WebFetch\n'),
    );
    // Unknown field kept in the preview; model / permission changes too.
    await tester.tap(find.byKey(const ValueKey('agent-model-opus')));
    await tester.tap(find.byKey(const ValueKey('agent-perm-plan')));
    await pumpFor(tester, 3);
    final p = previewText(tester);
    expect(p, contains('model: opus\n'));
    expect(p, contains('permissionMode: plan\n'));
    expect(p, contains('hooks:\n  x: 1\n'));
    // MCP chip from the config names.
    await tester.ensureVisible(
      find.byKey(const ValueKey('agent-mcp-youtrack')),
    );
    await pumpFor(tester, 3);
    await tester.tap(find.byKey(const ValueKey('agent-mcp-youtrack')));
    await pumpFor(tester, 3);
    expect(previewText(tester), contains('mcpServers:\n  - youtrack\n'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('project agent, scope switch and new draft', (tester) async {
    final c = await pumpAgents(tester);
    await tester.tap(find.byKey(const ValueKey('agent-project-reviewer')));
    await pumpFor(tester);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('agent-path'))).data,
      '.claude/agents/reviewer.md',
    );
    await tester.tap(find.byKey(const ValueKey('agent-scope-global')));
    await pumpFor(tester, 3);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('agent-path'))).data,
      '~/.claude/agents/reviewer.md',
    );

    c.read(selectedAgentProvider.notifier).newDraft();
    await pumpFor(tester);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('agent-title'))).data,
      'novo-agente',
    );
    await tester.enterText(find.byKey(const ValueKey('agent-name')), 'tester');
    await tester.enterText(
      find.byKey(const ValueKey('agent-description')),
      'Escreve testes',
    );
    await tester.tap(find.byKey(const ValueKey('agent-tool-Read')));
    await pumpFor(tester, 3);
    expect(
      previewText(tester),
      '---\nname: tester\ndescription: Escreve testes\ntools: Read\n---',
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('agent-path'))).data,
      '.claude/agents/tester.md',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Testar em sessão opens Nova sessão with the agent and its '
      'permission mode preselected', (tester) async {
    await pumpAgents(tester);
    await tester.tap(find.byKey(const ValueKey('agent-test')));
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('new-session-dialog')), findsOneWidget);
    final agent = tester.widget<DropdownButtonFormField<String?>>(
      find.byKey(const ValueKey('new-session-agent')),
    );
    expect(agent.initialValue, 'implementer');
    final mode = tester.widget<DropdownButtonFormField<ClaudePermissionMode>>(
      find.byKey(const ValueKey('new-session-mode')),
    );
    expect(mode.initialValue, ClaudePermissionMode.acceptEdits);
    expect(tester.takeException(), isNull);
  });
}
