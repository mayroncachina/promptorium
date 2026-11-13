import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/process/process_runner.dart';

/// "Conte a ideia" takes up to 40.000 characters (SPEC-057 R7).
const ideaMaxChars = 40000;

/// Files above 20 MB are not read (R7).
const ideaMaxBytes = 20 * 1024 * 1024;

/// PDFs with more pages than this show the progress card (R4).
const ideaProgressMinPages = 5;

/// Command shown when `pdftotext` is missing (R7).
const popplerInstallCommand = 'sudo apt install poppler-utils';

/// What a file was read as.
enum ImportKind {
  pdf('PDF'),
  markdown('Markdown'),
  text('TXT');

  const ImportKind(this.label);

  /// "PDF", "Markdown", "TXT".
  final String label;

  /// Kind for [path] by extension; null when not accepted.
  static ImportKind? of(String path) =>
      switch (p.extension(path).toLowerCase()) {
        '.pdf' => pdf,
        '.md' || '.markdown' => markdown,
        '.txt' => text,
        _ => null,
      };
}

/// Extensions offered by the file chooser (R1).
const ideaImportExtensions = ['pdf', 'md', 'markdown', 'txt'];

/// `1.284`.
String formatCount(int n) {
  final s = '${n.abs()}';
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

/// `24,3` (MB, one decimal, without a trailing `,0`).
String formatMegabytes(int bytes) {
  final mb = bytes / (1024 * 1024);
  final s = mb.toStringAsFixed(1);
  return (s.endsWith('.0') ? s.substring(0, s.length - 2) : s).replaceAll(
    '.',
    ',',
  );
}

/// A notice that comes with the text (it still goes into the field).
sealed class ImportWarning {
  const ImportWarning();

  String get title;
  String get detail;
}

/// The text went over the limit and was cut at a paragraph (R7).
class TruncatedWarning extends ImportWarning {
  const TruncatedWarning({
    required this.total,
    required this.limit,
    required this.overflow,
  });

  /// Characters in the whole file text.
  final int total;

  /// Characters the field had room for.
  final int limit;

  /// What was left out ("Ver o que ficou de fora").
  final String overflow;

  @override
  String get title =>
      'O arquivo tem ${formatCount(total)} caracteres; o campo aceita '
      '${formatCount(ideaMaxChars)}.';

  @override
  String get detail =>
      'Carregamos o começo e paramos no fim de um parágrafo. Corte o que não '
      'importa ou resuma antes de planejar.';
}

/// A TXT outside UTF-8 was read as Latin-1 (R7).
class EncodingWarning extends ImportWarning {
  const EncodingWarning();

  @override
  String get title => 'Alguns caracteres não foram reconhecidos.';

  @override
  String get detail =>
      'O TXT não está em UTF-8; trocamos os acentos que não deu para ler por '
      '“?”. Confira o texto.';
}

/// The text read from a file (R3), already within the limit (R7).
class ImportedText {
  const ImportedText({
    required this.path,
    required this.kind,
    required this.text,
    required this.fullText,
    this.pages,
    this.warnings = const [],
  });

  final String path;
  final ImportKind kind;

  /// What goes into the field (cut when over the limit).
  final String text;

  /// The whole cleaned text, before the cut.
  final String fullText;

  /// Pages of a PDF; null for TXT and Markdown.
  final int? pages;

  final List<ImportWarning> warnings;

  String get name => p.basename(path);

  int get chars => text.length;

  TruncatedWarning? get truncated =>
      warnings.whereType<TruncatedWarning>().firstOrNull;

  /// This text fitted in [room] characters (R7), cut at the end of the last
  /// paragraph that fits. Used again when the text is added after what the
  /// field already has (R6).
  ImportedText fit(int room) {
    final others = [
      for (final w in warnings)
        if (w is! TruncatedWarning) w,
    ];
    final (cut, rest) = cutAtParagraph(fullText, room);
    return ImportedText(
      path: path,
      kind: kind,
      text: cut,
      fullText: fullText,
      pages: pages,
      warnings: [
        if (rest.isNotEmpty)
          TruncatedWarning(total: fullText.length, limit: room, overflow: rest),
        ...others,
      ],
    );
  }
}

/// Why a file was not imported (R7). The field stays as it was.
sealed class ImportProblem implements Exception {
  const ImportProblem();

  String get title;
  String get detail;

  /// A command to show in monospace, when there is one.
  String? get command => null;
}

/// A PDF without a text layer (scanned).
class NoTextProblem extends ImportProblem {
  const NoTextProblem();

  @override
  String get title => 'Este PDF não tem texto para ler.';

  @override
  String get detail =>
      'Parece uma imagem escaneada. Copie o texto de outra fonte ou exporte o '
      'documento como PDF com texto.';
}

/// `.docx`, images…
class UnsupportedProblem extends ImportProblem {
  const UnsupportedProblem(this.extension);

  /// Without the dot; empty when the file has no extension.
  final String extension;

  @override
  String get title => extension.isEmpty
      ? 'Ainda não dá para importar este arquivo.'
      : 'Ainda não dá para importar .$extension.';

  @override
  String get detail => 'Salve como PDF, Markdown ou TXT.';
}

class PasswordProblem extends ImportProblem {
  const PasswordProblem();

  @override
  String get title => 'O PDF tem senha.';

  @override
  String get detail =>
      'Abra no leitor de PDF, salve uma cópia sem senha e importe essa cópia.';
}

class TooBigProblem extends ImportProblem {
  const TooBigProblem(this.bytes);

  final int bytes;

  @override
  String get title =>
      'O arquivo tem ${formatMegabytes(bytes)} MB; o limite é 20 MB.';

  @override
  String get detail => 'Importe só a parte que importa, num arquivo menor.';
}

class NoPdftotextProblem extends ImportProblem {
  const NoPdftotextProblem();

  @override
  String get title => 'Para ler PDF, instale o pacote poppler-utils.';

  @override
  String get detail => 'Rode no terminal e importe de novo:';

  @override
  String get command => popplerInstallCommand;
}

/// The file could not be opened (gone, no permission, broken PDF).
class UnreadableProblem extends ImportProblem {
  const UnreadableProblem(this.reason);

  final String reason;

  @override
  String get title => 'Não deu para ler o arquivo.';

  @override
  String get detail => reason;
}

/// Thrown by [IdeaImport.read] when [ImportCancel.cancel] was called.
class ImportCancelled implements Exception {
  const ImportCancelled();
}

/// Lets the progress card stop a PDF between pages (R4).
class ImportCancel {
  bool _cancelled = false;

  bool get cancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// Page `page` of `total` was read.
typedef ImportProgress = void Function(int page, int total);

/// Reads a PDF, Markdown or TXT file into the text of "Conte a ideia"
/// (SPEC-057 R3, R7).
class IdeaImport {
  IdeaImport(this._run);

  final ProcessRunner _run;

  /// The text of [path], cut at [limit] characters. Throws an
  /// [ImportProblem] or, when [cancel] fires, [ImportCancelled].
  Future<ImportedText> read(
    String path, {
    int limit = ideaMaxChars,
    ImportProgress? onProgress,
    ImportCancel? cancel,
  }) async {
    final kind = ImportKind.of(path);
    if (kind == null) {
      final ext = p.extension(path);
      throw UnsupportedProblem(
        ext.isEmpty ? '' : ext.substring(1).toLowerCase(),
      );
    }
    final file = File(path);
    final int size;
    try {
      size = await file.length();
    } on FileSystemException catch (e) {
      throw UnreadableProblem(e.osError?.message ?? e.message);
    }
    if (size > ideaMaxBytes) throw TooBigProblem(size);
    final ImportedText whole;
    if (kind == ImportKind.pdf) {
      whole = await _readPdf(path, onProgress, cancel);
    } else {
      whole = await _readText(file, kind);
    }
    if (cancel?.cancelled ?? false) throw const ImportCancelled();
    return whole.fit(limit);
  }

  Future<ImportedText> _readText(File file, ImportKind kind) async {
    final List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException catch (e) {
      throw UnreadableProblem(e.osError?.message ?? e.message);
    }
    final (text, lossy) = decodeText(bytes);
    final clean = normalizeText(text);
    return ImportedText(
      path: file.path,
      kind: kind,
      text: clean,
      fullText: clean,
      warnings: [if (lossy) const EncodingWarning()],
    );
  }

  Future<ImportedText> _readPdf(
    String path,
    ImportProgress? onProgress,
    ImportCancel? cancel,
  ) async {
    final total = await _pdfPages(path);
    final pages = <String>[];
    if (total == null) {
      // No page count (pdfinfo missing or confused): the whole document in
      // one run, pages split by the form feed pdftotext writes after each.
      final out = await _pdftotext(path, null);
      pages.addAll(out.split('\f'));
      if (pages.isNotEmpty && pages.last.trim().isEmpty) pages.removeLast();
      onProgress?.call(pages.length, pages.length);
    } else {
      for (var i = 1; i <= total; i++) {
        if (cancel?.cancelled ?? false) throw const ImportCancelled();
        pages.add((await _pdftotext(path, i)).replaceAll('\f', ''));
        onProgress?.call(i, total);
      }
    }
    final text = cleanPdfPages(pages);
    if (text.isEmpty) throw const NoTextProblem();
    return ImportedText(
      path: path,
      kind: ImportKind.pdf,
      text: text,
      fullText: text,
      pages: total ?? pages.length,
    );
  }

  /// Pages from `pdfinfo`; null when it is missing or does not say.
  Future<int?> _pdfPages(String path) async {
    final ProcessResult r;
    try {
      r = await _run('pdfinfo', [path]);
    } on ProcessException {
      return null;
    }
    if (r.exitCode != 0) {
      _throwPdfError(r);
      return null;
    }
    final m = RegExp(
      r'^Pages:\s+(\d+)',
      multiLine: true,
    ).firstMatch('${r.stdout}');
    return m == null ? null : int.parse(m.group(1)!);
  }

  Future<String> _pdftotext(String path, int? page) async {
    final ProcessResult r;
    try {
      r = await _run('pdftotext', [
        '-layout',
        if (page != null) ...['-f', '$page', '-l', '$page'],
        path,
        '-',
      ]);
    } on ProcessException {
      throw const NoPdftotextProblem();
    }
    if (r.exitCode != 0) {
      _throwPdfError(r);
      throw UnreadableProblem(_firstLine('${r.stderr}'));
    }
    return '${r.stdout}';
  }

  /// Password-protected PDFs throw [PasswordProblem] (poppler exits 1 with
  /// "Incorrect password"); other errors are left to the caller.
  void _throwPdfError(ProcessResult r) {
    final err = '${r.stderr}';
    if (err.contains('password') || r.exitCode == 3) {
      throw const PasswordProblem();
    }
  }

  static String _firstLine(String s) {
    final line = s.trim().split('\n').first.trim();
    return line.isEmpty ? 'O PDF parece estar corrompido.' : line;
  }
}

final ideaImportProvider = Provider<IdeaImport>(
  (ref) => IdeaImport(ref.watch(processRunnerProvider)),
);

/// UTF-8 text of [bytes]; outside UTF-8, Latin-1 with the control range
/// turned into "?" (R7). The flag says whether the fallback was used.
(String, bool) decodeText(List<int> bytes) {
  var b = bytes;
  if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
    b = b.sublist(3);
  }
  try {
    return (utf8.decode(b), false);
  } on FormatException {
    final s = String.fromCharCodes([
      for (final c in b) (c >= 0x80 && c < 0xA0) ? 0x3F : c,
    ]);
    return (s, true);
  }
}

/// `\n` line breaks, no spaces at line ends, at most one blank line in a
/// row, nothing around the text (R3).
String normalizeText(String text) {
  final lines = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((l) => l.trimRight());
  final out = <String>[];
  for (final l in lines) {
    if (l.isEmpty && (out.isEmpty || out.last.isEmpty)) continue;
    out.add(l);
  }
  return out.join('\n').trim();
}

/// [text] cut at the end of the last paragraph that fits in [limit]
/// characters, and the rest. With no paragraph break in reach, falls back to
/// the last line break, then to the last sentence, then to [limit].
(String, String) cutAtParagraph(String text, int limit) {
  if (text.length <= limit) return (text, '');
  if (limit <= 0) return ('', text.trim());
  int at = text.lastIndexOf('\n\n', limit);
  if (at <= 0) at = text.lastIndexOf('\n', limit);
  if (at <= 0) {
    final m = RegExp(r'[.!?…](?=\s)').allMatches(text.substring(0, limit));
    at = m.isEmpty ? limit : m.last.end;
  }
  return (text.substring(0, at).trimRight(), text.substring(at).trim());
}

/// The text of a PDF from the `pdftotext -layout` output of each page (R3):
/// headers and footers repeated on every page are removed, the layout
/// spacing is collapsed and lines broken in the middle of a sentence are
/// joined.
String cleanPdfPages(List<String> pages) {
  final split = [
    for (final page in pages)
      [
        for (final l in page.replaceAll('\r\n', '\n').split('\n'))
          l.trim().replaceAll(RegExp(r'[ \t]{2,}'), ' '),
      ],
  ];
  _dropRepeated(split);
  final buf = <String>[];
  for (final lines in split) {
    final body = _joinBroken(lines);
    if (body.isEmpty) continue;
    if (buf.isNotEmpty && _continues(buf.last, body)) {
      buf[buf.length - 1] = _join(buf.last, body);
    } else {
      buf.add(body);
    }
  }
  return normalizeText(buf.join('\n\n'));
}

/// Removes the first and last lines (up to two each) that repeat on every
/// page, ignoring digits so "Página 3" matches "Página 4".
void _dropRepeated(List<List<String>> pages) {
  if (pages.where((l) => l.any((s) => s.isNotEmpty)).length < 2) return;
  String key(String s) => s.replaceAll(RegExp(r'\d+'), '#').toLowerCase();
  for (final fromTop in [true, false]) {
    for (var round = 0; round < 2; round++) {
      final edges = <int?>[];
      for (final lines in pages) {
        final i = fromTop
            ? lines.indexWhere((s) => s.isNotEmpty)
            : lines.lastIndexWhere((s) => s.isNotEmpty);
        edges.add(i < 0 ? null : i);
      }
      final keys = {
        for (var i = 0; i < pages.length; i++)
          if (edges[i] != null) key(pages[i][edges[i]!]),
      };
      if (keys.length != 1) break;
      // A lone page or a blank one cannot vouch for repetition.
      if (edges.where((e) => e != null).length < 2) break;
      for (var i = 0; i < pages.length; i++) {
        if (edges[i] != null) pages[i][edges[i]!] = '';
      }
    }
  }
}

final _bullet = RegExp(r'^([•▪◦·*\-–—]|\d+[.)]|[a-z][.)])\s');
final _sentenceEnd = RegExp(r'[.!?:;…]["”’)]*$');
final _fullStop = RegExp(r'[.!?…]["”’)]*$');

/// Whether [next] goes on the same line as [prev]. [next] is not a list
/// item and either [prev] does not end a sentence and [next] starts in
/// lowercase or [prev] is long (not a title), or [prev] ends a sentence but
/// fills the width of the page (85 % of the longest line).
bool _continuesLine(String prev, String next, int longest) {
  if (prev.isEmpty || next.isEmpty || _bullet.hasMatch(next)) return false;
  // A line that fills the width and ends a sentence is still in the middle
  // of a paragraph; a list item or a colon closes it.
  if (_sentenceEnd.hasMatch(prev)) {
    return _fullStop.hasMatch(prev) &&
        prev.length >= longest * .85 &&
        !_bullet.hasMatch(prev);
  }
  final first = next[0];
  final lower = first != first.toUpperCase() && first == first.toLowerCase();
  return lower || prev.length >= longest * .6;
}

String _join(String prev, String next) {
  if (prev.endsWith('-') &&
      prev.length > 1 &&
      RegExp(r'\p{L}', unicode: true).hasMatch(prev[prev.length - 2]) &&
      RegExp(r'^\p{Ll}', unicode: true).hasMatch(next)) {
    return prev.substring(0, prev.length - 1) + next;
  }
  return '$prev $next';
}

String _joinBroken(List<String> lines) {
  final longest = lines.fold(0, (m, l) => l.length > m ? l.length : m);
  final out = <String>[];
  var previous = ''; // the line as printed, before any join
  for (final l in lines) {
    if (out.isNotEmpty && _continuesLine(previous, l, longest)) {
      out[out.length - 1] = _join(out.last, l);
    } else {
      out.add(l);
    }
    previous = l;
  }
  return normalizeText(out.join('\n'));
}

/// A page that starts in lowercase after one that stopped mid-sentence goes
/// on the same paragraph.
bool _continues(String prevPage, String nextPage) {
  final last = prevPage.split('\n').last;
  if (last.isEmpty || _sentenceEnd.hasMatch(last)) return false;
  return RegExp(r'^\p{Ll}', unicode: true).hasMatch(nextPage);
}
