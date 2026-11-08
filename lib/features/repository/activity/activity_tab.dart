import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/git_service.dart' show gitServiceFactoryProvider;
import '../../../data/providers.dart';
import '../../../ui/shell/navigation.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/info_tip.dart';
import '../../board/board_screen.dart' show boardSelectedSpecProvider;
import '../../code/code_model.dart' show codeWorktreeModelProvider;
import '../../project/project_config.dart';
import '../../project/widgets/agent_trailer_dialog.dart';
import '../graph/graph_tab.dart' show openGraph;
import '../releases/releases_tab.dart' show GhStatusLabel;
import '../releases/unreleased.dart' show CliffRules;
import '../repository_info.dart';
import '../repository_screen.dart';
import 'activity_charts.dart';
import 'activity_log.dart';
import 'activity_stats.dart';

/// The Atividade tab (SPEC-046; docs/mockups/spec-046/).
final activityTab = RepositoryTab(
  id: 'atividade',
  label: 'Atividade',
  builder: (context, repo) => ActivityTab(repo: repo),
  headerTrailing: (context, repo) => GhStatusLabel(repo: repo),
);

/// The period chosen (R1), kept in the app settings.
class ActivityPeriodController extends Notifier<ActivityPeriod> {
  static const settingKey = 'repo.atividade.periodo';

  @override
  ActivityPeriod build() {
    final saved = ref.read(appSettingsProvider.notifier).get(settingKey);
    return ActivityPeriod.values.where((p) => p.name == saved).firstOrNull ??
        ActivityPeriod.days90;
  }

  void select(ActivityPeriod p) {
    state = p;
    unawaited(ref.read(appSettingsProvider.notifier).set(settingKey, p.name));
  }
}

final activityPeriodProvider =
    NotifierProvider<ActivityPeriodController, ActivityPeriod>(
      ActivityPeriodController.new,
    );

/// The reader of a repository (overridden by the tests).
final activityReaderFactoryProvider =
    Provider<ActivityLogReader Function(RepositoryInfo)>((ref) {
      final gitFor = ref.watch(gitServiceFactoryProvider);
      final dir = ref.watch(activityCacheDirProvider);
      return (repo) => ActivityLogReader(
        gitFor(repo.path),
        defaultBranch: repo.defaultBranch,
        remote: repo.remote,
        cacheDir: dir,
      );
    });

/// Runs [buildActivityReports] off the UI thread (R6).
final activityComputeProvider =
    Provider<Future<ActivityReports> Function(ActivityInput)>(
      (ref) =>
          (input) => Isolate.run(() => buildActivityReports(input)),
    );

/// Clock of the tab (the tests fix it).
final activityNowProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Reports already worked out, by repository, tips, tags and day: opening
/// the tab again without new commits shows them at once (R6).
final _memo = <String, ActivityReports>{};

/// The Atividade of a repository: the log (cache by tip, R6) and the
/// reports of the three periods, worked out in another isolate.
final activityProvider = FutureProvider.autoDispose
    .family<ActivityReports, RepositoryInfo>((ref, repo) async {
      final reader = ref.watch(activityReaderFactoryProvider)(repo);
      final now = ref.watch(activityNowProvider)();
      final compute = ref.watch(activityComputeProvider);
      final load = await reader.load();
      final log = load.log;
      final key = [
        repo.path,
        repo.defaultBranch,
        dayOf(now).toIso8601String(),
        for (final e in log.tips.entries) '${e.key}=${e.value}',
        for (final t in log.tags) t.name,
      ].join('|');
      final hit = _memo[key];
      if (hit != null) return hit;
      final file = File('${repo.path}/cliff.toml');
      final cliff = await file.exists()
          ? CliffRules.parse(await file.readAsString())
          : CliffRules.promptorium;
      final reports = await compute(
        ActivityInput(
          log: log,
          defaultBranch: repo.defaultBranch,
          now: now,
          cliff: cliff,
        ),
      );
      _memo
        ..removeWhere((k, _) => k.startsWith('${repo.path}|'))
        ..[key] = reports;
      return reports;
    });

// --- formatting ----------------------------------------------------------

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
const _weekdays = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];

