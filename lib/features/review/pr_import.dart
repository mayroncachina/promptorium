import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/claude_args.dart';
import '../../core/git/gh_cli.dart';
import '../../core/git/git_service.dart';
import '../../data/providers.dart';
import '../project/project_config.dart';
import '../sessions/session_manager.dart';
import 'pr_babysitter.dart';
import 'review_host.dart';
import 'review_service.dart';

/// "Trazer PR" (SPEC-050): any open PR of the repository becomes a worktree,
/// a session of the agent and an item of the Review, even without a spec.

/// How the session of a PR brought into the app starts (R4).
enum PrStart {
  /// The agent reads the PR in plan mode and answers with what it changes,
  /// the risks and the open questions (P2: the default).
  resumir('Resumir o PR'),

  /// The open comments of the PR, with file and line, and the fixes.
  comentarios('Responder aos comentários'),

  /// A free request.
  pedido('Meu pedido');

  const PrStart(this.label);

  final String label;
}

/// A PR of the "Trazer PR" list (R1).
@immutable
class PrImportCandidate {
  const PrImportCandidate({
    required this.pr,
    this.sessionId,
    this.canWrite = false,
  });

  final GhOpenPr pr;

  /// Session of the workspace that already brought it ("Já no app").
  final String? sessionId;

  /// The user can push to the base repository (`viewerPermission`).
  final bool canWrite;

  int get number => pr.number;
  String get url => pr.url;
  String get title => pr.title;
  String get author => pr.author;
  bool get alreadyIn => sessionId != null;

  /// The agent's commits can go to the PR's branch (R7): same repository
  /// with write permission, or a fork that lets the maintainers edit.
  bool get canPush =>
      canWrite && (!pr.isCrossRepository || pr.maintainerCanModify);

  /// Branch of the worktree (R3): the PR's own name in the same
  /// repository, `pr/<n>-<slug>` for a fork.
  String get localBranch => pr.isCrossRepository
      ? forkBranchName(pr.number, pr.title)
      : pr.headRefName;

  /// `checks ok` / `1 check falhou` / `checks rodando` / `sem checks`.
  String get checksLabel {
    final failed = pr.failedChecks.length;
    return switch (pr.ci) {
      CiState.none => 'sem checks',
      CiState.passed => 'checks ok',
      CiState.running => 'checks rodando',
      CiState.failed =>
        failed == 1 ? '1 check falhou' : '$failed checks falharam',
    };
  }
}

/// `pr/212-corrige-o-scroll`: the local branch of a PR from a fork (R3).
String forkBranchName(int number, String title) {
  final words = slugify(title, maxLength: 60).split('-').take(3).join('-');
  return words.isEmpty ? 'pr/$number' : 'pr/$number-$words';
}

/// Number of a PR typed in the search (R1): `#212`, `212` or the URL of a PR
/// of [repository] (`owner/repo`). Null = not a PR reference; throws when
/// the URL is of another repository.
int? parsePrReference(String text, {String? repository}) {
  final t = text.trim();
  final n = RegExp(r'^#?(\d+)$').firstMatch(t);
  if (n != null) return int.parse(n.group(1)!);
  final uri = Uri.tryParse(t);
  final parts = uri?.pathSegments.where((p) => p.isNotEmpty).toList() ?? [];
  if (uri == null ||
      !uri.hasAuthority ||
      parts.length < 4 ||
      parts[2] != 'pull' ||
      int.tryParse(parts[3]) == null) {
    return null;
  }
  if (repository != null &&
      '${parts[0]}/${parts[1]}'.toLowerCase() != repository.toLowerCase()) {
    throw PrImportException(
      'Esse PR é de ${parts[0]}/${parts[1]}; só PRs de $repository podem ser '
      'trazidos.',
    );
  }
  return int.parse(parts[3]);
}

