@TestOn('linux')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// SPEC-029 R4: install.sh installs the mark from 16 to 512 px and the SVG
/// into hicolor; uninstall.sh removes them.
void main() {
  late Directory data;

  setUp(() => data = Directory.systemTemp.createTempSync('promptorium-icons'));
  tearDown(() => data.deleteSync(recursive: true));

  test('install.sh --icons-only instala a marca e uninstall.sh remove', () {
    final env = {'XDG_DATA_HOME': data.path, 'HOME': data.path};
    final install = Process.runSync('bash', [
      'scripts/install.sh',
      '--icons-only',
    ], environment: env);
    expect(install.exitCode, 0, reason: '${install.stdout}${install.stderr}');

    final hicolor = '${data.path}/icons/hicolor';
    for (final n in [16, 22, 24, 32, 48, 64, 128, 256, 512]) {
      final png = File('$hicolor/${n}x$n/apps/promptorium.png');
      expect(png.existsSync(), isTrue, reason: png.path);
      expect(
        png.readAsBytesSync(),
        File('assets/icon/mark/mark-$n.png').readAsBytesSync(),
        reason: '$n px deve ser a marca',
      );
    }
    expect(File('$hicolor/scalable/apps/promptorium.svg').existsSync(), isTrue);

    final uninstall = Process.runSync('bash', [
      'scripts/uninstall.sh',
    ], environment: env);
    expect(uninstall.exitCode, 0, reason: '${uninstall.stderr}');
    expect(File('$hicolor/16x16/apps/promptorium.png').existsSync(), isFalse);
    expect(
      File('$hicolor/scalable/apps/promptorium.svg').existsSync(),
      isFalse,
    );
  });
}
