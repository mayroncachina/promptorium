import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/memory/ai_memory_cli.dart';
import 'package:promptorium/core/memory/ai_memory_state.dart';

import 'fake_ai_memory.dart';

/// SPEC-098 T1: detection (R1, R2), the 5 s limit (R14) and the log (R13),
/// with a fake `ai-memory` on the test PATH and an isolated HOME.
void main() {
  late List<FakeAiMemory> fakes;
  setUp(() => fakes = []);
  tearDown(() async {
    for (final f in fakes) {
      await f.dispose();
    }
  });

  Future<FakeAiMemory> fake({
    String? version = '3.5.1',
    Map<String, String> replies = const {},
    int sleep = 0,
    bool inLocalBin = false,
  }) async {
    final f = await FakeAiMemory.create(
      version: version,
      replies: replies,
      sleep: sleep,
      inLocalBin: inLocalBin,
    );
    fakes.add(f);
    return f;
  }

  Future<HttpServer> healthz() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) {
      req.response.statusCode = req.uri.path == '/healthz' ? 200 : 404;
      req.response.close();
    });
    addTearDown(() => server.close(force: true));
    return server;
  }

  Future<AiMemoryDetection> detect(FakeAiMemory? f, String serverUrl) {
    final env = f?.environment() ?? {'PATH': '/usr/bin:/bin', 'HOME': '/x'};
    return detectAiMemory(
      executable: findAiMemory(env),
      cli: (e) => AiMemoryCli(executable: e, log: (_) {}),
      probe: defaultAiMemoryHttpProbe,
      serverUrl: serverUrl,
    );
  }

  group('findAiMemory (R1, R2)', () {
    test(
      'finds it on PATH and in ~/.local/bin, only by looking at the disk',
      () async {
        final onPath = await fake();
        expect(findAiMemory(onPath.environment()), onPath.executable);
        final local = await fake(inLocalBin: true);
        expect(
          findAiMemory({'PATH': '/usr/bin:/bin', 'HOME': local.home}),
          local.executable,
        );
        // Nothing ran: looking for it never starts the binary.
        expect(onPath.calls, isEmpty);
        expect(local.calls, isEmpty);
      },
    );

    test('a file without the execute bit or a missing one is "não '
        'instalado"', () async {
      final f = await fake();
      await Process.run('chmod', ['-x', f.executable]);
      expect(findAiMemory(f.environment()), isNull);
      expect(findAiMemory({'PATH': '/usr/bin:/bin', 'HOME': f.home}), isNull);
    });
  });

  group('the four states (R1): only --version and /healthz, never installs '
      'nor starts anything', () {
    test('ausente', () async {
      final d = await detect(null, 'http://127.0.0.1:1');
      expect(d.status, AiMemoryStatus.notInstalled);
      expect(d.fixCommand, contains('install.sh'));
      expect(d.fixCommand, contains('ai-memory setup'));
    });

    test('versão 3.0.0 = versão antiga, with "ai-memory upgrade"', () async {
      final f = await fake(version: '3.0.0');
      final server = await healthz();
      final d = await detect(f, 'http://127.0.0.1:${server.port}');
      expect(d.status, AiMemoryStatus.outdated);
      expect(d.version, '3.0.0');
      expect(d.fixCommand, aiMemoryUpgradeCommand);
      expect(d.serverUp, isTrue);
      expect(f.calls.map((c) => c.split('\t').first), ['--version']);
    });

    test('servidor parado, with "systemctl --user start ai-memory"', () async {
      final f = await fake();
      // A port nobody listens on.
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      await probe.close();
      final d = await detect(f, 'http://127.0.0.1:$port');
      expect(d.status, AiMemoryStatus.serverDown);
      expect(d.fixCommand, aiMemoryStartCommand);
      expect(d.message, contains('/healthz não respondeu'));
      expect(d.message, contains('O app não inicia o serviço'));
      expect(f.calls.map((c) => c.split('\t').first), ['--version']);
    });

    test('conectado', () async {
      final f = await fake();
      final server = await healthz();
      final d = await detect(f, 'http://127.0.0.1:${server.port}');
      expect(d.status, AiMemoryStatus.connected);
      expect(d.version, '3.5.1');
      expect(d.title, 'ai-memory 3.5.1');
      expect(d.serverHost, '127.0.0.1:${server.port}');
      expect(d.fixCommand, isNull);
      expect(f.calls.map((c) => c.split('\t').first), ['--version']);
    });

    test('a binary that does not answer --version counts as missing', () async {
      final f = await fake(version: null);
      final d = await detect(f, 'http://127.0.0.1:1');
      expect(d.status, AiMemoryStatus.notInstalled);
    });
  });

  test('server address: AI_MEMORY_SERVER_URL, else the saved one, else the '
      'default', () {
    expect(aiMemoryServerUrl({}, null), aiMemoryDefaultServer);
    expect(aiMemoryServerUrl({}, 'http://h:1/'), 'http://h:1');
    expect(
      aiMemoryServerUrl({'AI_MEMORY_SERVER_URL': 'http://e:2'}, 'http://h:1'),
      'http://e:2',
    );
  });

  group('call (P2, R13, R14)', () {
    test('runs `ai-memory call <tool> <json>` in the workspace and decodes '
        'the answer; the log keeps only tool, time and exit code', () async {
      final f = await fake(
        replies: {'call memory_handoff_list': handoffListJson()},
      );
      final logs = <String>[];
      final cli = AiMemoryCli(executable: f.executable, log: logs.add);
      final cwd = Directory.systemTemp.resolveSymbolicLinksSync();
      final out = await cli.call('memory_handoff_list', {}, cwd: cwd);
      expect(out, isA<Map>());
      final call = f.calls.single.split('\t');
      expect(call.first, 'call memory_handoff_list {}');
      expect(call.last, cwd);
      expect(logs.single, startsWith('ai-memory: call memory_handoff_list · '));
      expect(logs.single, endsWith('saída 0'));
      expect(logs.single, isNot(contains('Parser')));
    });

    test('a call slower than 5 s becomes a status, without hanging', () async {
      final f = await fake(
        replies: {'call memory_handoff_list': '{}'},
        sleep: 20,
      );
      final logs = <String>[];
      final cli = AiMemoryCli(executable: f.executable, log: logs.add);
      final watch = Stopwatch()..start();
      await expectLater(
        cli.call('memory_handoff_list', {}, cwd: f.root.path),
        throwsA(
          isA<AiMemoryException>()
              .having((e) => e.timedOut, 'timedOut', isTrue)
              .having((e) => e.message, 'message', 'tempo esgotado em 5 s'),
        ),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 12)));
      expect(logs.single, contains('tempo esgotado em 5 s'));
    }, timeout: const Timeout(Duration(seconds: 40)));

    test('an error exit becomes a message with the exit code only', () async {
      final f = await fake();
      final cli = AiMemoryCli(executable: f.executable, log: (_) {});
      await expectLater(
        cli.call('memory_handoff_cancel', {
          'handoff_id': 'x',
        }, cwd: f.root.path),
        throwsA(
          isA<AiMemoryException>().having(
            (e) => e.message,
            'message',
            'o ai-memory respondeu com erro (saída 2)',
          ),
        ),
      );
    });
  });

  test('installer output hides tokens before the app shows it (R13)', () {
    final out = redactAiMemoryOutput(
      'wrote ~/.claude.json\n'
      'Authorization: Bearer abcdefghijklmnop1234\n'
      'token = sk_live_abcdefghijklmnop\n'
      'AI_MEMORY_AUTH_TOKEN="abcdefghijklmnopqrstu"',
    );
    expect(out, contains('wrote ~/.claude.json'));
    expect(out, isNot(contains('abcdefghijklmnop1234')));
    expect(out, isNot(contains('sk_live_abcdefghijklmnop')));
    expect(out, isNot(contains('abcdefghijklmnopqrstu')));
  });

  test('semver comparison', () {
    expect(compareSemver('3.0.2', aiMemoryMinVersion), lessThan(0));
    expect(compareSemver('3.1.0', aiMemoryMinVersion), 0);
    expect(compareSemver('3.10.0', '3.9.9'), greaterThan(0));
    expect(parseAiMemoryVersion('ai-memory 3.5.1\n'), '3.5.1');
  });
}
