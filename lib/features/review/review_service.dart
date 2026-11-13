import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show max;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/git/diff_parser.dart';
import '../../core/fs/dir_watcher.dart';
import '../../core/git/git_service.dart';
import '../../core/git/agent_trailer.dart';
import '../../data/providers.dart';
import '../sessions/session_manager.dart';
import '../project/project_memory.dart';
import '../vibe/vibe_numbers.dart';
import '../specs/spec_service.dart';
import '../tasks/task_actions.dart';
import 'pr_babysitter.dart';
import 'conflict_resolution.dart';
import 'restack.dart';
import 'review_logic.dart';
import 'comment_anchor.dart';
import 'merge_readiness.dart';
import 'merge_options.dart';
import 'review_host.dart';
import '../project/project_config.dart';
import 'auto_reviewer.dart' show AutoReviewer, ReviewPhase;
import '../board/board_rules.dart';
import 'widgets/spec_review_panel.dart';

export 'review_logic.dart';

/// Runs a short command in a folder (`which gh`, `gh pr create`, `xdg-open`).
/// Injected so tests can simulate a missing `gh` / remote.
typedef CommandRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

Future<ProcessResult> _defaultCommand(
  String exe,
  List<String> args, {
  String? workingDirectory,
}) => Process.run(exe, args, workingDirectory: workingDirectory);

final commandRunnerProvider = Provider<CommandRunner>((ref) => _defaultCommand);

/// User-facing Review failure (shown in dialogs / snackbars).
class ReviewException implements Exception {
  const ReviewException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MergeConflictException extends ReviewException {
  const MergeConflictException(super.message, this.files);
  final List<String> files;
}

/// What the Review shows for one session.
///
/// **Comparison:** `git diff <merge-base>` in the worktree, i.e. the session
/// branch since it left the base (`base...HEAD`) **plus** the working tree
/// (uncommitted changes); untracked files come from
/// `git diff --no-index /dev/null <file>`.
@immutable
class ReviewDetail {
  const ReviewDetail({
    required this.session,
    this.task,
    this.baseBranch = '',
    this.mergeBase = '',
    this.files = const [],
    this.commitsAhead = 0,
    this.uncommitted = 0,
    this.error,
  });

  final Session session;
  final Task? task;
  final String baseBranch;
  final String mergeBase;
  final List<DiffFile> files;

  /// Commits of the session branch after the merge-base.
  final int commitsAhead;

  /// Entries of `git status` in the worktree (not committed yet).
  final int uncommitted;
  final String? error;

  int get additions => files.fold(0, (n, f) => n + fileStats(f).$1);

  int get deletions => files.fold(0, (n, f) => n + fileStats(f).$2);
}

/// Whether "Criar PR" can run (`gh` in the PATH + a git remote).
@immutable
class PrAvailability {
  const PrAvailability({
    required this.available,
    this.reason,
    this.remote,
    this.host = 'github',
    this.hostname,
    this.installUrl,
    this.remotes = const [],
  });

  final bool available;

  /// Tooltip when not [available].
  final String? reason;
  final String? remote;
  final String host;
  final String? hostname, installUrl;
  final List<String> remotes;
  String get requestLabel => host == 'gitlab' ? 'MR' : 'PR';
}

@immutable
class MergeResult {
  const MergeResult({
    required this.commit,
    this.warnings = const [],
    this.restacked = const [],
  });

  /// Hash of the merge commit in the base branch.
  final String commit;

  /// Cleanup steps that failed (worktree / branch removal).
  final List<String> warnings;

  /// Children whose base was redone after the merge (SPEC-032 R6).
  final List<RestackResult> restacked;
}

/// The project root against the branch the queue merges into (SPEC-032 R11).
@immutable
class RootStatus {
  const RootStatus({required this.base, this.branch, this.dirty = const []});

  final String base;

  /// Branch checked out in the root (null = detached HEAD).
  final String? branch;

  /// Tracked files with uncommitted changes (not the project memory).
  final List<String> dirty;

  bool get offBase => branch != base;
  bool get ok => !offBase && dirty.isEmpty;
}

/// Outcome of "Mergear a pilha" (SPEC-032 R13).
@immutable
class StackMergeResult {
  const StackMergeResult({
    this.merged = const [],
    this.stoppedAt,
    this.reason,
    this.restacked = const [],
  });

  /// Sessions merged, in order.
  final List<String> merged;

  /// Session where the sequence stopped (null = the whole stack went in).
  final String? stoppedAt;
  final String? reason;
  final List<RestackResult> restacked;
}

/// Git work of the Review screen (plano, Fase 9).
class ReviewService {
  ReviewService(this._ref);

  final Ref _ref;

  GitService _git(String root) => _ref.read(gitServiceFactoryProvider)(root);

  CommandRunner get _run => _ref.read(commandRunnerProvider);

  Future<({Session session, Workspace workspace, Task? task, Spec? spec})>
  _context(String sessionId) async {
    final s = await _ref.read(sessionsRepoProvider).getById(sessionId);
    if (s == null) throw ReviewException('Sessão $sessionId não encontrada.');
    final ws = await _ref.read(workspacesRepoProvider).getById(s.workspaceId);
    if (ws == null) throw const ReviewException('Workspace não encontrado.');
    final task = s.taskId == null
        ? null
        : await _ref.read(tasksRepoProvider).getById(s.taskId!);
    final spec = s.specId == null
        ? null
        : await _ref.read(specsRepoProvider).getById(s.specId!);
    return (session: s, workspace: ws, task: task, spec: spec);
  }

  static bool hasWorktree(Session s, Workspace ws) =>
      s.worktreePath != ws.path && Directory(s.worktreePath).existsSync();

  /// Merge target: `sessions.base_branch`, or the branch checked out in the
  /// workspace root (rows created before schema v5, or a base branch that no
  /// longer exists).
  Future<String> baseBranchOf(Session s, Workspace ws) async {
    final b = s.baseBranch;
    if (b != null && b.isNotEmpty) {
      _safeRef(b, 'Branch base');
      // The base may be the branch of a spec already merged (and deleted):
      // its work is in the branch checked out in the root.
      try {
        await _git(ws.path)
            .git(['rev-parse', '--verify', '--quiet', 'refs/heads/$b']);
        return b;
      } on GitException {
        // falls through to the root's branch
      }
    }
    return _safeRef(
      await _git(ws.path).currentBranch() ?? 'main',
      'Branch base',
    );
  }

  /// Refs coming from data must not be parsed by git as options.
  static String _safeRef(String value, String what) {
    if (value.isEmpty || value.startsWith('-')) {
      throw GitException('$what inválida: "$value"');
    }
    return value;
  }

  /// Commits ahead of the base or uncommitted files. Git errors = false.
  Future<bool> hasChanges(Session s, Workspace ws) async {
    try {
      final git = _git(s.worktreePath);
      if ((await git.status()).isNotEmpty) return true;
      final base = await baseBranchOf(s, ws);
      final n = await git.git(['rev-list', '--count', '$base..HEAD']);
      return (int.tryParse(n.trim()) ?? 0) > 0;
    } on GitException catch (e) {
      debugPrint('review ${s.id}: $e');
      return false;
    }
  }

  /// "Aguardando review" of a workspace (see [isAwaitingReview]).
  ///
  /// One item per spec: its latest session (all step sessions share the
  /// spec's worktree and branch).
  Future<List<ReviewItem>> queue(
    Workspace ws,
    List<Session> sessions,
    List<Task> tasks, [
    List<Spec> specs = const [],
  ]) async {
    final byId = {for (final t in tasks) t.id: t};
    final specById = {for (final s in specs) s.id: s};
    final latestOfSpec = <int, Session>{};
    for (final s in sessions) {
      final id = s.specId;
      if (id == null || s.duelId != null) continue;
      final cur = latestOfSpec[id];
      if (cur == null || s.startedAt.isAfter(cur.startedAt)) {
        latestOfSpec[id] = s;
      }
    }
    final items = <ReviewItem>[];
    for (final s in sessions) {
      // Best-of-N attempts are compared on the card, not reviewed.
      if (s.duelId != null) continue;
      final spec = s.specId == null ? null : specById[s.specId];
      if (s.specId != null && latestOfSpec[s.specId]?.id != s.id) continue;
      final task = s.taskId == null ? null : byId[s.taskId];
      final wt = hasWorktree(s, ws);
      // SPEC-043 R2: the agent resolving a conflict keeps the card here.
      final resolution = ConflictResolution.decode(
        _ref.read(appSettingsProvider)[resolutionKey(s.id)],
      );
      if ((resolution?.state.active ?? false) &&
          wt &&
          s.status != SessionStatus.merged &&
          s.mergeCommit == null &&
          (spec == null || spec.stage != SpecStage.done)) {
        items.add(ReviewItem(session: s, task: task, spec: spec));
        continue;
      }
      // Cheap checks first: git only for candidates.
      if (!isAwaitingReview(
        session: s,
        task: task,
        spec: spec,
        hasWorktree: wt,
        hasChanges: true,
      )) {
        continue;
      }
      final changes = spec != null || task?.status == TaskStatus.review
          ? true
          : await hasChanges(s, ws);
      if (isAwaitingReview(
        session: s,
        task: task,
        spec: spec,
        hasWorktree: wt,
        hasChanges: changes,
      )) {
        items.add(ReviewItem(session: s, task: task, spec: spec));
      }
    }
    return items;
  }

  /// Changed files of the session (see [ReviewDetail] for the comparison).
  Future<ReviewDetail> load(String sessionId) async {
    final c = await _context(sessionId);
    final s = c.session;
    if (!hasWorktree(s, c.workspace)) {
      return ReviewDetail(
        session: s,
        task: c.task,
        error: s.status == SessionStatus.merged
            ? 'Merge já feito${s.mergeCommit == null ? '' : ' (${_short(s.mergeCommit!)})'}.'
            : 'A sessão não tem worktree próprio.',
      );
    }
    final git = _git(s.worktreePath);
    try {
      final base = await baseBranchOf(s, c.workspace);
      final mb = (await git.git(['merge-base', base, 'HEAD'])).trim();
      final ahead = int.tryParse(
        (await git.git(['rev-list', '--count', '$mb..HEAD'])).trim(),
      );
      final status = await git.status();
      final files = DiffParser.parse(
        await git.git([
          'diff',
          '--no-color',
          '--no-ext-diff',
          '--unified=3',
          '-M',
          mb,
        ]),
      );
      for (final u in status.where((e) => e.isUntracked)) {
        files.addAll(DiffParser.parse(await _untrackedDiff(git, u.path)));
      }
      files.sort((a, b) => a.path.compareTo(b.path));
      return ReviewDetail(
        session: s,
        task: c.task,
        baseBranch: base,
        mergeBase: mb,
        files: files,
        commitsAhead: ahead ?? 0,
        uncommitted: status.length,
      );
    } on GitException catch (e) {
      return ReviewDetail(session: s, task: c.task, error: '$e');
    }
  }

  Future<AnchorShifts> anchorShifts(
    String sessionId,
    List<ReviewCommentRow> comments,
  ) async {
    final c = await _context(sessionId);
    final git = _git(c.session.worktreePath);
    final result = <int, ({int? line, String? reason})>{};
    final cache = <String, ({List<DiffHunk> hunks, String? reason})>{};
    for (final row in comments) {
      final sha = row.commitSha, path = row.path;
      if (sha == null || path == null) continue;
      final key = '$sha:$path';
      if (!cache.containsKey(key)) {
        try {
          _safeRef(sha, 'Commit');
          // The worktree, not HEAD: a file not committed yet still counts.
          if (!await File('${c.session.worktreePath}/$path').exists()) {
            cache[key] = (hunks: [], reason: 'arquivo removido ou renomeado');
          } else {
            final names = await git.git([
              'diff',
              '--name-status',
              '-M',
              '$sha..HEAD',
              '--',
              path,
            ]);
            final removed = names
                .split('\n')
                .any((l) => l.startsWith('D\t') || l.startsWith('R'));
            final diff = await git.git([
              'diff',
              '--no-ext-diff',
              '--no-color',
              '-U0',
              sha,
              '--',
              path,
            ]);
            cache[key] = (
              hunks: DiffParser.parse(diff).expand((f) => f.hunks).toList(),
              reason: removed ? 'arquivo removido ou renomeado' : null,
            );
          }
        } on GitException {
          cache[key] = (hunks: [], reason: 'commit ou arquivo indisponível');
        }
      }
      final change = cache[key]!;
      final line = row.line == null || row.line == 0
          ? row.line
          : shiftedLine(row.line!, change.hunks);
      result[row.id] = (
        line: line,
        reason:
            change.reason ??
            (row.line != null && row.line! > 0 && line == null
                ? 'linha alterada desde a rodada'
                : null),
      );
    }
    return result;
  }

