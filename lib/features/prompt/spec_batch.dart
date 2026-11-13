import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../../data/db/app_database.dart';
import '../../data/repos/specs_repo.dart';
import '../specs/spec_service.dart';
import 'spec_from_answer.dart';

/// Several specs of one Prompt answer, created together (SPEC-068 R3–R6).

/// One spec of the answer, as the agent wrote it.
@immutable
class SpecBatchItem {
  const SpecBatchItem({
    required this.index,
    required this.alias,
    required this.title,
    required this.markdown,
    required this.dependsOn,
    required this.requirements,
  });

  factory SpecBatchItem.of(int index, AnswerSpec spec) => SpecBatchItem(
    index: index,
    alias: spec.alias,
    title: spec.title ?? 'Spec sem título',
    markdown: spec.markdown,
    dependsOn: spec.rawDependsOn,
    requirements: spec.requirements,
  );

  /// Position of the spec in the answer.
  final int index;

  /// Code of its frontmatter (`SPEC-A`, `SPEC-012`); null when absent.
  final String? alias;
  final String title;
  final String markdown;

  /// `depende-de` as written (provisional codes included).
  final List<String> dependsOn;
  final int requirements;

  /// `SPEC-A`, or `#2` when the spec has no code.
  String get label => alias ?? '#${index + 1}';
}

/// [SpecBatchItem]s of [answer] (empty when it has none).
List<SpecBatchItem> batchItemsOf(String answer) {
  final specs = detectAnswerSpecs(answer);
  return [for (var i = 0; i < specs.length; i++) SpecBatchItem.of(i, specs[i])];
}

/// The state of one row of the review list.
@immutable
class SpecBatchEntry {
  const SpecBatchEntry({
    required this.item,
    this.checked = true,
    this.title,
    this.dependsOn,
    this.created,
  });

  final SpecBatchItem item;
  final bool checked;

  /// Title edited in the list (null = the answer's).
  final String? title;

  /// Dependencies after "Tirar a dependência" (null = the answer's).
  final List<String>? dependsOn;

  /// The spec already created from this item (R6): locked, unchecked.
  final Spec? created;

  String get effectiveTitle => title ?? item.title;
  List<String> get effectiveDeps => dependsOn ?? item.dependsOn;

  /// It will be created now.
  bool get willCreate => checked && created == null;

  SpecBatchEntry copyWith({
    bool? checked,
    String? title,
    List<String>? dependsOn,
  }) => SpecBatchEntry(
    item: item,
    checked: checked ?? this.checked,
    title: title ?? this.title,
    dependsOn: dependsOn ?? this.dependsOn,
    created: created,
  );
}

/// Where a spec came from in the Prompt (R6).
typedef SpecOrigin = ({int conversationId, int answer});

/// The spec of [specs] already created from [item] of [origin]'s answer:
/// same answer and position, or (a regenerated answer) same provisional
/// code and title in the same conversation.
Spec? createdFrom(Iterable<Spec> specs, SpecOrigin origin, SpecBatchItem item) {
  Spec? byPair;
  for (final s in specs) {
    if (s.originConversationId != origin.conversationId) continue;
    if (s.originAnswer == origin.answer && s.originItem == item.index) {
      return s;
    }
    if (byPair == null &&
        item.alias != null &&
        s.originAlias == item.alias &&
        s.originTitle == item.title) {
      byPair = s;
    }
  }
  return byPair;
}

/// Rows of the review list for [items]: the new ones checked, the ones
/// already created locked (R6).
List<SpecBatchEntry> batchEntries(
  List<SpecBatchItem> items,
  Iterable<Spec> specs,
  SpecOrigin? origin,
) => [
  for (final i in items)
    SpecBatchEntry(
      item: i,
      created: origin == null ? null : createdFrom(specs, origin, i),
    ),
];

enum BatchWarningKind { unchecked, cycle, unknown }

/// A warning of a row (R5).
@immutable
class BatchWarning {
  const BatchWarning(this.kind, this.code, {this.path = const []});

  final BatchWarningKind kind;

  /// The dependency it is about (`SPEC-A`).
  final String code;

  /// The cycle, from this row back to it (`SPEC-A`, `SPEC-B`, `SPEC-A`).
  final List<String> path;

  String get message => switch (kind) {
    BatchWarningKind.unchecked =>
      'Depende da $code, que você desmarcou. Ela não vai existir.',
    BatchWarningKind.cycle => 'Ciclo de dependências: ${path.join(' → ')}.',
    BatchWarningKind.unknown =>
      'Depende da $code, que não existe no projeto nem nesta lista.',
  };

