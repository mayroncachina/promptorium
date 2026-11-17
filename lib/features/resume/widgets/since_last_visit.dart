import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart' show SmallButton;
import '../resume_actions.dart';
import '../resume_state.dart';
import '../resume_summary.dart';
import 'resume_card.dart';

/// "Desde a sua última visita" on the Início (SPEC-080 R12): what the card
/// left unresolved when it was closed without "Tudo visto", until the next
/// "Tudo visto" or the next return. The approvals and plans stay in the
/// Início's own list.
class SinceLastVisit extends ConsumerStatefulWidget {
  const SinceLastVisit({super.key});

  @override
  ConsumerState<SinceLastVisit> createState() => _SinceLastVisitState();
}

class _SinceLastVisitState extends ConsumerState<SinceLastVisit> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final since = ref.watch(resumeBandSinceProvider);
    if (since == null) return const SizedBox.shrink();
    final view = ref.watch(resumeSummaryForProvider(since));
    final s = view.summary;
    final items = [
      for (final i in s.waiting)
        if (i.activity == null) i,
      ...s.finished,
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Semantics(
        container: true,
        label: 'Desde a sua última visita, ${items.length}',
        child: Container(
          key: const ValueKey('since-last-visit'),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.fromLTRB(8, 6, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    key: const ValueKey('since-last-visit-toggle'),
                    tooltip: _open ? 'Recolher' : 'Expandir',
                    iconSize: 18,
                    onPressed: () => setState(() => _open = !_open),
                    icon: Icon(_open ? Icons.expand_more : Icons.chevron_right),
                  ),
                  const Text(
                    'Desde a sua última visita',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${items.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '· desde ${resumeTime(since, now)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const Spacer(),
                  SmallButton(
                    key: const ValueKey('since-last-visit-seen'),
                    label: '✓ Tudo visto',
                    onTap: () => ref.read(resumeProvider.notifier).allSeen(),
                  ),
                ],
              ),
              if (_open)
                for (final i in items)
                  ResumeItemRow(
                    item: i,
                    now: now,
                    onAction: () => runResumeAction(context, ref, i),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
