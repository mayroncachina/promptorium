import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/text/line_diff.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:promptorium/ui/theme/tokens.dart';
import 'package:promptorium/ui/widgets/diff_view.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1100, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    ),
  );
}

/// WCAG contrast ratio of two opaque colors.
double _contrast(Color a, Color b) {
  double lum(Color c) {
    double ch(double v) => v <= 0.03928
        ? v / 12.92
        : ((v + 0.055) / 1.055) * ((v + 0.055) / 1.055);
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  final x = lum(a), y = lum(b);
  return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
}

void main() {
  testWidgets('a 1.000-line diff shows 400 and "Mostrar as outras 600 '
      'linhas", built lazily, and the list still scrolls (SPEC-026 R10)', (
    tester,
  ) async {
    final rows = [
      for (var i = 0; i < 1000; i++)
        (op: DiffOp.add, text: 'linha $i', line: i + 1),
    ];
    await _pump(tester, DiffView(rows: rows, scrollable: true));
    expect(find.text('Mostrar as outras 600 linhas'), findsNothing);
    // Lazy: only what fits is built.
    expect(find.text('linha 0'), findsOneWidget);
    expect(find.text('linha 399'), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('diff-show-more')),
      2000,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Mostrar as outras 600 linhas'), findsOneWidget);
    expect(find.text('linha 399'), findsOneWidget);
    expect(find.text('linha 400'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('diff-show-more')));
    await tester.pump();
    expect(find.byKey(const ValueKey('diff-show-more')), findsNothing);
    await tester.scrollUntilVisible(
      find.text('linha 999'),
      2000,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('linha 999'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('each line has its sign, its position and an accessible label; '
      'the sign column is ruled off (R9)', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      const DiffView(
        rows: [
          (op: DiffOp.same, text: '## Requisitos', line: 14),
          (op: DiffOp.del, text: '- R3 · velho', line: 15),
          (op: DiffOp.add, text: '- R3 · novo', line: 15),
        ],
      ),
    );
    expect(find.text('-'), findsOneWidget);
    expect(find.text('+'), findsOneWidget);
    expect(find.text('15'), findsNWidgets(2));
    expect(
      find.bySemanticsLabel('linha removida, linha 15: - R3 · velho'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('linha adicionada, linha 15: - R3 · novo'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('sem mudança, linha 14: ## Requisitos'),
      findsOneWidget,
    );
    final rule = tester.widget<Container>(
      find.ancestor(of: find.text('+'), matching: find.byType(Container)).first,
    );
    final border = (rule.decoration! as BoxDecoration).border! as Border;
    expect(border.right.color, AppColors.border);
    // Text contrast over the add / remove backgrounds.
    expect(_contrast(AppColors.text, SessionColors.addBg), greaterThan(4.5));
    expect(_contrast(AppColors.text, SessionColors.delBg), greaterThan(4.5));
    handle.dispose();
  });

  testWidgets('unchanged runs longer than 3 lines fold into "N linhas sem '
      'mudança" with "Mostrar" (R7)', (tester) async {
    await _pump(
      tester,
      DiffView(
        collapseSame: 3,
        rows: [
          (op: DiffOp.del, text: 'a', line: 1),
          for (var i = 0; i < 8; i++)
            (op: DiffOp.same, text: 'igual $i', line: i + 2),
          (op: DiffOp.add, text: 'b', line: 10),
          (op: DiffOp.same, text: 'x', line: 11),
          (op: DiffOp.same, text: 'y', line: 12),
        ],
      ),
    );
    expect(find.text('± 6 linhas sem mudança'), findsOneWidget);
    expect(find.text('igual 0'), findsOneWidget);
    expect(find.text('igual 3'), findsNothing);
    expect(find.text('igual 7'), findsOneWidget);
    // A run of 2 stays open.
    expect(find.text('y'), findsOneWidget);
    await tester.tap(find.text('Mostrar'));
    await tester.pump();
    expect(find.text('igual 3'), findsOneWidget);
    expect(find.textContaining('sem mudança'), findsNothing);
  });

  testWidgets('muted (denied edit): no background, grey signs (R4)', (
    tester,
  ) async {
    await _pump(
      tester,
      const DiffView(
        muted: true,
        rows: [
          (op: DiffOp.del, text: 'velho', line: 1),
          (op: DiffOp.add, text: 'novo', line: 1),
        ],
      ),
    );
    for (final sign in ['+', '-']) {
      final t = tester.widget<Text>(find.text(sign));
      expect(t.style!.color, AppColors.textDisabled);
    }
    final colored = tester
        .widgetList<Container>(find.byType(Container))
        .where(
          (c) =>
              c.color == SessionColors.addBg || c.color == SessionColors.delBg,
        );
    expect(colored, isEmpty);
  });
}
