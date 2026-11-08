import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../auto_reviewer.dart' show ReviewPhase;
import '../comment_anchor.dart';
import '../conflict_resolution.dart';
import '../merge_readiness.dart';
import '../review_service.dart';
import '../review_stack.dart';
import '../restack.dart';
import 'spec_review_panel.dart';

/// State of a queue item shared by the list and the graph (SPEC-032 R3).

/// Merge state of [item] (SPEC-032 R3): reviewer, mother still in review,
/// predicted conflict (R4), pendencies. [readiness] refines it for the
/// selected item.
MergeStatus watchMergeStatus(
  WidgetRef ref,
  ReviewItem item, {
  MergeReadiness? readiness,
}) {
  final s = item.session, spec = item.spec;
  final peers = ref.watch(specsProvider(s.workspaceId)).value ?? <Spec>[];
  String? mother = peers
      .where(
        (p) =>
            p.id != spec?.id &&
            p.branch != null &&
            p.branch == s.baseBranch &&
            p.stage != SpecStage.done,
      )
      .firstOrNull
      ?.code;
  final stacked = readiness?.blockers
      .where((i) => i.id == 'empilhada')
      .firstOrNull;
  if (mother == null && stacked != null) {
    mother =
        RegExp(r'de (\S+) primeiro').firstMatch(stacked.detail)?.group(1) ??
        'a mãe';
  }
  final criteria = spec == null
      ? null
      : ref.watch(pendingCriteriaProvider(spec.id)).value;
  final comments = spec == null
      ? 0
      : (ref.watch(reviewCommentsProvider(spec.id)).value ??
                const <ReviewCommentRow>[])
            .where(isOpenReviewComment)
            .length;
  final flagged =
      readiness?.items.any(
        (i) =>
            const {'criterios', 'verificacoes', 'comentarios'}.contains(i.id) &&
            (i.level == ReadinessLevel.aviso ||
                i.level == ReadinessLevel.bloqueio),
      ) ??
      false;
  final forecast = ref.watch(conflictForecastProvider(s.id));
  final files = forecast.hasError
      ? const <String>[]
      : forecast.value == null
      ? null
      : forecast.value!.error != null
      ? const <String>[]
      : forecast.value!.files;
  final mark = ref.watch(
    appSettingsProvider.select((m) => m[restackMarkKey(s.id)]),
  );
  final rebase = ref.watch(rebaseStatusProvider(s.id)).value;
  final resolution = ref.watch(conflictResolutionProvider(s.id));
  return mergeStatusOf(
    resolution: resolution?.state,
    resolutionDetail: switch (resolution?.state) {
      ResolutionState.conferindo when resolution!.running != null =>
        gateItemLabel(resolution.running!),
      ResolutionState.reprovada => resolution!.firstFailure?.label,
      _ => null,
    },
    rebaseStep: rebase?.inProgress ?? false
        ? '${rebase!.step} de ${rebase.total}'
        : null,
    reviewing:
        spec?.reviewPhase == ReviewPhase.auto &&
        spec?.stage == SpecStage.review,
    motherCode: mother,
    restackConflict: mark?.startsWith('conflito') ?? false,
    staleBase: mark?.startsWith('desatualizada') ?? false,
    conflictFiles: files,
    pending: (criteria?.isNotEmpty ?? false) || comments > 0 || flagged,
  );
}

(IconData, Color) mergeStateLook(MergeState s) => switch (s) {
  MergeState.pronto => (Icons.check_circle, AppColors.teal),
  MergeState.verificando => (Icons.more_horiz, AppColors.textMuted),
  MergeState.esperaMae => (Icons.hourglass_empty, AppColors.amber),
  MergeState.conflito ||
  MergeState.conflitoBase => (Icons.warning_amber_rounded, AppColors.red),
  MergeState.baseDesatualizada => (Icons.sync_problem, AppColors.amber),
  MergeState.revisando => (Icons.rate_review_outlined, AppColors.blue),
  MergeState.pendencias => (Icons.error_outline, AppColors.amber),
  MergeState.rebaseManual => (Icons.schedule, AppColors.amber),
  MergeState.resolvendo => (Icons.autorenew, AppColors.amber),
  MergeState.conferindo => (Icons.speed, AppColors.blue),
  MergeState.resolvida => (Icons.check, AppColors.teal),
  MergeState.reprovada => (Icons.disabled_by_default_outlined, AppColors.red),
  MergeState.resolucaoDesatualizada => (Icons.sync, AppColors.amber),
};
