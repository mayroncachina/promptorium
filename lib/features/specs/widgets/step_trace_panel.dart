import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/git_service.dart' show GitLogEntry;
import '../../../data/providers.dart';
import '../../../ui/shell/navigation.dart';
import '../../../ui/theme/tokens.dart';
import '../../board/board_rules.dart';
import '../../board/board_screen.dart' show openSession;
import '../../board/widgets/gate_report_view.dart';
import '../../board/widgets/spec_steps_panel.dart'
    show rewindStepAction, selectedStepProvider, stepStatusColor;
import '../../review/review_screen.dart' show stepCommitsProvider;
import '../../review/review_service.dart'
    show reviewInitialStepProvider, selectedReviewProvider;
import '../../sessions/session_manager.dart' show sessionTitle;
import '../../sessions/widgets/session_style.dart';
import '../spec_file.dart';

/// Rastreabilidade de uma etapa (UX v2, U5; docs/mockups/v2/Specs.dc.html):
/// criteria of the step with who checked them, its gate, the design it
/// used, its commits and its session, plus the ways to act on it.

/// Criteria of [text] that cite [step] (`[R2]`).
List<SpecCriterion> criteriaOfStep(String text, String step) => [
  for (final c in parseCriteria(text))
    if (c.requirements.contains(step)) c,
];

/// Paragraphs of the `## Design` section that mention [step]; when none
/// does, the beginning of the section (null = no design).
String? designExcerpt(String? design, String step, {int max = 320}) {
  if (design == null || design.trim().isEmpty) return null;
  final paras = design
      .split(RegExp(r'\n\s*\n'))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  final hits = [
    for (final p in paras)
      if (RegExp('\\b${RegExp.escape(step)}\\b').hasMatch(p)) p,
  ];
  final out = (hits.isEmpty ? paras : hits).join('\n\n');
  return out.length > max ? '${out.substring(0, max).trimRight()}…' : out;
}

/// Checked state of the criteria of a spec (`spec_criteria`).
final specCriteriaProvider = StreamProvider.family<List<SpecCriteriaData>, int>(
  (ref, specId) => ref.watch(reviewCommentsRepoProvider).watchCriteria(specId),
);

String _byLabel(String? by) => switch (by) {
  'gate' => 'gate',
  'revisor' => 'revisor',
  'humano' => 'você',
  null => '',
  _ => by,
};

class StepTracePanel extends ConsumerWidget {
  const StepTracePanel({
    super.key,
    required this.spec,
    required this.step,
    required this.text,
    required this.sessions,
  });

  final Spec spec;
  final StepView step;

  /// Current text of the spec file.
  final String text;

  /// Sessions of the spec, oldest first.
  final List<Session> sessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doc = SpecDocument.parse(text);
    final criteria = criteriaOfStep(text, step.id);
    final marks = {
      for (final m
          in ref.watch(specCriteriaProvider(spec.id)).value ??
              const <SpecCriteriaData>[])
        m.criterion: m,
    };
    final checked = criteria
        .where((c) => (marks[c.text]?.checked ?? false) || c.checkedInFile)
        .length;
    final session = sessions.where((s) => s.id == step.sessionId).firstOrNull;
    final branchSession = sessions.lastOrNull;
    final commits = branchSession == null
        ? const <GitLogEntry>[]
        : (ref.watch(stepCommitsProvider(branchSession.id)).value ??
                  const <String, List<GitLogEntry>>{})[step.id] ??
              const <GitLogEntry>[];
    final design = designExcerpt(doc.design, step.id);
    final color = stepStatusColor(step.status);

