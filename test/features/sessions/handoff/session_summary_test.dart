import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/features/sessions/handoff/session_summary.dart';
import 'package:promptorium/features/sessions/timeline.dart';

import '../../../core/codex/codex_replay.dart';

/// A Claude session recorded as `session_events` rows: a request, an edit,
/// a failing and a passing `flutter test`, a task list and the answer.
Timeline _claude() {
  final t = Timeline();
  void row(Map<String, dynamic> j, String at) =>
      t.applyStored(jsonEncode(j), at: DateTime.parse(at));
  Map<String, dynamic> use(String id, String name, Map<String, dynamic> input) =>
      {
        'type': 'assistant',
        'message': {
          'id': 'm-$id',
          'role': 'assistant',
          'content': [
            {'type': 'tool_use', 'id': id, 'name': name, 'input': input},
          ],
        },
      };
  Map<String, dynamic> result(String id, String out, {bool error = false}) => {
    'type': 'user',
    'message': {
      'role': 'user',
      'content': [
        {
          'type': 'tool_result',
          'tool_use_id': id,
          'content': out,
          'is_error': error,
        },
      ],
    },
  };
  row(
    AppEventTypes.userMessage(
      'troque o parser de regex por um leitor por linhas',
      DateTime.parse('2026-11-20T11:30:00'),
    ),
    '2026-11-20T11:30:00',
  );
  row(
    use('e1', 'Edit', {
      'file_path': '/wt/spec-parser/lib/core/spec_parser.dart',
      'old_string': 'a',
      'new_string': 'b',
    }),
    '2026-11-20T11:31:00',
  );
  row(result('e1', 'ok'), '2026-11-20T11:31:01');
  row(
    use('b1', 'Bash', {'command': 'flutter test test/core/spec_parser_test.dart'}),
    '2026-11-20T11:33:00',
  );
  row(
    result('b1', 'Exit code 1\n3 testes falharam', error: true),
    '2026-11-20T11:33:10',
  );
  row(
    use('t1', 'TodoWrite', {
      'todos': [
        {'content': 'leitor por linhas', 'status': 'completed'},
        {'content': 'teste com BOM', 'status': 'pending'},
      ],
    }),
    '2026-11-20T11:35:00',
  );
  row(result('t1', 'ok'), '2026-11-20T11:35:01');
  row(
    use('b2', 'Bash', {'command': 'flutter test test/core/spec_parser_test.dart'}),
    '2026-11-20T11:38:00',
  );
  row(result('b2', 'All tests passed!'), '2026-11-20T11:38:10');
  row({
    'type': 'assistant',
    'message': {
      'id': 'm-end',
      'role': 'assistant',
      'content': [
        {
          'type': 'text',
          'text': 'Os testes de spec_parser passam com o leitor por linhas.',
        },
      ],
    },
  }, '2026-11-20T11:39:00');
  return t;
}

void main() {
  test('R7: the app summary of a Claude session has the last request, a '
      'piece of the answer, the changed files, the failed commands with '
      'their exit code, the tasks and the uncommitted files — no model', () {
    final text = sessionSummary(
      title: 'Parser de front-matter',
      provider: 'claude',
      items: _claude().items,
      root: '/wt/spec-parser',
      uncommitted: const ['a', 'b', 'c', 'd', 'e'],
    );
    expect(
      text,
      startsWith(
        'Continuação da sessão "Parser de front-matter" (Claude Code).',
      ),
    );
    expect(
      text,
      contains(
        'Último pedido: troque o parser de regex por um leitor por linhas',
      ),
    );
    expect(
      text,
      contains('Última resposta (trecho): Os testes de spec_parser passam'),
    );
    expect(text, contains('Arquivos alterados: @lib/core/spec_parser.dart'));
    expect(
      text,
      contains(
        'Comandos que falharam: flutter test test/core/spec_parser_test.dart '
        '(saída 1, 11:33)',
      ),
    );
    // The command that passed later is not a failure.
    expect('saída'.allMatches(text), hasLength(1));
    expect(text, contains('Tarefas: [x] leitor por linhas  [ ] teste com BOM'));
    expect(text, contains('Não commitados: 5 arquivos.'));
    expect(text, endsWith('Continue a partir daqui.'));
  });

  test('R10: the summary of a Codex session comes from the neutral file and '
      'command events (0.170 transcripts)', () async {
    final cmds = Timeline();
    for (final e in await replayCodex(
      'comando',
      permissionMode: ClaudePermissionMode.defaultMode,
    )) {
      cmds.apply(e);
    }
    final edits = Timeline();
    for (final e in await replayCodex('edicao')) {
      edits.apply(e);
    }
    final failed = failedCommands(cmds.items);
    expect(failed, hasLength(1));
    expect(failed.single, startsWith('cat nao-existe.txt (saída 1'));
    final files = changedFiles(edits.items, root: '<sonda>/repos/edicao/repo');
    expect(files, containsAll(['base.txt', 'nota.txt']));
    final text = sessionSummary(
      title: 'Revisão',
      provider: 'codex',
      items: [...edits.items, ...cmds.items],
      root: '<sonda>/repos/edicao/repo',
    );
    expect(text, startsWith('Continuação da sessão "Revisão" (Codex).'));
    expect(text, contains('@base.txt'));
    expect(text, contains('cat nao-existe.txt (saída 1'));
    expect(text, isNot(contains('Não commitados')));
  });
}
