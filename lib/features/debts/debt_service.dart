import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/git/git_service.dart';
import '../../data/providers.dart';
import '../../data/repos/debt_links_repo.dart';
import '../project/project_config.dart';
import 'debt_files.dart';
import 'debt_item.dart';
import 'debt_table.dart';

/// What a new item carries (the form, a suggestion, an MCP call).
@immutable
class DebtDraft {
  const DebtDraft({
    required this.kind,
    required this.title,
    this.reason = '',
    this.where = '',
    this.toResolve = '',
    this.origin = '',
  });

  final DebtKind kind;

  /// Debt: the title ("O quê" in bold). Decision: the question.
  final String title;

  /// Debt: the motive. Decision: unused.
  final String reason;
  final String where;

  /// Debt: "Para resolver". Decision: the recommendation.
  final String toResolve;

  /// Debt: `spec 31, Q5` (between parentheses in "O quê"). Decision: the
  /// "Origem" cell.
  final String origin;

  Map<String, Object?> toJson() => {
    'tipo': kind.dbName,
    'titulo': title,
    if (reason.isNotEmpty) 'motivo': reason,
    if (where.isNotEmpty) 'onde': where,
    if (toResolve.isNotEmpty) 'para_resolver': toResolve,
    if (origin.isNotEmpty) 'origem': origin,
  };

  static DebtDraft fromJson(Map<String, Object?> j, {DebtKind? kind}) {
    String s(String k) => '${j[k] ?? ''}'.trim();
    return DebtDraft(
      kind: kind ?? DebtKind.fromDb(s('tipo')),
      title: s('titulo'),
      reason: s('motivo'),
      where: s('onde'),
      toResolve: s('para_resolver').isNotEmpty
          ? s('para_resolver')
          : s('recomendacao'),
      origin: s('origem'),
    );
  }

  DebtDraft copyWith({
    String? title,
    String? reason,
    String? where,
    String? toResolve,
    String? origin,
  }) => DebtDraft(
    kind: kind,
    title: title ?? this.title,
    reason: reason ?? this.reason,
    where: where ?? this.where,
    toResolve: toResolve ?? this.toResolve,
    origin: origin ?? this.origin,
  );

  /// The cells of the new row with [code] (`AAAA-MM-DD` in [since]).
  List<String> cells(String code, String since) => kind == DebtKind.debt
      ? DebtItem.newCells(
          code: code,
          since: since,
          title: title,
          reason: reason,
          origin: origin,
          where: where,
          toResolve: toResolve,
        )
      : DecisionItem.newCells(
          code: code,
          since: since,
          question: title,
          origin: origin,
          recommendation: toResolve,
        );
}

/// An item written to a file.
@immutable
class DebtWritten {
  const DebtWritten({
    required this.code,
    required this.linkId,
    required this.root,
    required this.relPath,
  });

  final String code;
  final int linkId;

  /// Where the row went: the main checkout or a worktree (R18).
  final String root;
  final String relPath;
}

/// Result of the own commit of an item made by hand (R18, P5).
enum DebtCommitResult { committed, dirty, nothing }

/// Creates and changes the debts and decisions (SPEC-112). The file is the
/// source of truth (R4): every change goes through [DebtFiles.apply]; the
/// database keeps only the links.
class DebtService {
  DebtService({
    required this.links,
    GitService Function(String root)? git,
    DateTime Function()? now,
  }) : _git = git ?? GitService.new,
       _now = now ?? DateTime.now;

  final DebtLinksRepo links;
  final GitService Function(String root) _git;
  final DateTime Function() _now;

  DebtLinksRepo get _links => links;

