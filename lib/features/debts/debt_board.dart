import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/repos/debt_links_repo.dart';
import 'debt_files.dart';
import 'debt_item.dart';
import 'debt_table.dart';

/// State of a debt on the screen (R13).
enum DebtRowState {
  open('aberto'),

  /// `paymentSpecId` set and the spec still open (R15).
  paying('em pagamento'),
  paid('pago'),

  /// Born in a spec not merged yet: the row is only in its worktree.
  inSpec('na spec');

  const DebtRowState(this.label);
  final String label;
}

/// `31` of `SPEC-031`, `7` of `VIBE-007`.
int? specNumber(String code) {
  final m = RegExp(r'(\d+)\s*$').firstMatch(code);
  return m == null ? null : int.parse(m.group(1)!);
}

/// `spec 31` / `VIBE-007`, as written in the files.
String specLabel(Spec s) => s.code.toUpperCase().startsWith('VIBE')
    ? s.code
    : 'spec ${specNumber(s.code) ?? s.code}';

/// A debt with its link and where it is.
@immutable
class DebtRowView {
  const DebtRowView({
    required this.item,
    required this.state,
    required this.origin,
    this.link,
    this.originSpec,
    this.paymentSpec,
    this.inSpec,
  });

  final DebtItem item;
  final DebtRowState state;

  /// `spec 25 · Q5`, `DP-01`, `revisão`, `sessão`, `à mão`.
  final String origin;
  final DebtLink? link;
  final Spec? originSpec;
  final Spec? paymentSpec;

  /// The spec whose worktree has the row ([DebtRowState.inSpec]).
  final Spec? inSpec;

  bool get open =>
      state == DebtRowState.open ||
      state == DebtRowState.paying ||
      state == DebtRowState.inSpec;

  /// "pago de carona?" waiting for the person (R17).
  bool get piggybackToConfirm =>
      link?.piggybackState == DebtPiggybackState.toConfirm;
}

@immutable
class DecisionRowView {
  const DecisionRowView({
    required this.item,
    required this.origin,
    this.link,
    this.originSpec,
    this.inSpec,
  });

  final DecisionItem item;
  final String origin;
  final DebtLink? link;
  final Spec? originSpec;
  final Spec? inSpec;
}

/// Everything the screen "Débitos e decisões" shows for one repository.
@immutable
class DebtBoard {
  const DebtBoard({
    required this.snapshot,
    required this.debts,
    required this.decisions,
    required this.suggestions,
    required this.orphans,
  });

  final DebtSnapshot snapshot;
  final List<DebtRowView> debts;
  final List<DecisionRowView> decisions;

  /// Pending suggestions of the agent (R7, R11).
  final List<DebtLink> suggestions;

  /// Links whose code is in no file (R4): shown, never written back.
  final List<DebtLink> orphans;

  List<DebtRowView> get openDebts => [
    for (final d in debts)
      if (d.open) d,
  ];

  List<DebtRowView> get paidDebts => [
    for (final d in debts)
      if (d.state == DebtRowState.paid) d,
  ];

  /// Open debts of the main branch's file (the Quadro chip, R14).
  int get openCount => [
    for (final d in debts)
      if (d.state == DebtRowState.open || d.state == DebtRowState.paying) d,
  ].length;

  List<DecisionRowView> get pending => [
    for (final d in decisions)
      if (!d.item.decided) d,
  ];

  List<DecisionRowView> get decided => [
    for (final d in decisions)
      if (d.item.decided) d,
  ];

  List<UnrecognizedLine> unrecognized(DebtKind kind) => kind == DebtKind.debt
      ? snapshot.debts.unrecognized
      : snapshot.decisions.unrecognized;

  /// The open debts whose "Onde" cites [path] (R16): by path, or by file
  /// name when "Onde" has only the name. A function without a file does not
  /// count.
  List<DebtRowView> debtsForPath(String path) => [
    for (final d in openDebts)
      if (debtCitesPath(d.item, path)) d,
  ];

