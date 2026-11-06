import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/enums.dart';
import 'package:promptorium/features/specs/widgets/spec_header.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:promptorium/ui/theme/tokens.dart';
import 'package:promptorium/ui/widgets/zoom_control.dart';

void _noop() {}

/// Width of the header column in a 1100×700 window: 1100 − 56 (rail) − 220
/// (spec list) − 280 (side panel).
const narrow = 544.0;

Future<void> loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      final bytes = File('assets/fonts/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await family(AppFonts.sans, [
    'IBMPlexSans-Regular.ttf',
    'IBMPlexSans-Medium.ttf',
    'IBMPlexSans-SemiBold.ttf',
  ]);
  await family(AppFonts.mono, ['JetBrainsMono-Regular.ttf']);
  await family('MaterialIcons', []);
}

const draft = SpecHeaderState(
  hasPlan: true,
  onRefine: _noop,
  onDesign: _noop,
  onApprove: _noop,
  onDelete: _noop,
);

Future<void> pumpHeader(
  WidgetTester tester, {
  SpecHeaderState? actions = draft,
  SpecStatus status = SpecStatus.draft,
  bool locked = false,
  bool dirty = false,
  double width = 1100,
  SpecViewMode mode = SpecViewMode.split,
  ValueChanged<SpecViewMode>? onMode,
}) async {
  tester.view.physicalSize = Size(width, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: SpecHeader(
                path: 'docs/specs/SPEC-024-acoes-da-spec-mais-claras.md',
                title: 'Ações da spec mais claras',
                status: status,
                locked: locked,
                actions: actions,
                mode: mode,
                onMode: onMode ?? (_) {},
                showSaveState: true,
                dirty: dirty,
                onSave: locked ? null : _noop,
                zoom: const ZoomControl(editorKey: 'specs'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder key(String k) => find.byKey(ValueKey(k));

/// Key of the closest keyed ancestor of the focused widget.
String? focusedKey() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return null;
  String? found;
  bool visit(Element e) {
    final w = e.widget;
    if (w is Tooltip && (w.message ?? '').contains('zoom')) {
      found = 'zoom';
      return false;
    }
    final k = w.key;
    if (k is ValueKey<String> &&
        (k.value.startsWith('spec-') ||
            k.value.startsWith('proto-') ||
            k.value.startsWith('zoom'))) {
      found = k.value;
      return false;
    }
    return true;
  }

  if (visit(ctx as Element)) ctx.visitAncestorElements(visit);
  return found;
}

void main() {
  setUpAll(loadFonts);

  testWidgets('R1: identity and actions on the first line; tabs, save state '
      'and zoom on the second', (tester) async {
    await pumpHeader(tester);
    for (final k in [
      'spec-path',
      'spec-title',
      'spec-status',
      'spec-actions',
      'spec-mode-edit',
      'spec-saved',
      'zoom-specs',
    ]) {
      expect(key(k), findsOneWidget, reason: k);
    }
    final firstLine = tester.getRect(key('spec-actions'));
    final tabs = tester.getRect(key('spec-mode-edit'));
    expect(tester.getRect(key('spec-title')).bottom, lessThan(tabs.top));
    expect(tester.getRect(key('spec-status')).bottom, lessThan(tabs.top));
    expect(firstLine.bottom, lessThan(tabs.top));
    expect(
      firstLine.right,
      greaterThan(tester.getRect(key('spec-title')).right),
    );
    final saved = tester.getRect(key('spec-saved'));
    final zoom = tester.getRect(key('zoom-specs'));
    expect(saved.top, greaterThan(firstLine.bottom));
    expect(zoom.top, greaterThan(firstLine.bottom));
    expect(saved.left, greaterThan(tabs.right));
    expect(zoom.left, greaterThan(saved.right));
    expect(find.text('Rascunho'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('R2: tabs "Editar", "Lado a lado", "Visualizar", "Protótipo"; '
      'the active one is selected; no "Dividido"', (tester) async {
    final semantics = tester.ensureSemantics();
    SpecViewMode? picked;
    await pumpHeader(tester, onMode: (m) => picked = m);
    for (final l in ['Editar', 'Lado a lado', 'Visualizar', 'Protótipo']) {
      expect(find.text(l), findsOneWidget, reason: l);
    }
    expect(find.textContaining('Dividido'), findsNothing);
    expect(
      tester.getSemantics(key('spec-mode-split')),
      isSemantics(label: 'Modo Lado a lado', isSelected: true),
    );
    expect(
      tester.getSemantics(key('spec-mode-edit')),
      isSemantics(label: 'Modo Editar', isSelected: false),
    );
    await tester.tap(key('spec-mode-preview'));
    expect(picked, SpecViewMode.preview);
    semantics.dispose();
  });

  testWidgets('R5: locked: only "Clonar para alterar", lock on the badge and '
      '"Somente leitura"', (tester) async {
    await pumpHeader(
      tester,
      locked: true,
      status: SpecStatus.approved,
      actions: const SpecHeaderState(locked: true, onClone: _noop),
    );
    expect(key('spec-clone'), findsOneWidget);
    expect(find.text('Clonar para alterar'), findsOneWidget);
    expect(key('spec-status-lock'), findsOneWidget);
    expect(find.text('Somente leitura'), findsOneWidget);
    expect(key('spec-saved'), findsNothing);
    expect(key('spec-save'), findsNothing);
    for (final k in ['spec-refine', 'spec-design', 'spec-approve']) {
      expect(key(k), findsNothing, reason: k);
    }
    // Nothing to put in "Mais ações": no button (R7).
    expect(key('spec-more'), findsNothing);
    // With archive available, the menu comes back.
    await pumpHeader(
      tester,
      locked: true,
      actions: const SpecHeaderState(
        locked: true,
        onClone: _noop,
        onArchive: _noop,
      ),
    );
    expect(key('spec-more'), findsOneWidget);
  });

  testWidgets('R7, R7a: "Aprovar", "Arquivar" and "Excluir…" without "spec"; '
      'Excluir after a divider, in red', (tester) async {
    await pumpHeader(
      tester,
      actions: const SpecHeaderState(
        onRefine: _noop,
        onDesign: _noop,
        onApprove: _noop,
        onArchive: _noop,
        onDelete: _noop,
      ),
    );
    expect(find.text('Aprovar'), findsOneWidget);
    expect(find.text('Aprovar spec'), findsNothing);
    await tester.tap(key('spec-more'));
    await tester.pumpAndSettle();
    expect(find.text('Arquivar'), findsOneWidget);
    expect(find.text('Excluir…'), findsOneWidget);
    expect(key('spec-more-divider'), findsOneWidget);
    expect(
      tester.getRect(key('spec-more-divider')).top,
      greaterThan(tester.getRect(key('spec-archive')).bottom - 1),
    );
    expect(
      tester.getRect(key('spec-delete')).top,
      greaterThan(tester.getRect(key('spec-more-divider')).top),
    );
    final excluir = tester.widget<Text>(find.text('Excluir…'));
    final style = DefaultTextStyle.of(tester.element(find.text('Excluir…')))
        .style
        .merge(excluir.style);
    expect(style.color, AppColors.red);
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      final s = t.data ?? '';
      if (s == 'Gerar telas da spec') continue;
      if (RegExp(r'^(Aprovar|Arquivar|Desarquivar|Excluir)').hasMatch(s)) {
        expect(s.toLowerCase(), isNot(contains('spec')), reason: s);
      }
    }
  });

  group('R9: nothing truncated at 1100×700', () {
    void expectNoOverflow(WidgetTester tester) {
      expect(tester.takeException(), isNull);
      final paragraphs = tester.renderObjectList<RenderParagraph>(
        find.descendant(
          of: find.byType(SpecHeader),
          matching: find.byType(RichText),
        ),
      );
      expect(paragraphs, isNotEmpty);
      for (final p in paragraphs) {
        final text = p.text.toPlainText();
        // The path and the title may shorten; actions, tabs and states not.
        if (text.startsWith('docs/') || text == 'Ações da spec mais claras') {
          continue;
        }
        expect(p.didExceedMaxLines, isFalse, reason: text);
        expect(
          p.size.width + .5,
          greaterThanOrEqualTo(_natural(p)),
          reason: text,
        );
      }
    }

    for (final dirty in [false, true]) {
      testWidgets('draft${dirty ? ', not saved' : ''}: the primary stays, '
          'secondaries that do not fit go to the menu', (tester) async {
        await pumpHeader(tester, width: narrow, dirty: dirty);
        expectNoOverflow(tester);
        expect(find.text('Aprovar'), findsOneWidget);
        expect(key('spec-more'), findsOneWidget);
        for (final l in ['Editar', 'Lado a lado', 'Visualizar', 'Protótipo']) {
          expect(find.text(l), findsOneWidget, reason: l);
        }
        if (dirty) {
          expect(find.text('Não salvo'), findsOneWidget);
          expect(find.text('Ctrl+S'), findsOneWidget);
        }
        // Whatever left the bar is in the menu.
        final inBar = [
          for (final k in ['spec-refine', 'spec-design'])
            if (key(k).evaluate().isNotEmpty) k,
        ];
        if (!inBar.contains('spec-design')) {
          await tester.tap(key('spec-more'));
          await tester.pumpAndSettle();
          expect(find.text('Planejar de novo'), findsOneWidget);
          expectNoOverflow(tester);
        }
        // "Planejar" leaves before "Refinar com IA".
        if (inBar.contains('spec-design')) {
          expect(inBar, contains('spec-refine'));
        }
      });
    }

    testWidgets('approved, locked and Protótipo', (tester) async {
      await pumpHeader(
        tester,
        width: narrow,
        status: SpecStatus.approved,
        actions: const SpecHeaderState(
          approved: true,
          onRefine: _noop,
          onDesign: _noop,
          onDelete: _noop,
        ),
      );
      expectNoOverflow(tester);
      await pumpHeader(
        tester,
        width: narrow,
        locked: true,
        actions: const SpecHeaderState(locked: true, onClone: _noop),
      );
      expectNoOverflow(tester);
      expect(find.text('Clonar para alterar'), findsOneWidget);
      expect(find.text('Somente leitura'), findsOneWidget);
      await pumpHeader(
        tester,
        width: narrow,
        mode: SpecViewMode.prototype,
        actions: const SpecHeaderState(
          prototype: true,
          onCompare: _noop,
          onGenerate: _noop,
          onDelete: _noop,
        ),
      );
      expectNoOverflow(tester);
      expect(find.text('Gerar telas da spec'), findsOneWidget);
    });

    testWidgets('a wide window keeps every action in the bar', (tester) async {
      await pumpHeader(tester, width: 1100);
      expectNoOverflow(tester);
      expect(key('spec-refine'), findsOneWidget);
      expect(key('spec-design'), findsOneWidget);
      expect(key('spec-approve'), findsOneWidget);
    });
  });

  testWidgets('R10: every action has a tooltip; a disabled one keeps legible '
      'colors (no opacity) and says why', (tester) async {
    await pumpHeader(
      tester,
      actions: const SpecHeaderState(
        onRefine: _noop,
        onDesign: _noop,
        unavailableReason: 'Aguarde a ação em andamento terminar.',
      ),
    );
    expect(find.byTooltip(refineTooltip), findsOneWidget);
    expect(find.byTooltip(designTooltip), findsOneWidget);
    expect(find.byTooltip('Mais ações'), findsNothing);
    final approve = key('spec-approve');
    expect(tester.widget<SpecActionButton>(approve).onTap, isNull);
    expect(
      find.descendant(
        of: approve,
        matching: find.byTooltip('Aguarde a ação em andamento terminar.'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: approve, matching: find.byType(Opacity)),
      findsNothing,
    );
    final material = tester.widget<Material>(
      find.descendant(of: approve, matching: find.byType(Material)).first,
    );
    expect(material.color, AppColors.surfaceRaised);
    final label = tester.widget<Text>(
      find.descendant(of: approve, matching: find.text('Aprovar')),
    );
    expect(label.style!.color, AppColors.textDisabled);
    // Contrast of the disabled text on its background: 4,5:1 or more.
    double lum(Color c) => c.computeLuminance();
    final ratio =
        (lum(AppColors.textDisabled) + .05) /
        (lum(AppColors.surfaceRaised) + .05);
    expect(ratio, greaterThanOrEqualTo(4.5));
    // The tooltip shows up on hover.
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(approve));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('Aguarde a ação em andamento terminar.'), findsOneWidget);
    // "Salvar" shows Ctrl+S in its tooltip.
    await pumpHeader(tester, dirty: true);
    expect(find.byTooltip(RegExp(r'Ctrl\+S')), findsOneWidget);
    expect(find.byTooltip(approveTooltip), findsOneWidget);
  });

  testWidgets('R11: Tab goes through actions, tabs, Salvar and zoom; the '
      'menu moves with arrows and Esc gives the focus back', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpHeader(tester, dirty: true);
    expect(find.bySemanticsLabel('Mais ações da spec'), findsOneWidget);
    final order = <String>[];
    for (var i = 0; i < 14; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final k = focusedKey();
      if (k != null && (order.isEmpty || order.last != k)) order.add(k);
    }
    int at(String k) => order.indexOf(k);
    expect(order, containsAll(['spec-refine', 'spec-mode-edit', 'spec-save']));
    expect(at('spec-refine'), lessThan(at('spec-design')));
    expect(at('spec-design'), lessThan(at('spec-approve')));
    expect(at('spec-approve'), lessThan(at('spec-more')));
    expect(at('spec-more'), lessThan(at('spec-mode-edit')));
    expect(at('spec-mode-edit'), lessThan(at('spec-mode-prototype')));
    expect(at('spec-mode-prototype'), lessThan(at('spec-save')));
    expect(at('spec-save'), lessThan(at('zoom')), reason: '$order');

    // Menu: Enter opens, arrows move, Esc closes and returns to the button.
    await pumpHeader(
      tester,
      actions: const SpecHeaderState(
        onRefine: _noop,
        onDesign: _noop,
        onApprove: _noop,
        onArchive: _noop,
        onDelete: _noop,
      ),
    );
    final more = key('spec-more');
    for (var i = 0; i < 20 && focusedKey() != 'spec-more'; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(focusedKey(), 'spec-more');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(key('spec-archive'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focusedKey(), 'spec-archive');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(focusedKey(), 'spec-delete');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(focusedKey(), 'spec-archive');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(key('spec-archive'), findsNothing);
    expect(focusedKey(), 'spec-more');
    // Focus ring: amber 2 px outline on the focused button.
    final shape =
        tester
                .widget<Material>(
                  find
                      .descendant(
                        of: find.byType(SpecMoreButton),
                        matching: find.byType(Material),
                      )
                      .first,
                )
                .shape!
            as RoundedRectangleBorder;
    expect(shape.side.color, AppColors.amber);
    expect(shape.side.width, 2);
    expect(more, findsOneWidget);
    semantics.dispose();
  });
}

/// Natural (unconstrained) width of a paragraph.
double _natural(RenderParagraph p) {
  final tp = TextPainter(
    text: p.text,
    textDirection: p.textDirection,
    textScaler: p.textScaler,
    maxLines: 1,
  )..layout();
  final w = tp.width;
  tp.dispose();
  return w;
}
