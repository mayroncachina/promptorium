import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../ui/theme/tokens.dart';
import '../../../../ui/widgets/markdown/app_markdown.dart';
import '../../../context/widgets/context_indicator.dart';
import '../../../sessions/session_manager.dart' show PendingApproval;
import '../../../sessions/widgets/session_style.dart';
import '../../../sessions/widgets/side_panel.dart' show ApprovalCard;
import '../../../sessions/widgets/timeline_view.dart';
import '../compare_controller.dart';
import '../compare_run.dart';
import '../compare_weight.dart';
import 'compare_bar.dart';
import 'compare_metrics.dart';

/// Below this width of the conversation area the columns become tabs
/// (R6, P7).
const compareColumnsMinWidth = 1100.0;

/// The header state of a side (R6): text and icon, never only the color
/// (R15).
({String text, String spoken, IconData icon, Color color}) compareStateOf(
  CompareSide s, {
  DateTime? now,
}) {
  final m = s.metrics;
  return switch (s.state) {
    CompareSideState.starting => (
      text: 'começando…',
      spoken: 'começando',
      icon: Icons.hourglass_empty,
      color: AppColors.textSecondary,
    ),
    CompareSideState.running => (
      text: 'rodando · ${compareElapsed(s, now: now)}',
      spoken: 'rodando',
      icon: Icons.autorenew,
      color: AppColors.teal,
    ),
    CompareSideState.done => (
      text: m == null ? 'pronta' : 'pronta · ${compareDuration(m.durationMs)}',
      spoken: m == null
          ? 'pronta'
          : 'pronta em ${compareDurationSpoken(m.durationMs)}',
      icon: Icons.check,
      color: AppColors.teal,
    ),
    CompareSideState.planReady => (
      text: 'plano pronto',
      spoken: 'com plano pronto',
      icon: Icons.assignment_turned_in_outlined,
      color: AppColors.amber,
    ),
    CompareSideState.stopped => (
      text: 'interrompida',
      spoken: 'interrompida',
      icon: Icons.pause_circle_outline,
      color: AppColors.textSecondary,
    ),
    CompareSideState.error => (
      text: 'parou: erro',
      spoken: 'parou com erro',
      icon: Icons.error_outline,
      color: AppColors.red,
    ),
  };
}

/// `Resposta A, Sonnet, Perguntar, pronta em 38 segundos` (R15).
String compareRegionLabel(CompareSide s) =>
    'Resposta ${s.letter}, ${compareModelLabel(s.model)}, ${s.mode.label}, '
    '${compareStateOf(s).spoken}';

/// The comparison of a conversation waiting for a choice (R6–R14): the
/// prompt once, the two columns (or tabs) and the bar to choose.
class ComparePanel extends ConsumerWidget {
  const ComparePanel({
    super.key,
    required this.view,
    required this.root,
    required this.onChoose,
    required this.onDiscard,
  });

  final CompareView view;
  final String? root;
  final ValueChanged<String> onChoose;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = view.run;
    final ctl = ref.read(compareControllerProvider.notifier);
    final id = run.conversationId;
    Widget column(CompareSide s, {bool metrics = true}) => _SideColumn(
      key: ValueKey('compare-column-${s.letter}'),
      run: run,
      side: s,
      live: view.liveOf(s.letter),
      root: root,
      onChoose: () => onChoose(s.letter),
      onStop: () => ctl.stop(id, s.letter),
      onResume: () => ctl.resume(id, s.letter),
      onApprove: (a, {required always, input}) => ctl.approve(
        id,
        s.letter,
        a.requestId,
        always: always,
        updatedInput: input,
      ),
      onDeny: (a) => ctl.deny(id, s.letter, a.requestId),
      metrics: metrics,
    );
    final h = run.at.toLocal();
    final time =
        '${h.hour.toString().padLeft(2, '0')}:${h.minute.toString().padLeft(2, '0')}';
    return Padding(
      key: ValueKey('compare-panel-$id'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                key: const ValueKey('compare-badge'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.amberTint,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: SessionColors.approvalBorder),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.view_column_outlined,
                      size: 13,
                      color: AppColors.amber,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Comparando',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.amber,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: SessionColors.selectedBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: SessionColors.selectedBorder),
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: run.prompt,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.text,
                          ),
                        ),
                        TextSpan(
                          text: '   Você · $time',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    key: const ValueKey('compare-prompt'),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                if (c.maxWidth >= compareColumnsMinWidth) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: column(run.a)),
                      const SizedBox(width: 12),
                      Expanded(child: column(run.b)),
                    ],
                  );
                }
                return _Tabs(run: run, view: view, column: column);
              },
            ),
          ),
          const SizedBox(height: 10),
          _ChooseBar(
            run: run,
            onStopBoth: () => ctl.stopBoth(id),
            onDiscard: onDiscard,
          ),
        ],
      ),
    );
  }
}