  @override
  bool operator ==(Object other) =>
      other is BatchWarning &&
      other.kind == kind &&
      other.code == code &&
      listEquals(other.path, path);

  @override
  int get hashCode => Object.hash(kind, code, Object.hashAll(path));
}

/// What creating the checked rows does (R4, R5): pure.
@immutable
class BatchPlan {
  const BatchPlan({
    required this.codes,
    required this.deps,
    required this.warnings,
    required this.existingDeps,
  });

  /// Real code of each row (by item index): the predicted number of the
  /// rows to create, the code of the ones already created.
  final Map<int, String> codes;

  /// `depende-de` of each row to create, rewritten with the real codes.
  final Map<int, List<String>> deps;

  /// Warnings of each row (only rows that will be created).
  final Map<int, List<BatchWarning>> warnings;

  /// `(row, alias, code)`: a row depends on one already created.
  final List<({int row, String alias, String code})> existingDeps;

  List<int> get toCreate => deps.keys.toList();

  /// A cycle blocks "Criar" (R5); the other warnings do not.
  bool get hasCycle => warnings.values.any(
    (l) => l.any((w) => w.kind == BatchWarningKind.cycle),
  );

  /// `SPEC-021 a SPEC-023`, `SPEC-021`, or '' when nothing is created.
  String get range {
    final list = [for (final i in toCreate) codes[i]!];
    if (list.isEmpty) return '';
    if (list.length == 1) return list.single;
    return '${list.first} a ${list.last}';
  }
}

String specCodeOf(int n) => 'SPEC-${n.toString().padLeft(3, '0')}';

/// Plans [entries]: each row to create takes the next free number from
/// [nextNumber] in list order; every `depende-de` naming a row of the list
/// is rewritten; a code of [existing] (the project's) that no row has stays
/// as is (R4). Warns about unchecked dependencies, cycles and unknown
/// codes (R5).
BatchPlan planBatch(
  List<SpecBatchEntry> entries, {
  required Set<String> existing,
  required int nextNumber,
}) {
  final codes = <int, String>{};
  final byAlias = <String, SpecBatchEntry>{};
  var n = nextNumber;
  for (final e in entries) {
    final alias = e.item.alias;
    if (alias != null) byAlias.putIfAbsent(alias, () => e);
    if (e.created != null) {
      codes[e.item.index] = e.created!.code;
    } else if (e.checked) {
      codes[e.item.index] = specCodeOf(n++);
    }
  }
  final deps = <int, List<String>>{};
  final warnings = <int, List<BatchWarning>>{};
  final existingDeps = <({int row, String alias, String code})>[];
  for (final e in entries) {
    if (!e.willCreate) continue;
    final out = <String>[];
    final warn = <BatchWarning>[];
    for (final d in e.effectiveDeps) {
      final target = byAlias[d];
      if (target != null && target != e) {
        final code = codes[target.item.index];
        if (code != null) {
          out.add(code);
          if (target.created != null) {
            existingDeps.add((row: e.item.index, alias: d, code: code));
          }
        } else {
          warn.add(BatchWarning(BatchWarningKind.unchecked, d));
        }
      } else if (existing.contains(d)) {
        out.add(d);
      } else if (target == null) {
        warn.add(BatchWarning(BatchWarningKind.unknown, d));
        // A provisional code with no spec is dropped; a real one stays.
        if (RegExp(r'^SPEC-\d+$').hasMatch(d)) out.add(d);
      }
    }
    deps[e.item.index] = out;
    if (warn.isNotEmpty) warnings[e.item.index] = warn;
  }
  // Cycles among the rows to create.
  final edges = <int, List<int>>{
    for (final e in entries)
      if (e.willCreate)
        e.item.index: [
          for (final d in e.effectiveDeps)
            if (byAlias[d] case final t? when t.willCreate && t != e)
              t.item.index,
        ],
  };
  for (final start in edges.keys) {
    final path = _cycleFrom(start, edges);
    if (path == null) continue;
    final labels = [
      for (final i in path)
        entries.firstWhere((e) => e.item.index == i).item.label,
    ];
    (warnings[start] ??= []).add(
      BatchWarning(BatchWarningKind.cycle, labels[1], path: labels),
    );
  }
  return BatchPlan(
    codes: codes,
    deps: deps,
    warnings: warnings,
    existingDeps: existingDeps,
  );
}

