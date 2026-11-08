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
import 'commit_panel.dart';
import 'graph_controller.dart';
import 'graph_painter.dart';
import 'graph_sources.dart';
import 'graph_watcher.dart';
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

/// Something asked from outside the tab (SPEC-046: the Atividade opens the
/// Grafo on a day), carried out once by the tab.
@immutable
class GraphRequest {
  const GraphRequest({this.day, this.select, this.search});

  /// Only this day's commits ([GraphQuery.day]).
  final DateTime? day;

  /// Commit to select (its SHA).
  final String? select;

  /// Text of the search.
  final String? search;
}

class GraphRequestController extends Notifier<GraphRequest?> {
  @override
  GraphRequest? build() => null;

  void request(GraphRequest r) => state = r;

  /// The request, cleared (null = nothing asked).
  GraphRequest? take() {
    final r = state;
    if (r != null) state = null;
    return r;
  }
}

final graphRequestProvider =
    NotifierProvider<GraphRequestController, GraphRequest?>(
      GraphRequestController.new,
    );

/// Opens the Grafo of the Repositório screen on [day] (its commits only),
/// selecting [select] and searching [search] (SPEC-046).
void openGraph(WidgetRef ref, {DateTime? day, String? select, String? search}) {
  ref
      .read(graphRequestProvider.notifier)
      .request(GraphRequest(day: day, select: select, search: search));
  ref.read(repositoryTabProvider.notifier).select('grafo');
  ref.read(navigationProvider.notifier).request(AppSection.repository);
}

class GraphTab extends ConsumerStatefulWidget {
  const GraphTab({
    super.key,
    required this.repo,
    this.controller,
    this.watchRefs = true,
  });

  final RepositoryInfo repo;

  /// Given by the tests (already loaded); otherwise made here.
  final GraphController? controller;

  /// Reads the log again when HEAD, the refs or the tags change (R7).
  final bool watchRefs;

  @override
  ConsumerState<GraphTab> createState() => GraphTabState();
}

class GraphTabState extends ConsumerState<GraphTab> {
  late final GraphController controller;
  late final bool _owned;
  final _scroll = ScrollController();
  final _stackKey = GlobalKey();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  GraphRefsWatcher? _watcher;
  bool _disposed = false;

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
    _search.text = controller.search;
    if (!controller.loaded) unawaited(controller.load());
    if (widget.watchRefs) unawaited(_watch());
  }

  @override
  void dispose() {
    _disposed = true;
    controller.removeListener(_changed);
    if (_owned) controller.dispose();
    unawaited(_watcher?.close());
    _scroll.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _watch() async {
    try {
      final dir = (await controller.log.git.git([
        'rev-parse',
        '--absolute-git-dir',
      ])).trim();
      if (_disposed || dir.isEmpty) return;
      _watcher = GraphRefsWatcher(dir, onChange: () => unawaited(refresh()));
    } on GitException catch (e) {
      debugPrint('Grafo: sem vigia das refs — $e');
    }
  }

  /// Reads the log again (R7) keeping the selection and the rows on screen:
  /// the first visible row stays where it was.
  Future<void> refresh() async {
    final c = controller;
    String? anchor;
    var delta = 0.0;
    if (_scroll.hasClients && c.rows.isNotEmpty) {
      final top = _scroll.offset - _listTop;
      final i = (top / graphRowHeight).floor().clamp(0, c.rows.length - 1);
      anchor = c.rows[i].sha;
      delta = top - i * graphRowHeight;
    }
    await c.refresh();
    if (_disposed || anchor == null || !_scroll.hasClients) return;
    final i = c.rows.indexWhere((r) => r.sha == anchor);
    if (i < 0) return;
    final to = (_listTop + i * graphRowHeight + delta).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    if ((to - _scroll.offset).abs() > .5) _scroll.jumpTo(to);
  }

  /// Top padding of the list.
  static const _listTop = 4.0;

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

  /// Brings row [i] to the middle of the list (a search result).
  void _reveal(int i) {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    final to = (_listTop + i * graphRowHeight - p.viewportDimension / 2).clamp(
      0.0,
      p.maxScrollExtent,
    );
    _scroll.jumpTo(to);
  }

  void _onSearch(String text) {
    controller.setSearch(text);
    final row = controller.currentMatchRow;
    if (row != null) _reveal(row);
  }

  void _nextMatch() {
    final row = controller.nextMatch();
    if (row != null) _reveal(row);
    _searchFocus.requestFocus();
  }

  /// A request from outside (SPEC-046), once.
  void _takeRequest() {
    final r = ref.read(graphRequestProvider.notifier).take();
    if (r == null) return;
    unawaited(() async {
      await controller.setDay(r.day);
      if (_disposed) return;
      if (r.search != null) {
        _search.text = r.search!;
        _onSearch(r.search!);
      }
      if (r.select != null) {
        controller.select(r.select);
        final i = controller.rows.indexWhere((x) => x.sha == r.select);
        if (i >= 0) _reveal(i);
      }
    }());
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
    if (ref.watch(graphRequestProvider) != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _takeRequest();
      });
    }
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
    final selectedRow = c.selected == null
        ? null
        : c.rows.where((r) => r.sha == c.selected).firstOrNull;
    final compact = selectedRow != null;
    final current = c.currentMatchRow;

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
    } else if (c.rows.isEmpty) {
      body = Center(
        child: Text(
          c.query.day != null
              ? 'Nenhum commit neste dia.'
              : 'Nenhum commit para mostrar.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
      );
    } else {
      body = Stack(
        key: _stackKey,
        children: [
          ListView.builder(
            key: const ValueKey('graph-list'),
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 24,
              _listTop,
              compact ? 12 : 24,
              24,
            ),
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
                match: i == current
                    ? GraphMatch.current
                    : c.isMatch(i)
                    ? GraphMatch.other
                    : GraphMatch.none,
                compact: compact,
                now: now,
                specTitles: titles,
                prs: prs,
                busyBranches: busy,
                authorBadge: badge,
                onTap: () => c.select(c.selected == row.sha ? null : row.sha),
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

    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(
          controller: c,
          search: _search,
          searchFocus: _searchFocus,
          compact: compact,
          onSearch: _onSearch,
          onNext: _nextMatch,
        ),
        if (!compact) _ColumnTitles(graphWidth: graphWidth),
        Expanded(child: body),
      ],
    );
    if (selectedRow == null) return list;
    return LayoutBuilder(
      builder: (context, box) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: list),
          Container(width: 1, color: AppColors.border),
          SizedBox(
            width: (box.maxWidth * .33).clamp(360.0, 520.0),
            child: CommitPanel(
              controller: c,
              row: selectedRow,
              repo: widget.repo,
              onClose: () => c.select(null),
            ),
          ),
        ],
      ),
    );
  }
}

