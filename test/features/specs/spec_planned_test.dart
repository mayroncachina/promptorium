import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/specs/widgets/spec_header.dart';
import 'package:promptorium/ui/theme/tokens.dart';

import 'spec_action_lock_test.dart';
import 'spec_file_test.dart' show sample;
import 'specs_screen_test.dart' show settleIo;

/// SPEC-062: "Planejar de novo" stays in the bar and "Planejada" shows in
/// the header and in the list.
void main() {
  late Directory tmp;
  late FakeDesigner designer;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('promptorium-planned-');
    Directory('${tmp.path}/specs').createSync();
    File(specPath(tmp)).writeAsStringSync(sample);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  FakeDesigner make(Ref ref) => designer = FakeDesigner(ref);

  Finder inBar(String text) =>
      find.descendant(of: key('spec-actions'), matching: find.text(text));

  String chip(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(of: key('spec-status'), matching: find.byType(Text)),
      )
      .data!;

  String listStatus(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(
          of: key('spec-item-status-SPEC-002'),
          matching: find.byType(Text),
        ),
      )
      .data!;

  Color listColor(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(
          of: key('spec-item-status-SPEC-002'),
          matching: find.byType(Text),
        ),
      )
      .style!
      .color!;

  Future<void> plan(WidgetTester tester) async {
    await startDesign(tester, () => designer);
    designer.next.complete('${sample.trimRight()}\n\n## Plano\n\nFazer X.\n');
    await settleIo(tester);
    await tester.pump();
  }

  testWidgets('R1, R3: in 1366×768 the plan in the editor turns the button '
      'into "Planejar de novo", kept in the bar, and the chip into '
      '"Planejada", before saving', (tester) async {
    await pumpSpecs(tester, tmp, designer: make, size: const Size(1366, 900));
    expect(inBar('Planejar'), findsOneWidget);
    expect(chip(tester), isNot('Planejada'));
    await plan(tester);
    expect(key('spec-unsaved'), findsOneWidget);
    expect(inBar('Planejar de novo'), findsOneWidget);
    expect(inBar('Aprovar'), findsOneWidget);
    // "Refinar com IA" went to the menu instead.
    expect(inBar('Refinar com IA'), findsNothing);
    expect(key('spec-more'), findsOneWidget);
    expect(chip(tester), 'Planejada');
    // The list reads the file: not saved yet.
    expect(listStatus(tester), isNot('Planejada'));
  });

  testWidgets('R2: the list shows "Planejada" in yellow once the plan is '
      'saved, and the status again when the plan leaves the file', (
    tester,
  ) async {
    await pumpSpecs(tester, tmp, designer: make);
    final before = listStatus(tester);
    await plan(tester);
    await tester.tap(key('spec-save'));
    await settleIo(tester, until: () => listStatus(tester) == 'Planejada');
    expect(listStatus(tester), 'Planejada');
    expect(listColor(tester), AppColors.yellow);
    expect(File(specPath(tmp)).readAsStringSync(), contains('## Plano'));

    editorOf(tester).controller!.text = sample;
    await tester.pump();
    expect(chip(tester), isNot('Planejada'));
    await tester.tap(key('spec-save'));
    await settleIo(tester, until: () => listStatus(tester) == before);
    expect(listStatus(tester), before);
  });

  testWidgets('R2: an approved spec with a plan stays "Aprovada"', (
    tester,
  ) async {
    File(specPath(tmp)).writeAsStringSync(
      '${sample.replaceFirst(RegExp(r'status: [^\n]+'), 'status: aprovada').trimRight()}'
      '\n\n## Plano\n\nFazer X.\n',
    );
    await pumpSpecs(tester, tmp, designer: make);
    expect(listStatus(tester), 'Aprovada');
    expect(chip(tester), 'Aprovada');
    expect(find.byType(SpecHeader), findsOneWidget);
  });
}
