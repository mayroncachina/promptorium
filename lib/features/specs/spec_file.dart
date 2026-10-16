import 'package:yaml/yaml.dart';

import '../../data/db/app_database.dart';

export '../../data/db/app_database.dart' show SpecRequirement;

/// Spec files: `specs/SPEC-NNN-<slug>.md` in the workspace, with a YAML
/// frontmatter holding `id` and `status` (plano, Fase 8).

/// Frontmatter value of each status (mockup Specs: `status: em-revisao`).
String specStatusValue(SpecStatus s) => switch (s) {
  SpecStatus.idea => 'ideia',
  SpecStatus.draft => 'rascunho',
  SpecStatus.review => 'em-revisao',
  SpecStatus.approved => 'aprovada',
  SpecStatus.done => 'concluida',
};

/// Status of a frontmatter value (accents / case / English names tolerated).
SpecStatus? specStatusFromValue(String? value) {
  if (value == null) return null;
  final v = value
      .trim()
      .toLowerCase()
      .replaceAll('ã', 'a')
      .replaceAll('ç', 'c')
      .replaceAll('í', 'i')
      .replaceAll('é', 'e')
      .replaceAll(RegExp(r'[\s_]+'), '-');
  return switch (v) {
    'ideia' || 'idea' => SpecStatus.idea,
    'rascunho' || 'draft' => SpecStatus.draft,
    'em-revisao' || 'revisao' || 'review' => SpecStatus.review,
    'aprovada' || 'aprovado' || 'approved' => SpecStatus.approved,
    'concluida' || 'feita' || 'done' => SpecStatus.done,
    _ => null,
  };
}

/// Label shown in the UI.
String specStatusLabel(SpecStatus s) => switch (s) {
  SpecStatus.idea => 'Ideia',
  SpecStatus.draft => 'Rascunho',
  SpecStatus.review => 'Em revisão',
  SpecStatus.approved => 'Aprovada',
  SpecStatus.done => 'Concluída',
};

final _frontmatterStart = RegExp(r'^﻿?---[ \t]*\r?\n');
final _fence = RegExp(r'^---[ \t]*$', multiLine: true);

/// Parsed spec file. The text is kept as is; [withMeta] edits only the
/// `id:` / `status:` lines of the frontmatter.
class SpecDocument {
  SpecDocument._(this.text, this.frontmatter, this.bodyStart);

  /// Full file text.
  final String text;

  /// Frontmatter map (empty when absent or invalid).
  final Map<String, Object?> frontmatter;

  /// Offset where the body starts (after the closing `---`).
  final int bodyStart;

  factory SpecDocument.parse(String text) {
    final start = _frontmatterStart.firstMatch(text);
    if (start == null) return SpecDocument._(text, const {}, 0);
    final close = _fence.allMatches(text, start.end).firstOrNull;
    if (close == null) return SpecDocument._(text, const {}, 0);
    final yamlText = text.substring(start.end, close.start);
    var end = close.end;
    if (end < text.length && text[end] == '\r') end++;
    if (end < text.length && text[end] == '\n') end++;
    Map<String, Object?> map = const {};
    try {
      final y = loadYaml(yamlText);
      if (y is YamlMap) {
        map = {for (final e in y.entries) '${e.key}': e.value};
      }
    } catch (_) {
      // Invalid YAML: treated as no metadata (the text is kept).
    }
    return SpecDocument._(text, map, end);
  }

  bool get hasFrontmatter => bodyStart > 0;

  String get body => text.substring(bodyStart);

  /// `id` of the frontmatter (`SPEC-001`).
  String? get id {
    final v = frontmatter['id'];
    return v == null ? null : '$v'.trim();
  }

  String? get rawStatus {
    final v = frontmatter['status'];
    return v == null ? null : '$v';
  }

  SpecStatus? get status => specStatusFromValue(rawStatus);

  /// Frontmatter `fase` (`fundacao`, `mvp`…).
  String? get phase {
    final v = frontmatter['fase'];
    return v == null || '$v'.trim().isEmpty ? null : '$v'.trim();
  }