  Future<String?> roundUnavailable(String sessionId, String? sha) async {
    if (sha == null || sha.isEmpty) {
      return 'esta rodada não registrou o commit revisado';
    }
    final c = await _context(sessionId);
    try {
      _safeRef(sha, 'Commit');
      final git = _git(c.session.worktreePath);
      await git.git(['cat-file', '-e', '$sha^{commit}']);
      await git.git(['merge-base', '--is-ancestor', sha, 'HEAD']);
      return null;
    } on GitException {
      return 'o commit da rodada não existe mais nesta branch';
    }
  }

  Future<ReviewDetail> loadSince(String sessionId, String sha) async {
    final c = await _context(sessionId);
    final reason = await roundUnavailable(sessionId, sha);
    if (reason != null) return ReviewDetail(session: c.session, error: reason);
    final git = _git(c.session.worktreePath);
    try {
      final status = await git.status();
      final files = DiffParser.parse(
        await git.git([
          'diff',
          '--no-color',
          '--no-ext-diff',
          '--unified=3',
          '-M',
          sha,
        ]),
      );
      for (final u in status.where((e) => e.isUntracked)) {
        files.addAll(DiffParser.parse(await _untrackedDiff(git, u.path)));
      }
      files.sort((a, b) => a.path.compareTo(b.path));
      return ReviewDetail(
        session: c.session,
        task: c.task,
        mergeBase: sha,
        baseBranch: await baseBranchOf(c.session, c.workspace),
        files: files,
        commitsAhead: int.parse(
          (await git.git(['rev-list', '--count', '$sha..HEAD'])).trim(),
        ),
        uncommitted: status.length,
      );
    } on GitException catch (e) {
      return ReviewDetail(session: c.session, error: '$e');
    }
  }

  /// `git diff --no-index` exits 1 when there are differences.
  static Future<String> _untrackedDiff(GitService git, String path) async {
    try {
      return await git.git([
        'diff',
        '--no-color',
        '--no-ext-diff',
        '--no-index',
        '--',
        '/dev/null',
        path,
      ]);
    } on GitException catch (e) {
      if (e.exitCode == 1) return e.stdout;
      rethrow;
    }
  }

  /// "Rejeitar hunk": `git apply -R` of the hunk in the worktree (working
  /// tree only). A hunk already **committed** on the session branch is
  /// reverted the same way and stays as an uncommitted change (committed by
  /// the next PR / merge).
  Future<void> rejectHunk(
    String sessionId,
    DiffFile file,
    DiffHunk hunk,
  ) async {
    final c = await _context(sessionId);
    if (!hasWorktree(c.session, c.workspace)) {
      throw const ReviewException('A sessão não tem worktree.');
    }
    final tmp = await Directory.systemTemp.createTemp('promptorium-hunk-');
    try {
      final patch = File('${tmp.path}/hunk.patch');
      await patch.writeAsString(rejectPatch(file, hunk));
      await _git(c.session.worktreePath)
          .git(['apply', '-R', '--whitespace=nowarn', patch.path]);
      if (c.spec case final spec?) {
        await _ref.read(specsRepoProvider).countRejectedHunk(spec.id);
      }
    } on GitException catch (e) {
      throw ReviewException(
        'Não foi possível rejeitar o hunk (o arquivo mudou desde o diff?): '
        '${e.stderr.trim().isEmpty ? e : e.stderr.trim()}',
      );
    } finally {
      await tmp.delete(recursive: true);
    }
  }

  /// "Pedir ajustes ao agente": ONE message with every comment, sent to the
  /// session (`SessionManager.send`, which resumes it with `--resume` when
  /// there is no live process). The task goes back to "Em execução".
  Future<String> requestChanges(
    String sessionId,
    List<ReviewComment> comments, {
    String note = '',
    List<ReviewCommentRow> selected = const [],
  }) async {
    if (comments.isEmpty && selected.isEmpty && note.trim().isEmpty) {
      throw const ReviewException('Escreva um comentário antes de enviar.');
    }
    final c = await _context(sessionId);
    if (c.session.status == SessionStatus.merged) {
      throw const ReviewException('A sessão já foi integrada (merge).');
    }
    final selectedComments = [
      for (final row in selected)
        ReviewComment(
          path: row.path ?? 'Geral',
          line: row.line ?? 0,
          snippet: await _lineOf(c.session.worktreePath, row.path, row.line),
          anchor: '',
          text:
              '[${row.author}, rodada ${row.round}] '
              '${row.body.substring(0, row.body.length.clamp(0, 4000))}',
        ),
    ];
    final msg = adjustmentMessage([
      ...comments,
      ...selectedComments,
    ], note: note);
    try {
      await _ref.read(sessionManagerProvider.notifier).send(sessionId, msg);
    } on SessionException catch (e) {
      throw ReviewException('$e');
    }
    final task = c.task;
    if (task != null && task.status != TaskStatus.running) {
      await _ref.read(taskActionsProvider).move(task.id, TaskStatus.running);
    }
    if (c.spec case final spec?) {
      // A round of the user's in the spec's review history.
      final repo = _ref.read(reviewCommentsRepoProvider);
      final rounds = (await repo.bySpec(spec.id)).map((x) => x.round);
      final round = rounds.isEmpty ? 1 : rounds.reduce(max) + 1;
      String? head;
      try {
        head = await _git(c.session.worktreePath).headSha();
      } on GitException {
        head = null;
      }
      await _ref.read(appDatabaseProvider).transaction(() async {
        await repo.insertAll([
          ReviewCommentsCompanion.insert(
            specId: spec.id,
            round: round,
            author: 'humano',
            body: note.trim().isEmpty ? 'Ajustes pedidos.' : note.trim(),
            verdict: const Value('corrigir'),
            commitSha: Value(head),
          ),
          for (final x in comments)
            ReviewCommentsCompanion.insert(
              specId: spec.id,
              round: round,
              author: 'humano',
              path: Value(x.path),
              line: Value(x.line),
              body: x.text,
              commitSha: Value(head),
            ),
        ]);
        for (final row in selected) {
          if (row.specId != spec.id || row.resolved) continue;
          await repo.setResolved(row.id, true);
        }
      });
    }
    return msg;
  }

  /// The line a comment points at, as it reads now (empty when gone).
  static Future<List<String>> _lineOf(
    String root,
    String? path,
    int? line,
  ) async {
    if (path == null || line == null || line < 1) return const [];
    try {
      final lines = await File('$root/$path').readAsLines();
      return line <= lines.length ? [lines[line - 1]] : const [];
    } on FileSystemException {
      return const [];
    }
  }

  /// Resolves the effective remote before inspecting the corresponding CLI.
  Future<PrAvailability> prAvailability(
    String sessionId, {
    String? remote,
  }) async {
    final c = await _context(sessionId);
    remote ??= _ref.read(appSettingsProvider)['review.remote.$sessionId'];
    if (c.session.prUrl case final saved?) {
      final uri = Uri.tryParse(saved);
      return PrAvailability(
        available: false,
        host: uri?.path.contains('/-/merge_requests/') == true
            ? 'gitlab'
            : 'github',
        hostname: uri?.host,
        reason: 'Request já criado: $saved',
      );
    }
    try {
      final git = _git(c.workspace.path);
      final names = (await git.git(['remote']))
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (names.isEmpty) {
        return const PrAvailability(
          available: false,
          reason: 'O repositório não tem remote (git remote add origin …).',
        );
      }
      String? upstream;
      try {
        upstream = (await _git(
          c.session.worktreePath,
        ).git(['config', '--get', 'branch.${c.session.branch}.remote'])).trim();
      } on GitException {
        /* no upstream */
      }
      final selected = chooseReviewRemote(
        names,
        explicit: remote,
        upstream: upstream,
      );
      if (selected == null) {
        return PrAvailability(
          available: false,
          host: 'unknown',
          remotes: names,
          reason: 'Escolha o remote de destino para as ações de PR/MR.',
        );
      }
      final url = (await git.git(['remote', 'get-url', '--push', selected]))
          .trim();
      final config = await _ref.read(
        projectConfigProvider(c.workspace.path).future,
      );
      final hostname = remoteHost(url);
      final host = detectReviewHost(url, config);
      if (host == null) {
        return PrAvailability(
          available: false,
          remote: selected,
          host: 'unknown',
          hostname: hostname,
          reason: switch (remoteKind(url)) {
            RemoteKind.local =>
              'O remote $selected aponta para um caminho local ($url); ações de PR/MR exigem um hospedeiro remoto.',
            RemoteKind.invalid =>
              'O remote $selected tem URL inválida ($url). Corrija com git remote set-url $selected <url>.',
            RemoteKind.hosted
                when hostname == config.host?.toLowerCase() &&
                    config.hostType != null =>
              'hospedagem.tipo "${config.hostType}" inválido no config.yml para $hostname: use github ou gitlab.',
            RemoteKind.hosted =>
              'Integração com $hostname ainda não disponível. Para instância própria de GitHub/GitLab, configure hospedagem: {host: $hostname, tipo: github|gitlab} no config.yml.',
          },
        );
      }
      if (!hasWorktree(c.session, c.workspace)) {
        return PrAvailability(
          available: false,
          remote: selected,
          host: host,
          hostname: hostname,
          reason: 'A sessão não tem worktree próprio.',
        );
      }
      final cli = host == 'gitlab' ? GitlabHost(_run) : GithubHost(_run);
      final a = await cli.availability(c.workspace.path, hostname!);
      return PrAvailability(
        available: a.available,
        reason: a.reason,
        remote: selected,
        host: host,
        hostname: hostname,
        installUrl: a.installUrl,
      );
    } on GitException catch (e) {
      return PrAvailability(available: false, reason: '$e');
    }
  }

  Future<void> _requireGithubRequest(String url, Workspace ws) async {
    final uri = Uri.tryParse(url);
    // A saved request belongs to its original host, regardless of the remote.
    if (uri != null &&
        uri.hasAuthority &&
        uri.pathSegments.length == 4 &&
        uri.pathSegments[2] == 'pull' &&
        int.tryParse(uri.pathSegments[3]) != null &&
        uri.host != 'gitlab.com') {
      return;
    }
    final gitlab =
        uri != null &&
        (uri.host == 'gitlab.com' || uri.path.contains('/-/merge_requests/'));
    throw ReviewException(
      gitlab
          ? 'Integração do destino deste request indisponível (DT-55).'
          : 'não foi possível ler a URL do PR',
    );
  }

  /// Commits everything pending in [git] (`add -A` + `commit`). Returns
  /// whether a commit was made.
  static Future<bool> _commitPending(
    GitService git,
    String message, {
    bool skipHooks = false,
    String? trailer,
  }) async {
    if ((await git.status()).isEmpty) return false;
    await git.git(['add', '-A']);
    await git.git([
      'commit',
      if (skipHooks) '--no-verify',
      '-q',
      '-m',
      message,
      if (trailer != null) ...['--trailer', trailer],
    ]);
    return true;
  }

  /// `Promptorium-Agente: app · SPEC-042` for the pending commit the app
  /// makes in a session's worktree, when the project marks agent commits
  /// (SPEC-048 R4); null otherwise.
  Future<String?> _appTrailer(Workspace ws, Session s, Spec? spec) async {
    if (!ProjectConfig.loadSync(ws.path).git.markAgentCommits) return null;
    if (!gitSupportsAgentTrailer(await _ref.read(gitVersionProvider.future))) {
      return null;
    }
    return agentTrailerLine(
      appTrailerModel,
      spec?.code ?? sessionOrigin(s.title ?? s.branch),
    );
  }

