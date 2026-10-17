import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/home/home_inbox.dart' show navBadgesProvider;
import '../theme/tokens.dart';
import '../widgets/app_icon.dart';
import 'navigation.dart';

/// Left navigation bar (56px): the [AppSection.navItems] + settings gear at
/// the bottom. An amber counter on an item is what waits for the user there
/// (UX v2: [navBadgesProvider]).
class SideBar extends ConsumerWidget {
  const SideBar({super.key, required this.active, required this.onSelect});

  final AppSection active;
  final ValueChanged<AppSection> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badges = ref.watch(navBadgesProvider);
    SideBarItem item(AppSection s) => SideBarItem(
      key: ValueKey('nav-${s.name}'),
      section: s,
      // "Ferramentas" stays lit on any of its tabs.
      active: s == active || (s == AppSection.agents && active.isTool),
      badge: badges[s] ?? 0,
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
    this.badge = 0,
  });

  final AppSection section;
  final bool active;
  final VoidCallback onTap;

  /// Pending items shown as a counter (0 = none).
  final int badge;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(8);
    final label = badge > 0
        ? '${section.navLabel} · $badge ${badge == 1 ? 'pendente' : 'pendentes'}'
        : section.navLabel;
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 400),
      preferBelow: false,
      child: Semantics(
        button: true,
        selected: active,
        label: label,
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
              child: Stack(
                children: [
                  Center(
                    child: AppIcon(
                      section.icon,
                      size: 20,
                      color: active ? AppColors.amber : AppColors.textSecondary,
                    ),
                  ),
                  if (badge > 0)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        key: ValueKey('nav-badge-${section.name}'),
                        constraints: const BoxConstraints(minWidth: 16),
                        height: 16,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.amber,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          badge > 99 ? '99+' : '$badge',
                          style: const TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.onAmber,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
