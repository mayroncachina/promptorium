import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show max;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/git/diff_parser.dart';
import '../../core/git/git_service.dart';
import '../../data/providers.dart';
import '../sessions/session_manager.dart';
import '../project/project_memory.dart';
import '../specs/spec_service.dart';
import '../tasks/task_actions.dart';
import 'review_logic.dart';

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
  const PrAvailability({required this.available, this.reason, this.remote});

  final bool available;

  /// Tooltip when not [available].
  final String? reason;
  final String? remote;
}

@immutable
class MergeResult {
  const MergeResult({required this.commit, this.warnings = const []});

  /// Hash of the merge commit in the base branch.
  final String commit;

  /// Cleanup steps that failed (worktree / branch removal).
  final List<String> warnings;
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
  }) async {
    if (comments.isEmpty && note.trim().isEmpty) {
      throw const ReviewException('Escreva um comentário antes de enviar.');
    }
    final c = await _context(sessionId);
    if (c.session.status == SessionStatus.merged) {
      throw const ReviewException('A sessão já foi integrada (merge).');
    }
    final msg = adjustmentMessage(comments, note: note);
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
    }
    return msg;
  }

  /// `which gh` + a remote in the workspace (prefers `origin`).
  Future<PrAvailability> prAvailability(String sessionId) async {
    final c = await _context(sessionId);
    try {
      final r = await _run('which', ['gh']);
      if (r.exitCode != 0 || '${r.stdout}'.trim().isEmpty) {
        return const PrAvailability(
          available: false,
          reason: 'GitHub CLI (gh) não encontrado no PATH.',
        );
      }
    } on ProcessException {
      return const PrAvailability(
        available: false,
        reason: 'GitHub CLI (gh) não encontrado no PATH.',
      );
    }
    final List<String> remotes;
    try {
      remotes = [
        for (final l in (await _git(
          c.workspace.path,
        ).git(['remote'])).split('\n'))
          if (l.trim().isNotEmpty) l.trim(),
      ];
    } on GitException catch (e) {
      return PrAvailability(available: false, reason: '$e');
    }
    if (remotes.isEmpty) {
      return const PrAvailability(
        available: false,
        reason: 'O repositório não tem remote (git remote add origin …).',
      );
    }
    if (!hasWorktree(c.session, c.workspace)) {
      return const PrAvailability(
        available: false,
        reason: 'A sessão não tem worktree próprio.',
      );
    }
    try {
      final auth = await _run('gh', [
        'auth',
        'status',
      ], workingDirectory: c.workspace.path);
      if (auth.exitCode != 0) {
        return const PrAvailability(
          available: false,
          reason: 'gh não está autenticado: rode gh auth login no terminal.',
        );
      }
    } on ProcessException {
      return const PrAvailability(
        available: false,
        reason: 'GitHub CLI (gh) não encontrado no PATH.',
      );
    }
    return PrAvailability(
      available: true,
      remote: remotes.contains('origin') ? 'origin' : remotes.first,
    );
  }

  /// Commits everything pending in [git] (`add -A` + `commit`). Returns
  /// whether a commit was made.
  static Future<bool> _commitPending(GitService git, String message) async {
    if ((await git.status()).isEmpty) return false;
    await git.git(['add', '-A']);
    await git.git(['commit', '-q', '-m', message]);
    return true;
  }

  /// "Criar PR": commit pending changes, `git push -u <remote> <branch>`,
  /// `gh pr create` (title/body from the task, `--fill` without one).
  /// Returns the PR URL (also stored in `sessions.pr_url`).
  Future<String> createPr(String sessionId, {bool draft = false}) async {
    final avail = await prAvailability(sessionId);
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
      await _commitPending(git, pendingCommitMessage(s, task, spec));
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

  /// Criteria of [spec] not checked yet (text). A criterion counts as
  /// checked when it is `- [x]` in the file or marked in the Review.
  Future<List<String>> pendingCriteria(Spec spec, Workspace ws) async {
    final text = await _ref.read(specServiceProvider).read(ws, spec);
    if (text == null) return const [];
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
  Future<MergeResult> merge(
    String sessionId, {
    bool deleteBranch = true,
    String? override,
  }) async {
    final c = await _context(sessionId);
    final s = c.session, ws = c.workspace, task = c.task, spec = c.spec;
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
    final stackedOn =
        (await _ref.read(specsRepoProvider).watchByWorkspace(ws.id).first)
            .where(
              (o) =>
                  o.id != spec?.id &&
                  o.branch == base &&
                  o.stage != SpecStage.done,
            )
            .firstOrNull;
    if (stackedOn != null) {
      throw ReviewException(
        '${spec?.code ?? 'Esta spec'} foi criada em cima de ${stackedOn.code} '
        '(branch "$base"), que ainda não foi mergeada. Faça o merge de '
        '${stackedOn.code} primeiro: depois deste, o merge desta vai para a '
        'branch principal.',
      );
    }
    try {
      final current = await main.currentBranch();
      if (current != base) {
        throw ReviewException(
          'O repositório principal está em "${current ?? 'HEAD destacado'}", '
          'mas o merge vai para "$base". Troque para "$base" '
          '(git switch $base) e tente de novo.',
        );
      }
      // The project memory is written by the app while specs run (F8).
      final dirty = (await main.status())
          .where((e) => !e.isUntracked && e.path != ProjectMemory.filePath)
          .toList();
      if (dirty.isNotEmpty) {
        throw ReviewException(
          'O repositório principal tem alterações não commitadas '
          '(${dirty.length} arquivo(s): ${dirty.take(3).map((e) => e.path).join(', ')}'
          '${dirty.length > 3 ? '…' : ''}). Faça commit ou stash antes do merge.',
        );
      }
    } on GitException catch (e) {
      throw ReviewException('Falha ao ler o repositório principal: $e');
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
      if (!await _commitPending(wt, pendingCommitMessage(s, task, spec))) {
        headBefore = null;
      }
    } on GitException catch (e) {
      await markStoppedIfLive();
      throw ReviewException('Falha ao commitar as alterações do worktree: $e');
    }

    final title = reviewTitle(s, task, spec);
    try {
      await main.git([
        'merge',
        '--no-ff',
        '-m',
        'Merge ${s.branch}: $title',
        '--',
        s.branch,
      ]);
    } on GitException catch (e) {
      var conflicted = <String>[];
      try {
        conflicted = [
          for (final l in (await main.git([
            'diff',
            '--name-only',
            '--diff-filter=U',
          ])).split('\n'))
            if (l.trim().isNotEmpty) l.trim(),
        ];
      } on GitException {
        // not in a merge
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
        throw ReviewException(
          'Conflito ao fazer merge de ${s.branch} em $base '
          '(${conflicted.join(', ')}). O merge foi desfeito '
          '(git merge --abort); nada foi alterado. Peça ajustes ao agente '
          '(ex.: integrar $base na branch) ou resolva manualmente.',
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
        await main.deleteBranch(s.branch);
      } on GitException catch (e) {
        warnings.add('branch não apagada: $e');
      }
    }
    await _ref.read(sessionsRepoProvider).setMerged(s.id, commit);
    if (task != null) await _ref.read(taskActionsProvider).markDone(task.id);
    if (spec != null) {
      warnings.addAll(await _closeSpec(ws, spec, commit, base));
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
    await _ref
        .read(specStepsRepoProvider)
        .setAll(spec.id, spec.requirements.map((r) => r.id), StepStatus.done);
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
          await main.git(['add', '--', spec.path]);
          await main.git([
            'commit',
            '-q',
            '-m',
            '${spec.code}: spec concluída',
            '--',
            spec.path,
          ]);
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
    if (!branch.startsWith('pr/') || branch.length <= 3) {
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

final prAvailabilityProvider = FutureProvider.family<PrAvailability, String>(
  (ref, sessionId) => ref.read(reviewServiceProvider).prAvailability(sessionId),
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