    return ListView(
      key: ValueKey('step-trace-${step.id}'),
      padding: EdgeInsets.zero,
      children: [
        Row(
          children: [
            Text(
              step.id,
              style: TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12,
                color: color,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                step.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              stepStatusLabel(step.status),
              style: TextStyle(fontSize: 11, color: color),
            ),
            IconButton(
              key: const ValueKey('step-trace-close'),
              tooltip: 'Fechar',
              iconSize: 14,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, color: AppColors.textSecondary),
              onPressed: () => ref.read(selectedStepProvider.notifier).clear(),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _title(
          'Critérios',
          criteria.isEmpty ? '' : '· $checked de ${criteria.length}',
        ),
        if (criteria.isEmpty)
          const Text(
            'Nenhum critério cita esta etapa. Escreva "[Rn]" na linha do '
            'critério para ligá-lo.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        for (final c in criteria)
          _CriterionRow(spec: spec, criterion: c, mark: marks[c.text]),
        const SizedBox(height: 12),
        _title('Gate da etapa', ''),
        if (step.gate case final g?)
          GateChips(report: g, keyPrefix: 'trace-gate-${step.id}')
        else
          const Text(
            'Ainda não verificada.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        const SizedBox(height: 12),
        _title('Design usado', ''),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            design ??
                (doc.designWaived
                    ? 'Design dispensado nesta spec.'
                    : 'A spec não tem seção Design.'),
            key: const ValueKey('step-trace-design'),
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _title('Commits', commits.isEmpty ? '' : '· ${commits.length}'),
        if (commits.isEmpty)
          Text(
            branchSession == null
                ? 'A etapa ainda não rodou.'
                : 'Nenhum commit "${spec.code} ${step.id}:" na branch.',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        for (final c in commits)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Text(
                  c.shortSha,
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 11,
                    color: AppColors.amber,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    c.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        _title('Sessão', ''),
        if (session == null)
          const Text(
            'Sem sessão para esta etapa.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted),
          )
        else ...[
          _kv('Título', sessionTitle(session)),
          _kv(
            'Duração',
            formatDuration(
              (session.endedAt ?? DateTime.now()).difference(session.startedAt),
            ),
          ),
          _kv('Custo', formatCost(session.costUsd)),
          _kv('Modelo', session.model),
          if (step.startSha case final sha?)
            _kv('Checkpoint', sha.length > 8 ? sha.substring(0, 8) : sha),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            AmberButton(
              key: const ValueKey('step-trace-diff'),
              label: 'Ver diff da etapa',
              height: 28,
              onTap: branchSession == null
                  ? null
                  : () {
                      ref
                          .read(selectedReviewProvider.notifier)
                          .select(branchSession.id);
                      ref.read(reviewInitialStepProvider.notifier).set(step.id);
                      ref
                          .read(navigationProvider.notifier)
                          .go(AppSection.review);
                    },
            ),
            SmallButton(
              key: const ValueKey('step-trace-session'),
              label: 'Abrir sessão',
              height: 28,
              onTap: session == null
                  ? null
                  : () => openSession(ref, session.id),
            ),
            if (step.startSha != null &&
                spec.worktreePath != null &&
                spec.stage != SpecStage.done)
              SmallButton(
                key: const ValueKey('step-trace-redo'),
                label: 'Refazer a partir daqui',
                height: 28,
                color: AppColors.amber,
                border: SessionColors.approvalBorder,
                onTap: () =>
                    rewindStepAction(context, ref, spec, step, redo: true),
              ),
          ],
        ),
      ],
    );
  }

  Widget _title(String text, String count) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Text(text.toUpperCase(), style: sectionTitleStyle),
        if (count.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text(
            count,
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    ),
  );

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(
      children: [
        SizedBox(
          width: 84,
          child: Text(
            k,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            v,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFamily: AppFonts.mono, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

class _CriterionRow extends ConsumerWidget {
  const _CriterionRow({
    required this.spec,
    required this.criterion,
    required this.mark,
  });

  final Spec spec;
  final SpecCriterion criterion;
  final SpecCriteriaData? mark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checked = (mark?.checked ?? false) || criterion.checkedInFile;
    final by = mark?.checked == true
        ? _byLabel(mark?.checkedBy)
        : (criterion.checkedInFile ? 'arquivo' : '');
    final when = mark?.checkedAt;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Checkbox(
              key: ValueKey('step-trace-criterion-${criterion.text}'),
              value: checked,
              onChanged: (v) => ref
                  .read(reviewCommentsRepoProvider)
                  .setCriterion(
                    spec.id,
                    criterion.text,
                    checked: v ?? false,
                    by: 'humano',
                  ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(criterion.text, style: const TextStyle(fontSize: 12)),
                if (by.isNotEmpty || criterion.verify != null)
                  Text(
                    [
                      if (by.isNotEmpty)
                        'marcado por $by'
                            '${when == null ? '' : ' · ${formatClock(when)}'}',
                      if (criterion.verify case final v?) 'verificar: $v',
                    ].join(' · '),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
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
