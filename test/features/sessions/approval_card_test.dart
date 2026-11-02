import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_event.dart';
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
}
