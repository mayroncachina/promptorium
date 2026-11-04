import 'package:flutter/widgets.dart';

import '../theme/motion.dart';
import '../widgets/motion_enter.dart';
import 'navigation.dart';

/// Enters [child] with a fade and 8 px in [AppMotion.section] when the sidebar
/// item changes (SPEC-034 R2): from below when the new item is under the old
/// one, from above otherwise.
///
/// Only the entrance is animated. The old screen leaves at once, because two
/// mounted screens would duplicate providers, focus and keys (D1). The tabs of
/// "Ferramentas" share one item, so they swap without an entrance.
class SectionTransition extends StatefulWidget {
  const SectionTransition({
    super.key,
    required this.section,
    required this.child,
  });

  final AppSection section;

  /// The screen, with a key of its own so a new section remounts it.
  final Widget child;

  @override
  State<SectionTransition> createState() => _SectionTransitionState();
}

class _SectionTransitionState extends State<SectionTransition> {
  /// Zero until the first change: the app opens on its screen, no entrance.
  var _dy = 0.0;

  @override
  void didUpdateWidget(SectionTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    final from = oldWidget.section.navIndex;
    final to = widget.section.navIndex;
    if (to != from) _dy = to > from ? 8 : -8;
  }

  @override
  Widget build(BuildContext context) => MotionEnter(
    // A new item restarts the entrance, even in the middle of one (R12).
    key: ValueKey(widget.section.navIndex),
    duration: AppMotion.section,
    dy: _dy,
    animate: _dy != 0,
    // The screen is painted once and moved as a layer (R13).
    child: RepaintBoundary(child: widget.child),
  );
}