  String get today {
    final d = _now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  DebtsConfig configOf(String repoRoot) =>
      ProjectConfig.loadSync(repoRoot).debts;

  /// The main checkout and the open worktrees of [repoRoot] (R3).
  Future<List<String>> roots(String repoRoot) async {
    try {
      final wts = await _git(repoRoot).listWorktrees();
      final out = <String>{repoRoot};
      for (final w in wts) {
        if (!w.bare && !w.prunable && Directory(w.path).existsSync()) {
          out.add(w.path);
        }
      }
      return out.toList();
    } catch (_) {
      return [repoRoot];
    }
  }

  /// Reserves the next code of [kind] (R3): the highest among the files of
  /// the main branch, of the open worktrees and of the reservations, plus
  /// one.
  Future<({int id, String code})> reserve(
    String repoRoot,
    DebtKind kind, {
    DebtLinksCompanion link = const DebtLinksCompanion(),
  }) async {
    final rel = DebtFiles.relPath(configOf(repoRoot), kind);
    final max = await DebtFiles.maxNumberIn(await roots(repoRoot), rel, kind);
    return _links.reserve(
      repoRoot: repoRoot,
      kind: kind.dbName,
      prefix: kind.prefix,
      minNumber: max + 1,
      link: link,
    );
  }

  /// The code the next item of [kind] would get (a preview: nothing is
  /// reserved).
  Future<String> previewCode(String repoRoot, DebtKind kind) async {
    final rel = DebtFiles.relPath(configOf(repoRoot), kind);
    final files = await DebtFiles.maxNumberIn(await roots(repoRoot), rel, kind);
    final db = await _links.maxReserved(repoRoot, kind.prefix);
    return kind.code((files > db ? files : db) + 1);
  }

  /// Writes [draft] as a new row (R1, R3, R18). [writeRoot] is the worktree
  /// of the spec or session the item was born in (null = the main
  /// checkout). [link] fills the origin of the link.
  Future<DebtWritten> create(
    String repoRoot,
    DebtDraft draft, {
    String? writeRoot,
    DebtLinksCompanion link = const DebtLinksCompanion(),
  }) async {
    final (:id, :code) = await reserve(repoRoot, draft.kind, link: link);
    final rel = DebtFiles.relPath(configOf(repoRoot), draft.kind);
    final root = writeRoot ?? repoRoot;
    try {
      await DebtFiles.apply(
        root,
        rel,
        draft.kind,
        AppendDebtRow(draft.cells(code, today)),
      );
    } catch (_) {
      // Nothing was written: the reservation stays (the ID is never given
      // again, R3) but the link goes.
      await _links.delete(id);
      rethrow;
    }
    return DebtWritten(code: code, linkId: id, root: root, relPath: rel);
  }

  /// A pending suggestion (R7, R11): nothing is written until accepted.
  Future<int> suggest(
    String repoRoot,
    DebtDraft draft, {
    required String source,
    DebtLinksCompanion link = const DebtLinksCompanion(),
  }) => _links.addSuggestion(
    repoRoot: repoRoot,
    kind: draft.kind.dbName,
    source: source,
    body: draft.toJson(),
    link: link,
  );

  /// Accepts the suggestion [linkId] ([edited] replaces the proposed text):
  /// the row is written and the link gets the code.
  Future<DebtWritten> accept(
    int linkId, {
    DebtDraft? edited,
    String? writeRoot,
  }) async {
    final l = await _links.byId(linkId);
    if (l == null) throw StateError('Sugestão $linkId não existe.');
    final kind = DebtKind.fromDb(l.kind);
    final draft =
        edited ?? DebtDraft.fromJson(DebtLinksRepo.suggestionOf(l), kind: kind);
    final rel = DebtFiles.relPath(configOf(l.repoRoot), kind);
    final max = await DebtFiles.maxNumberIn(await roots(l.repoRoot), rel, kind);
    // The suggestion row itself gets the code (unique index, R3).
    final reserved = await _links.reserve(
      repoRoot: l.repoRoot,
      kind: kind.dbName,
      prefix: kind.prefix,
      minNumber: max + 1,
    );
    await _links.delete(reserved.id);
    await _links.update(
      linkId,
      DebtLinksCompanion(
        code: Value(reserved.code),
        suggestionState: const Value(DebtSuggestionState.accepted),
        suggestionBody: Value(null),
      ),
    );
    final root = writeRoot ?? l.repoRoot;
    try {
      await DebtFiles.apply(
        root,
        rel,
        kind,
        AppendDebtRow(draft.cells(reserved.code, today)),
      );
    } catch (_) {
      await _links.update(
        linkId,
        DebtLinksCompanion(
          code: const Value(null),
          suggestionState: const Value(DebtSuggestionState.pending),
          suggestionBody: Value(l.suggestionBody),
        ),
      );
      rethrow;
    }
    return DebtWritten(
      code: reserved.code,
      linkId: linkId,
      root: root,
      relPath: rel,
    );
  }

  Future<void> discard(int linkId) => _links.update(
    linkId,
    const DebtLinksCompanion(
      suggestionState: Value(DebtSuggestionState.discarded),
    ),
  );

  /// Whether [rel] has changes not committed in [repoRoot] (P5).
  Future<bool> isDirty(String repoRoot, String rel) async {
    final out = await _git(repoRoot).git(['status', '--porcelain', '--', rel]);
    return out.trim().isNotEmpty;
  }

  /// The own commit of an item made by hand on the main branch (R18): only
  /// the file, `docs: DT-09 título`, never pushed. [wasDirty] is the state
  /// of the file before the app wrote it: then the commit stays with the
  /// person (P5).
  Future<DebtCommitResult> commitOwn(
    String repoRoot,
    String rel, {
    required String code,
    required String title,
    required bool wasDirty,
  }) async {
    if (wasDirty) return DebtCommitResult.dirty;
    final g = _git(repoRoot);
    if ((await g.git(['status', '--porcelain', '--', rel])).trim().isEmpty) {
      return DebtCommitResult.nothing;
    }
    await g.git(['add', '--', rel]);
    await g.git(['commit', '-q', '-m', commitMessage(code, title), '--', rel]);
    return DebtCommitResult.committed;
  }

  /// `docs: DT-09 lotes da equipe técnica`.
  static String commitMessage(String code, String title) {
    var t = title.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.length > 60) t = '${t.substring(0, 59).trimRight()}…';
    if (t.isNotEmpty) t = '${t[0].toLowerCase()}${t.substring(1)}';
    return 'docs: $code $t'.trimRight();
  }

