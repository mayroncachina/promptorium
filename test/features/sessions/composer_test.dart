import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/dev/picked_element.dart';
import 'package:promptorium/features/sessions/picked_elements.dart';
import 'package:promptorium/features/sessions/preview_reload.dart';
import 'package:promptorium/features/sessions/sessions_screen.dart';
import 'package:promptorium/features/sessions/widgets/composer.dart';

import 'sessions_screen_test.dart' show pumpFor, pumpScreen;

/// SPEC-051 R8, R11: pointed elements as attachments of the composer.
void main() {
  // 1×1 PNG.
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQ'
    'GAhKmMIQAAAABJRU5ErkJggg==',
  );
  PickedElement element({String selector = 'form.login > button'}) =>
      PickedElement(
        selector: selector,
        html: '<button type="submit" disabled>Continuar</button>',
        url: 'http://127.0.0.1:4003/login',
        styles: const {
          'background-color': 'rgb(157, 184, 238)',
          'color': 'rgb(255, 255, 255)',
        },
        width: 348,
        height: 44,
        elementPng: png,
        pagePng: png,
      );

  test('the request carries the text of each element and the PNGs as '
      'images', () async {
    final m = await buildPickedMessage(
      'O botão deve ficar azul forte quando habilitado.',
      [element(), element(selector: '.login h1')],
      images: true,
      root: '/nao/usado',
    );
    expect(m.text, startsWith('O botão deve ficar azul forte'));
    expect(m.text, contains('Elemento apontado 1 no preview:'));
    expect(m.text, contains('- seletor: `form.login > button`'));
    expect(m.text, contains('- seletor: `.login h1`'));
    expect(m.text, contains('- URL: http://127.0.0.1:4003/login'));
    expect(m.text, contains('- tamanho: 348 × 44'));
    expect(m.text, contains('  - background-color: rgb(157, 184, 238)'));
    expect(m.text, contains('<button type="submit" disabled>'));
    expect(m.images, hasLength(4));
    expect(m.images.first.mediaType, 'image/png');
    expect(base64Decode(m.images.first.base64), png);
    expect(m.images.map((i) => i.name), [
      'elemento-1.png',
      'pagina-1.png',
      'elemento-2.png',
      'pagina-2.png',
    ]);
  });

  test('Codex without the image modality: the PNGs go as files in '
      '.promptorium/attachments, mentioned in the text', () async {
    final tmp = Directory.systemTemp.createTempSync('picked_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final m = await buildPickedMessage(
      '',
      [element()],
      images: false,
      root: tmp.path,
      now: DateTime(2026, 11, 13, 21),
    );
    expect(m.images, isEmpty);
    expect(m.text, startsWith('Veja o elemento apontado no preview.'));
    const dir = '.promptorium/attachments/2026-11-13T21-00-00-000';
    expect(
      m.text,
      contains('- prints: @$dir/elemento-1.png @$dir/pagina-1.png'),
    );
    expect(File('${tmp.path}/$dir/elemento-1.png').readAsBytesSync(), png);
    expect(
      File('${tmp.path}/.promptorium/.gitignore').readAsStringSync(),
      'attachments/\n',
    );

    expect(sendsImages('claude', alive: false, accepts: false), isTrue);
    expect(sendsImages('codex', alive: true, accepts: false), isFalse);
    expect(sendsImages('codex', alive: false, accepts: true), isFalse);
    expect(sendsImages('codex', alive: true, accepts: true), isTrue);
  });

  testWidgets('the composer shows the cards, removes one and sends the '
      'request with the element and the PNGs (R8)', (tester) async {
    final (_, cli) = await pumpScreen(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SessionsScreen)),
    );
    container.read(pickedElementsProvider('s1').notifier)
      ..add(element())
      ..add(element(selector: '.login h1'));
    await pumpFor(tester);

    expect(find.byKey(const ValueKey('composer-picked-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('composer-picked-1')), findsOneWidget);
    expect(find.text('form.login > button'), findsOneWidget);
    expect(
      find.text('127.0.0.1:4003/login · 348 × 44 · 2 imagens'),
      findsOneWidget,
    );
    expect(find.text('Mostrar detalhes'), findsOneWidget);
    expect(find.text('Pedido'), findsOneWidget);
    expect(
      find.textContaining('2 elementos anexados · o seletor, o HTML'),
      findsOneWidget,
    );

    final remove = find.descendant(
      of: find.byKey(const ValueKey('composer-picked-1')),
      matching: find.byKey(const ValueKey('picked-remove')),
    );
    await tester.ensureVisible(remove);
    await tester.pump();
    await tester.tap(remove);
    await pumpFor(tester);
    expect(find.byKey(const ValueKey('composer-picked-1')), findsNothing);
    expect(find.textContaining('1 elemento anexado'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('composer-field')),
      'O botão deve ficar azul',
    );
    await tester.tap(find.byKey(const ValueKey('composer-send')));
    for (var i = 0; i < 20 && cli.processes.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await pumpFor(tester, 2);
    }
    await pumpFor(tester);
    final sent = cli.last.writtenJson.single;
    final content = sent['message']['content'] as List;
    expect(content.where((b) => b['type'] == 'image'), hasLength(2));
    final text = content.lastWhere((b) => b['type'] == 'text')['text'];
    expect(text, startsWith('O botão deve ficar azul'));
    expect(text, contains('- seletor: `form.login > button`'));
    expect(container.read(pickedElementsProvider('s1')), isEmpty);
    expect(find.byKey(const ValueKey('composer-picked-0')), findsNothing);
  });

  group(
    'R11: the preview reloads when a file changed and the page did not',
    () {
      late List<String> evaluated;
      late int reloads;
      late List<String> snapshots;
      late List<bool> busy;
      Object? changed;

      PreviewReloader reloader() => PreviewReloader(
        isOpen: () => true,
        evaluate: (e) async {
          evaluated.add(e);
          return e == previewChangedScript ? changed : true;
        },
        reload: () async => reloads++,
        snapshot: () async => snapshots.removeAt(0),
        busy: () => busy.isEmpty ? false : busy.removeAt(0),
        settle: const Duration(milliseconds: 5),
        poll: const Duration(milliseconds: 1),
      );

      setUp(() {
        evaluated = [];
        reloads = 0;
        busy = [true, true, false];
      });

      test('file changed, page did not: reload', () async {
        snapshots = ['a', 'b'];
        changed = false;
        expect(await reloader().run(), isTrue);
        expect(evaluated.first, previewWatchScript);
        expect(reloads, 1);
      });

      test('hot reload changed the page: nothing', () async {
        snapshots = ['a', 'b'];
        changed = true;
        expect(await reloader().run(), isFalse);
        expect(reloads, 0);
      });

      test('no file changed: nothing', () async {
        snapshots = ['a', 'a'];
        changed = false;
        expect(await reloader().run(), isFalse);
        expect(reloads, 0);
      });
    },
  );
}
