import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../ui/shell/navigation.dart';
import '../../ui/theme/tokens.dart';
import '../sessions/session_manager.dart';
import '../specs/workspace_watcher.dart';
import '../review/auto_reviewer.dart' show ReviewPhase, reviewerLabel;
import '../agents/widgets/agent_style.dart' show ToggleBox;
import '../sessions/widgets/session_style.dart';
import 'autopilot.dart';
import 'board_rules.dart';
import 'spec_runner.dart' show worktreePrepProvider;
import 'step_gate.dart' show tailLines;
import 'widgets/card_extras.dart';
import 'widgets/gate_report_view.dart';
import 'widgets/legacy_tasks_dialog.dart';
import 'widgets/run_spec_dialog.dart';
import 'widgets/spec_steps_panel.dart';
import 'widgets/subagent_status.dart';
import 'widgets/wave_graph.dart';

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
    cards.toList()..sort((a, b) {
      final oa = a.spec.boardOrder, ob = b.spec.boardOrder;
      if (oa != null && ob != null && oa != ob) return oa.compareTo(ob);
      if (oa != null && ob == null) return -1;
      if (oa == null && ob != null) return 1;
      return a.spec.code.compareTo(b.spec.code);
    });

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
    return ColoredBox(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(workspaceId: ws.id, total: cards.length, drafts: drafts),
          if (legacy.isNotEmpty)
            _LegacyBanner(
              count: legacy.length,
              onOpen: () => showLegacyTasksDialog(context, ws, legacy),
            ),
          Expanded(
            child: cards.isEmpty
                ? _Empty(
                    drafts == 0
                        ? 'Nenhuma spec ainda. Crie uma em Specs ou planeje '
                              'o projeto em Projeto.'
                        : 'Nenhuma spec aprovada. Aprove uma spec na tela '
                              'Specs para ela entrar no quadro.',
                  )
                : ref.watch(boardGraphViewProvider)
                ? WaveGraph(
                    specs: [for (final d in cards) d.spec],
                    highlightNext: ref.watch(
                      autopilotProvider.select((s) => s.contains(ws.id)),
                    ),
                    cardBuilder: (spec) =>
                        SpecCard(data: cards.firstWhere((d) => d.spec == spec)),
                  )
                : _Board(cards: cards),
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
    required this.total,
    required this.drafts,
  });

  final int workspaceId;
  final int total;
  final int drafts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(
      autopilotProvider.select((s) => s.contains(workspaceId)),
    );
    final pilot = ref.read(autopilotProvider.notifier);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Cada cartão é uma spec (uma branch, um PR); os requisitos são as '
              'etapas, executadas uma por sessão.',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          if (drafts > 0)
            Text(
              '$drafts em rascunho fora do quadro',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          const SizedBox(width: 12),
          for (final (graph, label) in [(false, 'Colunas'), (true, 'Grafo')])
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
  const _Board({required this.cards});

  final List<SpecCardData> cards;

  static const _gap = 14.0;
  static const _pad = 20.0;
  static const _minCol = 240.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final avail = c.maxWidth - 2 * _pad - 3 * _gap;
      final colW = math.max(_minCol, avail / 4);
      final width = colW * 4 + 3 * _gap + 2 * _pad;
      final board = SizedBox(
        width: width,
        height: c.maxHeight,
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
                    cards: orderedCards([
                      for (final d in cards)
                        if (d.spec.stage == s) d,
                    ]),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
      if (width <= c.maxWidth + 0.5) return board;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: board,
      );
    },
  );
}

class _Column extends ConsumerWidget {
  const _Column({
    required this.stage,
    required this.width,
    required this.cards,
  });

  final SpecStage stage;
  final double width;
  final List<SpecCardData> cards;

  @override
  Widget build(BuildContext context, WidgetRef ref) => DragTarget<int>(
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
                  '${cards.length}',
                  key: ValueKey('board-column-count-${stage.name}'),
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
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
                    itemCount: cards.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final d = cards[i];
                      Future<void> move(int delta) async {
                        final ids = [for (final c in cards) c.spec.id];
                        final j = i + delta;
                        if (j < 0 || j >= ids.length) return;
                        ids
                          ..removeAt(i)
                          ..insert(j, d.spec.id);
                        await ref.read(specsRepoProvider).setBoardOrder(ids);
                      }

                      final card = SpecCard(
                        data: d,
                        onMove: cards.length > 1 ? move : null,
                        isFirst: i == 0,
                        isLast: i == cards.length - 1,
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
                        childWhenDragging: Opacity(opacity: 0.35, child: card),
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

    var meta = '';
    var metaColor = AppColors.textSecondary;
    var border = AppColors.border;
    if (spec.stage == SpecStage.done) {
      meta = 'concluída';
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

    final canRun =
        !busy &&
        !blocked &&
        total > 0 &&
        done < total &&
        spec.stage != SpecStage.done;
    return InkWell(
      key: ValueKey('board-open-${spec.code}'),
      borderRadius: BorderRadius.circular(8),
      onTap: () => showSpecDetailDialog(context, spec.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
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
            _Progress(done: done, total: total, specCode: spec.code),
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
            if (changedOnDisk) ...[
              const SizedBox(height: 6),
              const Text(
                'O arquivo da spec mudou enquanto ela rodava. Confirme para '
                'as próximas etapas usarem o texto novo.',
                style: TextStyle(fontSize: 11, color: AppColors.amber),
              ),
              const SizedBox(height: 6),
              _ActionButton(
                key: ValueKey('board-confirm-change-${spec.code}'),
                label: 'Confirmar alteração',
                onTap: () => ref
                    .read(workspaceWatcherProvider.notifier)
                    .confirm(spec.id),
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
                key: ValueKey('board-prep-retry-${spec.code}'),
                label: 'Tentar de novo',
                onTap: () => runSpec(context, ref, data),
              ),
            ] else if (waitingUser && !busy && current!.sessionId != null) ...[
              const SizedBox(height: 8),
              _ActionButton(
                key: ValueKey('board-answer-${spec.code}'),
                label: 'Responder na sessão',
                onTap: () => openSession(ref, current.sessionId!),
              ),
            ] else if (canRun) ...[
              const SizedBox(height: 8),
              _ActionButton(
                key: ValueKey('board-run-${spec.code}'),
                label: data.sessions.isEmpty
                    ? 'Executar'
                    : 'Continuar · ${current?.id ?? ''}',
                onTap: () => runSpec(context, ref, data),
              ),
            ] else if (spec.stage == SpecStage.review) ...[
              const SizedBox(height: 8),
              _ActionButton(
                key: ValueKey('board-review-${spec.code}'),
                label: 'Ver review',
                onTap: () =>
                    ref.read(navigationProvider.notifier).go(AppSection.review),
              ),
            ],
          ],
        ),
      ),
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

class _Progress extends StatelessWidget {
  const _Progress({
    required this.done,
    required this.total,
    required this.specCode,
  });

  final int done;
  final int total;
  final String specCode;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : done / total,
            minHeight: 5,
            backgroundColor: AppColors.border,
            color: done == total && total > 0 ? AppColors.blue : AppColors.teal,
          ),
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
  const _ActionButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SmallButton(
    label: label,
    height: 28,
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
              if (context.mounted) await showSpecDetailDialog(context, spec.id);
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
          if (canRun)
            const PopupMenuItem(
              value: 'run',
              child: Text(
                'Executar com opções…',
                style: TextStyle(fontSize: 12),
              ),
            ),
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