  /// R2 "Usar estes arquivos": the old paths go to the config.
  Future<void> useLegacy(String repoRoot) async {
    final cfg = ProjectConfig.loadSync(repoRoot);
    var d = cfg.debts;
    final snap = await DebtSnapshot.load(repoRoot);
    if (snap.legacyDebts != null) d = d.copyWith(debtsPath: snap.legacyDebts);
    if (snap.legacyDecisions != null) {
      d = d.copyWith(decisionsPath: snap.legacyDecisions);
    }
    await ProjectConfig.save(repoRoot, cfg.copyWith(debts: d));
  }

  /// R2 "Mover para a raiz": `git mv` to the configured names, with the
  /// relative links of the rows fixed (`specs/31-…` → `docs/specs/31-…`).
  Future<void> moveLegacy(String repoRoot) async {
    final snap = await DebtSnapshot.load(repoRoot);
    final g = _git(repoRoot);
    for (final (legacy, target) in [
      (snap.legacyDebts, snap.config.debtsPath),
      (snap.legacyDecisions, snap.config.decisionsPath),
    ]) {
      if (legacy == null) continue;
      await g.git(['mv', '--', legacy, target]);
      final f = File('$repoRoot/$target');
      final text = await f.readAsString();
      final fixed = fixRelativeLinks(text, from: legacy, to: target);
      if (fixed != text) {
        await f.writeAsString(fixed);
        await g.git(['add', '--', target]);
      }
    }
  }

  /// The relative links of [text] (`](specs/x.md)`) rewritten for a file
  /// moved from [from] to [to]. Absolute links and anchors stay.
  static String fixRelativeLinks(
    String text, {
    required String from,
    required String to,
  }) {
    List<String> dirOf(String p) {
      final parts = p.split('/')..removeLast();
      return parts;
    }

    final fromDir = dirOf(from), toDir = dirOf(to);
    return text.replaceAllMapped(RegExp(r'\]\(([^)\s]+)\)'), (m) {
      final target = m.group(1)!;
      if (target.startsWith('#') ||
          target.startsWith('/') ||
          RegExp(
            r'^[a-z][a-z0-9+.-]*:',
            caseSensitive: false,
          ).hasMatch(target)) {
        return m.group(0)!;
      }
      // Absolute inside the repository, then relative to the new folder.
      final abs = <String>[...fromDir];
      for (final s in target.split('/')) {
        if (s == '..') {
          if (abs.isNotEmpty) abs.removeLast();
        } else if (s != '.') {
          abs.add(s);
        }
      }
      var common = 0;
      while (common < toDir.length &&
          common < abs.length - 1 &&
          toDir[common] == abs[common]) {
        common++;
      }
      final rel = [
        for (var i = common; i < toDir.length; i++) '..',
        ...abs.sublist(common),
      ].join('/');
      return '](${rel.isEmpty ? '.' : rel})';
    });
  }
}

final debtServiceProvider = Provider(
  (ref) => DebtService(links: ref.watch(debtLinksRepoProvider)),
);
