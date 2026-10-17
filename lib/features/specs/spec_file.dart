import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;
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
  SpecStatus.archived => 'arquivada',
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
    'arquivada' || 'arquivado' || 'archived' => SpecStatus.archived,
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
  SpecStatus.archived => 'Arquivada',
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

  /// Frontmatter `subagentes` (invalid items are ignored).
  List<SpecSubagent> get subagents {
    final v = frontmatter[subagentsKey];
    if (v is! List) return const [];
    final out = <SpecSubagent>[];
    for (final e in v) {
      if (e is! Map) continue;
      final agent = '${e['agente'] ?? ''}'.trim();
      final when = SubagentWhen.fromValue('${e['quando'] ?? ''}');
      if (agent.isEmpty || when == null) continue;
      final step = '${e['etapa'] ?? ''}'.trim().toUpperCase();
      final text = '${e['instrucao'] ?? ''}'.trim();
      out.add(
        SpecSubagent(
          agent: agent,
          when: when,
          step: step.isEmpty ? null : step,
          instruction: text.isEmpty ? null : text,
        ),
      );
    }
    return out;
  }

  /// Text with the `subagentes` block of the frontmatter replaced by
  /// [list] (removed when empty). Other lines are kept byte for byte.
  String withSubagents(List<SpecSubagent> list) {
    final block = <String>[
      if (list.isNotEmpty) '$subagentsKey:',
      for (final a in list) ...[
        '  - agente: ${a.agent}',
        '    quando: ${a.when.value}',
        if (a.step != null) '    etapa: ${a.step}',
        if (a.instruction != null)
          '    instrucao: ${jsonEncode(a.instruction)}',
      ],
    ];
    if (!hasFrontmatter) {
      if (block.isEmpty) return text;
      return '---\n${block.join('\n')}\n---\n${text.startsWith('\n') ? '' : '\n'}$text';
    }
    final start = _frontmatterStart.firstMatch(text)!;
    final close = _fence.allMatches(text, start.end).first;
    final head = text.substring(0, start.end);
    final lines = text.substring(start.end, close.start).split('\n');
    final trailing = lines.isNotEmpty && lines.last.isEmpty;
    if (trailing) lines.removeLast();
    final keyRe = RegExp(r'^[A-Za-z_][\w-]*\s*:');
    final out = <String>[];
    var replaced = false;
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (RegExp('^$subagentsKey\\s*:').hasMatch(l)) {
        // Skip the old block: everything up to the next top-level key.
        while (i + 1 < lines.length && !keyRe.hasMatch(lines[i + 1])) {
          i++;
        }
        out.addAll(block);
        replaced = true;
      } else {
        out.add(l);
      }
    }
    if (!replaced) out.addAll(block);
    return '$head${out.join('\n')}\n${text.substring(close.start)}';
  }

  /// First `# ` heading of the body.
  String? get title {
    for (final line in body.split('\n')) {
      final m = RegExp(r'^#\s+(.+?)\s*#*\s*$').firstMatch(line.trimRight());
      if (m != null) return m.group(1)!.trim();
    }
    return null;
  }

  /// Text of the `## <name>` section (accents / case tolerated; up to the
  /// next `##`), or null when the spec has none.
  String? section(String name) {
    String fold(String s) => s
        .toLowerCase()
        .replaceAll(RegExp('[áàâã]'), 'a')
        .replaceAll(RegExp('[éê]'), 'e')
        .replaceAll('í', 'i')
        .replaceAll(RegExp('[óôõ]'), 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ç', 'c');
    final want = fold(name);
    final lines = body.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final h = RegExp(r'^##\s+(.+?)\s*#*\s*$')
          .firstMatch(lines[i].trimRight());
      if (h == null || !fold(h.group(1)!).startsWith(want)) continue;
      final out = <String>[];
      for (var j = i + 1; j < lines.length; j++) {
        if (RegExp(r'^##\s').hasMatch(lines[j])) break;
        out.add(lines[j]);
      }
      return out.join('\n').trim();
    }
    return null;
  }

  /// `## Objetivo`.
  String? get objective => section('Objetivo');

  /// `## Design` without HTML comments (the template's hint); null when
  /// absent or empty.
  String? get design {
    final d = section('Design')?.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
    return d == null || d.trim().isEmpty ? null : d.trim();
  }

  /// Frontmatter `design: dispensado` (a trivial spec approved without it).
  bool get designWaived =>
      '${frontmatter['design'] ?? ''}'.trim().toLowerCase() == 'dispensado';

  /// `## Etapas`: `- R2 → lib/a.dart, lib/b.dart · verificar: cmd`.
  Map<String, StepPlan> get stepPlans {
    final text = section('Etapas');
    if (text == null) return const {};
    final out = <String, StepPlan>{};
    for (final line in text.split('\n')) {
      final m = RegExp(
        r'^\s*[-*+]\s+\**((?:REV|R)\d+)\**\s*(?:→|->|:|·)?\s*(.*)$',
      ).firstMatch(line);
      if (m == null) continue;
      var rest = m.group(2)!.trim();
      String? verify;
      final v = RegExp(
        r'\s*(?:[·—–|-]\s*)?verificar:\s*`?([^`]+?)`?\s*$',
        caseSensitive: false,
      ).firstMatch(rest);
      if (v != null) {
        verify = v.group(1)!.trim();
        rest = rest.substring(0, v.start).trim();
      }
      out[m.group(1)!] = StepPlan(
        files: [
          for (final f in rest.split(RegExp(r'[,\s]+')))
            if (f.contains('/') || f.contains('.')) f.replaceAll('`', ''),
        ],
        verify: verify == null || verify.isEmpty ? null : verify,
      );
    }
    return out;
  }

  /// Text with the `## Design` section set to [design] (added after the
  /// requirements when absent) and, when given, `## Etapas` to [plans].
  String withDesign(String design, {Map<String, StepPlan>? plans}) {
    var out = _withSection(text, 'Design', design.trim(), after: 'Requisitos');
    if (plans != null && plans.isNotEmpty) {
      final lines = [
        for (final MapEntry(:key, :value) in plans.entries)
          '- $key → ${value.files.join(', ')}'
              '${value.verify == null ? '' : ' · verificar: `${value.verify}`'}',
      ];
      out = _withSection(out, 'Etapas', lines.join('\n'), after: 'Design');
    }
    return out;
  }

  static String _withSection(
    String text,
    String name,
    String content, {
    required String after,
  }) {
    final lines = text.split('\n');
    bool isHeading(String l, String n) => RegExp(
      '^##\\s+${RegExp.escape(n)}\\b',
      caseSensitive: false,
    ).hasMatch(l.trimRight());
    final i = lines.indexWhere((l) => isHeading(l, name));
    final block = ['## $name', '', content, ''];
    if (i >= 0) {
      var j = i + 1;
      while (j < lines.length && !RegExp(r'^##\s').hasMatch(lines[j])) {
        j++;
      }
      lines.replaceRange(i, j, block);
      return lines.join('\n');
    }
    final a = lines.indexWhere((l) => isHeading(l, after));
    if (a < 0) return '${text.trimRight()}\n\n${block.join('\n')}';
    var j = a + 1;
    while (j < lines.length && !RegExp(r'^##\s').hasMatch(lines[j])) {
      j++;
    }
    if (j > 0 && lines[j - 1].trim().isNotEmpty) block.insert(0, '');
    lines.insertAll(j, block);
    return lines.join('\n');
  }

  /// Requirement lines (`- R1 · texto`, `- [ ] R2: texto`, `1. R3 - texto`)
  /// of the `## Requisitos` section (the whole body when there is none).
  List<SpecRequirement> get requirements {
    final re = RegExp(
      r'^\s*(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s+)?\**(R\d+)\**\b\s*[·:.\-–—]?\s*(.*)$',
    );
    final out = <SpecRequirement>[];
    final seen = <String>{};
    for (final line in (section('Requisitos') ?? body).split('\n')) {
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
  String withMeta({
    String? id,
    SpecStatus? status,
    List<String>? dependsOn,
    bool? designWaived,
  }) {
    final updates = <String, String>{
      'id': ?id,
      if (status != null) 'status': specStatusValue(status),
      if (dependsOn != null) dependsOnKey: '[${dependsOn.join(', ')}]',
      if (designWaived == true) 'design': 'dispensado',
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

/// When a subagent of a spec is called (frontmatter `subagentes`).
enum SubagentWhen {
  specStart('inicio-da-spec', 'Início da spec'),
  beforeEach('antes-de-cada-etapa', 'Antes de cada etapa'),
  afterEach('depois-de-cada-etapa', 'Depois de cada etapa'),
  atStep('em-etapa', 'Ao terminar uma etapa'),
  specEnd('fim-da-spec', 'Fim da spec (antes do Review)');

  const SubagentWhen(this.value, this.label);

  final String value;
  final String label;

  static SubagentWhen? fromValue(String? v) {
    for (final w in values) {
      if (w.value == v?.trim()) return w;
    }
    return null;
  }
}

/// A subagent the step sessions of a spec must call, and when.
class SpecSubagent {
  const SpecSubagent({
    required this.agent,
    required this.when,
    this.step,
    this.instruction,
  });

  final String agent;
  final SubagentWhen when;

  /// `R3` for [SubagentWhen.atStep].
  final String? step;
  final String? instruction;

  @override
  bool operator ==(Object other) =>
      other is SpecSubagent &&
      other.agent == agent &&
      other.when == when &&
      other.step == step &&
      other.instruction == instruction;

  @override
  int get hashCode => Object.hash(agent, when, step, instruction);

  /// `spec-reviewer · fim da spec`.
  String get summary => switch (when) {
    SubagentWhen.atStep => '$agent · ao terminar ${step ?? '?'}',
    _ => '$agent · ${when.label.toLowerCase()}',
  };
}

/// Frontmatter key of the spec dependencies.
const dependsOnKey = 'depende-de';

/// Frontmatter key of the subagents of the spec.
const subagentsKey = 'subagentes';

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

## Design

<!-- Como implementar: componentes, arquivos e decisões. Use "Gerar design". -->

## Critérios de aceite

- [ ]
''';

final _requirementLine = RegExp(
  r'^\s*(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s+)?\**(R\d+)\**\b',
);

/// Text of the spec that changes [originalCode] ("Clonar para alterar"):
/// new `id`, status draft, `depende-de` the original, the title marked as an
/// alteration, requirements in [doneIds] removed and the rest renumbered
/// from R1. Without requirements left, an empty `- R1 ·` is offered.
String cloneSpecText(
  String text, {
  required String newCode,
  required String originalCode,
  required Set<String> doneIds,
}) {
  final meta = SpecDocument.parse(
    text,
  ).withMeta(id: newCode, status: SpecStatus.draft, dependsOn: [originalCode]);
  final doc = SpecDocument.parse(meta);
  final lines = doc.body.split('\n');
  final out = <String>[];
  var titled = false;
  var n = 0;
  for (final line in lines) {
    if (!titled) {
      final m = RegExp(r'^#\s+(.+?)\s*#*\s*$').firstMatch(line.trimRight());
      if (m != null) {
        titled = true;
        out.add('# ${m.group(1)!.trim()} (alteração)');
        continue;
      }
    }
    final r = _requirementLine.firstMatch(line);
    if (r != null) {
      if (doneIds.contains(r.group(1))) continue;
      n++;
      out.add(line.replaceFirst(RegExp(r'\bR\d+\b'), 'R$n'));
      continue;
    }
    out.add(line);
  }
  if (n == 0) {
    final i = out.indexWhere(
      (l) => RegExp(r'^#{2,}\s*Requisitos\b', caseSensitive: false).hasMatch(l),
    );
    if (i >= 0) {
      out.insertAll(i + 1, ['', '- R1 ·']);
    } else {
      out.addAll(['', '## Requisitos', '', '- R1 ·', '']);
    }
  }
  return meta.substring(0, doc.bodyStart) + out.join('\n');
}

/// One line of `## Etapas`: the files a step touches and its own check.
@immutable
class StepPlan {
  const StepPlan({this.files = const [], this.verify});

  final List<String> files;
  final String? verify;
}

/// One line of "## Critérios de aceite": `- [ ] texto [R2] · verificar: cmd`.
@immutable
class SpecCriterion {
  const SpecCriterion({
    required this.text,
    this.requirements = const [],
    this.verify,
    this.checkedInFile = false,
  });

  /// The line without the checkbox and the `verificar:` part (also the key
  /// of its state in `spec_criteria`).
  final String text;

  /// `[R1, R2]` of the line.
  final List<String> requirements;

  /// Shell command that checks it (run by the step gate).
  final String? verify;

  /// `- [x]` in the file.
  final bool checkedInFile;
}

/// Lines of the section "Critérios de aceite" (accents / case tolerated),
/// empty ones (`- [ ]`) skipped.
List<SpecCriterion> parseCriteria(String text) {
  final out = <SpecCriterion>[];
  var inSection = false;
  for (final line in text.split('\n')) {
    final h = RegExp(r'^#{2,}\s*(.+?)\s*$').firstMatch(line.trim());
    if (h != null) {
      inSection = RegExp(
        r'^crit[eé]rios(\s+de\s+aceita[cç][aã]o|\s+de\s+aceite)?\b',
        caseSensitive: false,
      ).hasMatch(h.group(1)!);
      continue;
    }
    if (!inSection) continue;
    final m = RegExp(r'^\s*[-*+]\s+\[([ xX])\]\s*(.*)$').firstMatch(line);
    if (m == null) continue;
    var body = m.group(2)!.trim();
    String? verify;
    final v = RegExp(
      r'\s*(?:[·—–|-]\s*)?verificar:\s*`?([^`]+?)`?\s*$',
      caseSensitive: false,
    ).firstMatch(body);
    if (v != null) {
      verify = v.group(1)!.trim();
      body = body.substring(0, v.start).trim();
    }
    if (body.isEmpty) continue;
    final reqs = <String>[
      for (final r in RegExp(r'\[([^\]]*)\]').allMatches(body))
        for (final id in RegExp(r'\bR\d+\b').allMatches(r.group(1)!))
          id.group(0)!,
    ];
    out.add(
      SpecCriterion(
        text: body,
        requirements: reqs,
        verify: verify == null || verify.isEmpty ? null : verify,
        checkedInFile: m.group(1) != ' ',
      ),
    );
  }
  return out;
}

/// `SPEC-007` from `specs/SPEC-007-algo.md` (null when the name differs).
String? specCodeFromFileName(String fileName) {
  final m = RegExp(r'^(SPEC-\d+)').firstMatch(fileName);
  return m?.group(1);
}
