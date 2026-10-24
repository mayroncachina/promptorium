import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../ui/shell/navigation.dart';
import '../../ui/theme/tokens.dart';
import '../sessions/session_manager.dart';
import '../specs/workspace_watcher.dart';
import '../specs/widgets/spec_sync_bar.dart';
import '../review/auto_reviewer.dart' show ReviewPhase, reviewerLabel;
import '../agents/widgets/agent_style.dart' show ToggleBox;
import '../sessions/widgets/session_style.dart';
import '../project/project_config.dart' show projectConfigProvider;
import 'autopilot.dart';
import 'board_rules.dart';
import 'spec_runner.dart' show specRunnerProvider, worktreePrepProvider;
import 'step_gate.dart' show tailLines;
import 'widgets/card_extras.dart';
import 'widgets/duel_dialog.dart';
import 'widgets/gate_report_view.dart';
import 'widgets/legacy_tasks_dialog.dart';
import 'widgets/run_spec_dialog.dart';
import 'widgets/schedule_dialog.dart';
import 'widgets/spec_steps_panel.dart';
import 'widgets/subagent_status.dart';
import 'widgets/spec_canvas.dart';
import 'widgets/wave_graph.dart' show dependencyWaves, nextWave;

/// Step rows of every spec of a workspace.
final specStepsProvider = StreamProvider.family<List<SpecStep>, int>(
  (ref, workspaceId) =>
      ref.watch(specStepsRepoProvider).watchByWorkspace(workspaceId),
);

/// Old tasks the schema v8 could not turn into steps.
final legacyTasksProvider = StreamProvider.family<List<Task>, int>(
  (ref, workspaceId) => ref.watch(tasksRepoProvider).watchLegacy(workspaceId),
);

/// Column dot colors.
Color specStageColor(SpecStage s) => switch (s) {
  SpecStage.backlog => AppColors.textMuted,
  SpecStage.running => AppColors.teal,
  SpecStage.review => AppColors.amber,
  SpecStage.done => AppColors.blue,
};

/// Everything a card shows, computed once per build.
@immutable
class SpecCardData {
  const SpecCardData({
    required this.spec,
    required this.steps,
    required this.sessions,
    required this.blockers,
  });

  final Spec spec;
  final List<StepView> steps;

  /// Sessions of the spec, oldest first.
  final List<Session> sessions;
  final List<String> blockers;

  Session? get lastSession => sessions.isEmpty ? null : sessions.last;

  double get cost => sessions.fold(0.0, (a, s) => a + s.costUsd);

  /// Step the card highlights: the one running / waiting, else the next.
  StepView? get current =>
      steps
          .where(
            (s) =>
                s.status == StepStatus.running ||
                s.status == StepStatus.verifying ||
                s.status == StepStatus.needsInput,
          )
          .firstOrNull ??
      steps.where((s) => !s.isDone).firstOrNull;
}

/// Card open in the side panel of the Quadro (UX v2, U8; null = none).
class BoardSelectedSpec extends Notifier<int?> {
  @override
  int? build() => null;

  void select(int? id) => state = id;
}

final boardSelectedSpecProvider = NotifierProvider<BoardSelectedSpec, int?>(
  BoardSelectedSpec.new,
);

/// Card to scroll into view once the Quadro builds it ("Voltar à spec",
/// SPEC-021 R4); cleared by the card.
final boardFocusSpecProvider = NotifierProvider<BoardSelectedSpec, int?>(
  BoardSelectedSpec.new,
);

/// Filters of the Quadro (UX v2, U8): only cards that need the user, one
/// phase, one agent (null = any).
@immutable
class BoardFilter {
  const BoardFilter({this.attention = false, this.phase, this.agent});

  final bool attention;
  final String? phase;
  final String? agent;

  bool get isEmpty => !attention && phase == null && agent == null;

  BoardFilter copyWith({
    bool? attention,
    String? Function()? phase,
    String? Function()? agent,
  }) => BoardFilter(
    attention: attention ?? this.attention,
    phase: phase == null ? this.phase : phase(),
    agent: agent == null ? this.agent : agent(),
  );
}

class BoardFilterController extends Notifier<BoardFilter> {
  /// Cleared when the workspace changes (its phases / agents are others).
  @override
  BoardFilter build() {
    ref.watch(activeWorkspaceProvider.select((w) => w?.id));
    return const BoardFilter();
  }

  void set(BoardFilter f) => state = f;
}

final boardFilterProvider =
    NotifierProvider<BoardFilterController, BoardFilter>(
      BoardFilterController.new,
    );

/// Whether the card waits for the user: a step in `needs_input`, a pending
/// approval, a failed worktree preparation, the spec changed on disk or an
/// A/B ready to compare.
bool needsAttention(
  SpecCardData d, {
  required bool waitingApproval,
  required bool prepFailed,
  required bool changedOnDisk,
  required bool duelReady,
}) =>
    d.spec.stage != SpecStage.done &&
    (d.steps.any((s) => s.status == StepStatus.needsInput) ||
        waitingApproval ||
        prepFailed ||
        changedOnDisk ||
        duelReady);

