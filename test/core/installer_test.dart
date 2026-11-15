import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/app_shutdown.dart';
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

  test(
    'SPEC-038 R8: cancelling the download deletes the partial file',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final data = List<int>.filled(200000, 7);
      server.listen((req) async {
        req.response.contentLength = data.length * 2;
        req.response.add(data);
        await req.response.flush();
        // Never sends the rest.
      });
      final root = await Directory.systemTemp.createTemp('inst-test-');
      addTearDown(() => root.delete(recursive: true));

      final partial = Completer<void>();
      final sub = UpdateInstaller(tempRoot: root, skipUrlCheck: true)
          .download(
            ReleaseAsset(
              name: 'p.deb',
              url: 'http://127.0.0.1:${server.port}/p.deb',
            ),
          )
          .listen((p) {
            if (p.received > 0 && !partial.isCompleted) partial.complete();
          });
      await partial.future;
      expect(root.listSync(), hasLength(1));
      await sub.cancel();
      expect(root.listSync(), isEmpty);
    },
  );

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

  group('SPEC-070 · installAndRestart', () {
    test('R1, R2, R5 · installs, starts the launcher, records the version, '
        'stops like the window and exits, each step on the log', () async {
      final calls = <String>[];
      final installer = _Recording(calls);
      await installer.installAndRestart(
        File('/tmp/p.tar.gz'),
        version: '0.17.0',
        shutdown: _shutdown(calls),
        markInstalled: () async => calls.add('mark'),
        onInstalled: () => calls.add('onInstalled'),
      );
      expect(calls, [
        'install',
        'mark',
        'onInstalled',
        'launcher',
        'stopWork',
        'closeDatabase',
        'exit 0',
      ]);
      expect(installer.lines, [
        'atualização: instalado',
        'atualização: lançador iniciado',
        'atualização: encerrando',
        matches(RegExp(r'^atualização: banco fechado em \d+ ms$')),
        'atualização: saindo',
      ]);
      expect(installer.launched.single, containsAllInOrder(['setsid', 'sh']));
      expect(installer.launched.single, contains('/home/u/app/promptorium'));
    });

    test(
      'R2 · a database that does not close in 3 s does not hold the exit',
      () {
        fakeAsync((async) {
          final calls = <String>[];
          final installer = _Recording(calls);
          unawaited(
            installer.installAndRestart(
              File('/tmp/p.tar.gz'),
              version: '0.17.0',
              shutdown: _shutdown(calls, database: Completer<void>().future),
            ),
          );
          async.elapse(const Duration(milliseconds: 2900));
          expect(calls, isNot(contains('exit 0')));
          async.elapse(const Duration(milliseconds: 200));
          expect(calls.last, 'exit 0');
          expect(installer.lines, [
            'atualização: instalado',
            'atualização: lançador iniciado',
            'atualização: encerrando',
            'atualização: o banco não fechou em 3 s; saindo assim mesmo',
            'atualização: saindo',
          ]);
          expect(calls, isNot(contains('kill')));
        });
      },
    );

    test('R2, R9 · still alive 15 s after the request, the process is '
        'killed', () {
      fakeAsync((async) {
        final calls = <String>[];
        final installer = _Recording(calls);
        unawaited(
          installer.installAndRestart(
            File('/tmp/p.tar.gz'),
            version: '0.17.0',
            // Sessions that never stop and an exit that doesn't end.
            shutdown: _shutdown(calls, work: Completer<void>().future),
          ),
        );
        async.elapse(const Duration(milliseconds: 14900));
        expect(calls, isNot(contains('kill')));
        async.elapse(const Duration(milliseconds: 200));
        expect(calls.last, 'kill');
        expect(
          installer.lines.last,
          'atualização: ainda aberto 15 s depois; saindo à força',
        );
      });
    });

    test('R4, R5 · without the launcher nothing is closed and the app stays '
        'open', () async {
      final calls = <String>[];
      final installer = _Recording(calls, launcherError: 'setsid: não há');
      await expectLater(
        installer.installAndRestart(
          File('/tmp/p.tar.gz'),
          version: '0.17.0',
          shutdown: _shutdown(calls),
          markInstalled: () async => calls.add('mark'),
        ),
        throwsA(isA<RelaunchFailed>()),
      );
      // The version is recorded: opening the app by hand says so (R6).
      expect(calls, ['install', 'mark']);
      expect(installer.lines, [
        'atualização: instalado',
        startsWith('atualização: o lançador não iniciou: '),
      ]);
    });

    test('a failed install neither starts the launcher nor closes', () async {
      final calls = <String>[];
      await expectLater(
        _Recording(calls, fail: true).installAndRestart(
          File('/tmp/p.deb'),
          version: '0.17.0',
          shutdown: _shutdown(calls),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(calls, ['install']);
    });
  });

  group('SPEC-070 R3 · the launcher', () {
    test('opens the copy that was updated: /opt for the .deb, this one for '
        'the .tar.gz', () {
      const installer = UpdateInstaller(executable: '/home/u/app/promptorium');
      expect(
        installer.relaunchExecutable(File('/tmp/promptorium_1_amd64.deb')),
        '/opt/promptorium/promptorium',
      );
      expect(
        installer.relaunchExecutable(
          File('/tmp/promptorium-1-linux-x64.tar.gz'),
        ),
        '/home/u/app/promptorium',
      );
    });

    test('inherits the environment without the PROMPTORIUM_* variables', () {
      expect(
        UpdateInstaller.relaunchEnvironment({
          'HOME': '/home/u',
          'XDG_DATA_HOME': '/d',
          'PROMPTORIUM_QUADROS': '1',
        }),
        {'HOME': '/home/u', 'XDG_DATA_HOME': '/d'},
      );
    });

    test('a session of its own, named promptorium-update', () {
      final cmd = const UpdateInstaller().relaunchCommand(42, '/x/promptorium');
      expect(cmd.take(3), ['setsid', 'sh', '-c']);
      expect(cmd.sublist(4), [
        'promptorium-update',
        '42',
        '/x/promptorium',
        '',
        '',
        '',
        '',
        '300',
      ]);
    });

    test(
      'waits for the old process to end, then opens the executable',
      () async {
        final dir = await Directory.systemTemp.createTemp('relaunch');
        addTearDown(() => dir.delete(recursive: true));
        final opened = File('${dir.path}/opened');
        final exe = File('${dir.path}/promptorium')
          ..writeAsStringSync('#!/bin/sh\ndate +%s%N > "${opened.path}"\n');
        await Process.run('chmod', ['+x', exe.path]);
        final old = await Process.start('sleep', ['30']);
        final cmd = const UpdateInstaller().relaunchCommand(
          old.pid,
          exe.path,
          version: '0.17.0',
        );
        final launcher = await Process.start(cmd.first, cmd.sublist(1));
        await Future<void>.delayed(const Duration(milliseconds: 600));
        expect(opened.existsSync(), isFalse, reason: 'the old one is alive');
        final killedAt = DateTime.now().microsecondsSinceEpoch * 1000;
        old.kill(ProcessSignal.sigkill);
        await old.exitCode;
        expect(await launcher.exitCode.timeout(const Duration(seconds: 5)), 0);
        expect(
          int.parse(opened.readAsStringSync().trim()),
          greaterThan(killedAt),
        );
      },
    );

    test('R3 · after the limit it ends the old process, then opens', () async {
      final dir = await Directory.systemTemp.createTemp('relaunch');
      addTearDown(() => dir.delete(recursive: true));
      final opened = File('${dir.path}/opened');
      final exe = File('${dir.path}/promptorium')
        ..writeAsStringSync('#!/bin/sh\ntouch "${opened.path}"\n');
      await Process.run('chmod', ['+x', exe.path]);
      final old = await Process.start('sleep', ['30']);
      addTearDown(() => old.kill(ProcessSignal.sigkill));
      final cmd = const UpdateInstaller().relaunchCommand(old.pid, exe.path);
      // Three tenths instead of 30 s.
      cmd[cmd.length - 1] = '3';
      final launcher = await Process.start(cmd.first, cmd.sublist(1));
      expect(await launcher.exitCode.timeout(const Duration(seconds: 8)), 0);
      expect(await old.exitCode.timeout(const Duration(seconds: 1)), isNot(0));
      expect(opened.existsSync(), isTrue);
    });

    test('R11, R12 · puts the staged copy in place, keeps the old one as '
        '.prev and deletes the download', () async {
      final root = await Directory.systemTemp.createTemp('relaunch');
      addTearDown(() => root.delete(recursive: true));
      final app = Directory('${root.path}/app')..createSync();
      File('${app.path}/promptorium').writeAsStringSync('#!/bin/sh\n');
      File('${app.path}/old.txt').writeAsStringSync('old');
      final next = Directory('${root.path}/app.next')..createSync();
      final opened = File('${root.path}/opened');
      File('${next.path}/promptorium').writeAsStringSync(
        '#!/bin/sh\ncat "\$(dirname "\$0")/new.txt" > "${opened.path}"\n',
      );
      File('${next.path}/new.txt').writeAsStringSync('new');
      await Process.run('chmod', ['+x', '${next.path}/promptorium']);
      final dl = Directory('${root.path}/promptorium-update-x')..createSync();
      File('${dl.path}/p.tar.gz').writeAsStringSync('');
      final cmd = const UpdateInstaller().relaunchCommand(
        999999999,
        '${app.path}/promptorium',
        appDir: app.path,
        staging: next.path,
        downloadDir: dl.path,
      );
      final launcher = await Process.start(cmd.first, cmd.sublist(1));
      expect(await launcher.exitCode.timeout(const Duration(seconds: 5)), 0);
      expect(opened.readAsStringSync(), 'new');
      expect(File('${app.path}/old.txt').existsSync(), isFalse);
      expect(File('${root.path}/app.prev/old.txt').readAsStringSync(), 'old');
      expect(next.existsSync(), isFalse);
      expect(dl.existsSync(), isFalse);
    });

    test('R8 · the new copy has an output: without systemd-cat, '
        'promptorium.log', () async {
      final root = await Directory.systemTemp.createTemp('relaunch');
      addTearDown(() => root.delete(recursive: true));
      // A PATH with the tools of the script, but no systemd-cat or logger.
      final bin = Directory('${root.path}/bin')..createSync();
      for (final tool in ['sh', 'sleep', 'mv', 'rm', 'mkdir', 'setsid']) {
        final which = (await Process.run('which', [tool])).stdout as String;
        Link('${bin.path}/$tool').createSync(which.trim());
      }
      final exe = File('${root.path}/promptorium')
        ..writeAsStringSync('#!/bin/sh\necho "olá do app"\necho erro >&2\n');
      await Process.run('chmod', ['+x', exe.path]);
      final cmd = const UpdateInstaller().relaunchCommand(999999999, exe.path);
      final launcher = await Process.start(
        '${bin.path}/setsid',
        cmd.sublist(1),
        environment: {'PATH': bin.path, 'XDG_STATE_HOME': '${root.path}/st'},
        includeParentEnvironment: false,
        mode: ProcessStartMode.detached,
      );
      expect(launcher.pid, greaterThan(0));
      final log = File('${root.path}/st/promptorium/promptorium.log');
      for (var i = 0; i < 50 && !log.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(log.readAsStringSync(), 'olá do app\nerro\n');
    });
  });

  group('SPEC-070 R11 · the .tar.gz beside this copy', () {
    Future<(Directory, File)> fixture({bool withExe = true}) async {
      final root = await Directory.systemTemp.createTemp('stage');
      addTearDown(() => root.delete(recursive: true));
      final app = Directory('${root.path}/app')..createSync();
      File('${app.path}/promptorium').writeAsStringSync('velho');
      final src = Directory('${root.path}/src/promptorium-1.0.0')
        ..createSync(recursive: true);
      if (withExe) File('${src.path}/promptorium').writeAsStringSync('novo');
      File('${src.path}/lib.so').writeAsStringSync('so');
      final pkg = File('${root.path}/promptorium-1.0.0-linux-x64.tar.gz');
      await Process.run('tar', [
        '-czf',
        pkg.path,
        '-C',
        '${root.path}/src',
        'promptorium-1.0.0',
      ]);
      return (app, pkg);
    }

    test('extracts into <app>.next and leaves the open copy alone', () async {
      final (app, pkg) = await fixture();
      final installer = UpdateInstaller(
        executable: '${app.path}/promptorium',
      );
      await installer.install(pkg);
      expect(File('${app.path}/promptorium').readAsStringSync(), 'velho');
      expect(installer.stagingDir, '${app.path}.next');
      expect(
        File('${installer.stagingDir}/promptorium').readAsStringSync(),
        'novo',
      );

      // R4: without the launcher the swap happens here.
      await installer.applyStaged();
      expect(File('${app.path}/promptorium').readAsStringSync(), 'novo');
      expect(
        File('${installer.previousDir}/promptorium').readAsStringSync(),
        'velho',
      );
      expect(Directory(installer.stagingDir).existsSync(), isFalse);
    });

    test('a package without the executable fails and leaves nothing behind',
        () async {
      final (app, pkg) = await fixture(withExe: false);
      final installer = UpdateInstaller(
        executable: '${app.path}/promptorium',
      );
      await expectLater(
        installer.install(pkg),
        throwsA(isA<ProcessException>()),
      );
      expect(Directory(installer.stagingDir).existsSync(), isFalse);
      expect(File('${app.path}/promptorium').readAsStringSync(), 'velho');
    });
  });

  test('R12 · a package outside a download directory is never deleted',
      () async {
    final calls = <String>[];
    final installer = _Recording(calls);
    await installer.installAndRestart(
      File('/tmp/p.tar.gz'),
      version: '0.17.0',
      shutdown: _shutdown(calls),
    );
    expect(installer.launched.single[10], '');
  });

  test('install rejects an unsupported package format', () async {
    await expectLater(
      const UpdateInstaller().install(File('/tmp/p.zip')),
      throwsA(isA<FileSystemException>()),
    );
  });
}

AppShutdown _shutdown(
  List<String> calls, {
  Future<void>? work,
  Future<void>? database,
}) => AppShutdown(
  stopWork: () async {
    calls.add('stopWork');
    await work;
  },
  closeDatabase: () async {
    calls.add('closeDatabase');
    await database;
  },
  destroyWindow: () async => calls.add('destroyWindow'),
  exitWith: (code) => calls.add('exit $code'),
  kill: () => calls.add('kill'),
);

class _Recording extends UpdateInstaller {
  _Recording(this.calls, {this.fail = false, this.launcherError})
    : super(executable: '/home/u/app/promptorium', logger: _lines.add);

  // The const constructor of [UpdateInstaller] takes a function: one list
  // per instance through a static that each test replaces.
  static var _lines = <String>[];

  final List<String> calls;
  final bool fail;
  final Object? launcherError;
  final launched = <List<String>>[];
  final List<String> lines = _lines = [];

  @override
  Future<void> install(File file) async {
    calls.add('install');
    if (fail) throw const FileSystemException('x');
  }

  @override
  Future<void> startLauncher(List<String> command) async {
    if (launcherError != null) {
      throw ProcessException('setsid', const [], '$launcherError');
    }
    calls.add('launcher');
    launched.add(command);
  }
}

class _Pkexec extends UpdateInstaller {
  const _Pkexec(this.pkexec, String exe) : super(executable: exe);

  final bool pkexec;

  @override
  Future<bool> hasPkexec() async => pkexec;
}
