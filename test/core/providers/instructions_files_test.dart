import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/providers/instructions_files.dart';
import 'package:promptorium/core/providers/workspace_assets.dart';

/// SPEC-113 T1: the import of the `CLAUDE.md` (R1, R9), the safe write of
/// the two files (R5) and the size against the Codex limit (R11).
void main() {
  late Directory tmp;
  late String root;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('instructions-files-');
    root = tmp.path;
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  String path(String name) => '$root/$name';
  void write(String name, String text) =>
      File(path(name)).writeAsStringSync(text);
  String? read(String name) {
    final f = File(path(name));
    return f.existsSync() ? f.readAsStringSync() : null;
  }

  List<String> files() =>
      [for (final e in tmp.listSync()) e.path.split('/').last]..sort();

  group('R9: the import of the CLAUDE.md', () {
    test('splits the import line from the Claude-only part', () {
      final parts = splitClaudeMd('@AGENTS.md\n\n# Só Claude\n- hooks\n');
      expect(parts.hasImport, isTrue);
      expect(parts.importLine, '@AGENTS.md');
      expect(parts.claudeOnly, '# Só Claude\n- hooks\n');
      expect(
        composeClaudeMd(parts.claudeOnly),
        '@AGENTS.md\n\n# Só Claude\n- hooks\n',
      );
    });

    test('an import in the middle and the ./ spelling', () {
      final parts = splitClaudeMd('# Projeto\n@./AGENTS.md\n- x\n');
      expect(parts.importLine, '@./AGENTS.md');
      expect(parts.claudeOnly, '# Projeto\n- x\n');
    });

    test('no import (or only inside a code block): warns', () {
      for (final c in ['# a\n', '```\n@AGENTS.md\n```\n']) {
        final parts = splitClaudeMd(c);
        expect(parts.hasImport, isFalse);
        expect(parts.claudeOnly, c);
      }
    });

    test('"Recolocar o import" puts it on top, once', () {
      expect(restoreAgentsImport('# a\n'), '@AGENTS.md\n\n# a\n');
      expect(restoreAgentsImport(''), '@AGENTS.md\n');
      const ok = '# a\n@AGENTS.md\n';
      expect(restoreAgentsImport(ok), ok);
      expect(
        hasAgentsImport(restoreAgentsImport('```\n@AGENTS.md\n```\n')),
        isTrue,
      );
    });

    test('CRLF line endings', () {
      expect(hasAgentsImport('# a\r\n@AGENTS.md\r\n'), isTrue);
      expect(splitClaudeMd('@AGENTS.md\r\n# b\r\n').importLine, '@AGENTS.md');
    });
  });

  group('R5: safe write', () {
    test('writes both files and keeps the previous version for undo', () async {
      write('CLAUDE.md', '# antigo\n');
      final claude = await readInstructionsSnapshot(path('CLAUDE.md'));
      final agents = await readInstructionsSnapshot(path('AGENTS.md'));
      expect(agents.exists, isFalse);
      final result = await writeInstructionFiles([
        InstructionsWrite(agents, '# antigo\n'),
        InstructionsWrite(claude, '@AGENTS.md\n'),
      ]);
      expect(read('AGENTS.md'), '# antigo\n');
      expect(read('CLAUDE.md'), '@AGENTS.md\n');
      expect(files(), ['AGENTS.md', 'CLAUDE.md']);
      expect(result.previous.map((s) => s.text), [null, '# antigo\n']);
      expect(
        agentsMdState(claude: read('CLAUDE.md'), agents: read('AGENTS.md')),
        AgentsMdState.singleSource,
      );

      await undoInstructionWrite(result);
      expect(read('CLAUDE.md'), '# antigo\n');
      expect(read('AGENTS.md'), isNull);
      expect(files(), ['CLAUDE.md']);
    });

    test('a failure in the second file puts the first one back', () async {
      write('AGENTS.md', '# agents v1\n');
      write('CLAUDE.md', '# claude v1\n');
      final agents = await readInstructionsSnapshot(path('AGENTS.md'));
      final claude = await readInstructionsSnapshot(path('CLAUDE.md'));
      await expectLater(
        writeInstructionFiles([
          InstructionsWrite(agents, '# agents v2\n'),
          InstructionsWrite(claude, '@AGENTS.md\n'),
        ], fs: _FailOn('CLAUDE.md')),
        throwsA(
          isA<InstructionsException>().having(
            (e) => e.message,
            'message',
            contains('CLAUDE.md'),
          ),
        ),
      );
      expect(read('AGENTS.md'), '# agents v1\n');
      expect(read('CLAUDE.md'), '# claude v1\n');
      expect(files(), ['AGENTS.md', 'CLAUDE.md'], reason: 'no temp left');
    });

    test('a failure in the second file removes a first file that did not '
        'exist', () async {
      write('CLAUDE.md', '# claude v1\n');
      await expectLater(
        writeInstructionFiles([
          InstructionsWrite(
            await readInstructionsSnapshot(path('AGENTS.md')),
            '# novo\n',
          ),
          InstructionsWrite(
            await readInstructionsSnapshot(path('CLAUDE.md')),
            '@AGENTS.md\n',
          ),
        ], fs: _FailOn('CLAUDE.md')),
        throwsA(isA<InstructionsException>()),
      );
      expect(files(), ['CLAUDE.md']);
      expect(read('CLAUDE.md'), '# claude v1\n');
    });

    test('refuses when a file changed on disk after the reading', () async {
      write('AGENTS.md', '# a\n');
      write('CLAUDE.md', '@AGENTS.md\n');
      final agents = await readInstructionsSnapshot(path('AGENTS.md'));
      final claude = await readInstructionsSnapshot(path('CLAUDE.md'));
      write('CLAUDE.md', '@AGENTS.md\n# editado fora\n');
      await expectLater(
        writeInstructionFiles([
          InstructionsWrite(agents, '# b\n'),
          InstructionsWrite(claude, '@AGENTS.md\n'),
        ]),
        throwsA(
          isA<InstructionsConflict>().having(
            (e) => e.path,
            'path',
            claude.path,
          ),
        ),
      );
      expect(read('AGENTS.md'), '# a\n', reason: 'nothing written');

      // A file created after the reading (read as absent) is a change too.
      final absent = await readInstructionsSnapshot(path('NOVO.md'));
      write('NOVO.md', 'x');
      await expectLater(
        writeInstructionFiles([InstructionsWrite(absent, 'y')]),
        throwsA(isA<InstructionsConflict>()),
      );
      expect(read('NOVO.md'), 'x');
    });

    test('undo refuses when the file changed after the write', () async {
      write('AGENTS.md', '# a\n');
      final result = await writeInstructionFiles([
        InstructionsWrite(
          await readInstructionsSnapshot(path('AGENTS.md')),
          '# b\n',
        ),
      ]);
      write('AGENTS.md', '# c\n');
      await expectLater(
        undoInstructionWrite(result),
        throwsA(isA<InstructionsConflict>()),
      );
      expect(read('AGENTS.md'), '# c\n');
    });
  });

  group('R11: size against the Codex 32 KiB', () {
    test('ok below 80%, warning from 80%, over past the limit', () {
      expect(codexInstructionsLimit, 32768);
      expect(instructionsSize('').level, InstructionsSizeLevel.ok);
      expect(instructionsSize('a' * 26214).level, InstructionsSizeLevel.ok);
      expect(
        instructionsSize('a' * 26215).level,
        InstructionsSizeLevel.warning,
      );
      final full = instructionsSize('a' * 32768);
      expect(full.level, InstructionsSizeLevel.warning);
      expect(full.cut, isNull);
    });

    test('bytes (UTF-8) and lines', () {
      final s = instructionsSize('ação\nb\n');
      expect(s.bytes, utf8.encode('ação\nb\n').length);
      expect(s.bytes, 9);
      expect(s.lines, 2);
      expect(instructionsSize('a\nb').lines, 2);
    });

    test('32 769 bytes show the cut: line and column of byte 32 768', () {
      // 100 lines of 99 chars + \n = 10 000 bytes per 100 lines.
      final line = '${'x' * 99}\n';
      final text = '${line * 327}${'y' * 69}';
      expect(utf8.encode(text).length, 32769);
      final s = instructionsSize(text);
      expect(s.level, InstructionsSizeLevel.over);
      expect(s.bytes, 32769);
      expect(s.cut, isNotNull);
      // 327 lines = 32 700 bytes; byte 32 768 is the 69th of line 328.
      expect(s.cut!.line, 328);
      expect(s.cut!.column, 69);
      expect(s.cut!.midLine, isTrue);
      expect(s.cut!.offset, 32768);
      expect(text.substring(s.cut!.offset), 'y');
    });

    test('a multibyte character split by the cut is left out', () {
      // 32 767 ASCII bytes + "é" (2 bytes) = 32 769 bytes.
      final text = '${'a' * 32767}é';
      final s = instructionsSize(text);
      expect(s.bytes, 32769);
      expect(s.cut!.offset, 32767);
      expect(s.cut!.column, 32768);
    });
  });
}

/// Fails the `rename` over [name] (R5: the second file of the pair).
class _FailOn extends InstructionsFs {
  const _FailOn(this.name);

  final String name;

  @override
  Future<void> replace(File tmp, String target) {
    if (target.endsWith('/$name')) {
      throw const FileSystemException('falha simulada');
    }
    return super.replace(tmp, target);
  }
}