  /// "Criar PR": commit pending changes, `git push -u <remote> <branch>`,
  /// `gh pr create` (title/body from the task, `--fill` without one).
  /// Returns the PR URL (also stored in `sessions.pr_url`).
  Future<String> createPr(
    String sessionId, {
    bool draft = false,
    String? remote,
  }) async {
    final avail = await prAvailability(sessionId, remote: remote);
    if (!avail.available) {
      throw ReviewException(avail.reason ?? 'Indisponível.');
    }
    final c = await _context(sessionId);
    final s = c.session, task = c.task, spec = c.spec;
    final git = _git(s.worktreePath);
    final String base;
    try {
      base = await baseBranchOf(s, c.workspace);
    } on GitException catch (e) {
      throw ReviewException('$e');
    }
    try {
      await _commitPending(
        git,
        pendingCommitMessage(s, task, spec),
        trailer: await _appTrailer(c.workspace, s, spec),
      );
      await git.git([
        'push',
        '-u',
        _safeRef(avail.remote!, 'Remote'),
        _safeRef(s.branch, 'Branch'),
      ]);
    } on GitException catch (e) {
      throw ReviewException('Falha ao enviar a branch: $e');
    }
    final taskSpec =
        spec ??
        (task?.specId == null
            ? null
            : await _ref.read(specsRepoProvider).getById(task!.specId!));
    final steps = spec == null
        ? const <SpecStep>[]
        : await _ref.read(specStepsRepoProvider).bySpec(spec.id);
    final args = [
      'pr',
      'create',
      '--repo',
      reviewRepositoryUrl(
        (await _git(c.workspace.path)
                .git(['remote', 'get-url', '--push', avail.remote!]))
            .trim(),
      )!,
      '--head',
      s.branch,
      '--base',
      base,
      if (draft) '--draft',
      if (task == null && spec == null)
        '--fill'
      else ...[
        '--title',
        reviewTitle(s, task, spec),
        '--body',
        [
          if (spec != null) ...[
            'Spec: ${spec.code} (`${spec.path}`)',
            'Etapas: ${spec.requirements.map((r) {
              final done = steps.any((x) => x.step == r.id && x.status == StepStatus.done);
              return '- [${done ? 'x' : ' '}] ${r.id} · ${r.text}';
            }).join('\n')}',
          ] else ...[
            if (task!.body?.trim().isNotEmpty ?? false) task.body!.trim(),
            if (taskSpec != null)
              'Spec: ${taskSpec.code} (`${taskSpec.path}`)'
                  '${task.requirement == null ? '' : ' · requisito ${task.requirement}'}',
          ],
          'Criado pelo Promptorium (sessão ${_short(s.id)}).',
        ].join('\n\n'),
      ],
    ];
    final ProcessResult r;
    try {
      r = await _run('gh', args, workingDirectory: s.worktreePath);
    } on ProcessException catch (e) {
      throw ReviewException('Falha ao executar gh: ${e.message}');
    }
    if (r.exitCode != 0) {
      final err = '${r.stderr}'.trim();
      throw ReviewException(
        'gh pr create falhou: ${err.isEmpty ? '${r.stdout}'.trim() : err}',
      );
    }
    final url = '${r.stdout}'
        .split('\n')
        .map((l) => l.trim())
        .lastWhere((l) => l.startsWith('http'), orElse: () => '');
    if (url.isNotEmpty) {
      await _ref.read(sessionsRepoProvider).setPrUrl(s.id, url);
    }
    return url;
  }

  final _openedPr = <String, ({DateTime at, Future<PrStatus?> result})>{};
  Future<PrStatus?> refreshPrComments(String sessionId) {
    final cached = _openedPr[sessionId];
    if (cached != null &&
        DateTime.now().difference(cached.at) < const Duration(minutes: 1)) {
      return cached.result;
    }
    final future = prView(sessionId);
    _openedPr[sessionId] = (at: DateTime.now(), result: future);
    return future;
  }

  /// `gh pr view <url> --json …` of the session's PR (null = no PR).
  Future<PrStatus?> prView(String sessionId) async {
    final c = await _context(sessionId);
    final url = c.session.prUrl;
    if (url == null) return null;
    await _requireGithubRequest(url, c.workspace);
    final ProcessResult r;
    try {
      r = await _run('gh', [
        'pr',
        'view',
        url,
        '--json',
        prViewFields,
      ], workingDirectory: c.workspace.path);
    } on ProcessException catch (e) {
      throw ReviewException('Falha ao executar gh: ${e.message}');
    }
    if (r.exitCode != 0) {
      throw ReviewException('gh pr view falhou: ${'${r.stderr}'.trim()}');
    }
    final status = parsePrView('${r.stdout}');
    if (status == null) throw const ReviewException('Resposta inválida do PR.');
    final inline = await inlineComments(sessionId);
    final all = [...status.comments, ...inline]
      ..sort((a, b) => a.at.compareTo(b.at));
    if (c.spec case final spec?) {
      final repo = _ref.read(reviewCommentsRepoProvider);
      final rows = await repo.bySpec(spec.id);
      final round = rows.isEmpty ? 1 : rows.map((r) => r.round).reduce(max) + 1;
      for (final comment in all) {
        if (comment.externalId == null) continue;
        await repo.insertExternal(
          ReviewCommentsCompanion.insert(
            specId: spec.id,
            round: round,
            author: 'pr',
            body: '@${comment.author}: ${comment.body}',
            externalId: Value(comment.externalId),
            path: Value(comment.path),
            line: Value(comment.line),
            commitSha: Value(comment.commitSha),
            createdAt: Value(comment.at),
          ),
        );
      }
    }
    return PrStatus(
      state: status.state,
      mergeable: status.mergeable,
      reviewDecision: status.reviewDecision,
      checks: status.checks,
      comments: all,
    );
  }

  Future<List<PrComment>> inlineComments(String sessionId) async {
    final c = await _context(sessionId);
    final uri = Uri.tryParse(c.session.prUrl ?? '');
    final parts = uri?.pathSegments ?? [];
    await _requireGithubRequest(c.session.prUrl ?? '', c.workspace);
    if (uri == null ||
        parts.length != 4 ||
        parts[2] != 'pull' ||
        int.tryParse(parts[3]) == null) {
      throw const ReviewException('não foi possível ler a URL do PR');
    }
    final r = await _run('gh', [
      'api',
      '--hostname',
      uri.host,
      'repos/${parts[0]}/${parts[1]}/pulls/${parts[3]}/comments',
      '--paginate',
      '--slurp',
    ], workingDirectory: c.workspace.path);
    if (r.exitCode != 0) {
      throw ReviewException('Comentários do PR: ${r.stderr}');
    }
    final decoded = jsonDecode('${r.stdout}');
    if (decoded is! List) {
      throw const ReviewException('Comentários do PR inválidos');
    }
    final rows = <Map>[
      for (final page in decoded)
        if (page is List) ...page.whereType<Map>() else if (page is Map) page,
    ];
    final replies = <String, List<Map>>{};
    for (final row in rows) {
      if (row['in_reply_to_id'] != null) {
        replies.putIfAbsent('${row['in_reply_to_id']}', () => []).add(row);
      }
    }
    String author(Map row) =>
        row['user'] is Map ? '${row['user']['login'] ?? '?'}' : '?';
    return [
      for (final row in rows)
        if (row['in_reply_to_id'] == null)
          PrComment(
            author: author(row),
            externalId: 'github:${row['id']}',
            path: row['path'] as String?,
            line: (row['line'] as num? ?? row['original_line'] as num?)
                ?.toInt(),
            commitSha: row['commit_id'] as String?,
            body: [
              '${row['body'] ?? ''}',
              for (final reply in replies['${row['id']}'] ?? <Map>[])
                '@${author(reply)}: ${reply['body'] ?? ''}',
            ].join('\n'),
            at: DateTime.tryParse('${row['created_at']}') ?? DateTime(1970),
          ),
    ];
  }

  /// Pushes the session's branch when it has commits the PR does not.
  Future<bool> pushIfAhead(String sessionId) async {
    final c = await _context(sessionId);
    if (c.session.prUrl == null || !hasWorktree(c.session, c.workspace)) {
      return false;
    }
    final git = _git(c.session.worktreePath);
    if (!await aheadOfUpstream(git)) return false;
    final remote = (await git.git([
      'config',
      '--get',
      'branch.${c.session.branch}.remote',
    ])).trim();
    final destination = reviewRepositoryUrl(
      (await git.git(['remote', 'get-url', '--push', remote])).trim(),
    );
    final saved = Uri.tryParse(c.session.prUrl!);
    final dest = destination == null ? null : Uri.tryParse(destination);
    final repository = saved?.pathSegments.take(2).join('/').toLowerCase();
    if (dest == null ||
        saved?.host != dest.host ||
        dest.path.substring(1).toLowerCase() != repository) {
      throw const ReviewException(
        'O remote mudou e não corresponde ao destino do request salvo. Corrija o upstream antes de enviar commits.',
      );
    }
    await git.git(['push']);
    return true;
  }

  /// "Mergear PR": `gh pr merge --squash|--rebase|--merge --delete-branch`;
  /// then the session / spec close like a local merge (the worktree goes
  /// away; the base branch gets the work with the next `git pull`).
  Future<List<RestackResult>> mergePr(
    String sessionId,
    PrMergeMethod method,
  ) async {
    final c = await _context(sessionId);
    final url = c.session.prUrl;
    if (url == null) throw const ReviewException('A sessão não tem PR.');
    await _requireGithubRequest(url, c.workspace);
    final children = await _prepareChildren(c.workspace, c.session.branch);
    // The PRs of the children move to the mother's base before the merge
    // deletes the mother's branch (a PR whose base is deleted is closed).
    final target = await baseBranchOf(c.session, c.workspace);
    for (final child in children.where((x) => x.prUrl != null)) {
      try {
        await _run('gh', [
          'pr',
          'edit',
          child.prUrl!,
          '--base',
          target,
        ], workingDirectory: c.workspace.path);
      } on ProcessException catch (e) {
        debugPrint('gh pr edit ${child.prUrl} falhou — $e');
      }
    }
    final ProcessResult r;
    try {
      r = await _run('gh', [
        'pr',
        'merge',
        url,
        method.flag,
        '--delete-branch',
      ], workingDirectory: c.workspace.path);
    } on ProcessException catch (e) {
      throw ReviewException('Falha ao executar gh: ${e.message}');
    }
    // gh exits 1 when only the local branch could not be deleted (it is
    // still checked out in the session's worktree): merged all the same.
    if (r.exitCode != 0 && !await _prMerged(url, c.workspace.path)) {
      throw ReviewException(
        'gh pr merge falhou: ${'${r.stderr}'.trim().isEmpty ? '${r.stdout}'.trim() : '${r.stderr}'.trim()}',
      );
    }
    final ws = c.workspace, s = c.session;
    await _ref.read(sessionManagerProvider.notifier).release(s.id);
    try {
      await _git(ws.path).removeWorktree(s.worktreePath, force: true);
    } on GitException catch (e) {
      debugPrint('worktree ${s.worktreePath} não removido — $e');
    }
    if (r.exitCode != 0) {
      try {
        await _git(ws.path).deleteBranch(s.branch, force: true);
      } on GitException catch (e) {
        debugPrint('branch ${s.branch} não removida — $e');
      }
    }
    final sessions = _ref.read(sessionsRepoProvider);
    await sessions.setMerged(s.id, url);
    final spec = c.spec;
    final base = await baseBranchOf(s, ws);
    if (spec != null) {
      await _closeSpec(ws, spec, url, base);
    } else if (c.task != null) {
      await _ref.read(taskActionsProvider).move(c.task!.id, TaskStatus.done);
    }
    if (children.isEmpty) return const [];
    // The merge happened on the host: the local base may be behind.
    return restackChildren(
      ws,
      children,
      newBase: await _fetchedBase(ws, base),
      target: base,
    );
  }

  /// `origin/<base>` after `git fetch origin <base>`, or [base] when there
  /// is no such remote (or the fetch failed).
  Future<String> _fetchedBase(Workspace ws, String base) async {
    try {
      await _git(ws.path).git(['fetch', '-q', 'origin', '--', base]);
      return 'origin/$base';
    } on GitException catch (e) {
      debugPrint('fetch origin $base falhou — $e');
      return base;
    }
  }

  /// Direct children of [motherBranch] (SPEC-032 R6): the latest session of
  /// each spec created on top of it, not merged, with its own worktree.
  Future<List<Session>> stackedChildren(
    Workspace ws,
    String motherBranch,
  ) async {
    final all = await _ref
        .read(sessionsRepoProvider)
        .watchByWorkspace(ws.id)
        .first;
    final latest = <int, Session>{};
    for (final s in all) {
      final id = s.specId;
      if (id == null || s.duelId != null) continue;
      final cur = latest[id];
      if (cur == null || s.startedAt.isAfter(cur.startedAt)) latest[id] = s;
    }
    return [
      for (final s in latest.values)
        if (s.baseBranch == motherBranch &&
            s.branch != motherBranch &&
            s.status != SessionStatus.merged &&
            s.mergeCommit == null &&
            hasWorktree(s, ws))
          s,
    ];
  }

  Future<String> _restackKey(Session s) async {
    final spec = s.specId == null
        ? null
        : await _ref.read(specsRepoProvider).getById(s.specId!);
    return spec?.code ?? s.id;
  }

  /// Children of [motherBranch] with its current tip saved as their old
  /// base (`refs/promptorium/<spec>/base-antiga`), before the merge.
  Future<List<Session>> _prepareChildren(
    Workspace ws,
    String motherBranch,
  ) async {
    try {
      final children = await stackedChildren(ws, motherBranch);
      if (children.isEmpty) return children;
      final main = _git(ws.path);
      final tip = await main.resolveRef('refs/heads/$motherBranch');
      if (tip == null) return children;
      for (final child in children) {
        await main.updateRef(oldBaseRef(await _restackKey(child)), tip);
      }
      return children;
    } catch (e) {
      debugPrint('filhas de $motherBranch não preparadas — $e');
      return const [];
    }
  }

  /// Redoes the base of [children] on [newBase] (SPEC-032 R6, R7): each one
  /// gets `git rebase --onto <newBase> <base-antiga>` in its worktree; a PR
  /// is pushed (`--force-with-lease`) and moved to [target]. Their base
  /// becomes [target] whatever the outcome; a failed one is marked in the
  /// app settings ("Conflito ao refazer a base" / "Base desatualizada").
  Future<List<RestackResult>> restackChildren(
    Workspace ws,
    List<Session> children, {
    required String newBase,
    required String target,
  }) async {
    final out = <RestackResult>[];
    final settings = _ref.read(appSettingsProvider.notifier);
    for (final child in children) {
      final key = await _restackKey(child);
      var files = <String>[];
      String? reason;
      final warnings = <String>[];
      var outcome = RestackOutcome.skipped;
      final now = await _ref.read(sessionsRepoProvider).getById(child.id);
      final old = await _git(ws.path).resolveRef(oldBaseRef(key));
      if (now != null && !now.status.isTerminal) {
        reason = 'a sessão ainda está rodando';
      } else if (old == null) {
        reason = 'a ponta antiga da mãe não foi gravada';
      } else {
        try {
          outcome = await rebaseOnto(
            _git(child.worktreePath),
            newBase: newBase,
            oldBase: old,
            onConflict: (f) => files = f,
            onSkip: (r) => reason = r,
          );
        } on GitException catch (e) {
          reason = '$e';
        }
      }
      if (outcome == RestackOutcome.ok) {
        try {
          await _git(ws.path).git(['update-ref', '-d', oldBaseRef(key)]);
        } on GitException {
          /* stays as a checkpoint */
        }
        final url = child.prUrl;
        if (url != null) {
          try {
            await _git(child.worktreePath).git(['push', '--force-with-lease']);
          } on GitException catch (e) {
            warnings.add('push da $key falhou: $e');
          }
          try {
            final r = await _run('gh', [
              'pr',
              'edit',
              url,
              '--base',
              target,
            ], workingDirectory: ws.path);
            if (r.exitCode != 0) {
              warnings.add('base do PR da $key não trocada: ${r.stderr}');
            }
          } on ProcessException catch (e) {
            warnings.add('gh pr edit falhou: ${e.message}');
          }
        }
      }
      // The mother is in the base: the child merges there from now on.
      if (child.specId != null) {
        await _ref
            .read(specsRepoProvider)
            .update(child.specId!, SpecsCompanion(baseBranch: Value(target)));
        await _ref
            .read(sessionsRepoProvider)
            .setSpecBaseBranch(child.specId!, target);
      }
      final result = RestackResult(
        sessionId: child.id,
        label: key,
        outcome: outcome,
        files: files,
        reason: reason,
        warnings: warnings,
      );
      final mark = restackMark(result);
      if (mark == null) {
        await settings.remove(restackMarkKey(child.id));
      } else {
        await settings.set(restackMarkKey(child.id), mark);
      }
      if (outcome == RestackOutcome.conflict) {
        // SPEC-043 R6: the conflicting rebase may start the resolution.
        unawaited(_ref.read(conflictResolverProvider).autoStart(child.id));
      }
      out.add(result);
    }
    return out;
  }

  /// The branch the queue merges into (`branch-base:` of the project, else
  /// `main` or `master`) and the root's state against it (SPEC-032 R11).
  Future<RootStatus?> rootStatus(Workspace ws) async {
    final main = _git(ws.path);
    final config = await _ref.read(projectConfigProvider(ws.path).future);
    String? base;
    for (final b in [?config.baseBranch, 'main', 'master']) {
      if (await main.resolveRef('refs/heads/$b') != null) {
        base = b;
        break;
      }
    }
    if (base == null) return null;
    return RootStatus(
      base: base,
      branch: await main.currentBranch(),
      dirty: [
        for (final e in await main.status())
          if (!e.isUntracked && e.path != ProjectMemory.filePath) e.path,
      ],
    );
  }

  /// "Voltar para a main" (R11): `git switch <base>` in the root, only with
  /// no tracked changes.
  Future<void> switchRoot(Workspace ws, String base) async {
    final status = await rootStatus(ws);
    if (status != null && status.dirty.isNotEmpty) {
      throw const ReviewException(
        'A raiz tem alterações não commitadas: guarde-as antes de trocar.',
      );
    }
    try {
      await _git(ws.path).git(['switch', '--', _safeRef(base, 'Branch')]);
    } on GitException catch (e) {
      throw ReviewException('Não foi possível voltar para $base: $e');
    }
  }

  /// "Guardar alterações" (R11): `git stash push -m promptorium` in the root
  /// (tracked files; untracked ones stay).
  Future<void> stashRoot(Workspace ws) async {
    try {
      await _git(ws.path).git(['stash', 'push', '-m', 'promptorium']);
    } on GitException catch (e) {
      throw ReviewException('Não foi possível guardar as alterações: $e');
    }
  }

  /// "Mergear a pilha" (R13): merges [sessionIds] (a stack, base first) one
  /// by one — each merge redoes the base of the next (R6). Stops at the
  /// first one that cannot go in (a refused merge, a conflict, or a base
  /// that could not be redone) and says where.
  Future<StackMergeResult> mergeStack(
    List<String> sessionIds, {
    MergeOptions options = const MergeOptions(),
    PrMergeMethod prMethod = PrMergeMethod.squash,
  }) async {
    final merged = <String>[];
    final restacked = <RestackResult>[];
    for (final (i, id) in sessionIds.indexed) {
      try {
        final c = await _context(id);
        final List<RestackResult> r;
        if (c.session.prUrl != null) {
          r = await mergePr(id, prMethod);
        } else {
          r = (await merge(id, options: options)).restacked;
        }
        merged.add(id);
        restacked.addAll(r);
        final next = i + 1 < sessionIds.length ? sessionIds[i + 1] : null;
        final failed = r
            .where((x) => x.sessionId == next && x.outcome != RestackOutcome.ok)
            .firstOrNull;
        if (failed != null) {
          return StackMergeResult(
            merged: merged,
            stoppedAt: next,
            reason: restackNotice([failed]),
            restacked: restacked,
          );
        }
      } on ReviewException catch (e) {
        return StackMergeResult(
          merged: merged,
          stoppedAt: id,
          reason: e.message,
          restacked: restacked,
        );
      }
    }
    return StackMergeResult(merged: merged, restacked: restacked);
  }

  /// Upstream of the manual rebase of [s]: the saved old base of the
  /// mother (R6) or, without it, the fork point with [base].
  Future<String> _rebaseUpstream(Session s, Workspace ws, String base) async {
    final saved = await _git(ws.path)
        .resolveRef(oldBaseRef(await _restackKey(s)));
    if (saved != null) return saved;
    return (await _git(s.worktreePath).git(['merge-base', 'HEAD', base]))
        .trim();
  }

  /// "Começar rebase" (SPEC-032 R17): `git rebase --onto <base> <upstream>`
  /// in the spec's worktree, left stopped on the conflicts. The root never
  /// changes branch.
  Future<RebaseStatus> startRebase(String sessionId) async {
    final c = await _context(sessionId);
    if (!hasWorktree(c.session, c.workspace)) {
      throw const ReviewException('A sessão não tem worktree próprio.');
    }
    final wt = _git(c.session.worktreePath);
    final dirty = (await wt.status()).where((e) => !e.isUntracked).toList();
    if (dirty.isNotEmpty) {
      throw ReviewException(
        'O worktree tem ${dirty.length} alteração(ões) não commitada(s): '
        'faça commit antes de começar o rebase.',
      );
    }
    final base = await baseBranchOf(c.session, c.workspace);
    final upstream = await _rebaseUpstream(c.session, c.workspace, base);
    try {
      await wt.git(['rebase', '--onto', base, upstream]);
    } on GitException catch (e) {
      final status = await rebaseStatus(sessionId);
      if (!status.inProgress) {
        throw ReviewException('O rebase não começou: $e');
      }
      return status;
    }
    await _ref
        .read(appSettingsProvider.notifier)
        .remove(restackMarkKey(sessionId));
    return const RebaseStatus();
  }

  /// State of the rebase in the spec's worktree (R17): `rebase-merge/msgnum`
  /// and `end`, and the markers left in each conflicted file.
  Future<RebaseStatus> rebaseStatus(String sessionId) async {
    final c = await _context(sessionId);
    if (!hasWorktree(c.session, c.workspace)) return const RebaseStatus();
    final root = c.session.worktreePath;
    final wt = _git(root);
    var dir = (await wt.git(['rev-parse', '--git-path', 'rebase-merge']))
        .trim();
    if (!dir.startsWith('/')) dir = '$root/$dir';
    if (!Directory(dir).existsSync()) return const RebaseStatus();
    int read(String name) =>
        int.tryParse(
          File('$dir/$name').existsSync()
              ? File('$dir/$name').readAsStringSync().trim()
              : '',
        ) ??
        0;
    final files = <String, int>{};
    for (final path in (await wt.git([
      'diff',
      '--name-only',
      '--diff-filter=U',
    ])).split('\n').where((l) => l.trim().isNotEmpty)) {
      final f = File('$root/$path');
      files[path] = f.existsSync() ? countMarkers(f.readAsStringSync()) : 0;
    }
    return RebaseStatus(
      inProgress: true,
      step: read('msgnum'),
      total: read('end'),
      files: files,
    );
  }

  /// "Continuar rebase" (R17): only with no markers left. Stages the
  /// conflicted files and runs `git rebase --continue` (no editor); it may
  /// stop again on the next commit.
  Future<RebaseStatus> continueRebase(String sessionId) async {
    final status = await rebaseStatus(sessionId);
    if (!status.inProgress) return status;
    if (!status.canContinue) {
      throw const ReviewException(
        'Ainda há marcadores de conflito: resolva todos os trechos antes de '
        'continuar.',
      );
    }
    final c = await _context(sessionId);
    final wt = _git(c.session.worktreePath);
    if (status.files.isNotEmpty) {
      await wt.git(['add', '--', ...status.files.keys]);
    }
    try {
      await wt.git(['-c', 'core.editor=true', 'rebase', '--continue']);
    } on GitException catch (e) {
      final next = await rebaseStatus(sessionId);
      if (!next.inProgress) throw ReviewException('$e');
      return next;
    }
    return rebaseStatus(sessionId);
  }

  /// "Desistir e voltar como estava" (R17): `git rebase --abort`.
  Future<void> abortRebase(String sessionId) async {
    final c = await _context(sessionId);
    try {
      await _git(c.session.worktreePath).git(['rebase', '--abort']);
    } on GitException catch (e) {
      throw ReviewException('Não foi possível desfazer o rebase: $e');
    }
  }

  /// The stretches in conflict (R17): from the files of a rebase in
  /// progress, or else from `git merge-tree <base> <branch>`.
  Future<List<ConflictHunk>> conflictHunks(String sessionId) async {
    final c = await _context(sessionId);
    final status = await rebaseStatus(sessionId);
    if (status.inProgress) {
      return [
        for (final path in status.files.keys)
          if (File('${c.session.worktreePath}/$path').existsSync())
            ...parseConflictHunks(
              path,
              File('${c.session.worktreePath}/$path').readAsStringSync(),
            ),
      ];
    }
    final main = _git(c.workspace.path);
    final base = await baseBranchOf(c.session, c.workspace);
    try {
      await main.git([
        'merge-tree',
        '--write-tree',
        '--name-only',
        base,
        c.session.branch,
      ]);
      return const [];
    } on GitException catch (e) {
      if (e.exitCode != 1) rethrow;
      final lines = e.stdout.split('\n');
      final tree = lines.first.trim();
      final out = <ConflictHunk>[];
      for (final path in lines.skip(1).takeWhile((l) => l.isNotEmpty)) {
        try {
          final text = await main.git(['cat-file', '-p', '$tree:$path']);
          out.addAll(parseConflictHunks(path, text));
        } on GitException {
          /* binary or deleted on one side */
        }
      }
      return out;
    }
  }

  /// "Passar para o agente" during a manual rebase (R17).
  Future<void> handRebaseToAgent(String sessionId) async {
    final c = await _context(sessionId);
    final base = await baseBranchOf(c.session, c.workspace);
    final status = await rebaseStatus(sessionId);
    final message =
        '${restackMessage(branch: c.session.branch, base: base, files: status.files.keys.toList())}'
        '${status.inProgress ? ' O rebase já está em andamento no worktree (commit ${status.step} de ${status.total}): continue de onde parou, sem recomeçar.' : ''}';
    // SPEC-043 R1: during a rebase the branch still points to its old tip.
    final resolver = _ref.read(conflictResolverProvider);
    await resolver.begin(
      session: c.session,
      ws: c.workspace,
      spec: c.spec,
      base: base,
      files: status.files.keys.toList(),
    );
    try {
      await _ref.read(sessionManagerProvider.notifier).send(sessionId, message);
    } on SessionException catch (e) {
      await resolver.cancel(sessionId);
      throw ReviewException('$e');
    }
  }

  /// The spec's tests (`testes:` of the project) in its worktree, after a
  /// manual rebase (R17). Null = no test command.
  Future<(bool, String)?> runSpecTests(String sessionId) async {
    final c = await _context(sessionId);
    final config = await _ref.read(
      projectConfigProvider(c.workspace.path).future,
    );
    final cmd = config.testCommand;
    if (cmd == null) return null;
    try {
      final r = await _run('bash', [
        '-lc',
        cmd,
      ], workingDirectory: c.session.worktreePath);
      final out = '${r.stdout}${r.stderr}'.trim().split('\n');
      return (
        r.exitCode == 0,
        out.skip(out.length > 8 ? out.length - 8 : 0).join('\n'),
      );
    } on ProcessException catch (e) {
      return (false, e.message);
    }
  }

  /// SPEC-032 R15: children whose mother entered the base outside the app
  /// (PR `MERGED` on the host, or its branch gone locally and on the
  /// remote) get their base redone on `origin/<base>`. While the mother's
  /// branch exists, its tip is saved as the children's old base. Errors
  /// leave everything as it was.
  Future<List<RestackResult>> restackOrphans(Workspace ws) async {
    try {
      final specs = await _ref
          .read(specsRepoProvider)
          .watchByWorkspace(ws.id)
          .first;
      final out = <RestackResult>[];
      for (final mother in specs) {
        final branch = mother.branch;
        if (branch == null || mother.stage == SpecStage.done) continue;
        final children = await stackedChildren(ws, branch);
        if (children.isEmpty) continue;
        final main = _git(ws.path);
        final tip = await main.resolveRef('refs/heads/$branch');
        if (tip != null) {
          for (final child in children) {
            await main.updateRef(oldBaseRef(await _restackKey(child)), tip);
          }
        }
        final sessions = await _ref
            .read(sessionsRepoProvider)
            .bySpec(mother.id);
        final latest = sessions.isEmpty
            ? null
            : sessions.reduce(
                (a, b) => b.startedAt.isAfter(a.startedAt) ? b : a,
              );
        final url = latest?.prUrl;
        var merged = false;
        if (url != null) {
          merged = await _prMerged(url, ws.path);
        } else if (tip == null) {
          merged = await _goneFromRemote(main, branch);
        }
        if (!merged) continue;
        final base =
            latest?.baseBranch ??
            mother.baseBranch ??
            await main.currentBranch() ??
            'main';
        out.addAll(
          await restackChildren(
            ws,
            children,
            newBase: await _fetchedBase(ws, base),
            target: base,
          ),
        );
      }
      return out;
    } catch (e) {
      debugPrint('refazer bases da Review: $e');
      return const [];
    }
  }

  /// [branch] is not on `origin` (there must be an `origin`).
  Future<bool> _goneFromRemote(GitService main, String branch) async {
    try {
      final out = await main.git([
        'ls-remote',
        '--heads',
        'origin',
        'refs/heads/$branch',
      ]);
      return out.trim().isEmpty;
    } on GitException {
      return false;
    }
  }

  /// "Refazer agora" (SPEC-032 R15): redoes the base of [sessionId] on its
  /// base branch, from the saved old base or, without it, `git merge-base`.
  Future<RestackResult> restackNow(String sessionId) async {
    final c = await _context(sessionId);
    final base = await baseBranchOf(c.session, c.workspace);
    final key = await _restackKey(c.session);
    final main = _git(c.workspace.path);
    if (await main.resolveRef(oldBaseRef(key)) == null) {
      final fork = (await _git(
        c.session.worktreePath,
      ).git(['merge-base', 'HEAD', base])).trim();
      await main.updateRef(oldBaseRef(key), fork);
    }
    final r = await restackChildren(
      c.workspace,
      [c.session],
      newBase: base,
      target: base,
    );
    return r.single;
  }

  /// Whether `gh pr view` reports [url] as merged.
  Future<bool> _prMerged(String url, String cwd) async {
    try {
      final r = await _run('gh', [
        'pr',
        'view',
        url,
        '--json',
        'state',
      ], workingDirectory: cwd);
      if (r.exitCode != 0) return false;
      final j = jsonDecode('${r.stdout}');
      return j is Map && j['state'] == 'MERGED';
    } on Object {
      return false;
    }
  }

  /// "Resolver conflito": the session gets the instructions to merge the
  /// base into its branch and resolve. The tip of the branch is saved
  /// first and the gate checks the result when the agent finishes
  /// (SPEC-043 R1). Returns the files in conflict.
  Future<List<String>> resolveConflict(
    String sessionId, {
    String origin = ResolutionOrigin.person,
  }) async {
    final c = await _context(sessionId);
    final base = await baseBranchOf(c.session, c.workspace);
    final settings = _ref.read(appSettingsProvider.notifier);
    final mark = settings.get(restackMarkKey(sessionId));
    var message = conflictMessage(base);
    List<String> files;
    if (mark != null && mark.startsWith('conflito')) {
      // SPEC-032 R7: the base redone after the mother's merge conflicted.
      files = mark.split('\n').skip(1).where((l) => l.isNotEmpty).toList();
      final old = await _git(c.workspace.path)
          .resolveRef(oldBaseRef(await _restackKey(c.session)));
      message = restackMessage(
        branch: c.session.branch,
        base: base,
        oldBase: old,
        files: files,
      );
    } else {
      final prediction = await predictConflict(sessionId);
      files = prediction.files;
    }
    // SPEC-048: the commits of the resolution say where they came from.
    final label =
        c.spec?.code ?? sessionOrigin(c.session.title ?? c.session.branch);
    final restack = mark != null && mark.startsWith('conflito');
    final resolver = _ref.read(conflictResolverProvider);
    await resolver.begin(
      session: c.session,
      ws: c.workspace,
      spec: c.spec,
      base: base,
      files: files,
      origin: origin,
      restackMark: mark != null && mark.startsWith('conflito') ? mark : null,
    );
    try {
      final manager = _ref.read(sessionManagerProvider.notifier);
      await manager.setAgentOrigin(
        sessionId,
        restack ? restackOrigin(label) : conflictOrigin(label),
      );
      await manager.send(sessionId, message);
    } on SessionException catch (e) {
      await resolver.cancel(sessionId);
      throw ReviewException('$e');
    }
    await settings.remove(restackMarkKey(sessionId));
    if (c.task != null) {
      await _ref.read(taskActionsProvider).move(c.task!.id, TaskStatus.running);
    }
    return files;
  }

  /// Criteria of [spec] not checked yet (text). A criterion counts as
  /// checked when it is `- [x]` in the file or marked in the Review.
  Future<List<String>> pendingCriteria(Spec spec, Workspace ws) async {
    final text = await _ref.read(specServiceProvider).read(ws, spec);
    if (text == null) {
      throw const ReviewException('Não foi possível ler os critérios da spec.');
    }
    final marks = {
      for (final m
          in await _ref.read(reviewCommentsRepoProvider).criteria(spec.id))
        m.criterion: m.checked,
    };
    return [
      for (final c in parseCriteria(text))
        if (!(marks[c.text] ?? c.checkedInFile)) c.text,
    ];
  }

  /// Commits of the spec's branch by step (`SPEC-003 R2: …` → R2), oldest
  /// first: the "Etapa" filter of the Review.
  Future<Map<String, List<GitLogEntry>>> stepCommits(String sessionId) async {
    final c = await _context(sessionId);
    final spec = c.spec;
    if (spec == null || !hasWorktree(c.session, c.workspace)) return const {};
    final git = _git(c.session.worktreePath);
    try {
      final base = await baseBranchOf(c.session, c.workspace);
      final out = await git.git([
        'log',
        '--reverse',
        '--format=%H%x1f%h%x1f%an%x1f%aI%x1f%s%x1e',
        '$base..HEAD',
      ]);
      return commitsByStep(spec.code, [
        for (final rec in out.split('\x1e'))
          if (rec.trim().isNotEmpty) _logEntry(rec.trim()),
      ]);
    } on GitException catch (e) {
      debugPrint('review $sessionId: commits por etapa — $e');
      return const {};
    }
  }

  static GitLogEntry _logEntry(String rec) {
    final f = rec.split('\x1f');
    return GitLogEntry(
      sha: f[0],
      shortSha: f.length > 1 ? f[1] : '',
      author: f.length > 2 ? f[2] : '',
      date: DateTime.tryParse(f.length > 3 ? f[3] : '') ?? DateTime(1970),
      subject: f.length > 4 ? f[4] : '',
    );
  }

  /// Diff of the commits of one step (each commit's own diff, in order).
  Future<ReviewDetail> loadStep(String sessionId, String step) async {
    final c = await _context(sessionId);
    final commits = (await stepCommits(sessionId))[step] ?? const [];
    final git = _git(c.session.worktreePath);
    final files = <DiffFile>[];
    try {
      for (final commit in commits) {
        files.addAll(
          DiffParser.parse(
            await git.git([
              'show',
              '--format=',
              '--no-color',
              '--no-ext-diff',
              '--unified=3',
              '-M',
              commit.sha,
            ]),
          ),
        );
      }
    } on GitException catch (e) {
      return ReviewDetail(session: c.session, task: c.task, error: '$e');
    }
    return ReviewDetail(
      session: c.session,
      task: c.task,
      baseBranch: await baseBranchOf(c.session, c.workspace),
      files: files,
      commitsAhead: commits.length,
      error: commits.isEmpty ? 'Nenhum commit de $step nesta branch.' : null,
    );
  }

  /// `gh pr checks` of the session's PR: `(nome, estado)` per check; empty
  /// without a PR or `gh`.
  Future<List<(String, String)>> prChecks(String sessionId) async {
    final c = await _context(sessionId);
    final url = c.session.prUrl;
    if (url == null) return const [];
    await _requireGithubRequest(url, c.workspace);
    try {
      final r = await _run('gh', [
        'pr',
        'checks',
        url,
      ], workingDirectory: c.workspace.path);
      return parsePrChecks('${r.stdout}');
    } on ProcessException {
      return const [];
    }
  }

  Future<Spec?> stackedOnOf(Workspace ws, String base, int? specId) async =>
      (await _ref.read(specsRepoProvider).watchByWorkspace(ws.id).first)
          .where(
            (o) =>
                o.id != specId && o.branch == base && o.stage != SpecStage.done,
          )
          .firstOrNull;

  Future<String?> rootProblem(
    GitService main,
    String base, {
    String? ignoredPath,
  }) async {
    final current = await main.currentBranch();
    if (current != base) {
      return 'O repositório principal está em '
          '"${current ?? 'HEAD destacado'}", mas o merge vai para "$base". '
          'Troque para "$base" (git switch $base) e tente de novo.';
    }
    final dirty = (await main.status())
        .where(
          (e) =>
              !e.isUntracked &&
              e.path != ProjectMemory.filePath &&
              e.path != ignoredPath,
        )
        .toList();
    if (dirty.isNotEmpty) {
      return 'O repositório principal tem alterações não '
          'commitadas (${dirty.length} arquivo(s): '
          '${dirty.take(3).map((e) => e.path).join(', ')}'
          '${dirty.length > 3 ? '…' : ''}). Faça commit ou stash antes do merge.';
    }
    return null;
  }

  /// Watches only tracked/untracked file parents and git refs of the selected
  /// item. Object writes from merge-tree are intentionally outside this set.
  Future<DirWatcher?> watchRepositories(
    String sessionId,
    VoidCallback changed,
  ) async {
    try {
      final c = await _context(sessionId);
      final dirs = <String>{};
      for (final root in {c.workspace.path, c.session.worktreePath}) {
        final git = _git(root);
        dirs.addAll([root, '$root/.promptorium']);
        final files = await git.git([
          'ls-files',
          '--cached',
          '--others',
          '--exclude-standard',
          '-z',
        ]);
        for (final path in files.split('\x00').where((p) => p.isNotEmpty)) {
          dirs.add(File('$root/$path').parent.path);
        }
        final gitDir = (await git.git(['rev-parse', '--absolute-git-dir']))
            .trim();
        dirs.addAll([gitDir, '$gitDir/refs', '$gitDir/refs/heads']);
      }
      return DirWatcher(
        dirs,
        onChange: (paths) {
          if (paths.every((p) => p.endsWith('.lock'))) return;
          changed();
        },
      );
    } catch (e) {
      debugPrint(
        'Review $sessionId: observação do repositório indisponível — $e',
      );
      return null;
    }
  }

  Future<ReadinessInputs> readinessInputs(String sessionId) async {
    final c = await _context(sessionId);
    final unknown = <String, String>{};
    List<String> pending = [], failed = [];
    var open = 0, uncommitted = 0;
    var reviewerFailed = false;
    String? root, stacked, worktree, pr;
    final spec = c.spec;
    if (spec != null) {
      try {
        pending = await pendingCriteria(spec, c.workspace);
      } catch (e) {
        unknown['criterios'] = '$e';
      }
      try {
        final rows = await _ref
            .read(reviewCommentsRepoProvider)
            .bySpec(spec.id);
        open = rows.where(isOpenReviewComment).length;
        final last = rows.where((r) => r.author == 'revisor').lastOrNull;
        reviewerFailed =
            last != null &&
            !last.resolved &&
            last.body.startsWith(AutoReviewer.failurePrefix);
      } catch (e) {
        unknown['comentarios'] = '$e';
      }
      try {
        final rows = await _ref
            .read(specStepsRepoProvider)
            .watchBySpec(spec.id)
            .first;
        failed = stepsOf(
          spec,
          rows,
        ).where((s) => s.gate != null && !s.gate!.ok).map((s) => s.id).toList();
      } catch (e) {
        unknown['verificacoes'] = '$e';
      }
    }
    try {
      final base = await baseBranchOf(c.session, c.workspace);
      stacked = (await stackedOnOf(c.workspace, base, spec?.id))?.code;
      root = await rootProblem(_git(c.workspace.path), base);
      if (!hasWorktree(c.session, c.workspace)) {
        worktree = 'Sem worktree próprio';
      } else {
        worktree = mergeGuard(
          branch: c.session.branch,
          base: base,
          worktreePath: c.session.worktreePath,
          workspacePath: c.workspace.path,
          worktreesBase: _git(c.workspace.path).worktreesBase,
        );
      }
      if (c.session.status == SessionStatus.merged) {
        worktree = 'Sessão já mergeada';
      }
      if (worktree == null) {
        uncommitted = (await _git(c.session.worktreePath).status()).length;
      }
    } catch (e) {
      for (final id in ['raiz', 'empilhada', 'worktree']) {
        unknown[id] = '$e';
      }
    }
    if (c.session.prUrl != null) {
      try {
        final status = await prView(sessionId);
        if (status == null) {
          unknown['pr'] = 'Não foi possível ler o PR';
        } else if (status.conflicting ||
            status.reviewDecision == 'CHANGES_REQUESTED' ||
            status.checks.any(
              (c) => !['SUCCESS', 'NEUTRAL', 'SKIPPED'].contains(c.$2),
            )) {
          pr = status.summary;
        }
      } catch (e) {
        unknown['pr'] = '$e';
      }
    }
    String? resolution;
    var hasResolution = false;
    final r = _ref.read(conflictResolverProvider).get(sessionId);
    if (r != null && c.session.status != SessionStatus.merged) {
      hasResolution = true;
      try {
        final base = await baseBranchOf(c.session, c.workspace);
        final tip = await _git(c.workspace.path).resolveRef('refs/heads/$base');
        var contains = true;
        if (r.state == ResolutionState.aprovada &&
            tip != null &&
            r.checkedSha != null) {
          try {
            await _git(c.workspace.path)
                .git(['merge-base', '--is-ancestor', tip, r.checkedSha!]);
          } on GitException {
            contains = false;
          }
        }
        final head = hasWorktree(c.session, c.workspace)
            ? await _git(c.session.worktreePath).headSha()
            : null;
        final problem = resolutionProblem(
          r,
          head: head,
          baseTip: tip,
          containsBase: contains,
        );
        if (problem != null) resolution = '${problem.$1} · ${problem.$2}';
        // R7: the card shows the approved resolution as outdated.
        if (!contains) {
          await _ref.read(conflictResolverProvider).markOutdated(sessionId);
        }
      } catch (e) {
        unknown['resolucao'] = '$e';
      }
    }
    return ReadinessInputs(
      hasResolution: hasResolution,
      resolutionProblem: resolution,
      hasSpec: spec != null,
      reviewing:
          spec?.reviewPhase == ReviewPhase.auto &&
          spec?.stage == SpecStage.review,
      reviewerFailed: reviewerFailed,
      pendingCriteria: pending,
      failedGates: failed,
      openComments: open,
      rootProblem: root,
      stackedOn: stacked,
      worktreeProblem: worktree,
      uncommitted: uncommitted,
      prProblem: pr,
      unknown: unknown,
    );
  }

  /// "Fazer merge" (in the **workspace root**):
  /// 1. the root must be on the base branch with no tracked changes
  ///    (untracked files do not block);
  /// 2. stops the session process ([SessionManager.release]);
  /// 3. commits pending changes in the worktree;
  /// 4. `git merge --no-ff <branch>` into the base; on conflict
  ///    `git merge --abort` and the pending commit of step 3 is undone
  ///    (`reset HEAD~1`) — everything stays as before;
  /// 5. removes the worktree, deletes the branch ([deleteBranch]), marks the
  ///    session `merged` (+ hash) and the task "Feito".
  Future<ConflictPrediction> predictConflict(String sessionId) async {
    final c = await _context(sessionId);
    return predictMergeConflict(
      _git(c.workspace.path),
      await baseBranchOf(c.session, c.workspace),
      c.session.branch,
    );
  }

  Future<MergeResult> merge(
    String sessionId, {
    bool deleteBranch = true,
    String? override,
    MergeOptions options = const MergeOptions(),
  }) async {
    final c = await _context(sessionId);
    final main = _git(c.workspace.path);
    final base = await baseBranchOf(c.session, c.workspace);
    final previous = await main.currentBranch();
    final previousSha = await main.headSha();
    String? stash;
    var switched = false;
    final warnings = <String>[];
    Future<String?> stashHead() async {
      try {
        return (await main.git(['rev-parse', '-q', '--verify', 'refs/stash']))
            .trim();
      } on GitException {
        return null;
      }
    }

    Future<void> restore() async {
      if (switched && options.restoreBranch) {
        try {
          await main.git(
            previous == null
                ? ['switch', '--detach', previousSha!]
                : ['switch', '--', previous],
          );
        } on GitException catch (e) {
          warnings.add(
            'Não foi possível voltar à branch anterior: $e. '
            'Branch atual: ${await main.currentBranch()}; stash: ${stash ?? 'nenhum'}',
          );
          return;
        }
      }
      if (stash != null) {
        if (await main.currentBranch() != previous) {
          warnings.add('Stash $stash mantido: a raiz está em outra branch');
          return;
        }
        try {
          try {
            await main.git(['stash', 'apply', '--index', stash!]);
          } on GitException {
            await main.stashApply(stash!);
            warnings.add(
              'Stash restaurado sem preservar a separação staged/não staged',
            );
          }
          final entries = (await main.git(['stash', 'list', '--format=%H']))
              .split('\n');
          final index = entries.indexOf(stash!);
          if (index >= 0) await main.git(['stash', 'drop', 'stash@{$index}']);
        } on GitException catch (e) {
          warnings.add('Stash $stash mantido; restauração falhou: $e');
        }
      }
    }

    try {
      if (options.switchBase || options.stash) {
        for (final marker in [
          'MERGE_HEAD',
          'CHERRY_PICK_HEAD',
          'REVERT_HEAD',
          'rebase-merge',
          'rebase-apply',
        ]) {
          final path = (await main.git(['rev-parse', '--git-path', marker]))
              .trim();
          final absolute = path.startsWith('/')
              ? path
              : '${c.workspace.path}/$path';
          if (await FileSystemEntity.type(absolute) !=
              FileSystemEntityType.notFound) {
            throw ReviewException('Operação git em andamento: $marker');
          }
        }
      }
      if (options.method == MergeMethod.rebase) {
        var published = c.session.prUrl != null;
        try {
          await _git(c.session.worktreePath)
              .git(['rev-parse', '--verify', '@{u}']);
          published = true;
        } on GitException {
          /* no upstream */
        }
        if (published) {
          throw const ReviewException(
            'Rebase indisponível: branch publicada (PR ou upstream).',
          );
        }
      }
      if (options.stash) {
        final before = await stashHead();
        await main.git([
          'stash',
          'push',
          '-m',
          'promptorium-merge-$sessionId',
          '--',
          '.',
          ':(exclude)${ProjectMemory.filePath}',
          if (c.spec != null) ':(exclude)${c.spec!.path}',
        ]);
        final after = await stashHead();
        if (after != before) stash = after;
      }
      if (options.switchBase && previous != base) {
        await main.git(['switch', '--', base]);
        switched = true;
      }
      final children = await _prepareChildren(c.workspace, c.session.branch);
      // The PRs of the children move to the mother's base before the merge
      // deletes the mother's branch (a PR whose base is deleted is closed).
      final target = await baseBranchOf(c.session, c.workspace);
      for (final child in children.where((x) => x.prUrl != null)) {
        try {
          await _run('gh', [
            'pr',
            'edit',
            child.prUrl!,
            '--base',
            target,
          ], workingDirectory: c.workspace.path);
        } on ProcessException catch (e) {
          debugPrint('gh pr edit ${child.prUrl} falhou — $e');
        }
      }
      final result = await _mergeLocal(
        sessionId,
        deleteBranch: deleteBranch,
        override: override,
        options: options,
      );
      await restore();
      final restacked = children.isEmpty
          ? const <RestackResult>[]
          : await restackChildren(
              c.workspace,
              children,
              newBase: base,
              target: base,
            );
      return MergeResult(
        commit: result.commit,
        warnings: [...result.warnings, ...warnings],
        restacked: restacked,
      );
    } catch (e) {
      await restore();
      if (warnings.isNotEmpty) {
        final message = '$e\n${warnings.join('\n')}';
        // Still a conflict: the error keeps "Resolver com o agente".
        if (e is MergeConflictException) {
          throw MergeConflictException(message, e.files);
        }
        throw ReviewException(message);
      }
      rethrow;
    }
  }

  /// What the merge dialog offers: the root's branch, its tracked changes
  /// that "stash" would keep (not the project memory nor the spec file) and
  /// whether the branch is published (PR or upstream: no rebase).
  Future<MergeFacts> mergeFacts(String sessionId) async {
    final c = await _context(sessionId);
    final main = _git(c.workspace.path);
    var published = c.session.prUrl != null;
    if (!published) {
      try {
        await _git(c.session.worktreePath)
            .git(['rev-parse', '--verify', '@{u}']);
        published = true;
      } on GitException {
        /* no upstream */
      }
    }
    return MergeFacts(
      rootBranch: await main.currentBranch(),
      rootChanges: [
        for (final e in await main.status())
          if (!e.isUntracked &&
              e.path != ProjectMemory.filePath &&
              e.path != c.spec?.path)
            e.path,
      ],
      published: published,
    );
  }

  Future<MergeResult> _mergeLocal(
    String sessionId, {
    bool deleteBranch = true,
    String? override,
    MergeOptions options = const MergeOptions(),
  }) async {
    final c = await _context(sessionId);
    final s = c.session, ws = c.workspace, task = c.task;
    var spec = c.spec;
    if (s.status == SessionStatus.merged) {
      throw const ReviewException('O merge desta sessão já foi feito.');
    }
    if (spec != null) {
      final open = await pendingCriteria(spec, ws);
      if (open.isNotEmpty) {
        if (override == null || override.trim().isEmpty) {
          throw ReviewException(
            'Critérios de aceite sem marcar: ${open.join('; ')}. Marque-os '
            'ou use "Mergear mesmo assim" com um motivo.',
          );
        }
        await _ref
            .read(specsRepoProvider)
            .update(
              spec.id,
              SpecsCompanion(mergeOverride: Value(override.trim())),
            );
      } else if (override != null && override.trim().isNotEmpty) {
        // SPEC-043 R5: merged over the conflict resolution's blocker.
        await _ref
            .read(specsRepoProvider)
            .update(
              spec.id,
              SpecsCompanion(mergeOverride: Value(override.trim())),
            );
      }
      if (override != null && override.trim().isNotEmpty) {
        final r = _ref.read(conflictResolverProvider).get(sessionId);
        if (r != null && r.state != ResolutionState.aprovada) {
          await _ref
              .read(conflictResolverProvider)
              .recordOverride(sessionId, override.trim());
        }
      }
    }
    if (!hasWorktree(s, ws)) {
      throw const ReviewException(
        'A sessão não tem worktree próprio (rodou na raiz do workspace).',
      );
    }
    final main = _git(ws.path);
    final wt = _git(s.worktreePath);
    final String base;
    try {
      base = await baseBranchOf(s, ws);
    } on GitException catch (e) {
      throw ReviewException('Falha ao ler a branch base: $e');
    }
    final guard = mergeGuard(
      branch: s.branch,
      base: base,
      worktreePath: s.worktreePath,
      workspacePath: ws.path,
      worktreesBase: main.worktreesBase,
    );
    if (guard != null) throw ReviewException(guard);
    // A spec created on top of another one (dependency still in Review) has
    // that spec's branch as its base: the dependency goes first.
    final stackedOn = await stackedOnOf(ws, base, spec?.id);
    if (stackedOn != null) {
      throw ReviewException(
        '${spec?.code ?? 'Esta spec'} foi criada em cima de ${stackedOn.code} '
        '(branch "$base"), que ainda não foi mergeada. Faça o merge de '
        '${stackedOn.code} primeiro: depois deste, o merge desta vai para a '
        'branch principal.',
      );
    }
    try {
      final problem = await rootProblem(
        main,
        base,
        ignoredPath: options.stash ? spec?.path : null,
      );
      if (problem != null) throw ReviewException(problem);
    } on GitException catch (e) {
      throw ReviewException('Falha ao ler o repositório principal: $e');
    }

    // SPEC-069 R12: a VIBE (or the spec it became) whose number the base
    // already has moves to the next free one before the merge.
    if (spec case final current?) {
      try {
        final moved = await renumberIfTaken(
          repo: _ref.read(specsRepoProvider),
          ws: ws,
          spec: current,
          main: main,
          worktree: wt,
          base: base,
        );
        if (moved != null) {
          spec = await _ref.read(specsRepoProvider).getById(current.id);
        }
      } on Exception catch (e) {
        throw ReviewException('Falha ao renumerar ${current.code}: $e');
      }
    }

    await _ref.read(sessionManagerProvider.notifier).release(s.id);
    // The process was released without recording an exit: if the merge
    // fails, a session that was still live must not stay "running".
    Future<void> markStoppedIfLive() async {
      final now = await _ref.read(sessionsRepoProvider).getById(s.id);
      if (now != null && !now.status.isTerminal) {
        await _ref
            .read(sessionsRepoProvider)
            .setStatus(s.id, SessionStatus.stopped);
      }
    }

    // HEAD before the pending commit: on failure the worktree goes back to
    // exactly this commit (never further — agent commits are kept).
    String? headBefore;
    try {
      headBefore = (await wt.git(['rev-parse', 'HEAD'])).trim();
      if (!await _commitPending(
        wt,
        pendingCommitMessage(s, task, spec),
        skipHooks: options.skipHooks,
        trailer: await _appTrailer(c.workspace, s, spec),
      )) {
        headBefore = null;
      }
    } on GitException catch (e) {
      if (headBefore != null) {
        try {
          await wt.git(['reset', '-q', headBefore]);
        } on GitException {
          /* report original error */
        }
      }
      await markStoppedIfLive();
      throw ReviewException('Falha ao commitar as alterações do worktree: $e');
    }

    final title = reviewTitle(s, task, spec);
    String? preRebase;
    try {
      switch (options.method) {
        case MergeMethod.merge:
          await main.git([
            'merge',
            '--no-ff',
            '-m',
            'Merge ${s.branch}: $title',
            '--',
            s.branch,
          ]);
        case MergeMethod.squash:
          final all = (await wt.git(['log', '--format=%s', '$base..HEAD']))
              .trim()
              .split('\n');
          final subjects = [
            ...all.take(50),
            if (all.length > 50) '…',
          ].join('\n');
          await main.git(['merge', '--squash', '--', s.branch]);
          final staged = await main.git(['diff', '--cached', '--name-only']);
          if (staged.trim().isEmpty) {
            throw const GitException('nada a integrar');
          }
          await main.git(['commit', '-m', title, '-m', subjects]);
        case MergeMethod.rebase:
          preRebase = await wt.headSha();
          await wt.git([
            'update-ref',
            'refs/promptorium/${spec?.code ?? s.id}/pre-rebase',
            preRebase!,
          ]);
          await wt.git(['rebase', base]);
          await main.git(['merge', '--ff-only', '--', s.branch]);
      }
    } on GitException catch (e) {
      var conflicted = <String>[];
      try {
        final source = options.method == MergeMethod.rebase ? wt : main;
        conflicted = (await source.git([
          'diff',
          '--name-only',
          '--diff-filter=U',
        ])).split('\n').where((l) => l.trim().isNotEmpty).toList();
      } on GitException {
        /* best effort */
      }
      if (options.method == MergeMethod.squash) {
        await main.git(['reset', '--merge']);
      }
      if (options.method == MergeMethod.rebase && preRebase != null) {
        try {
          await wt.git(['rebase', '--abort']);
        } on GitException {
          /* completed */
        }
        await wt.git(['reset', '-q', '--hard', preRebase]);
      }
      if (await _merging(main)) {
        try {
          await main.mergeAbort();
        } on GitException catch (a) {
          debugPrint('merge --abort falhou: $a');
        }
      }
      if (headBefore != null) {
        try {
          await wt.git(['reset', '-q', headBefore]);
        } on GitException catch (r) {
          debugPrint('reset do commit pendente falhou: $r');
        }
      }
      await markStoppedIfLive();
      if (conflicted.isNotEmpty) {
        throw MergeConflictException(
          'Conflito ao fazer merge de ${s.branch} em $base '
          '(${conflicted.join(', ')}). O merge foi desfeito '
          '(${switch (options.method) {
            MergeMethod.merge => 'git merge --abort',
            MergeMethod.squash => 'git reset --merge',
            MergeMethod.rebase => 'git rebase --abort',
          }}); nada foi alterado. Peça ajustes ao agente '
          '(ex.: integrar $base na branch) ou resolva manualmente.',
          conflicted,
        );
      }
      throw ReviewException('O merge falhou e foi desfeito: $e');
    }

    final String commit;
    try {
      commit = (await main.git(['rev-parse', 'HEAD'])).trim();
    } on GitException catch (e) {
      throw ReviewException('Merge feito, mas o hash não foi lido: $e');
    }
    final warnings = <String>[];
    try {
      // Everything was committed and merged: only ignored files are lost.
      await main.removeWorktree(s.worktreePath, force: true);
    } on GitException catch (e) {
      warnings.add('worktree não removido: $e');
    }
    if (deleteBranch) {
      try {
        await main.deleteBranch(
          s.branch,
          force: options.method == MergeMethod.squash,
        );
      } on GitException catch (e) {
        warnings.add('branch não apagada: $e');
      }
    }
    await _ref.read(sessionsRepoProvider).setMerged(s.id, commit);
    if (task != null) await _ref.read(taskActionsProvider).markDone(task.id);
    if (spec != null) {
      warnings.addAll(await _closeSpec(ws, spec, commit, base));
    } else if (options.method == MergeMethod.rebase) {
      try {
        await main.git([
          'update-ref',
          '-d',
          'refs/promptorium/${s.id}/pre-rebase',
        ]);
      } on GitException catch (e) {
        warnings.add('checkpoint pre-rebase mantido: $e');
      }
    }
    try {
      await _ref.read(durableStateRepoProvider).setReviewDraft(sessionId, null);
    } catch (e) {
      debugPrint('rascunho do review $sessionId não removido — $e');
    }
    return MergeResult(commit: commit, warnings: warnings);
  }

  /// After the merge of a spec: every session of its worktree is `merged`,
  /// the steps are done, the card is "Feito", the worktree is forgotten and
  /// the file says `status: concluida`. Returns warnings (file not written).
  Future<List<String>> _closeSpec(
    Workspace ws,
    Spec spec,
    String commit,
    String base,
  ) async {
    final warnings = <String>[];
    final sessions = _ref.read(sessionsRepoProvider);
    for (final x in await sessions.bySpec(spec.id)) {
      if (x.status != SessionStatus.merged) {
        await sessions.setMerged(x.id, commit);
      }
    }
    final stepsRepo = _ref.read(specStepsRepoProvider);
    await stepsRepo.setAll(spec.id, {
      ...spec.requirements.map((r) => r.id),
      for (final r in subStepRows(await stepsRepo.bySpec(spec.id))) r.step,
    }, StepStatus.done);
    final repo = _ref.read(specsRepoProvider);
    // Specs stacked on this one now merge where this one went.
    if (spec.branch != null) {
      for (final o in await repo.watchByWorkspace(ws.id).first) {
        if (o.id == spec.id || o.baseBranch != spec.branch) continue;
        await repo.update(o.id, SpecsCompanion(baseBranch: Value(base)));
        await sessions.setSpecBaseBranch(o.id, base);
      }
    }
    await repo.setStage(spec.id, SpecStage.done);
    await repo.setWorktree(spec.id);
    try {
      // Checkpoints of the steps ("Voltar ao início da etapa").
      await _git(ws.path).deleteRefs('refs/promptorium/${spec.code}/');
    } on GitException catch (e) {
      warnings.add('checkpoints das etapas não removidos: $e');
    }
    try {
      final service = _ref.read(specServiceProvider);
      final text = await service.read(ws, spec);
      if (text != null) {
        final main = _git(ws.path);
        // Only when the file had no pending change of the user's.
        final clean = !(await main.status()).any((e) => e.path == spec.path);
        await service.save(
          ws,
          spec,
          SpecDocument.parse(text).withMeta(status: SpecStatus.done),
        );
        if (clean) {
          // Its own commit: a dirty tracked file would block the next merge.
          try {
            await main.git(['add', '--', spec.path]);
            await main.git([
              'commit',
              '-q',
              '-m',
              '${spec.code}: spec concluída',
              '--',
              spec.path,
            ]);
          } on GitException catch (e) {
            // A user's hook refused it: the merge stands.
            warnings.add(
              'status gravado em ${spec.path}, mas o commit "spec concluída" '
              'falhou: $e',
            );
          }
        } else {
          warnings.add(
            'A spec tinha alterações locais; status atualizado sem commit: ${spec.path}',
          );
        }
      }
    } catch (e) {
      warnings.add('status da spec não gravado no arquivo: $e');
    }
    return warnings;
  }

  /// Refuses a merge whose session data could make git touch something
  /// other than the session's own worktree / `pr/…` branch: the branch must
  /// be `pr/<slug>`, the base a plain ref and the worktree a folder inside
  /// [worktreesBase] (never the workspace root). Null = ok.
  @visibleForTesting
  static String? mergeGuard({
    required String branch,
    required String base,
    required String worktreePath,
    required String workspacePath,
    required String worktreesBase,
  }) {
    // `vibe/…`: the branch of a VIBE (SPEC-069 R1).
    final own =
        (branch.startsWith('pr/') && branch.length > 3) ||
        (branch.startsWith('vibe/') && branch.length > 5);
    if (!own) {
      return 'A branch da sessão ("$branch") não é uma branch pr/… criada '
          'pelo Promptorium; faça o merge manualmente.';
    }
    if (base.isEmpty || base.startsWith('-') || base.contains('..')) {
      return 'Branch base inválida: "$base".';
    }
    String norm(String p) {
      final abs = Directory(p).absolute.path;
      final parts = <String>[];
      for (final seg in abs.split('/')) {
        if (seg.isEmpty || seg == '.') continue;
        if (seg == '..') {
          if (parts.isNotEmpty) parts.removeLast();
        } else {
          parts.add(seg);
        }
      }
      return '/${parts.join('/')}';
    }

    final wt = norm(worktreePath), root = norm(workspacePath);
    final baseDir = norm(worktreesBase);
    if (wt == root || !wt.startsWith('$baseDir/') || root.startsWith('$wt/')) {
      return 'O worktree da sessão ($worktreePath) não está na pasta de '
          'worktrees do Promptorium ($worktreesBase); faça o merge manualmente.';
    }
    return null;
  }

  static Future<bool> _merging(GitService git) async {
    try {
      await git.git(['rev-parse', '-q', '--verify', 'MERGE_HEAD']);
      return true;
    } on GitException {
      return false;
    }
  }

  /// Opens [url] in the browser (`xdg-open`). Errors only log.
  Future<void> openUrl(String url) async {
    try {
      await _run('xdg-open', [url]);
    } catch (e) {
      debugPrint('xdg-open $url: $e');
    }
  }

  static String _short(String id) => id.length > 8 ? id.substring(0, 8) : id;
}

