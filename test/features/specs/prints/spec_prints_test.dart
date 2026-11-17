import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/specs/prototype/prototype_files.dart';
import 'package:promptorium/features/specs/spec_draft.dart';
import 'package:promptorium/features/specs/spec_file.dart';
import 'package:promptorium/features/specs/spec_planner.dart';
import 'package:promptorium/features/specs/spec_prints.dart';
import 'package:promptorium/features/specs/specs_screen.dart' show SpecPreview;

import '../../../helpers/test_db.dart';
import '../../sessions/session_test_utils.dart';
import 'print_test_utils.dart';

Future<(int, int)> sizeOf(String path) async {
  final codec = await ui.instantiateImageCodec(await File(path).readAsBytes());
  final img = (await codec.getNextFrame()).image;
  return (img.width, img.height);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('promptorium-prints-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('preparePrint (R3, R4)', () {
    test('a large print is reduced to 1568 px keeping the proportion, as '
        'PNG in the git-ignored attachments folder', () async {
      final s = await preparePrint(
        await pngBytes(2880, 1800),
        workspacePath: tmp.path,
      );
      expect((s.width, s.height), (1568, 980));
      expect((s.originalWidth, s.originalHeight), (2880, 1800));
      expect(s.fullSizeLabel, '1568 × 980 · reduzido de 2880 × 1800');
      expect(s.name, 'print-1.png');
      expect(s.path, contains('/.promptorium/attachments/'));
      expect(await sizeOf(s.path), (1568, 980));
      expect(
        File('${tmp.path}/.promptorium/.gitignore').readAsStringSync(),
        'attachments/\n',
      );
    });

    test(
      'a tall print reduces the height; a small one stays as it is',
      () async {
        final tall = await preparePrint(
          await pngBytes(800, 3136),
          workspacePath: tmp.path,
        );
        expect((tall.width, tall.height), (400, 1568));
        final small = await preparePrint(
          await pngBytes(1366, 768),
          workspacePath: tmp.path,
          existing: [tall],
        );
        expect(small.reduced, isFalse);
        expect(small.fullSizeLabel, '1366 × 768');
        expect(small.name, 'print-2.png');
      },
    );

    test('refuses what is not an image, more than 20 MB and the fifth print', () async {
      await expectLater(
        preparePrint(
          Uint8List.fromList('ftypmp42 vídeo'.codeUnits),
          workspacePath: tmp.path,
          sourceName: 'gravacao.mp4',
        ),
        throwsA(
          isA<PrintException>().having(
            (e) => e.message,
            'message',
            '"gravacao.mp4" não é uma imagem. Aceitos: PNG, JPEG, WebP e GIF, '
                'até 20 MB.',
          ),
        ),
      );
      final big = Uint8List(maxPrintBytes + 1)
        ..setAll(0, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      await expectLater(
        preparePrint(big, workspacePath: tmp.path),
        throwsA(isA<PrintException>()),
      );
      final four = [
        for (var i = 1; i <= 4; i++)
          fakePrint('/x/$i.png', name: 'print-$i.png'),
      ];
      await expectLater(
        preparePrint(
          await pngBytes(10, 10),
          workspacePath: tmp.path,
          existing: four,
        ),
        throwsA(
          isA<PrintException>().having(
            (e) => e.message,
            'message',
            startsWith('No máximo 4 prints por spec'),
          ),
        ),
      );
    });

    test('the signature tells the format', () {
      expect(sniffImageExtension(const [0xFF, 0xD8, 0xFF, 0xE0]), 'jpg');
      expect(sniffImageExtension('GIF89a'.codeUnits), 'gif');
      expect(
        sniffImageExtension([
          ...'RIFF'.codeUnits,
          0,
          0,
          0,
          0,
          ...'WEBP'.codeUnits,
        ]),
        'webp',
      );
      expect(sniffImageExtension('%PDF-1.7'.codeUnits), isNull);
    });
  });

  group('SpecDraftData (R4)', () {
    test('the prints go in and out of the JSON of spec_drafts.data', () {
      final d = SpecDraftData(
        prints: [
          SpecPrint(
            path: '/w/.promptorium/attachments/x/print-1.png',
            name: 'print-1.png',
            width: 1568,
            height: 980,
            originalWidth: 2880,
            originalHeight: 1800,
            kind: PrintKind.reference,
            description: 'Três colunas',
            brands: const ['Nimbo'],
          ),
          fakePrint('/w/b.png', name: 'print-2.png', kind: null),
        ],
        printsSent: true,
      );
      final back = SpecDraftData.decode(d.encode());
      expect(back.prints, d.prints);
      expect(back.prints.first.fullSizeLabel, contains('reduzido de 2880'));
      expect(back.prints.last.kind, isNull);
      expect(back.printsSent, isTrue);
      expect(printsTyped(back.prints), isFalse);
      expect(SpecDraftData.decode('{}').prints, isEmpty);
    });

    test('removing renumbers print-N by position', () {
      final r = renumberPrints([
        fakePrint('/a/print-2.png', name: 'print-2.png'),
        fakePrint('/a/x.jpg', name: 'print-3.jpg'),
      ]);
      expect(r.map((s) => s.name), ['print-1.png', 'print-2.jpg']);
    });
  });

  group('specTextFromDraft (R11, R7)', () {
    test('"Referência visual" after the Objetivo, with the path relative to '
        'the spec, the description as alt text and the reference note', () {
      final d = SpecDraftData(
        objective: 'Comparar duas respostas.',
        requirements: const ['O sistema deve mostrar duas colunas.'],
        prints: [
          fakePrint(
            '/t/p.png',
            kind: PrintKind.reference,
            description: 'Três colunas iguais com um botão embaixo',
          ),
        ],
      );
      final text = specTextFromDraft(d, code: 'SPEC-087', title: 'Comparar');
      expect(
        text,
        contains(
          '![Print 1: Três colunas iguais com um botão embaixo]'
          '(../../docs/mockups/spec-087/print-1.png)',
        ),
      );
      expect(text, contains('- print-1.png · Referência de outro app'));
      expect(text, contains(referenceNote));
      expect(
        text.indexOf('## Objetivo') < text.indexOf('## Referência visual') &&
            text.indexOf('## Referência visual') <
                text.indexOf('## Requisitos'),
        isTrue,
      );
      expect(SpecDocument.parse(text).frontmatter.containsKey('tipo'), isFalse);
    });

    test('a bug print makes the spec tipo: bug; no prints, no section', () {
      final bug = SpecDraftData(
        prints: [fakePrint('/t/p.png', description: 'O botão cortado')],
      );
      final text = specTextFromDraft(
        bug,
        code: 'SPEC-073',
        title: 'Botão',
        specsDir: 'specs',
      );
      expect(SpecDocument.parse(text).frontmatter['tipo'], 'bug');
      expect(
        text,
        contains(
          '![Print 1: O botão cortado](../docs/mockups/spec-073/print-1.png)',
        ),
      );
      expect(text, isNot(contains(referenceNote)));
      final none = specTextFromDraft(
        const SpecDraftData(),
        code: 'SPEC-1',
        title: 'x',
      );
      expect(none, isNot(contains('Referência visual')));
    });
  });

  group('copyPrintsToMockups (R10)', () {
    test('writes print-N in docs/mockups/spec-0NN/ and the marks in '
        'index.json; the prototype does not list them as screens', () async {
      final a = File('${tmp.path}/a.png')
        ..writeAsBytesSync(await pngBytes(4, 4));
      final b = File('${tmp.path}/b.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF]);
      final names = await copyPrintsToMockups(tmp.path, 'SPEC-087', [
        fakePrint(a.path, kind: PrintKind.bug, description: 'cortado'),
        fakePrint(
          b.path,
          name: 'print-2.jpg',
          kind: PrintKind.reference,
          brands: const ['Nimbo'],
        ),
      ]);
      expect(names, ['print-1.png', 'print-2.jpg']);
      final dir = '${tmp.path}/docs/mockups/spec-087';
      expect(File('$dir/print-1.png').existsSync(), isTrue);
      expect(File('$dir/print-2.jpg').existsSync(), isTrue);
      final index = await PrototypeIndex.read(dir);
      expect(index.prints['print-1.png']!.kind, PrintKind.bug);
      expect(index.prints['print-1.png']!.description, 'cortado');
      expect(await referenceBrandsOf(dir), ['Nimbo']);
      expect(await listScreens(dir), isEmpty);
      // Kept through other writes of the prototype.
      final again = PrototypeIndex.decode(index.encode());
      expect(again.prints.keys, ['print-1.png', 'print-2.jpg']);
    });

    test('a failed copy removes what was copied and throws', () async {
      final a = File('${tmp.path}/a.png')..writeAsBytesSync([1]);
      await expectLater(
        copyPrintsToMockups(tmp.path, 'SPEC-002', [
          fakePrint(a.path),
          fakePrint('${tmp.path}/sumiu.png', name: 'print-2.png'),
        ]),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        File('${tmp.path}/docs/mockups/spec-002/print-1.png').existsSync(),
        isFalse,
      );
    });
  });

  group('SpecPlanner.create and discard (R4, R10)', () {
    late ProviderContainer c;
    late Workspace ws;

    setUp(() async {
      c = ProviderContainer(
        overrides: sessionOverrides(
          db: memoryDatabase(),
          cli: FakeCli(),
          notifier: FakeNotifier(),
        ),
      );
      c.listen(specPlannerProvider, (_, _) {});
      await c.read(appSettingsProvider.notifier).load();
      ws = await c.read(workspacesRepoProvider).add(path: tmp.path, name: 'r');
    });
    tearDown(() => c.dispose());

    Future<File> draftWith(List<SpecPrint> prints) async {
      final repo = c.read(specDraftsRepoProvider);
      await repo.start(ws.id);
      await repo.update(
        ws.id,
        SpecDraftsCompanion(
          data: Value(
            SpecDraftData(
              title: 'Botão cortado',
              objective: 'Corrigir o botão.',
              prints: prints,
            ).encode(),
          ),
        ),
      );
      return File(prints.first.path);
    }

    test('"Criar spec" copies the prints with the spec and removes the '
        'temporary files', () async {
      final tmpPrint = await preparePrint(
        await pngBytes(20, 10),
        workspacePath: tmp.path,
      );
      final f = await draftWith([
        tmpPrint.copyWith(kind: PrintKind.bug, description: 'cortado'),
      ]);
      final spec = await c
          .read(specPlannerProvider.notifier)
          .create(ws, title: 'Botão cortado');
      final mock = File(
        '${tmp.path}/docs/mockups/${spec.code.toLowerCase()}/print-1.png',
      );
      expect(mock.existsSync(), isTrue);
      expect(f.existsSync(), isFalse);
      final text = File('${tmp.path}/${spec.path}').readAsStringSync();
      // The image path, relative to the spec file, reaches the copy.
      final rel = RegExp(r'!\[Print 1: cortado\]\(([^)]+)\)')
          .firstMatch(text)!
          .group(1)!;
      expect(
        File(p.normalize(p.join(p.dirname('${tmp.path}/${spec.path}'), rel)))
            .existsSync(),
        isTrue,
      );
      expect(SpecDocument.parse(text).frontmatter['tipo'], 'bug');
      expect(await c.read(specDraftsRepoProvider).get(ws.id), isNull);
    });

    test('a failed copy creates no spec and keeps the draft', () async {
      await draftWith([fakePrint('${tmp.path}/sumiu.png')]);
      await expectLater(
        c.read(specPlannerProvider.notifier).create(ws, title: 'Botão'),
        throwsA(anything),
      );
      expect(await c.read(specDraftsRepoProvider).get(ws.id), isNotNull);
      expect(
        await c.read(specsRepoProvider).watchByWorkspace(ws.id).first,
        isEmpty,
      );
      final specsDir = Directory('${tmp.path}/docs/specs');
      expect(
        specsDir.existsSync() ? specsDir.listSync() : const [],
        isEmpty,
        reason: 'the reserved file is removed',
      );
    });

    test('discarding the draft deletes the temporary prints', () async {
      final pr = await preparePrint(
        await pngBytes(8, 8),
        workspacePath: tmp.path,
      );
      final f = await draftWith([pr]);
      expect(f.existsSync(), isTrue);
      await c.read(specPlannerProvider.notifier).discard(ws);
      expect(f.existsSync(), isFalse);
      expect(await c.read(specDraftsRepoProvider).get(ws.id), isNull);
    });
  });

  testWidgets('R11: the preview of the spec shows the print, resolved from '
      'the folder of the spec file', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SpecPreview(
            text:
                '---\nid: SPEC-073\n---\n\n# Botão\n\n'
                '![Print 1: o botão cortado](../mockups/spec-073/print-1.png)\n',
            imageDirectory: '/w/docs/specs',
          ),
        ),
      ),
    );
    final img = tester.widget<Image>(
      find.byKey(const ValueKey('markdown-image-print-1.png')),
    );
    expect(
      (img.image as FileImage).file.path,
      '/w/docs/mockups/spec-073/print-1.png',
    );
    expect(img.semanticLabel, 'Print 1: o botão cortado');
  });
}
