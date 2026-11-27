import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'workspace_assets.dart';

/// The instruction files as text (SPEC-113): the import of the `CLAUDE.md`
/// (R9), the safe write of one or both root files (R5) and the size
/// against the Codex limit (R11).

// --- Import do CLAUDE.md (R1, R9) ----------------------------------------------

/// A `CLAUDE.md` split into the import line and the "Só para o Claude Code"
/// part (R9).
@immutable
class ClaudeMdParts {
  const ClaudeMdParts({required this.importLine, required this.claudeOnly});

  /// The import line as written (`@AGENTS.md`, `@./AGENTS.md`); null = the
  /// `CLAUDE.md` does not import the `AGENTS.md` (R9: warn, offer
  /// "Recolocar o import").
  final String? importLine;

  /// Everything else: what only the Claude Code reads.
  final String claudeOnly;

  bool get hasImport => importLine != null;
}

/// Splits [claude] into its import line (the first one outside a code
/// block, R1) and the rest (R9). The blank line right after the import is
/// part of the import, so [composeClaudeMd] gives the text back.
ClaudeMdParts splitClaudeMd(String claude) {
  final index = agentsImportLineIndex(claude);
  if (index == null) return ClaudeMdParts(importLine: null, claudeOnly: claude);
  final lines = claude.split('\n');
  final importLine = lines[index].replaceAll('\r', '').trim();
  lines.removeAt(index);
  // On top (as [composeClaudeMd] writes it), the blank line after it goes too.
  if (index == 0 && lines.isNotEmpty && lines.first.trim().isEmpty) {
    lines.removeAt(0);
  }
  return ClaudeMdParts(importLine: importLine, claudeOnly: lines.join('\n'));
}

/// A `CLAUDE.md` from the import and [claudeOnly] (R9): the import on the
/// first line, a blank line, then the Claude-only part (if any).
String composeClaudeMd(
  String claudeOnly, {
  String importLine = claudeImportLine,
}) {
  final rest = claudeOnly.trimLeft();
  return rest.isEmpty ? '$importLine\n' : '$importLine\n\n$rest';
}

/// "Recolocar o import" (R9): [claude] with the import on top; unchanged
/// when it already imports the `AGENTS.md`.
String restoreAgentsImport(String claude) =>
    hasAgentsImport(claude) ? claude : composeClaudeMd(claude);

// --- Gravação segura (R5) ------------------------------------------------------

/// sha256 of a text's UTF-8 bytes.
String instructionsTextHash(String text) =>
    sha256.convert(utf8.encode(text)).toString();

/// One instruction file as the app read it (R5): the base of a write, which
/// is refused when the file changed on disk since.
@immutable
class InstructionsSnapshot {
  const InstructionsSnapshot({
    required this.path,
    required this.text,
    this.modified,
  });

  /// Absolute path.
  final String path;

  /// Null = the file did not exist.
  final String? text;
  final DateTime? modified;

  bool get exists => text != null;
  String? get hash => text == null ? null : instructionsTextHash(text!);
  String get name => path.split('/').last;
}

/// Reads [path] for a later [writeInstructionFiles] (R5).
Future<InstructionsSnapshot> readInstructionsSnapshot(String path) async {
  final f = File(path);
  if (!await f.exists()) return InstructionsSnapshot(path: path, text: null);
  final text = await f.readAsString();
  return InstructionsSnapshot(
    path: path,
    text: text,
    modified: (await f.stat()).modified,
  );
}

/// One file of a write: the [base] read and the new text (null = delete).
@immutable
class InstructionsWrite {
  const InstructionsWrite(this.base, this.text);

  final InstructionsSnapshot base;
  final String? text;
}

/// The file changed on disk after it was read (R5): nothing was written.
class InstructionsConflict extends InstructionsException {
  const InstructionsConflict(this.path, super.message);

  final String path;
}

