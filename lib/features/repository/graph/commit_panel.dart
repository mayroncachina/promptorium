import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/diff_parser.dart';
import '../../../core/git/gh_cli.dart' show CiState;
import '../../../core/text/line_diff.dart' show DiffOp, DiffRow;
import '../../../data/providers.dart';
import '../../../ui/shell/navigation.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../../ui/widgets/app_toast.dart';
import '../../../ui/widgets/diff_view.dart';
import '../../board/board_screen.dart' show boardSelectedSpecProvider;
import '../../review/review_service.dart' show selectedReviewProvider;
import '../releases/releases_tab.dart' show openExternal, formatReleaseDateTime;
import '../repository_info.dart';
import 'commit_log.dart';
import 'graph_controller.dart';
import 'graph_painter.dart';
import 'graph_sources.dart';
import 'graph_tab.dart' show GraphChip, formatThousands;
import 'lane_layout.dart';
import 'spec_branch.dart';

/// Files listed before "+ N arquivos".
const _filesShown = 8;

/// Rows of a unified diff of one file, for [DiffView].
List<DiffRow> diffRowsOf(String diff) {
  final files = DiffParser.parse(diff);
  return [
    for (final f in files)
      for (final h in f.hunks)
        for (final l in h.lines)
          (
            op: switch (l.kind) {
              DiffLineKind.add => DiffOp.add,
              DiffLineKind.del => DiffOp.del,
              DiffLineKind.context => DiffOp.same,
            },
            text: l.text,
            line: l.kind == DiffLineKind.del ? l.oldNo : l.newNo,
          ),
  ];
}

/// The selected commit (SPEC-045 R5; docs/mockups/spec-045/2-commit.png):
/// message, author, date and SHA; parents, what contains it, spec and PR;
/// the files with +/− and their diff.
class CommitPanel extends ConsumerStatefulWidget {
  const CommitPanel({
    super.key,
    required this.controller,
    required this.row,
    required this.repo,
    this.onClose,
  });

  final GraphController controller;
  final LaneRow row;
  final RepositoryInfo repo;
  final VoidCallback? onClose;

  @override
  ConsumerState<CommitPanel> createState() => _CommitPanelState();
}

class _CommitPanelState extends ConsumerState<CommitPanel> {
  bool _allFiles = false;

  @override
  void didUpdateWidget(CommitPanel old) {
    super.didUpdateWidget(old);
    if (old.row.sha != widget.row.sha) _allFiles = false;
  }

  void _copy(String sha) {
    unawaited(Clipboard.setData(ClipboardData(text: sha)));
    ScaffoldMessenger.maybeOf(context)?.showAppToast(
      const SnackBar(
        key: ValueKey('graph-sha-copied'),
        content: Text('SHA copiado.'),
      ),
    );
  }

  void _openSpec(Spec spec) {
    ref.read(boardSelectedSpecProvider.notifier).select(spec.id);
    ref.read(navigationProvider.notifier).request(AppSection.tasks);
  }

  void _openReview(String sessionId) {
    ref.read(selectedReviewProvider.notifier).select(sessionId);
    ref.read(navigationProvider.notifier).request(AppSection.review);
  }