/// Narrow window (R6): tabs "A · Sonnet" / "B · Opus", the metrics of both
/// on top.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.run, required this.view, required this.column});

  final CompareRun run;
  final CompareView view;
  final Widget Function(CompareSide, {bool metrics}) column;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        key: const ValueKey('compare-tabs'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in run.sides)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 14, top: 4),
                        child: Row(
                          children: [
                            CompareLetter(s.letter, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              s.label,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      CompareMetricsView(
                        run: run,
                        side: s,
                        calls: view.liveOf(s.letter).calls,
                      ),
                    ],
                  ),
                ),
            ],
          ),
          TabBar(
            labelColor: AppColors.amber,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.amber,
            tabs: [
              for (final s in run.sides)
                Tab(
                  key: ValueKey('compare-tab-${s.letter}'),
                  text: '${s.letter} · ${compareModelLabel(s.model)}',
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              // The metrics are on top already.
              children: [for (final s in run.sides) column(s, metrics: false)],
            ),
          ),
        ],
      ),
    );
  }
}

class _SideColumn extends StatelessWidget {
  const _SideColumn({
    super.key,
    required this.run,
    required this.side,
    required this.live,
    required this.root,
    required this.onChoose,
    required this.onStop,
    required this.onResume,
    required this.onApprove,
    required this.onDeny,
    this.metrics = true,
  });

  final CompareRun run;
  final CompareSide side;
  final CompareLive live;
  final bool metrics;
  final String? root;
  final VoidCallback onChoose;
  final VoidCallback onStop;
  final VoidCallback onResume;
  final Future<void> Function(
    PendingApproval a, {
    required bool always,
    Map<String, dynamic>? input,
  })
  onApprove;
  final Future<void> Function(PendingApproval a) onDeny;