/// What a write did (R5): the files before ([previous], for "Desfazer")
/// and after ([written], the base of the next edit or of the undo).
@immutable
class InstructionsWriteResult {
  const InstructionsWriteResult({
    required this.previous,
    required this.written,
  });

  final List<InstructionsSnapshot> previous;
  final List<InstructionsSnapshot> written;
}

/// The file operations of a write; tests inject failures (R5).
@visibleForTesting
class InstructionsFs {
  const InstructionsFs();

  Future<void> writeTemp(File tmp, String text) =>
      tmp.writeAsString(text, flush: true);

  /// Puts [tmp] in place of [target] (`rename`, atomic in the same folder).
  Future<void> replace(File tmp, String target) => tmp.rename(target);

  Future<void> delete(String target) => File(target).delete();
}

const _tmpSuffix = '.promptorium-tmp';

/// Writes one or more instruction files together (R5): every file must be
/// as its [InstructionsWrite.base] (same content, or still absent) —
/// otherwise [InstructionsConflict] and nothing is written. Each text goes
/// to a temporary file in the same folder and then `rename`s over the
/// target; if a later file fails, the earlier ones go back to what they
/// were and the error is rethrown as [InstructionsException].
Future<InstructionsWriteResult> writeInstructionFiles(
  List<InstructionsWrite> writes, {
  @visibleForTesting InstructionsFs fs = const InstructionsFs(),
}) async {
  if (writes.map((w) => w.base.path).toSet().length != writes.length) {
    throw ArgumentError('Arquivo repetido na gravação.');
  }
  // 1. Nothing changed on disk since the reading.
  final previous = <InstructionsSnapshot>[];
  for (final w in writes) {
    final now = await readInstructionsSnapshot(w.base.path);
    if (now.hash != w.base.hash) {
      throw InstructionsConflict(
        w.base.path,
        'O ${w.base.name} mudou no disco depois da leitura: '
        'nada foi gravado.',
      );
    }
    previous.add(now);
  }
  // 2. The new texts in temporary files.
  final temps = <File?>[];
  try {
    for (final w in writes) {
      if (w.text == null) {
        temps.add(null);
        continue;
      }
      final tmp = File('${w.base.path}$_tmpSuffix');
      temps.add(tmp);
      await fs.writeTemp(tmp, w.text!);
    }
  } catch (e) {
    await _deleteTemps(temps);
    throw InstructionsException('Não foi possível gravar: $e');
  }
  // 3. In place, one by one; a failure puts the earlier ones back.
  var done = 0;
  try {
    for (var i = 0; i < writes.length; i++) {
      final target = writes[i].base.path;
      final tmp = temps[i];
      if (tmp != null) {
        await fs.replace(tmp, target);
      } else if (previous[i].exists) {
        await fs.delete(target);
      }
      done++;
    }
  } catch (e) {
    final failed = writes[done].base.name;
    await _deleteTemps(temps.sublist(done));
    for (var i = done - 1; i >= 0; i--) {
      await _restore(previous[i]);
    }
    throw InstructionsException(
      'Não foi possível gravar o $failed: $e. '
      '${done == 0 ? 'Nada mudou.' : 'Os arquivos voltaram ao que eram.'}',
    );
  }
  final written = <InstructionsSnapshot>[
    for (final w in writes) await readInstructionsSnapshot(w.base.path),
  ];
  return InstructionsWriteResult(previous: previous, written: written);
}

/// "Desfazer" (R5): puts back the files of [result] as they were before,
/// refusing (with [InstructionsConflict]) when one changed since the write.
Future<InstructionsWriteResult> undoInstructionWrite(
  InstructionsWriteResult result, {
  @visibleForTesting InstructionsFs fs = const InstructionsFs(),
}) => writeInstructionFiles([
  for (var i = 0; i < result.written.length; i++)
    InstructionsWrite(result.written[i], result.previous[i].text),
], fs: fs);

