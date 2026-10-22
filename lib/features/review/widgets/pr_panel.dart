import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart';
import '../pr_babysitter.dart';
import '../review_service.dart';

/// PR of the reviewed session (F16): its state, "Acompanhar PR", "Mergear
/// PR" (squash / rebase / merge) and "Resolver conflito".
class PrPanel extends ConsumerStatefulWidget {
  const PrPanel({super.key, required this.session, this.localConflict = false});

  final Session session;

  /// The last local merge stopped on a conflict.
  final bool localConflict;

  @override
  ConsumerState<PrPanel> createState() => _PrPanelState();
}

class _PrPanelState extends ConsumerState<PrPanel> {
  bool _busy = false;
  PrStatus? _openedStatus;
  String? _openedError;
  @override
  void initState() {
    super.initState();
    if (widget.session.prUrl != null) {
      Future<void>.microtask(() async {
        try {
          final status = await ref
              .read(reviewServiceProvider)
              .refreshPrComments(_id);
          if (mounted) setState(() => _openedStatus = status);
        } catch (e) {
          if (mounted) setState(() => _openedError = '$e');
        }
      });
    }
  }

  String? _message;

  String get _id => widget.session.id;

  Future<void> _do(String done, Future<void> Function() job) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await job();
      _message = done;
    } catch (e) {
      _message = '$e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPr = widget.session.prUrl != null;
    if (!hasPr && !widget.localConflict) return const SizedBox.shrink();
    final watch = ref.watch(prBabysitterProvider)[_id];
    final sitter = ref.read(prBabysitterProvider.notifier);
    final status = watch?.status ?? _openedStatus;
    final conflict = widget.localConflict || (status?.conflicting ?? false);
    return Container(
      key: const ValueKey('review-pr-panel'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 6,
        children: [
          if (_openedError != null || watch?.error != null)
            Text(_openedError ?? watch!.error!),
          if (hasPr)
            Text(
              status == null
                  ? 'PR: ${watch?.error ?? 'não verificado'}'
                  : 'PR ${status.summary}',
              key: const ValueKey('review-pr-status'),
              style: TextStyle(
                fontSize: 12,
                color: status?.conflicting ?? false
                    ? AppColors.red
                    : AppColors.textSecondary,
              ),
            ),
          if (hasPr)
            FilterChip(
              key: const ValueKey('review-pr-babysit'),
              label: const Text(
                'Acompanhar PR',
                style: TextStyle(fontSize: 11),
              ),
              selected: sitter.isWatching(_id),
              onSelected: _busy
                  ? null
                  : (_) => _do('', () => sitter.toggle(_id)),
            ),
          if (hasPr)
            SmallButton(
              key: const ValueKey('review-pr-check'),
              label: 'Verificar agora',
              onTap: _busy ? null : () => _do('', () => sitter.check(_id)),
            ),
          if (hasPr && (status?.open ?? true))
            PopupMenuButton<PrMergeMethod>(
              key: const ValueKey('review-pr-merge'),
              tooltip: 'gh pr merge',
              color: AppColors.panel,
              enabled: !_busy,
              onSelected: (m) => _do(
                'PR mergeado (${m.label}). Atualize a branch base com git pull.',
                () async {
                  await ref.read(reviewServiceProvider).mergePr(_id, m);
                  ref.read(selectedReviewProvider.notifier).select(null);
                },
              ),
              itemBuilder: (_) => [
                for (final m in PrMergeMethod.values)
                  PopupMenuItem(
                    value: m,
                    child: Text(
                      'Mergear PR · ${m.label}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  'Mergear PR ▾',
                  style: TextStyle(fontSize: 12, color: AppColors.amber),
                ),
              ),
            ),
          if (conflict)
            SmallButton(
              key: const ValueKey('review-resolve-conflict'),
              label: 'Resolver conflito com o agente',
              color: AppColors.red,
              onTap: _busy
                  ? null
                  : () => _do(
                      'Instruções enviadas à sessão.',
                      () =>
                          ref.read(reviewServiceProvider).resolveConflict(_id),
                    ),
            ),
          if (_message != null && _message!.isNotEmpty)
            Text(
              _message!,
              style: const TextStyle(fontSize: 11, color: AppColors.amber),
            ),
        ],
      ),
    );
  }
}