  static DebtBoard build({
    required DebtSnapshot snapshot,
    required List<DebtLink> links,
    required List<Spec> specs,
    Map<int, DebtDocument> worktreeDebts = const {},
    Map<int, DebtDocument> worktreeDecisions = const {},
  }) {
    final byId = {for (final s in specs) s.id: s};
    final byCode = {
      for (final l in links)
        if (l.code != null) l.code!: l,
    };
    Spec? spec(int? id) => id == null ? null : byId[id];
    bool openSpec(Spec? s) => s != null && s.stage != SpecStage.done;

    String originOf(String what, DebtLink? l) {
      if (l != null) {
        final s = spec(l.originSpecId);
        if (s != null) {
          final q = l.originQuestion;
          return '${specLabel(s)}${q == null ? '' : ' · $q'}';
        }
        if (l.originDecision case final d?) return d;
        if (l.originReviewCommentId != null) return 'revisão';
        if (l.originSessionId != null) return 'sessão';
      }
      return originFromText(what) ?? 'à mão';
    }

    final rows = <DebtRowView>[];
    final mainCodes = <String>{};
    for (final d in snapshot.debts.debts) {
      mainCodes.add(d.code);
      final l = byCode[d.code];
      final pay = spec(l?.paymentSpecId);
      rows.add(
        DebtRowView(
          item: d,
          link: l,
          origin: originOf(d.what, l),
          originSpec: spec(l?.originSpecId),
          paymentSpec: pay,
          state: d.paid
              ? DebtRowState.paid
              : openSpec(pay)
              ? DebtRowState.paying
              : DebtRowState.open,
        ),
      );
    }
    // Rows only in the worktree of an open spec.
    final wtCodes = <String>{};
    for (final MapEntry(key: specId, value: doc) in worktreeDebts.entries) {
      final s = byId[specId];
      if (!openSpec(s)) continue;
      for (final d in doc.debts) {
        if (mainCodes.contains(d.code) || !wtCodes.add(d.code)) continue;
        final l = byCode[d.code];
        rows.add(
          DebtRowView(
            item: d,
            link: l,
            origin: originOf(d.what, l),
            originSpec: spec(l?.originSpecId) ?? s,
            inSpec: s,
            state: d.paid ? DebtRowState.paid : DebtRowState.inSpec,
          ),
        );
      }
    }
    final decisions = <DecisionRowView>[];
    final mainDp = <String>{};
    for (final d in snapshot.decisions.decisions) {
      mainDp.add(d.code);
      final l = byCode[d.code];
      decisions.add(
        DecisionRowView(
          item: d,
          link: l,
          origin: originOf(d.origin, l),
          originSpec: spec(l?.originSpecId),
        ),
      );
    }
    for (final MapEntry(key: specId, value: doc) in worktreeDecisions.entries) {
      final s = byId[specId];
      if (!openSpec(s)) continue;
      for (final d in doc.decisions) {
        if (mainDp.contains(d.code) || !wtCodes.add(d.code)) continue;
        final l = byCode[d.code];
        decisions.add(
          DecisionRowView(
            item: d,
            link: l,
            origin: originOf(d.origin, l),
            originSpec: spec(l?.originSpecId) ?? s,
            inSpec: s,
          ),
        );
      }
    }
    rows.sort((a, b) => a.item.number.compareTo(b.item.number));
    decisions.sort((a, b) => a.item.number.compareTo(b.item.number));
    final known = {...mainCodes, ...mainDp, ...wtCodes};
    return DebtBoard(
      snapshot: snapshot,
      debts: rows,
      decisions: decisions,
      suggestions: [
        for (final l in links)
          if (l.suggestionState == DebtSuggestionState.pending) l,
      ],
      orphans: [
        for (final l in links)
          if (l.code != null &&
              l.suggestionState != DebtSuggestionState.pending &&
              !known.contains(l.code))
            l,
      ],
    );
  }
}

