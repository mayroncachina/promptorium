import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/quota_source.dart';
import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../handoff/continue_controller.dart';
import '../handoff/continue_dialog.dart';
import '../handoff/continue_link.dart';
import '../handoff/continue_widgets.dart';
import '../handoff/session_summary.dart' show providerWords;
import '../timeline.dart';
import '../timeline_provider.dart';

/// Sessions whose banner was closed (until the app restarts).
class _Dismissed extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void add(String id) => state = {...state, id};
}

final quotaBannerDismissedProvider =
    NotifierProvider<_Dismissed, Set<String>>(_Dismissed.new);

/// "1h43", "12 min".
String untilWords(Duration d) {
  if (d.isNegative) return 'agora';
  final h = d.inHours, m = d.inMinutes % 60;
  if (h > 0) return '${h}h${m.toString().padLeft(2, '0')}';
  return '${d.inMinutes < 1 ? 1 : d.inMinutes} min';
}

/// The free share of the target's quota: 100 − the most used window
/// (null = unknown).
int? freePercent(QuotaSnapshot s) {
  double? used;
  for (final w in s.main.windows) {
    final u = w.usedPercent;
    if (u != null && (used == null || u > used)) used = u;
  }
  return used == null ? null : (100 - used).clamp(0, 100).round();
}

/// The text of the banner (R2).
String quotaBannerText(LimitItem limit, {required String target, int? free, DateTime? now}) {
  final b = StringBuffer(
    '${quotaWindowWords(limit.minutes).replaceFirst('cota', 'Cota')} do '
    '${providerWords(limit.provider)} esgotada',
  );
  if (limit.resetsAt case final at?) {
    b.write(' · reinicia em ${untilWords(at.difference(now ?? DateTime.now()))}');
  }
  if (free != null) b.write(' · ${providerWords(target)} com $free% livre');
  return b.toString();
}

/// R2: when the origin stopped at its usage limit, a banner above the
/// composer suggests the other agent — only if that one has quota. It is a
/// suggestion: the app never switches by itself.
class QuotaSwitchBanner extends ConsumerWidget {
  const QuotaSwitchBanner({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = session;
    final limit = ref.watch(
      sessionTimelineProvider(s.id).select((t) => lastLimit(t.timeline.items)),
    );
    if (limit == null) return const SizedBox.shrink();
    if (ref.watch(quotaBannerDismissedProvider).contains(s.id)) {
      return const SizedBox.shrink();
    }
    // Already continued: the link in the header says where.
    final continued = ref.watch(
      continuationLinksProvider(
        s.workspaceId,
      ).select((l) => l.value?.continuedInto(s.id) != null),
    );
    if (continued) return const SizedBox.shrink();
    final a = watchContinueAvailability(ref, s);
    if (!a.enabled) return const SizedBox.shrink();
    final target = a.target!;
    final snap = ref.watch(quotaSnapshotProvider(target));
    if (snap == null || !snap.hasReading) return const SizedBox.shrink();
    if (snap.limit(DateTime.now()) != null) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('quota-switch-banner'),
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.teal.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ReviewColors.acceptBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.swap_horiz, size: 16, color: AppColors.teal),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              quotaBannerText(limit, target: target, free: freePercent(snap)),
              key: const ValueKey('quota-switch-text'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AppColors.text),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            key: const ValueKey('quota-switch-go'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.teal,
              side: const BorderSide(color: ReviewColors.acceptBorder),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => openContinue(context, ref, s),
            child: Text(continueLabel(target)),
          ),
          IconButton(
            key: const ValueKey('quota-switch-close'),
            tooltip: 'Fechar',
            icon: const Icon(Icons.close, size: 14),
            onPressed: () =>
                ref.read(quotaBannerDismissedProvider.notifier).add(s.id),
          ),
        ],
      ),
    );
  }
}