final reviewServiceProvider = Provider(ReviewService.new);

/// "Aguardando review" of a workspace (recomputed when sessions / tasks
/// change).
final reviewQueueProvider = FutureProvider.family<List<ReviewItem>, int>((
  ref,
  workspaceId,
) async {
  final sessions = await ref.watch(sessionsProvider(workspaceId).future);
  final tasks = await ref.watch(tasksProvider(workspaceId).future);
  final specs = await ref.watch(specsProvider(workspaceId).future);
  final ws = await ref.read(workspacesRepoProvider).getById(workspaceId);
  if (ws == null) return const [];
  return ref.read(reviewServiceProvider).queue(ws, sessions, tasks, specs);
});

/// Diff of one session (invalidate after reject / merge / refresh).
final reviewDetailProvider = FutureProvider.family<ReviewDetail, String>(
  (ref, sessionId) => ref.read(reviewServiceProvider).load(sessionId),
);

final prAvailabilityProvider = FutureProvider.family<PrAvailability, String>((
  ref,
  sessionId,
) async {
  ref.watch(appSettingsProvider.select((s) => s['review.remote.$sessionId']));
  final ws = ref.watch(activeWorkspaceProvider);
  if (ws != null) ref.watch(projectConfigProvider(ws.path));
  return ref.read(reviewServiceProvider).prAvailability(sessionId);
});

