import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import 'svg_path.dart';

/// A 24×24 stroke icon described by SVG path data (copied from the mockups).
@immutable
class AppIconData {
  AppIconData(List<String> paths, {this.strokeWidth = 1.8})
    : path = _combine(paths);

  /// Combined path in a 24×24 view box.
  final Path path;

  /// Stroke width in view-box units (as in the mockup `stroke-width`).
  final double strokeWidth;

  static Path _combine(List<String> paths) {
    final out = Path();
    for (final d in paths) {
      out.addPath(parseSvgPath(d), Offset.zero);
    }
    return out;
  }
}

/// Icons used by the shell. Paths copied verbatim from
/// docs/mockups/Main.dc.html (`viewBox="0 0 24 24"`).
abstract final class AppIcons {
  static final flask = AppIconData([
    'M9 3h6M10 3v6l-5 9a2 2 0 0 0 1.7 3h10.6a2 2 0 0 0 1.7-3l-5-9V3',
  ], strokeWidth: 2.2);

  static final chevronDown = AppIconData(['M6 9l6 6 6-6'], strokeWidth: 2);

  static final search = AppIconData([
    svgCircle(11, 11, 7),
    'M20 20l-3.5-3.5',
  ], strokeWidth: 2);

  static final plus = AppIconData(['M12 5v14M5 12h14'], strokeWidth: 2.4);

  static final sessions = AppIconData([
    svgRect(3, 4, 18, 16, 2),
    'M7 9l3 3-3 3M12 15h5',
  ]);

  static final prompt = AppIconData([
    'M21 12a8.5 8.5 0 0 1-12.4 7.6L3.5 21l1.4-4.6A8.5 8.5 0 1 1 21 12z',
    'M12 8l1 2.5 2.5 1-2.5 1-1 2.5-1-2.5-2.5-1 2.5-1z',
  ]);

  static final specs = AppIconData([
    'M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z',
    'M14 3v6h6M8 13h8M8 17h5',
  ]);

  static final tasks = AppIconData([
    svgRect(3, 4, 5, 16, 1),
    svgRect(10, 4, 5, 10, 1),
    svgRect(17, 4, 4, 13, 1),
  ]);

  static final agents = AppIconData([
    svgRect(4, 8, 16, 12, 3),
    'M12 4v4M9 13v1M15 13v1M9 17h6',
  ]);

  static final review = AppIconData([
    svgCircle(6, 5, 2),
    svgCircle(6, 19, 2),
    svgCircle(18, 12, 2),
    'M6 7v10M16 12h-3a5 5 0 0 1-5-5',
  ]);

  static final code = AppIconData(['M8 8l-4 4 4 4M16 8l4 4-4 4M14 5l-4 14']);

  static final mcp = AppIconData([
    'M9 3v5M15 3v5M7 8h10v3a5 5 0 0 1-10 0zM12 16v5',
  ]);

  /// Provider mark of the Prompt mockup (Claude Code).
  static final sparkle = AppIconData([
    'M12 4l1.8 4.6L18.5 10l-4.7 1.6L12 16.4l-1.8-4.8L5.5 10l4.7-1.4z',
  ], strokeWidth: 2);

  static final chevronUp = AppIconData(['M6 15l6-6 6 6'], strokeWidth: 2);

  static final check = AppIconData([
    'M5 12.5l4.5 4.5L19 7.5',
  ], strokeWidth: 2.2);

  static final close = AppIconData(['M6 6l12 12M18 6L6 18'], strokeWidth: 2);

  static final folder = AppIconData([
    'M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z',
  ]);

  static final settings = AppIconData([
    svgCircle(12, 12, 3),
    'M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9L7 7M17 17l2.1 2.1M4.9 19.1L7 17M17 7l2.1-2.1',
  ]);
}

/// Paints an [AppIconData] stroked with round caps and joins.
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size = 20,
    this.color,
    this.strokeWidth,
    this.semanticLabel,
  });

  final AppIconData icon;
  final double size;

  /// Defaults to the ambient [DefaultTextStyle] color (like `currentColor`).
  final Color? color;

  /// Overrides [AppIconData.strokeWidth].
  final double? strokeWidth;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c =
        color ?? DefaultTextStyle.of(context).style.color ?? AppColors.text;
    final painted = CustomPaint(
      size: Size.square(size),
      painter: _AppIconPainter(icon, c, strokeWidth ?? icon.strokeWidth),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: painted);
    return Semantics(label: semanticLabel, child: painted);
  }
}

class _AppIconPainter extends CustomPainter {
  _AppIconPainter(this.icon, this.color, this.strokeWidth);

  final AppIconData icon;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(
      icon.path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_AppIconPainter old) =>
      old.icon != icon || old.color != color || old.strokeWidth != strokeWidth;
}
