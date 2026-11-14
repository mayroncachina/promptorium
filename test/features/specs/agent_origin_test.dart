import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/specs/spec_file.dart';
import 'package:promptorium/features/specs/widgets/agent_origin.dart';
import 'package:promptorium/features/specs/widgets/spec_list.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';

/// A spec the agent created through the Promptorium MCP (SPEC-052 R6).
void main() {
  test('the frontmatter says who created it', () {
    final agent = SpecDocument.parse(
      '---\nid: SPEC-053\nstatus: rascunho\norigem: agente\nsessao: 6f2c\n---\n',
    );
    expect(agent.agentSession, '6f2c');
    expect(
      SpecDocument.parse('---\nid: SPEC-1\nsessao: 6f2c\n---\n').agentSession,
      isNull,
    );
  });

  testWidgets('Specs: the seal "Criada pelo agente", the link to the session '
      'and the children', (tester) async {
    final db = memoryDatabase();
    final c = ProviderContainer(overrides: [databaseOverride(db)]);
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    late Spec parent;
    late List<Spec> specs;
    await tester.runAsync(() async {
      final ws = await c
          .read(workspacesRepoProvider)
          .add(path: '/w', name: 'w');
      final repo = c.read(specsRepoProvider);
      await c
          .read(sessionsRepoProvider)
          .insert(
            id: 'sessao-1',
            workspaceId: ws.id,
            worktreePath: '/w',
            branch: 'main',
            model: 'inherit',
            title: 'Planejar o export do Review',
          );
      parent = await repo.insert(
        workspaceId: ws.id,
        code: 'SPEC-053',
        title: 'Exportar o relatório do Review em PDF',
        path: 'specs/SPEC-053-x.md',
        agentSession: 'sessao-1',
      );
      await repo.insert(
        workspaceId: ws.id,
        code: 'SPEC-054',
        title: 'Gerar o PDF',
        path: 'specs/SPEC-054-x.md',
        dependsOn: ['SPEC-053'],
        agentSession: 'sessao-1',
      );
      await repo.insert(
        workspaceId: ws.id,
        code: 'SPEC-050',
        title: 'Trazer um PR',
        path: 'specs/SPEC-050-x.md',
      );
      specs = await repo.watchByWorkspace(ws.id).first;
    });
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Row(
              children: [
                SizedBox(
                  width: 420,
                  child: SpecList(
                    specs: specs,
                    selectedId: parent.id,
                    stepRows: const [],
                    onSelect: (_) {},
                  ),
                ),
                Expanded(child: AgentOriginBanner(spec: parent)),
              ],
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.byKey(const ValueKey('spec-item-agent-SPEC-053')), findsOne);
    expect(find.byKey(const ValueKey('spec-item-agent-SPEC-054')), findsOne);
    expect(
      find.byKey(const ValueKey('spec-item-agent-SPEC-050')),
      findsNothing,
    );
    expect(
      find.textContaining('na sessão “Planejar o export do Review”'),
      findsOneWidget,
    );
    expect(find.textContaining('nada roda até você aprovar'), findsOneWidget);
    expect(find.text('Abrir a sessão'), findsOneWidget);
    expect(find.text('Filhas · 1: SPEC-054 Gerar o PDF'), findsOneWidget);
  });
}
