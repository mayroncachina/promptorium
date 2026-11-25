import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../core/git/git_service.dart';
import '../project/project_config.dart';
import 'debt_files.dart';
import 'debt_item.dart';
import 'debt_table.dart';

/// The debts paid by a spec, struck in its branch before the merge (SPEC-112
/// R15, R17) and the conflict of two specs that appended rows (P4).

/// Result of [strikeDebtRows].
@immutable
class DebtStrike {
  const DebtStrike({
    required this.text,
    required this.struck,
    required this.warnings,
  });

  /// The new text of the worktree's file.
  final String text;

  /// Codes struck now, in the order asked.
  final List<String> struck;

  /// Debts given up (the row changed, or it is in no file).
  final List<String> warnings;

  bool get changed => struck.isNotEmpty;
}

/// Strikes [codes] in [worktreeText] (the file of the spec's branch), with
/// "— **resolvido** pela [label](link)" (R15). A row missing there (the debt
/// was born after the branch) is taken from [mainText] (the file of the
/// main branch) and added struck. A row that differs between the two files
/// changed since the payment began: it is given up, with a warning, and the
/// merge goes on. A row already struck is left as it is.
DebtStrike strikeDebtRows(
  String worktreeText,
  String? mainText,
  List<String> codes, {
  required String label,
  String? link,
}) {
  var text = worktreeText;
  final main = mainText == null
      ? null
      : DebtTable.parse(mainText, DebtKind.debt);
  final struck = <String>[];
  final warnings = <String>[];
  for (final code in codes) {
    final table = DebtTable.parse(text, DebtKind.debt);
    final here = table.rowOf(code);
    final there = main?.rowOf(code);
    final row = here ?? there;
    final item = row == null ? null : DebtItem.fromRow(row);
    if (item == null) {
      warnings.add('$code não está no arquivo de débitos: não foi riscado.');
      continue;
    }
    if (item.paid) continue;
    if (here != null && there != null && here.raw.trim() != there.raw.trim()) {
      final thereItem = DebtItem.fromRow(there);
      if (thereItem == null || !thereItem.paid) {
        warnings.add(
          '$code mudou na branch principal desde o início da spec: não foi '
          'riscado. Risque à mão depois do merge.',
        );
      }
      continue;
    }
    final cells = item.struckCells(label: label, link: link);
    text = here != null ? table.replace(code, cells) : table.append(cells);
    struck.add(code);
  }
  return DebtStrike(text: text, struck: struck, warnings: warnings);
}

/// `docs: DT-03, DT-05 pagos pela spec 118` (R15).
String paidCommitMessage(List<String> codes, String label) =>
    'docs: ${codes.join(', ')} ${codes.length == 1 ? 'pago' : 'pagos'} '
    'pela $label';

/// The link of the spec at [specPath] as written in the file at [debtsRel]
/// (both relative to the repository root).
String specLinkFrom(String debtsRel, String specPath) =>
    p.posix.relative(specPath, from: p.posix.dirname(debtsRel));

/// What [strikeInWorktree] did.
@immutable
class DebtStrikeOutcome {
  const DebtStrikeOutcome({
    this.struck = const [],
    this.warnings = const [],
    this.commit,
  });

  final List<String> struck;
  final List<String> warnings;

  /// The commit `docs: … pagos pela …` (null = nothing committed).
  final String? commit;
}