  Future<void> _showDiff(CommitRow c, String path) async {
    final diff = widget.controller.fileDiff(c.sha, path);
    await showAppDialog<void>(
      context: context,
      builder: (context) => Dialog(
        key: const ValueKey('graph-diff-dialog'),
        backgroundColor: AppColors.panel,
        insetPadding: const EdgeInsets.all(48),
        child: SizedBox(
          width: 900,
          height: 640,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$path · ${c.shortSha}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fechar',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              Expanded(
                child: FutureBuilder<String>(
                  future: diff,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(
                        child: Text(
                          'Não foi possível ler a diferença: ${snap.error}',
                          style: const TextStyle(color: AppColors.red),
                        ),
                      );
                    }
                    if (!snap.hasData) {
                      return const Center(
                        child: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    final rows = diffRowsOf(snap.data!);
                    if (rows.isEmpty) {
                      return const Center(
                        child: Text(
                          'Sem diferença de texto (arquivo binário ou só '
                          'renomeado).',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.all(12),
                      child: DiffView(rows: rows, scrollable: true),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final row = widget.row;
    final ws = ref.watch(activeWorkspaceProvider);
    final specs = ws == null
        ? const <Spec>[]
        : ref.watch(specsProvider(ws.id)).value ?? const <Spec>[];
    final sessions = ws == null
        ? const <Session>[]
        : ref.watch(sessionsProvider(ws.id)).value ?? const <Session>[];
    final prs = ref.watch(graphPrsProvider(widget.repo.path));
    final spec = c.specOf(row);
    final specRow = spec == null
        ? null
        : specs.where((s) => s.code == spec.code).firstOrNull;
    final commit = c.commit(row.sha)!;
    final summary = row.kind == NodeKind.summary;
    final details = summary ? null : c.details(row.sha);
    final error = c.detailsError(row.sha);
    final base = c.defaultBranch;

    // The PR: the open one of the commit's branch, or the merge's number.
    final openPr = row.track == null ? null : prs[row.track!];
    final mergedPr = prFromMergeSubject(commit.subject);
    String? sessionFor(String? branch) => branch == null
        ? null
        : sessions.where((s) => s.branch == branch).firstOrNull?.id;
    final mergedBranch = branchFromMergeSubject(commit.subject);
    final reviewSession =
        openPr?.sessionId ?? sessionFor(mergedBranch) ?? sessionFor(row.track);
    final slug = widget.repo.githubSlug;

    const label = TextStyle(fontSize: 13, color: AppColors.textSecondary);
    const mono = TextStyle(fontFamily: AppFonts.mono, fontSize: 13);
    const link = TextStyle(
      fontSize: 13,
      color: Color(0xFF8EC5FF),
      decoration: TextDecoration.underline,
      decorationColor: Color(0xFF8EC5FF),
    );

    Widget field(String name, Widget value) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 88, child: Text(name, style: label)),
          Expanded(child: value),
        ],
      ),
    );

    Widget linkButton(String text, VoidCallback onTap, {Key? key}) => InkWell(
      key: key,
      onTap: onTap,
      child: Text(text, style: link),
    );

    final parents = [
      for (final p in commit.parents)
        (
          p.length > 7 ? p.substring(0, 7) : p,
          c.rows.where((r) => r.sha == p).firstOrNull?.track,
        ),
    ];

    final header = Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!summary) ...[
                Text(
                  commit.shortSha,
                  style: mono.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const ValueKey('graph-copy-sha'),
                  onPressed: () => _copy(commit.sha),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 26),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    side: const BorderSide(color: AppColors.border),
                    foregroundColor: AppColors.textSecondary,
                    textStyle: const TextStyle(fontFamily: AppFonts.sans, fontSize: 12),
                  ),
                  child: const Text('Copiar SHA'),
                ),
              ],
              const Spacer(),
              for (final t in commit.tags) ...[
                const SizedBox(width: 6),
                GraphChip(text: t, color: AppColors.amber, filled: true),
              ],
              IconButton(
                key: const ValueKey('graph-panel-close'),
                tooltip: 'Fechar',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 16),
                color: AppColors.textSecondary,
                onPressed: widget.onClose,
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            summary
                ? '${spec!.code}${specRow == null ? '' : ' · ${specRow.title}'}'
                : commit.subject,
            key: const ValueKey('graph-panel-subject'),
            style: const TextStyle(
              fontSize: 16,
              height: 23 / 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (details != null && details.body.isNotEmpty) ...[
            const SizedBox(height: 6),
            SelectableText(
              details.body,
              key: const ValueKey('graph-panel-body'),
              style: const TextStyle(fontSize: 13, color: Color(0xFFC9CED8)),
            ),
          ],
          if (!summary) ...[
            const SizedBox(height: 6),
            Text(
              '${commit.author} · ${formatReleaseDateTime(commit.time)}',
              style: label,
            ),
          ],
        ],
      ),
    );