/// `spec 29 · P3` from "(spec 29, P3)" in a cell; `DP-01` when the
/// parentheses cite a decision.
String? originFromText(String what) {
  final spec = RegExp(
    r'spec\]?\s*0*(\d+)\]?(?:\([^)]*\))?\s*[,·(]?\s*([QPK]\d+)?',
    caseSensitive: false,
  ).firstMatch(what);
  if (spec != null) {
    final q = spec.group(2);
    return 'spec ${spec.group(1)}${q == null ? '' : ' · $q'}';
  }
  final dp = RegExp(r'\bDP-\d{2,}\b').firstMatch(what);
  return dp?.group(0);
}

/// Whether "Onde" of [d] cites [path] (R16).
bool debtCitesPath(DebtItem d, String path) {
  final p = path.replaceAll('\\', '/');
  final name = p.split('/').last;
  for (final ref in d.whereRefs) {
    final r = ref.trim().replaceAll('\\', '/');
    if (r.isEmpty) continue;
    final file = r.split(RegExp(r'[\s(]')).first;
    final hasExt = RegExp(r'\.[A-Za-z0-9]{1,6}$').hasMatch(file);
    if (file.contains('/')) {
      if (p == file || p.endsWith('/$file') || file.endsWith('/$p')) {
        return true;
      }
    } else if (hasExt && file == name) {
      return true;
    }
  }
  return false;
}

/// Key of [debtBoardProvider]: the workspace and its repository root.
typedef DebtBoardKey = ({int workspaceId, String root});

final _debtLinksProvider = StreamProvider.family<List<DebtLink>, String>(
  (ref, root) => ref.watch(debtLinksRepoProvider).watchRepo(root),
);

/// The files of the worktrees of the open specs (the "na spec N" rows).
final _worktreeDocsProvider =
    FutureProvider.family<
      ({Map<int, DebtDocument> debts, Map<int, DebtDocument> decisions}),
      DebtBoardKey
    >((ref, key) async {
      final specs = ref.watch(specsProvider(key.workspaceId)).value ?? const [];
      final snap = ref.watch(debtSnapshotProvider(key.root)).value;
      final cfg = snap?.config;
      if (cfg == null) {
        return (
          debts: const <int, DebtDocument>{},
          decisions: const <int, DebtDocument>{},
        );
      }
      final debts = <int, DebtDocument>{};
      final decisions = <int, DebtDocument>{};
      for (final s in specs) {
        final wt = s.worktreePath;
        if (wt == null || s.stage == SpecStage.done) continue;
        if (!Directory(wt).existsSync()) continue;
        debts[s.id] = await DebtFiles.read(wt, cfg.debtsPath, DebtKind.debt);
        decisions[s.id] = await DebtFiles.read(
          wt,
          cfg.decisionsPath,
          DebtKind.decision,
        );
      }
      return (debts: debts, decisions: decisions);
    });

/// The screen's state of one repository (null while the files load).
final debtBoardProvider = Provider.family<DebtBoard?, DebtBoardKey>((ref, key) {
  final snap = ref.watch(debtSnapshotProvider(key.root)).value;
  if (snap == null) return null;
  final links = ref.watch(_debtLinksProvider(key.root)).value ?? const [];
  final specs = ref.watch(specsProvider(key.workspaceId)).value ?? const [];
  final wt = ref.watch(_worktreeDocsProvider(key)).value;
  return DebtBoard.build(
    snapshot: snap,
    links: links,
    specs: specs,
    worktreeDebts: wt?.debts ?? const {},
    worktreeDecisions: wt?.decisions ?? const {},
  );
});

/// The board of [w] (a workspace).
DebtBoardKey debtKeyOf(Workspace w) => (workspaceId: w.id, root: w.path);