/// Shared attention text; all waiting steps belong to the same session.
String boardAttentionReason(
  SpecCardData d, {
  bool waitingApproval = false,
  bool prepFailed = false,
  bool changedOnDisk = false,
  bool duelReady = false,
}) {
  if (duelReady) return 'A/B prontas para comparar';
  if (changedOnDisk) return 'spec alterada no disco';
  if (prepFailed) return 'falha ao preparar o worktree';
  if (waitingApproval) return 'aguardando aprovação';
  final waiting = d.steps
      .where((s) => s.status == StepStatus.needsInput)
      .toList();
  if (waiting.isEmpty) return 'Precisa de você';
  final ids = waiting.map((s) => s.id).join(' e ');
  if (waiting.any((s) => s.gateFailed)) return '$ids · verificação falhou';
  return waiting.length == 1 ? '$ids aguardando você' : '$ids aguardam você';
}

/// "Grafo" (dependency waves) instead of the columns.
class BoardGraphView extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool graph) => state = graph;
}

final boardGraphViewProvider = NotifierProvider<BoardGraphView, bool>(
  BoardGraphView.new,
);

/// Cards of one column in their saved order (`specs.board_order`; the rest
/// by code).
List<SpecCardData> orderedCards(Iterable<SpecCardData> cards) =>
    cards.toList()..sort((a, b) => compareBoardOrder(a.spec, b.spec));

/// Order of the cards of a column: `board_order`, then the code.
int compareBoardOrder(Spec a, Spec b) {
  final oa = a.boardOrder, ob = b.boardOrder;
  if (oa != null && ob != null && oa != ob) return oa.compareTo(ob);
  if (oa != null && ob == null) return -1;
  if (oa == null && ob != null) return 1;
  return a.code.compareTo(b.code);
}

/// "↑ / ↓" on [id]: the whole column ([order], filters ignored) with [id]
/// moved next to [neighbor], the card shown above / below it.
List<int> moveInColumn(List<int> order, int id, int neighbor, int delta) {
  final ids = [...order]..remove(id);
  final at = ids.indexOf(neighbor);
  if (at < 0) return order;
  return ids..insert(delta > 0 ? at + 1 : at, id);
}

/// Quadro: one card per approved spec; its requirements are the steps
/// (docs/plano-specs-no-quadro.md).
class BoardScreen extends ConsumerWidget {
  const BoardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(activeWorkspaceProvider);
    if (ws == null) {
      return const _Empty('Selecione um workspace na barra de título.');
    }
    final specs = ref.watch(specsProvider(ws.id)).value ?? const <Spec>[];
    final rows = ref.watch(specStepsProvider(ws.id)).value ?? const [];
    final sessions =
        ref.watch(sessionsProvider(ws.id)).value ?? const <Session>[];
    final legacy = ref.watch(legacyTasksProvider(ws.id)).value ?? const [];
    final byCode = specsByCode(specs);
    final cards = [
      for (final s in specs)
        if (isOnBoard(s))
          SpecCardData(
            spec: s,
            steps: stepsOf(s, rows),
            sessions: [
              for (final x in sessions.reversed)
                if (x.specId == s.id) x,
            ]..sort((a, b) => a.startedAt.compareTo(b.startedAt)),
            // A spec already started keeps going (its dependency may be in
            // Review, released by the autopilot).
            blockers: s.worktreePath == null
                ? specBlockers(s, byCode)
                : const [],
          ),
    ];
    final drafts = specs
        .where((s) => s.status != SpecStatus.archived && !isOnBoard(s))
        .length;
    final filter = ref.watch(boardFilterProvider);
    final manager = ref.watch(sessionManagerProvider);
    final preps = ref.watch(worktreePrepProvider);
    final changed = ref.watch(workspaceWatcherProvider);
    final duels = ref.watch(openDuelsProvider(ws.id)).value ?? const [];
    bool attention(SpecCardData d) {
      final last = d.lastSession;
      return needsAttention(
        d,
        waitingApproval:
            last != null &&
            manager.isAlive(last.id) &&
            last.status == SessionStatus.waitingApproval,
        prepFailed: preps[d.spec.id]?.error != null,
        changedOnDisk: changed.contains(d.spec.id),
        duelReady: duels.any(
          (x) => x.specId == d.spec.id && x.state == 'pronto',
        ),
      );
    }

