import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/core/mcp/app_mcp_tools.dart';
import 'package:promptorium/features/sessions/edit_diff.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/features/sessions/widgets/side_panel.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

const _spec =
    '# Ações\n'
    '\n'
    '## Requisitos\n'
    '\n'
    '- R1 · O cabeçalho separa modos.\n'
    '- R2 · Uma ação primária.\n'
    '- R3 · Nenhum rótulo truncado.\n';

PendingApproval _approval(String tool, Map<String, dynamic> input) {
  final line = jsonEncode({
    'type': 'control_request',
    'request_id': 'req-1',
    'request': {
      'subtype': 'can_use_tool',
      'tool_name': tool,
      'input': input,
      'tool_use_id': 'toolu_1',
    },
  });
  return PendingApproval(
    sessionId: 's1',
    sessionTitle: 'Refinar SPEC-024',
    request: ClaudeEvent.parseLine(line).single as PermissionRequest,
    receivedAt: DateTime(2026, 11, 1),
  );
}

Future<({List<String> calls})> _pump(
  WidgetTester tester,
  PendingApproval a, {
  EditInfo? edit,
}) async {
  tester.view.physicalSize = const Size(1100, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final calls = <String>[];
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 520,
            child: ApprovalCard(
              approval: a,
              edit: edit,
              onOpen: () {},
              onApprove: ({required bool always, input}) async =>
                  calls.add('approve'),
              onDeny: () async => calls.add('deny'),
            ),
          ),
        ),
      ),
    ),
  );
  return (calls: calls);
}

