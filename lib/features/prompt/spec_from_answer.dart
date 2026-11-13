import '../../data/db/app_database.dart';
import '../sessions/timeline.dart';
import '../specs/spec_service.dart';

export '../../core/text/line_diff.dart';

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

  /// Code of the frontmatter as written in the answer, provisional ones
  /// included (`SPEC-A`); null when absent.
  String? get alias {
    final v = doc.id?.toUpperCase();
    return v != null && answerSpecCode.hasMatch(v) ? v : null;
  }

  /// `depende-de` (or a variation) as written, provisional codes included.
  late final List<String> rawDependsOn = () {
    final out = <String>[];
    for (final e in doc.frontmatter.entries) {
      if (e.key != dependsOnKey && !isDependsOnAlias(e.key)) continue;
      final v = e.value;
      final items = v is List
          ? v.map((x) => '$x')
          : '${v ?? ''}'.split(RegExp(r'[\s,;\[\]]+'));
      for (final i in items) {
        final c = i.trim().toUpperCase();
        if (answerSpecCode.hasMatch(c) && !out.contains(c)) out.add(c);
      }
    }
    return out;
  }();

  String? get title => doc.title;

  late final int requirements = doc.requirements.length;

  late final List<SpecCriterion> criteria = parseCriteria(markdown);
}

final _code = RegExp(r'^SPEC-\d+$');

/// A code an answer may give a spec: `SPEC-012` or a provisional `SPEC-A`
/// (SPEC-068 R2).
final answerSpecCode = RegExp(r'^SPEC-(\d+|[A-Z][A-Z0-9]*)$');

bool _looksLikeSpec(String text) {
  final doc = SpecDocument.parse(text);
  final id = doc.id?.toUpperCase();
  if (id != null && answerSpecCode.hasMatch(id)) return true;
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

/// The last spec of [text] (see [detectAnswerSpecs]). Null when there is
/// none.
AnswerSpec? detectAnswerSpec(String text) => detectAnswerSpecs(text).lastOrNull;

/// Every spec of [text], in order (SPEC-068 R1): the fenced blocks with a
/// spec; without them, the parts of the answer that open with a frontmatter
/// `id:`; else the answer itself from its frontmatter or `# ` title on.
List<AnswerSpec> detectAnswerSpecs(String text) {
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  final blocks = [
    for (final b in _fencedBlocks(lines))
      if (_looksLikeSpec(b.content)) b,
  ];
  if (blocks.isNotEmpty) {
    final inside = <int>{
      for (final b in blocks)
        for (var i = b.open; i <= b.close; i++) i,
    };
    final leftover = [
      for (var i = 0; i < lines.length; i++)
        if (!inside.contains(i)) lines[i],
    ].join('\n').trim().isNotEmpty;
    return [
      for (final b in blocks)
        AnswerSpec('${b.content.trim()}\n', leftover: leftover),
    ];
  }
  final starts = _frontmatterStarts(lines);
  if (starts.length > 1) {
    final out = <AnswerSpec>[];
    for (var k = 0; k < starts.length; k++) {
      final end = k + 1 < starts.length ? starts[k + 1] : lines.length;
      final part = lines.sublist(starts[k], end).join('\n');
      if (_looksLikeSpec(part)) {
        out.add(AnswerSpec('${part.trim()}\n', leftover: true));
      }
    }
    if (out.length > 1) return out;
  }
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i].trimRight();
    if (l != '---' && !l.startsWith('# ')) continue;
    final rest = lines.sublist(i).join('\n');
    if (!_looksLikeSpec(rest)) continue;
    return [
      AnswerSpec(
        '${rest.trim()}\n',
        leftover: lines.sublist(0, i).join('\n').trim().isNotEmpty,
      ),
    ];
  }
  return const [];
}

/// Lines that open a frontmatter with an `id:` (a `---` line followed by
/// `key: value` lines up to the closing `---`).
List<int> _frontmatterStarts(List<String> lines) {
  final out = <int>[];
  final key = RegExp(r'^[A-Za-z_][\w-]*\s*:');
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trimRight() != '---') continue;
    var hasId = false;
    var closed = false;
    var j = i + 1;
    for (; j < lines.length && j <= i + 40; j++) {
      final l = lines[j].trimRight();
      if (l == '---') {
        closed = true;
        break;
      }
      if (l.isEmpty || l.startsWith('#') || l.startsWith(' ')) continue;
      if (l.startsWith('- ')) continue;
      if (!key.hasMatch(l)) break;
      if (RegExp(r'^id\s*:').hasMatch(l)) hasId = true;
    }
    if (closed && hasId && j > i + 1) {
      out.add(i);
      i = j;
    }
  }
  return out;
}

/// Finished top-level answers of a conversation, in order: the index of
/// one is the origin of the specs created from it (SPEC-068 R6).
List<AssistantTextItem> finishedAnswers(List<TimelineItem> items) => [
  for (final i in items)
    if (i is AssistantTextItem && i.parentToolUseId == null && !i.live) i,
];

/// The last answer that has a spec: its index among [finishedAnswers] and
/// its specs.
({int answer, List<AnswerSpec> specs})? lastAnswerSpecs(
  List<TimelineItem> items,
) {
  final answers = finishedAnswers(items);
  for (var i = answers.length - 1; i >= 0; i--) {
    final specs = detectAnswerSpecs(answers[i].text);
    if (specs.isNotEmpty) return (answer: i, specs: specs);
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
/// frontmatter keys kept; a variation of `depende-de` gets the right name
/// (SPEC-063 R5).
String newSpecTextFromAnswer(String markdown, String code) =>
    SpecDocument.parse(
      SpecDocument.parse(markdown).withMeta(id: code, status: SpecStatus.draft),
    ).withCanonicalDependsOn();

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
  return SpecDocument.parse(
    SpecDocument.parse(markdown).withMeta(id: target.code, status: status),
  ).withCanonicalDependsOn();
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

/// "Ajustado ao salvar" for a variation of `depende-de` (SPEC-063 R5);
/// null when there is none.
String? dependsOnAliasAdjust(String markdown) {
  final doc = SpecDocument.parse(markdown);
  final alias = doc.dependsOnAlias;
  if (alias == null) return null;
  return 'A chave "$alias" vira "$dependsOnKey": [${doc.dependsOn.join(', ')}].';
}
