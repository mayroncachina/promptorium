import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/structured_run.dart';
import '../../features/cost/cost_format.dart';
import '../providers/provider_logos.dart';
import '../theme/tokens.dart';

/// "Codex · gpt-6.1-terra · 14 mil tokens · custo indisponível" (SPEC-100
/// R10): who runs a structured flow, with which model, and what it used.
/// The cost shows in US$ only when the provider reports it (decisão 5).
String runProviderSummary(StructuredRunInfo info) {
  final parts = <String>[
    providerDisplayName(info.provider),
    if (info.model case final m? when m.isNotEmpty) m,
    if (info.running) 'rodando',
    if (!info.running && info.tokens != null) spokenTokens(info.tokens!),
    if (!info.running && info.failure == null)
      info.costUsd == null ? costUnavailable : formatUsd(info.costUsd!),
    if (info.elapsed case final e? when !info.running) _elapsed(e),
  ];
  return parts.join(' · ');
}

String _elapsed(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds} s';
  final s = d.inSeconds % 60;
  return '${d.inMinutes} min${s == 0 ? '' : ' $s s'}';
}

/// The provider line of a structured flow's dialog (R10), plus what R6,
/// R7 and R11 ask when the run did not go: the reason and the choices.
///
/// [onRetry] runs the flow again; "Usar o … desta vez" and "Enviar sem os
/// prints" set a choice for that one run before calling it.
class RunProviderLine extends ConsumerWidget {
  const RunProviderLine({super.key, required this.slot, this.onRetry});

  final String slot;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(structuredRunsProvider.select((m) => m[slot]));
    if (info == null) return const SizedBox.shrink();
    final failure = info.failure;
    return Column(
      key: ValueKey('run-provider-$slot'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (info.resumed && failure == null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Continua no ${providerDisplayName(info.provider)}, onde a '
              'execução começou.',
              key: const ValueKey('run-provider-resumed'),
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
        if (failure == null)
          Row(
            children: [
              ProviderChip(info.provider, dense: true),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  runProviderSummary(info).split(' · ').skip(1).join(' · '),
                  key: const ValueKey('run-provider-summary'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        if (info.switchedFrom case final from? when failure == null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'rodou no ${providerDisplayName(info.provider)} nesta vez · o '
              'tipo continua no ${providerDisplayName(from)}',
              key: const ValueKey('run-provider-switched'),
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ),
        if (failure != null)
          StructuredFailurePanel(
            slot: slot,
            failure: failure,
            provider: info.provider,
            onRetry: onRetry,
          ),
      ],
    );
  }
}

/// Why a structured run did not go (R6, R11), with the choices for this
/// run only. Nothing switches by itself.
class StructuredFailurePanel extends ConsumerWidget {
  const StructuredFailurePanel({
    super.key,
    required this.slot,
    required this.failure,
    required this.provider,
    this.onRetry,
  });

  final String slot;
  final PlannerException failure;
  final String provider;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.read(structuredRunsProvider.notifier);
    final images = failure is StructuredImagesUnsupported
        ? failure as StructuredImagesUnsupported
        : null;
    final start = failure is StructuredProviderFailure
        ? failure as StructuredProviderFailure
        : null;
    final other = alternativeProvider(provider);
    final name = providerDisplayName(provider);
    final title = images != null
        ? images.message
        : start != null
        ? 'O $name não pôde rodar esta execução'
        : 'A execução no $name falhou';
    final detail = images != null
        ? 'O pedido tem ${images.count} '
              '${images.count == 1 ? 'print' : 'prints'}. O catálogo do '
              '$name não lista a modalidade image para este modelo.'
        : start?.reason ?? failure.message;
    final color = images != null ? AppColors.amber : AppColors.red;
    void retry({String? provider, bool dropImages = false}) {
      runs.once(slot, provider: provider, dropImages: dropImages);
      runs.clear(slot);
      onRetry?.call();
    }

    return Container(
      key: const ValueKey('run-provider-failure'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.text),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (images != null)
                  _Choice(
                    key: const ValueKey('run-send-without-prints'),
                    label: 'Enviar sem os prints',
                    onTap: () => retry(dropImages: true),
                  )
                else
                  _Choice(
                    key: const ValueKey('run-retry'),
                    label: 'Tentar de novo',
                    onTap: retry,
                  ),
                if (other != null && other != provider)
                  _Choice(
                    key: const ValueKey('run-use-other'),
                    label: 'Usar o ${providerDisplayName(other)} desta vez',
                    primary: true,
                    onTap: () => retry(provider: other),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => Material(
    color: primary ? AppColors.amber : AppColors.background,
    borderRadius: BorderRadius.circular(6),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: primary ? AppColors.amber : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: primary ? AppColors.background : AppColors.text,
          ),
        ),
      ),
    ),
  );
}