/// Whether [pr] matches what the user typed in the search (title, author or
/// number).
bool prMatches(GhOpenPr pr, String query) {
  final q = query.trim().toLowerCase().replaceFirst(RegExp(r'^[#@]'), '');
  if (q.isEmpty) return true;
  return pr.title.toLowerCase().contains(q) ||
      pr.author.toLowerCase().contains(q) ||
      pr.headRefName.toLowerCase().contains(q) ||
      '${pr.number}'.startsWith(q);
}

/// Session of [sessions] that already works on [pr] (R1 "Já no app"): by its
/// `prUrl` or by the branch, and not merged.
String? sessionOfPr(GhOpenPr pr, List<Session> sessions) {
  for (final s in sessions) {
    if (s.status == SessionStatus.merged || s.mergeCommit != null) continue;
    if (s.prUrl != null && s.prUrl == pr.url) return s.id;
  }
  for (final s in sessions) {
    if (s.status == SessionStatus.merged || s.mergeCommit != null) continue;
    if (!pr.isCrossRepository && s.branch == pr.headRefName) return s.id;
    if (s.branch.startsWith('pr/${pr.number}-') ||
        s.branch == 'pr/${pr.number}') {
      return s.id;
    }
  }
  return null;
}

/// Why "Trazer PR…" is off for a repository on [host] (R10); null = on.
String? importUnavailableReason(String? host) => switch (host) {
  'github' => null,
  'gitlab' =>
    'Trazer PR ainda não funciona com GitLab: as ações de MR ficam para a '
        'SPEC-013.',
  _ => 'Trazer PR precisa de um remote no GitHub.',
};

/// "Trazer PR" of a workspace: where the PRs live and whether it works.
@immutable
class PrImportAvailability {
  const PrImportAvailability({
    this.reason,
    this.remote,
    this.repository,
    this.remoteUrl,
  });

  /// Why it is off (null = on).
  final String? reason;

  /// Remote of the repository (`origin`) and its URL.
  final String? remote, remoteUrl;

  /// `owner/repo`.
  final String? repository;

  bool get available => reason == null;
}

/// What the app keeps about a PR brought into it, by session
/// (`app_settings`, key [ImportedPr.key]).
@immutable
class ImportedPr {
  const ImportedPr({
    required this.number,
    required this.url,
    this.title = '',
    this.author = '',
    this.headRef = '',
    this.baseRef = '',
    this.cross = false,
    this.canPush = false,
    this.remote = 'origin',
    this.pushTo,
    this.state = 'OPEN',
    this.replyInPr = false,
    this.pendingReplies = const [],
  });

  static String key(String sessionId) => 'pr.trazido.$sessionId';

  final int number;
  final String url, title, author, headRef, baseRef;

  /// The head lives in a fork.
  final bool cross;

  /// The agent's commits go to the PR's branch (R7).
  final bool canPush;

  /// Remote the PR is fetched from.
  final String remote;

  /// Where the pushes go (a remote or the fork's URL; null = [remote]).
  final String? pushTo;

  /// Last state read from the host: `OPEN` / `MERGED` / `CLOSED` (R5).
  final String state;

  /// "Responder no PR depois do push" of the last request (R8).
  final bool replyInPr;

  /// Ids (`github:<id>`) of the PR conversations to answer after the next
  /// push (R8).
  final List<String> pendingReplies;

  /// Local copy of the PR's head (`git fetch <remote> pull/<n>/head`).
  String get localRef => prLocalRef(number);

  bool get open => state == 'OPEN';

  ImportedPr copyWith({
    String? state,
    bool? replyInPr,
    List<String>? pendingReplies,
  }) => ImportedPr(
    number: number,
    url: url,
    title: title,
    author: author,
    headRef: headRef,
    baseRef: baseRef,
    cross: cross,
    canPush: canPush,
    remote: remote,
    pushTo: pushTo,
    state: state ?? this.state,
    replyInPr: replyInPr ?? this.replyInPr,
    pendingReplies: pendingReplies ?? this.pendingReplies,
  );