/// Step ("R2") the Review opens filtered on, set by "Ver diff da etapa" of
/// the Specs screen and consumed once (UX v2, U5).
class ReviewInitialStep extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? step) => state = step;
}

final reviewInitialStepProvider = NotifierProvider<ReviewInitialStep, String?>(
  ReviewInitialStep.new,
);

/// Session shown in the Review screen (null = first of the queue).
class SelectedReview extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

final selectedReviewProvider = NotifierProvider<SelectedReview, String?>(
  SelectedReview.new,
);

/// Pending comments and accepted hunks of one session, kept in
/// `review_drafts` (schema v9) so closing the app does not lose them.
@immutable
class ReviewDraft {
  const ReviewDraft({this.comments = const [], this.accepted = const {}});

  final List<ReviewComment> comments;

  /// [hunkKey]s marked "Aceitar hunk".
  final Set<String> accepted;

  bool get isEmpty => comments.isEmpty && accepted.isEmpty;

  String encode() => jsonEncode({
    'comentarios': [for (final c in comments) c.toJson()],
    'aceitos': accepted.toList(),
  });

  static ReviewDraft decode(String? text) {
    if (text == null) return const ReviewDraft();
    try {
      final j = jsonDecode(text);
      if (j is! Map) return const ReviewDraft();
      return ReviewDraft(
        comments: [
          for (final c in (j['comentarios'] as List? ?? const []))
            ?ReviewComment.fromJson(c),
        ],
        accepted: {for (final a in (j['aceitos'] as List? ?? const [])) '$a'},
      );
    } on FormatException {
      return const ReviewDraft();
    }
  }
}

