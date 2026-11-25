import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/providers/provider_logos.dart' show ProviderChip;
import '../../../ui/theme/tokens.dart';
import '../../project/project_config.dart';
import '../reviewer_provider.dart';

/// The line Revisão of Executar (SPEC-102 R3): who will review the spec
/// and with which model, "segunda opinião" when it is the other provider,
/// and "do config do projeto" when `provedor:` decides.
class ReviewerRunLine extends ConsumerWidget {
  const ReviewerRunLine({
    super.key,
    required this.config,
    required this.executedBy,
    this.auto = false,
  });

  final ReviewerConfig config;

  /// The provider the run will use (or uses).
  final String executedBy;

  /// Executar in Automático (the plan's rule, unless `provedor:`).
  final bool auto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = resolveReviewerChoice(
      config,
      executedBy: executedBy,
      auto: auto,
    );
    final model = reviewerModelLabel(
      choice,
      config,
      ref.watch(appSettingsProvider),
    );
    final why = [
      if (choice.secondOpinion) secondOpinionLabel,
      if (choice.fromConfig)
        'do config do projeto · provedor: ${config.provider}',
    ].join(' · ');
    return Container(
      key: const ValueKey('run-spec-reviewer-line'),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 40,
            child: Text(
              'REV',
              style: TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Revisão automática',
                  style: TextStyle(fontSize: 13),
                ),
                if (why.isNotEmpty)
                  Text(
                    why,
                    key: const ValueKey('run-spec-reviewer-why'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ProviderChip(choice.provider, dense: true),
          const SizedBox(width: 8),
          Text(
            model,
            key: const ValueKey('run-spec-reviewer-model'),
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