    final attentionCount = cards.where(attention).length;
    final visible = [
      for (final d in cards)
        if ((!filter.attention || attention(d)) &&
            (filter.phase == null || d.spec.phase == filter.phase) &&
            (filter.agent == null || d.spec.agentName == filter.agent))
          d,
    ];
    final parallel = ref
        .watch(projectConfigProvider(ws.path))
        .value
        ?.autopilot
        .parallel;
    final selectedId = ref.watch(boardSelectedSpecProvider);
    final selected = cards.where((d) => d.spec.id == selectedId).firstOrNull;
    final body = cards.isEmpty
        ? _Empty(
            drafts == 0
                ? 'Nenhuma spec ainda. Crie uma em Specs ou planeje '
                      'o projeto em Projeto.'
                : 'Nenhuma spec aprovada. Aprove uma spec na tela '
                      'Specs para ela entrar no quadro.',
          )
        : visible.isEmpty
        ? const _Empty('Nenhum cartão passa pelos filtros.')
        : ref.watch(boardGraphViewProvider)
        ? SpecCanvas(
            cards: visible,
            attention: attention,
            highlightNext: ref.watch(
              autopilotProvider.select((s) => s.contains(ws.id)),
            ),
            attentionCount: attentionCount,
          )
        : _Board(
            cards: visible,
            all: [for (final d in cards) d.spec],
            attention: attention,
            parallel: parallel,
          );
    return ColoredBox(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SpecSyncBar(workspace: ws, specs: specs, selected: selected?.spec),
          _Header(
            workspaceId: ws.id,
            workspacePath: ws.path,
            total: cards.length,
            drafts: drafts,
            cards: cards,
            attentionCount: attentionCount,
            parallel: parallel,
          ),
          if (legacy.isNotEmpty)
            _LegacyBanner(
              count: legacy.length,
              onOpen: () => showLegacyTasksDialog(context, ws, legacy),
            ),
          Expanded(
            child: selected == null || ref.watch(boardGraphViewProvider)
                ? body
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: body),
                      Container(
                        key: const ValueKey('board-side-panel'),
                        width: 360,
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(
                          color: AppColors.panel,
                          border: Border(
                            left: BorderSide(color: AppColors.border),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: Alignment.centerRight,
                              child: IconButton(
                                key: const ValueKey('board-side-close'),
                                tooltip: 'Fechar',
                                iconSize: 16,
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(
                                  Icons.close,
                                  color: AppColors.textSecondary,
                                ),
                                onPressed: () => ref
                                    .read(boardSelectedSpecProvider.notifier)
                                    .select(null),
                              ),
                            ),
                            Expanded(
                              child: SpecStepsPanel(specId: selected.spec.id),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.background,
    child: Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ),
    ),
  );
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.workspaceId,
    required this.workspacePath,
    required this.total,
    required this.drafts,
    required this.cards,
    required this.attentionCount,
    required this.parallel,
  });

  final int workspaceId;
  final String workspacePath;
  final int total;
  final int drafts;
  final List<SpecCardData> cards;
  final int attentionCount;
  final int? parallel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(
      autopilotProvider.select((s) => s.contains(workspaceId)),
    );
    final pilot = ref.read(autopilotProvider.notifier);
    final filter = ref.watch(boardFilterProvider);
    final filters = ref.read(boardFilterProvider.notifier);
    final phases = {for (final d in cards) ?d.spec.phase}.toList()..sort();
    final agents = {for (final d in cards) ?d.spec.agentName}.toList()..sort();
    // Autopilot strip: running / limit, wave, spent today.
    final specs = [for (final d in cards) d.spec];
    final waves = dependencyWaves(specs);
    final next = nextWave(specs, waves);
    final waveCount = waves.isEmpty
        ? 0
        : waves.values.fold(0, (m, v) => v > m ? v : m) + 1;
    final running = cards
        .where((d) => d.spec.stage == SpecStage.running)
        .length;
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final spent = cards.fold<double>(
      0,
      (a, d) =>
          a +
          d.sessions
              .where((s) => !s.startedAt.isBefore(day))
              .fold(0.0, (x, s) => x + s.costUsd),
    );
    final budget = ref
        .watch(projectConfigProvider(workspacePath))
        .value
        ?.autopilot
        .dailyBudgetUsd;
    final strip = [
      parallel == null
          ? '$running em execução'
          : '$running de $parallel em paralelo',
      if (next != null && waveCount > 1) 'onda ${next + 1} de $waveCount',
      '${formatCost(spent)}${budget == null ? '' : ' / ${formatCost(budget)}'} hoje',
    ].join(' · ');

    Widget chip(String label, bool on, VoidCallback onTap, String keyName) =>
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Material(
            key: ValueKey('board-filter-$keyName'),
            color: on ? AppColors.amberTint : Colors.transparent,
            shape: StadiumBorder(
              side: BorderSide(color: on ? AppColors.amber : AppColors.border),
            ),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onTap,
              child: Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: on ? AppColors.amber : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        );
    Widget menuChip<T>(
      String label,
      T? value,
      List<T> options,
      void Function(T?) onPick,
      String keyName,
    ) => PopupMenuButton<String>(
      key: ValueKey('board-filter-$keyName'),
      tooltip: label,
      color: AppColors.panel,
      onSelected: (v) =>
          onPick(v == '' ? null : options.firstWhere((o) => '$o' == v)),
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: '',
          child: Text('todas', style: TextStyle(fontSize: 12)),
        ),
        for (final o in options)
          PopupMenuItem(
            value: '$o',
            child: Text('$o', style: const TextStyle(fontSize: 12)),
          ),
      ],
      child: Container(
        height: 26,
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: value == null ? Colors.transparent : AppColors.amberTint,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: value == null ? AppColors.border : AppColors.amber,
          ),
        ),
        child: Text(
          '$label: ${value ?? 'todas'}',
          style: TextStyle(
            fontSize: 11,
            color: value == null ? AppColors.textSecondary : AppColors.amber,
          ),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Text(
            'Quadro',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 10),
          Text(
            '$total',
            key: const ValueKey('board-total'),
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 14),
          chip(
            attentionCount == 0
                ? 'Precisam de mim'
                : 'Precisam de mim · $attentionCount',
            filter.attention,
            () => filters.set(filter.copyWith(attention: !filter.attention)),
            'attention',
          ),
          // A value set stays visible so it can be cleared.
          if (phases.isNotEmpty || filter.phase != null)
            menuChip(
              'Fase',
              filter.phase,
              phases,
              (v) => filters.set(filter.copyWith(phase: () => v)),
              'phase',
            ),
          if (agents.isNotEmpty || filter.agent != null)
            menuChip(
              'Agente',
              filter.agent,
              agents,
              (v) => filters.set(filter.copyWith(agent: () => v)),
              'agent',
            ),
          Expanded(
            child: Text(
              on ? 'Autopilot · $strip' : strip,
              key: const ValueKey('board-strip'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                color: on ? AppColors.teal : AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (drafts > 0)
            Text(
              '$drafts em rascunho fora do quadro',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          const SizedBox(width: 12),
          for (final (graph, label) in [(false, 'Colunas'), (true, 'Canvas')])
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ToggleBox(
                key: ValueKey('board-view-${graph ? 'graph' : 'columns'}'),
                on: ref.watch(boardGraphViewProvider) == graph,
                height: 28,
                onTap: () =>
                    ref.read(boardGraphViewProvider.notifier).set(graph),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: ref.watch(boardGraphViewProvider) == graph
                        ? AppColors.amber
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 8),
          Builder(
            builder: (context) {
              ref.watch(appSettingsProvider);
              final schedule = pilot.scheduleOf(workspaceId);
              return TextButton.icon(
                key: const ValueKey('board-schedule'),
                onPressed: () => showScheduleDialog(context, ref, workspaceId),
                icon: const Icon(Icons.schedule, size: 16),
                label: Text(
                  schedule == null ? 'Agendar' : schedule.label,
                  style: const TextStyle(fontSize: 12),
                ),
              );
            },
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: on
                ? 'Parar: desliga o automático e interrompe as sessões das specs'
                : 'Executar: inicia as specs sem bloqueio em paralelo e as '
                      'bloqueadas assim que a dependência chegar em Review',
            child: FilledButton.icon(
              key: const ValueKey('board-autopilot'),
              onPressed: () =>
                  on ? pilot.stop(workspaceId) : pilot.start(workspaceId),
              icon: Icon(on ? Icons.stop : Icons.play_arrow, size: 16),
              label: Text(on ? 'Parar' : 'Executar tudo'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegacyBanner extends StatelessWidget {
  const _LegacyBanner({required this.count, required this.onOpen});

  final int count;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('board-legacy'),
    margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: SessionColors.approvalBg,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: SessionColors.approvalBorder),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            count == 1
                ? '1 tarefa antiga não pertence a nenhuma etapa.'
                : '$count tarefas antigas não pertencem a nenhuma etapa.',
            style: const TextStyle(fontSize: 12, color: AppColors.amber),
          ),
        ),
        SmallButton(
          key: const ValueKey('board-legacy-open'),
          label: 'Revisar',
          height: 26,
          onTap: onOpen,
        ),
      ],
    ),
  );
}

class _Board extends StatelessWidget {
  const _Board({
    required this.cards,
    required this.all,
    required this.attention,
    required this.parallel,
  });

  final List<SpecCardData> cards;

  /// Every spec of the board (dependency waves of the Backlog groups).
  final List<Spec> all;
  final bool Function(SpecCardData) attention;
  final int? parallel;

  static const _gap = 14.0;
  static const _pad = 20.0;
  static const _minCol = 240.0;

  /// Below this height the columns no longer fit their header and a card:
  /// the whole Board scrolls vertically instead of clipping.
  static const _minHeight = 360.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final avail = c.maxWidth - 2 * _pad - 3 * _gap;
      final colW = math.max(_minCol, avail / 4);
      final width = colW * 4 + 3 * _gap + 2 * _pad;
      final board = SizedBox(
        width: width,
        height: math.max(c.maxHeight, _minHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _pad, vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final s in SpecStage.values) ...[
                if (s != SpecStage.backlog) const SizedBox(width: _gap),
                SizedBox(
                  width: colW,
                  child: _Column(
                    stage: s,
                    width: colW,
                    cards: attentionFirst(
                      orderedCards([
                        for (final d in cards)
                          if (d.spec.stage == s) d,
                      ]),
                      attention,
                    ),
                    waves: s == SpecStage.backlog ? dependencyWaves(all) : null,
                    limit: s == SpecStage.running ? parallel : null,
                    order: [
                      for (final spec
                          in all.where((x) => x.stage == s).toList()
                            ..sort(compareBoardOrder))
                        spec.id,
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
      final wide = width <= c.maxWidth + 0.5
          ? board
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: board,
            );
      if (c.maxHeight >= _minHeight) return wide;
      return Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          key: const ValueKey('board-vertical-scroll'),
          child: wide,
        ),
      );
    },
  );
}

/// Cards that wait for the user first, the rest in their saved order
/// (UX v2, U8).
List<SpecCardData> attentionFirst(
  List<SpecCardData> cards,
  bool Function(SpecCardData) attention,
) => [
  for (final d in cards)
    if (attention(d)) d,
  for (final d in cards)
    if (!attention(d)) d,
];

/// Rows of a column: a group label ("Prontas · onda 2", "Bloqueadas") or a
/// card. Only the Backlog is grouped.
List<Object> columnRows(
  SpecStage stage,
  List<SpecCardData> cards,
  Map<int, int>? waves,
) {
  if (stage != SpecStage.backlog || waves == null) return cards;
  final ready = [
    for (final d in cards)
      if (d.blockers.isEmpty) d,
  ];
  final blocked = [
    for (final d in cards)
      if (d.blockers.isNotEmpty) d,
  ];
  String wave(List<SpecCardData> list) {
    final ws = {for (final d in list) (waves[d.spec.id] ?? 0) + 1}.toList()
      ..sort();
    return ws.isEmpty
        ? ''
        : ws.length == 1
        ? ' · onda ${ws.single}'
        : ' · ondas ${ws.first}–${ws.last}';
  }

  return [
    if (ready.isNotEmpty) 'Prontas${wave(ready)}',
    ...ready,
    if (blocked.isNotEmpty) 'Bloqueadas${wave(blocked)}',
    ...blocked,
  ];
}

class _Column extends ConsumerWidget {
  const _Column({
    required this.stage,
    required this.width,
    required this.cards,
    required this.order,
    this.waves,
    this.limit,
  });

  final SpecStage stage;
  final double width;
  final List<SpecCardData> cards;

  /// Ids of every spec of the column in board order (hidden by the filters
  /// too): what "↑ / ↓" saves.
  final List<int> order;

  /// Dependency waves (Backlog only: "Prontas · onda N" / "Bloqueadas").
  final Map<int, int>? waves;

  /// `autopilot.paralelo` (Em execução only: "3 / 3").
  final int? limit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focus = ref.watch(boardFocusSpecProvider);
    final focusHere = focus != null && cards.any((c) => c.spec.id == focus);
    return DragTarget<int>(
      key: ValueKey('board-column-${stage.name}'),
      onWillAcceptWithDetails: (d) => !cards.any((c) => c.spec.id == d.data),
      onAcceptWithDetails: (d) =>
          ref.read(specsRepoProvider).setStage(d.data, stage),
      builder: (context, candidate, _) => Container(
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: candidate.isNotEmpty ? AppColors.amber : AppColors.border,
          ),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
              child: Row(
                children: [
                  Dot(specStageColor(stage)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      specStageLabel(stage).toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sectionTitleStyle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    limit == null
                        ? '${cards.length}'
                        : '${cards.length} / $limit',
                    key: ValueKey('board-column-count-${stage.name}'),
                    style: TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 11,
                      color: limit != null && cards.length >= limit!
                          ? AppColors.amber
                          : AppColors.textSecondary,
                    ),
                  ),
                  if (limit != null) ...[
                    const Spacer(),
                    const Text(
                      'limite do Autopilot',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: cards.isEmpty
                  ? const Center(
                      child: Text(
                        'Arraste specs para cá',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    )
                  : ListView.separated(
                      // "Voltar à spec" (SPEC-021 R4): build the whole column
                      // while a card of it waits to be scrolled into view.
                      scrollCacheExtent: focusHere
                          ? const ScrollCacheExtent.pixels(1e6)
                          : null,
                      itemCount: columnRows(stage, cards, waves).length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, r) {
                        final row = columnRows(stage, cards, waves)[r];
                        if (row is String) {
                          return Padding(
                            key: ValueKey('board-group-$row'),
                            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                            child: Text(
                              row,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                          );
                        }
                        final d = row as SpecCardData;
                        // Neighbours as shown (attention first, Prontas /
                        // Bloqueadas), saved into the full column order.
                        final shown = [
                          for (final x in columnRows(stage, cards, waves))
                            if (x is SpecCardData) x,
                        ];
                        final i = shown.indexOf(d);
                        Future<void> move(int delta) async {
                          final j = i + delta;
                          if (j < 0 || j >= shown.length) return;
                          await ref
                              .read(specsRepoProvider)
                              .setBoardOrder(
                                moveInColumn(
                                  order,
                                  d.spec.id,
                                  shown[j].spec.id,
                                  delta,
                                ),
                              );
                        }

                        final card = SpecCard(
                          data: d,
                          onMove: shown.length > 1 ? move : null,
                          isFirst: i == 0,
                          isLast: i == shown.length - 1,
                        );
                        return Draggable<int>(
                          key: ValueKey('board-card-${d.spec.code}'),
                          data: d.spec.id,
                          feedback: Material(
                            color: Colors.transparent,
                            child: SizedBox(
                              width: width - 20,
                              child: Opacity(opacity: 0.9, child: card),
                            ),
                          ),
                          childWhenDragging: Opacity(
                            opacity: 0.35,
                            child: card,
                          ),
                          child: card,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card of a spec: code, phase, title, progress, current step, blockers,
/// agent, cost and the action that fits its state.
class SpecCard extends ConsumerWidget {
  const SpecCard({
    super.key,
    required this.data,
    this.onMove,
    this.isFirst = false,
    this.isLast = false,
  });

  final SpecCardData data;

  /// Moves the card up (-1) / down (+1) in its column (null = no menu item).
  final Future<void> Function(int delta)? onMove;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = data.spec;
    final last = data.lastSession;
    final alive =
        last != null &&
        ref.watch(sessionManagerProvider.select((m) => m.isAlive(last.id)));
    final liveStatus = alive ? last.status : null;
    final busy =
        liveStatus == SessionStatus.running ||
        liveStatus == SessionStatus.waitingApproval;
    final (done, total) = progressOf(data.steps);
    final current = data.current;
    final blocked = data.blockers.isNotEmpty && spec.stage != SpecStage.done;
    final waitingUser = current?.status == StepStatus.needsInput;
    final prep = ref.watch(worktreePrepProvider.select((m) => m[spec.id]));

    final changedOnDisk = ref.watch(
      workspaceWatcherProvider.select((s) => s.contains(spec.id)),
    );
    final duel =
        (ref.watch(openDuelsProvider(spec.workspaceId)).value ??
                const <SpecDuel>[])
            .where((d) => d.specId == spec.id)
            .firstOrNull;

    var meta = '';
    var metaColor = AppColors.textSecondary;
    var border = AppColors.border;
    if (spec.stage == SpecStage.done) {
      meta = 'concluída';
    } else if (duel != null) {
      meta = duel.state == 'pronto'
          ? 'A/B prontas para comparar'
          : 'A/B rodando · ${duel.steps}';
      metaColor = AppColors.lilac;
    } else if (changedOnDisk && !busy) {
      meta = 'spec alterada no disco';
      metaColor = AppColors.amber;
      border = SessionColors.approvalBorder;
    } else if (prep?.running ?? false) {
      meta = 'Preparando worktree…';
      metaColor = AppColors.lilac;
    } else if (prep?.error != null) {
      meta = 'falha ao preparar o worktree';
      metaColor = AppColors.red;
      border = SessionColors.stopBorder;
    } else if (busy) {
      final dur = DateTime.now().difference(last!.startedAt);
      meta = liveStatus == SessionStatus.waitingApproval
          ? 'aguardando aprovação'
          : '${current?.id ?? ''} rodando · ${formatDuration(dur)}';
      if (liveStatus == SessionStatus.waitingApproval) {
        metaColor = AppColors.amber;
        border = SessionColors.approvalBorder;
      } else {
        border = SessionColors.runningToolBorder;
      }
    } else if (current?.status == StepStatus.verifying) {
      meta = '${current!.id} verificando';
      metaColor = AppColors.lilac;
    } else if (waitingUser) {
      meta = current!.gateFailed
          ? '${current.id} · verificação falhou'
          : '${current.id} aguardando você';
      metaColor = AppColors.amber;
      border = SessionColors.approvalBorder;
    } else if (blocked) {
      meta = 'bloqueada por ${data.blockers.join(', ')}';
      metaColor = AppColors.red;
    } else if (total == 0) {
      meta = 'sem requisitos';
      metaColor = AppColors.red;
    } else if (spec.stage == SpecStage.review) {
      meta =
          reviewerLabel(spec, running: true) ??
          (spec.reviewRounds > 0
              ? 'pronta para review · ${spec.reviewRounds} correção(ões) do revisor'
              : 'pronta para review');
      if (spec.reviewPhase == ReviewPhase.auto) metaColor = AppColors.lilac;
    } else {
      meta = done == 0 ? 'pronta' : 'próxima: ${current?.id ?? '—'}';
    }

    if (needsAttention(
      data,
      waitingApproval: liveStatus == SessionStatus.waitingApproval,
      prepFailed: prep?.error != null,
      changedOnDisk: changedOnDisk,
      duelReady: duel?.state == 'pronto',
    )) {
      meta = boardAttentionReason(
        data,
        waitingApproval: liveStatus == SessionStatus.waitingApproval,
        prepFailed: prep?.error != null,
        changedOnDisk: changedOnDisk,
        duelReady: duel?.state == 'pronto',
      );
    }

    final canRun =
        !busy &&
        !blocked &&
        total > 0 &&
        done < total &&
        spec.stage != SpecStage.done;
    final selected = ref.watch(boardSelectedSpecProvider) == spec.id;
    if (ref.watch(boardFocusSpecProvider) == spec.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ref.read(boardFocusSpecProvider.notifier).select(null);
        Scrollable.ensureVisible(
          context,
          alignment: 0.3,
          duration: const Duration(milliseconds: 200),
        );
      });
    }
    return InkWell(
      key: ValueKey('board-open-${spec.code}'),
      borderRadius: BorderRadius.circular(8),
      // The side panel (U8): same card again closes it.
      onTap: () => ref
          .read(boardSelectedSpecProvider.notifier)
          .select(selected ? null : spec.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? SessionColors.selectedBg : AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected && border == AppColors.border
                ? SessionColors.selectedBorder
                : border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  spec.code,
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (spec.phase != null) ...[
                  const SizedBox(width: 6),
                  _Chip(spec.phase!),
                ],
                const Spacer(),
                if (data.cost > 0)
                  Text(
                    formatCost(data.cost),
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                _CardMenu(
                  data: data,
                  canRun: canRun,
                  onMove: onMove,
                  isFirst: isFirst,
                  isLast: isLast,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              spec.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            _Progress(
              done: done,
              total: total,
              specCode: spec.code,
              steps: data.steps,
            ),
            Builder(
              builder: (context) {
                final subs = watchSubagentStatuses(
                  ref,
                  spec,
                  data.steps,
                  data.sessions,
                );
                if (subs.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SubagentChips(statuses: subs),
                );
              },
            ),
            if (current != null && spec.stage != SpecStage.done) ...[
              const SizedBox(height: 6),
              Text(
                '${current.id} · ${current.text}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              if (current.gate case final g?) ...[
                const SizedBox(height: 4),
                GateChips(report: g, keyPrefix: 'board-gate-${spec.code}'),
              ],
            ],
            if (busy && last != null) ...[
              const SizedBox(height: 4),
              LiveToolLine(session: last, specCode: spec.code),
            ],
            SuggestionBanner(spec: spec),
            const SizedBox(height: 6),
            Row(
              children: [
                _AgentAvatar(spec.agentName),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    spec.agentName ?? 'sem agente',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: Text(
                    meta,
                    key: ValueKey('board-meta-${spec.code}'),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: metaColor),
                  ),
                ),
              ],
            ),
            BoardSpecAction(data: data),
          ],
        ),
      ),
    );
  }
}

/// Shared by columns and the canvas detail panel.
class BoardSpecAction extends ConsumerWidget {
  const BoardSpecAction({super.key, required this.data, this.height = 28});
  final SpecCardData data;

  /// Button height: 28 on the card, 44 in the canvas panel.
  final double height;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = data.spec, last = data.lastSession;
    final alive =
        last != null &&
        ref.watch(sessionManagerProvider.select((m) => m.isAlive(last.id)));
    final busy =
        alive &&
        (last.status == SessionStatus.running ||
            last.status == SessionStatus.waitingApproval);
    final current = data.current;
    final waitingUser = current?.status == StepStatus.needsInput;
    final prep = ref.watch(worktreePrepProvider.select((m) => m[spec.id]));
    final changedOnDisk = ref.watch(
      workspaceWatcherProvider.select((s) => s.contains(spec.id)),
    );
    final duel =
        (ref.watch(openDuelsProvider(spec.workspaceId)).value ?? <SpecDuel>[])
            .where((d) => d.specId == spec.id)
            .firstOrNull;
    final (done, total) = progressOf(data.steps);
    final canRun =
        !busy &&
        data.blockers.isEmpty &&
        total > 0 &&
        done < total &&
        spec.stage != SpecStage.done;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (alive && last.status == SessionStatus.waitingApproval)
          _ActionButton(
            height: height,
            key: ValueKey('board-approvals-${spec.code}'),
            label: 'Abrir aprovações',
            onTap: () => openSession(ref, last.id),
          )
        else ...[
          if (duel != null && duel.state == 'pronto') ...[
            const SizedBox(height: 8),
            _ActionButton(
              height: height,
              key: ValueKey('board-duel-${spec.code}'),
              label: 'Comparar A/B',
              onTap: () => showDuelDialog(context, duel),
            ),
          ] else if (changedOnDisk) ...[
            const SizedBox(height: 6),
            const Text(
              'O arquivo da spec mudou enquanto ela rodava. Confirme para '
              'as próximas etapas usarem o texto novo.',
              style: TextStyle(fontSize: 11, color: AppColors.amber),
            ),
            const SizedBox(height: 6),
            _ActionButton(
              height: height,
              key: ValueKey('board-confirm-change-${spec.code}'),
              label: 'Confirmar alteração',
              onTap: () =>
                  ref.read(workspaceWatcherProvider.notifier).confirm(spec.id),
            ),
          ] else if (prep?.error != null) ...[
            const SizedBox(height: 6),
            Text(
              tailLines(prep!.error!, 3),
              key: ValueKey('board-prep-error-${spec.code}'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 10,
                color: AppColors.red,
              ),
            ),
            const SizedBox(height: 8),
            _ActionButton(
              height: height,
              key: ValueKey('board-prep-retry-${spec.code}'),
              label: 'Tentar de novo',
              onTap: () => runSpec(context, ref, data),
            ),
          ] else if (waitingUser && !busy && current!.sessionId != null) ...[
            const SizedBox(height: 8),
            _ActionButton(
              height: height,
              key: ValueKey('board-answer-${spec.code}'),
              label: 'Responder na sessão',
              onTap: () => openSession(ref, current.sessionId!),
            ),
          ] else if (canRun) ...[
            const SizedBox(height: 8),
            _ActionButton(
              height: height,
              key: ValueKey('board-run-${spec.code}'),
              label: data.sessions.isEmpty
                  ? 'Executar'
                  : 'Continuar · ${current?.id ?? ''}',
              onTap: () => runSpec(context, ref, data),
            ),
          ] else if (spec.stage == SpecStage.review) ...[
            const SizedBox(height: 8),
            _ActionButton(
              height: height,
              key: ValueKey('board-review-${spec.code}'),
              label: 'Ver review',
              onTap: () =>
                  ref.read(navigationProvider.notifier).go(AppSection.review),
            ),
          ],
        ],
      ],
    );
  }
}

/// Selects [sessionId] and goes to Sessões.
void openSession(WidgetRef ref, String sessionId) {
  ref.read(selectedSessionProvider.notifier).select(sessionId);
  ref.read(navigationProvider.notifier).go(AppSection.sessions);
}

/// Same as [openSession] for callers whose widget may be gone (snackbar
/// actions).
void openSessionIn(ProviderContainer container, String sessionId) {
  container.read(selectedSessionProvider.notifier).select(sessionId);
  container.read(navigationProvider.notifier).go(AppSection.sessions);
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: BoxDecoration(
      color: AppColors.border,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
    ),
  );
}

class _AgentAvatar extends StatelessWidget {
  const _AgentAvatar(this.agent);

  final String? agent;

  @override
  Widget build(BuildContext context) => Container(
    width: 18,
    height: 18,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: AppColors.border,
      shape: BoxShape.circle,
    ),
    child: Text(
      (agent == null || agent!.isEmpty) ? '–' : agent![0].toUpperCase(),
      style: const TextStyle(fontSize: 10, color: AppColors.text),
    ),
  );
}

/// Colour of one segment of the card's progress (UX v2, U8).
Color stepSegmentColor(StepView s) => s.gateFailed
    ? AppColors.red
    : switch (s.status) {
        StepStatus.done => AppColors.teal,
        StepStatus.running || StepStatus.verifying => AppColors.amber,
        StepStatus.needsInput => AppColors.red,
        StepStatus.pending => AppColors.border,
      };

class _Progress extends StatelessWidget {
  const _Progress({
    required this.done,
    required this.total,
    required this.specCode,
    required this.steps,
  });

  final int done;
  final int total;
  final String specCode;
  final List<StepView> steps;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: steps.isEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: const LinearProgressIndicator(
                  value: 0,
                  minHeight: 5,
                  backgroundColor: AppColors.border,
                ),
              )
            : Row(
                key: ValueKey('board-segments-$specCode'),
                children: [
                  for (final (i, s) in steps.indexed)
                    Expanded(
                      child: Container(
                        height: 5,
                        margin: EdgeInsets.only(left: i == 0 ? 0 : 3),
                        decoration: BoxDecoration(
                          color: stepSegmentColor(s),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                ],
              ),
      ),
      const SizedBox(width: 8),
      Text(
        '$done/$total',
        key: ValueKey('board-progress-$specCode'),
        style: const TextStyle(
          fontFamily: AppFonts.mono,
          fontSize: 11,
          color: AppColors.textSecondary,
        ),
      ),
    ],
  );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.label,
    required this.onTap,
    this.height = 28,
  });

  final String label;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) => SmallButton(
    label: label,
    height: height,
    fontSize: height > 30 ? 13 : 12,
    expand: true,
    color: AppColors.amber,
    border: SessionColors.approvalBorder,
    background: SessionColors.approvalBg,
    onTap: onTap,
  );
}