/// `4.392`.
String fmtInt(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '−' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

/// `1,8`.
String fmtDecimal(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

/// `1,8 d`.
String fmtDays(double v) => '${fmtDecimal(v)} d';

/// `8 nov`.
String fmtDay(DateTime d) => '${d.day} ${_months[d.month - 1]}';

String _plural(int n, String one, String many) =>
    '${fmtInt(n)} ${n == 1 ? one : many}';

// --- colours ---------------------------------------------------------------

/// Colour of a group of "Commits por tipo" (R3).
Color typeColor(String group, int index) => switch (group) {
  'Funcionalidades' => AppColors.amber,
  'Correções' => const Color(0xFF8EC5FF),
  'Documentação' => const Color(0xFFC59BFF),
  'Testes' => const Color(0xFF5BC88A),
  'Refatoração' => const Color(0xFFF08A4B),
  'Desempenho' => const Color(0xFFD9C27A),
  'Build e CI' => const Color(0xFFE07AB0),
  'Manutenção' => AppColors.teal,
  'Reversões' => AppColors.red,
  otherGroup => const Color(0xFF7C8595),
  _ => SpecColors.palette[(index + 4) % SpecColors.palette.length],
};

/// Colours of "Quem fez os commits" (R8).
abstract final class OriginColors {
  static const person = Color(0xFF8EC5FF);
  static const agent = AppColors.amber;
  static const app = Color(0xFFC59BFF);
  static const unmarked = Color(0xFF3B4150);

  /// The bars behind the "desligado" card.
  static const off = Color(0xFF222731);
}

const _green = Color(0xFF5BC88A);

// --- the tab ---------------------------------------------------------------

class ActivityTab extends ConsumerWidget {
  const ActivityTab({super.key, required this.repo});

  final RepositoryInfo repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(activityPeriodProvider);
    final async = ref.watch(activityProvider(repo));
    final reports = async.value;
    final Widget body;
    if (async.hasError && reports == null) {
      body = Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Center(
          child: Text(
            'Não foi possível ler o histórico: ${async.error}',
            style: const TextStyle(color: AppColors.red, fontSize: 13),
          ),
        ),
      );
    } else if (reports == null) {
      body = const _Skeleton();
    } else {
      body = _Cards(
        repo: repo,
        report: reports[period],
        allCycles: reports.cycles,
      );
    }
    final n = period.days;
    return SingleChildScrollView(
      key: const ValueKey('activity-scroll'),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Branch ${repo.defaultBranch} e branches de spec · '
                  '${period == ActivityPeriod.year ? 'último ano, comparado com o anterior' : 'últimos $n dias, comparados com os $n anteriores'}',
                  key: const ValueKey('activity-caption'),
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              _PeriodSelector(
                value: period,
                onChanged: ref.read(activityPeriodProvider.notifier).select,
              ),
            ],
          ),
          const SizedBox(height: 16),
          body,
        ],
      ),
    );
  }
}

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({required this.value, required this.onChanged});

  final ActivityPeriod value;
  final ValueChanged<ActivityPeriod> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    height: 36,
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    clipBehavior: Clip.antiAlias,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, p) in ActivityPeriod.values.indexed) ...[
          if (i > 0) Container(width: 1, color: AppColors.border),
          Semantics(
            selected: p == value,
            button: true,
            child: InkWell(
              key: ValueKey('activity-period-${p.name}'),
              onTap: () => onChanged(p),
              child: Container(
                color: p == value ? AppColors.amberTint : null,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                child: Text(
                  p.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: p == value ? AppColors.amber : AppColors.text,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

/// A card of the tab.
class _Card extends StatelessWidget {
  const _Card({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: AppColors.panel,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(10),
    ),
    child: child,
  );
}

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Align(
          alignment: Alignment.centerRight,
          child: DefaultTextStyle.merge(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: trailing ?? const SizedBox.shrink(),
          ),
        ),
      ),
    ],
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 1,
      color: AppColors.textSecondary,
    ),
  );
}

/// A note in place of a number without a source (R7).
class _Note extends StatelessWidget {
  const _Note(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ),
    ),
  );
}

/// The cards while the numbers are worked out (R6).
class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    Widget block(double h, {double? w}) => Container(
      height: h,
      width: w,
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(6),
      ),
    );
    Widget card(double h) => _Card(
      child: SizedBox(
        height: h,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            block(14, w: 140),
            const SizedBox(height: 16),
            Expanded(child: block(double.infinity)),
          ],
        ),
      ),
    );
    return Semantics(
      label: 'Calculando a atividade do repositório',
      child: Column(
        key: const ValueKey('activity-skeleton'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 16),
                Expanded(child: card(52)),
              ],
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 314,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 5, child: card(280)),
                const SizedBox(width: 16),
                Expanded(flex: 7, child: card(280)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          card(220),
        ],
      ),
    );
  }
}

class _Cards extends ConsumerWidget {
  const _Cards({
    required this.repo,
    required this.report,
    required this.allCycles,
  });

  final RepositoryInfo repo;
  final ActivityReport report;
  final List<SpecCycle> allCycles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(activeWorkspaceProvider);
    final specs = ws == null
        ? const <Spec>[]
        : ref.watch(specsProvider(ws.id)).value ?? const <Spec>[];
    final sprints = ws == null
        ? const <Sprint>[]
        : ref.watch(sprintsProvider(ws.id)).value ?? const <Sprint>[];
    final marking = ws == null
        ? false
        : ref
                  .watch(projectConfigProvider(ws.path))
                  .value
                  ?.git
                  .markAgentCommits ??
              false;
    final byCode = {for (final s in specs) s.code: s};

    void openSpec(String code) {
      final s = byCode[code];
      if (s == null) return;
      ref.read(boardSelectedSpecProvider.notifier).select(s.id);
      ref.read(navigationProvider.notifier).request(AppSection.tasks);
    }

