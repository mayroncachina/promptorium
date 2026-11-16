import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/claude/usage_tracker.dart';
import '../../../ui/theme/tokens.dart';
import '../quota_forecast.dart';

/// The 5-hour window and the week, with the forecast at the current pace
/// (SPEC-076 R7, R16).
class QuotaCard extends ConsumerWidget {
  const QuotaCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final f = quotaForecast(ref.watch(quotaSamplesProvider), now: now);
    final rate = ref.watch(rateLimitProvider);
    final weekResets = rate?.sevenDayResetsAt;
    final week = planWindowExpired(weekResets, now)
        ? 0.0
        : rate?.sevenDayUtilization;
    Widget meter(
      String label,
      double? used,
      String note,
      Color color,
      String key,
    ) => SizedBox(
      width: 150,
      child: Column(
        key: ValueKey(key),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Text(
                used == null ? '—' : '${(used * 100).round()}%',
                style: TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: (used ?? 0).clamp(0, 1),
              minHeight: 4,
              backgroundColor: Colors.white.withValues(alpha: .08),
              color: color,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            note,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted),
          ),
        ],
      ),
    );
    return Container(
      key: const ValueKey('activities-quota'),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          meter(
            'Janela de 5 h',
            f.used,
            f.text,
            f.endsAt != null ? AppColors.amber : AppColors.teal,
            'activities-quota-5h',
          ),
          const SizedBox(width: 18),
          meter(
            'Semana',
            week,
            weekResetLabel(weekResets),
            AppColors.teal,
            'activities-quota-week',
          ),
        ],
      ),
    );
  }
}
