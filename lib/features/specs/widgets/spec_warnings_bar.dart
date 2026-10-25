import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';
import '../spec_lint.dart';

/// Collapsible strip below the spec editor with the structure warnings
/// (SPEC-023 R8): "N avisos" closed, the list open. A warning takes the
/// editor to its line (R9). Every row is reachable by Tab and Enter (R14).
class SpecWarningsBar extends StatelessWidget {
  const SpecWarningsBar({
    super.key,
    required this.warnings,
    required this.open,
    required this.onToggle,
    required this.onSelect,
  });

  final List<SpecWarning> warnings;
  final bool open;
  final VoidCallback onToggle;
  final ValueChanged<SpecWarning> onSelect;

  static String countLabel(int n) =>
      n == 1 ? '1 aviso de estrutura' : '$n avisos de estrutura';

  @override
  Widget build(BuildContext context) {
    final count = countLabel(warnings.length);
    return Container(
      key: const ValueKey('spec-warnings'),
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            expanded: open,
            label: '$count. ${open ? 'Recolher' : 'Mostrar'} a lista',
            excludeSemantics: true,
            child: InkWell(
              key: const ValueKey('spec-warnings-toggle'),
              onTap: onToggle,
              focusColor: AppColors.amberTint,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Icon(
                      open ? Icons.expand_more : Icons.chevron_right,
                      size: 16,
                      color: AppColors.amber,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      count,
                      key: const ValueKey('spec-warnings-count'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.amber,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'não impedem salvar nem aprovar',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (open)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: ListView(
                key: const ValueKey('spec-warnings-list'),
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 6),
                children: [
                  for (final (i, w) in warnings.indexed)
                    Semantics(
                      button: true,
                      label: 'Linha ${w.line}: ${w.message}. Ir para a linha',
                      excludeSemantics: true,
                      child: InkWell(
                        key: ValueKey('spec-warning-$i'),
                        onTap: () => onSelect(w),
                        focusColor: AppColors.amberTint,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 3,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'linha ${w.line}',
                                style: const TextStyle(
                                  fontFamily: AppFonts.mono,
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  w.message,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.text,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