void main() {
  testWidgets('an Edit on the spec shows the title, tool, file and section, '
      '"+N −M", the removed and added lines, "Negar" and "Aprovar edição" '
      '(SPEC-026 R1)', (tester) async {
    final input = {
      'file_path': '/w/docs/specs/SPEC-024-acoes.md',
      'old_string': '- R3 · Nenhum rótulo truncado.',
      'new_string':
          '- R3 · Quando a janela tiver 1100×700, nada é truncado.\n'
          '- R4 · Ações que não cabem vão para "Mais ações".',
    };
    final diff = editDiffOf('Edit', input, before: _spec);
    final r = await _pump(
      tester,
      _approval('Edit', input),
      edit: EditInfo(diff: diff, target: 'SPEC-024 · Requisitos'),
    );
    expect(find.text('Aprovar esta edição na spec?'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('SPEC-024-acoes.md'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('approval-section-req-1')),
      findsOneWidget,
    );
    expect(find.text('Requisitos'), findsWidgets);
    final stats = tester.widget<Text>(
      find.byKey(const ValueKey('approval-stats-req-1')),
    );
    expect(stats.textSpan!.toPlainText(), '+2 −1');
    expect(find.text('- R3 · Nenhum rótulo truncado.'), findsOneWidget);
    expect(
      find.text('- R3 · Quando a janela tiver 1100×700, nada é truncado.'),
      findsOneWidget,
    );
    expect(find.text('-'), findsOneWidget);
    expect(find.text('+'), findsNWidgets(2));
    expect(find.text('Negar'), findsOneWidget);
    expect(find.text('Aprovar edição'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('approve-req-1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('deny-req-1')));
    await tester.pump();
    expect(r.calls, ['approve', 'deny']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long diff is limited in height and scrolls inside the card '
      '(R10)', (tester) async {
    final input = {
      'file_path': '/w/a.md',
      'old_string': 'x',
      'new_string': [for (var i = 0; i < 60; i++) 'linha $i'].join('\n'),
    };
    await _pump(tester, _approval('Edit', input));
    final box = tester.getSize(
      find.byKey(const ValueKey('approval-diff-req-1')),
    );
    expect(box.height, lessThanOrEqualTo(200));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('approval-diff-req-1')),
        matching: find.byType(Scrollable),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('without the refine info (Sessões) the card still shows the '
      'diff of the request; other tools keep "Aprovar"', (tester) async {
    await _pump(
      tester,
      _approval('Write', {'file_path': '/w/n.md', 'content': 'a\nb\n'}),
    );
    expect(find.text('Aprovar esta edição?'), findsOneWidget);
    expect(find.text('Conteúdo anterior desconhecido'), findsOneWidget);
    expect(find.text('Aprovar edição'), findsOneWidget);

    await _pump(tester, _approval('Bash', {'command': 'ls'}));
    expect(find.text('Aprovar'), findsOneWidget);
    expect(find.text('Aprovar edição'), findsNothing);
  });

  group('SPEC-052 R4 · criar_spec / criar_filhas', () {
    const suggestion = {
      'type': 'addRules',
      'rules': [
        {'toolName': 'mcp__promptorium__criar_spec'},
      ],
      'behavior': 'allow',
      'destination': 'localSettings',
    };
    const text =
        '# Exportar o relatório do Review em PDF\n\n'
        '## Requisitos\n\n'
        '- R1 · O Review deve oferecer "Exportar PDF".\n'
        '- R2 · O PDF deve trazer os critérios.\n'
        '- R3 · Capa com o logo do projeto.\n\n'
        '## Critérios de aceite\n\n'
        '- [ ] Exporta [R1]\n- [ ] Critérios [R2]\n';

    PendingApproval mcpApproval(String tool, Map<String, dynamic> input) {
      final line = jsonEncode({
        'type': 'control_request',
        'request_id': 'req-1',
        'request': {
          'subtype': 'can_use_tool',
          'tool_name': tool,
          'input': input,
          'tool_use_id': 'toolu_1',
          'permission_suggestions': [suggestion],
        },
      });
      return PendingApproval(
        sessionId: 's1',
        sessionTitle: 'Planejar o export do Review',
        request: ClaudeEvent.parseLine(line).single as PermissionRequest,
        receivedAt: DateTime(2026, 11, 13),
      );
    }

    Future<List<String>> pump(WidgetTester tester, PendingApproval a) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final calls = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: SizedBox(
                  width: 720,
                  child: ApprovalCard(
                    approval: a,
                    onOpen: () {},
                    onApprove: ({required bool always, input}) async =>
                        calls.add(always ? 'always' : 'approve'),
                    onDeny: () async => calls.add('deny'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return calls;
    }

    testWidgets('the card shows the preview: title, requirements, criteria, '
        'lint warnings and the file', (tester) async {
      final calls = await pump(
        tester,
        mcpApproval('mcp__promptorium__criar_spec', {
          'texto': text,
          'depende_de': ['SPEC-043'],
        }),
      );
      expect(find.text('O agente quer criar uma spec'), findsOneWidget);
      expect(find.text('mcp__promptorium__criar_spec'), findsOneWidget);
      expect(
        find.text('Exportar o relatório do Review em PDF'),
        findsOneWidget,
      );
      expect(find.text('3 requisitos'), findsOneWidget);
      expect(find.text('2 critérios'), findsOneWidget);
      expect(find.text('depende de SPEC-043'), findsOneWidget);
      expect(find.text('status: rascunho'), findsOneWidget);
      expect(find.text('origem: agente'), findsOneWidget);
      final path = tester.widget<Text>(
        find.byKey(const ValueKey('agent-spec-path-0')),
      );
      expect(path.data, endsWith('-exportar-o-relatorio-do-review-em-pdf.md'));
      expect(find.byKey(const ValueKey('agent-spec-lint-0')), findsOneWidget);
      expect(find.textContaining('do lint: '), findsOneWidget);
      expect(find.textContaining('R3'), findsWidgets);

      await tester.tap(find.text('Aprovar'));
      await tester.pump();
      expect(calls, ['approve']);
    });

    testWidgets('it does not offer "Sempre permitir" in the project, only in '
        'this session', (tester) async {
      final calls = await pump(
        tester,
        mcpApproval('mcp__promptorium__criar_spec', {'texto': text}),
      );
      expect(find.textContaining('neste projeto'), findsNothing);
      expect(find.textContaining('no projeto (local)'), findsNothing);
      expect(find.textContaining('em todos os projetos'), findsNothing);
      expect(find.text('Sempre permitir nesta sessão'), findsOneWidget);
      await tester.tap(find.text('Sempre permitir nesta sessão'));
      await tester.pump();
      expect(calls, ['always']);
      // What goes back to the CLI: the rule only for the session.
      expect(
        alwaysAllowSuggestions('mcp__promptorium__criar_spec', [
          suggestion,
        ]).single['destination'],
        'session',
      );
      expect(
        alwaysAllowSuggestions('mcp__promptorium__criar_filhas', [
          suggestion,
        ]).single['destination'],
        'session',
      );
      // Other tools keep what the CLI suggested.
      expect(
        alwaysAllowSuggestions('Bash', [suggestion]).single['destination'],
        'localSettings',
      );
    });

    testWidgets('criar_filhas: one approval for every child, each with '
        'depende-de of the parent', (tester) async {
      await pump(
        tester,
        mcpApproval('mcp__promptorium__criar_filhas', {
          'pai': 'SPEC-053',
          'filhas': [
            {'texto': '# Gerar o PDF\n\n## Requisitos\n\n- R1 · Deve gerar.\n'},
            {
              'texto':
                  '# Botão Exportar\n\n## Requisitos\n\n- R1 · Deve ter.\n',
            },
          ],
        }),
      );
      expect(
        find.text('O agente quer criar 2 filhas da SPEC-053'),
        findsOneWidget,
      );
      expect(find.text('Gerar o PDF'), findsOneWidget);
      expect(find.text('Botão Exportar'), findsOneWidget);
      expect(find.text('depende de SPEC-053'), findsNWidgets(2));
      expect(find.text('Aprovar'), findsOneWidget);
    });
  });
}
