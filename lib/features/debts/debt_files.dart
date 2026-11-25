import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/fs/dir_watcher.dart';
import '../project/project_config.dart';
import 'debt_item.dart';
import 'debt_table.dart';

/// A change to a debts or decisions file (R5).
sealed class DebtEdit {
  const DebtEdit();
}

/// A new row at the end of the table.
class AppendDebtRow extends DebtEdit {
  const AppendDebtRow(this.cells);
  final List<String> cells;
}

/// The row of [code] replaced by [cells]; [expectedRaw] is the row as it
/// was read (null = no check).
class ReplaceDebtRow extends DebtEdit {
  const ReplaceDebtRow(this.code, this.cells, {this.expectedRaw});
  final String code;
  final List<String> cells;
  final String? expectedRaw;
}

/// Where the files live and how they are read and written (SPEC-112 R1,
/// R2, R5).
abstract final class DebtFiles {
  /// Files of before (R2): offered to be used or moved.
  static const legacyDebts = 'docs/debitos-tecnicos.md';
  static const legacyDecisions = 'docs/decisoes-pendentes.md';

  static String relPath(DebtsConfig c, DebtKind kind) =>
      kind == DebtKind.debt ? c.debtsPath : c.decisionsPath;

  static String legacyPath(DebtKind kind) =>
      kind == DebtKind.debt ? legacyDebts : legacyDecisions;

  static String _join(String root, String rel) =>
      root.endsWith('/') ? '$root$rel' : '$root/$rel';

  /// The old file of [kind] when it exists and the configured one does not
  /// (R2); null otherwise.
  static String? legacyOf(String root, DebtsConfig c, DebtKind kind) {
    final configured = relPath(c, kind);
    final legacy = legacyPath(kind);
    if (configured == legacy) return null;
    if (File(_join(root, configured)).existsSync()) return null;
    return File(_join(root, legacy)).existsSync() ? legacy : null;
  }

  /// The text of a new file: a short header and the empty table (R1).
  static String newFileText(DebtKind kind, {String eol = '\n'}) {
    final head = kind == DebtKind.debt
        ? [
            '# Débito técnico',
            '',
            'O que ficou simulado ou provisório de propósito, para resolver '
                'depois. Débito pago fica riscado, com a spec que o resolveu.',
          ]
        : [
            '# Decisões pendentes',
            '',
            'Perguntas que ficaram para responder depois. Ao decidir, '
                'preencher **Decisão** e levar a resposta para a spec de origem.',
          ];
    return [
      ...head,
      '',
      DebtTable.formatRow(kind.columns, escape: false),
      '|${List.filled(kind.columns.length, '---').join('|')}|',
      '',
    ].join(eol);
  }

  static Future<DebtDocument> read(
    String root,
    String rel,
    DebtKind kind,
  ) async {
    final f = File(_join(root, rel));
    if (!await f.exists()) return DebtDocument.parse('', kind);
    return DebtDocument.parse(await f.readAsString(), kind);
  }

  /// Applies [edit] to the file at [root]/[rel] (R5): the file is read
  /// again right before writing, so a change made outside the app since the
  /// screen read it is kept; the row of a replaced item must still be the
  /// one read ([DebtRowChanged]). A missing file is created with
  /// [newFileText]. The write is atomic (temporary file + rename).
  static Future<DebtDocument> apply(
    String root,
    String rel,
    DebtKind kind,
    DebtEdit edit,
  ) async {
    final f = File(_join(root, rel));
    final exists = await f.exists();
    final text = exists ? await f.readAsString() : newFileText(kind);
    final table = DebtTable.parse(text, kind);
    final out = switch (edit) {
      AppendDebtRow(:final cells) => table.append(cells),
      ReplaceDebtRow(:final code, :final cells, :final expectedRaw) =>
        table.replace(code, cells, expectedRaw: expectedRaw),
    };
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.promptorium-tmp');
    await tmp.writeAsString(out, flush: true);
    await tmp.rename(f.path);
    return DebtDocument.parse(out, kind);
  }

