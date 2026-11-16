import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/claude/usage_tracker.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart';
import '../cost_estimate.dart';
import '../environment_check.dart' show planLabel;

/// "Uso" (SPEC-072 R8): on a subscription plan, the 5-hour and weekly quota
/// of [rateLimitProvider]; with an API key, the dollar ceiling per call.
class UsageBlock extends ConsumerWidget {
  const UsageBlock({
    super.key,
    required this.subscriptionType,
    this.title = true,
    this.now,
  });

  /// `max`, `pro`; null = API key (P6).
  final String? subscriptionType;

  /// Shows the "USO · PLANO MAX" title.
  final bool title;

  /// Clock of the "renova" texts (tests).
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const small = TextStyle(fontSize: 11, color: AppColors.textSecondary);
    final plan = subscriptionType;
    if (plan == null) {
      return Column(
        key: const ValueKey('usage-block'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title) ...[
            const Text('USO · CHAVE DE API', style: sectionTitleStyle),
            const SizedBox(height: 6),
          ],
          Text(
            'Com chave de API cada chamada é cobrada, com teto: $apiCeiling.',
            key: const ValueKey('usage-api'),
            style: small,
          ),
        ],
      );
    }
    final rate = ref.watch(rateLimitProvider);
    final at = now ?? DateTime.now();
    final name = planLabel(plan);
    return Column(
      key: const ValueKey('usage-block'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title) ...[
          Text('USO · PLANO ${name.toUpperCase()}', style: sectionTitleStyle),
          const SizedBox(height: 8),
        ],
        if (rate == null ||
            (rate.fiveHourUtilization == null &&
                rate.sevenDayUtilization == null))
          const Text(
            'O uso aparece depois da primeira chamada.',
            key: ValueKey('usage-empty'),
            style: small,
          )
        else ...[
          _Bar(
            key: const ValueKey('usage-5h'),
            label: 'Janela de 5 h',
            value: rate.fiveHourUtilization,
            resetsAt: rate.fiveHourResetsAt,
            now: at,
          ),
          const SizedBox(height: 4),
          _Bar(
            key: const ValueKey('usage-week'),
            label: 'Semana',
            value: rate.sevenDayUtilization,
            resetsAt: rate.sevenDayResetsAt,
            now: at,
          ),
        ],
        const SizedBox(height: 6),
        Text(
          'No plano $name não há cobrança por chamada: o planner e a fila '
          'gastam da quota.',
          key: const ValueKey('usage-quota-note'),
          style: small,
        ),
      ],
    );
  }
}

const _weekdays = ['seg.', 'ter.', 'qua.', 'qui.', 'sex.', 'sáb.', 'dom.'];

String _hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// "renova às 18:40" (today), "renova sex. 09:00", or "renovada" (R8).
String renewText(DateTime? resetsAt, DateTime now) {
  if (resetsAt == null) return '';
  if (planWindowExpired(resetsAt, now)) return 'renovada';
  final local = resetsAt.toLocal();
  final n = now.toLocal();
  final sameDay =
      local.year == n.year && local.month == n.month && local.day == n.day;
  return sameDay
      ? 'renova às ${_hm(local)}'
      : 'renova ${_weekdays[local.weekday - 1]} ${_hm(local)}';
}

class _Bar extends StatelessWidget {
  const _Bar({
    super.key,
    required this.label,
    required this.value,
    required this.resetsAt,
    required this.now,
  });

  final String label;
  final double? value;
  final DateTime? resetsAt;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final expired = planWindowExpired(resetsAt, now);
    final v = expired ? 0.0 : (value ?? 0).clamp(0.0, 1.0);
    final pct = expired || value == null ? '—' : '${(v * 100).round()}%';
    final renew = renewText(resetsAt, now);
    return Semantics(
      label:
          '$label: ${expired ? 'renovada' : pct}${renew.isEmpty || expired ? '' : ', $renew'}',
      child: ExcludeSemantics(
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: v,
                  minHeight: 5,
                  backgroundColor: AppColors.border,
                  color: v >= 0.9 ? AppColors.red : AppColors.teal,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 36,
              child: Text(
                pct,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 104,
              child: Text(
                renew,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
