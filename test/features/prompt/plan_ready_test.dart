import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/features/prompt/plan_ready.dart';

void main() {
  test('planOfRequest reads the plan of ExitPlanMode only', () {
    final e =
        ClaudeEvent.parseLine(
              '{"type":"control_request","request_id":"r1","request":'
              '{"subtype":"can_use_tool","tool_name":"ExitPlanMode",'
              '"input":{"plan":"1. Ler\\n2. Editar `lib/a.dart`"}}}',
            ).single
            as PermissionRequest;
    expect(planOfRequest(e), '1. Ler\n2. Editar `lib/a.dart`');
    final bash =
        ClaudeEvent.parseLine(
              '{"type":"control_request","request_id":"r2","request":'
              '{"subtype":"can_use_tool","tool_name":"Bash",'
              '"input":{"command":"ls"}}}',
            ).single
            as PermissionRequest;
    expect(planOfRequest(bash), isNull);
  });

  test('planSummary counts items and files', () {
    expect(
      planSummary(
        '1. Gravar em `stream_parser.dart`\n2. Card em `timeline_view.dart`\n'
        '- teste em `timeline_test.dart`\n',
      ),
      '3 itens · 3 arquivos',
    );
    expect(planSummary('só texto'), '');
  });

  test('savePlanFile writes .promptorium/planos/<date>-<slug>.md', () async {
    final tmp = Directory.systemTemp.createTempSync('promptorium-plan-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final rel = await savePlanFile(
      tmp.path,
      'Thinking recolhido',
      '1. x',
      now: DateTime(2026, 10, 17),
    );
    expect(rel, '.promptorium/planos/2026-10-17-thinking-recolhido.md');
    expect(
      File('${tmp.path}/$rel').readAsStringSync(),
      '# Thinking recolhido\n\n1. x\n',
    );
    expect(implementPrompt('T', 'P'), contains('P'));
  });
}
