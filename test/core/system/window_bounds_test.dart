import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/system/window_bounds.dart';

void main() {
  group('initialWindowBounds (SPEC-114)', () {
    test('1920×1080 at 100%: same 1440×900 as before, centred', () {
      final b = initialWindowBounds(const Size(1920, 1040), Offset.zero);
      expect(b.size, const Size(1440, 900));
      expect(b.minimumSize, const Size(1100, 700));
      expect(b.position, const Offset(240, 70));
    });

    test('1366×768: fits in 90% of the usable area', () {
      final b = initialWindowBounds(const Size(1366, 728), Offset.zero);
      expect(b.size, const Size(1229, 655));
      expect(b.size.height, lessThan(728));
      expect(b.minimumSize, const Size(1100, 655));
      expect(b.position, const Offset(69, 37));
    });

    test(
      '1080p at 150% (1280×688 logical): minimum never exceeds the screen',
      () {
        final b = initialWindowBounds(const Size(1280, 688), Offset.zero);
        expect(b.size, const Size(1152, 619));
        expect(b.minimumSize.width, lessThanOrEqualTo(1280));
        expect(b.minimumSize.height, lessThanOrEqualTo(688));
        expect(b.minimumSize, const Size(1100, 619));
      },
    );

    test('very small screen: minimum follows the size', () {
      final b = initialWindowBounds(const Size(1000, 600), Offset.zero);
      expect(b.size, const Size(900, 540));
      expect(b.minimumSize, const Size(900, 540));
    });

    test('taskbar on the left or on top shifts the position', () {
      final left = initialWindowBounds(
        const Size(1860, 1080),
        const Offset(60, 0),
      );
      expect(left.position, const Offset(270, 90));
      final top = initialWindowBounds(
        const Size(1920, 1040),
        const Offset(0, 40),
      );
      expect(top.position, const Offset(240, 110));
    });

    test('second monitor origin is kept', () {
      final b = initialWindowBounds(
        const Size(1920, 1040),
        const Offset(1920, 0),
      );
      expect(b.position, const Offset(2160, 70));
    });

    test('no usable area: values of before, no position', () {
      for (final visible in [null, Size.zero]) {
        final b = initialWindowBounds(visible, null);
        expect(b.size, idealWindowSize);
        expect(b.minimumSize, preferredMinimumWindowSize);
        expect(b.position, isNull);
      }
    });
  });
}
