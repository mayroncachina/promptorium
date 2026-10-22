import '../../data/db/app_database.dart';
import '../sessions/timeline.dart';
import '../specs/spec_service.dart';

/// A spec the agent wrote inside a Prompt answer (SPEC-016): the agent has no
/// write tool in Perguntar/Planejar and asks the user to save the file.
class AnswerSpec {
  AnswerSpec(this.markdown, {required this.leftover});

  /// Text of the spec only (no fences, no chat around it).
  final String markdown;

  /// Whether the answer has text outside the spec (left out when saving).
  final bool leftover;

  late final SpecDocument doc = SpecDocument.parse(markdown);

  /// `SPEC-NNN` of the frontmatter (null when absent or not a spec code).
  String? get id {
    final v = doc.id?.toUpperCase();
    return v != null && _code.hasMatch(v) ? v : null;
  }

  String? get title => doc.title;

  late final int requirements = doc.requirements.length;

  late final List<SpecCriterion> criteria = parseCriteria(markdown);
}

final _code = RegExp(r'^SPEC-\d+$');

bool _looksLikeSpec(String text) {
  final doc = SpecDocument.parse(text);
  final id = doc.id?.toUpperCase();
  if (id != null && _code.hasMatch(id)) return true;
  return doc.title != null &&
      doc.section('Objetivo') != null &&
      doc.section('Requisitos') != null;
}

typedef _Block = ({int open, int close, String content});

/// Fenced blocks (``` or ~~~) by line. A fence with an info string inside a
/// block opens a nested one (a `bash` example inside the spec), so the
/// outer block ends at its own bare fence.
List<_Block> _fencedBlocks(List<String> lines) {
  final out = <_Block>[];
  final fence = RegExp(r'^\s{0,3}(`{3,}|~{3,})\s*([^`\s]*)\s*$');
  int? open;
  var char = '';
  var len = 0;
  var depth = 0;
  for (var i = 0; i < lines.length; i++) {
    final m = fence.firstMatch(lines[i].trimRight());
    if (m == null) continue;
    final f = m.group(1)!;
    final info = m.group(2)!;
    if (open == null) {
      open = i;
      char = f[0];
      len = f.length;
      depth = 0;
      continue;
    }
    if (f[0] != char) continue;
    if (info.isNotEmpty) {
      depth++;
    } else if (depth > 0) {
      depth--;
    } else if (f.length >= len) {
      out.add((
        open: open,
        close: i,
        content: lines.sublist(open + 1, i).join('\n'),
      ));
      open = null;
    }
  }
  return out;
}

/// The last spec of [text]: a fenced block with a spec, else the answer
/// itself from its frontmatter or `# ` title on. Null when there is none.
AnswerSpec? detectAnswerSpec(String text) {
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  for (final b in _fencedBlocks(lines).reversed) {
    if (!_looksLikeSpec(b.content)) continue;
    final outside = [
      ...lines.sublist(0, b.open),
      ...lines.sublist(b.close + 1),
    ].join('\n');
    return AnswerSpec(
      '${b.content.trim()}\n',
      leftover: outside.trim().isNotEmpty,
    );
  }
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i].trimRight();
    if (l != '---' && !l.startsWith('# ')) continue;
    final rest = lines.sublist(i).join('\n');
    if (!_looksLikeSpec(rest)) continue;
    return AnswerSpec(
      '${rest.trim()}\n',
      leftover: lines.sublist(0, i).join('\n').trim().isNotEmpty,
    );
  }
  return null;
}

/// Spec of the last top-level answer that has one.
AnswerSpec? lastAnswerSpec(List<TimelineItem> items) {
  for (final i in items.reversed) {
    if (i is AssistantTextItem && i.parentToolUseId == null && !i.live) {
      final s = detectAnswerSpec(i.text);
      if (s != null) return s;
    }
  }
  return null;
}

