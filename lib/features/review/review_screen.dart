import 'dart:async';

import '../../core/fs/dir_watcher.dart';

import 'dart:io';

import '../project/project_config.dart';
import 'merge_options.dart';
import 'merge_readiness.dart';
import 'comment_anchor.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/git/diff_parser.dart';
import '../../core/git/git_service.dart' show GitLogEntry;
import '../../data/providers.dart';
import '../../ui/shell/navigation.dart';
import '../../ui/theme/tokens.dart';
import '../sessions/session_manager.dart';
import '../agents/widgets/agent_style.dart' show ToggleBox;
import '../sessions/widgets/session_style.dart';
import 'auto_reviewer.dart';
import 'pr_babysitter.dart';
import '../specs/spec_service.dart';
import 'review_service.dart';
import 'widgets/spec_review_panel.dart';
import 'widgets/review_diff_view.dart';
import 'widgets/pr_panel.dart';
import 'widgets/review_all_files.dart';
import 'widgets/review_dialogs.dart';
import 'widgets/persisted_comment.dart';

/// Review screen (docs/mockups/Review.dc.html, plano Fase 9): "Aguardando
/// review" + changed files on the left; header with the actions and the
/// diff of the selected file on the right. Only inner panels scroll.
class ReviewScreen extends ConsumerWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(activeWorkspaceProvider);
    if (ws == null) {
      return const _Empty(
        title: 'Nenhum workspace',
        text: 'Selecione ou adicione um workspace na barra de título.',
      );
    }
    final queueAsync = ref.watch(reviewQueueProvider(ws.id));
    final queue = queueAsync.value ?? const <ReviewItem>[];
    final selectedId = ref.watch(selectedReviewProvider);
    ReviewItem? selected;
    for (final i in queue) {
      if (i.session.id == selectedId) selected = i;
    }
    selected ??= queue.isEmpty ? null : queue.first;
    final detail = selected == null
        ? null
        : ref.watch(reviewDetailProvider(selected.session.id)).value;

    return LayoutBuilder(
      builder: (context, c) {
        final left = c.maxWidth < 1100 ? 250.0 : 280.0;
        return ColoredBox(
          color: AppColors.background,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: left,
                child: _ReviewSidebar(
                  queue: queue,
                  loading: queueAsync.isLoading && queueAsync.value == null,
                  selectedId: selected?.session.id,
                  detail: detail?.session.id == selected?.session.id
                      ? detail
                      : null,
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: selected == null
                    ? _Empty(
                        title: queueAsync.isLoading
                            ? 'Carregando…'
                            : 'Nada aguardando review',
                        text:
                            'Sessões concluídas com alterações no worktree '
                            '(ou tarefas em Review) aparecem aqui.',
                      )
                    : _ReviewMain(
                        key: ValueKey('review-main-${selected.session.id}'),
                        item: selected,
                        workspaceId: ws.id,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.background,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// File shown in the diff (null = first file).
class _SelectedFile extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? path) => state = path;
}

final _selectedFileProvider = NotifierProvider<_SelectedFile, String?>(
  _SelectedFile.new,
);

/// How the diff is shown (kept while switching items).
@immutable
class ReviewView {
  const ReviewView({
    this.allFiles = true,
    this.sideBySide = false,
    this.commentsVisible = true,
    this.onlyOpen = true,
    this.sources = const {'humano', 'revisor', 'pr'},
  });
  final bool commentsVisible, onlyOpen;
  final Set<String> sources;
  ReviewView copyWith({
    bool? allFiles,
    bool? sideBySide,
    bool? commentsVisible,
    bool? onlyOpen,
    Set<String>? sources,
  }) => ReviewView(
    allFiles: allFiles ?? this.allFiles,
    sideBySide: sideBySide ?? this.sideBySide,
    commentsVisible: commentsVisible ?? this.commentsVisible,
    onlyOpen: onlyOpen ?? this.onlyOpen,
    sources: sources ?? this.sources,
  );

  /// Every file in one page (the file list scrolls to the file).
  final bool allFiles;
  final bool sideBySide;
}

class _ReviewViewNotifier extends Notifier<ReviewView> {
  @override
  ReviewView build() => const ReviewView();

  void set(ReviewView v) => state = v;
}

final reviewViewProvider = NotifierProvider<_ReviewViewNotifier, ReviewView>(
  _ReviewViewNotifier.new,
);

/// Commits of the item by step (the "Etapa" filter).
final stepCommitsProvider =
    FutureProvider.family<Map<String, List<GitLogEntry>>, String>(
      (ref, sessionId) =>
          ref.read(reviewServiceProvider).stepCommits(sessionId),
    );

/// Diff of the commits of one step of the item.
final reviewStepDetailProvider =
    FutureProvider.family<ReviewDetail, (String, String)>(
      (ref, key) => ref.read(reviewServiceProvider).loadStep(key.$1, key.$2),
    );

/// Above this many diff lines, "Todos os arquivos" falls back to one file
/// at a time (the page builds every line).
const allFilesMaxLines = 4000;

DiffFile? _fileOf(ReviewDetail? d, String? path) {
  if (d == null || d.files.isEmpty) return null;
  for (final f in d.files) {
    if (f.path == path) return f;
  }
  return d.files.first;
}

class _SinceSelection extends Notifier<(String, int, String)?> {
  @override
  (String, int, String)? build() => null;
  void select((String, int, String)? value) => state = value;
}

final _sinceSelectionProvider =
    NotifierProvider<_SinceSelection, (String, int, String)?>(
      _SinceSelection.new,
    );

class _ReviewSidebar extends ConsumerWidget {
  const _ReviewSidebar({
    required this.queue,
    required this.loading,
    required this.selectedId,
    required this.detail,
  });

  final List<ReviewItem> queue;
  final bool loading;
  final String? selectedId;
  final ReviewDetail? detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = _fileOf(detail, ref.watch(_selectedFileProvider));
    final files = detail?.files ?? const <DiffFile>[];
    final since = ref.watch(_sinceSelectionProvider);
    final sinceDetail = since == null || since.$1 != selectedId
        ? null
        : ref.watch(reviewSinceProvider((since.$1, since.$3))).value;
    final changedPaths = sinceDetail?.files.map((f) => f.path).toSet();
    final specId = detail?.session.specId;
    final rows = specId == null
        ? <ReviewCommentRow>[]
        : ref.watch(reviewCommentsProvider(specId)).value ??
              <ReviewCommentRow>[];
    return ColoredBox(
      color: AppColors.panel,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Text(
              'AGUARDANDO REVIEW · ${queue.length}',
              key: const ValueKey('review-queue-title'),
              style: sectionTitleStyle,
            ),
          ),
          if (queue.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                loading ? 'Verificando worktrees…' : 'Nenhuma sessão.',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          for (final i in queue)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
              child: _QueueTile(
                item: i,
                selected: i.session.id == selectedId,
                onTap: () {
                  ref
                      .read(selectedReviewProvider.notifier)
                      .select(i.session.id);
                  ref.read(_selectedFileProvider.notifier).select(null);
                },
              ),
            ),
          if (detail != null) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: Text(
                'ARQUIVOS · ${files.length}',
                key: const ValueKey('review-files-title'),
                style: sectionTitleStyle,
              ),
            ),
            for (final f in files)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
                child: _FileTile(
                  file: f,
                  unchanged:
                      changedPaths != null && !changedPaths.contains(f.path),
                  openComments: rows
                      .where((c) => !c.resolved && c.path == f.path)
                      .length,
                  selected: identical(f, current),
                  onTap: () {
                    ref.read(_selectedFileProvider.notifier).select(f.path);
                    ref.read(reviewScrollTargetProvider.notifier)
                      ..go(null)
                      ..go(f.path);
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _QueueTile extends ConsumerWidget {
  const _QueueTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final ReviewItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = item.session;
    final complete = selected
        ? ref.watch(mergeReadinessProvider(s.id)).value
        : null;
    final pending = item.spec == null
        ? null
        : ref.watch(pendingCriteriaProvider(item.spec!.id));
    final peers = ref.watch(specsProvider(s.workspaceId)).value ?? <Spec>[];
    final stacked = peers.any(
      (p) =>
          p.id != item.spec?.id &&
          p.branch == s.baseBranch &&
          p.branch != null &&
          p.stage != SpecStage.done,
    );
    final workspace = ref.watch(activeWorkspaceProvider);
    final blocked =
        item.spec?.reviewPhase == ReviewPhase.auto ||
        s.status == SessionStatus.merged ||
        stacked ||
        (pending?.hasError ?? false) ||
        (pending?.value?.isNotEmpty ?? false) ||
        s.worktreePath == workspace?.path ||
        !Directory(s.worktreePath).existsSync();
    final color = complete == null
        ? (blocked ? AppColors.red : AppColors.amber)
        : switch (complete.level) {
            ReadinessLevel.ok => AppColors.teal,
            ReadinessLevel.bloqueio => AppColors.red,
            _ => AppColors.amber,
          };
    final meta = [
      if (item.spec != null)
        item.spec!.code
      else if (item.task != null)
        item.task!.code,
      s.agentName?.isNotEmpty ?? false ? s.agentName! : 'sem agente',
    ].join(' · ');
    final radius = BorderRadius.circular(8);
    return Material(
      color: selected ? SessionColors.selectedBg : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: selected ? SessionColors.selectedBorder : Colors.transparent,
        ),
      ),
      child: InkWell(
        key: ValueKey('review-item-${s.id}'),
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Tooltip(
                message:
                    complete?.summary ??
                    'Estado parcial: não verificado por completo',
                child: Icon(
                  complete == null ? Icons.circle_outlined : Icons.circle,
                  color: color,
                  size: 9,
                ),
              ),
              Text(
                sessionTitle(s),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    this.openComments = 0,
    this.unchanged = false,
    required this.file,
    required this.selected,
    required this.onTap,
  });

  final bool unchanged;
  final int openComments;
  final DiffFile file;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const mono = TextStyle(fontFamily: AppFonts.mono, fontSize: 12);
    final (add, del) = fileStats(file);
    final radius = BorderRadius.circular(6);
    return Material(
      color: selected ? SessionColors.selectedBg : Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        key: ValueKey('review-file-${file.path}'),
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                child: Text(
                  fileStatusLetter(file.status),
                  style: mono.copyWith(color: statusColor(file.status)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Tooltip(
                  message: file.path,
                  waitDuration: const Duration(milliseconds: 600),
                  child: Text(
                    file.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono.copyWith(color: AppColors.text),
                  ),
                ),
              ),
              if (unchanged)
                const Text(
                  'sem alterações',
                  style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                ),
              if (openComments > 0)
                Text(
                  ' · $openComments abertos',
                  style: mono.copyWith(color: AppColors.amber),
                ),
              if (add > 0) ...[
                const SizedBox(width: 6),
                Text('+$add', style: mono.copyWith(color: AppColors.teal)),
              ],
              if (del > 0) ...[
                const SizedBox(width: 6),
                Text('−$del', style: mono.copyWith(color: AppColors.red)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewMain extends ConsumerStatefulWidget {
  const _ReviewMain({super.key, required this.item, required this.workspaceId});

  final ReviewItem item;
  final int workspaceId;

  @override
  ConsumerState<_ReviewMain> createState() => _ReviewMainState();
}

class _ReviewMainState extends ConsumerState<_ReviewMain> {
  CommentTarget? _target;
  String? _busy;
  DirWatcher? _repositoryWatcher;

  /// Step whose commits are shown (null = the whole branch).
  String? _step;
  ReviewCommentRow? _since;
  final _selectedComments = <int>{};
  bool get _commentsVisible => ref.read(reviewViewProvider).commentsVisible;
  bool get _onlyOpen => ref.read(reviewViewProvider).onlyOpen;
  Set<String> get _sources => ref.read(reviewViewProvider).sources;
  void _filter({bool? visible, bool? onlyOpen, Set<String>? sources}) => ref
      .read(reviewViewProvider.notifier)
      .set(
        ref
            .read(reviewViewProvider)
            .copyWith(
              commentsVisible: visible,
              onlyOpen: onlyOpen,
              sources: sources,
            ),
      );

  void _update(VoidCallback action) => setState(action);

  void _selectComment(int id, bool value) => setState(() {
    if (value) {
      _selectedComments.add(id);
    } else {
      _selectedComments.remove(id);
    }
  });

  List<AnchoredComment> _persisted(List<DiffFile> files) {
    final spec = widget.item.spec;
    if (spec == null || !_commentsVisible) return [];
    final rows = ref.watch(reviewCommentsProvider(spec.id)).value ?? [];
    final shifts = ref.watch(reviewAnchorProvider((_id, spec.id))).value ?? {};
    return [
      for (final c in rows)
        if ((!_onlyOpen || !c.resolved) && _sources.contains(c.author))
          anchorOf(c, files.where((f) => f.path == c.path).firstOrNull, shifts),
    ];
  }

  /// The last "Fazer merge" stopped on a conflict.
  bool _conflict = false;

  String get _id => widget.item.session.id;

  ReviewService get _service => ref.read(reviewServiceProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_observeRepository());
    // "Ver diff da etapa" (Specs, U5) opens the item on that step; the
    // provider is cleared after this frame (no writes during build).
    _step = ref.read(reviewInitialStepProvider);
    if (_step != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(reviewInitialStepProvider.notifier).set(null);
      });
    }
  }

  Future<void> _observeRepository() async {
    final watcher = await _service.watchRepositories(_id, () {
      if (mounted && _busy == null) _refresh();
    });
    if (!mounted) {
      await watcher?.close();
      return;
    }
    _repositoryWatcher = watcher;
  }

  @override
  void dispose() {
    unawaited(_repositoryWatcher?.close());
    super.dispose();
  }

  void _toast(String msg, {SnackBarAction? action}) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          persist: false,
          duration: const Duration(seconds: 8),
          action: action,
        ),
      );
  }

  Future<void> _run(String label, Future<void> Function() job) async {
    if (_busy != null) return;
    setState(() => _busy = label);
    try {
      await job();
    } on ReviewException catch (e) {
      if (e.message.startsWith('Conflito ao fazer merge')) {
        setState(() => _conflict = true);
      }
      if (mounted) {
        await showReviewError(
          context,
          label,
          e.message,
          onResolve: e is MergeConflictException
              ? () => _service.resolveConflict(_id)
              : null,
        );
      }
    } catch (e) {
      if (mounted) await showReviewError(context, label, '$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _selectStep(String? step) => setState(() {
    _step = step;
    _since = null;
    ref.read(_sinceSelectionProvider.notifier).select(null);
    _target = null;
  });

  /// File of [_target] (the page with every file has several).
  String? _targetPath;

  void _setTarget(CommentTarget? t, [String? path]) => setState(() {
    _target = t;
    _targetPath = path;
  });

  void _refresh() {
    ref.invalidate(mergeReadinessProvider(_id));
    ref.invalidate(reviewSinceProvider);
    ref.invalidate(reviewRoundAvailabilityProvider);
    ref.invalidate(reviewDetailProvider(_id));
    ref.invalidate(reviewQueueProvider(widget.workspaceId));
    ref.invalidate(prAvailabilityProvider(_id));
  }

  Future<void> _reject(DiffFile f, DiffHunk h) =>
      _run('Rejeitar hunk', () async {
        await _service.rejectHunk(_id, f, h);
        setState(() => _target = null);
        ref.invalidate(reviewDetailProvider(_id));
        _toast(
          'Hunk rejeitado em ${f.path} (alteração não commitada no worktree).',
        );
      });

  Future<void> _requestChanges() async {
    final comments = ref.read(reviewDraftProvider(_id)).comments;
    final selectedRows = widget.item.spec == null
        ? <ReviewCommentRow>[]
        : (ref.read(reviewCommentsProvider(widget.item.spec!.id)).value ??
                  <ReviewCommentRow>[])
              .where((c) => _selectedComments.contains(c.id) && !c.resolved)
              .toList();
    final preview = [
      ...comments,
      for (final c in selectedRows)
        ReviewComment(
          path: c.path ?? 'Geral',
          line: c.line ?? 0,
          text:
              '[${c.author}, rodada ${c.round}] ${c.body.substring(0, c.body.length.clamp(0, 4000))}',
          snippet: const [],
        ),
    ];
    final note = await showAdjustDialog(context, preview);
    if (note == null || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final id = _id;
    await _run('Pedir ajustes ao agente', () async {
      await _service.requestChanges(
        _id,
        comments,
        note: note,
        selected: selectedRows,
      );
      _selectedComments.clear();
      ref.read(reviewDraftProvider(_id).notifier).clearComments();
      _refresh();
      _toast(
        'Ajustes enviados à sessão; a tarefa voltou para Em execução.',
        action: SnackBarAction(
          label: 'Ver sessão',
          onPressed: () {
            messenger?.hideCurrentSnackBar();
            container.read(selectedSessionProvider.notifier).select(id);
            container.read(navigationProvider.notifier).go(AppSection.sessions);
          },
        ),
      );
    });
  }

  Future<void> _createPr({bool draft = false}) =>
      _run(draft ? 'Criar PR rascunho' : 'Criar PR', () async {
        final url = await _service.createPr(_id, draft: draft);
        _refresh();
        if (!mounted) return;
        await showPrCreatedDialog(
          context,
          url: url,
          onOpen: () => _service.openUrl(url),
        );
      });

  Future<void> _merge(ReviewDetail d, {List<String> pending = const []}) async {
    String? override;
    if (pending.isNotEmpty) {
      override = await showMergeOverrideDialog(context, pending);
      if (override == null || !mounted) return;
    }
    final ws = await ref
        .read(workspacesRepoProvider)
        .getById(widget.workspaceId);
    final config = ws == null
        ? const ProjectConfig()
        : await ref.read(projectConfigProvider(ws.path).future);
    final prediction = await _service.predictConflict(_id);
    if (!mounted) return;
    var options = const MergeOptions();
    final deleteBranch = await showMergeDialog(
      context,
      branch: d.session.branch,
      base: d.baseBranch,
      uncommitted: d.uncommitted,
      published: d.session.prUrl != null,
      initialMethod: MergeMethod.values.firstWhere(
        (m) => m.name == config.mergeMethod,
        orElse: () => MergeMethod.merge,
      ),
      onOptions: (v) => options = v,
      warnings: [
        if (prediction.error != null)
          'Conflito previsto: não verificado · ${prediction.error}',
        if (prediction.files.isNotEmpty)
          'Conflito previsto: ${prediction.files.join(', ')}',
        'A previsão não inclui pendências e é aproximada para rebase.',
        ...ref
                .read(mergeReadinessProvider(_id))
                .value
                ?.warnings
                .map((i) => i.detail)
                .toList() ??
            [],
      ],
    );
    if (deleteBranch == null || !mounted) return;
    await _run('Fazer merge', () async {
      final r = await _service.merge(
        _id,
        deleteBranch: deleteBranch,
        options: options,
        override: override,
      );
      ref.read(selectedReviewProvider.notifier).select(null);
      _refresh();
      final short = r.commit.length > 7 ? r.commit.substring(0, 7) : r.commit;
      _toast(
        'Merge concluído · $short'
        '${r.warnings.isEmpty ? '' : ' (${r.warnings.join('; ')})'}',
      );
    });
  }

  VoidCallback? _readinessAction(String id) => switch (id) {
    'revisor' =>
      widget.item.spec == null
          ? null
          : () => ref.read(autoReviewerProvider).skip(widget.item.spec!.id),
    'pr' => () => _run(
      'Verificar PR',
      () => ref.read(prBabysitterProvider.notifier).check(_id),
    ),
    'comentarios' => () {
      _filter(visible: true, onlyOpen: true);
      ref
          .read(reviewViewProvider.notifier)
          .set(ref.read(reviewViewProvider).copyWith(allFiles: true));
    },
    'criterios' || 'verificacoes' => () {
      if (widget.item.spec != null) {
        ref.read(selectedSpecProvider.notifier).select(widget.item.spec!.id);
        ref.read(navigationProvider.notifier).go(AppSection.specs);
      }
    },
    'empilhada' => () async {
      final items = await ref.read(
        reviewQueueProvider(widget.workspaceId).future,
      );
      final base = ref.read(reviewDetailProvider(_id)).value?.baseBranch;
      final dependency = items
          .where((i) => i.session.branch == base)
          .firstOrNull;
      if (dependency != null) {
        ref.read(selectedReviewProvider.notifier).select(dependency.session.id);
      }
    },
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(reviewDetailProvider(_id));
    final d = async.value;
    final draft = ref.watch(reviewDraftProvider(_id));
    final pr = ref.watch(prAvailabilityProvider(_id)).value;
    final file = _fileOf(d, ref.watch(_selectedFileProvider));
    final s = d?.session ?? widget.item.session;
    final busy = _busy != null;

    final prReason = pr == null
        ? 'Identificando hospedeiro e ferramenta…'
        : pr.available
        ? (s.prUrl != null
              ? 'PR já criado: ${s.prUrl}'
              : 'Destino: ${pr.hostname} · ${pr.remote}. Commita pendências e envia a branch para criar ${pr.requestLabel}.')
        : pr.reason ?? 'Indisponível';
    final canPr = !busy && d?.error == null && (pr?.available ?? false);
    final reviewing =
        widget.item.spec?.reviewPhase == ReviewPhase.auto &&
        widget.item.spec?.stage == SpecStage.review;
    final readiness = ref.watch(mergeReadinessProvider(_id));
    final ready = readiness.value;
    final canMerge =
        !busy &&
        d != null &&
        d.error == null &&
        !reviewing &&
        ready != null &&
        !readiness.isLoading &&
        !readiness.hasError &&
        ready.blockers.isEmpty;
    final pending = widget.item.spec == null
        ? const <String>[]
        : ref.watch(pendingCriteriaProvider(widget.item.spec!.id)).value ??
              const <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.spec != null
                          ? widget.item.spec!.title
                          : widget.item.task != null
                          ? widget.item.task!.title
                          : sessionTitle(s),
                      key: const ValueKey('review-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _Subtitle(detail: d, branch: s.branch, busy: _busy),
                    if (s.specId != null)
                      Text(
                        '${(ref.watch(reviewCommentsProvider(s.specId!)).value ?? <ReviewCommentRow>[]).where((c) => !c.resolved).length} comentários abertos',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.amber,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: SmallButton(
                  key: const ValueKey('review-request-changes'),
                  label: draft.comments.isEmpty
                      ? 'Pedir ajustes ao agente'
                      : 'Pedir ajustes ao agente (${draft.comments.length})',
                  onTap: busy || s.status == SessionStatus.merged
                      ? null
                      : _requestChanges,
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                key: const ValueKey('review-create-pr-tooltip'),
                message: prReason,
                child: SmallButton(
                  key: const ValueKey('review-create-pr'),
                  label: s.prUrl != null
                      ? '${pr?.requestLabel ?? 'PR'} criado'
                      : 'Criar ${pr?.requestLabel ?? 'PR'}',
                  onTap: canPr ? _createPr : null,
                ),
              ),
              if (s.prUrl == null) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Criar PR como rascunho (gh pr create --draft)',
                  child: SmallButton(
                    key: const ValueKey('review-create-pr-draft'),
                    label: 'Rascunho',
                    onTap: canPr ? () => _createPr(draft: true) : null,
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Tooltip(
                message: ready?.blockers.isNotEmpty == true
                    ? ready!.blockers.map((i) => i.detail).join('\n')
                    : reviewing
                    ? 'O revisor automático ainda está revisando'
                    : pending.isEmpty
                    ? ''
                    : 'Critérios de aceite sem marcar: ${pending.length}',
                child: AmberButton(
                  key: const ValueKey('review-merge'),
                  label: 'Fazer merge',
                  onTap: canMerge ? () => _merge(d, pending: pending) : null,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: prReason,
                  child: Text(
                    pr == null
                        ? 'Verificando hospedagem…'
                        : '${pr.host == 'github'
                                  ? 'GitHub · gh'
                                  : pr.host == 'gitlab'
                                  ? 'GitLab · glab'
                                  : 'Hospedagem não identificada'}'
                              '${pr.hostname == null ? '' : ' · ${pr.hostname}'}'
                              '${pr.remote == null ? '' : ' · ${pr.remote}'}'
                              '${pr.available ? '' : ' · ${pr.reason ?? 'Não verificado'}'}',
                    key: const ValueKey('review-host'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
              if (pr?.installUrl != null)
                TextButton(
                  key: const ValueKey('review-install-cli'),
                  onPressed: () => _service.openUrl(pr!.installUrl!),
                  child: const Text('Instalar / atualizar CLI'),
                ),
              if (pr?.remotes.isNotEmpty == true)
                DropdownButton<String>(
                  hint: const Text('Escolher remote'),
                  items: [
                    for (final name in pr!.remotes)
                      DropdownMenuItem(value: name, child: Text(name)),
                  ],
                  onChanged: busy
                      ? null
                      : (name) async {
                          if (name != null) {
                            await ref
                                .read(appSettingsProvider.notifier)
                                .set('review.remote.$_id', name);
                          }
                        },
                ),
              IconButton(
                key: const ValueKey('review-host-details'),
                tooltip: 'Ver diagnóstico da hospedagem',
                iconSize: 16,
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Hospedagem do projeto'),
                    content: SelectableText(prReason),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Fechar'),
                      ),
                    ],
                  ),
                ),
                icon: const Icon(Icons.info_outline),
              ),
              IconButton(
                key: const ValueKey('review-check-host'),
                tooltip: 'Verificar novamente',
                iconSize: 16,
                onPressed: busy ? null : _refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        if (!busy && ready?.canOverride == true && d != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _merge(d, pending: pending),
              child: const Text('Mergear mesmo assim…'),
            ),
          ),
        if (!busy &&
            d != null &&
            ready != null &&
            ready.blockers.isNotEmpty &&
            ready.blockers.every(
              (i) => i.id == 'raiz' && i.level != ReadinessLevel.naoVerificado,
            ))
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _merge(d),
              child: const Text('Preparar merge local…'),
            ),
          ),
        Material(
          color: Colors.transparent,
          child: ExpansionTile(
            title: Text(
              readiness.isLoading
                  ? 'Verificando merge…'
                  : ready?.summary ?? 'Não verificado',
            ),
            subtitle: const Text('Pronto para merge?'),
            children: [
              if (readiness.hasError)
                Text('Não verificado: ${readiness.error}'),
              for (final i in ready?.items ?? <ReadinessItem>[])
                ListTile(
                  dense: true,
                  title: Text(i.label),
                  subtitle: Text('${i.level.name} · ${i.detail}'),
                  trailing: i.action == null
                      ? null
                      : TextButton(
                          onPressed: _readinessAction(i.id),
                          child: Text(i.action!),
                        ),
                ),
              TextButton(
                onPressed: _refresh,
                child: const Text('Verificar de novo'),
              ),
            ],
          ),
        ),
        PrPanel(session: s, localConflict: _conflict),
        if (widget.item.spec != null)
          SpecReviewPanel(
            specId: widget.item.spec!.id,
            sessionId: _id,
            prUrl: s.prUrl,
          ),
        _toolbar(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: _since != null
                ? _sinceBody()
                : _step == null
                ? _body(async, d, file, draft, busy)
                : _stepBody(),
          ),
        ),
      ],
    );
  }
}

extension on _ReviewMainState {
  Widget _message(String text, {Color color = AppColors.textSecondary}) =>
      Center(
        child: SelectableText(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: color, fontSize: 12),
        ),
      );

  Widget _body(
    AsyncValue<ReviewDetail> async,
    ReviewDetail? d,
    DiffFile? file,
    ReviewDraft draft,
    bool busy,
  ) {
    if (d == null) {
      return async.hasError
          ? _message('${async.error}', color: AppColors.red)
          : _message('Carregando diff…');
    }
    if (d.error != null) return _message(d.error!, color: AppColors.red);
    if (file == null) {
      final persisted = _persisted(d.files);
      if (persisted.isNotEmpty) {
        return ReviewAllFiles(
          files: d.files,
          draft: draft,
          persisted: persisted,
          selected: _selectedComments,
          onSelectComment: _selectComment,
        );
      }
      return _message('Nenhuma alteração em relação à branch base.');
    }
    final notifier = ref.read(reviewDraftProvider(_id).notifier);
    final view = ref.watch(reviewViewProvider);
    final lines = d.files.fold(0, (n, f) => n + diffLineCount(f));
    if (view.allFiles && lines <= allFilesMaxLines) {
      return ReviewAllFiles(
        files: d.files,
        persisted: _persisted(d.files),
        selected: _selectedComments,
        onSelectComment: _selectComment,
        sideBySide: view.sideBySide,
        draft: draft,
        target: _target,
        busy: busy,
        onOpenComment: (f, t) => _setTarget(t, f.path),
        onCancelComment: () => _setTarget(null),
        onSubmitComment: (f, t, text) {
          notifier.addComment(commentFor(f, f.hunks[t.$1], t.$2, text));
          _setTarget(null);
        },
        onRemoveComment: notifier.removeComment,
        onRejectHunk: _reject,
        onToggleAccept: (f, h) => notifier.toggleAccepted(hunkKey(f, h)),
        targetPath: _targetPath,
      );
    }
    final diff = ReviewFileDiff(
      key: ValueKey('review-file-diff-${file.path}'),
      persisted: _persisted(d.files)
          .where((c) => c.row.path == file.path)
          .toList(),
      selected: _selectedComments,
      onSelectComment: _selectComment,
      sideBySide: view.sideBySide,
      file: file,
      comments: [
        for (final c in draft.comments)
          if (c.path == file.path) c,
      ],
      accepted: draft.accepted,
      commentTarget: _target,
      busy: busy,
      onOpenComment: (t) => _setTarget(t),
      onCancelComment: () => _setTarget(null),
      onSubmitComment: (t, text) {
        notifier.addComment(commentFor(file, file.hunks[t.$1], t.$2, text));
        _setTarget(null);
      },
      onRemoveComment: notifier.removeComment,
      onRejectHunk: (h) => _reject(file, h),
      onToggleAccept: (h) => notifier.toggleAccepted(hunkKey(file, h)),
    );
    final general = _persisted(d.files)
        .where(
          (c) =>
              c.row.path == null || !d.files.any((f) => f.path == c.row.path),
        )
        .toList();
    if (general.isEmpty) return diff;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Geral'),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 160),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final c in general)
                PersistedComment(
                  comment: c,
                  selected: _selectedComments.contains(c.row.id),
                  onSelected: (v) => _selectComment(c.row.id, v),
                ),
            ],
          ),
        ),
        Expanded(child: diff),
      ],
    );
  }
}