  String encode() => jsonEncode({
    'n': number,
    'url': url,
    'titulo': title,
    'autor': author,
    'head': headRef,
    'base': baseRef,
    'fork': cross,
    'push': canPush,
    'remote': remote,
    'pushPara': ?pushTo,
    'estado': state,
    'responder': replyInPr,
    if (pendingReplies.isNotEmpty) 'responderA': pendingReplies,
  });

  static ImportedPr? decode(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      final j = jsonDecode(text);
      if (j is! Map || j['n'] is! int || j['url'] is! String) return null;
      String str(String k) => j[k] is String ? j[k] as String : '';
      return ImportedPr(
        number: j['n'] as int,
        url: j['url'] as String,
        title: str('titulo'),
        author: str('autor'),
        headRef: str('head'),
        baseRef: str('base'),
        cross: j['fork'] == true,
        canPush: j['push'] == true,
        remote: str('remote').isEmpty ? 'origin' : str('remote'),
        pushTo: j['pushPara'] is String ? j['pushPara'] as String : null,
        state: str('estado').isEmpty ? 'OPEN' : str('estado'),
        replyInPr: j['responder'] == true,
        pendingReplies: [
          if (j['responderA'] case final List l) ...l.whereType<String>(),
        ],
      );
    } on FormatException {
      return null;
    }
  }
}

/// The reply left in a PR conversation the agent fixed (SPEC-050 R8).
String prReplyBody(String sha) =>
    'Corrigido em ${sha.length > 7 ? sha.substring(0, 7) : sha} '
    '(Promptorium).';

/// `refs/promptorium/pr/<n>`: where the head of a PR is fetched to.
String prLocalRef(int number) => 'refs/promptorium/pr/$number';

/// The PR brought into the app by [sessionId], from the settings map.
ImportedPr? importedPrOf(Map<String, String> settings, String sessionId) =>
    ImportedPr.decode(settings[ImportedPr.key(sessionId)]);

/// `app_settings` key of the last "Responder no PR depois do push" choice of
/// a workspace (P3).
String replyInPrKey(int workspaceId) => 'pr.responder.$workspaceId';

/// A failure of "Trazer PR".
class PrImportException implements Exception {
  const PrImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The first message of the session of a PR brought into the app (R4): the
/// context of the PR (title, description, author, base, `git diff --stat`,
/// open comments and failed checks), the rules of someone else's PR (R7)
/// and how to start.
String prContextMessage({
  required GhOpenPr pr,
  required PrStart start,
  required bool canPush,
  String diffStat = '',
  List<PrComment> comments = const [],
  String request = '',
}) {
  final b = StringBuffer()
    ..writeln('Pull request #${pr.number}: ${pr.title}')
    ..writeln(pr.url)
    ..writeln()
    ..writeln(
      'Autor: @${pr.author.isEmpty ? '?' : pr.author}'
      '${pr.isCrossRepository ? ' (fork ${pr.headOwner.isEmpty ? '' : '${pr.headOwner}/'}…)' : ''}',
    )
    ..writeln('Branch: ${pr.headRefName} → base ${pr.baseRefName}');
  final body = pr.body.trim();
  b
    ..writeln()
    ..writeln('Descrição:')
    ..writeln(
      body.isEmpty
          ? '(sem descrição)'
          : body.substring(0, body.length.clamp(0, 6000)),
    );
  final stat = diffStat.trim();
  if (stat.isNotEmpty) {
    b
      ..writeln()
      ..writeln('git diff --stat contra ${pr.baseRefName}:')
      ..writeln(stat);
  }
  if (comments.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Comentários abertos (${comments.length}):');
    for (final c in comments) {
      final where = c.path == null ? '' : '${c.path}:${c.line ?? 0} — ';
      final text = c.body.substring(0, c.body.length.clamp(0, 4000));
      b.writeln('- [${c.externalId ?? ''}] $where@${c.author}: $text');
    }
  }
  final failed = pr.failedChecks;
  if (failed.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Checks que falharam: ${failed.join(', ')}');
  }
  b
    ..writeln()
    ..writeln('Regras deste PR (é de outra pessoa):')
    ..writeln(
      '- Nunca reescreva o histórico publicado da branch: nada de '
      'git push --force, --force-with-lease, rebase ou amend de commits já '
      'publicados. Faça commits novos por cima.',
    )
    ..writeln(
      canPush
          ? '- Não faça push: o Promptorium publica os seus commits na branch '
                'do PR depois da revisão.'
          : '- Sem permissão de escrita na branch do PR: os seus commits ficam '
                'locais e a pessoa manda um patch para a autora. Não faça push.',
    )
    ..writeln('- Não feche, aprove nem mergeie o PR, e não resolva conversas.')
    ..writeln();
  switch (start) {
    case PrStart.resumir:
      b.write(
        'Leia o PR em modo plano, sem editar nada, e responda com: o que o '
        'PR muda, os riscos e as perguntas em aberto.',
      );
    case PrStart.comentarios:
      b.write(
        comments.isEmpty
            ? 'O PR não tem comentários abertos: leia o PR e diga o que '
                  'falta para ele ser aprovado.'
            : 'Corrija o que os comentários abertos pedem, rode os testes e '
                  'faça um commit por conversa tratada, citando o arquivo e a '
                  'linha.',
      );
    case PrStart.pedido:
      b.write(
        request.trim().isEmpty ? 'Aguarde o meu pedido.' : request.trim(),
      );
  }
  return b.toString();
}

/// Lists, resolves and brings PRs into the app (R1, R3, R4).
class PrImportService {
  PrImportService(this._ref);

