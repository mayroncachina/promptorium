import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
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

  group('prefersDeb: the package of the running copy', () {
    test('.deb only for the copy in /opt/promptorium with pkexec', () async {
      expect(
        await _Pkexec(true, '/opt/promptorium/promptorium').prefersDeb(),
        isTrue,
      );
      expect(
        await _Pkexec(false, '/opt/promptorium/promptorium').prefersDeb(),
        isFalse,
      );
      // Extracted from the .tar.gz: the update goes over this copy.
      expect(
        await _Pkexec(
          true,
          '/home/u/.local/share/promptorium/app/promptorium',
        ).prefersDeb(),
        isFalse,
      );
    });
  });

  group('R13 · validação do download', () {
    const base = 'https://github.com/o/p/releases/download/v1';
    ReleaseAsset ok([String n = 'promptorium_1.0.0_amd64.deb']) =>
        ReleaseAsset(name: n, url: '$base/$n');

    Future<Object?> abort(ReleaseAsset a, Directory root) async {
      try {
        await UpdateInstaller(tempRoot: root).download(a).toList();
      } catch (e) {
        return e;
      }
      return null;
    }

    late Directory root;
    setUp(() async => root = await Directory.systemTemp.createTemp('r13-'));
    tearDown(() => root.delete(recursive: true));

    test('aceita os nomes e a URL esperados', () {
      validateAsset(ok());
      validateAsset(ok('promptorium-1.0.0-linux-x64.tar.gz'));
    });

    test('http://, host fora de github.com e URL fora do padrão abortam', () {
      for (final url in [
        'http://github.com/o/p/releases/download/v1/promptorium_1.0.0_amd64.deb',
        'https://evil.com/o/p/releases/download/v1/promptorium_1.0.0_amd64.deb',
        'https://github.com.evil.com/o/p/releases/download/v1/promptorium_1.0.0_amd64.deb',
        'https://github.com/o/p/raw/v1/promptorium_1.0.0_amd64.deb',
        'https://github.com/o/p/releases/download/v1/outro.deb',
      ]) {
        expect(
          () => validateAsset(
            ReleaseAsset(name: 'promptorium_1.0.0_amd64.deb', url: url),
          ),
          throwsA(isA<FileSystemException>()),
          reason: url,
        );
      }
    });

    test('nome fora do padrão aborta antes de qualquer arquivo', () async {
      for (final n in ['p.deb', 'promptorium.sh', '../x_1_amd64.deb']) {
        expect(await abort(ok(n), root), isA<FileSystemException>(), reason: n);
      }
      expect(root.listSync(), isEmpty);
    });

    Future<HttpServer> serve(Map<String, List<int>> files) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((req) async {
        final data = files[req.uri.path];
        if (data == null) {
          req.response.statusCode = 404;
        } else {
          req.response.add(data);
        }
        await req.response.close();
      });
      return server;
    }

    Future<Object?> run(
      HttpServer s,
      ReleaseAsset a, {
      List<ReleaseAsset> siblings = const [],
    }) async {
      try {
        await UpdateInstaller(
          tempRoot: root,
          skipUrlCheck: true,
        ).download(a, releaseAssets: siblings).toList();
      } catch (e) {
        return e;
      }
      return null;
    }

    test('tamanho divergente aborta e apaga o download', () async {
      final data = utf8.encode('conteudo');
      final s = await serve({'/p.deb': data});
      final a = ReleaseAsset(
        name: 'p.deb',
        url: 'http://127.0.0.1:${s.port}/p.deb',
        size: data.length + 1,
      );
      expect(await run(s, a), isA<FileSystemException>());
      expect(root.listSync(), isEmpty);
    });

    test('.sha256 divergente aborta; correto passa', () async {
      final data = utf8.encode('conteudo');
      final good = sha256.convert(data).toString();
      final s = await serve({
        '/p.deb': data,
        '/bad': utf8.encode('${'0' * 64}  p.deb'),
        '/good': utf8.encode('$good  p.deb\n'),
      });
      final a = ReleaseAsset(
        name: 'p.deb',
        url: 'http://127.0.0.1:${s.port}/p.deb',
        size: data.length,
      );
      ReleaseAsset sum(String path) => ReleaseAsset(
        name: 'p.deb.sha256',
        url: 'http://127.0.0.1:${s.port}/$path',
      );
      expect(
        await run(s, a, siblings: [sum('bad')]),
        isA<FileSystemException>(),
      );
      expect(root.listSync(), isEmpty);
      expect(await run(s, a, siblings: [sum('good')]), isNull);
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
    final events = await UpdateInstaller(
      tempRoot: root,
      skipUrlCheck: true,
    ).download(asset).toList();

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

class _Pkexec extends UpdateInstaller {
  const _Pkexec(this.pkexec, String exe) : super(executable: exe);

  final bool pkexec;

  @override
  Future<bool> hasPkexec() async => pkexec;
}
