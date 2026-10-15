import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/app_icon.dart';
import 'navigation.dart';

/// Left navigation bar (56px): 10 sections + settings gear at the bottom.
class SideBar extends StatelessWidget {
  const SideBar({super.key, required this.active, required this.onSelect});

  final AppSection active;
  final ValueChanged<AppSection> onSelect;

  @override
  Widget build(BuildContext context) {
    SideBarItem item(AppSection s) => SideBarItem(
      key: ValueKey('nav-${s.name}'),
      section: s,
      active: s == active,
      onTap: () => onSelect(s),
    );
    return Container(
      width: 56,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          for (final s in AppSection.navItems) ...[
            item(s),
            const SizedBox(height: 4),
          ],
          const Spacer(),
          item(AppSection.settings),
        ],
      ),
    );
  }
}

class SideBarItem extends StatelessWidget {
  const SideBarItem({
    super.key,
    required this.section,
    required this.active,
    required this.onTap,
  });

  final AppSection section;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(8);
    return Tooltip(
      message: section.label,
      waitDuration: const Duration(milliseconds: 400),
      preferBelow: false,
      child: Semantics(
        button: true,
        selected: active,
        label: section.label,
        excludeSemantics: true,
        child: Material(
          color: active ? AppColors.amberTint : Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            hoverColor: active ? Colors.transparent : AppColors.surfaceRaised,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: AppIcon(
                  section.icon,
                  size: 20,
                  color: active ? AppColors.amber : AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
