import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/project/widgets/project_widgets.dart';
import 'package:promptorium/features/sessions/widgets/session_style.dart';
import 'package:promptorium/features/specs/prototype/prototype_view.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

// SPEC-075: SmallButton and AmberButton are as wide as their content unless
// `expand: true` (or a parent that imposes an exact width).

const btn = Key('btn');

Widget app(Widget child) => MaterialApp(
  theme: AppTheme.dark(),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 600, height: 400, child: child),
    ),
  ),
);

Widget small({bool expand = false, String label = 'Verificar agora'}) =>
    SmallButton(key: btn, label: label, onTap: () {}, expand: expand);

Widget amber({bool expand = false, bool busy = false}) => AmberButton(
  key: btn,
  label: 'Aprovar',
  onTap: () {},
  expand: expand,
  busy: busy,
);

double widthOf(WidgetTester t) => t.getSize(find.byKey(btn)).width;

/// Width of the button alone, in a Row (unbounded width).
Future<double> natural(WidgetTester t, Widget b) async {
  await t.pumpWidget(app(Row(children: [b])));
  return widthOf(t);
}

void main() {
  final loose = <String, Widget Function(Widget)>{
    'Column': (b) => Column(children: [b]),
    'Wrap': (b) => Wrap(children: [b]),
    'Align': (b) => Align(alignment: Alignment.centerLeft, child: b),
    'Center': (b) => Center(child: b),
    'Flexible': (b) => Row(children: [Flexible(child: b)]),
  };

  for (final MapEntry(key: parent, value: wrap) in loose.entries) {
    testWidgets('SmallButton has the width of its content in $parent [R1]', (
      t,
    ) async {
      final w = await natural(t, small());
      expect(w, lessThan(300));
      await t.pumpWidget(app(wrap(small())));
      expect(widthOf(t), w);
    });

    testWidgets('AmberButton has the width of its content in $parent [R3]', (
      t,
    ) async {
      final w = await natural(t, amber());
      expect(w, lessThan(300));
      await t.pumpWidget(app(wrap(amber())));
      expect(widthOf(t), w);
    });

    testWidgets('expand: true fills the width in $parent [R2]', (t) async {
      if (parent == 'Flexible') {
        // A Row needs Expanded (or a tight Flexible) to give a width.
        await t.pumpWidget(app(Row(children: [Expanded(child: small())])));
      } else {
        await t.pumpWidget(app(wrap(small(expand: true))));
      }
      expect(widthOf(t), 600);
      await t.pumpWidget(
        app(
          parent == 'Flexible'
              ? Row(children: [Expanded(child: amber())])
              : wrap(amber(expand: true)),
        ),
      );
      expect(widthOf(t), 600);
    });
  }

  testWidgets('the busy AmberButton keeps the content width [R3]', (t) async {
    final w = await natural(t, amber(busy: true));
    await t.pumpWidget(app(Column(children: [amber(busy: true)])));
    expect(widthOf(t), w);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('an exact width from the parent still wins [R4]', (t) async {
    await t.pumpWidget(
      app(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [small()],
        ),
      ),
    );
    expect(widthOf(t), 600);
    await t.pumpWidget(
      app(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 240, child: amber()),
        ),
      ),
    );
    expect(widthOf(t), 240);
    // The label stays centered.
    final button = t.getRect(find.byKey(btn));
    final label = t.getRect(find.text('Aprovar'));
    expect(label.center.dx, closeTo(button.center.dx, 0.5));
  });

  testWidgets('a long label shrinks with ellipsis when space is short [R1]', (
    t,
  ) async {
    await t.pumpWidget(
      app(
        UnconstrainedBox(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 120,
            child: Column(
              children: [small(label: 'Um rótulo bem comprido ' * 4)],
            ),
          ),
        ),
      ),
    );
    expect(widthOf(t), 120);
    expect(t.takeException(), isNull);
  });

  testWidgets('the label is vertically centered in the 30px box', (t) async {
    await t.pumpWidget(app(Column(children: [small()])));
    final button = t.getRect(find.byKey(btn));
    final label = t.getRect(find.text('Verificar agora'));
    expect(button.height, 30);
    expect(label.center.dy, closeTo(button.center.dy, 0.5));
    expect(label.center.dx, closeTo(button.center.dx, 0.5));
  });

  testWidgets('ChipButton and ProtoButton keep their width in a Wrap [R3]', (
    t,
  ) async {
    for (final b in <Widget>[
      ChipButton(key: btn, label: 'Flutter', onTap: () {}),
      ProtoButton(key: btn, label: 'tela.html', onTap: () {}),
    ]) {
      final w = await natural(t, b);
      expect(w, lessThan(300));
      await t.pumpWidget(app(Wrap(children: [b])));
      expect(widthOf(t), w);
      await t.pumpWidget(app(Column(children: [b])));
      expect(widthOf(t), w);
    }
  });
}
