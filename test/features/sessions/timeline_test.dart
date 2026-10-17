import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/features/sessions/agent_names.dart';
import 'package:promptorium/features/sessions/timeline.dart';

ClaudeEvent ev(Map<String, dynamic> j) => ClaudeEvent.fromJson(j);

Map<String, dynamic> delta(String text, {int index = 0}) => {
  'type': 'stream_event',
  'event': {
    'type': 'content_block_delta',
    'index': index,
    'delta': {'type': 'text_delta', 'text': text},
  },
  'parent_tool_use_id': null,
};

void main() {
  test(
    'text deltas stream live and are consolidated by the assistant line',
    () {
      final t = Timeline();
      t.apply(ev(delta('Ol')));
      t.apply(ev(delta('á, ')));
      final live = t.items.single as AssistantTextItem;
      expect((live.text, live.live), ('Olá, ', true));

      t.apply(
        ev({
          'type': 'assistant',
          'message': {
            'id': 'm1',
            'content': [
              {'type': 'text', 'text': 'Olá, mundo'},
            ],
          },
          'parent_tool_use_id': null,
        }),
      );
      final done = t.items.single as AssistantTextItem;
      expect((done.text, done.live), ('Olá, mundo', false));

      // Next block streams into a new item.
      t.apply(ev(delta('Segundo', index: 2)));
      expect(t.items, hasLength(2));
      expect((t.items.last as AssistantTextItem).live, isTrue);
      // A result closes any live text and adds a notice.
      t.apply(ev({'type': 'result', 'subtype': 'success', 'num_turns': 1}));
      expect((t.items[1] as AssistantTextItem).live, isFalse);
      expect((t.items.last as NoticeItem).level, NoticeLevel.success);
    },
  );

  test('thinking streams collapsed and the subagent card counts its tools '
      '(UX v2, U3)', () {
    final t = Timeline();
    Map<String, dynamic> think(String text) => {
      'type': 'stream_event',
      'event': {
        'type': 'content_block_delta',
        'index': 0,
        'delta': {'type': 'thinking_delta', 'thinking': text},
      },
      'parent_tool_use_id': null,
    };
    t.apply(ev(think('Preciso ')));
    t.apply(ev(think('ler o parser')));
    final live = t.items.single as ThinkingItem;
    expect((live.text, live.live), ('Preciso ler o parser', true));
    // The assistant message consolidates it and adds the text after.
    t.apply(
      ev({
        'type': 'assistant',
        'message': {
          'id': 'm1',
          'content': [
            {'type': 'thinking', 'thinking': 'Preciso ler o parser.'},
            {'type': 'text', 'text': 'Vou ler.'},
          ],
        },
        'parent_tool_use_id': null,
      }),
    );
    expect(t.items, hasLength(2));
    final done = t.items.first as ThinkingItem;
    expect((done.text, done.live), ('Preciso ler o parser.', false));
    expect((t.items.last as AssistantTextItem).text, 'Vou ler.');

    // A thinking block without deltas is an item of its own; a tool use
    // closes a live one.
    t.apply(ev(think('outra ideia')));
    t.apply(
      ev({
        'type': 'assistant',
        'message': {
          'id': 'm2',
          'content': [
            {
              'type': 'tool_use',
              'id': 'task1',
              'name': 'Task',
              'input': {'prompt': 'revise'},
            },
          ],
        },
        'parent_tool_use_id': null,
      }),
    );
    expect((t.items[2] as ThinkingItem).live, isFalse);
    final task = t.items.last as ToolItem;
    for (final id in ['g1', 'g2']) {
      t.apply(
        ev({
          'type': 'assistant',
          'message': {
            'id': 'sub-$id',
            'content': [
              {
                'type': 'tool_use',
                'id': id,
                'name': 'Grep',
                'input': {'pattern': 'x'},
              },
            ],
          },
          'parent_tool_use_id': 'task1',
        }),
      );
    }
    expect(task.childToolCount, 2);
    expect(task.doneAt, isNull);
    t.apply(
      ev({
        'type': 'user',
        'message': {
          'role': 'user',
          'content': [
            {'type': 'tool_result', 'tool_use_id': 'task1', 'content': 'ok'},
          ],
        },
        'parent_tool_use_id': null,
      }),
      at: DateTime(2026, 1, 1, 0, 0, 41),
    );
    expect(task.doneAt, DateTime(2026, 1, 1, 0, 0, 41));
  });

  test('fixture replays to init notice, text and result', () {
    final t = Timeline();
    for (final l in File(
      'test/fixtures/stream-json-exemplo.jsonl',
    ).readAsLinesSync().where((l) => l.trim().isNotEmpty)) {
      t.applyStored(l);
    }
    expect(t.model, 'claude-haiku-5-5');
    expect(t.items.first, isA<NoticeItem>());
    expect(t.items.whereType<AssistantTextItem>().single.text, 'ok');
    expect(t.items.last, isA<NoticeItem>());
  });

  test('app events, invalid lines and type keys', () {
    final t = Timeline();
    t.applyStored(jsonEncode(AppEventTypes.userMessage('oi', DateTime(2026))));
    t.applyStored(jsonEncode(AppEventTypes.noteMessage('caiu', error: true)));
    t.applyStored('não é json');
    expect((t.items[0] as UserItem).text, 'oi');
    expect((t.items[1] as NoticeItem).level, NoticeLevel.error);
    expect(t.items, hasLength(2));

    final bad = ClaudeEvent.parseLine('lixo').single;
    expect(eventTypeKey(bad), AppEventTypes.invalidLine);
    expect(jsonDecode(eventJson(bad))['raw'], 'lixo');
    expect(
      eventTypeKey(ev({'type': 'system', 'subtype': 'init'})),
      'system/init',
    );
  });

  test('toolTarget / editStats', () {
    expect(
      toolTarget('Read', {'file_path': '/w/lib/a.dart'}, root: '/w'),
      'lib/a.dart',
    );
    expect(toolTarget('Bash', {'command': 'ls\nrm'}), 'ls');
    expect(
      toolTarget('Grep', {'pattern': 'TODO', 'path': '/w/lib'}, root: '/w'),
      'TODO  em lib',
    );
    expect(editStats('Edit', {'old_string': 'a', 'new_string': 'b\nc\n'}), (
      2,
      1,
    ));
    expect(editStats('Write', {'content': 'x'}), (1, 0));
    expect(editStats('Bash', {}), isNull);
  });

  test('agent frontmatter: only name / description are read', () async {
    expect(
      parseAgentFrontmatter(
        '---\nname: tester\ndescription: Testa\ntools: Read\n---\ncorpo',
      ),
      (name: 'tester', description: 'Testa'),
    );
    expect(parseAgentFrontmatter('sem frontmatter'), isNull);
    expect(parseAgentFrontmatter('---\nname: [\n---\n'), isNull);

    final tmp = Directory.systemTemp.createTempSync('promptorium-agents-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    Directory('${tmp.path}/home/.claude/agents').createSync(recursive: true);
    Directory('${tmp.path}/ws/.claude/agents').createSync(recursive: true);
    File('${tmp.path}/home/.claude/agents/a.md')
        .writeAsStringSync('---\nname: reviewer\ndescription: g\n---\n');
    File('${tmp.path}/home/.claude/agents/b.md')
        .writeAsStringSync('---\nname: implementer\ndescription: g\n---\n');
    File('${tmp.path}/ws/.claude/agents/c.md')
        .writeAsStringSync('---\nname: reviewer\ndescription: p\n---\n');
    File('${tmp.path}/ws/.claude/agents/notes.txt').writeAsStringSync('x');
    final list = await listAgents(
      workspacePath: '${tmp.path}/ws',
      home: '${tmp.path}/home',
    );
    expect(list.map((a) => (a.name, a.project)), [
      ('implementer', false),
      ('reviewer', true),
    ]);
  });
}