/// [markdown] with its first `# ` title replaced by [title] (added after the
/// frontmatter when there is none).
String withSpecTitle(String markdown, String title) {
  final t = title.trim();
  if (t.isEmpty) return markdown;
  final doc = SpecDocument.parse(markdown);
  final body = doc.body;
  final re = RegExp(r'^#\s+.*$', multiLine: true);
  final head = markdown.substring(0, doc.bodyStart);
  final m = re.firstMatch(body);
  if (m == null) return '$head# $t\n\n$body';
  return '$head${body.replaceRange(m.start, m.end, '# $t')}';
}

/// Text written for a new spec: `id` = [code], `status: rascunho`, other
/// frontmatter keys kept.
String newSpecTextFromAnswer(String markdown, String code) =>
    SpecDocument.parse(markdown).withMeta(id: code, status: SpecStatus.draft);

/// Saves [markdown] as the next free spec of [ws] (exclusive create).
Future<Spec> saveAnswerSpecAsNew(
  SpecService service,
  Workspace ws,
  String markdown,
) {
  final title = SpecDocument.parse(markdown).title ?? 'Spec sem título';
  return service.create(
    ws,
    title: title,
    render: (code) => newSpecTextFromAnswer(markdown, code),
  );
}

/// Why [target] cannot receive a new version (null when it can): only specs
/// still in the Backlog are replaced.
String? applyBlockedReason(Spec target) {
  if (target.status == SpecStatus.archived) {
    return '${target.code} está arquivada.';
  }
  if (target.status == SpecStatus.done || target.stage == SpecStage.done) {
    return '${target.code} está concluída.';
  }
  return switch (target.stage) {
    SpecStage.backlog => null,
    SpecStage.running => '${target.code} está em execução.',
    SpecStage.review => '${target.code} está em revisão.',
    SpecStage.done => '${target.code} está concluída.',
  };
}

/// Text written over [target]: [markdown] with the current `id` and status.
String appliedSpecText(String markdown, Spec target, String? currentText) {
  final status =
      (currentText == null ? null : SpecDocument.parse(currentText).status) ??
      target.status;
  return SpecDocument.parse(markdown).withMeta(id: target.code, status: status);
}

/// Replaces [target]'s file with [markdown]. [expectedText] is the file as
/// shown to the user: a file changed since then is not overwritten.
Future<Spec> applyAnswerSpec(
  SpecService service,
  Workspace ws,
  Spec target,
  String markdown, {
  required String? expectedText,
}) async {
  final reason = applyBlockedReason(target);
  if (reason != null) {
    throw SpecException('$reason Use "Salvar como nova".');
  }
  return service.save(
    ws,
    target,
    appliedSpecText(markdown, target, expectedText),
    expectedText: expectedText,
  );
}

// --- line diff ------------------------------------------------------------------

enum DiffOp { same, add, del }

typedef DiffLine = ({DiffOp op, String text});

/// Line diff of [a] → [b] (LCS). Very large inputs fall back to removing
/// every line of [a] and adding every line of [b].
List<DiffLine> lineDiff(String a, String b) {
  final x = a.split('\n'), y = b.split('\n');
  if (x.length * y.length > 4000000) {
    return [
      for (final l in x) (op: DiffOp.del, text: l),
      for (final l in y) (op: DiffOp.add, text: l),
    ];
  }
  final n = x.length, m = y.length;
  final lcs = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lcs[i][j] = x[i] == y[j]
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }
  final out = <DiffLine>[];
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (x[i] == y[j]) {
      out.add((op: DiffOp.same, text: x[i]));
      i++;
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      out.add((op: DiffOp.del, text: x[i++]));
    } else {
      out.add((op: DiffOp.add, text: y[j++]));
    }
  }
  while (i < n) {
    out.add((op: DiffOp.del, text: x[i++]));
  }
  while (j < m) {
    out.add((op: DiffOp.add, text: y[j++]));
  }
  return out;
}
