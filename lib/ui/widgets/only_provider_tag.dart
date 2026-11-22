import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// "Só Claude Code" / "Só Codex" (SPEC-094 R11): marks a control that the
/// selected provider does not support, in light amber (P4), with the reason
/// in one line as the hint. The control stays visible and disabled.
class OnlyProviderTag extends StatelessWidget {
  const OnlyProviderTag({
    super.key,
    required this.provider,
    required this.reason,
    this.suffix = '',
  });

  /// Name of the provider that has it ("Claude Code").
  final String provider;

  /// One line: "O Codex não tem limite em US$."
  final String reason;

  /// Extra words ("por enquanto").
  final String suffix;

  String get label => 'Só $provider${suffix.isEmpty ? '' : ' $suffix'}';

  @override
  Widget build(BuildContext context) => Tooltip(
    message: reason,
    child: Semantics(
      label: '$label. $reason',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: AppColors.amberLight.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.amberLight.withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lock_outline,
              size: 11,
              color: AppColors.amberLight,
            ),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.amberLight,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
