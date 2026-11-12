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

/// "Planejada" (SPEC-062 R2): a `## Plano` and not approved yet. Derived,
/// never written to the file.
bool specIsPlanned(SpecStatus status, {required bool hasPlan}) =>
    hasPlan &&
    (status == SpecStatus.idea ||
        status == SpecStatus.draft ||
        status == SpecStatus.review);

const plannedLabel = 'Planejada';

/// Label shown in the UI.
String specStatusLabel(SpecStatus s) => switch (s) {
  SpecStatus.idea => 'Ideia',
  SpecStatus.draft => 'Rascunho',
  SpecStatus.review => 'Em revisão',
  SpecStatus.approved => 'Aprovada',
  SpecStatus.done => 'Concluída',
  SpecStatus.archived => 'Arquivada',
};

/// Lower case without accents (section names).
String foldText(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[áàâã]'), 'a')
    .replaceAll(RegExp('[éê]'), 'e')
    .replaceAll('í', 'i')
    .replaceAll(RegExp('[óôõ]'), 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ç', 'c');

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
  /// next `##`), or null when the spec has none. Without [exact], a heading
  /// that starts with [name] also counts.
  String? section(String name, {bool exact = false}) {
    final r = _sectionRange(text, name, from: _bodyLine, exact: exact);
    if (r == null) return null;
    final lines = text.split('\n');
    return lines.sublist(r.start + 1, r.end).join('\n').trim();
  }

  /// 0-based line where the body starts.
  int get _bodyLine => '\n'.allMatches(text.substring(0, bodyStart)).length;

  /// Heading line and end (exclusive: the next `##` or the end) of the
  /// `## <name>` section of [text], searched from line [from].
  static ({int start, int end})? _sectionRange(
    String text,
    String name, {
    int from = 0,
    bool exact = false,
  }) {
    final want = foldText(name);
    final lines = text.split('\n');
    for (var i = from; i < lines.length; i++) {
      final h = RegExp(r'^##\s+(.+?)\s*#*\s*$')
          .firstMatch(lines[i].trimRight());
      if (h == null) continue;
      final found = foldText(h.group(1)!);
      if (exact ? found != want : !found.startsWith(want)) continue;
      var j = i + 1;
      while (j < lines.length && !RegExp(r'^##\s').hasMatch(lines[j])) {
        j++;
      }
      return (start: i, end: j);
    }
    return null;
  }

  /// Questions of `## Perguntas em aberto` (SPEC-028 R2): first-level
  /// items, each with the `- Sugestão:` subitem (or a first-level
  /// "Sugestão:" item right after it, the old format). HTML comments (the
  /// template's hint) are not questions.
  List<OpenQuestion> get openQuestions => openQuestionsScan.questions;

  /// The lines of "Perguntas em aberto" around [q] (SPEC-059 R7): the
  /// question's own lines ([first]..[last], 1-based) with up to [context]
  /// lines of the section before and after; null when the question is not
  /// in the text.
  QuestionExcerptLines? questionExcerpt(OpenQuestion q, {int context = 2}) {
    final r = _sectionRange(text, openQuestionsSection, from: _bodyLine);
    if (r == null || q.line <= r.start + 1 || q.line > r.end) return null;
    final all = text.split('\n');
    // 1-based: the section body is r.start + 2 .. r.end.
    final top = r.start + 2;
    var bottom = r.end;
    while (bottom > top && all[bottom - 1].trim().isEmpty) {
      bottom--;
    }
    final next = openQuestions
        .map((x) => x.line)
        .where((l) => l > q.line)
        .fold<int?>(null, (m, l) => m == null || l < m ? l : m);
    var last = (next ?? bottom + 1) - 1;
    while (last > q.line && all[last - 1].trim().isEmpty) {
      last--;
    }
    if (last > bottom) last = bottom;
    var from = (q.line - context).clamp(top, q.line);
    while (from < q.line && all[from - 1].trim().isEmpty) {
      from++;
    }
    var to = (last + context).clamp(last, bottom);
    while (to > last && all[to - 1].trim().isEmpty) {
      to--;
    }
    return QuestionExcerptLines(
      first: q.line,
      last: last,
      from: from,
      lines: all.sublist(from - 1, to),
    );
  }

  /// [openQuestions] plus what is outside the R1 format (SPEC-028 R2, R3).
  OpenQuestionsScan get openQuestionsScan {
    final r = _sectionRange(text, openQuestionsSection, from: _bodyLine);
    if (r == null) return const OpenQuestionsScan();
    final all = text.split('\n');
    // Comments blanked line by line: the line numbers stay.
    final body = all
        .sublist(r.start + 1, r.end)
        .join('\n')
        .replaceAllMapped(
          RegExp(r'<!--[\s\S]*?-->'),
          (m) => m.group(0)!.replaceAll(RegExp(r'[^\n]'), ''),
        )
        .split('\n');
    final items = <_QuestionDraft>[];
    final stray = <int>[];
    var unprefixed = false;
    // Where wrapped lines go: the question text or its suggestion.
    var toSuggestion = false;
    var skipping = false;
    for (var k = 0; k < body.length; k++) {
      final line = body[k];
      final lineNo = r.start + 2 + k;
      if (line.trim().isEmpty) continue;
      final m = _questionItemRe.firstMatch(line);
      if (m == null) {
        if (items.isEmpty || skipping) continue;
        final q = items.last;
        if (toSuggestion) {
          q.suggestion = '${q.suggestion} ${line.trim()}'.trim();
        } else {
          q.text = '${q.text} ${line.trim()}';
        }
        continue;
      }
      final indent = m.group(1)!.replaceAll('\t', '  ').length;
      var content = m.group(2)!;
      final label = _labelRe.firstMatch(content);
      final kind = label == null ? null : foldText(label.group(1)!);
      if (label != null) content = content.substring(label.end).trim();
      if (indent >= 2) {
        // A subitem: the suggestion, or more text of the question.
        skipping = false;
        if (items.isEmpty) continue;
        final q = items.last;
        if (kind == 'sugestao') {
          q.suggestion = content;
          toSuggestion = true;
        } else if (kind == null) {
          q.text = '${q.text} $content';
          toSuggestion = false;
        } else {
          skipping = true;
        }
        continue;
      }
      if (kind != null) {
        // "Sugestão:" at the first level belongs to the question before it.
        stray.add(lineNo);
        skipping = kind != 'sugestao' || items.isEmpty;
        if (!skipping) {
          items.last.suggestion ??= content;
          toSuggestion = true;
        }
        continue;
      }
      skipping = false;
      toSuggestion = false;
      final p = _questionIdRe.firstMatch(content);
      if (p == null) unprefixed = true;
      items.add(
        _QuestionDraft(
          id: p == null ? null : 'P${p.group(1)}',
          text: p == null ? content : content.substring(p.end).trim(),
          line: lineNo,
        ),
      );
    }
    final used = {for (final d in items) ?d.id};
    var n = 0;
    String nextId() {
      String id;
      do {
        id = 'P${++n}';
      } while (used.contains(id));
      return id;
    }

    return OpenQuestionsScan(
      questions: [
        for (final (i, d) in items.indexed)
          OpenQuestion(
            id: d.id ?? (used.contains('P${i + 1}') ? nextId() : 'P${i + 1}'),
            text: d.text.trim(),
            suggestion: d.suggestion == null || d.suggestion!.trim().isEmpty
                ? null
                : d.suggestion!.trim(),
            line: d.line,
          ),
      ],
      suggestionLines: stray,
      unprefixed: unprefixed,
    );
  }

  static final _questionItemRe = RegExp(
    r'^([ \t]*)(?:[-*+]|\d+[.)])\s+(.*\S)\s*$',
  );
  static final _labelRe = RegExp(
    r'^\**(Sugest[aã]o|Resposta|Op[cç][oõ]es)\**\s*:\**\s*',
    caseSensitive: false,
  );
  static final _questionIdRe = RegExp(r'^\**P(\d+)\**(?:\s*[·:.\-–—)]\s*|\s+)');

  /// `## Perguntas em aberto` rewritten in the R1 format with [questions]
  /// (SPEC-028 R3: "Corrigir formato"; the texts are kept). Empty leaves the
  /// section empty.
  String withOpenQuestions(List<OpenQuestion> questions) {
    final lines = text.split('\n');
    final open = _sectionRange(text, openQuestionsSection, from: _bodyLine);
    final block = [for (final q in questions) ...q.toLines()];
    if (open == null) {
      if (block.isEmpty) return text;
      return '${text.trimRight()}\n\n## $openQuestionsSection\n\n'
          '${block.join('\n')}\n';
    }
    lines.replaceRange(open.start + 1, open.end, [
      '',
      ...block,
      if (block.isNotEmpty) '',
    ]);
    return lines.join('\n');
  }

  /// "Aprovar com as sugestões" (SPEC-028 R5): `## Perguntas em aberto`
  /// left empty and each of [questions] added to `## Premissas`: with a
  /// suggestion `- (assumida em 2026-11-01) P1 · <pergunta> → <sugestão>`,
  /// without `- (sem resposta, aceita em 2026-11-01) P1 · <pergunta>` (the
  /// section is created before `## Critérios de aceite` when absent).
  String withAssumptions(List<OpenQuestion> questions, DateTime at) {
    final lines = text.split('\n');
    final open = _sectionRange(text, openQuestionsSection, from: _bodyLine);
    if (open != null) {
      lines.replaceRange(open.start + 1, open.end, ['']);
    }
    if (questions.isEmpty) return lines.join('\n');
    final day = specDay(at);
    final items = [
      for (final q in questions)
        q.suggestion == null
            ? '- (sem resposta, aceita em $day) ${q.id} · ${q.text}'
            : '- (assumida em $day) ${q.id} · ${q.text} → ${q.suggestion}',
    ];
    return _appendItems(
      lines.join('\n'),
      assumptionsSection,
      items,
      before: const ['Critérios', openQuestionsSection],
    );
  }

  /// Applying the answers of the session (SPEC-028 R10): each one in
  /// `## Decisões` as `- P1 · <resumo> (2026-11-01)` (the section is created
  /// before `## Perguntas em aberto` when absent) and the answered questions
  /// out of `## Perguntas em aberto`; the others stay, in the R1 format.
  /// [answers]: question id → summary of the answer.
  String withAnswers(Map<String, String> answers, DateTime at) {
    final questions = openQuestions;
    final answered = [
      for (final q in questions)
        if ((answers[q.id] ?? '').trim().isNotEmpty) q,
    ];
    if (answered.isEmpty) return text;
    final left = [
      for (final q in questions)
        if (!answered.contains(q)) q,
    ];
    final day = specDay(at);
    final rest = SpecDocument.parse(text).withOpenQuestions(left);
    return SpecDocument.parse(rest)._appendItems(
      rest,
      decisionsSection,
      [
        for (final q in answered)
          '- ${q.id} · ${_oneLine(answers[q.id]!)} ($day)',
      ],
      before: const [openQuestionsSection],
    );
  }

  static String _oneLine(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// [items] at the end of `## <section>` of [source], or in a new section
  /// before the first of [before] found (the end of the file otherwise).
  String _appendItems(
    String source,
    String section,
    List<String> items, {
    required List<String> before,
  }) {
    final lines = source.split('\n');
    final from = _bodyLine;
    final existing = _sectionRange(source, section, from: from);
    if (existing != null) {
      var j = existing.end;
      while (j > existing.start + 1 && lines[j - 1].trim().isEmpty) {
        j--;
      }
      lines.insertAll(j, [
        if (j == existing.start + 1) '',
        ...items,
        if (j == existing.end && j < lines.length) '',
      ]);
      return lines.join('\n');
    }
    final block = ['## $section', '', ...items, ''];
    for (final name in before) {
      final anchor = _sectionRange(source, name, from: from);
      if (anchor == null) continue;
      if (anchor.start > 0 && lines[anchor.start - 1].trim().isNotEmpty) {
        block.insert(0, '');
      }
      lines.insertAll(anchor.start, block);
      return lines.join('\n');
    }
    return '${source.trimRight()}\n\n${block.join('\n')}';
  }

  static const openQuestionsSection = 'Perguntas em aberto';
  static const assumptionsSection = 'Premissas';
  static const decisionsSection = 'Decisões';
  static const outOfScopeSection = 'Fora do escopo';
  static const criteriaSection = 'Critérios de aceite';

  /// The section "Planejar" writes, and the name it had (SPEC-037 R3, R4).
  static const planSection = 'Plano';
  static const legacyPlanSection = 'Design';

  /// Frontmatter mark of a plan written by the automatic queue.
  static const autoPlanKey = 'plano';
  static const autoPlanValue = 'automatico';

  /// `## Objetivo`.
  String? get objective => section('Objetivo');

  /// The only reader of the plan (SPEC-037 R4): `## Plano`, else the old
  /// `## Design`, without HTML comments (the template's hint); null when
  /// absent or empty. `## Plano` only matches exactly: `## Plano de testes`
  /// is another section.
  String? get design {
    String? clean(String? s) {
      final d = s?.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '').trim();
      return d == null || d.isEmpty ? null : d;
    }

    return clean(section(planSection, exact: true)) ??
        clean(section(legacyPlanSection));
  }

  /// Frontmatter `plano: automatico`: the plan was written by the automatic
  /// queue and no one saved the spec since (SPEC-037 R13, D7).
  bool get autoPlanned =>
      '${frontmatter[autoPlanKey] ?? ''}'.trim().toLowerCase() == autoPlanValue;

  /// Text with the `plano: automatico` mark set or removed.
  String withAutoPlan(bool on) =>
      withMeta(fields: {autoPlanKey: on ? autoPlanValue : null});

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

  /// Text with the `## Plano` section set to [design] (added after the
  /// requirements when absent) and, when given, `## Etapas` to [plans]. An
  /// old `## Design` gives its place to `## Plano`: the two never stay
  /// (SPEC-037 R4).
  String withDesign(String design, {Map<String, StepPlan>? plans}) {
    final legacy = _sectionRange(text, legacyPlanSection, from: _bodyLine);
    var source = text;
    if (legacy != null) {
      final lines = text.split('\n');
      if (section(planSection, exact: true) == null) {
        lines[legacy.start] = '## $planSection';
      } else {
        lines.removeRange(legacy.start, legacy.end);
      }
      source = lines.join('\n');
    }
    var out = _withSection(
      source,
      planSection,
      design.trim(),
      after: 'Requisitos',
    );
    if (plans != null && plans.isNotEmpty) {
      final lines = [
        for (final MapEntry(:key, :value) in plans.entries)
          '- $key → ${value.files.join(', ')}'
              '${value.verify == null ? '' : ' · verificar: `${value.verify}`'}',
      ];
      out = _withSection(out, 'Etapas', lines.join('\n'), after: planSection);
    }
    return out;
  }

  /// Text with `## <name>` set to [content], added after `## <after>` when
  /// absent.
  String withSection(String name, String content, {required String after}) =>
      _withSection(text, name, content.trim(), after: after);

  /// `## Protótipo` (SPEC-022 R9): `- R1 → docs/mockups/spec-022/R1-x.html`,
  /// one approved screen per requirement.
  Map<String, String> get prototypes {
    final text = section('Protótipo');
    if (text == null) return const {};
    final out = <String, String>{};
    for (final line in text.split('\n')) {
      final m = RegExp(
        r'^\s*[-*+]\s+\**(R\d+)\**\s*(?:→|->|:|·)\s*`?([^`\s]+)`?',
      ).firstMatch(line);
      if (m != null) out[m.group(1)!] = m.group(2)!;
    }
    return out;
  }

  /// Text with [path] as the approved screen of [requirement] in
  /// `## Protótipo` (a previous one of the same requirement is replaced;
  /// null removes it). Only the body changes: the status stays.
  String withPrototype(String requirement, String? path) {
    final all = {...prototypes};
    if (path == null) {
      all.remove(requirement);
    } else {
      all[requirement] = path;
    }
    int n(String r) => int.tryParse(r.substring(1)) ?? 0;
    final keys = all.keys.toList()..sort((a, b) => n(a).compareTo(n(b)));
    final content = keys.isEmpty
        ? '<!-- Telas aprovadas no modo Protótipo. -->'
        : keys.map((k) => '- $k → ${all[k]}').join('\n');
    final after = section('Etapas') != null
        ? 'Etapas'
        : section(planSection, exact: true) != null
        ? planSection
        : section(legacyPlanSection) != null
        ? legacyPlanSection
        : 'Requisitos';
    return _withSection(text, 'Protótipo', content, after: after);
  }

  static String _withSection(
    String text,
    String name,
    String content, {
    required String after,
  }) {
    final lines = text.split('\n');
    // `## Plano de testes` is not the plan.
    bool isHeading(String l, String n) => RegExp(
      '^##\\s+${RegExp.escape(n)}${n == planSection ? r'\s*#*$' : r'\b'}',
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
    final re = _requirementRe;
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

  /// Every requirement line with its 1-based line in [text], repeats
  /// included (the structure warnings, SPEC-023 R8).
  List<({String id, String text, int line})> get requirementLines {
    final lines = text.split('\n');
    final r = _sectionRange(text, 'Requisitos', from: _bodyLine);
    final (from, to) = r == null
        ? (_bodyLine, lines.length)
        : (r.start + 1, r.end);
    return [
      for (var i = from; i < to; i++)
        if (_requirementRe.firstMatch(lines[i]) case final m?)
          (id: m.group(1)!, text: m.group(2)!.trim(), line: i + 1),
    ];
  }

  static final _requirementRe = RegExp(
    r'^\s*(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s+)?\**(R\d+)\**\b\s*[·:.\-–—]?\s*(.*)$',
  );

  /// Frontmatter keys written by "Marcar como finalizada" (SPEC-019): the
  /// stage and status "Reabrir" restores.
  static const previousStageKey = 'estagio-anterior';
  static const previousStatusKey = 'status-anterior';

  /// Stage saved by "Marcar como finalizada" (null = none / not a working
  /// stage).
  SpecStage? get previousStage {
    final v = '${frontmatter[previousStageKey] ?? ''}'.trim();
    final stage = SpecStage.values.where((s) => s.name == v).firstOrNull;
    return stage == SpecStage.done ? null : stage;
  }

  /// Status saved by "Marcar como finalizada" (null = none / a finished
  /// status).
  SpecStatus? get previousStatus {
    final s = specStatusFromValue('${frontmatter[previousStatusKey] ?? ''}');
    return s == SpecStatus.done || s == SpecStatus.archived ? null : s;
  }

  /// Text with `id` / `status` / `depende-de` set in the frontmatter
  /// (created when absent). [fields] sets other single-line keys; a null
  /// value removes the key's line. Other lines (unknown keys, comments) are
  /// kept byte for byte.
  String withMeta({
    String? id,
    SpecStatus? status,
    List<String>? dependsOn,
    bool? designWaived,
    Map<String, String?> fields = const {},
  }) {
    final updates = <String, String>{
      'id': ?id,
      if (status != null) 'status': specStatusValue(status),
      if (dependsOn != null) dependsOnKey: '[${dependsOn.join(', ')}]',
      if (designWaived == true) 'design': 'dispensado',
      for (final e in fields.entries)
        if (e.value != null) e.key: e.value!,
    };
    final removals = {
      for (final e in fields.entries)
        if (e.value == null) e.key,
    };
    if (updates.isEmpty && removals.every((k) => !frontmatter.containsKey(k))) {
      return text;
    }
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
    lines.removeWhere((l) {
      final m = RegExp(r'^([A-Za-z_][\w-]*)\s*:').firstMatch(l);
      return m != null && removals.contains(m.group(1));
    });
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

/// Markdown of a new spec ("Nova spec"). What is not given stays as in the
/// empty template (SPEC-039 R6).
String newSpecMarkdown({
  required String code,
  required String title,
  String objective = '',
  List<String> requirements = const [],
  List<String> outOfScope = const [],
  List<String> dependsOn = const [],
  List<({String text, String suggestion})> questions = const [],
}) {
  final requirementLines = [
    for (final (i, r) in requirements.indexed) '- R${i + 1} · $r',
  ].join('\n');
  final questionLines = [
    for (final (i, q) in questions.indexed) ...[
      '- P${i + 1} · ${q.text}',
      if (q.suggestion.isNotEmpty) '  - Sugestão: ${q.suggestion}',
    ],
  ].join('\n');
  return '''
---
id: $code
status: ${specStatusValue(SpecStatus.draft)}
${dependsOn.isEmpty ? '' : '$dependsOnKey: [${dependsOn.join(', ')}]\n'}---

# $title

## Objetivo

${objective.isEmpty ? 'Descreva o problema e o resultado esperado.' : objective}

## Requisitos

${requirements.isEmpty ? '- R1 ·' : requirementLines}

## Fora do escopo

${outOfScope.isEmpty ? '<!-- O que esta spec não faz (as sessões de etapa recebem esta lista). -->' : outOfScope.map((o) => '- $o').join('\n')}

## Plano

<!-- Como implementar: componentes, arquivos e decisões. Use "Planejar". -->

## Critérios de aceite

- [ ]

## Perguntas em aberto

${questions.isEmpty ? _questionsHint : questionLines}
''';
}

const _questionsHint = '''
<!-- Dúvidas sem resposta, uma por item, no formato:
- P1 · <pergunta>
  - Sugestão: <resposta sugerida, quando houver>
Responda antes de aprovar ("Responder perguntas"). -->''';

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
  // A clone is the person's draft: the automatic plan does not touch it.
  final meta = SpecDocument.parse(text).withMeta(
    id: newCode,
    status: SpecStatus.draft,
    dependsOn: [originalCode],
    fields: const {SpecDocument.autoPlanKey: null},
  );
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

/// `2026-11-01` of [at] (dates written into the spec).
String specDay(DateTime at) =>
    '${at.year}-${'${at.month}'.padLeft(2, '0')}-'
    '${'${at.day}'.padLeft(2, '0')}';

/// Instruction for the `## Perguntas em aberto` format (SPEC-028 R1), shared
/// by the refine prompt and `/spec`.
const openQuestionsFormatHint =
    'cada pergunta como um item "- P<n> · <pergunta>", com a sugestão, '
    'quando houver, num subitem recuado "  - Sugestão: <texto>"';

/// One question of `## Perguntas em aberto` (SPEC-028 R2).
@immutable
class OpenQuestion {
  const OpenQuestion({
    required this.id,
    required this.text,
    this.suggestion,
    this.line = 0,
  });

  /// `P1`, `P2`… (the item's own, or its position).
  final String id;
  final String text;
  final String? suggestion;

  /// 1-based line of the item in the file (0 = unknown).
  final int line;

  /// The item in the R1 format.
  List<String> toLines() => [
    '- $id · $text',
    if (suggestion != null) '  - Sugestão: $suggestion',
  ];

  @override
  bool operator ==(Object other) =>
      other is OpenQuestion &&
      other.id == id &&
      other.text == text &&
      other.suggestion == suggestion;

  @override
  int get hashCode => Object.hash(id, text, suggestion);

  @override
  String toString() =>
      '$id · $text${suggestion == null ? '' : ' → $suggestion'}';
}

/// The excerpt of "Perguntas em aberto" around a question (SPEC-059 R7).
@immutable
class QuestionExcerptLines {
  const QuestionExcerptLines({
    required this.first,
    required this.last,
    required this.from,
    required this.lines,
  });

  /// 1-based lines of the question itself.
  final int first;
  final int last;

  /// 1-based line of [lines].first.
  final int from;
  final List<String> lines;

  bool marked(int line) => line >= first && line <= last;
}

/// What [SpecDocument.openQuestionsScan] read.
@immutable
class OpenQuestionsScan {
  const OpenQuestionsScan({
    this.questions = const [],
    this.suggestionLines = const [],
    this.unprefixed = false,
  });

  final List<OpenQuestion> questions;

  /// 1-based lines of first-level items that are not questions
  /// ("Sugestão:", "Resposta:", "Opções:").
  final List<int> suggestionLines;

  /// Some question has no `P<n>`.
  final bool unprefixed;

  /// The section is outside the R1 format (R3).
  bool get offFormat => suggestionLines.isNotEmpty || unprefixed;
}

class _QuestionDraft {
  _QuestionDraft({required this.id, required this.text, required this.line});

  final String? id;
  String text;
  String? suggestion;
  final int line;
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
    this.line = 0,
  });

  /// 1-based line in the text given to [parseCriteria].
  final int line;

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
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
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
        line: i + 1,
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