/// Before the merge of a spec (R15): strikes [codes] in the debts file of
/// [worktree] and commits only that file on the spec's branch. [mainGit]
/// and [base] give the file of the main branch (for rows born after the
/// branch). Failures become warnings: the merge is never blocked.
Future<DebtStrikeOutcome> strikeInWorktree({
  required GitService wt,
  required GitService mainGit,
  required String worktree,
  required String repoRoot,
  required String base,
  required List<String> codes,
  required String label,
  required String specPath,
  bool skipHooks = false,
}) async {
  if (codes.isEmpty) return const DebtStrikeOutcome();
  final rel = DebtFiles.relPath(
    ProjectConfig.loadSync(repoRoot).debts,
    DebtKind.debt,
  );
  final f = File(p.join(worktree, rel));
  final wtText = await f.exists() ? await f.readAsString() : null;
  String? mainText;
  try {
    mainText = await mainGit.git(['show', '$base:$rel']);
  } on GitException {
    mainText = null;
  }
  if (wtText == null && mainText == null) {
    return DebtStrikeOutcome(
      warnings: ['$rel não existe: ${codes.join(', ')} não foram riscados.'],
    );
  }
  final r = strikeDebtRows(
    wtText ?? mainText!,
    mainText,
    codes,
    label: label,
    link: specLinkFrom(rel, specPath),
  );
  if (!r.changed) return DebtStrikeOutcome(warnings: r.warnings);
  await f.parent.create(recursive: true);
  final tmp = File('${f.path}.promptorium-tmp');
  await tmp.writeAsString(r.text, flush: true);
  await tmp.rename(f.path);
  try {
    await wt.git(['add', '--', rel]);
    await wt.git([
      'commit',
      if (skipHooks) '--no-verify',
      '-q',
      '-m',
      paidCommitMessage(r.struck, label),
      '--',
      rel,
    ]);
    return DebtStrikeOutcome(
      struck: r.struck,
      warnings: r.warnings,
      commit: (await wt.git(['rev-parse', 'HEAD'])).trim(),
    );
  } on GitException catch (e) {
    try {
      await wt.git(['reset', '-q', '--', rel]);
      if (wtText == null) {
        await f.delete();
      } else {
        await wt.git(['checkout', '--', rel]);
      }
    } on Object {
      /* best effort */
    }
    return DebtStrikeOutcome(
      warnings: [
        ...r.warnings,
        'O commit que risca ${r.struck.join(', ')} falhou ($e): risque à '
            'mão depois do merge.',
      ],
    );
  }
}

/// Undoes the commit of [strikeInWorktree] after a failed merge: the branch
/// goes back to [before] and the file to what it was.
Future<void> undoStrike(GitService wt, String before, String repoRoot) async {
  final rel = DebtFiles.relPath(
    ProjectConfig.loadSync(repoRoot).debts,
    DebtKind.debt,
  );
  await wt.git(['reset', '-q', before]);
  try {
    await wt.git(['checkout', '--', rel]);
  } on GitException {
    // The file did not exist before the strike.
    final f = File(p.join(wt.repoRoot, rel));
    if (await f.exists()) await f.delete();
  }
}

/// P4: [text] is a debts or decisions file with conflict markers. When
/// every conflict is at the end of the table and holds only rows (two
/// specs appending lines), the rows of both sides are joined in ID order.
/// A row both sides changed differently keeps the struck one (a payment);
/// otherwise null: the conflict goes to the normal resolution (SPEC-092).
/// Works with the diff3 markers (`|||||||`) or without them.
String? resolveDebtTableConflict(String text, DebtKind kind) {
  final lines = text.split('\n');
  final eol = text.contains('\r\n') ? '\r\n' : '\n';
  final cr = eol == '\r\n' ? '\r' : '';
  String strip(String l) => l.endsWith('\r') ? l.substring(0, l.length - 1) : l;
  final out = <String>[];
  var any = false;
  var i = 0;
  while (i < lines.length) {
    final l = strip(lines[i]);
    if (!l.startsWith('<<<<<<<')) {
      if (l.startsWith('=======') ||
          l.startsWith('>>>>>>>') ||
          l.startsWith('|||||||')) {
        return null;
      }
      out.add(lines[i]);
      i++;
      continue;
    }
    any = true;
    final ours = <String>[], theirs = <String>[];
    List<String>? base;
    var part = 0; // 0 ours, 1 base, 2 theirs
    i++;
    var closed = false;
    for (; i < lines.length; i++) {
      final x = strip(lines[i]);
      if (x.startsWith('|||||||') && part == 0) {
        part = 1;
        base = [];
      } else if (x.startsWith('=======') && part < 2) {
        part = 2;
      } else if (x.startsWith('>>>>>>>') && part == 2) {
        closed = true;
        i++;
        break;
      } else if (x.startsWith('<<<<<<<')) {
        return null;
      } else {
        (part == 0 ? ours : (part == 1 ? base! : theirs)).add(x);
      }
    }
    if (!closed) return null;
    // Inside the table: the line before is a row or the separator…
    final before = out.isEmpty ? '' : strip(out.last).trim();
    if (!before.startsWith('|')) return null;
    // …and at its end: nothing of the table after the conflict.
    if (i < lines.length && strip(lines[i]).trim().startsWith('|')) {
      return null;
    }
    final merged = _joinRows(ours, base, theirs, kind);
    if (merged == null) return null;
    out.addAll([for (final r in merged) '$r$cr']);
  }
  if (!any) return null;
  return out.join('\n');
}