  /// Whether the frontmatter has `depende-de` (even empty).
  bool get hasDependsOn => frontmatter.containsKey(dependsOnKey);

  /// Frontmatter `depende-de`: `[SPEC-001, SPEC-002]` or `SPEC-001, SPEC-002`.
  List<String> get dependsOn {
    final v = frontmatter[dependsOnKey];
    final items = v is List
        ? v.map((e) => '$e')
        : '${v ?? ''}'.split(RegExp(r'[\s,;]+'));
    return [
      for (final i in items)
        if (RegExp(r'^SPEC-\d+$').hasMatch(i.trim().toUpperCase()))
          i.trim().toUpperCase(),
    ];
  }

  /// First `# ` heading of the body.
  String? get title {
    for (final line in body.split('\n')) {
      final m = RegExp(r'^#\s+(.+?)\s*#*\s*$').firstMatch(line.trimRight());
      if (m != null) return m.group(1)!.trim();
    }
    return null;
  }

  /// Requirement lines (`- R1 · texto`, `- [ ] R2: texto`, `1. R3 - texto`).
  List<SpecRequirement> get requirements {
    final re = RegExp(
      r'^\s*(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s+)?\**(R\d+)\**\b\s*[·:.\-–—]?\s*(.*)$',
    );
    final out = <SpecRequirement>[];
    final seen = <String>{};
    for (final line in body.split('\n')) {
      final m = re.firstMatch(line);
      if (m == null) continue;
      final id = m.group(1)!;
      if (seen.add(id)) out.add((id: id, text: m.group(2)!.trim()));
    }
    return out;
  }

  /// Text with `id` / `status` / `depende-de` set in the frontmatter
  /// (created when absent). Other lines (unknown keys, comments) are kept
  /// byte for byte.
  String withMeta({String? id, SpecStatus? status, List<String>? dependsOn}) {
    final updates = <String, String>{
      'id': ?id,
      if (status != null) 'status': specStatusValue(status),
      if (dependsOn != null) dependsOnKey: '[${dependsOn.join(', ')}]',
    };
    if (updates.isEmpty) return text;
    if (!hasFrontmatter) {
      final b = StringBuffer('---\n');
      updates.forEach((k, v) => b.writeln('$k: $v'));
      b.writeln('---');
      if (!text.startsWith('\n')) b.writeln();
      return '$b$text';
    }
    final start = _frontmatterStart.firstMatch(text)!;
    final close = _fence.allMatches(text, start.end).first;
    final head = text.substring(0, start.end);
    final lines = text.substring(start.end, close.start).split('\n');
    // The block ends with '\n' before the closing fence: last item is ''.
    final trailing = lines.isNotEmpty && lines.last.isEmpty;
    if (trailing) lines.removeLast();
    final pending = Map.of(updates);
    for (var i = 0; i < lines.length; i++) {
      final m = RegExp(r'^([A-Za-z_][\w-]*)\s*:').firstMatch(lines[i]);
      if (m == null) continue;
      final key = m.group(1)!;
      final value = pending.remove(key);
      if (value != null) {
        final cr = lines[i].endsWith('\r') ? '\r' : '';
        lines[i] = '$key: $value$cr';
      }
    }
    pending.forEach((k, v) => lines.add('$k: $v'));
    return '$head${lines.join('\n')}\n${text.substring(close.start)}';
  }
}

/// Frontmatter key of the spec dependencies.
const dependsOnKey = 'depende-de';

/// Markdown of a new spec ("Nova spec").
String newSpecMarkdown({required String code, required String title}) =>
    '''
---
id: $code
status: ${specStatusValue(SpecStatus.draft)}
---

# $title

## Objetivo

Descreva o problema e o resultado esperado.

## Requisitos

- R1 ·

## Critérios de aceite

- [ ]
''';

/// `SPEC-007` from `specs/SPEC-007-algo.md` (null when the name differs).
String? specCodeFromFileName(String fileName) {
  final m = RegExp(r'^(SPEC-\d+)').firstMatch(fileName);
  return m?.group(1);
}
