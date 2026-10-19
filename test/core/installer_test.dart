import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/update/installer.dart';
import 'package:promptorium/core/update/update_check.dart';

ReleaseAsset _a(String n) =>
    ReleaseAsset(name: n, url: 'https://github.com/x/$n');

void main() {
  group('pickAsset', () {
    final all = [_a('p.zip'), _a('p.tar.gz'), _a('p.deb')];

    test('prefers .deb with pkexec, .tar.gz without', () {
      expect(pickAsset(all)!.name, 'p.deb');
      expect(pickAsset(all, preferDeb: false)!.name, 'p.tar.gz');
    });

    test('falls back to the other format', () {
      expect(pickAsset([_a('p.tar.gz')])!.name, 'p.tar.gz');
      expect(pickAsset([_a('p.deb')], preferDeb: false)!.name, 'p.deb');
    });

    test('null when nothing is compatible', () {
      expect(pickAsset([_a('p.zip'), _a('p.exe')]), isNull);
      expect(pickAsset(const []), isNull);
    });
  });

  test('download writes to a new temp dir and emits progress 0..1', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final data = List<int>.generate(200000, (i) => i % 251);
    server.listen((req) async {
      req.response.contentLength = data.length;
      req.response.add(data);
      await req.response.close();
    });
    final root = await Directory.systemTemp.createTemp('inst-test-');
    addTearDown(() => root.delete(recursive: true));

    final asset = ReleaseAsset(
      name: 'p.deb',
      url: 'http://127.0.0.1:${server.port}/p.deb',
    );
    final events = await UpdateInstaller(tempRoot: root)
        .download(asset)
        .toList();

    final fractions = events.map((e) => e.fraction!).toList();
    expect(fractions.first, 0);
    expect(fractions.last, 1);
    expect(fractions, orderedEquals([...fractions]..sort()));
    final file = events.last.file!;
    expect(file.parent.parent.path, root.path);
    expect(file.parent.listSync().length, 1);
    expect(await file.readAsBytes(), data);
  });

  test(
    'installAndRestart installs, closes the database, then restarts',
    () async {
      final calls = <String>[];
      await _Recording(calls).installAndRestart(
        File('/tmp/p.deb'),
        closeDatabase: () async => calls.add('close'),
      );
      expect(calls, ['install', 'close', 'restart']);
    },
  );

  test('a failed install neither closes the database nor restarts', () async {
    final calls = <String>[];
    await expectLater(
      _Recording(calls, fail: true).installAndRestart(
        File('/tmp/p.deb'),
        closeDatabase: () async => calls.add('close'),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(calls, ['install']);
  });

  test('install rejects an unsupported package format', () async {
    await expectLater(
      const UpdateInstaller().install(File('/tmp/p.zip')),
      throwsA(isA<FileSystemException>()),
    );
  });
}

class _Recording extends UpdateInstaller {
  _Recording(this.calls, {this.fail = false});

  final List<String> calls;
  final bool fail;

  @override
  Future<void> install(File file) async {
    calls.add('install');
    if (fail) throw const FileSystemException('x');
  }

  @override
  Future<void> restart() async => calls.add('restart');
}
