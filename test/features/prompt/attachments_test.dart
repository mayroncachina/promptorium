import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/prompt/attachments.dart';

void main() {
  late Directory ws;
  late Directory outside;

  setUp(() {
    ws = Directory.systemTemp.createTempSync('promptorium-att-ws-');
    outside = Directory.systemTemp.createTempSync('promptorium-att-out-');
  });

  tearDown(() {
    ws.deleteSync(recursive: true);
    outside.deleteSync(recursive: true);
  });

  test('imageMediaType', () {
    expect(imageMediaType('/a/Foto.PNG'), 'image/png');
    expect(imageMediaType('x.jpeg'), 'image/jpeg');
    expect(imageMediaType('x.webp'), 'image/webp');
    expect(imageMediaType('x.pdf'), isNull);
  });

  test('image → block; outside file → copied and mentioned; inside file → '
      'mentioned as is', () async {
    final img = File('${outside.path}/foto.png')
      ..writeAsBytesSync([1, 2, 3, 4]);
    final pdf = File('${outside.path}/relatorio.pdf')
      ..writeAsStringSync('conteúdo');
    File('${ws.path}/docs').createSync();
    final inside = File('${ws.path}/leia-me.md')..writeAsStringSync('# oi');

    final r = await prepareAttachments(ws.path, [
      img.path,
      pdf.path,
      inside.path,
    ], now: DateTime.utc(2026, 10, 16, 12));

    expect(r.names, ['foto.png', 'relatorio.pdf', 'leia-me.md']);
    expect(r.images.single.mediaType, 'image/png');
    expect(r.images.single.base64, base64Encode([1, 2, 3, 4]));
    expect(r.mentions, [
      '.promptorium/attachments/2026-10-16T12-00-00-000Z/relatorio.pdf',
      'leia-me.md',
    ]);
    expect(
      File('${ws.path}/${r.mentions.first}').readAsStringSync(),
      'conteúdo',
    );
    // The copies never reach git.
    expect(
      File('${ws.path}/.promptorium/.gitignore').readAsStringSync(),
      'attachments/\n',
    );
    // The original is untouched.
    expect(pdf.existsSync(), isTrue);

    final text = r.applyTo('Resuma os anexos');
    expect(text, startsWith('Resuma os anexos\n\n@.promptorium/attachments/'));
    expect(text, contains(' @leia-me.md'));
    expect(text, endsWith('(imagem anexada: foto.png)'));
  });

  test(
    'same name twice does not overwrite; missing file and too many fail',
    () async {
      final a = File('${outside.path}/a/n.txt')
        ..createSync(recursive: true)
        ..writeAsStringSync('1');
      final b = File('${outside.path}/b/n.txt')
        ..createSync(recursive: true)
        ..writeAsStringSync('2');
      final r = await prepareAttachments(ws.path, [a.path, b.path]);
      expect(r.mentions, hasLength(2));
      expect(r.mentions.toSet(), hasLength(2));
      expect(File('${ws.path}/${r.mentions[1]}').readAsStringSync(), '2');

      await expectLater(
        prepareAttachments(ws.path, ['${outside.path}/nao-existe.txt']),
        throwsA(isA<AttachmentException>()),
      );
      await expectLater(
        prepareAttachments(ws.path, List.filled(maxAttachments + 1, a.path)),
        throwsA(isA<AttachmentException>()),
      );
      expect((await prepareAttachments(ws.path, [])).mentions, isEmpty);
    },
  );

  test('image over the limit is copied like a file', () async {
    final big = File('${outside.path}/grande.png')
      ..writeAsBytesSync(List.filled(maxImageBytes + 1, 0));
    final r = await prepareAttachments(ws.path, [big.path]);
    expect(r.images, isEmpty);
    expect(r.mentions.single, contains('grande.png'));
  });
}
