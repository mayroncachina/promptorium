import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../board/board_rules.dart';
import '../../board/widgets/gate_report_view.dart';
import '../../sessions/widgets/session_style.dart';
import '../../specs/spec_service.dart';
import '../auto_reviewer.dart';
import '../criteria_batch.dart';
import '../review_service.dart';
import 'review_dialogs.dart';

export '../criteria_batch.dart' show CriterionState, criterionChecked;

final _specProvider = StreamProvider.family<Spec?, int>(
  (ref, id) => ref.watch(specsRepoProvider).watchById(id),
);

final _stepRowsProvider = StreamProvider.family<List<SpecStep>, int>(
  (ref, id) => ref.watch(specStepsRepoProvider).watchBySpec(id),
);

final reviewCommentsProvider =
    StreamProvider.family<List<ReviewCommentRow>, int>(
      (ref, specId) =>
          ref.watch(reviewCommentsRepoProvider).watchBySpec(specId),
    );

final _marksProvider = StreamProvider.family<List<SpecCriteriaData>, int>(
  (ref, specId) => ref.watch(reviewCommentsRepoProvider).watchCriteria(specId),
);

/// Text of the spec file (criteria).
final _specTextProvider = FutureProvider.family<String?, int>((
  ref,
  specId,
) async {
  final spec = await ref.watch(_specProvider(specId).future);
  if (spec == null) return null;
  final ws = await ref.read(workspacesRepoProvider).getById(spec.workspaceId);
  if (ws == null) return null;
  return ref.read(specServiceProvider).read(ws, spec);
});

final criteriaProvider = FutureProvider.family<List<CriterionState>, int>((
  ref,
  specId,
) async {
  final text = await ref.watch(_specTextProvider(specId).future);
  if (text == null) return const [];
  final marks = {
    for (final m in await ref.watch(_marksProvider(specId).future))
      m.criterion: m,
  };
  return [
    for (final c in parseCriteria(text)) (criterion: c, mark: marks[c.text]),
  ];
});

/// Criteria not checked yet (merge needs them all, or a reason).
final pendingCriteriaProvider = FutureProvider.family<List<String>, int>(
  (ref, specId) async => [
    for (final c in await ref.watch(criteriaProvider(specId).future))
      if (!criterionChecked(c)) c.criterion.text,
  ],
);

final _prChecksProvider = FutureProvider.family<List<(String, String)>, String>(
  (ref, sessionId) => ref.read(reviewServiceProvider).prChecks(sessionId),
);

/// Top of the Review of a spec (F5, F6): the automatic reviewer's state,
/// the checks (last gate of each step, PR checks), the acceptance criteria
/// as a checklist and the history of review rounds.
class SpecReviewPanel extends ConsumerStatefulWidget {
  const SpecReviewPanel({
    super.key,
    required this.specId,
    this.sessionId,
    this.prUrl,
    this.merged = false,
  });

  final int specId;
  final String? sessionId;
  final String? prUrl;

  /// The session was merged: "Marcar todos" is disabled.
  final bool merged;

  @override
  ConsumerState<SpecReviewPanel> createState() => _SpecReviewPanelState();
}

class _SpecReviewPanelState extends ConsumerState<SpecReviewPanel> {
  bool _open = true;

  /// Texts of the last "Marcar todos" while its "Desfazer" is on screen.
  List<String>? _batch;