    final done = [
      for (final s in sprints)
        if (s.state == SprintState.done)
          (id: s.id, name: s.name, position: s.position, closedAt: s.closedAt),
    ];
    final bySprint = sprintCycles(
      doneSprints: done,
      specSprint: {
        for (final s in specs)
          if (s.sprintId != null) s.code: s.sprintId!,
      },
      cycles: allCycles,
      from: report.from,
      to: report.to,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SummaryRow(report: report),
        const SizedBox(height: 16),
        SizedBox(
          height: 336,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5,
                child: _HeatmapCard(
                  report: report,
                  onDay: (d) => openGraph(ref, day: d),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(flex: 7, child: _TypesCard(report: report)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _CycleCard(
          report: report,
          titles: {for (final s in specs) s.code: s.title},
          sprints: bySprint,
          hasSprints: sprints.isNotEmpty,
          onSpec: openSpec,
        ),
        const SizedBox(height: 16),
        _FilesCard(
          report: report,
          titles: {for (final s in specs) s.code: s.title},
          onSpec: openSpec,
          onCommit: (sha) => openGraph(ref, select: sha),
          onCode: ws == null
              ? null
              : (path) async {
                  await ref
                      .read(appSettingsProvider.notifier)
                      .set(AppSettingKeys.codeWorktree(ws.id), ws.path);
                  await ref.read(codeWorktreeModelProvider(ws.path)).open(path);
                  ref
                      .read(navigationProvider.notifier)
                      .request(AppSection.code);
                },
        ),
        const SizedBox(height: 16),
        WhoMadeCard(
          report: report,
          marking: marking,
          onEnable: ws == null
              ? null
              : () => showAgentTrailerDialog(context, workspace: ws),
        ),
      ],
    );
  }
}

// --- R1 · summary ----------------------------------------------------------

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.report});

  final ActivityReport report;

  @override
  Widget build(BuildContext context) {
    final s = report.summary;
    final n = report.period.days;
    final prevLabel = report.period == ActivityPeriod.year
        ? 'que o ano anterior'
        : 'que os $n dias anteriores';
    final commitsChange = changeLabel(s.commits, s.prevCommits);
    final specDiff = s.specsMerged - s.prevSpecsMerged;
    final releases = s.releases;
    final relDiff = releases == null ? 0 : releases - (s.prevReleases ?? 0);
    final med = s.medianCycle, prevMed = s.prevMedianCycle;
    final medDiff = med == null || prevMed == null ? null : med - prevMed;

    String signed(int v) => v > 0 ? '+${fmtInt(v)}' : fmtInt(v);
    Color tone(num v, {bool lowerIsBetter = false}) =>
        (lowerIsBetter ? v < 0 : v > 0) ? _green : AppColors.textSecondary;

    return Row(
      children: [
        Expanded(
          child: _Tile(
            key: const ValueKey('activity-summary-commits'),
            label: 'Commits',
            value: fmtInt(s.commits),
            note: commitsChange == null ? null : '$commitsChange $prevLabel',
            noteColor: tone(s.commits - s.prevCommits),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _Tile(
            key: const ValueKey('activity-summary-specs'),
            label: 'Specs mergeadas',
            value: fmtInt(s.specsMerged),
            note: specDiff == 0 ? null : signed(specDiff),
            noteColor: tone(specDiff),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _Tile(
            key: const ValueKey('activity-summary-releases'),
            label: 'Releases',
            value: releases == null ? '—' : fmtInt(releases),
            note: releases == null
                ? 'Sem tags no repositório'
                : s.firstRelease == null
                ? (relDiff == 0 ? null : signed(relDiff))
                : s.firstRelease == s.lastRelease
                ? s.firstRelease
                : '${s.firstRelease} a ${s.lastRelease}',
            noteColor: AppColors.textSecondary,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _Tile(
            key: const ValueKey('activity-summary-cycle'),
            label: 'Ciclo mediano das specs',
            value: med == null
                ? '—'
                : '${fmtDecimal(med)} ${med < 2 ? 'dia' : 'dias'}',
            note: !report.cycle.hasSpecBranches
                ? 'Sem branches de spec'
                : med == null
                ? 'Nenhuma spec mergeada'
                : medDiff == null || medDiff.abs() < .05
                ? null
                : '${medDiff > 0 ? '+' : '−'}${fmtDecimal(medDiff.abs())} '
                      '${medDiff.abs() < 2 ? 'dia' : 'dias'}',
            noteColor: medDiff == null
                ? AppColors.textSecondary
                : tone(medDiff, lowerIsBetter: true),
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.label,
    required this.value,
    this.note,
    this.noteColor = AppColors.textSecondary,
  });

  final String label;
  final String value;
  final String? note;
  final Color noteColor;

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            ),
            if (note != null) ...[
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  note!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: noteColor),
                ),
              ),
            ],
          ],
        ),
      ],
    ),
  );
}

// --- balloon ---------------------------------------------------------------

class _Balloon extends StatelessWidget {
  const _Balloon({required this.lines, super.key});

  final List<(String, Color?)> lines;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 280),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.borderHover),
      boxShadow: const [
        BoxShadow(
          color: Color(0x66000000),
          blurRadius: 16,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, (text, color)) in lines.indexed)
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400,
              color:
                  color ?? (i == 0 ? AppColors.text : AppColors.textSecondary),
            ),
          ),
      ],
    ),
  );
}

// --- R2 · map --------------------------------------------------------------

/// The lines of the balloon of [day] (R2).
List<String> dayBalloon(ActivityReport r, DateTime day) {
  final cell = r.days[day];
  final n = cell?.commits ?? 0;
  return [
    '${_weekdays[day.weekday - 1]}, ${fmtDay(day)} · '
        '${n == 0 ? 'nenhum commit' : _plural(n, 'commit', 'commits')}',
    if (cell != null && cell.specs.isNotEmpty) cell.specs.join(', '),
    if (r.releaseDays[day] case final tags?) 'Release ${tags.join(', ')}',
  ];
}

class _HeatmapCard extends StatefulWidget {
  const _HeatmapCard({required this.report, required this.onDay});

  final ActivityReport report;
  final ValueChanged<DateTime> onDay;