extension on _ReviewMainState {
  Widget _toolbar() {
    final view = ref.watch(reviewViewProvider);
    final notifier = ref.read(reviewViewProvider.notifier);
    final steps = widget.item.spec == null
        ? const <String, List<GitLogEntry>>{}
        : ref.watch(stepCommitsProvider(_id)).value ??
              const <String, List<GitLogEntry>>{};
    Widget toggle(String key, String label, bool on, VoidCallback tap) =>
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: ToggleBox(
            key: ValueKey(key),
            on: on,
            height: 26,
            onTap: tap,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: on ? AppColors.amber : AppColors.textSecondary,
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              toggle(
                'review-view-one',
                'Um arquivo',
                !view.allFiles,
                () => notifier.set(view.copyWith(allFiles: false)),
              ),
              toggle(
                'review-view-all',
                'Todos os arquivos',
                view.allFiles,
                () => notifier.set(view.copyWith(allFiles: true)),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              toggle(
                'review-view-unified',
                'Unificado',
                !view.sideBySide,
                () => notifier.set(view.copyWith(sideBySide: false)),
              ),
              toggle(
                'review-view-split',
                'Lado a lado',
                view.sideBySide,
                () => notifier.set(view.copyWith(sideBySide: true)),
              ),
            ],
          ),
          FilterChip(
            label: const Text('Comentários'),
            selected: _commentsVisible,
            onSelected: (v) => _filter(visible: v),
          ),
          FilterChip(
            label: const Text('Só abertos'),
            selected: _onlyOpen,
            onSelected: (v) => _filter(onlyOpen: v),
          ),
          for (final source in ['humano', 'revisor', 'pr'])
            FilterChip(
              label: Text(source == 'humano' ? 'Você' : source),
              selected: _sources.contains(source),
              onSelected: (v) => _filter(
                sources: v
                    ? {..._sources, source}
                    : ({..._sources}..remove(source)),
              ),
            ),
          if (widget.item.spec != null) _roundFilter(),
          if (steps.isNotEmpty)
            DropdownButton<String?>(
              key: const ValueKey('review-step-filter'),
              value: steps.containsKey(_step) ? _step : null,
              isDense: true,
              underline: const SizedBox.shrink(),
              style: const TextStyle(fontSize: 12, color: AppColors.text),
              dropdownColor: AppColors.panel,
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Todas as etapas'),
                ),
                for (final MapEntry(:key, :value) in steps.entries)
                  DropdownMenuItem<String?>(
                    value: key,
                    child: Text(
                      '$key · ${value.length} commit(s)',
                      key: ValueKey('review-step-$key'),
                    ),
                  ),
              ],
              onChanged: _selectStep,
            ),
        ],
      ),
    );
  }

  Widget _roundFilter() {
    final rows =
        ref.watch(reviewCommentsProvider(widget.item.spec!.id)).value ?? [];
    final rounds = <int, ReviewCommentRow>{};
    for (final c in rows) {
      rounds.putIfAbsent(c.round, () => c);
    }
    final sorted = rounds.values.toList()
      ..sort((a, b) => b.round.compareTo(a.round));
    if (sorted.isEmpty) return const SizedBox.shrink();
    final reasons = {
      for (final c in sorted)
        c.round: ref.watch(reviewRoundAvailabilityProvider((_id, c.commitSha))),
    };
    final latest = sorted
        .where(
          (c) => reasons[c.round]!.hasValue && reasons[c.round]!.value == null,
        )
        .firstOrNull;
    void choose(ReviewCommentRow? c) => _update(() {
      _since = c;
      ref
          .read(_sinceSelectionProvider.notifier)
          .select(c == null ? null : (_id, c.round, c.commitSha!));
      _step = null;
      _target = null;
    });
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButton<int>(
          key: const ValueKey('review-since-filter'),
          hint: const Text('Alterações desde…'),
          value: _since?.round,
          items: [
            for (final c in sorted)
              DropdownMenuItem(
                value: c.round,
                enabled:
                    reasons[c.round]!.hasValue &&
                    reasons[c.round]!.value == null,
                child: Tooltip(
                  message: reasons[c.round]!.value ?? '',
                  child: Text(
                    'Rodada ${c.round} · ${c.author} · '
                    '${c.verdict ?? 'sem veredito'} · ${c.createdAt}',
                  ),
                ),
              ),
          ],
          onChanged: (n) => choose(rounds[n]),
        ),
        TextButton(
          onPressed: latest == null ? null : () => choose(latest),
          child: const Text('Desde a última rodada'),
        ),
        if (_since != null)
          TextButton(
            onPressed: () => choose(null),
            child: const Text('Diff completo'),
          ),
      ],
    );
  }

  Widget _sinceBody() {
    final row = _since!;
    final async = ref.watch(reviewSinceProvider((_id, row.commitSha!)));
    final d = async.value;
    if (d == null) {
      return _message(async.hasError ? '${async.error}' : 'Carregando…');
    }
    if (d.error != null) return _message(d.error!);
    if (d.files.isEmpty) {
      return _message('Nada mudou desde a rodada ${row.round}');
    }
    final view = ref.watch(reviewViewProvider);
    final selected = ref.watch(_selectedFileProvider);
    final full = ref.watch(reviewDetailProvider(_id)).value;
    final unchanged =
        selected != null && !d.files.any((f) => f.path == selected);
    final fallback = full?.files.where((f) => f.path == selected).firstOrNull;
    final files = !view.allFiles && unchanged && fallback != null
        ? [fallback]
        : view.allFiles
        ? d.files
        : [
            d.files.where((f) => f.path == selected).firstOrNull ??
                d.files.first,
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${d.commitsAhead} commits · ${d.files.length} arquivos desde a rodada ${row.round}',
        ),
        if (!view.allFiles && unchanged && fallback != null)
          const Text('diff completo desde a base da branch'),
        Expanded(
          child: ReviewAllFiles(
            files: files,
            draft: const ReviewDraft(),
            readOnly: true,
            sideBySide: view.sideBySide,
            persisted: _persisted(d.files)
                .where((c) => c.row.round == row.round)
                .toList(),
            selected: _selectedComments,
            onSelectComment: _selectComment,
          ),
        ),
      ],
    );
  }

  /// Diff of the commits of [_step] (read only).
  Widget _stepBody() {
    final async = ref.watch(reviewStepDetailProvider((_id, _step!)));
    final d = async.value;
    if (d == null) {
      return async.hasError
          ? _message('${async.error}', color: AppColors.red)
          : _message('Carregando os commits de $_step…');
    }
    if (d.error != null) return _message(d.error!, color: AppColors.red);
    final view = ref.watch(reviewViewProvider);
    return ReviewAllFiles(
      files: d.files,
      sideBySide: view.sideBySide,
      draft: const ReviewDraft(),
      readOnly: true,
    );
  }
}