  ScaffoldMessengerState? _messenger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
  }

  @override
  void didUpdateWidget(SpecReviewPanel old) {
    super.didUpdateWidget(old);
    if (old.specId != widget.specId) _dropBatch();
  }

  @override
  void dispose() {
    // Another item of the queue (the Review rebuilds the panel per session):
    // the tree is locked now, so the notice is hidden after this frame.
    if (_batch != null) {
      _batch = null;
      final messenger = _messenger, open = _toastOpen;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (open && _toastOpen && messenger != null && messenger.mounted) {
          messenger.hideCurrentSnackBar();
        }
      });
    }
    super.dispose();
  }

  /// The notice of the last batch is still on screen.
  bool _toastOpen = false;

  /// Ends the undo window of the last batch (and hides its notice).
  void _dropBatch() {
    if (_batch == null) return;
    _batch = null;
    if (_toastOpen) _messenger?.hideCurrentSnackBar();
  }

  Future<void> _setOne(CriterionState c, bool checked) {
    _dropBatch();
    return ref
        .read(reviewCommentsRepoProvider)
        .setCriterion(
          widget.specId,
          c.criterion.text,
          checked: checked,
          by: 'humano',
        );
  }

  Future<void> _runBatch(BatchControl control) async {
    final specId = widget.specId;
    final repo = ref.read(reviewCommentsRepoProvider);
    if (control.action == BatchAction.unmarkMine) {
      _dropBatch();
      await repo.uncheckHumanOnly(specId, control.plan.mine);
      return;
    }
    final plan = control.plan;
    final ok = await showBatchCriteriaDialog(
      context,
      eligible: plan.eligible.length,
      awaiting: plan.awaiting.length,
    );
    if (!ok || !mounted) return;
    // Recomputed: the gate or the reviewer may have checked some meanwhile.
    final now = batchPlan(await ref.read(criteriaProvider(specId).future));
    final done = await repo.setCriteria(
      specId,
      now.eligible,
      checked: true,
      by: 'humano',
    );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    if (done.isEmpty) {
      _batch = null;
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Nada mudou: os critérios já estavam marcados.'),
          persist: false,
          duration: Duration(seconds: 8),
        ),
      );
      return;
    }
    _batch = done;
    _toastOpen = true;
    final n = done.length;
    messenger
        ?.showSnackBar(
          SnackBar(
            key: const ValueKey('review-batch-toast'),
            content: Text(
              '$n ${n == 1 ? 'critério marcado' : 'critérios marcados'} '
              'por você',
            ),
            persist: false,
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              key: const ValueKey('review-batch-undo'),
              label: 'Desfazer',
              onPressed: () {
                if (!identical(_batch, done)) return;
                _batch = null;
                repo.uncheckHumanOnly(specId, done);
              },
            ),
          ),
        )
        .closed
        .then((_) {
          _toastOpen = false;
          if (identical(_batch, done)) _batch = null;
        });
  }

  static const _title = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
    letterSpacing: 0.5,
  );

  @override
  Widget build(BuildContext context) {
    final specId = widget.specId;
    final spec = ref.watch(_specProvider(specId)).value;
    if (spec == null) return const SizedBox.shrink();
    final comments =
        ref.watch(reviewCommentsProvider(specId)).value ??
        const <ReviewCommentRow>[];
    final rows = ref.watch(_stepRowsProvider(specId)).value ?? const [];
    final steps = stepsOf(spec, rows);
    final criteria =
        ref.watch(criteriaProvider(specId)).value ?? const <CriterionState>[];
    final checks = widget.sessionId == null || widget.prUrl == null
        ? const <(String, String)>[]
        : ref.watch(_prChecksProvider(widget.sessionId!)).value ??
              const <(String, String)>[];
    final auto = spec.reviewPhase == ReviewPhase.auto;
    final done = criteria.where(criterionChecked).length;
    final batch = batchControl(criteria);
    final rounds = <int, List<ReviewCommentRow>>{};
    for (final c in comments) {
      rounds.putIfAbsent(c.round, () => []).add(c);
    }
    final gated = [
      for (final s in steps)
        if (s.gate != null) s,
    ];

    return Container(
      key: const ValueKey('spec-review-panel'),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const ValueKey('spec-review-toggle'),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(
                children: [
                  Icon(
                    _open ? Icons.expand_more : Icons.chevron_right,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      [
                        '${spec.code} · verificação e critérios',
                        if (criteria.isNotEmpty)
                          '$done/${criteria.length} critérios',
                        if (rounds.isNotEmpty) '${rounds.length} rodada(s)',
                      ].join(' · '),
                      key: const ValueKey('spec-review-summary'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  if (auto) ...[
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.lilac,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        reviewerLabel(spec, running: true) ?? '',
                        key: const ValueKey('review-auto-label'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.lilac,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SmallButton(
                      key: const ValueKey('review-skip-reviewer'),
                      label: 'Pular revisor',
                      onTap: () => ref.read(autoReviewerProvider).skip(specId),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_open)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                children: [
                  if (gated.isNotEmpty || checks.isNotEmpty) ...[
                    const Text('CHECKS', style: _title),
                    const SizedBox(height: 4),
                    for (final s in gated)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 44,
                              child: Text(
                                s.id,
                                style: const TextStyle(
                                  fontFamily: AppFonts.mono,
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            Expanded(
                              child: GateChips(
                                report: s.gate!,
                                keyPrefix: 'review-gate-${s.id}',
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (checks.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final (name, state) in checks)
                            Text(
                              '${_prIcon(state)} $name',
                              style: TextStyle(
                                fontSize: 11,
                                color: _prColor(state),
                              ),
                            ),
                        ],
                      ),
                    const SizedBox(height: 8),
                  ],
                  if (criteria.isNotEmpty) ...[
                    Row(
                      children: [
                        const Text('CRITÉRIOS DE ACEITE', style: _title),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: _BatchToggle(
                              control: batch,
                              onTap:
                                  widget.merged ||
                                      auto ||
                                      batch.action == BatchAction.none
                                  ? null
                                  : () => _runBatch(batch),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    for (final (i, c) in criteria.indexed)
                      _CriterionTile(
                        index: i,
                        state: c,
                        onChanged: (v) => _setOne(c, v),
                      ),
                    const SizedBox(height: 8),
                  ],
                  if (rounds.isNotEmpty) ...[
                    const Text('RODADAS DE REVIEW', style: _title),
                    for (final MapEntry(key: round, value: list)
                        in rounds.entries.toList().reversed)
                      _RoundTile(round: round, comments: list),
                  ],
                  if (spec.mergeOverride != null)
                    Text(
                      'Merge sem todos os critérios: ${spec.mergeOverride}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.amber,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _prIcon(String state) => switch (state.toLowerCase()) {
    'pass' || 'success' => '✓',
    'fail' || 'failure' => '✗',
    _ => '•',
  };

  static Color _prColor(String state) => switch (state.toLowerCase()) {
    'pass' || 'success' => AppColors.teal,
    'fail' || 'failure' => AppColors.red,
    _ => AppColors.textSecondary,
  };
}

class _CriterionTile extends StatelessWidget {
  const _CriterionTile({
    required this.index,
    required this.state,
    required this.onChanged,
  });

  final int index;
  final CriterionState state;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final checked = criterionChecked(state);
    final by = state.mark?.checked ?? false
        ? switch (state.mark!.checkedBy) {
            'gate' => 'verificação',
            'revisor' => 'revisor automático',
            'humano' => 'você',
            _ => null,
          }
        : state.criterion.checkedInFile
        ? 'arquivo da spec'
        : null;
    return InkWell(
      key: ValueKey('review-criterion-$index'),
      onTap: () => onChanged(!checked),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              checked ? Icons.check_box : Icons.check_box_outline_blank,
              size: 16,
              color: checked ? AppColors.teal : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: state.criterion.text),
                    if (state.criterion.verify != null)
                      TextSpan(
                        text: '  verificar: ${state.criterion.verify}',
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          color: AppColors.textMuted,
                        ),
                      ),
                    if (by != null)
                      TextSpan(
                        text: '  · por $by',
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    if (awaitsVerification(state))
                      state.criterion.requirements.isEmpty
                          ? const TextSpan(
                              text: '  · sem etapa: o gate não o marca',
                              style: TextStyle(color: AppColors.textMuted),
                            )
                          : const TextSpan(
                              text: '  · aguarda a verificação',
                              style: TextStyle(color: AppColors.amber),
                            ),
                  ],
                ),
                style: const TextStyle(fontSize: 12, color: AppColors.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Marcar todos" (SPEC-014): a tri-state checkbox and the label of its
/// mode; one focus target (Space / Enter act), disabled when [onTap] is
/// null.
class _BatchToggle extends StatefulWidget {
  const _BatchToggle({required this.control, required this.onTap});

  final BatchControl control;
  final VoidCallback? onTap;

  @override
  State<_BatchToggle> createState() => _BatchToggleState();
}

class _BatchToggleState extends State<_BatchToggle> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    final enabled = onTap != null;
    final value = widget.control.value;
    final radius = BorderRadius.circular(6);
    return Focus(
      key: const ValueKey('review-criteria-master'),
      canRequestFocus: enabled,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, e) {
        if (!enabled || e is! KeyDownEvent) return KeyEventResult.ignored;
        if (e.logicalKey == LogicalKeyboardKey.space ||
            e.logicalKey == LogicalKeyboardKey.enter) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        checked: value ?? false,
        mixed: value == null,
        enabled: enabled,
        label: widget.control.label,
        excludeSemantics: true,
        onTap: onTap,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: Material(
            color: AppColors.panel,
            shape: RoundedRectangleBorder(borderRadius: radius),
            child: InkWell(
              onTap: onTap,
              canRequestFocus: false,
              borderRadius: radius,
              child: Container(
                key: const ValueKey('review-criteria-master-box'),
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: _focused ? AppColors.amber : AppColors.border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      value == null
                          ? Icons.indeterminate_check_box
                          : value
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      key: ValueKey('review-criteria-master-$value'),
                      size: 16,
                      color: value == false
                          ? AppColors.textSecondary
                          : AppColors.teal,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        widget.control.label,
                        key: const ValueKey('review-criteria-master-label'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundTile extends StatelessWidget {
  const _RoundTile({required this.round, required this.comments});

  final int round;
  final List<ReviewCommentRow> comments;

  @override
  Widget build(BuildContext context) {
    final head = comments.first;
    final who = head.author == 'humano' ? 'Você' : 'Revisor automático';
    final verdict = switch (head.verdict) {
      'aprovar' => ' · aprovou',
      'corrigir' => ' · pediu correções',
      _ => '',
    };
    final sha = head.commitSha == null
        ? ''
        : ' · ${head.commitSha!.substring(0, head.commitSha!.length.clamp(0, 7))}';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rodada $round · $who$verdict$sha',
            key: ValueKey('review-round-$round'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          for (final c in comments)
            Padding(
              padding: const EdgeInsets.only(top: 3, left: 8),
              child: Text.rich(
                TextSpan(
                  children: [
                    if (c.path != null)
                      TextSpan(
                        text:
                            '${c.path}${c.line != null && c.line! > 0 ? ':${c.line}' : ''} ',
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    if (c.severity != null)
                      TextSpan(
                        text: '[${c.severity}] ',
                        style: TextStyle(
                          color: c.severity == 'alta'
                              ? AppColors.red
                              : AppColors.amber,
                        ),
                      ),
                    TextSpan(text: c.body),
                    if (c.requirement != null)
                      TextSpan(
                        text: ' · ${c.requirement}',
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                  ],
                ),
                style: const TextStyle(fontSize: 12, color: AppColors.text),
              ),
            ),
        ],
      ),
    );
  }
}
