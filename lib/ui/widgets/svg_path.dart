import 'dart:ui';

/// Minimal SVG path-data parser (`d` attribute) for the shapes copied from
/// docs/mockups/*.dc.html.
///
/// Supports M, L, H, V, C, S, Q, T, A, Z (absolute and relative) and implicit
/// command repetition. Anything else throws a [FormatException].
Path parseSvgPath(String d) {
  final t = _Tokenizer(d);
  final path = Path();
  var cx = 0.0, cy = 0.0; // current point
  var sx = 0.0, sy = 0.0; // start of current subpath
  Offset? lastQuadCtrl;
  Offset? lastCubicCtrl;
  String? cmd;

  while (true) {
    t.skipSeparators();
    if (t.atEnd) break;
    if (t.peekIsCommand) {
      cmd = t.readCommand();
    } else if (cmd == null) {
      throw FormatException('Path must start with a command', d, t.pos);
    }
    final c = cmd;
    final rel = c == c.toLowerCase();
    final ox = rel ? cx : 0.0, oy = rel ? cy : 0.0;
    Offset? quadCtrl;
    Offset? cubicCtrl;

    switch (c.toUpperCase()) {
      case 'M':
        cx = t.number() + ox;
        cy = t.number() + oy;
        path.moveTo(cx, cy);
        sx = cx;
        sy = cy;
        // Subsequent coordinate pairs are implicit line-tos.
        cmd = rel ? 'l' : 'L';
      case 'L':
        cx = t.number() + ox;
        cy = t.number() + oy;
        path.lineTo(cx, cy);
      case 'H':
        cx = t.number() + ox;
        path.lineTo(cx, cy);
      case 'V':
        cy = t.number() + oy;
        path.lineTo(cx, cy);
      case 'C':
        final x1 = t.number() + ox, y1 = t.number() + oy;
        final x2 = t.number() + ox, y2 = t.number() + oy;
        cx = t.number() + ox;
        cy = t.number() + oy;
        path.cubicTo(x1, y1, x2, y2, cx, cy);
        cubicCtrl = Offset(x2, y2);
      case 'S':
        final r = lastCubicCtrl;
        final x1 = r == null ? cx : 2 * cx - r.dx;
        final y1 = r == null ? cy : 2 * cy - r.dy;
        final x2 = t.number() + ox, y2 = t.number() + oy;
        cx = t.number() + ox;
        cy = t.number() + oy;
        path.cubicTo(x1, y1, x2, y2, cx, cy);
        cubicCtrl = Offset(x2, y2);
      case 'Q':
        final x1 = t.number() + ox, y1 = t.number() + oy;
        cx = t.number() + ox;
        cy = t.number() + oy;
        path.quadraticBezierTo(x1, y1, cx, cy);
        quadCtrl = Offset(x1, y1);
      case 'T':
        final r = lastQuadCtrl;
        final x1 = r == null ? cx : 2 * cx - r.dx;
        final y1 = r == null ? cy : 2 * cy - r.dy;
        cx = t.number() + ox;
        cy = t.number() + oy;
        path.quadraticBezierTo(x1, y1, cx, cy);
        quadCtrl = Offset(x1, y1);
      case 'A':
        final rx = t.number(), ry = t.number(), rot = t.number();
        final large = t.flag(), sweep = t.flag();
        cx = t.number() + ox;
        cy = t.number() + oy;
        path.arcToPoint(
          Offset(cx, cy),
          radius: Radius.elliptical(rx.abs(), ry.abs()),
          rotation: rot,
          largeArc: large,
          // SVG and Flutter both use a y-down space: sweep=1 is clockwise.
          clockwise: sweep,
        );
      case 'Z':
        path.close();
        cx = sx;
        cy = sy;
        cmd = null; // Z takes no arguments; a command must follow.
      default:
        throw FormatException('Unsupported path command "$c"', d, t.pos);
    }
    lastQuadCtrl = quadCtrl;
    lastCubicCtrl = cubicCtrl;
  }
  return path;
}

/// `<circle>` as path data.
String svgCircle(double cx, double cy, double r) =>
    'M${cx - r} $cy A$r $r 0 1 0 ${cx + r} $cy A$r $r 0 1 0 ${cx - r} $cy Z';

/// `<rect>` (optionally rounded) as path data.
String svgRect(double x, double y, double w, double h, [double rx = 0]) {
  if (rx <= 0) return 'M$x $y H${x + w} V${y + h} H$x Z';
  final r = rx;
  return 'M${x + r} $y H${x + w - r} A$r $r 0 0 1 ${x + w} ${y + r} '
      'V${y + h - r} A$r $r 0 0 1 ${x + w - r} ${y + h} '
      'H${x + r} A$r $r 0 0 1 $x ${y + h - r} '
      'V${y + r} A$r $r 0 0 1 ${x + r} $y Z';
}

/// `<line>` as path data.
String svgLine(double x1, double y1, double x2, double y2) =>
    'M$x1 $y1 L$x2 $y2';

class _Tokenizer {
  _Tokenizer(this.src);

  final String src;
  int pos = 0;

  static final _number = RegExp(r'[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?');
  static const _commands = 'MmLlHhVvCcSsQqTtAaZz';

  bool get atEnd => pos >= src.length;

  bool get peekIsCommand => !atEnd && _commands.contains(src[pos]);

  void skipSeparators() {
    while (!atEnd) {
      final ch = src.codeUnitAt(pos);
      // space, tab, CR, LF, comma
      if (ch == 0x20 || ch == 0x09 || ch == 0x0D || ch == 0x0A || ch == 0x2C) {
        pos++;
      } else {
        break;
      }
    }
  }

  String readCommand() => src[pos++];

  double number() {
    skipSeparators();
    final m = _number.matchAsPrefix(src, pos);
    if (m == null) throw FormatException('Expected number', src, pos);
    pos = m.end;
    return double.parse(m.group(0)!);
  }

  bool flag() {
    skipSeparators();
    if (atEnd) throw FormatException('Expected flag', src, pos);
    final ch = src[pos++];
    if (ch == '0') return false;
    if (ch == '1') return true;
    throw FormatException('Expected 0 or 1 flag', src, pos - 1);
  }
}
