import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/home/home_inbox.dart' show navBadgesProvider;
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../widgets/app_icon.dart';
import 'navigation.dart';

const _itemSize = 44.0;

/// One item and the gap below it.
const _itemStride = _itemSize + 4;

/// Left navigation bar (56px): the [AppSection.navItems] + settings gear at
/// the bottom. An amber counter on an item is what waits for the user there
/// (UX v2: [navBadgesProvider]). The active item is lit by one highlight that
/// slides between the items (SPEC-034 R3).
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
      active: s == active.navItem,
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
      // The highlight repaints the bar, not the shell, while it slides.
      child: RepaintBoundary(
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Positioned.fill(child: _Highlight(index: active.navIndex)),
            Column(
              children: [
                for (final s in AppSection.navItems) ...[
                  item(s),
                  const SizedBox(height: 4),
                ],
                const Spacer(),
                item(AppSection.settings),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The background of the active item, the same element for every item. It
/// moves by transform only, and a new target starts from where it is (R12).
class _Highlight extends StatefulWidget {
  const _Highlight({required this.index});

  /// [AppSection.navIndex] of the active item.
  final int index;

  @override
  State<_Highlight> createState() => _HighlightState();
}

class _HighlightState extends State<_Highlight> {
  late var _index = widget.index;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      // Only a new item slides: resizing the window moves the gear, and the
      // highlight on it has to stay with it.
      final slide = widget.index != _index;
      _index = widget.index;
      final items = AppSection.navItems.length;
      // The gear sits at the bottom, or right after the items if space is out.
      final top = widget.index < items
          ? widget.index * _itemStride
          : math.max(items * _itemStride, box.maxHeight - _itemSize);
      return Align(
        alignment: Alignment.topCenter,
        child: AnimatedSlide(
          offset: Offset(0, top / _itemSize),
          duration: slide
              ? AppMotion.duration(context, AppMotion.section)
              : Duration.zero,
          curve: AppMotion.enter,
          child: DecoratedBox(
            key: const ValueKey('nav-highlight'),
            decoration: BoxDecoration(
              color: AppColors.amberTint,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const SizedBox.square(dimension: _itemSize),
          ),
        ),
      );
    },
  );
}

class SideBarItem extends StatefulWidget {
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
  State<SideBarItem> createState() => _SideBarItemState();
}

class _SideBarItemState extends State<SideBarItem> {
  var _hovered = false;
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final active = widget.active;
    final badge = widget.badge;
    final radius = BorderRadius.circular(8);
    final label = badge > 0
        ? '${section.navLabel} · $badge ${badge == 1 ? 'pendente' : 'pendentes'}'
        : section.navLabel;
    final hovered = _hovered && !active;
    final hover = AppMotion.duration(
      context,
      hovered ? AppMotion.quick : AppMotion.quickExit,
    );
    final hoverCurve = hovered ? AppMotion.enter : AppMotion.exit;
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 400),
      preferBelow: false,
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        excludeSemantics: true,
        child: AnimatedScale(
          scale: _pressed ? .98 : 1,
          duration: AppMotion.duration(
            context,
            _pressed ? AppMotion.quick : AppMotion.quickExit,
          ),
          curve: _pressed ? AppMotion.enter : AppMotion.exit,
          // The hover background is not the InkWell's: its hoverDuration also
          // delays the focus ring, which has to show at once (R6).
          child: AnimatedContainer(
            duration: hover,
            curve: hoverCurve,
            decoration: BoxDecoration(
              color: hovered ? AppColors.surfaceRaised : Colors.transparent,
              borderRadius: radius,
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: radius,
              child: InkWell(
                onTap: widget.onTap,
                onHover: (v) => setState(() => _hovered = v),
                onHighlightChanged: (v) => setState(() => _pressed = v),
                borderRadius: radius,
                hoverColor: Colors.transparent,
                child: SizedBox(
                  width: _itemSize,
                  height: _itemSize,
                  child: Stack(
                    children: [
                      Center(
                        child: TweenAnimationBuilder<Color?>(
                          tween: ColorTween(
                            end: active
                                ? AppColors.amber
                                : hovered
                                ? AppColors.text
                                : AppColors.textSecondary,
                          ),
                          duration: hover,
                          curve: hoverCurve,
                          builder: (context, color, _) =>
                              AppIcon(section.icon, size: 20, color: color),
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
        ),
      ),
    );
  }
}
