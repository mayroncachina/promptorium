import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/ui/widgets/app_icon.dart';
import 'package:promptorium/ui/widgets/svg_path.dart';

void main() {
  test('parses absolute and relative commands', () {
    final p = parseSvgPath('M9 3h6M10 3v6l-5 9a2 2 0 0 0 1.7 3h10.6Z');
    final b = p.getBounds();
    expect(b.left, lessThan(5)); // arc bulges left of x=5
    expect(b.top, 3);
    expect(b.right, closeTo(17.3, 0.01)); // 6.7 + h10.6
  });

  test('smooth quadratic T reflects the previous control point', () {
    final p = parseSvgPath('M0 124 Q15 118 30 124 T60 124');
    final b = p.getBounds();
    expect(b.right, 60);
    expect(b.bottom, greaterThan(126)); // second hump goes below 124
  });

  test('rejects unsupported commands', () {
    expect(() => parseSvgPath('M0 0 X1 1'), throwsFormatException);
  });

  test('all shell icons parse within the 24×24 box', () {
    for (final icon in [
      AppIcons.sessions,
      AppIcons.prompt,
      AppIcons.specs,
      AppIcons.tasks,
      AppIcons.agents,
      AppIcons.review,
      AppIcons.code,
      AppIcons.mcp,
      AppIcons.settings,
      AppIcons.flask,
    ]) {
      final b = icon.path.getBounds();
      expect(b.left, greaterThanOrEqualTo(0));
      expect(b.right, lessThanOrEqualTo(24));
    }
  });
}