  final Ref _ref;

  GitService _git(String root) => _ref.read(gitServiceFactoryProvider)(root);

  GhCli _gh(String cwd) => GhCli(_ref.read(commandRunnerProvider), cwd: cwd);

  /// Where the PRs of [ws] live and whether "Trazer PR" works there (R10).
  Future<PrImportAvailability> availability(Workspace ws) async {
    try {
      final git = _git(ws.path);
      final names = (await git.git(['remote']))
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (names.isEmpty) {
        return const PrImportAvailability(
          reason: 'O repositório não tem remote (git remote add origin …).',
        );
      }
      final remote = names.contains('origin') ? 'origin' : names.first;
      final url = (await git.git(['remote', 'get-url', remote])).trim();
      final config = await _ref.read(projectConfigProvider(ws.path).future);
      final host = detectReviewHost(url, config);
      final reason = importUnavailableReason(host);
      final repo = reviewRepositoryUrl(url);
      final slug = repo == null
          ? null
          : Uri.parse(repo).pathSegments.take(2).join('/');
      return PrImportAvailability(
        reason: reason,
        remote: remote,
        remoteUrl: url,
        repository: slug,
      );
    } on GitException catch (e) {
      return PrImportAvailability(reason: '$e');
    }
  }

  Future<PrImportAvailability> _require(Workspace ws) async {
    final a = await availability(ws);
    if (!a.available) throw PrImportException(a.reason!);
    return a;
  }

  /// The user can push to the repository (`gh repo view --json
  /// viewerPermission`); false when it cannot be read.
  Future<bool> _canWrite(Workspace ws) async {
    try {
      final out = await _gh(ws.path)
          .gh(['repo', 'view', '--json', 'viewerPermission']);
      final j = jsonDecode(out);
      return j is Map &&
          const {'ADMIN', 'MAINTAIN', 'WRITE'}.contains(j['viewerPermission']);
    } catch (e) {
      debugPrint('viewerPermission não lida — $e');
      return false;
    }
  }

  Future<List<Session>> _sessions(Workspace ws) =>
      _ref.read(sessionsRepoProvider).watchByWorkspace(ws.id).first;

