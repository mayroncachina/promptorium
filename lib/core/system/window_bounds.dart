import 'dart:math' as math;
import 'dart:ui';

/// The window size the app is designed for (SPEC-114 R2).
const idealWindowSize = Size(1440, 900);

/// The smallest size the layouts assume, e.g. the Quadro at 1100 px (R3).
const preferredMinimumWindowSize = Size(1100, 700);

/// Share of the screen's usable area the first window takes at most (R2).
const _screenShare = 0.9;

/// Size, minimum and position of the first window (SPEC-114).
class WindowBounds {
  const WindowBounds({
    required this.size,
    required this.minimumSize,
    this.position,
  });

  final Size size;
  final Size minimumSize;

  /// Top-left corner, centred on the usable area; `null` means "let
  /// window_manager centre it" (no screen information, R6).
  final Offset? position;
}

/// Bounds of the first window for a screen whose usable area (without the
/// taskbar) is [visible] at [origin], in logical pixels.
///
/// Without a usable area the result is the fixed size of before (R6).
WindowBounds initialWindowBounds(Size? visible, Offset? origin) {
  if (visible == null || visible.width <= 0 || visible.height <= 0) {
    return const WindowBounds(
      size: idealWindowSize,
      minimumSize: preferredMinimumWindowSize,
    );
  }
  final size = Size(
    math
        .min(idealWindowSize.width, visible.width * _screenShare)
        .floorToDouble(),
    math
        .min(idealWindowSize.height, visible.height * _screenShare)
        .floorToDouble(),
  );
  final minimumSize = Size(
    math.min(preferredMinimumWindowSize.width, size.width),
    math.min(preferredMinimumWindowSize.height, size.height),
  );
  final o = origin ?? Offset.zero;
  final position = Offset(
    (o.dx + (visible.width - size.width) / 2).roundToDouble(),
    (o.dy + (visible.height - size.height) / 2).roundToDouble(),
  );
  return WindowBounds(size: size, minimumSize: minimumSize, position: position);
}
