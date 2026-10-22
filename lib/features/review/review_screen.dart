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
import 'review_service.dart';
import 'widgets/spec_review_panel.dart';
import 'widgets/review_diff_view.dart';
import 'widgets/pr_panel.dart';
import 'widgets/review_all_files.dart';
import 'widgets/review_dialogs.dart';

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
  const ReviewView({this.allFiles = true, this.sideBySide = false});

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

class _QueueTile extends StatelessWidget {
  const _QueueTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final ReviewItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = item.session;
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
    required this.file,
    required this.selected,
    required this.onTap,
  });

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

  /// Step whose commits are shown (null = the whole branch).
  String? _step;

  /// The last "Fazer merge" stopped on a conflict.
  bool _conflict = false;

  String get _id => widget.item.session.id;

  ReviewService get _service => ref.read(reviewServiceProvider);

  @override
  void initState() {
    super.initState();
    // "Ver diff da etapa" (Specs, U5) opens the item on that step; the
    // provider is cleared after this frame (no writes during build).
    _step = ref.read(reviewInitialStepProvider);
    if (_step != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(reviewInitialStepProvider.notifier).set(null);
      });
    }
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
      if (mounted) await showReviewError(context, label, e.message);
    } catch (e) {
      if (mounted) await showReviewError(context, label, '$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _selectStep(String? step) => setState(() {
    _step = step;
    _target = null;
  });

  /// File of [_target] (the page with every file has several).
  String? _targetPath;

  void _setTarget(CommentTarget? t, [String? path]) => setState(() {
    _target = t;
    _targetPath = path;
  });

  void _refresh() {
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
    final note = await showAdjustDialog(context, comments);
    if (note == null || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final id = _id;
    await _run('Pedir ajustes ao agente', () async {
      await _service.requestChanges(_id, comments, note: note);
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
    final deleteBranch = await showMergeDialog(
      context,
      branch: d.session.branch,
      base: d.baseBranch,
      uncommitted: d.uncommitted,
    );
    if (deleteBranch == null || !mounted) return;
    await _run('Fazer merge', () async {
      final r = await _service.merge(
        _id,
        deleteBranch: deleteBranch,
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
        ? 'Verificando gh e remote…'
        : pr.available
        ? (s.prUrl != null
              ? 'PR já criado: ${s.prUrl}'
              : 'Commita pendências, envia a branch e roda gh pr create')
        : pr.reason ?? 'Indisponível';
    final canPr = !busy && d?.error == null && (pr?.available ?? false);
    final reviewing =
        widget.item.spec?.reviewPhase == ReviewPhase.auto &&
        widget.item.spec?.stage == SpecStage.review;
    final canMerge = !busy && d != null && d.error == null && !reviewing;
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
                  label: s.prUrl != null ? 'PR criado' : 'Criar PR',
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
                message: reviewing
                    ? 'O revisor automático ainda está revisando'
                    : pending.isEmpty
                    ? ''
                    : 'Critérios de aceite sem marcar: ${pending.length}',
                child: AmberButton(
                  key: const ValueKey('review-merge'),
                  label: pending.isEmpty
                      ? 'Fazer merge'
                      : 'Mergear mesmo assim…',
                  onTap: canMerge ? () => _merge(d, pending: pending) : null,
                ),
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
            merged: s.status == SessionStatus.merged,
          ),
        _toolbar(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: _step == null
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
      return _message('Nenhuma alteração em relação à branch base.');
    }
    final notifier = ref.read(reviewDraftProvider(_id).notifier);
    final view = ref.watch(reviewViewProvider);
    final lines = d.files.fold(0, (n, f) => n + diffLineCount(f));
    if (view.allFiles && lines <= allFilesMaxLines) {
      return ReviewAllFiles(
        files: d.files,
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
    return ReviewFileDiff(
      key: ValueKey('review-file-diff-${file.path}'),
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
                () => notifier.set(
                  ReviewView(allFiles: false, sideBySide: view.sideBySide),
                ),
              ),
              toggle(
                'review-view-all',
                'Todos os arquivos',
                view.allFiles,
                () => notifier.set(
                  ReviewView(allFiles: true, sideBySide: view.sideBySide),
                ),
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
                () => notifier.set(ReviewView(allFiles: view.allFiles)),
              ),
              toggle(
                'review-view-split',
                'Lado a lado',
                view.sideBySide,
                () => notifier.set(
                  ReviewView(allFiles: view.allFiles, sideBySide: true),
                ),
              ),
            ],
          ),
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
