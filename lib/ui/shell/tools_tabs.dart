import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'navigation.dart';

/// Tabs of "Ferramentas" (Agentes · Skills · MCP) above the active one.
class ToolsTabs extends StatelessWidget {
  const ToolsTabs({
    super.key,
    required this.active,
    required this.onSelect,
    required this.child,
  });

  final AppSection active;
  final ValueChanged<AppSection> onSelect;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: const BoxDecoration(
          color: AppColors.panel,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            for (final s in AppSection.toolTabs)
              InkWell(
                key: ValueKey('tools-tab-${s.name}'),
                onTap: () => onSelect(s),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: s == active
                            ? AppColors.amber
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    s == AppSection.mcp ? 'MCP' : s.label,
                    style: TextStyle(
                      fontSize: 12,
                      color: s == active
                          ? AppColors.text
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      Expanded(child: child),
    ],
  );
}