/// How a row stands in the search (R6).
enum GraphMatch { none, other, current }

const _toolbarBorder = Color(0xFF1E232C);

/// Header of the tab (R6; Grafo.dc.html): what to show, the search, the
/// remote-only branches and the count.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.search,
    required this.searchFocus,
    required this.onSearch,
    required this.onNext,
    this.compact = false,
  });

  final GraphController controller;
  final TextEditingController search;
  final FocusNode searchFocus;
  final ValueChanged<String> onSearch;
  final VoidCallback onNext;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final q = c.query;
    Widget scope(GraphScope s, String label, {bool first = false}) {
      final on = q.scope == s;
      return Semantics(
        button: true,
        selected: on,
        child: InkWell(
          key: ValueKey('graph-scope-${s.name}'),
          onTap: () => unawaited(c.setScope(s)),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? AppColors.amberTint : Colors.transparent,
              border: first
                  ? null
                  : const Border(left: BorderSide(color: AppColors.border)),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: on ? AppColors.amber : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    final searching = search.text.trim().isNotEmpty;
    final counter = !searching
        ? null
        : c.matches.isEmpty
        ? 'nenhum'
        : '${c.currentMatch + 1} de ${c.matches.length} · Enter';
    final day = q.day;
    return Container(
      height: 60,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 24),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _toolbarBorder)),
      ),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                scope(GraphScope.all, 'Todas as branches', first: true),
                scope(GraphScope.defaultBranch, 'Só a ${c.defaultBranch}'),
                scope(GraphScope.openSpecs, 'Specs abertas'),
              ],
            ),
          ),
          if (day != null) ...[
            const SizedBox(width: 8),
            InputChip(
              key: const ValueKey('graph-day'),
              label: Text(
                'Só ${day.day} ${_months[day.month - 1]} ${day.year}',
                style: const TextStyle(fontSize: 12),
              ),
              onDeleted: () => unawaited(c.setDay(null)),
              deleteButtonTooltipMessage: 'Todos os dias',
            ),
          ],
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: compact ? double.infinity : 380,
                ),
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppColors.panel,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search,
                        size: 15,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('graph-search'),
                          controller: search,
                          focusNode: searchFocus,
                          onChanged: onSearch,
                          onSubmitted: (_) => onNext(),
                          onEditingComplete: () {},
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: 'Mensagem, SHA, autor ou SPEC-NNN',
                            hintStyle: TextStyle(
                              fontSize: 13,
                              color: AppColors.textMuted,
                            ),
                            semanticCounterText: 'Buscar commits',
                          ),
                        ),
                      ),
                      if (counter != null)
                        Text(
                          counter,
                          key: const ValueKey('graph-search-counter'),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 12),
            Flexible(
              flex: 2,
              child: InkWell(
                key: const ValueKey('graph-remote-only'),
                onTap: () => unawaited(c.setRemoteOnly(!q.remoteOnly)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 16,
                      child: Checkbox(
                        value: q.remoteOnly,
                        onChanged: (v) =>
                            unawaited(c.setRemoteOnly(v ?? false)),
                        activeColor: AppColors.amber,
                        checkColor: AppColors.onAmber,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        'Branches só no remoto',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (c.loaded)
              Flexible(
                child: Text(
                  '${formatThousands(c.commits.length)} de '
                  '${formatThousands(c.total)} commits',
                  key: const ValueKey('graph-count'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
          ],
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
      border: Border(bottom: BorderSide(color: _toolbarBorder)),
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
    this.match = GraphMatch.none,
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

  /// A result of the search (R6).
  final GraphMatch match;

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
        color: selected
            ? const Color(0xFF1A2130)
            : switch (match) {
                GraphMatch.current => AppColors.amberTint,
                GraphMatch.other => AppColors.amber.withValues(alpha: .05),
                GraphMatch.none => Colors.transparent,
              },
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