/// The shortest path from [start] back to it, or null.
List<int>? _cycleFrom(int start, Map<int, List<int>> edges) {
  final prev = <int, int>{};
  final queue = <int>[start];
  final seen = <int>{};
  while (queue.isNotEmpty) {
    final at = queue.removeAt(0);
    for (final next in edges[at] ?? const <int>[]) {
      if (next == start) {
        final path = <int>[start];
        for (var c = at; c != start; c = prev[c]!) {
          path.insert(1, c);
        }
        return [...path, start];
      }
      if (seen.add(next)) {
        prev[next] = at;
        queue.add(next);
      }
    }
  }
  return null;
}

/// Text written for [e] as [code] with [deps]: id, `status: rascunho`, the
/// edited title, `depende-de` with the real codes (a variation of the key
/// is replaced).
String batchSpecText(SpecBatchEntry e, String code, List<String> deps) {
  var md = e.title == null
      ? e.item.markdown
      : withSpecTitle(e.item.markdown, e.title!);
  final doc = SpecDocument.parse(md);
  final alias = doc.dependsOnAlias;
  md = doc.withMeta(
    id: code,
    status: SpecStatus.draft,
    fields: {
      dependsOnKey: deps.isEmpty ? null : '[${deps.join(', ')}]',
      ?alias: null,
    },
  );
  return md;
}

/// Creates the rows of [plan] in order (R4): exclusive creation, and a
/// number taken by someone else meanwhile moves the spec to the next free
/// one, with the references adjusted. Each spec keeps its [origin] (R6).
/// Returns the specs created, in order.
Future<List<Spec>> createSpecBatch(
  SpecService service,
  SpecsRepo repo,
  Workspace ws,
  List<SpecBatchEntry> entries,
  BatchPlan plan, {
  SpecOrigin? origin,
}) async {
  final byIndex = {for (final e in entries) e.item.index: e};
  // Predicted code → row, to follow a row that moved.
  final rowOfCode = {for (final i in plan.toCreate) plan.codes[i]!: i};
  final actual = <int, String>{};
  final written = <int, List<String>>{};
  final created = <int, Spec>{};

  List<String> depsOf(int row) => [
    for (final d in plan.deps[row]!)
      if (rowOfCode[d] case final r?) actual[r] ?? d else d,
  ];

  for (final row in plan.toCreate) {
    final e = byIndex[row]!;
    Spec? spec;
    for (var attempt = 0; spec == null; attempt++) {
      try {
        spec = await service.create(
          ws,
          title: e.effectiveTitle,
          render: (code) {
            actual[row] = code;
            final deps = depsOf(row);
            written[row] = deps;
            return batchSpecText(e, code, deps);
          },
        );
      } on SpecException {
        // Exclusive creation lost the number: the next try reads it again.
        if (attempt >= 5) rethrow;
      }
    }
    actual[row] = spec.code;
    created[row] = spec;
    if (origin != null) {
      await repo.update(
        spec.id,
        SpecsCompanion(
          originConversationId: Value(origin.conversationId),
          originAnswer: Value(origin.answer),
          originItem: Value(row),
          originAlias: Value(e.item.alias),
          originTitle: Value(e.item.title),
        ),
      );
    }
  }
  // A row that depends on a later one that moved: rewrite it.
  for (final row in plan.toCreate) {
    final deps = depsOf(row);
    if (listEquals(deps, written[row])) continue;
    final spec = created[row]!;
    final text = await service.read(ws, spec);
    if (text == null) continue;
    final doc = SpecDocument.parse(text);
    created[row] = await service.save(
      ws,
      spec,
      doc.withMeta(
        fields: {dependsOnKey: deps.isEmpty ? null : '[${deps.join(', ')}]'},
      ),
    );
  }
  return [
    for (final row in plan.toCreate)
      (await repo.getById(created[row]!.id)) ?? created[row]!,
  ];
}

/// `SPEC-021, SPEC-022 e SPEC-023`.
String joinCodes(List<String> codes) {
  if (codes.length <= 1) return codes.join();
  return '${codes.sublist(0, codes.length - 1).join(', ')} e ${codes.last}';
}

/// Highest number in [specs] or the specs folder of [ws], plus one.
Future<int> nextSpecNumber(SpecsRepo repo, Workspace ws) async {
  final code = await nextSpecCode(repo, ws);
  return int.parse(code.substring(5));
}