    final g = summary ? c.laneState.groups[row.group] : null;
    final facts = Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          if (summary && g != null)
            field(
              'Recolhida',
              Text(
                [
                  if (g.tasks.isNotEmpty) '${g.tasks.length} tarefas',
                  if (g.tasks.isNotEmpty) '${g.mergedTasks.length} mergeadas',
                  '${g.commits} commits',
                ].join(' · '),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          if (!summary)
            field(
              'Pais',
              Wrap(
                key: const ValueKey('graph-panel-parents'),
                spacing: 10,
                children: [
                  if (parents.isEmpty)
                    const Text('nenhum (primeiro commit)', style: label),
                  for (final (sha, track) in parents)
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: sha,
                            style: mono.copyWith(
                              color: trackColor(track, base),
                            ),
                          ),
                          if (track != null)
                            TextSpan(
                              text: ' $track',
                              style: mono.copyWith(color: AppColors.textMuted),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (!summary)
            field(
              'Contido em',
              Text(
                details == null
                    ? '…'
                    : [...details.branches, ...details.tags].join(', '),
                key: const ValueKey('graph-panel-contains'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: mono.copyWith(color: const Color(0xFFC9CED8)),
              ),
            ),
          if (spec != null)
            field(
              'Spec',
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: SpecColors.of(spec.number),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Text(
                    '${spec.label}'
                    '${specRow == null ? '' : ' · ${specRow.title}'}',
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (specRow != null)
                    linkButton(
                      'Abrir no Quadro',
                      () => _openSpec(specRow),
                      key: const ValueKey('graph-open-board'),
                    ),
                ],
              ),
            ),
          if (openPr != null || mergedPr != null)
            field(
              'PR',
              Wrap(
                spacing: 8,
                children: [
                  Text(
                    openPr != null
                        ? [
                            '#${openPr.number} · aberto',
                            ?switch (openPr.ci) {
                              CiState.none => null,
                              CiState.running => 'CI rodando',
                              CiState.passed => 'CI passou',
                              CiState.failed => 'CI falhou',
                            },
                          ].join(' · ')
                        : '#$mergedPr · mergeado',
                    key: const ValueKey('graph-panel-pr'),
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (reviewSession != null)
                    linkButton(
                      'Abrir no Review',
                      () => _openReview(reviewSession),
                      key: const ValueKey('graph-open-review'),
                    )
                  else if (openPr?.url != null || slug != null)
                    linkButton(
                      'Abrir no GitHub',
                      () => unawaited(
                        openExternal(
                          ref,
                          openPr?.url ??
                              'https://github.com/$slug/pull/$mergedPr',
                        ),
                      ),
                      key: const ValueKey('graph-open-github'),
                    ),
                ],
              ),
            ),
          if (summary)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: linkButton(
                  'Expandir ${spec!.code}',
                  () => c.toggleGroup(row.group!),
                  key: const ValueKey('graph-panel-expand'),
                ),
              ),
            ),
        ],
      ),
    );

    Widget files;
    if (summary) {
      files = const SizedBox.shrink();
    } else if (error != null) {
      files = Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'Não foi possível ler o commit: $error',
          style: const TextStyle(fontSize: 13, color: AppColors.red),
        ),
      );
    } else if (details == null) {
      files = const Padding(
        padding: EdgeInsets.all(20),
        child: SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else {
      final shown = _allFiles
          ? details.files
          : details.files.take(_filesShown).toList();
      files = Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'ARQUIVOS · ${details.files.length} · '
              '+${formatThousands(details.added)} '
              '−${formatThousands(details.removed)}',
              key: const ValueKey('graph-panel-files-title'),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: .5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            for (final f in shown)
              Container(
                key: ValueKey('graph-file-${f.path}'),
                height: 32,
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFF1E232C))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Tooltip(
                        message: f.path,
                        child: Text(
                          _leftEllipsis(f.path, 38),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(
                        f.added == null ? 'bin' : '+${f.added}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 12,
                          color: Color(0xFF5BC88A),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        (f.removed ?? 0) == 0 ? '' : '−${f.removed}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 12,
                          color: AppColors.red,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Semantics(
                      button: true,
                      label: 'Ver diferença de ${f.path}',
                      child: linkButton(
                        'diferença',
                        () => _showDiff(commit, f.path),
                        key: ValueKey('graph-diff-${f.path}'),
                      ),
                    ),
                  ],
                ),
              ),
            if (!_allFiles && details.files.length > _filesShown)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    key: const ValueKey('graph-more-files'),
                    onTap: () => setState(() => _allFiles = true),
                    child: Text(
                      '+ ${details.files.length - _filesShown} arquivos',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Container(
      key: const ValueKey('graph-commit-panel'),
      color: const Color(0xFF12151B),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [header, facts, files],
      ),
    );
  }
}

/// `…s/board/widgets/sprint_selector.dart`: the end of a path fits.
String _leftEllipsis(String path, int max) =>
    path.length <= max ? path : '…${path.substring(path.length - max + 1)}';
