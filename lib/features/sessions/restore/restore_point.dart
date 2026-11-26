import 'package:flutter/foundation.dart';

import '../../../core/git/git_service.dart';

/// Phase of a restore point of a turn (SPEC-084 R1).
enum RestorePhase { start, end }

/// Where the hidden refs of an owner live (SPEC-084 R3, P8):
/// `refs/promptorium/restore/<owner>/`.
const restoreRefsPrefix = 'refs/promptorium/restore/';

String restoreOwnerKey({String? sessionId, int? conversationId}) =>
    sessionId ?? 'conversa-$conversationId';

String restoreRef(String owner, int turn, String suffix) =>
    '$restoreRefsPrefix$owner/$turn-$suffix';

/// Suffixes of the refs of one turn.
abstract final class RestoreRefs {
  static const start = 'inicio';
  static const end = 'fim';
  static const beforeUndo = 'antes-de-desfazer';
  static const undone = 'desfeito';
  static const all = [start, end, beforeUndo, undone];
}

/// One file of the undo dialog (SPEC-084 R6, R7).
@immutable
class UndoFile {
  const UndoFile({
    required this.path,
    required this.kind,
    this.added,
    this.removed,
    this.userDuring = false,
    this.userAfter = false,
    this.editedAt,
    this.otherSessions = const [],
  });

  final String path;

  /// What the agent did to it in the turn: modified, created (it will be
  /// deleted) or deleted (it comes back).
  final TreeChangeKind kind;
  final int? added;
  final int? removed;

  /// Saved by the person through Código during the turn (still checked).
  final bool userDuring;

  /// Changed after the turn ended (comes unchecked: the person's).
  final bool userAfter;

  /// When it was last changed (the "editado por você às 14:09").
  final DateTime? editedAt;

  /// Other live sessions in the same folder that changed it too (R16).
  final List<String> otherSessions;

  /// Checked when the dialog opens.
  bool get checkedByDefault => !userAfter;
}

/// One commit the undo throws away (R6, R12).
@immutable
class UndoCommit {
  const UndoCommit({
    required this.sha,
    required this.shortSha,
    required this.subject,
    this.pushed = false,
  });

  final String sha;
  final String shortSha;
  final String subject;

  /// Already on a remote branch.
  final bool pushed;
}

/// Something the point cannot bring back (R6).
@immutable
class NotRestored {
  const NotRestored(this.path, this.reason);

  final String path;
  final String reason;
}

/// Another live session in the same directory (R16).
@immutable
class OtherSession {
  const OtherSession(this.title, this.files);

  final String title;
  final List<String> files;
}

/// The agent's conversation in the undo window (SPEC-110 R7, R9).
@immutable
class ConversationPlan {
  const ConversationPlan({
    required this.provider,
    required this.agent,
    this.firstTurn = 0,
    this.lastTurn = 0,
    this.beforeTurnId,
    this.onlyCodex = false,
    this.reason,
    this.copyAt,
  });

  /// `codex`, `claude`…
  final String provider;

  /// "Codex", "Claude Code".
  final String agent;

  /// Turns the agent forgets.
  final int firstTurn;
  final int lastTurn;

  /// The agent's turn it goes back to before; null = it cannot ([reason]).
  final String? beforeTurnId;

  /// The agent has no way back ("Só Codex: …").
  final bool onlyCodex;
  final String? reason;

  /// Redo: when the copy the session goes on in was made; null = there is
  /// none ([reason]).
  final DateTime? copyAt;

  bool get available => beforeTurnId != null;
}

/// What going back to the start of a turn would do, worked out from the
/// two points of the turn and the current state (SPEC-084 R6, R7, R12,
/// R16).
@immutable
class UndoPlan {
  const UndoPlan({
    this.restore = const [],
    this.changedAfter = const [],
    this.commits = const [],
    this.remotes = const [],
    this.kept = const [],
    this.notRestored = const [],
    this.others = const [],
    this.startBranch,
    this.currentBranch,
    this.startHead = '',
    this.conversation,
  });

  /// The agent's conversation (SPEC-110); null = not offered (a VIBE, or a
  /// redo of an undo that kept it).
  final ConversationPlan? conversation;

