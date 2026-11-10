import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/home/home_inbox.dart' show navBadgesProvider;
import '../theme/motion.dart';
import '../theme/tokens.dart';
import '../widgets/app_icon.dart';
import 'navigation.dart';

const _itemSize = 44.0;

/// Gap below every item.
const _gap = 4.0;

/// The featured item (the Prompt, SPEC-055 R2): 48 × 58.
const _featuredSize = Size(48, 58);

/// A 1px separator around the featured item and the gap below it.
const _separator = 1 + _gap;

Size _sizeOf(AppSection s) =>
    s.featured ? _featuredSize : const Size.square(_itemSize);

/// Top of each of the [AppSection.navItems] in the column, and where the
/// items end (with the gap of the last one). Built from the real heights, so
/// the highlight follows the bigger featured item (SPEC-055 R8).
final _navLayout = () {
  final tops = <double>[];
  var y = 0.0;
  for (final s in AppSection.navItems) {
    if (s.featured) y += _separator;
    tops.add(y);
    y += _sizeOf(s).height + _gap;
    if (s.featured) y += _separator;
  }
  return (tops: tops, end: y);
}();

/// Left navigation bar (56px): the [AppSection.navItems] + settings gear at
/// the bottom. An amber counter on an item is what waits for the user there
/// (UX v2: [navBadgesProvider]). The active item is lit by one highlight that
/// slides between the items (SPEC-034 R3). The Prompt is the featured item,
/// bigger and with its name, between two separators (SPEC-055).
class SideBar extends ConsumerWidget {
  const SideBar({super.key, required this.active, required this.onSelect});