Future<void> _deleteTemps(List<File?> temps) async {
  for (final t in temps) {
    try {
      if (t != null && await t.exists()) await t.delete();
    } catch (_) {}
  }
}

/// Best effort: [before] back on disk (the rollback of a failed write).
Future<void> _restore(InstructionsSnapshot before) async {
  try {
    final f = File(before.path);
    if (before.text == null) {
      if (await f.exists()) await f.delete();
      return;
    }
    final tmp = File('${before.path}$_tmpSuffix');
    await tmp.writeAsString(before.text!, flush: true);
    await tmp.rename(before.path);
  } catch (e) {
    debugPrint('instruções: não voltou ${before.path}: $e');
  }
}

// --- Tamanho (R11) -------------------------------------------------------------

/// What the Codex reads of an `AGENTS.md`: 32 KiB, cut without warning
/// (conferido no Codex 0.170, SPEC-113).
const codexInstructionsLimit = 32768;

enum InstructionsSizeLevel {
  /// Below 80% of the limit.
  ok,

  /// From 80% of the limit up to the limit (R11: warn).
  warning,

  /// Over the limit: the Codex cuts it (R11: show where).
  over,
}

/// Where the Codex cuts the text: the first byte left out (byte 32 768).
@immutable
class InstructionsCut {
  const InstructionsCut({
    required this.line,
    required this.column,
    required this.offset,
  });

  /// 1-based line of the first byte left out.
  final int line;

  /// 1-based column (in characters) of that byte in its line.
  final int column;

  /// UTF-16 index in the text (`String`) where the cut falls, for the
  /// editor; a character split by the cut counts as left out.
  final int offset;

  /// Whether the cut falls in the middle of a line.
  bool get midLine => column > 1;

  @override
  bool operator ==(Object other) =>
      other is InstructionsCut &&
      other.line == line &&
      other.column == column &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(line, column, offset);

  @override
  String toString() => 'linha $line, coluna $column';
}

/// The size of an instruction file against the Codex limit (R11).
@immutable
class InstructionsSize {
  const InstructionsSize({
    required this.bytes,
    required this.lines,
    required this.level,
    this.cut,
    this.limit = codexInstructionsLimit,
  });

  final int bytes;
  final int lines;
  final InstructionsSizeLevel level;

  /// Null unless [level] is [InstructionsSizeLevel.over].
  final InstructionsCut? cut;
  final int limit;

  /// [bytes] / [limit] (above 1 when over).
  double get fraction => bytes / limit;
}

int _utf8Length(int rune) => rune < 0x80
    ? 1
    : rune < 0x800
    ? 2
    : rune < 0x10000
    ? 3
    : 4;

/// Bytes and lines of [text] against [limit] (R11): warning from 80%,
/// over past the limit, with the line and column where the cut falls.
InstructionsSize instructionsSize(
  String text, {
  int limit = codexInstructionsLimit,
}) {
  final bytes = utf8.encode(text).length;
  final lines = text.isEmpty
      ? 0
      : '\n'.allMatches(text).length + (text.endsWith('\n') ? 0 : 1);
  final level = bytes > limit
      ? InstructionsSizeLevel.over
      : bytes * 5 >= limit * 4
      ? InstructionsSizeLevel.warning
      : InstructionsSizeLevel.ok;
  InstructionsCut? cut;
  if (level == InstructionsSizeLevel.over) {
    var byte = 0;
    var offset = 0;
    var line = 1;
    var column = 1;
    for (final rune in text.runes) {
      final len = _utf8Length(rune);
      if (byte + len > limit) break;
      byte += len;
      offset += rune > 0xFFFF ? 2 : 1;
      if (rune == 0x0A) {
        line++;
        column = 1;
      } else {
        column++;
      }
    }
    cut = InstructionsCut(line: line, column: column, offset: offset);
  }
  return InstructionsSize(
    bytes: bytes,
    lines: lines,
    level: level,
    cut: cut,
    limit: limit,
  );
}