  /// Files the agent changed in the turn(s): they go back (checked).
  final List<UndoFile> restore;

  /// Files the agent changed and the person changed again after the turn
  /// (unchecked: checking them loses the person's edit).
  final List<UndoFile> changedAfter;

  /// Commits from the start HEAD to the current one, newest first.
  final List<UndoCommit> commits;

  /// Remote branches that already have some of [commits].
  final List<String> remotes;

  /// Uncommitted files at the start that the turn did not touch: they stay
  /// as they are (the `src/cupom.ts` of the example).
  final List<String> kept;

  final List<NotRestored> notRestored;
  final List<OtherSession> others;

  final String? startBranch;
  final String? currentBranch;
  final String startHead;

  List<UndoCommit> get pushedCommits => [
    for (final c in commits)
      if (c.pushed) c,
  ];

  /// Some commit was pushed: only the files go back (R12, P4).
  bool get filesOnly => commits.any((c) => c.pushed);

  bool get branchChanged => startBranch != null && currentBranch != startBranch;

  /// Nothing would change.
  bool get isEmpty =>
      restore.isEmpty && changedAfter.isEmpty && commits.isEmpty;

  List<UndoFile> get allFiles => [...restore, ...changedAfter];

  /// Paths checked when the dialog opens.
  Set<String> get defaultSelection => {for (final f in restore) f.path};
}

/// Builds the [UndoPlan] (pure):
/// - [turn]: what changed from the start of the turn to its end (the
///   agent's, P7);
/// - [after]: from the end of the turn to now (the person's, when the same
///   file is in [turn]); files only in [after] are never touched (R7);
/// - [editedDuring]: files saved through Código during the turn;
/// - [editedAt]: last change of the files (for the "depois" label);
/// - [commits] / [pushed] / [remotes]: `startHead..HEAD` (R12);
/// - [kept]: uncommitted files at the start (left out when the turn touched
///   them);
/// - [others]: files changed by other live sessions in the same folder, by
///   title (R16).
UndoPlan buildUndoPlan({
  required List<TreeChange> turn,
  List<TreeChange> after = const [],
  Set<String> editedDuring = const {},
  Map<String, DateTime> editedAt = const {},
  List<GitLogEntry> commits = const [],
  Set<String> pushed = const {},
  List<String> remotes = const [],
  List<String> kept = const [],
  List<String> ignored = const [],
  List<String> large = const [],
  Map<String, Set<String>> others = const {},
  String? startBranch,
  String? currentBranch,
  String startHead = '',
  ConversationPlan? conversation,
}) {
  final afterPaths = {for (final c in after) c.path};
  final restore = <UndoFile>[];
  final changedAfter = <UndoFile>[];
  final turnPaths = <String>{};
  for (final c in turn) {
    turnPaths.add(c.path);
    final userAfter = afterPaths.contains(c.path);
    final f = UndoFile(
      path: c.path,
      kind: c.kind,
      added: c.added,
      removed: c.removed,
      userDuring: editedDuring.contains(c.path),
      userAfter: userAfter,
      editedAt: editedAt[c.path],
      otherSessions: [
        for (final MapEntry(key: title, value: files) in others.entries)
          if (files.contains(c.path)) title,
      ],
    );
    (userAfter ? changedAfter : restore).add(f);
  }
  return UndoPlan(
    restore: restore,
    changedAfter: changedAfter,
    commits: [
      for (final c in commits)
        UndoCommit(
          sha: c.sha,
          shortSha: c.shortSha,
          subject: c.subject,
          pushed: pushed.contains(c.sha),
        ),
    ],
    remotes: remotes,
    kept: [
      for (final k in kept)
        if (!turnPaths.contains(k)) k,
    ],
    notRestored: [
      for (final i in ignored) NotRestored(i, 'ignorado pelo .gitignore'),
      for (final l in large) NotRestored(l, 'grande demais, fora do ponto'),
    ],
    others: [
      for (final MapEntry(key: title, value: files) in others.entries)
        OtherSession(title, [
          for (final p in turnPaths)
            if (files.contains(p)) p,
        ]),
    ],
    startBranch: startBranch,
    currentBranch: currentBranch,
    startHead: startHead,
    conversation: conversation,
  );
}