  @override
  State<_HeatmapCard> createState() => _HeatmapCardState();
}

class _HeatmapCardState extends State<_HeatmapCard> {
  DateTime? _hover;
  Offset? _at;

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final today = dayOf(r.to);
    final start = weekOf(r.from);
    final weeks = daysBetween(start, weekOf(today)) ~/ 7 + 1;
    return _Card(
      key: const ValueKey('activity-heatmap-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
            'Commits por dia',
            trailing: r.hasTags
                ? const Text(
                    'anel = dia de release',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  )
                : const Text(
                    'sem tags: nenhum dia de release',
                    key: ValueKey('activity-no-tags'),
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, box) {
              const left = 34.0, gap = 4.0;
              final cell = ((box.maxWidth - left) / weeks - gap).clamp(
                6.0,
                26.0,
              );
              final g = HeatmapGeometry(
                start: start,
                weeks: weeks,
                cell: cell,
                gap: gap,
                left: left,
              );
              final cells = <HeatCell>[];
              for (
                var d = r.from;
                !d.isAfter(today);
                d = DateTime(d.year, d.month, d.day + 1)
              ) {
                cells.add(
                  HeatCell(
                    d,
                    r.level(r.days[d]?.commits ?? 0),
                    release: r.releaseDays.containsKey(d),
                  ),
                );
              }
              final months = <int, String>{};
              var lastMonth = -1;
              for (var c = 0; c < weeks; c++) {
                final monday = DateTime(
                  start.year,
                  start.month,
                  start.day + c * 7,
                );
                // The month of the week's first day inside the period.
                final first = monday.isBefore(r.from) ? r.from : monday;
                if (first.month != lastMonth) {
                  if (months.isEmpty ||
                      c - months.keys.last >= (weeks > 20 ? 3 : 2)) {
                    months[c] = _months[first.month - 1];
                  }
                  lastMonth = first.month;
                }
              }
              DateTime? inside(Offset p) {
                final d = g.dayAt(p);
                if (d == null || d.isBefore(r.from) || d.isAfter(today)) {
                  return null;
                }
                return d;
              }

              final size = g.size;
              return SizedBox(
                width: box.maxWidth,
                height: size.height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    MouseRegion(
                      cursor: _hover == null
                          ? MouseCursor.defer
                          : SystemMouseCursors.click,
                      onHover: (e) {
                        final d = inside(e.localPosition);
                        if (d != _hover || d != null) {
                          setState(() {
                            _hover = d;
                            _at = e.localPosition;
                          });
                        }
                      },
                      onExit: (_) => setState(() => _hover = null),
                      child: GestureDetector(
                        key: const ValueKey('activity-heatmap'),
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (e) {
                          final d = inside(e.localPosition);
                          if (d != null) widget.onDay(d);
                        },
                        child: CustomPaint(
                          size: size,
                          painter: HeatmapPainter(
                            geometry: g,
                            cells: cells,
                            months: months,
                            hover: _hover,
                          ),
                        ),
                      ),
                    ),
                    if (_hover != null && _at != null)
                      Positioned(
                        left: math.min(_at!.dx + 14, box.maxWidth - 200),
                        top: _at!.dy + 14,
                        child: IgnorePointer(
                          child: _Balloon(
                            key: const ValueKey('activity-day-balloon'),
                            lines: [
                              for (final l in dayBalloon(r, _hover!)) (l, null),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                'menos',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
              const SizedBox(width: 6),
              for (final c in HeatmapColors.tones) ...[
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              const SizedBox(width: 2),
              const Flexible(
                child: Text(
                  'mais · clique leva ao Grafo do dia',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- R3 · types ------------------------------------------------------------

/// `semana de 3 nov`.
String weekLabel(DateTime w) => 'semana de ${fmtDay(w)}';

class _TypesCard extends StatefulWidget {
  const _TypesCard({required this.report});

  final ActivityReport report;

  @override
  State<_TypesCard> createState() => _TypesCardState();
}

class _TypesCardState extends State<_TypesCard> {
  final _hidden = <String>{};
  int? _hover;
  Offset? _at;

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final groups = r.typeGroups;
    final colors = {for (final (i, g) in groups.indexed) g: typeColor(g, i)};
    final visible = [
      for (final g in groups)
        if (!_hidden.contains(g)) g,
    ];
    final bars = [
      for (final w in r.typeWeeks)
        [for (final g in visible) (color: colors[g]!, value: w.counts[g] ?? 0)],
    ];
    final max = bars.fold(
      0,
      (m, b) => math.max(m, b.fold(0, (s, p) => s + p.value)),
    );
    return _Card(
      key: const ValueKey('activity-types-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('Commits por tipo, por semana'),
          const SizedBox(height: 12),
          SizedBox(
            height: 210,
            child: groups.isEmpty
                ? const _Note('Nenhum commit neste período.')
                : LayoutBuilder(
                    builder: (context, box) {
                      const gap = 8.0;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          MouseRegion(
                            onHover: (e) {
                              final i = StackedBarsPainter.barAt(
                                e.localPosition.dx,
                                box.maxWidth,
                                bars.length,
                                gap,
                              );
                              setState(() {
                                _hover = i;
                                _at = e.localPosition;
                              });
                            },
                            onExit: (_) => setState(() => _hover = null),
                            child: CustomPaint(
                              key: const ValueKey('activity-types-chart'),
                              size: Size(box.maxWidth, box.maxHeight),
                              painter: StackedBarsPainter(
                                bars: bars,
                                max: max,
                                hover: _hover,
                                gap: gap,
                              ),
                            ),
                          ),
                          if (_hover != null && _at != null)
                            Positioned(
                              left: math.min(_at!.dx + 14, box.maxWidth - 200),
                              top: math.min(_at!.dy, box.maxHeight - 120),
                              child: IgnorePointer(
                                child: _Balloon(
                                  lines: [
                                    (
                                      weekLabel(r.typeWeeks[_hover!].week),
                                      null,
                                    ),
                                    for (final g in visible.reversed)
                                      if ((r.typeWeeks[_hover!].counts[g] ??
                                              0) >
                                          0)
                                        (
                                          '$g: ${r.typeWeeks[_hover!].counts[g]}',
                                          colors[g],
                                        ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              for (final g in groups)
                Semantics(
                  button: true,
                  toggled: !_hidden.contains(g),
                  label: _hidden.contains(g) ? 'Mostrar $g' : 'Esconder $g',
                  child: InkWell(
                    key: ValueKey('activity-type-$g'),
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => setState(
                      () => _hidden.contains(g)
                          ? _hidden.remove(g)
                          : _hidden.add(g),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: _hidden.contains(g)
                                  ? Colors.transparent
                                  : colors[g],
                              border: Border.all(color: colors[g]!),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            g,
                            style: TextStyle(
                              fontSize: 12,
                              color: _hidden.contains(g)
                                  ? AppColors.textMuted
                                  : AppColors.textSecondary,
                              decoration: _hidden.contains(g)
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- R4 · cycle ------------------------------------------------------------

class _CycleCard extends StatelessWidget {
  const _CycleCard({
    required this.report,
    required this.titles,
    required this.sprints,
    required this.hasSprints,
    required this.onSpec,
  });

  final ActivityReport report;
  final Map<String, String> titles;
  final List<SprintCycle> sprints;
  final bool hasSprints;
  final ValueChanged<String> onSpec;

  @override
  Widget build(BuildContext context) {
    final c = report.cycle;
    final base =
        'Do primeiro commit da branch ao merge na branch padrão. '
        'Filhas contam dentro da pai.';
    if (!c.hasSpecBranches || c.cycles.isEmpty) {
      return _Card(
        key: const ValueKey('activity-cycle-card'),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _CardTitle('Ciclo das specs'),
            _Note(
              !c.hasSpecBranches
                  ? 'Este repositório não usa branches de spec.'
                  : 'Nenhuma spec mergeada neste período.',
              key: const ValueKey('activity-cycle-note'),
            ),
          ],
        ),
      );
    }
    final longest = c.longest;
    final top = longest.first.days!;
    final sprintTop = sprints.fold(0.0, (m, s) => math.max(m, s.median));
    Widget metric(String value, String label) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
    Widget bar(double frac, Color color) => Container(
      height: 8,
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: frac.clamp(0.02, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
    const mono = TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: 12,
      color: AppColors.textSecondary,
    );
    return _Card(
      key: const ValueKey('activity-cycle-card'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 230,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _CardTitle('Ciclo das specs'),
                const SizedBox(height: 10),
                Text(
                  base,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 24,
                  runSpacing: 8,
                  children: [
                    KeyedSubtree(
                      key: const ValueKey('activity-cycle-median'),
                      child: metric(fmtDays(c.median!), 'mediana'),
                    ),
                    KeyedSubtree(
                      key: const ValueKey('activity-cycle-p90'),
                      child: metric(fmtDays(c.p90!), 'percentil 90'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionLabel('As mais longas'),
                const SizedBox(height: 8),
                for (final s in longest)
                  InkWell(
                    key: ValueKey('activity-longest-${s.code}'),
                    onTap: titles.containsKey(s.code)
                        ? () => onSpec(s.code)
                        : null,
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 32,
                      child: Row(
                        children: [
                          SizedBox(width: 82, child: Text(s.code, style: mono)),
                          Expanded(
                            flex: 3,
                            child: Text(
                              titles[s.code] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: bar(s.days! / top, const Color(0xFF8EC5FF)),
                          ),
                          SizedBox(
                            width: 64,
                            child: Text(
                              fmtDays(s.days!),
                              textAlign: TextAlign.right,
                              style: mono,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (hasSprints) ...[
            const SizedBox(width: 32),
            Expanded(
              flex: 2,
              child: Column(
                key: const ValueKey('activity-sprints'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionLabel('Mediana por sprint'),
                  const SizedBox(height: 8),
                  if (sprints.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Nenhuma sprint concluída neste período.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  for (final s in sprints)
                    SizedBox(
                      key: ValueKey('activity-sprint-${s.name}'),
                      height: 32,
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              s.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: bar(
                              sprintTop == 0 ? 0 : s.median / sprintTop,
                              const Color(0xFFC59BFF),
                            ),
                          ),
                          SizedBox(
                            width: 56,
                            child: Text(
                              fmtDays(s.median),
                              textAlign: TextAlign.right,
                              style: mono,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// --- R5 · files ------------------------------------------------------------

/// The specs of a file's history, newest first: (spec or null, commits).
List<(String?, List<FileCommit>)> fileSpecGroups(FileStat f) {
  final out = <(String?, List<FileCommit>)>[];
  final index = <String?, int>{};
  for (final h in f.history) {
    final i = index[h.spec];
    if (i == null) {
      index[h.spec] = out.length;
      out.add((h.spec, [h]));
    } else {
      out[i].$2.add(h);
    }
  }
  return out;
}

class _FilesCard extends StatefulWidget {
  const _FilesCard({
    required this.report,
    required this.titles,
    required this.onSpec,
    required this.onCommit,
    this.onCode,
  });

  final ActivityReport report;
  final Map<String, String> titles;
  final ValueChanged<String> onSpec;
  final ValueChanged<String> onCommit;
  final Future<void> Function(String path)? onCode;

  @override
  State<_FilesCard> createState() => _FilesCardState();
}

class _FilesCardState extends State<_FilesCard> {
  String? _open;

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final files = r.files;
    final open = files.where((f) => f.path == _open).firstOrNull;
    final maxCommits = files.fold(0, (m, f) => math.max(m, f.commits));
    const head = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 1,
      color: AppColors.textSecondary,
    );
    const mono = TextStyle(fontFamily: AppFonts.mono, fontSize: 12);
    final table = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Text(
              'Arquivos mais alterados',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                '${r.period.label} · sem *.g.dart e pubspec.lock',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (files.isEmpty)
          const _Note('Nenhum arquivo alterado neste período.')
        else ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(flex: 5, child: Text('ARQUIVO', style: head)),
                Expanded(flex: 3, child: Text('COMMITS', style: head)),
                SizedBox(
                  width: 70,
                  child: Text(
                    'LINHAS',
                    textAlign: TextAlign.right,
                    style: head,
                  ),
                ),
                SizedBox(
                  width: 60,
                  child: Text('SPECS', textAlign: TextAlign.right, style: head),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          for (final f in files)
            Material(
              color: f.path == _open
                  ? const Color(0xFF1A2130)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                key: ValueKey('activity-file-${f.path}'),
                borderRadius: BorderRadius.circular(6),
                onTap: () =>
                    setState(() => _open = _open == f.path ? null : f.path),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: f.path == _open
                      ? const BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: Color(0xFF8EC5FF),
                              width: 2,
                            ),
                          ),
                        )
                      : null,
                  child: Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: Text(
                          f.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: mono,
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            Flexible(
                              child: FractionallySizedBox(
                                widthFactor: maxCommits == 0
                                    ? 0
                                    : f.commits / maxCommits,
                                child: Container(
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: AppColors.amber,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 34,
                              child: Text('${f.commits}', style: mono),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 70,
                        child: Text(
                          fmtInt(f.lines),
                          textAlign: TextAlign.right,
                          style: mono.copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                      SizedBox(
                        width: 60,
                        child: Text(
                          '${f.specs.length}',
                          key: ValueKey('activity-file-specs-${f.path}'),
                          textAlign: TextAlign.right,
                          style: mono,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ],
    );
    return _Card(
      key: const ValueKey('activity-files-card'),
      child: open == null
          ? table
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: table),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: _FilePanel(
                    file: open,
                    period: r.period,
                    titles: widget.titles,
                    onSpec: widget.onSpec,
                    onCommit: widget.onCommit,
                    onCode: widget.onCode,
                    onClose: () => setState(() => _open = null),
                  ),
                ),
              ],
            ),
    );
  }
}

class _FilePanel extends StatelessWidget {
  const _FilePanel({
    required this.file,
    required this.period,
    required this.titles,
    required this.onSpec,
    required this.onCommit,
    required this.onClose,
    this.onCode,
  });

  final FileStat file;
  final ActivityPeriod period;
  final Map<String, String> titles;
  final ValueChanged<String> onSpec;
  final ValueChanged<String> onCommit;
  final Future<void> Function(String path)? onCode;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final f = file;
    const mono = TextStyle(fontFamily: AppFonts.mono, fontSize: 12);
    return Container(
      key: const ValueKey('activity-file-panel'),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(f.path, style: mono.copyWith(fontSize: 13)),
                      const SizedBox(height: 4),
                      Text(
                        '${_plural(f.commits, 'commit', 'commits')} · '
                        '+${fmtInt(f.added)} −${fmtInt(f.removed)} linhas · '
                        '${_plural(f.specs.length, 'spec', 'specs')} em '
                        '${period.label}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Fechar',
                  iconSize: 16,
                  onPressed: onClose,
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Container(height: 1, color: AppColors.border),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: _SectionLabel('Specs, da mais nova para a mais antiga'),
          ),
          for (final (spec, commits) in fileSpecGroups(f))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      key: ValueKey('activity-file-spec-${spec ?? 'nenhuma'}'),
                      onTap: spec != null && titles.containsKey(spec)
                          ? () => onSpec(spec)
                          : null,
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: spec == null
                                  ? SpecColors.other
                                  : SpecColors.of(
                                      int.tryParse(spec.substring(5)) ?? 0,
                                    ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            spec ?? 'Sem spec',
                            style: mono.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              spec == null ? '' : titles[spec] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          Text(
                            _plural(commits.length, 'commit', 'commits'),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _FileCommits(
                      key: ValueKey(
                        'activity-file-commits-${spec ?? 'nenhuma'}',
                      ),
                      commits: commits,
                      onCommit: onCommit,
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                OutlinedButton(
                  key: const ValueKey('activity-file-graph'),
                  onPressed: f.history.isEmpty
                      ? null
                      : () => onCommit(f.history.first.sha),
                  child: const Text('Ver no Grafo'),
                ),
                const SizedBox(width: 10),
                if (onCode != null)
                  OutlinedButton(
                    key: const ValueKey('activity-file-code'),
                    onPressed: () => unawaited(onCode!(f.path)),
                    child: const Text('Abrir no Código'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- R8 · who made the commits --------------------------------------------

/// The ⓘ of "Quem fez os commits" (R8).
Widget whoMadeInfoTip({required bool marking, DateTime? since}) => InfoTip(
  key: const ValueKey('activity-who-info'),
  title: 'De onde vem esta separação',
  text:
      'Os commits das sessões do app levam uma linha no fim da mensagem, '
      'com o modelo e a etapa:',
  code: const InfoTipCode(
    ['Promptorium-Agente: sonnet · SPEC-042 R2'],
    highlight: {0},
  ),
  detail: const TextSpan(
    text:
        'Sem a linha, o commit é seu. Com "app", foi o próprio Promptorium '
        'que commitou numa etapa.',
  ),
  footnote: !marking
      ? 'A marcação está desligada neste projeto: o git não separa o que '
            'você e os agentes fizeram.'
      : since == null
      ? 'A marcação está ligada, mas nenhum commit foi marcado ainda.'
      : 'A marcação está ligada desde ${fmtDay(since)}. As semanas '
            'anteriores aparecem em cinza, como sem marca, e não contam '
            'como suas.',
);

class WhoMadeCard extends StatefulWidget {
  const WhoMadeCard({
    super.key,
    required this.report,
    required this.marking,
    this.onEnable,
  });

  final ActivityReport report;

  /// `git: marcar-commits-de-agente` of the project.
  final bool marking;
  final Future<bool> Function()? onEnable;

  @override
  State<WhoMadeCard> createState() => _WhoMadeCardState();
}

class _WhoMadeCardState extends State<WhoMadeCard> {
  int? _hover;
  Offset? _at;

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final o = r.origins;
    final on = widget.marking;
    final since = o.since;
    final bars = [
      for (final w in o.weeks)
        on
            ? <BarPiece>[
                (color: OriginColors.person, value: w.person),
                (color: OriginColors.agent, value: w.agent),
                (color: OriginColors.app, value: w.app),
                (color: OriginColors.unmarked, value: w.unmarked),
              ]
            : <BarPiece>[(color: OriginColors.off, value: w.total)],
    ];
    final max = o.weeks.fold(0, (m, w) => math.max(m, w.total));
    final title = Row(
      children: [
        const Text(
          'Quem fez os commits',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 6),
        whoMadeInfoTip(marking: on, since: since),
        const Spacer(),
        Text(
          !on
              ? 'Marcação desligada'
              : since == null
              ? 'Nenhum commit marcado ainda'
              : 'Marcado desde ${fmtDay(since)} · '
                    '${_plural(o.marked, 'commit', 'commits')}',
          key: const ValueKey('activity-who-status'),
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
      ],
    );
    final firstMarkedWeek = since == null ? null : weekOf(since);
    final chart = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('Por semana'),
        const SizedBox(height: 12),
        SizedBox(
          height: 260,
          child: LayoutBuilder(
            builder: (context, box) {
              const gap = 8.0;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  MouseRegion(
                    onHover: (e) => setState(() {
                      _hover = StackedBarsPainter.barAt(
                        e.localPosition.dx,
                        box.maxWidth,
                        bars.length,
                        gap,
                      );
                      _at = e.localPosition;
                    }),
                    onExit: (_) => setState(() => _hover = null),
                    child: CustomPaint(
                      key: const ValueKey('activity-who-chart'),
                      size: Size(box.maxWidth, box.maxHeight),
                      painter: StackedBarsPainter(
                        bars: bars,
                        max: max,
                        hover: on ? _hover : null,
                        gap: gap,
                      ),
                    ),
                  ),
                  if (on && _hover != null && _at != null)
                    Positioned(
                      left: math.min(_at!.dx + 14, box.maxWidth - 200),
                      top: math.min(_at!.dy, box.maxHeight - 110),
                      child: IgnorePointer(
                        child: _Balloon(
                          lines: [
                            (weekLabel(o.weeks[_hover!].week), null),
                            if (o.weeks[_hover!].person > 0)
                              (
                                'Você: ${o.weeks[_hover!].person}',
                                OriginColors.person,
                              ),
                            if (o.weeks[_hover!].agent > 0)
                              (
                                'Agentes: ${o.weeks[_hover!].agent}',
                                OriginColors.agent,
                              ),
                            if (o.weeks[_hover!].app > 0)
                              (
                                'App: ${o.weeks[_hover!].app}',
                                OriginColors.app,
                              ),
                            if (o.weeks[_hover!].unmarked > 0)
                              ('Sem marca: ${o.weeks[_hover!].unmarked}', null),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        _WeekAxis(
          weeks: [for (final w in o.weeks) w.week],
          marked: on ? firstMarkedWeek : null,
          markedLabel: since == null
              ? null
              : '${fmtDay(since)} · marcação ligada',
        ),
      ],
    );
    if (!on) {
      return _Card(
        key: const ValueKey('activity-who-card'),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            const SizedBox(height: 12),
            Stack(
              alignment: Alignment.center,
              children: [
                chart,
                Container(
                  key: const ValueKey('activity-who-off'),
                  constraints: const BoxConstraints(maxWidth: 520),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.panel,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.borderHover),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Este projeto não marca os commits dos agentes',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Os agentes commitam com o seu nome, então o git não '
                        'separa o que você e eles fizeram. Ligada a marcação, '
                        'os próximos commits das sessões ganham uma linha que '
                        'o app lê aqui.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        key: const ValueKey('activity-who-enable'),
                        onPressed: widget.onEnable == null
                            ? null
                            : () => unawaited(widget.onEnable!()),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.amber,
                          foregroundColor: AppColors.onAmber,
                        ),
                        child: const Text(
                          'Ligar neste projeto',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
    String pct(int n) =>
        o.marked == 0 ? '' : '${(n * 100 / o.marked).round()}%';
    final agents = o.agent;
    return _Card(
      key: const ValueKey('activity-who-card'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: chart),
              const SizedBox(width: 32),
              SizedBox(
                width: 380,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _OriginTile(
                            key: const ValueKey('activity-who-person'),
                            color: OriginColors.person,
                            label: 'Você',
                            value: o.person,
                            note: pct(o.person),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _OriginTile(
                            key: const ValueKey('activity-who-agent'),
                            color: OriginColors.agent,
                            label: 'Agentes',
                            value: o.agent,
                            note: pct(o.agent),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _OriginTile(
                            key: const ValueKey('activity-who-app'),
                            color: OriginColors.app,
                            label: 'App',
                            value: o.app,
                            note: pct(o.app),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _OriginTile(
                            key: const ValueKey('activity-who-unmarked'),
                            color: OriginColors.unmarked,
                            label: 'Sem marca',
                            value: o.unmarked,
                            note: since == null
                                ? 'nenhum marcado'
                                : 'antes de ${fmtDay(since)}',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const _SectionLabel('Commits de agente por modelo'),
                    const SizedBox(height: 8),
                    if (o.models.isEmpty)
                      const Text(
                        'Nenhum commit de agente neste período.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    for (final (model, n) in o.models)
                      SizedBox(
                        key: ValueKey('activity-who-model-$model'),
                        height: 27,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 74,
                              child: Text(
                                model,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: AppFonts.mono,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Container(
                                height: 8,
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceRaised,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: agents == 0 ? 0 : n / agents,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: OriginColors.agent,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 84,
                              child: Text(
                                '$n · ${(n * 100 / agents).round()}%',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontFamily: AppFonts.mono,
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 14),
                    const Text(
                      '"App" é o commit que o próprio app faz numa etapa, '
                      'como "Commitar o que sobrou". Ele pode juntar edição '
                      'sua e do agente.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OriginTile extends StatelessWidget {
  const _OriginTile({
    super.key,
    required this.color,
    required this.label,
    required this.value,
    required this.note,
  });

  final Color color;
  final String label;
  final int value;
  final String note;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              fmtInt(value),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                note,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

/// Month labels under the weekly bars, and the week the marking started.
class _WeekAxis extends StatelessWidget {
  const _WeekAxis({required this.weeks, this.marked, this.markedLabel});

  final List<DateTime> weeks;
  final DateTime? marked;
  final String? markedLabel;

  @override
  Widget build(BuildContext context) {
    if (weeks.isEmpty) return const SizedBox(height: 16);
    final labels = <int, String>{};
    var last = -1;
    for (final (i, w) in weeks.indexed) {
      if (w.month != last) {
        if (labels.isEmpty || i - labels.keys.last >= 3) {
          labels[i] = _months[w.month - 1];
        }
        last = w.month;
      }
    }
    final markedAt = marked == null ? -1 : weeks.indexOf(marked!);
    return LayoutBuilder(
      builder: (context, box) {
        final step = box.maxWidth / weeks.length;
        return SizedBox(
          height: 16,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final e in labels.entries)
                if (markedAt < 0 || (e.key - markedAt).abs() > 2)
                  Positioned(
                    left: e.key * step,
                    child: Text(
                      e.value,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
              if (markedAt >= 0 && markedLabel != null)
                Positioned(
                  left: math.min(markedAt * step, box.maxWidth - 150),
                  child: Text(
                    markedLabel!,
                    key: const ValueKey('activity-who-since'),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The commits of one spec in the file panel: the three newest, and the
/// others on "+N anteriores" (R5).
class _FileCommits extends StatefulWidget {
  const _FileCommits({
    super.key,
    required this.commits,
    required this.onCommit,
  });

  final List<FileCommit> commits;
  final ValueChanged<String> onCommit;

  static const shown = 3;

  @override
  State<_FileCommits> createState() => _FileCommitsState();
}

class _FileCommitsState extends State<_FileCommits> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final all = widget.commits;
    final list = _all ? all : all.take(_FileCommits.shown).toList();
    const style = TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: 11.5,
      color: AppColors.textSecondary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final c in list)
          InkWell(
            key: ValueKey('activity-file-commit-${c.sha}'),
            onTap: () => widget.onCommit(c.sha),
            child: Padding(
              padding: const EdgeInsets.only(left: 16, top: 3),
              child: Text(
                '${c.shortSha} ${c.subject}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ),
        if (!_all && all.length > list.length)
          InkWell(
            onTap: () => setState(() => _all = true),
            child: Padding(
              padding: const EdgeInsets.only(left: 16, top: 3),
              child: Text(
                '+${all.length - list.length} '
                '${all.length - list.length == 1 ? 'anterior' : 'anteriores'}',
                style: const TextStyle(fontSize: 12, color: AppColors.blue),
              ),
            ),
          ),
      ],
    );
  }
}