  /// Highest number of [kind] in the files of [roots] (the main checkout and
  /// the open worktrees, R3).
  static Future<int> maxNumberIn(
    Iterable<String> roots,
    String rel,
    DebtKind kind,
  ) async {
    var max = 0;
    for (final r in roots) {
      final d = await read(r, rel, kind);
      if (d.table.maxNumber > max) max = d.table.maxNumber;
    }
    return max;
  }
}

/// Both files of a repository, as read now.
@immutable
class DebtSnapshot {
  const DebtSnapshot({
    required this.repoRoot,
    required this.config,
    required this.debts,
    required this.decisions,
    this.debtsExists = false,
    this.decisionsExists = false,
    this.legacyDebts,
    this.legacyDecisions,
  });

  final String repoRoot;
  final DebtsConfig config;
  final DebtDocument debts;
  final DebtDocument decisions;
  final bool debtsExists;
  final bool decisionsExists;

  /// Old files offered to be used or moved (R2).
  final String? legacyDebts;
  final String? legacyDecisions;

  bool get hasLegacy => legacyDebts != null || legacyDecisions != null;

  List<DebtItem> get openDebts => [
    for (final d in debts.debts)
      if (!d.paid) d,
  ];

  List<DecisionItem> get pendingDecisions => [
    for (final d in decisions.decisions)
      if (!d.decided) d,
  ];

  static Future<DebtSnapshot> load(String root) async {
    final cfg = ProjectConfig.loadSync(root).debts;
    final dp = DebtFiles.relPath(cfg, DebtKind.debt);
    final cp = DebtFiles.relPath(cfg, DebtKind.decision);
    return DebtSnapshot(
      repoRoot: root,
      config: cfg,
      debts: await DebtFiles.read(root, dp, DebtKind.debt),
      decisions: await DebtFiles.read(root, cp, DebtKind.decision),
      debtsExists: File('$root/$dp').existsSync(),
      decisionsExists: File('$root/$cp').existsSync(),
      legacyDebts: DebtFiles.legacyOf(root, cfg, DebtKind.debt),
      legacyDecisions: DebtFiles.legacyOf(root, cfg, DebtKind.decision),
    );
  }

  /// Snapshots of [root], read again whenever one of the files (or the
  /// config) changes outside the app (R5).
  static Stream<DebtSnapshot> watch(
    String root, {
    Duration debounce = const Duration(milliseconds: 250),
  }) {
    late StreamController<DebtSnapshot> ctl;
    DirWatcher? watcher;
    var last = '';
    Set<String> dirsOf(DebtSnapshot s) {
      String dir(String rel) {
        final i = rel.lastIndexOf('/');
        return i < 0 ? root : '$root/${rel.substring(0, i)}';
      }

      return {
        root,
        '$root/.promptorium',
        '$root/docs',
        dir(s.config.debtsPath),
        dir(s.config.decisionsPath),
      };
    }

    Future<void> emit() async {
      if (ctl.isClosed) return;
      final s = await load(root);
      final key =
          '${s.debts.table.text}\u0000${s.decisions.table.text}\u0000'
          '${s.config.hashCode}\u0000${s.legacyDebts}\u0000'
          '${s.legacyDecisions}\u0000${s.debtsExists}${s.decisionsExists}';
      watcher?.update(dirsOf(s));
      if (key == last || ctl.isClosed) return;
      last = key;
      ctl.add(s);
    }

    ctl = StreamController<DebtSnapshot>(
      onListen: () {
        watcher = DirWatcher(
          {root},
          debounce: debounce,
          onChange: (_) => unawaited(emit()),
        );
        unawaited(emit());
      },
      onCancel: () async {
        await watcher?.close();
        watcher = null;
      },
    );
    return ctl.stream;
  }
}

/// The files of a repository (by its root), read again on change.
final debtSnapshotProvider = StreamProvider.family<DebtSnapshot, String>(
  (ref, root) => DebtSnapshot.watch(root),
);
