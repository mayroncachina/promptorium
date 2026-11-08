import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/gh_cli.dart';
import '../../../core/git/git_service.dart';
import '../../../data/providers.dart';
import '../../../ui/shell/navigation.dart';
import '../../../ui/theme/motion.dart';
import '../../../ui/theme/tokens.dart';
import '../../review/review_service.dart' show selectedReviewProvider;
import '../releases/releases_tab.dart';
import '../repository_info.dart';
import '../repository_screen.dart';
import 'commit_log.dart';
import 'graph_controller.dart';
import 'graph_painter.dart';
import 'graph_sources.dart';
import 'lane_layout.dart';
import 'spec_branch.dart';

/// The Grafo tab (SPEC-045; docs/mockups/spec-045/1-grafo.png).
final graphTab = RepositoryTab(
  id: 'grafo',
  label: 'Grafo',
  builder: (context, repo) => GraphTab(repo: repo),
  headerTrailing: (context, repo) => GhStatusLabel(repo: repo),
);

/// What goes beside the author's name of a commit (R9: the model of an
/// agent's commit, from SPEC-048). Null = only the name. SPEC-046 sets it
/// when it joins this branch with SPEC-048's.
typedef CommitAuthorBadge = Widget? Function(BuildContext context, CommitRow c);

final graphAuthorBadgeProvider = Provider<CommitAuthorBadge?>((ref) => null);

/// The [CommitLog] of a repository (overridden by the tests).
final graphLogFactoryProvider = Provider<CommitLog Function(RepositoryInfo)>((
  ref,
) {
  final gitFor = ref.watch(gitServiceFactoryProvider);
  return (repo) => CommitLog(
    gitFor(repo.path),
    defaultBranch: repo.defaultBranch,
    remote: repo.remote,
  );
});

const _months = [
  'jan',
  'fev',
  'mar',
  'abr',
  'mai',
  'jun',
  'jul',
  'ago',
  'set',
  'out',
  'nov',
  'dez',
];

/// `agora`, `há 5 min`, `há 2 h`, `7 nov`, `7 nov 2025` (R1).
String graphDate(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inMinutes < 1) return 'agora';
  if (d.inMinutes < 60) return 'há ${d.inMinutes} min';
  if (d.inHours < 24) return 'há ${d.inHours} h';
  final l = t.toLocal();
  final day = '${l.day} ${_months[l.month - 1]}';
  return l.year == now.toLocal().year ? day : '$day ${l.year}';
}

/// `7 nov, 02:37`.
String graphDateTime(DateTime t) {
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.day} ${_months[l.month - 1]}, ${two(l.hour)}:${two(l.minute)}';
}

/// `spec/043-conflito…`: a branch label fits in 20 characters.
String shortRef(String name, {int max = 20}) =>
    name.length <= max ? name : '${name.substring(0, max - 1)}…';

String _plural(int n, String one, String many) =>
    n == 1 ? '1 $one' : '$n $many';

/// The three lines of the lane balloon (R8).
@immutable
class LaneBalloon {
  const LaneBalloon(this.title, this.detail, [this.merged]);

  final String title;
  final String detail;
  final String? merged;
}

