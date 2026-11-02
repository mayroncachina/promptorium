import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// SPEC-029 R1: the mark (the flask without the dark square) exists in every
/// size, has a transparent background and reaches 3:1 against a dark and a
/// light panel (average of the opaque pixels).
const _sizes = [16, 22, 24, 32, 48, 64, 128, 256, 512];

double _channel(double v) {
  final c = v / 255;
  return c <= 0.03928
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4) as double;
}

double _luminance(double r, double g, double b) =>
    0.2126 * _channel(r) + 0.7152 * _channel(g) + 0.0722 * _channel(b);

double _contrast(double a, double b) {
  final hi = math.max(a, b), lo = math.min(a, b);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('o SVG da marca e o desenho simplificado existem', () {
    expect(File('assets/icon/mark/mark.svg').existsSync(), isTrue);
    expect(File('assets/icon/mark/mark-small.svg').existsSync(), isTrue);
  });

  for (final n in _sizes) {
    test('mark-$n.png: $n×$n, cantos transparentes e contraste 3:1', () async {
      final file = File('assets/icon/mark/mark-$n.png');
      expect(file.existsSync(), isTrue, reason: file.path);
      final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
      final image = (await codec.getNextFrame()).image;
      expect(image.width, n);
      expect(image.height, n);
      final data = (await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      ))!;
      int alpha(int x, int y) => data.getUint8((y * n + x) * 4 + 3);
      for (final (x, y) in [(0, 0), (n - 1, 0), (0, n - 1), (n - 1, n - 1)]) {
        expect(alpha(x, y), 0, reason: 'canto ($x, $y) deve ser transparente');
      }
      var r = 0.0, g = 0.0, b = 0.0, count = 0;
      for (var i = 0; i < n * n; i++) {
        if (data.getUint8(i * 4 + 3) < 128) continue;
        r += data.getUint8(i * 4);
        g += data.getUint8(i * 4 + 1);
        b += data.getUint8(i * 4 + 2);
        count++;
      }
      expect(count, greaterThan(0));
      final l = _luminance(r / count, g / count, b / count);
      expect(
        _contrast(l, _luminance(0, 0, 0)),
        greaterThanOrEqualTo(3),
        reason: 'contra #000000',
      );
      expect(
        _contrast(l, _luminance(0xF6, 0xF6, 0xF6)),
        greaterThanOrEqualTo(3),
        reason: 'contra #F6F6F6',
      );
    });
  }
}
