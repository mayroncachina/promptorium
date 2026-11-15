import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/db/app_database.dart';
import '../../../ui/theme/tokens.dart';
import '../../review/ci_fixer.dart';
import '../../review/pr_babysitter.dart';
import '../../review/widgets/ci_panel.dart' show confirmAndFixCi, showCiToast;
import '../../sessions/widgets/session_style.dart';
import '../board_screen.dart' show SpecCardData;

/// What the CI badge of a card says (SPEC-073 R7).
@immutable
class CiBadgeView {
  const CiBadgeView(
    this.label,
    this.color, {
    this.action,
    this.tooltip,
    this.disabledReason,
  });

  final String label;
  final Color color;

  /// "Corrigir CI" or "Cancelar" next to the badge.
  final String? action;
  final String? tooltip;

  /// Why [action] is off (R9).
  final String? disabledReason;
}

String _elapsed(DateTime since, DateTime now) {
  final m = now.difference(since).inMinutes;
  return m < 1 ? 'agora' : '$m min';
}

/// The badge of a PR whose state the app knows ([status]) and of its CI fix
/// ([fix]); null = nothing to show.
CiBadgeView? ciBadgeOf(PrStatus? status, CiFixState? fix, {DateTime? now}) {
  if (status == null) return null;
  final at = now ?? DateTime.now();
  if (fix != null) {
    return switch (fix.phase) {
      CiFixPhase.queued => const CiBadgeView(
        'Na fila · sessão ocupada',
        AppColors.amber,
        action: 'Cancelar',
      ),
      CiFixPhase.fixing => CiBadgeView(
        'Corrigindo CI · ${_elapsed(fix.since, at)}',
        AppColors.amber,
      ),
      CiFixPhase.running => CiBadgeView(
        'CI rodando · ${shortSha(fix.pushedSha ?? status.headSha)}',
        AppColors.blue,
      ),
      CiFixPhase.rerunning => CiBadgeView(
        'Rodando de novo · tentativa ${fix.attempt}',
        AppColors.blue,
      ),
      CiFixPhase.fixed => CiBadgeView(
        'CI corrigido · ${fix.round} ${fix.round == 1 ? 'rodada' : 'rodadas'}',
        AppColors.teal,
      ),
      CiFixPhase.stopped => const CiBadgeView(
        'CI falhou de novo · automático parado',
        AppColors.red,
        action: 'Corrigir CI',
      ),
      CiFixPhase.noCommit => CiBadgeView(
        'O agente terminou sem commit',
        AppColors.red,
        tooltip: fix.detail,
      ),
      CiFixPhase.external => CiBadgeView(
        'CI: falha externa',
        AppColors.amber,
        tooltip: fix.detail,
      ),
      CiFixPhase.pushRefused => CiBadgeView(
        'Push recusado',
        AppColors.red,
        tooltip: fix.detail,
      ),
      CiFixPhase.local => const CiBadgeView(
        'Correção local · use Copiar patch',
        AppColors.amber,
      ),
    };
  }
  if (!status.open) return null;
  final failed = status.failedChecks;
  if (failed.isEmpty) return null;
  final withLog = failed.any((c) => c.hasLog);
  return CiBadgeView(
    'CI falhou · ${failed.length}',
    AppColors.red,
    action: 'Corrigir CI',
    tooltip: failed.map((c) => c.name).join(', '),
    disabledReason: withLog ? null : 'Nenhum check com log do GitHub Actions',
  );
}

/// The PR session of a card: the newest session of the spec with a PR.
Session? prSessionOf(SpecCardData data) =>
    data.sessions.where((s) => s.prUrl != null).lastOrNull;

/// The CI badge of a card with a PR (R7), next to "Corrigir CI". Only when
/// the app knows the PR's state ("Acompanhar PR" or opened in the Review).
/// Fixing the CI never moves the card out of Review.
class CiBadge extends ConsumerWidget {
  const CiBadge({super.key, required this.data});

  final SpecCardData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = prSessionOf(data);
    if (s == null) return const SizedBox.shrink();
    final status = ref.watch(
      prBabysitterProvider.select((m) => m[s.id]?.status),
    );
    final fix = ref.watch(ciFixerProvider.select((m) => m[s.id]));
    final view = ciBadgeOf(status, fix);
    if (view == null) return const SizedBox.shrink();
    final code = data.spec.code;
    final pill = Container(
      key: ValueKey('board-ci-$code'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: view.color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: view.color.withValues(alpha: .5)),
      ),
      child: Text(
        view.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: view.color,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Flexible(
            child: view.tooltip == null
                ? pill
                : Tooltip(message: view.tooltip!, child: pill),
          ),
          const Spacer(),
          if (view.action case final action?)
            Tooltip(
              message: view.disabledReason ?? '',
              child: SmallButton(
                key: ValueKey('board-ci-action-$code'),
                label: action,
                height: 26,
                fontSize: 11,
                color: action == 'Cancelar' ? AppColors.text : AppColors.red,
                onTap: view.disabledReason != null
                    ? null
                    : () async {
                        final fixer = ref.read(ciFixerProvider.notifier);
                        if (action == 'Cancelar') {
                          await fixer.cancel(s.id);
                          return;
                        }
                        try {
                          final sent = await confirmAndFixCi(
                            context,
                            ref,
                            s.id,
                          );
                          if (sent && context.mounted) {
                            showCiToast(
                              context,
                              '$code: log do CI enviado ao agente.',
                            );
                          }
                        } catch (e) {
                          if (context.mounted) showCiToast(context, '$e');
                        }
                      },
              ),
            ),
        ],
      ),
    );
  }
}