  @override
  Widget build(BuildContext context) {
    final s = side;
    final plan = s.plan;
    final footer = live.approvals.isEmpty && (plan == null || plan.isEmpty)
        ? (s.error != null && s.state == CompareSideState.error
              ? Text(
                  s.error!,
                  style: const TextStyle(fontSize: 12, color: AppColors.red),
                )
              : null)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final a in live.approvals) ...[
                ApprovalCard(
                  key: ValueKey('compare-approval-${s.letter}-${a.requestId}'),
                  approval: a,
                  onOpen: () {},
                  onApprove: ({required always, input}) =>
                      onApprove(a, always: always, input: input),
                  onDeny: () => onDeny(a),
                ),
                const SizedBox(height: 8),
              ],
              if (plan != null && plan.isNotEmpty)
                Container(
                  key: ValueKey('compare-plan-${s.letter}'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.amberTint,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: SessionColors.approvalBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Plano pronto · aprovar só depois de escolher este '
                        'lado',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.amber,
                        ),
                      ),
                      const SizedBox(height: 6),
                      AppMarkdown(data: plan),
                    ],
                  ),
                ),
            ],
          );
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: compareRegionLabel(s),
      child: FocusTraversalGroup(
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                side: s,
                onChoose: onChoose,
                onStop: onStop,
                onResume: onResume,
              ),
              const Divider(height: 1),
              // SPEC-087 R11: each side has its own window, reading, limit
              // and threshold; nothing is summed between the sides.
              _SideContext(side: s, live: live),
              Expanded(
                child: TimelineListView(
                  key: ValueKey('compare-timeline-${s.letter}'),
                  items: live.timeline.items,
                  root: root,
                  waitingTools: {
                    for (final a in live.approvals) ?a.request.toolUseId,
                  },
                  footer: footer,
                  assistantName:
                      'Claude · ${compareModelLabel(s.model)} · ${s.mode.label}',
                  emptyText: s.state.live
                      ? 'Começando…'
                      : 'Sem resposta deste lado.',
                ),
              ),
              if (metrics) ...[
                const Divider(height: 1),
                CompareMetricsView(run: run, side: s, calls: live.calls),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.side,
    required this.onChoose,
    required this.onStop,
    required this.onResume,
  });

  final CompareSide side;
  final VoidCallback onChoose;
  final VoidCallback onStop;
  final VoidCallback onResume;

  @override
  Widget build(BuildContext context) {
    final s = side;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
      child: Row(
        children: [
          CompareLetter(s.letter),
          const SizedBox(width: 8),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: compareModelLabel(s.model),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  TextSpan(
                    text: '  · ${s.mode.label}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Spacer(),
          CompareTicker(
            active: s.state == CompareSideState.running,
            builder: (_) {
              final st = compareStateOf(s);
              return Row(
                key: ValueKey('compare-state-${s.letter}'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(st.icon, size: 13, color: st.color),
                  const SizedBox(width: 4),
                  Text(
                    st.text,
                    style: TextStyle(fontSize: 12, color: st.color),
                  ),
                ],
              );
            },
          ),
          const SizedBox(width: 10),
          if (s.state.live)
            SmallButton(
              key: ValueKey('compare-stop-${s.letter}'),
              label: 'Parar',
              icon: Icons.stop_circle_outlined,
              color: AppColors.text,
              height: 28,
              semanticLabel: 'Parar o lado ${s.letter}',
              onTap: onStop,
            )
          else ...[
            if (s.state == CompareSideState.stopped ||
                s.state == CompareSideState.error) ...[
              SmallButton(
                key: ValueKey('compare-resume-${s.letter}'),
                label: 'Retomar',
                height: 28,
                semanticLabel: 'Retomar o lado ${s.letter}',
                onTap: onResume,
              ),
              const SizedBox(width: 6),
            ],
            if (s.state.choosable)
              Semantics(
                button: true,
                label: 'Continuar com a resposta ${s.letter}',
                excludeSemantics: true,
                child: AmberButton(
                  key: ValueKey('compare-choose-${s.letter}'),
                  label: 'Continuar com esta',
                  height: 28,
                  onTap: onChoose,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ChooseBar extends StatelessWidget {
  const _ChooseBar({
    required this.run,
    required this.onStopBoth,
    required this.onDiscard,
  });

  final CompareRun run;
  final VoidCallback onStopBoth;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('compare-choose-bar'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.view_column_outlined,
            size: 15,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              compareBlockedMessage,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          if (run.anyLive) ...[
            SmallButton(
              key: const ValueKey('compare-stop-both'),
              label: 'Parar os dois',
              icon: Icons.stop_circle_outlined,
              height: 30,
              onTap: onStopBoth,
            ),
            const SizedBox(width: 8),
          ],
          SmallButton(
            key: const ValueKey('compare-discard'),
            label: 'Descartar os dois',
            color: AppColors.red,
            border: SessionColors.stopBorder,
            height: 30,
            onTap: onDiscard,
          ),
        ],
      ),
    );
  }
}

/// "Descartar os dois" asks first (R12).
Future<bool> confirmDiscardCompare(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Descartar as duas respostas?'),
        content: const Text(
          'O que ainda roda para, os dois lados são apagados e a conversa '
          'volta ao ponto de antes, com o prompt de volta no composer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const ValueKey('compare-discard-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Descartar os dois',
              style: TextStyle(color: AppColors.red),
            ),
          ),
        ],
      ),
    ) ??
    false;

/// The meter of one side (SPEC-087 R11) and its subagents.
class _SideContext extends StatelessWidget {
  const _SideContext({required this.side, required this.live});

  final CompareSide side;
  final CompareLive live;

  @override
  Widget build(BuildContext context) {
    final snap = live.timeline.context.snapshot;
    return Padding(
      key: ValueKey('compare-context-${side.letter}'),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Contexto do lado ${side.letter}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              const Text(
                'contexto próprio',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ContextIndicator(
            snapshot: snap,
            alive: side.state.live,
            dense: true,
            onOpen: () {},
          ),
          if (snap.subagents.isNotEmpty)
            SubagentContextNote(subagents: snap.subagents),
        ],
      ),
    );
  }
}
