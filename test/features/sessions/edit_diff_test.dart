import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/features/sessions/edit_diff.dart';
import 'package:promptorium/features/sessions/timeline.dart';

const _spec =
    '---\n'
    'id: SPEC-024\n'
    '---\n'
    '# Ações\n'
    '\n'
    '## Requisitos\n'
    '\n'
    '- R1 · O cabeçalho separa modos.\n'
    '- R2 · Uma ação primária.\n'
    '- R3 · Nenhum rótulo truncado.\n'
    '\n'
    '## Critérios de aceite\n'
    '\n'
    '- [ ] Os rótulos aparecem inteiros.\n';

String _ops(EditDiff d) => [
  for (final r in d.rows)
    '${r.line ?? '-'}${switch (r.op) {
      DiffOp.add => '+',
      DiffOp.del => '-',
      DiffOp.same => ' ',
    }}${r.text}',
].join('|');

void main() {
  group('editDiffOf (SPEC-026 R1–R3)', () {
    test('Edit with the file known: full lines, context, positions and the '
        'nearest section above', () {
      final d = editDiffOf('Edit', {
        'file_path': '/w/spec.md',
        'old_string': 'Nenhum rótulo truncado.',
        'new_string': 'Nenhum rótulo truncado a 1100×700.\n- R4 · Mais ações.',
      }, before: _spec)!;
      expect(d.section, 'Requisitos');
      expect(d.added, 2);
      expect(d.removed, 1);
      final del = d.rows.firstWhere((r) => r.op == DiffOp.del);
      expect(del.text, '- R3 · Nenhum rótulo truncado.');
      expect(del.line, 10);
      final adds = d.rows.where((r) => r.op == DiffOp.add).toList();
      expect(adds.map((r) => r.line), [10, 11]);
      expect(adds.first.text, '- R3 · Nenhum rótulo truncado a 1100×700.');
      // 3 lines of context before; the rows keep the file positions.
      expect(d.rows.first, (op: DiffOp.same, text: '', line: 7));
      expect(d.rows.last.op, DiffOp.same);
    });

    test('Edit without the file: the strings only, no positions nor '
        'section', () {
      final d = editDiffOf('Edit', {
        'old_string': 'a\nb',
        'new_string': 'a\nc',
      })!;
      expect(_ops(d), '- a|--b|-+c');
      expect(d.section, isNull);
    });

    test('a new section added by the edit is its own section', () {
      final d = editDiffOf('Edit', {
        'old_string': '- [ ] Os rótulos aparecem inteiros.',
        'new_string':
            '- [ ] Os rótulos aparecem inteiros.\n\n## Fora do escopo\n\n- x',
      }, before: _spec)!;
      expect(d.section, 'Fora do escopo');
      expect(d.added, 4);
      expect(d.removed, 0);
    });

    test('Write over a known text is diffed against it (R3)', () {
      final after = _spec.replaceFirst('Uma ação primária.', 'Só uma.');
      final d = editDiffOf('Write', {'content': after}, before: _spec)!;
      expect(d.unknownBefore, isFalse);
      expect(d.added, 1);
      expect(d.removed, 1);
      expect(d.section, 'Requisitos');
      expect(d.rows.firstWhere((r) => r.op == DiffOp.add), (
        op: DiffOp.add,
        text: '- R2 · Só uma.',
        line: 9,
      ));
    });

    test('Write with the previous text unknown: every line added and the '
        'note flag (R3)', () {
      final d = editDiffOf('Write', {'content': 'a\nb\n'})!;
      expect(d.unknownBefore, isTrue);
      expect(_ops(d), '1+a|2+b');
    });

    test('MultiEdit concatenates the blocks of each edit', () {
      final d = editDiffOf('MultiEdit', {
        'edits': [
          {'old_string': 'separa modos', 'new_string': 'separa abas'},
          {'old_string': 'inteiros.', 'new_string': 'inteiros [R3].'},
        ],
      }, before: _spec)!;
      expect(d.added, 2);
      expect(d.removed, 2);
      expect(d.section, 'Requisitos');
    });

    test('other tools have no diff', () {
      expect(editDiffOf('Read', {'file_path': 'x'}), isNull);
    });
  });

  group('editDiffsOf: follows the file through the conversation (R3)', () {
    Timeline timeline(List<Map<String, dynamic>> lines) {
      final t = Timeline();
      for (final l in lines) {
        for (final e in ClaudeEvent.expand(l)) {
          t.apply(e);
        }
      }
      return t;
    }

    Map<String, dynamic> use(String id, String name, Map<String, dynamic> i) =>
        {
          'type': 'assistant',
          'message': {
            'id': 'm-$id',
            'role': 'assistant',
            'content': [
              {'type': 'tool_use', 'id': id, 'name': name, 'input': i},
            ],
          },
          'parent_tool_use_id': null,
          'session_id': 's',
        };

    Map<String, dynamic> result(String id, {bool error = false, String? c}) => {
      'type': 'user',
      'message': {
        'role': 'user',
        'content': [
          {
            'type': 'tool_result',
            'tool_use_id': id,
            'content': c ?? 'The file has been updated successfully.',
            'is_error': error,
          },
        ],
      },
      'parent_tool_use_id': null,
      'session_id': 's',
    };

    test('a Write after another Write of the same file is diffed against '
        'it; without one, all added', () {
      final t = timeline([
        use('w1', 'Write', {'file_path': '/w/a.md', 'content': 'x\ny\n'}),
        result('w1'),
        use('w2', 'Write', {'file_path': 'a.md', 'content': 'x\nz\n'}),
        result('w2'),
      ]);
      final d = editDiffsOf(t.items, root: '/w');
      expect(d['w1']!.unknownBefore, isTrue);
      expect(d['w2']!.unknownBefore, isFalse);
      expect(_ops(d['w2']!), '1 x|2-y|2+z');
    });

    test('the base text is followed through applied edits; denied ones do '
        'not change it', () {
      final t = timeline([
        use('e1', 'Edit', {
          'file_path': '/w/s.md',
          'old_string': 'Uma ação primária.',
          'new_string': 'Só uma.',
        }),
        result('e1', error: true, c: AppEventTypes.deniedMessage),
        use('e2', 'Edit', {
          'file_path': '/w/s.md',
          'old_string': 'Uma ação primária.',
          'new_string': 'Uma por estado.',
        }),
        result('e2'),
        use('e3', 'Edit', {
          'file_path': '/w/s.md',
          'old_string': 'Uma por estado.',
          'new_string': 'Uma por estado [R2].',
        }),
      ]);
      expect(t.tool('e1')!.denied, isTrue);
      final d = editDiffsOf(t.items, known: {'/w/s.md': _spec});
      expect(d['e2']!.section, 'Requisitos');
      // e3 only matches the text after e2.
      expect(d['e3']!.rows.any((r) => r.line == 9), isTrue);
      expect(
        textAfterEdits(t.items, '/w/s.md', base: _spec),
        _spec.replaceFirst('Uma ação primária.', 'Uma por estado.'),
      );
    });
  });
}
