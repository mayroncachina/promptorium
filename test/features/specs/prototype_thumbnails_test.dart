import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/process/process_runner.dart';
import 'package:promptorium/features/specs/prototype/prototype_service.dart';
import 'package:promptorium/features/specs/prototype/prototype_thumbnails.dart';

/// 1×1 PNG.
const png1x1 = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

/// Fake `which` + headless browser: the screenshot writes a PNG.
class FakeBrowser {
  FakeBrowser({this.installed = true});

  final bool installed;
  final calls = <List<String>>[];
  final lookups = <String>[];

  Future<ProcessResult> run(String exe, List<String> args) async {
    if (exe == 'which') {
      lookups.add(args.single);
      return installed && args.single == 'google-chrome'
          ? ProcessResult(1, 0, '/usr/bin/google-chrome\n', '')
          : ProcessResult(1, 1, '', '');
    }
    calls.add([exe, ...args]);
    final shot = args.firstWhere((a) => a.startsWith('--screenshot='));
    File(shot.substring('--screenshot='.length)).writeAsBytesSync(png1x1);
    return ProcessResult(1, 0, '', '');
  }
}

Future<void> waitFor(bool Function() cond) async {
  final end = DateTime.now().add(const Duration(seconds: 15));
  while (!cond()) {
    if (DateTime.now().isAfter(end)) fail('condição não atingida');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('promptorium-thumb-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  ProviderContainer container(FakeBrowser b) {
    final c = ProviderContainer(
      overrides: [
        processRunnerProvider.overrideWithValue(b.run),
        prototypeCacheDirProvider.overrideWithValue('${tmp.path}/cache'),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('R4: creating or changing an HTML runs the headless command at '
      '1440×900 and the state gets the PNG (cache outside the repo)', () async {
    final b = FakeBrowser();
    final c = container(b);
    final repo = '${tmp.path}/repo';
    Directory('$repo/docs/mockups/spec-022').createSync(recursive: true);
    final key = (root: repo, code: 'SPEC-022');
    final sub = c.listen(prototypeScreensProvider(key), (_, _) {});
    addTearDown(sub.close);
    await waitFor(() => c.read(prototypeScreensProvider(key)).loaded);
    expect(b.calls, isEmpty);

    final html = File('$repo/docs/mockups/spec-022/R1-lista.html')
      ..writeAsStringSync('<p>a</p>');
    await waitFor(
      () => c
          .read(prototypeScreensProvider(key))
          .thumbs
          .containsKey('R1-lista.html'),
    );
    expect(b.calls, hasLength(1));
    final call = b.calls.single;
    expect(call.first, '/usr/bin/google-chrome');
    expect(call, contains('--headless=new'));
    expect(call, contains('--window-size=1440,900'));
    expect(call.last, Uri.file(html.path).toString());
    final first = c
        .read(prototypeScreensProvider(key))
        .thumbs['R1-lista.html']!;
    expect(first, startsWith('${tmp.path}/cache/'));
    expect(File(first).existsSync(), isTrue);
    expect(call, contains('--screenshot=$first'));

    // Changed file: new key, new screenshot.
    html.writeAsStringSync('<p>b — maior</p>');
    html.setLastModifiedSync(DateTime.now().add(const Duration(seconds: 5)));
    await waitFor(() => b.calls.length == 2);
    await waitFor(
      () =>
          c.read(prototypeScreensProvider(key)).thumbs['R1-lista.html'] !=
          first,
    );
    expect(c.read(prototypeScreensProvider(key)).browserMissing, isFalse);
  });

  test(
    'R5: without a headless browser nothing runs and the state says so',
    () async {
      final b = FakeBrowser(installed: false);
      final c = container(b);
      final repo = '${tmp.path}/repo';
      Directory('$repo/docs/mockups/spec-022').createSync(recursive: true);
      File('$repo/docs/mockups/spec-022/R1-lista.html').writeAsStringSync('x');
      final key = (root: repo, code: 'SPEC-022');
      final sub = c.listen(prototypeScreensProvider(key), (_, _) {});
      addTearDown(sub.close);
      await waitFor(() => c.read(prototypeScreensProvider(key)).browserMissing);
      expect(b.lookups, headlessBrowsers);
      expect(b.calls, isEmpty);
      expect(c.read(prototypeScreensProvider(key)).thumbs, isEmpty);
    },
  );

  test('headlessArgs', () {
    expect(
      headlessArgs(
        html: '/r/a b.html',
        png: '/c/x.png',
        profileDir: '/c/profile',
        size: narrowThumbnailSize,
      ),
      [
        '--headless=new',
        '--disable-gpu',
        '--hide-scrollbars',
        '--no-first-run',
        '--no-default-browser-check',
        '--user-data-dir=/c/profile',
        '--screenshot=/c/x.png',
        '--window-size=1100,700',
        'file:///r/a%20b.html',
      ],
    );
  });
}