/// `pr/x → main · n arquivos · +x −y · k commits · m não commitados`.
class _Subtitle extends StatelessWidget {
  const _Subtitle({required this.detail, required this.branch, this.busy});

  final ReviewDetail? detail;
  final String branch;
  final String? busy;

  @override
  Widget build(BuildContext context) {
    const mono = TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: 12,
      color: AppColors.textSecondary,
    );
    final d = detail;
    final spans = <InlineSpan>[
      TextSpan(
        text:
            '$branch → ${d?.baseBranch.isNotEmpty ?? false ? d!.baseBranch : '…'}',
      ),
    ];
    if (d != null && d.error == null) {
      spans.addAll([
        TextSpan(
          text:
              ' · ${d.files.length} arquivo${d.files.length == 1 ? '' : 's'} · ',
        ),
        TextSpan(
          text: '+${d.additions}',
          style: const TextStyle(color: AppColors.teal),
        ),
        const TextSpan(text: ' '),
        TextSpan(
          text: '−${d.deletions}',
          style: const TextStyle(color: AppColors.red),
        ),
        TextSpan(
          text:
              ' · ${d.commitsAhead} commit${d.commitsAhead == 1 ? '' : 's'}'
              '${d.uncommitted > 0 ? ' · ${d.uncommitted} não commitado${d.uncommitted == 1 ? '' : 's'}' : ''}',
        ),
      ]);
    }
    if (busy != null) {
      spans.add(
        TextSpan(
          text: ' · $busy…',
          style: const TextStyle(color: AppColors.amber),
        ),
      );
    }
    return Text.rich(
      TextSpan(style: mono, children: spans),
      key: const ValueKey('review-subtitle'),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

final reviewAnchorProvider = FutureProvider.family<AnchorShifts, (String, int)>(
  (ref, key) async {
    final rows = await ref.watch(reviewCommentsProvider(key.$2).future);
    ref.watch(reviewDetailProvider(key.$1));
    return ref.read(reviewServiceProvider).anchorShifts(key.$1, rows);
  },
);