/// The rows of a conflict joined by ID (see [resolveDebtTableConflict]).
List<String>? _joinRows(
  List<String> ours,
  List<String>? base,
  List<String> theirs,
  DebtKind kind,
) {
  Map<int, String>? rowsOf(List<String> side) {
    final m = <int, String>{};
    for (final l in side) {
      final t = l.trim();
      if (!t.startsWith('|')) return null;
      final cells = DebtTable.splitCells(t);
      final n = cells.isEmpty ? null : kind.numberOf(cells.first);
      if (n == null || cells.length != kind.columns.length) return null;
      if (m.containsKey(n)) return null;
      m[n] = l;
    }
    return m;
  }

  final o = rowsOf(ours), t = rowsOf(theirs);
  final b = base == null ? const <int, String>{} : rowsOf(base);
  if (o == null || t == null || b == null) return null;
  bool paid(String row) =>
      DebtTable.splitCells(row.trim()).first.trim().startsWith('~~');
  final out = <int, String>{};
  for (final n in {...b.keys, ...o.keys, ...t.keys}) {
    final bo = b[n], oo = o[n], to = t[n];
    // A row removed by one side is not a simple append.
    if (bo != null && (oo == null || to == null)) return null;
    if (oo == to) {
      if (oo != null) out[n] = oo;
    } else if (oo == null) {
      out[n] = to!;
    } else if (to == null) {
      out[n] = oo;
    } else if (oo == bo) {
      out[n] = to;
    } else if (to == bo) {
      out[n] = oo;
    } else if (paid(oo) != paid(to)) {
      out[n] = paid(oo) ? oo : to;
    } else {
      return null;
    }
  }
  final keys = out.keys.toList()..sort();
  return [for (final k in keys) out[k]!];
}

/// The paths of the debts and decisions files of [repoRoot].
Set<String> debtFilePaths(String repoRoot) {
  final c = ProjectConfig.loadSync(repoRoot).debts;
  return {
    DebtFiles.relPath(c, DebtKind.debt),
    DebtFiles.relPath(c, DebtKind.decision),
  };
}

/// P4 during a merge in [main]: when every file in [conflicted] is a debts
/// or decisions file and [resolveDebtTableConflict] solves each one, the
/// files are written and staged and true is returned (the caller commits).
/// Otherwise nothing is touched and false is returned.
Future<bool> resolveDebtMergeConflicts(
  GitService main,
  List<String> conflicted,
) async {
  if (conflicted.isEmpty) return false;
  final c = ProjectConfig.loadSync(main.repoRoot).debts;
  final kinds = {
    DebtFiles.relPath(c, DebtKind.debt): DebtKind.debt,
    DebtFiles.relPath(c, DebtKind.decision): DebtKind.decision,
  };
  if (!conflicted.every(kinds.containsKey)) return false;
  final resolved = <String, String>{};
  for (final path in conflicted) {
    try {
      // The base of the conflict helps tell an append from a change.
      await main.git(['checkout', '--conflict=diff3', '--', path]);
    } on GitException {
      return false;
    }
    final f = File(p.join(main.repoRoot, path));
    if (!await f.exists()) return false;
    final r = resolveDebtTableConflict(await f.readAsString(), kinds[path]!);
    if (r == null) return false;
    resolved[path] = r;
  }
  for (final MapEntry(key: path, value: text) in resolved.entries) {
    await File(p.join(main.repoRoot, path)).writeAsString(text);
    await main.git(['add', '--', path]);
  }
  return true;
}