class _CardMenu extends ConsumerWidget {
  const _CardMenu({
    required this.data,
    required this.canRun,
    this.onMove,
    this.isFirst = false,
    this.isLast = false,
  });

  final SpecCardData data;
  final bool canRun;
  final Future<void> Function(int delta)? onMove;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = data.spec;
    return SizedBox(
      width: 22,
      height: 18,
      child: PopupMenuButton<String>(
        key: ValueKey('board-menu-${spec.code}'),
        padding: EdgeInsets.zero,
        iconSize: 14,
        tooltip: 'Ações',
        color: AppColors.panel,
        icon: const Icon(Icons.more_horiz, color: AppColors.textSecondary),
        onSelected: (v) async {
          final repo = ref.read(specsRepoProvider);
          switch (v) {
            case 'run':
              await runSpec(context, ref, data, ask: true);
            case 'auto':
              await repo.setAutoAdvance(spec.id, !spec.autoAdvance);
            case 'details':
              ref.read(boardSelectedSpecProvider.notifier).select(spec.id);
            case 'duel':
              final messenger = ScaffoldMessenger.maybeOf(context);
              try {
                await ref
                    .read(specRunnerProvider)
                    .runNext(spec.id, duel: true, reviewUnblocks: true);
              } catch (e) {
                messenger?.showSnackBar(SnackBar(content: Text('$e')));
              }
            case 'up':
              await onMove?.call(-1);
            case 'down':
              await onMove?.call(1);
            default:
              final s = SpecStage.values.asNameMap()[v];
              if (s != null) await repo.setStage(spec.id, s);
          }
        },
        itemBuilder: (_) => [
          if (canRun) ...[
            const PopupMenuItem(
              value: 'run',
              child: Text(
                'Executar com opções…',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const PopupMenuItem(
              value: 'duel',
              child: Text(
                'Executar em dobro (A/B)',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
          PopupMenuItem(
            value: 'auto',
            child: Text(
              spec.autoAdvance
                  ? 'Pausar avanço automático'
                  : 'Ligar avanço automático',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const PopupMenuItem(
            value: 'details',
            child: Text('Etapas e sessões', style: TextStyle(fontSize: 12)),
          ),
          if (onMove != null && !isFirst)
            const PopupMenuItem(
              value: 'up',
              child: Text('Subir na coluna', style: TextStyle(fontSize: 12)),
            ),
          if (onMove != null && !isLast)
            const PopupMenuItem(
              value: 'down',
              child: Text('Descer na coluna', style: TextStyle(fontSize: 12)),
            ),
          for (final s in SpecStage.values)
            if (s != spec.stage)
              PopupMenuItem(
                value: s.name,
                child: Text(
                  'Mover para ${specStageLabel(s)}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
        ],
      ),
    );
  }
}