class ReviewDraftNotifier extends Notifier<ReviewDraft> {
  ReviewDraftNotifier(this.sessionId);

  final String sessionId;

  /// A change was made before the stored draft was read: it wins.
  bool _touched = false;
  Future<void> _writes = Future.value();

  @override
  ReviewDraft build() {
    unawaited(Future<void>.microtask(_restore));
    return const ReviewDraft();
  }

  Future<void> _restore() async {
    try {
      final text = await ref
          .read(durableStateRepoProvider)
          .reviewDraft(sessionId);
      if (!ref.mounted || _touched || text == null) return;
      state = ReviewDraft.decode(text);
    } catch (e) {
      debugPrint('rascunho do review $sessionId não lido — $e');
    }
  }

  void _set(ReviewDraft d) {
    _touched = true;
    state = d;
    final repo = ref.read(durableStateRepoProvider);
    _writes = _writes.then(
      (_) => repo
          .setReviewDraft(sessionId, d.isEmpty ? null : d.encode())
          .catchError((Object e) {
            debugPrint('rascunho do review $sessionId não gravado — $e');
          }),
    );
  }

  /// Completes when the stored draft matches the state (tests).
  Future<void> get saved => _writes;

  void addComment(ReviewComment c) => _set(
    ReviewDraft(comments: [...state.comments, c], accepted: state.accepted),
  );