/// What the balloon says about [track] (R8), from the rows read.
LaneBalloon laneBalloon(String track, GraphController c) {
  final st = c.laneState;
  final base = c.defaultBranch;
  if (track == base) {
    return LaneBalloon(track, 'Branch padrão');
  }
  final spec = parseSpecBranch(track);
  final String detail;
  if (spec != null && !spec.isTask) {
    final g = st.groups[spec.number];
    final tasks = g?.tasks.length ?? 0;
    detail = [
      if (tasks > 0) _plural(tasks, 'filha', 'filhas'),
      '${_plural(g?.commits ?? 0, 'commit', 'commits')} a mais que a $base',
    ].join(' · ');
  } else {
    final n = st.tracks[track]?.commits ?? 0;
    detail = [
      ?spec?.label,
      '${_plural(n, 'commit', 'commits')} a mais que a $base',
    ].join(' · ');
  }
  final t = st.tracks[track];
  String? merged;
  final at = t?.mergedAt == null ? null : c.commit(t!.mergedAt!);
  if (at != null) {
    final into = t!.mergedInto == base ? 'na $base' : 'em ${t.mergedInto}';
    merged =
        'Mergeada $into em ${graphDateTime(at.time)}'
        '${t.pr == null ? '' : ' (PR #${t.pr})'}';
  }
  return LaneBalloon(track, detail, merged);
}

class GraphTab extends ConsumerStatefulWidget {
  const GraphTab({super.key, required this.repo, this.controller});

  final RepositoryInfo repo;

  /// Given by the tests (already loaded); otherwise made here.
  final GraphController? controller;

  @override
  ConsumerState<GraphTab> createState() => GraphTabState();
}

class GraphTabState extends ConsumerState<GraphTab> {
  late final GraphController controller;
  late final bool _owned;
  final _scroll = ScrollController();
  final _stackKey = GlobalKey();

  /// Lane under the pointer (R8).
  String? _hoverTrack;
  Offset? _hoverAt;

  @override
  void initState() {
    super.initState();
    _owned = widget.controller == null;
    controller =
        widget.controller ??
        GraphController(ref.read(graphLogFactoryProvider)(widget.repo));
    controller.addListener(_changed);
    _scroll.addListener(_onScroll);
    if (!controller.loaded) unawaited(controller.load());
  }

  @override
  void dispose() {
    controller.removeListener(_changed);
    if (_owned) controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Near the end, the next page (R7).
  void _onScroll() {
    final p = _scroll.position;
    if (p.extentAfter < graphRowHeight * 20 && controller.hasMore) {
      unawaited(controller.loadMore());
    }
  }

  void _hover(LaneRow row, Offset local, Offset global) {
    final col = laneAt(local.dx);
    String? track;
    var found = false;
    if (col != null) {
      if (col == row.column) {
        track = row.track;
        found = true;
      } else {
        for (final s in row.segments) {
          if (s.column == col) {
            track = s.track;
            found = true;
            break;
          }
        }
      }
    }
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final at = found && box != null ? box.globalToLocal(global) : null;
    if (track == _hoverTrack && (at == null) == (_hoverAt == null)) {
      if (at != null) setState(() => _hoverAt = at);
      return;
    }
    setState(() {
      _hoverTrack = found ? track : null;
      _hoverAt = at;
    });
  }

  void _leave() {
    if (_hoverTrack == null && _hoverAt == null) return;
    setState(() {
      _hoverTrack = null;
      _hoverAt = null;
    });
  }

  void _openTag(String tag) {
    ref.read(selectedReleaseProvider.notifier).select(tag);
    ref.read(repositoryTabProvider.notifier).select('releases');
  }

  void _openPr(GraphPr pr) {
    final id = pr.sessionId;
    if (id != null) {
      ref.read(selectedReviewProvider.notifier).select(id);
      ref.read(navigationProvider.notifier).request(AppSection.review);
    } else if (pr.url != null) {
      unawaited(openExternal(ref, pr.url!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final ws = ref.watch(activeWorkspaceProvider);
    final specs = ws == null
        ? const <Spec>[]
        : ref.watch(specsProvider(ws.id)).value ?? const <Spec>[];
    final titles = {for (final s in specs) s.code: s.title};
    final prs = ref.watch(graphPrsProvider(widget.repo.path));
    final busy = ref.watch(graphBusyBranchesProvider);
    final badge = ref.watch(graphAuthorBadgeProvider);
    final highlight = _hoverTrack == null ? null : highlightKeyOf(_hoverTrack);
    final graphWidth = graphColumnWidth(c.width);
    final now = DateTime.now();

    Widget body;
    if (c.error != null && c.rows.isEmpty) {
      body = Center(
        child: Text(
          'Não foi possível ler o histórico: ${c.error}',
          style: const TextStyle(color: AppColors.red, fontSize: 13),
        ),
      );
    } else if (!c.loaded && c.rows.isEmpty) {
      body = const Center(
        child: SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else {
      body = Stack(
        key: _stackKey,
        children: [
          ListView.builder(
            key: const ValueKey('graph-list'),
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
            itemExtent: graphRowHeight,
            itemCount: c.rows.length + (c.hasMore ? 1 : 0),
            itemBuilder: (context, i) {
              if (i >= c.rows.length) {
                if (!c.loading) {
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => unawaited(c.loadMore()),
                  );
                }
                return const Center(
                  child: Text(
                    'Carregando mais commits…',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                );
              }
              final row = c.rows[i];
              final commit = c.commit(row.sha);
              if (commit == null) return const SizedBox.shrink();
              return GraphCommitRow(
                key: ValueKey('graph-row-${row.sha}'),
                row: row,
                commit: commit,
                controller: c,
                graphWidth: graphWidth,
                highlight: highlight,
                selected: c.selected == row.sha,
                now: now,
                specTitles: titles,
                prs: prs,
                busyBranches: busy,
                authorBadge: badge,
                onTap: () => c.select(row.sha),
                onHover: (local, global) => _hover(row, local, global),
                onLeave: _leave,
                onTag: _openTag,
                onPr: _openPr,
              );
            },
          ),
          if (_hoverTrack != null && _hoverAt != null)
            Positioned(
              left: _hoverAt!.dx + 16,
              top: _hoverAt!.dy + 12,
              child: IgnorePointer(
                child: _Balloon(
                  balloon: laneBalloon(_hoverTrack!, c),
                  color: trackColor(_hoverTrack, c.defaultBranch),
                ),
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(controller: c),
        _ColumnTitles(graphWidth: graphWidth),
        Expanded(child: body),
      ],
    );
  }
}

/// Header of the tab (R6): the count of commits read.
class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.controller});

  final GraphController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1E232C))),
      ),
      child: Row(
        children: [
          const Spacer(),
          if (c.loaded)
            Text(
              '${formatThousands(c.commits.length)} de '
              '${formatThousands(c.total)} commits',
              key: const ValueKey('graph-count'),
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }
}

/// `1.284`.
String formatThousands(int n) {
  final s = '$n';
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

const _titleStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w600,
  letterSpacing: .5,
  color: AppColors.textMuted,
);

class _ColumnTitles extends StatelessWidget {
  const _ColumnTitles({required this.graphWidth});

  final double graphWidth;

  @override
  Widget build(BuildContext context) => Container(
    height: 32,
    padding: const EdgeInsets.fromLTRB(24, 0, 36, 0),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0xFF1E232C))),
    ),
    child: Row(
      children: [
        SizedBox(
          width: graphWidth,
          child: const Text('GRAFO', style: _titleStyle),
        ),
        const SizedBox(width: 10),
        const Expanded(child: Text('COMMIT', style: _titleStyle)),
        const SizedBox(width: 10),
        const SizedBox(width: 84, child: Text('SPEC', style: _titleStyle)),
        const SizedBox(width: 10),
        const SizedBox(width: 170, child: Text('AUTOR', style: _titleStyle)),
        const SizedBox(width: 10),
        const SizedBox(width: 78, child: Text('DATA', style: _titleStyle)),
        const SizedBox(width: 10),
        const SizedBox(width: 62, child: Text('SHA', style: _titleStyle)),
      ],
    ),
  );
}

/// One commit (R1): the lanes, the labels and the message, the spec, the
/// author, the date and the short SHA.
class GraphCommitRow extends StatelessWidget {
  const GraphCommitRow({
    super.key,
    required this.row,
    required this.commit,
    required this.controller,
    required this.graphWidth,
    required this.now,
    this.highlight,
    this.selected = false,
    this.compact = false,
    this.specTitles = const {},
    this.prs = const {},
    this.busyBranches = const {},
    this.authorBadge,
    this.onTap,
    this.onHover,
    this.onLeave,
    this.onTag,
    this.onPr,
  });

  final LaneRow row;
  final CommitRow commit;
  final GraphController controller;
  final double graphWidth;
  final DateTime now;
  final Object? highlight;
  final bool selected;

  /// Without the spec and author columns (the panel is open).
  final bool compact;
  final Map<String, String> specTitles;
  final Map<String, GraphPr> prs;
  final Set<String> busyBranches;
  final CommitAuthorBadge? authorBadge;
  final VoidCallback? onTap;
  final void Function(Offset local, Offset global)? onHover;
  final VoidCallback? onLeave;
  final ValueChanged<String>? onTag;
  final ValueChanged<GraphPr>? onPr;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final base = c.defaultBranch;
    final color = trackColor(row.track, base);
    final spec = c.specOf(row);
    final summary = row.kind == NodeKind.summary;
    final dim = highlight != null && highlightKeyOf(row.track) != highlight;
    final chips = <Widget>[];

    if (summary) {
      chips.add(
        GraphChip(
          key: ValueKey('graph-group-${row.group}'),
          text: 'recolhida',
          color: color,
          tint: true,
          tooltip: 'Expandir ${specCode(row.group!)}',
          onTap: () => c.toggleGroup(row.group!),
        ),
      );
    } else {
      final group = parseSpecBranch(row.track)?.number;
      final branchLabels = commit.branchLabels;
      if (group != null &&
          c.laneState.groups[group]?.first == row.sha &&
          !branchLabels.any(
            (r) => parseSpecBranch(r.branchName)?.number == group,
          )) {
        chips.add(
          GraphChip(
            key: ValueKey('graph-group-$group'),
            text: specCode(group),
            color: SpecColors.of(group),
            tooltip: 'Recolher ${specCode(group)}',
            onTap: () => c.toggleGroup(group),
          ),
        );
      }
      for (final r in branchLabels) {
        chips.add(
          GraphChip(
            key: ValueKey('graph-branch-${r.name}'),
            text: shortRef(r.name),
            color: trackColor(r.branchName, base),
            tooltip: r.name,
          ),
        );
      }
      for (final t in commit.tags) {
        chips.add(
          GraphChip(
            key: ValueKey('graph-tag-$t'),
            text: t,
            color: AppColors.amber,
            filled: true,
            tooltip: 'Abrir $t em Releases',
            onTap: onTag == null ? null : () => onTag!(t),
          ),
        );
      }
      for (final r in branchLabels) {
        final pr = prs[r.branchName];
        if (pr == null || r.kind == RefKind.remote && branchLabels.length > 1) {
          continue;
        }
        chips.add(
          GraphChip(
            key: ValueKey('graph-pr-${pr.number}'),
            text: pr.label,
            color: switch (pr.ci) {
              CiState.passed => SpecColors.palette[3],
              CiState.failed => AppColors.red,
              _ => SpecColors.palette[1],
            },
            tint: true,
            tooltip: pr.sessionId != null
                ? 'Abrir no Review'
                : 'Abrir o PR #${pr.number} no navegador',
            onTap: onPr == null ? null : () => onPr!(pr),
          ),
        );
      }
      if (branchLabels.any((r) => busyBranches.contains(r.branchName))) {
        chips.add(
          GraphChip(
            key: const ValueKey('graph-agent'),
            text: 'agente trabalhando',
            color: AppColors.amber,
            tint: true,
            pulse: true,
            tooltip: 'Um agente está rodando no worktree desta branch.',
          ),
        );
      }
    }

    final String message;
    if (summary) {
      final g = c.laneState.groups[row.group];
      final code = specCode(row.group!);
      final title = specTitles[code];
      final tasks = g?.tasks.length ?? 0;
      message = [
        '$code${title == null ? '' : ' · $title'}:',
        [
          if (tasks > 0) _plural(tasks, 'tarefa', 'tarefas'),
          if (tasks > 0)
            _plural(g!.mergedTasks.length, 'mergeada', 'mergeadas'),
          _plural(g?.commits ?? 0, 'commit', 'commits'),
        ].join(', '),
      ].join(' ');
    } else {
      message = commit.subject;
    }

    final mono = const TextStyle(fontFamily: AppFonts.mono, fontSize: 12);
    final badge = summary ? null : authorBadge?.call(context, commit);
    return Semantics(
      selected: selected,
      button: true,
      label: message,
      child: Material(
        color: selected ? const Color(0xFF1A2130) : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: selected
                ? const BoxDecoration(
                    border: Border(
                      left: BorderSide(color: Color(0xFF8EC5FF), width: 3),
                    ),
                  )
                : null,
            padding: EdgeInsets.only(right: 12, left: selected ? 0 : 3),
            child: Opacity(
              opacity: dim ? .45 : 1,
              child: Row(
                children: [
                  MouseRegion(
                    onHover: onHover == null
                        ? null
                        : (e) => onHover!(e.localPosition, e.position),
                    onExit: onLeave == null ? null : (_) => onLeave!(),
                    child: CustomPaint(
                      key: ValueKey('graph-lanes-${row.sha}'),
                      size: Size(graphWidth - 3, graphRowHeight),
                      painter: GraphRowPainter(
                        row: row,
                        defaultBranch: base,
                        highlight: highlight,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      children: [
                        for (final chip in chips) ...[
                          chip,
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            message,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: summary
                                  ? FontWeight.w500
                                  : FontWeight.w400,
                              color: commit.isMerge && !summary
                                  ? AppColors.textSecondary
                                  : AppColors.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 84,
                      child: Text(
                        spec?.label ?? '',
                        key: ValueKey('graph-spec-${row.sha}'),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: mono.copyWith(color: color),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 170,
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              summary ? '' : commit.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          if (badge != null) ...[
                            const SizedBox(width: 6),
                            badge,
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 78,
                    child: Text(
                      graphDate(commit.time, now),
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 62,
                    child: Text(
                      summary ? '' : commit.shortSha,
                      style: mono.copyWith(color: AppColors.textMuted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A label on a commit (R4): branch (outlined), tag (filled amber), PR and
/// "agente trabalhando" (tinted).
class GraphChip extends StatelessWidget {
  const GraphChip({
    super.key,
    required this.text,
    required this.color,
    this.filled = false,
    this.tint = false,
    this.pulse = false,
    this.tooltip,
    this.onTap,
  });

  final String text;
  final Color color;
  final bool filled;
  final bool tint;

  /// A dot pulsing before the text (an agent running).
  final bool pulse;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: filled
            ? color
            : tint
            ? color.withValues(alpha: .1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: filled ? color : color.withValues(alpha: .4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pulse) ...[_PulseDot(color: color), const SizedBox(width: 5)],
          Text(
            text,
            style: TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: filled ? AppColors.onAmber : color,
            ),
          ),
        ],
      ),
    );
    final Widget body = onTap == null
        ? chip
        : MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(onTap: onTap, child: chip),
          );
    return tooltip == null
        ? body
        : Tooltip(message: tooltip, waitDuration: AppMotion.base, child: body);
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color});

  final Color color;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.animate(context)) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) => Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: widget.color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: widget.color.withValues(alpha: .25 * _c.value),
            spreadRadius: 3,
          ),
        ],
      ),
    ),
  );
}

/// The lane balloon (R8; GrafoLista.dc.html).
class _Balloon extends StatelessWidget {
  const _Balloon({required this.balloon, required this.color});

  final LaneBalloon balloon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('graph-balloon'),
    width: 300,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: CanvasColors.tooltip,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: .4)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x8C000000),
          blurRadius: 28,
          offset: Offset(0, 12),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          balloon.title,
          style: TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          balloon.detail,
          style: const TextStyle(fontSize: 13, color: Color(0xFFC9CED8)),
        ),
        if (balloon.merged != null) ...[
          const SizedBox(height: 3),
          Text(
            balloon.merged!,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    ),
  );
}
