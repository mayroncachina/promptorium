import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/transcript_reader.dart';

String _line(String toolId, String? original) => jsonEncode({
  'type': 'user',
  'message': {
    'role': 'user',
    'content': [
      {'type': 'tool_result', 'tool_use_id': toolId, 'content': 'ok'},
    ],
  },
  'toolUseResult': {
    'type': 'update',
    'filePath': '/w/a.dart',
    'originalFile': original,
  },
});

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('transcript'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('encodes the cwd like Claude Code', () {
    expect(
      TranscriptReader.encodeCwd('/home/u/.promptorium/worktrees/a_b'),
      '-home-u--promptorium-worktrees-a-b',
    );
  });

  test('finds the originalFile by tool_use_id (SPEC-082 R10)', () async {
    final folder = Directory(
      '${dir.path}/projects/${TranscriptReader.encodeCwd('/w/x')}',
    )..createSync(recursive: true);
    File('${folder.path}/s1.jsonl').writeAsStringSync(
      [
        '{"type":"summary"}',
        'não é json "originalFile"',
        _line('toolu_1', 'antes\n'),
        _line('toolu_2', null),
        '{"originalFile": 3}',
        _line('toolu_3', 'outro'),
      ].join('\n'),
    );
    final r = TranscriptReader(configDir: dir.path);
    final map = await r.originalFiles('s1', cwd: '/w/x');
    expect(map, {'toolu_1': 'antes\n', 'toolu_3': 'outro'});
  });

  test('looks in the other projects when the cwd differs', () async {
    final folder = Directory('${dir.path}/projects/-outro')
      ..createSync(recursive: true);
    File('${folder.path}/s2.jsonl').writeAsStringSync(_line('t', 'x'));
    final r = TranscriptReader(configDir: dir.path);
    expect(await r.originalFiles('s2', cwd: '/w/y'), {'t': 'x'});
  });

  test('a missing transcript is empty, not an error', () async {
    final r = TranscriptReader(configDir: '${dir.path}/nada');
    expect(await r.originalFiles('s3', cwd: '/w'), isEmpty);
    expect(await r.originalFiles('../s3'), isEmpty);
  });
}