  void removeComment(ReviewComment c) => _set(
    ReviewDraft(
      comments: [
        for (final x in state.comments)
          if (!identical(x, c)) x,
      ],
      accepted: state.accepted,
    ),
  );

  void clearComments() => _set(ReviewDraft(accepted: state.accepted));

  /// Merged / rejected: nothing to keep.
  void clear() => _set(const ReviewDraft());

  void toggleAccepted(String key) => _set(
    ReviewDraft(
      comments: state.comments,
      accepted: state.accepted.contains(key)
          ? ({...state.accepted}..remove(key))
          : {...state.accepted, key},
    ),
  );
}

final reviewDraftProvider =
    NotifierProvider.family<ReviewDraftNotifier, ReviewDraft, String>(
      ReviewDraftNotifier.new,
    );

final reviewSinceProvider =
    FutureProvider.family<ReviewDetail, (String, String)>(
      (ref, key) => ref.read(reviewServiceProvider).loadSince(key.$1, key.$2),
    );
final reviewRoundAvailabilityProvider =
    FutureProvider.family<String?, (String, String?)>((ref, key) {
      ref.watch(reviewDetailProvider(key.$1));
      return ref.read(reviewServiceProvider).roundUnavailable(key.$1, key.$2);
    });

final mergeReadinessProvider = FutureProvider.family<MergeReadiness, String>((
  ref,
  sessionId,
) async {
  final detail = await ref.watch(reviewDetailProvider(sessionId).future);
  final specId = detail.session.specId;
  if (specId != null) {
    ref.watch(reviewCommentsProvider(specId));
    ref.watch(criteriaProvider(specId));
    ref.watch(specsProvider(detail.session.workspaceId));
    ref.watch(_readinessStepsProvider(specId));
  }
  ref.watch(sessionsProvider(detail.session.workspaceId));
  ref.watch(prBabysitterProvider);
  ref.watch(
    conflictResolutionProvider(sessionId)
        .select((r) => (r?.state, r?.checkedSha, r?.running)),
  );
  try {
    final readiness = evaluateReadiness(
      await ref.read(reviewServiceProvider).readinessInputs(sessionId),
    );
    final prediction = await ref
        .read(reviewServiceProvider)
        .predictConflict(sessionId);
    return MergeReadiness([
      ...readiness.items,
      ReadinessItem(
        'conflito',
        'Conflito previsto',
        prediction.error != null
            ? ReadinessLevel.naoVerificado
            : prediction.files.isNotEmpty
            ? ReadinessLevel.aviso
            : ReadinessLevel.ok,
        prediction.error ??
            (prediction.files.isEmpty
                ? 'Sem conflito previsto nos commits; não inclui pendências'
                : prediction.files.join(', ')),
      ),
    ]);
  } catch (e) {
    return evaluateReadiness(
      ReadinessInputs(
        unknown: {'raiz': '$e', 'empilhada': '$e', 'worktree': '$e'},
      ),
    );
  }
});