  /// The open PRs of [ws], newest first, with the session that already
  /// brought each one (R1).
  Future<List<PrImportCandidate>> candidates(Workspace ws) async {
    await _require(ws);
    final gh = _gh(ws.path);
    final List<GhOpenPr> prs;
    try {
      prs = await gh.prListOpen();
    } on GhException catch (e) {
      throw PrImportException('$e');
    }
    final canWrite = await _canWrite(ws);
    final sessions = await _sessions(ws);
    final sorted = [...prs]
      ..sort((a, b) {
        final ua = a.updatedAt, ub = b.updatedAt;
        if (ua == null || ub == null) return b.number.compareTo(a.number);
        return ub.compareTo(ua);
      });
    return [
      for (final p in sorted)
        PrImportCandidate(
          pr: p,
          sessionId: sessionOfPr(p, sessions),
          canWrite: canWrite,
        ),
    ];
  }

  /// The PR of `#n`, `n` or its URL, even when it is not in the list (R1).
  /// Null = [text] is not a PR reference.
  Future<PrImportCandidate?> resolve(Workspace ws, String text) async {
    final a = await _require(ws);
    final n = parsePrReference(text, repository: a.repository);
    if (n == null) return null;
    final GhOpenPr pr;
    try {
      pr = await _gh(ws.path).prView('$n');
    } on GhException catch (e) {
      throw PrImportException('PR #$n não encontrado: $e');
    }
    if (pr.state != 'OPEN') {
      throw PrImportException(
        'O PR #$n está ${pr.state == 'MERGED' ? 'mergeado' : 'fechado'}.',
      );
    }
    return PrImportCandidate(
      pr: pr,
      sessionId: sessionOfPr(pr, await _sessions(ws)),
      canWrite: await _canWrite(ws),
    );
  }

  /// The open review threads of PR [number] (empty when they cannot be
  /// read).
  Future<List<PrComment>> openComments(Workspace ws, int number) async {
    final a = await availability(ws);
    if (a.repository == null) return const [];
    try {
      final out = await _gh(ws.path).gh([
        'api',
        'repos/${a.repository}/pulls/$number/comments',
        ...ghRowPerLine,
      ]);
      return parsePrInlineComments(decodeGhRows(out));
    } catch (e) {
      debugPrint('comentários do PR #$number não lidos — $e');
      return const [];
    }
  }