  final AppSection active;
  final ValueChanged<AppSection> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badges = ref.watch(navBadgesProvider);
    Widget item(AppSection s) => s.featured
        ? SideBarFeaturedItem(
            key: ValueKey('nav-${s.name}'),
            section: s,
            active: s == active.navItem,
            badge: badges[s] ?? 0,
            onTap: () => onSelect(s),
          )
        : SideBarItem(
            key: ValueKey('nav-${s.name}'),
            section: s,
            // "Ferramentas" stays lit on any of its tabs.
            active: s == active.navItem,
            badge: badges[s] ?? 0,
            onTap: () => onSelect(s),
          );
    return Container(
      width: 56,
      padding: const EdgeInsets.symmetric(vertical: 8),
      // The highlight repaints the bar, not the shell, while it slides.
      child: RepaintBoundary(
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Positioned.fill(child: _Highlight(active: active.navItem)),
            Column(
              children: [
                for (final s in AppSection.navItems) ...[
                  if (s.featured) const _Separator(),
                  item(s),
                  const SizedBox(height: _gap),
                  if (s.featured) const _Separator(),
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

/// 28 × 1 line around the featured item (SPEC-055 R1).
class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: _gap),
    child: Container(
      key: const ValueKey('nav-separator'),
      width: 28,
      height: 1,
      color: Colors.white.withValues(alpha: .1),
    ),
  );
}

/// The background of the active item, the same element for every item. It
/// moves by transform, and a new target starts from where it is (R12). On the
/// featured item it grows to its size (SPEC-055 R8).
class _Highlight extends StatefulWidget {
  const _Highlight({required this.active});

  /// [AppSection.navItem] of the active screen.
  final AppSection active;

  @override
  State<_Highlight> createState() => _HighlightState();
}

class _HighlightState extends State<_Highlight> {
  late var _active = widget.active;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      // Only a new item slides: resizing the window moves the gear, and the
      // highlight on it has to stay with it.
      final slide = widget.active != _active;
      _active = widget.active;
      final i = AppSection.navItems.indexOf(widget.active);
      // The gear sits at the bottom, or right after the items if space is out.
      final top = i >= 0
          ? _navLayout.tops[i]
          : math.max(_navLayout.end, box.maxHeight - _itemSize);
      final size = _sizeOf(widget.active);
      return Align(
        alignment: Alignment.topCenter,
        child: TweenAnimationBuilder<Rect?>(
          tween: RectTween(end: Offset(0, top) & size),
          duration: slide
              ? AppMotion.duration(context, AppMotion.section)
              : Duration.zero,
          curve: AppMotion.enter,
          builder: (context, rect, _) {
            final r = rect!;
            // 10 on a plain item, 13 on the featured one.
            final grow =
                ((r.height - _itemSize) / (_featuredSize.height - _itemSize))
                    .clamp(0.0, 1.0);
            return Transform.translate(
              offset: Offset(0, r.top),
              child: DecoratedBox(
                key: const ValueKey('nav-highlight'),
                // Lit in amber: the active item is live state (SPEC-049 R4).
                decoration: BoxDecoration(
                  color: AppColors.amberTint,
                  borderRadius: BorderRadius.circular(10 + 3 * grow),
                  border: Border.all(
                    color: AppColors.amber.withValues(alpha: .4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.amber.withValues(
                        alpha: .18 + .17 * grow,
                      ),
                      blurRadius: 16 + 6 * grow,
                    ),
                  ],
                ),
                child: SizedBox(width: r.width, height: r.height),
              ),
            );
          },
        ),
      );
    },
  );
}

/// The Prompt in the sidebar (SPEC-055 R2, R3): 48 × 58, the icon at 24 and
/// its name below, on an amber→teal glass even at rest. The only item with a
/// label: it stands out by size, name and background, not by colour alone.
class SideBarFeaturedItem extends StatefulWidget {
  const SideBarFeaturedItem({
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
  State<SideBarFeaturedItem> createState() => _SideBarFeaturedItemState();
}

class _SideBarFeaturedItemState extends State<SideBarFeaturedItem> {
  var _hovered = false;
  var _pressed = false;
  var _focused = false;

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final active = widget.active;
    final badge = widget.badge;
    final radius = BorderRadius.circular(13);
    final label = badge > 0
        ? '${section.navLabel} · $badge ${badge == 1 ? 'pendente' : 'pendentes'}'
        : section.navLabel;
    final hovered = _hovered && !active;
    final hover = AppMotion.duration(
      context,
      _hovered ? AppMotion.quick : AppMotion.quickExit,
    );
    final hoverCurve = _hovered ? AppMotion.enter : AppMotion.exit;
    // Rest, hover and active backgrounds of the mockup (Trilho.dc.html).
    final (from, to, border) = active
        ? (
            AppColors.amber.withValues(alpha: .34),
            AppColors.amber.withValues(alpha: .16),
            AppColors.amber.withValues(alpha: .7),
          )
        : hovered
        ? (
            AppColors.amber.withValues(alpha: .28),
            AppColors.teal.withValues(alpha: .14),
            AppColors.amber.withValues(alpha: .5),
          )
        : (
            AppColors.amber.withValues(alpha: .20),
            AppColors.teal.withValues(alpha: .10),
            AppColors.amber.withValues(alpha: .32),
          );
    final ring =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
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
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: hover,
                curve: hoverCurve,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: const Alignment(-.35, -1),
                    end: const Alignment(.35, 1),
                    colors: [from, to],
                  ),
                  borderRadius: radius,
                  border: Border.all(color: border),
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: radius,
                  child: InkWell(
                    onTap: widget.onTap,
                    onHover: (v) => setState(() => _hovered = v),
                    onHighlightChanged: (v) => setState(() => _pressed = v),
                    onFocusChange: (v) => setState(() => _focused = v),
                    borderRadius: radius,
                    hoverColor: Colors.transparent,
                    focusColor: Colors.transparent,
                    child: SizedBox.fromSize(
                      // The 1px border is outside: 48 × 58 in all.
                      size: const Size(46, 56),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AppIcon(
                            section.icon,
                            size: 24,
                            color: active
                                ? AppColors.amberLight
                                : AppColors.amber,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            section.navLabel,
                            key: const ValueKey('nav-featured-label'),
                            maxLines: 1,
                            style: TextStyle(
                              fontFamily: AppFonts.sans,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: .1,
                              height: 1.2,
                              color: active
                                  ? AppColors.amberLight
                                  : AppColors.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Keyboard focus: a 2px ring 3px away (R3), at once.
              if (ring)
                Positioned(
                  left: -5,
                  top: -5,
                  right: -5,
                  bottom: -5,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      key: const ValueKey('nav-featured-focus'),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppColors.amberLight,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              if (badge > 0)
                Positioned(
                  top: -3,
                  right: -3,
                  child: _Badge(section: section, count: badge),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The amber counter of what waits for the user on a screen.
class _Badge extends StatelessWidget {
  const _Badge({required this.section, required this.count});

  final AppSection section;
  final int count;

  @override
  Widget build(BuildContext context) => Container(
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
      count > 99 ? '99+' : '$count',
      style: const TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: AppColors.onAmber,
        height: 1,
      ),
    ),
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
                          child: _Badge(section: section, count: badge),
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