final _readinessStepsProvider = StreamProvider.family<List<SpecStep>, int>(
  (ref, id) => ref.watch(specStepsRepoProvider).watchBySpec(id),
);

/// One git check at a time for the conflict forecast of the queue
/// (SPEC-032 R4): each item waits for the previous one. One lane per
/// provider container, so a check left pending never blocks another
/// container's queue.
class GitLane {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() job) {
    final done = Completer<T>();
    final previous = _tail;
    _tail = done.future.then<void>((_) {}, onError: (_) {});
    unawaited(
      previous.whenComplete(() async {
        try {
          done.complete(await job());
        } catch (e, st) {
          done.completeError(e, st);
        }
      }),
    );
    return done.future;
  }
}

final forecastLaneProvider = Provider<GitLane>((ref) => GitLane());

/// Predicted conflict of a queue item with its base (`git merge-tree`),
/// computed in the background, one at a time. Invalidated with the queue.
final conflictForecastProvider =
    FutureProvider.family<ConflictPrediction, String>((ref, sessionId) {
      final service = ref.read(reviewServiceProvider);
      // Never an error state: Riverpod would retry it on a timer. A failed
      // check is a prediction with [ConflictPrediction.error].
      return ref.read(forecastLaneProvider).run(() async {
        try {
          final p = await service.predictConflict(sessionId);
          // SPEC-043 R6: a predicted conflict may start the resolution.
          if (p.files.isNotEmpty) {
            unawaited(ref.read(conflictResolverProvider).autoStart(sessionId));
          }
          return p;
        } catch (e) {
          return ConflictPrediction(error: '$e');
        }
      });
    });

/// SPEC-032 R15: runs [ReviewService.restackOrphans] when the Review opens
/// and whenever the repository changes (invalidated by the screen).
final orphanRestackProvider = FutureProvider.family<List<RestackResult>, int>((
  ref,
  workspaceId,
) async {
  final ws = await ref.read(workspacesRepoProvider).getById(workspaceId);
  if (ws == null) return const [];
  return ref.read(reviewServiceProvider).restackOrphans(ws);
});

/// SPEC-032 R11: the root against the queue's base; null when it cannot be
/// read (never an error, so nothing retries on a timer).
final rootStatusProvider = FutureProvider.family<RootStatus?, int>((
  ref,
  workspaceId,
) async {
  try {
    final ws = await ref.read(workspacesRepoProvider).getById(workspaceId);
    if (ws == null) return null;
    return await ref.read(reviewServiceProvider).rootStatus(ws);
  } catch (e) {
    debugPrint('raiz do workspace $workspaceId indisponível');
    return null;
  }
});

/// SPEC-032 R17: the rebase of a queue item (never an error).
final rebaseStatusProvider = FutureProvider.family<RebaseStatus, String>((
  ref,
  sessionId,
) async {
  try {
    return await ref.read(reviewServiceProvider).rebaseStatus(sessionId);
  } catch (_) {
    return const RebaseStatus();
  }
});

/// SPEC-032 R17: the stretches in conflict of a queue item.
final conflictHunksProvider = FutureProvider.family<List<ConflictHunk>, String>(
  (ref, sessionId) async {
    try {
      return await ref.read(reviewServiceProvider).conflictHunks(sessionId);
    } catch (_) {
      return const [];
    }
  },
);

/// SPEC-032 R16: files two branches of the queue both change in conflicting
/// ways (`git merge-tree <a> <b>` in the root), one check at a time. Key:
/// (workspace id, branch a, branch b). Never an error (empty = none).
final pairConflictProvider =
    FutureProvider.family<List<String>, (int, String, String)>((
      ref,
      key,
    ) async {
      final (wsId, a, b) = key;
      final ws = await ref.read(workspacesRepoProvider).getById(wsId);
      if (ws == null) return const [];
      final git = ref.read(gitServiceFactoryProvider)(ws.path);
      return ref.read(forecastLaneProvider).run(() async {
        try {
          await git.git(['merge-tree', '--write-tree', '--name-only', a, b]);
          return const <String>[];
        } on GitException catch (e) {
          if (e.exitCode != 1) return const <String>[];
          return e.stdout
              .split('\n')
              .skip(1)
              .takeWhile((l) => l.isNotEmpty)
              .toList();
        } catch (_) {
          return const <String>[];
        }
      });
    });

/// App setting with the Review's view of a workspace ("lista" | "grafo").
String reviewModeKey(int workspaceId) => 'review.modo.$workspaceId';

/// Files that would conflict merging [branch] into [base], without touching
/// the tree or the index (`git merge-tree --write-tree`): the Review's
/// forecast, also used by the Higiene tab (SPEC-047 R4).
Future<ConflictPrediction> predictMergeConflict(
  GitService git,
  String base,
  String branch,
) async {
  try {
    await git.git(['merge-tree', '--write-tree', '--name-only', base, branch]);
    return const ConflictPrediction();
  } on GitException catch (e) {
    if (e.exitCode == 1) {
      return ConflictPrediction(
        files: e.stdout
            .split('\n')
            .skip(1)
            .takeWhile((l) => l.isNotEmpty)
            .toList(),
      );
    }
    return ConflictPrediction(error: '$e');
  }
}
