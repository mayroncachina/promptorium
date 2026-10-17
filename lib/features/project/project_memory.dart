import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One line of `.promptorium/memoria.md`:
/// `- texto  <!-- origem, 2026-10-17 -->`.
@immutable
class MemoryEntry {
  const MemoryEntry({required this.text, this.origin = 'você', this.date});

  final String text;

  /// `SPEC-003 R2` (an APRENDIZADO of a step), `verificação` (the gate) or
  /// `você` (written by hand).
  final String origin;
  final DateTime? date;

  String toLine() {
    final d = date == null ? '' : ', ${_day(date!)}';
    return '- $text  <!-- $origin$d -->';
  }

  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Learned facts of the project (F8), versioned with the repository at
/// `.promptorium/memoria.md` and sent in the prompt of every step session,
/// the automatic reviewer and "Gerar design". At most [maxEntries] lines:
/// the oldest go first.
@immutable
class ProjectMemory {
  const ProjectMemory(this.entries);

  static const filePath = '.promptorium/memoria.md';
  static const maxEntries = 60;

  static const _header =
      '# Memória do projeto\n\n'
      '<!-- Escrita pelo Promptorium e por você. Uma linha por fato; vai no '
      'prompt das sessões de etapa. Máximo de $maxEntries linhas. -->\n';

  final List<MemoryEntry> entries;

  bool get isEmpty => entries.isEmpty;

  factory ProjectMemory.parse(String text) {
    final out = <MemoryEntry>[];
    for (final line in text.split('\n')) {
      final m = RegExp(r'^\s*[-*]\s+(.+?)\s*$').firstMatch(line);
      if (m == null) continue;
      var body = m.group(1)!;
      var origin = 'você';
      DateTime? date;
      final meta = RegExp(r'\s*<!--\s*(.*?)\s*-->\s*$').firstMatch(body);
      if (meta != null) {
        body = body.substring(0, meta.start).trim();
        final parts = meta.group(1)!.split(',');
        if (parts.first.trim().isNotEmpty) origin = parts.first.trim();
        if (parts.length > 1) date = DateTime.tryParse(parts[1].trim());
      }
      if (body.isNotEmpty) {
        out.add(MemoryEntry(text: body, origin: origin, date: date));
      }
    }
    return ProjectMemory(out);
  }

  String toMarkdown() =>
      '$_header\n${[for (final e in entries) e.toLine()].join('\n')}\n';

  /// Lines for a prompt (no metadata).
  String toPrompt() => [for (final e in entries) '- ${e.text}'].join('\n');

  /// [e] added at the end (an equal text is moved); [replacing] drops the
  /// entries it matches first (e.g. the old time of the same command).
  ProjectMemory add(MemoryEntry e, {bool Function(MemoryEntry)? replacing}) {
    final kept = [
      for (final x in entries)
        if (x.text != e.text && !(replacing?.call(x) ?? false)) x,
    ];
    final all = [...kept, e];
    return ProjectMemory(
      all.length > maxEntries ? all.sublist(all.length - maxEntries) : all,
    );
  }

  ProjectMemory remove(MemoryEntry e) => ProjectMemory([
    for (final x in entries)
      if (!identical(x, e)) x,
  ]);

  /// "Limpar entradas com mais de 30 dias" (entries without a date stay).
  ProjectMemory withoutOlderThan(Duration age, {DateTime? now}) {
    final limit = (now ?? DateTime.now()).subtract(age);
    return ProjectMemory([
      for (final e in entries)
        if (e.date == null || !e.date!.isBefore(limit)) e,
    ]);
  }

  static ProjectMemory loadSync(String workspacePath) {
    try {
      final f = File('$workspacePath/$filePath');
      return f.existsSync()
          ? ProjectMemory.parse(f.readAsStringSync())
          : const ProjectMemory([]);
    } catch (_) {
      return const ProjectMemory([]);
    }
  }

  static Future<void> save(String workspacePath, ProjectMemory m) async {
    final f = File('$workspacePath/$filePath');
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(m.toMarkdown(), flush: true);
    await tmp.rename(f.path);
  }

  /// Adds [e] to the workspace's file (errors only log).
  static Future<void> record(
    String workspacePath,
    MemoryEntry e, {
    bool Function(MemoryEntry)? replacing,
  }) async {
    try {
      await save(
        workspacePath,
        loadSync(workspacePath).add(e, replacing: replacing),
      );
    } catch (err) {
      debugPrint('memória do projeto não gravada — $err');
    }
  }
}

/// The `APRENDIZADO: …` of a step answer (last one; null = none).
String? parseLearning(String? text) {
  if (text == null) return null;
  final m = RegExp(
    r'^\s*APRENDIZADO\s*:\s*(.+?)\s*$',
    caseSensitive: false,
    multiLine: true,
  ).allMatches(text).lastOrNull;
  final s = m?.group(1)?.trim();
  return s == null || s.isEmpty ? null : s;
}

/// Memory of a workspace (by path). Invalidate after saving.
final projectMemoryProvider = FutureProvider.family<ProjectMemory, String>(
  (ref, path) async => ProjectMemory.loadSync(path),
);