  /// "Trazer e começar" (R3, R4): fetches the PR's head, creates its
  /// worktree (copying and preparing it like a spec's), and starts the
  /// session with the PR's context. Returns the session id.
  Future<String> bring(
    Workspace ws,
    PrImportCandidate candidate, {
    PrStart start = PrStart.resumir,
    String request = '',
    bool replyInPr = false,
  }) async {
    final a = await _require(ws);
    final pr = candidate.pr;
    if (candidate.alreadyIn) {
      throw const PrImportException('Esse PR já está no app.');
    }
    final remote = a.remote!;
    final root = _git(ws.path);
    final n = pr.number;
    final branch = candidate.localBranch;
    String? upstream;
    try {
      await root.git(['fetch', '-q', remote, '+pull/$n/head:${prLocalRef(n)}']);
      if (!pr.isCrossRepository) {
        await root.git([
          'fetch',
          '-q',
          remote,
          '+refs/heads/${pr.headRefName}:refs/remotes/$remote/${pr.headRefName}',
        ]);
        upstream = '$remote/${pr.headRefName}';
      }
      if (pr.baseRefName.isNotEmpty) {
        try {
          await root.git(['fetch', '-q', remote, '--', pr.baseRefName]);
        } on GitException catch (e) {
          debugPrint('base ${pr.baseRefName} não buscada — $e');
        }
      }
    } on GitException catch (e) {
      throw PrImportException('Não foi possível buscar o PR #$n: $e');
    }
    final CreatedWorktree wt;
    try {
      wt = await root.addWorktreeAt(
        'pr-$n',
        prLocalRef(n),
        branch: branch,
        upstream: upstream,
      );
    } on GitException catch (e) {
      throw PrImportException('Falha ao criar o worktree: $e');
    }
    final manager = _ref.read(sessionManagerProvider.notifier);
    Future<void> undo() async {
      try {
        await root.removeWorktree(wt.path, force: true);
      } on GitException catch (e) {
        debugPrint('worktree ${wt.path} não removido — $e');
      }
      try {
        await root.deleteBranch(wt.branch, force: true);
      } on GitException catch (e) {
        debugPrint('branch ${wt.branch} não removida — $e');
      }
    }

    try {
      await manager.setupWorktree(ws.path, wt);
    } on GitException catch (e) {
      throw PrImportException('Falha ao preparar o worktree: $e');
    }
    final stat = await _diffStat(wt.path, remote, pr.baseRefName);
    final comments = await openComments(ws, n);
    final message = prContextMessage(
      pr: pr,
      start: start,
      canPush: candidate.canPush,
      diffStat: stat,
      comments: comments,
      request: request,
    );
    final meta = ImportedPr(
      number: n,
      url: pr.url,
      title: pr.title,
      author: pr.author,
      headRef: pr.headRefName,
      baseRef: pr.baseRefName,
      cross: pr.isCrossRepository,
      canPush: candidate.canPush,
      remote: remote,
      pushTo: pr.isCrossRepository && a.remoteUrl != null
          ? forkRemoteUrl(a.remoteUrl!, pr.headOwner)
          : null,
      replyInPr: replyInPr,
      pendingReplies: start == PrStart.comentarios && replyInPr
          ? [for (final c in comments) ?c.externalId]
          : const [],
    );
    final String id;
    try {
      id = await manager.create(
        NewSessionRequest(
          workspace: ws,
          title: 'PR #$n · ${pr.title}',
          prompt: message,
          worktreePath: wt.path,
          branch: wt.branch,
          baseBranch: pr.baseRefName.isEmpty ? null : pr.baseRefName,
          prUrl: pr.url,
          permissionMode: start == PrStart.resumir
              ? ClaudePermissionMode.plan
              : ClaudePermissionMode.defaultMode,
          origin: 'PR #$n de @${pr.author} trazido para o app.',
        ),
      );
    } on Object {
      await undo();
      rethrow;
    }
    final settings = _ref.read(appSettingsProvider.notifier);
    await settings.set(ImportedPr.key(id), meta.encode());
    await settings.set(replyInPrKey(ws.id), replyInPr ? '1' : '0');
    return id;
  }

  /// `git diff --stat` of the worktree against the PR's base (its copy on
  /// [remote] when there is one).
  Future<String> _diffStat(String worktree, String remote, String base) async {
    if (base.isEmpty) return '';
    final git = _git(worktree);
    final ref = await git.resolveRef('refs/remotes/$remote/$base') != null
        ? '$remote/$base'
        : base;
    try {
      return (await git.git(['diff', '--stat', '$ref...HEAD'])).trim();
    } on GitException catch (e) {
      debugPrint('diff --stat contra $ref falhou — $e');
      return '';
    }
  }
}

/// The URL of [owner]'s fork from the URL of the base repository
/// (`git@github.com:o/r.git` → `git@github.com:owner/r.git`).
String? forkRemoteUrl(String baseUrl, String owner) {
  if (owner.isEmpty) return null;
  final ssh = RegExp(r'^([^@/\s]+@[^:]+:)([^/]+)/(.+)$').firstMatch(baseUrl);
  if (ssh != null) return '${ssh.group(1)}$owner/${ssh.group(3)}';
  final uri = Uri.tryParse(baseUrl);
  if (uri == null || !uri.hasAuthority || uri.pathSegments.length < 2) {
    return null;
  }
  return uri
      .replace(pathSegments: [owner, ...uri.pathSegments.skip(1)])
      .toString();
}

final prImportServiceProvider = Provider(PrImportService.new);

/// "Trazer PR" of a workspace (the button of the Review, R1, R10).
final prImportAvailabilityProvider =
    FutureProvider.family<PrImportAvailability, Workspace>(
      (ref, ws) => ref.read(prImportServiceProvider).availability(ws),
    );
