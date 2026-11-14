import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/dev/dev_server.dart';
import 'package:promptorium/features/project/project_config.dart';

class FakeProcess implements Process {
  FakeProcess(this.pid);

  @override
  final int pid;
  final out = StreamController<List<int>>();
  final err = StreamController<List<int>>();
  final _exit = Completer<int>();

  void say(String line) => out.add(utf8.encode('$line\n'));
  void exit(int code) {
    if (!_exit.isCompleted) _exit.complete(code);
  }

  @override
  Stream<List<int>> get stdout => out.stream;
  @override
  Stream<List<int>> get stderr => err.stream;
  @override
  Future<int> get exitCode => _exit.future;
  @override
  IOSink get stdin => throw UnimplementedError();
  final kills = <ProcessSignal>[];

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    kills.add(signal);
    exit(-15);
    return true;
  }
}

/// `/proc` of the tests: groups and environments by hand.
class FakeProcInfo extends ProcInfo {
  FakeProcInfo();

  final groups = <int, List<int>>{};
  final env = <int, Map<String, String>>{};
  final cmd = <int, String>{};

  @override
  List<int> group(int pgid) => groups[pgid] ?? const [];
  @override
  int? pgrp(int pid) {
    for (final MapEntry(:key, :value) in groups.entries) {
      if (value.contains(pid)) return key;
    }
    return null;
  }

  @override
  Map<String, String> environ(int pid) => env[pid] ?? const {};
  @override
  String? cmdline(int pid) => cmd[pid];
  @override
  String? cwd(int pid) => cmd.containsKey(pid) ? '/home/eu/loja-web' : null;
}

ProcessResult _ss(String out) => ProcessResult(1, 0, out, '');

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('dev_server_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('the log keeps the last 2.000 lines, searches and tails', () {
    final b = DevLogBuffer();
    for (var i = 0; i < 2100; i++) {
      b.add(DevLogLine('linha $i'));
    }
    expect(b.length, 2000);
    expect(b.lines.first.text, 'linha 100');
    expect(b.search('LINHA 2099').single.text, 'linha 2099');
    expect(b.tail(2), 'linha 2098\nlinha 2099');
  });

  test('parseSs reads the pid and name of the listener', () {
    const out =
        'LISTEN 0 511 127.0.0.1:4004 0.0.0.0:* '
        'users:(("node",pid=39120,fd=23))\n';
    final o = PortProbe.parseSs(out, 4004)!;
    expect(o.pid, 39120);
    expect(o.name, 'node');
    expect(PortProbe.parseSs(out, 4005), isNull);
    expect(PortProbe.parseSs('', 4004), isNull);
  });

  group('states', () {
    late FakeProcInfo proc;
    late List<(String, List<String>, Map<String, String>?, String?)> started;
    late FakeProcess process;
    late List<(int, ProcessSignal)> signals;
    var answers = false;
    var ssOut = '';

    DevServerRegistry registry() => DevServerRegistry(
      runDir: '${tmp.path}/run',
      proc: proc,
      appPid: 1,
      pollInterval: const Duration(milliseconds: 5),
      readyTimeout: const Duration(seconds: 2),
      stopGrace: const Duration(milliseconds: 200),
      freePort: () async => 5173,
      starter: (exe, args, {workingDirectory, environment}) async {
        started.add((exe, args, environment, workingDirectory));
        proc.groups[process.pid] = [process.pid];
        return process;
      },
      signal: (pgid, s) async {
        signals.add((pgid, s));
        proc.groups.remove(pgid);
        process.exit(-15);
      },
      probe: PortProbe(
        proc: proc,
        run: (exe, args) async => _ss(ssOut),
        http: (_) async => answers,
      ),
    );

    setUp(() {
      proc = FakeProcInfo();
      started = [];
      signals = [];
      process = FakeProcess(48211);
      answers = false;
      ssOut = '';
    });

    test('parado → iniciando → no ar when the port answers HTTP; Parar '
        'signals the group and goes back to parado', () async {
      final r = registry();
      final s = r.of('/wt/a');
      expect(s.status, DevServerStatus.stopped);
      final seen = <DevServerStatus>[];
      s.changes.listen((_) {
        if (seen.isEmpty || seen.last != s.status) seen.add(s.status);
      });
      await s.start(
        config: const DevServerConfig(command: 'npm run dev'),
        port: 4003,
        environment: const {'PROMPTORIUM_SPEC': 'SPEC-012'},
      );
      expect(s.status, DevServerStatus.starting);
      final (exe, args, env, cwd) = started.single;
      expect(exe, 'setsid');
      expect(args, ['sh', '-c', 'npm run dev']);
      expect(cwd, '/wt/a');
      expect(env!['PROMPTORIUM_PORT'], '4003');
      expect(env['PROMPTORIUM_SPEC'], 'SPEC-012');
      expect(s.pgid, 48211);
      expect(File('${tmp.path}/run/48211.json').existsSync(), isTrue);

      answers = true;
      await pumpUntil(() => s.status == DevServerStatus.running);
      expect(s.startedAt, isNotNull);
      expect(s.url.toString(), 'http://localhost:4003/');

      await s.stop();
      expect(signals.first, (48211, ProcessSignal.sigterm));
      expect(s.status, DevServerStatus.stopped);
      expect(File('${tmp.path}/run/48211.json').existsSync(), isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(seen, [
        DevServerStatus.starting,
        DevServerStatus.running,
        DevServerStatus.stopped,
      ]);
    });

    test('pronto: a text of the log; without a port the app picks a free '
        'one (P4)', () async {
      final s = registry().of('/wt/a');
      await s.start(
        config: const DevServerConfig(command: 'vite', readyText: 'ready in'),
      );
      expect(s.port, 5173);
      expect(started.single.$3!['PROMPTORIUM_PORT'], '5173');
      answers = true; // ignored: the condition is the text
      process.say('VITE v6.2.1  ready in 412 ms');
      await pumpUntil(() => s.status == DevServerStatus.running);
      expect(s.logs.text, contains('ready in 412 ms'));
    });

    test('falhou when the command exits, with the code', () async {
      final s = registry().of('/wt/a');
      await s.start(
        config: const DevServerConfig(command: 'npm run dev'),
        port: 4003,
      );
      process.err.add(utf8.encode('Error: Cannot find module vite\n'));
      process.exit(1);
      await pumpUntil(() => s.status == DevServerStatus.failed);
      expect(s.failure!.reason, 'o comando terminou (código 1)');
      expect(s.failure!.portTaken, isFalse);
      expect(s.logs.lines.any((l) => l.kind == DevLogKind.err), isTrue);
      expect(looksLikeError('Error: Cannot find module vite'), isTrue);
    });

    test('port taken by another process: nothing starts, PID and command '
        'shown, nothing is killed (R3)', () async {
      ssOut =
          'LISTEN 0 511 127.0.0.1:4004 0.0.0.0:* '
          'users:(("node",pid=39120,fd=23))\n';
      proc.groups[39120] = [39120];
      proc.cmd[39120] = 'vite --port 4004';
      final r = registry();
      final s = r.of('/wt/b');
      await s.start(
        config: const DevServerConfig(command: 'npm run dev'),
        port: 4004,
      );
      expect(started, isEmpty);
      expect(s.status, DevServerStatus.failed);
      expect(s.failure!.reason, 'porta 4004 ocupada');
      expect(s.failure!.owner!.pid, 39120);
      expect(s.failure!.owner!.command, 'vite --port 4004');
      expect(s.logs.text, contains('nada foi iniciado nem encerrado'));

      await s.stop();
      await r.stopAll();
      expect(signals, isEmpty);

      // "Usar o que está no ar": up without a process, never killed.
      s.useRunning(4004);
      expect(s.status, DevServerStatus.running);
      expect(s.external, isTrue);
      await s.stop();
      expect(signals, isEmpty);
      expect(s.status, DevServerStatus.stopped);
    });

    test('port taken by the server the app started for this worktree is '
        'reused (R3)', () async {
      ssOut =
          'LISTEN 0 511 127.0.0.1:4003 0.0.0.0:* '
          'users:(("node",pid=31878,fd=23))\n';
      proc.groups[31877] = [31877, 31878];
      proc.env[31877] = {'PROMPTORIUM_WORKTREE': '/wt/a'};
      final r = registry();
      await r.writeRecord(
        DevServerRecord(
          pid: 31877,
          pgid: 31877,
          worktree: '/wt/a',
          port: 4003,
          command: 'npm run dev',
          startedAt: DateTime(2026),
          appPid: 99,
        ),
      );
      final s = r.of('/wt/a');
      await s.start(
        config: const DevServerConfig(command: 'npm run dev'),
        port: 4003,
      );
      expect(started, isEmpty);
      expect(s.status, DevServerStatus.running);
      expect(s.adopted, isTrue);
      expect(s.pgid, 31877);
    });
  });

  group('records of a run that crashed (R5)', () {
    test('found when still alive, ended with TERM to the group; dead ones '
        'are cleaned; a reused PID is never killed', () async {
      final proc = FakeProcInfo()
        ..groups[31877] = [31877, 31880]
        ..env[31880] = {'PROMPTORIUM_WORKTREE': '/wt/busca'}
        ..groups[40000] = [40000]
        ..env[40000] = {'PROMPTORIUM_WORKTREE': '/outro'};
      final signals = <(int, ProcessSignal)>[];
      final r = DevServerRegistry(
        runDir: '${tmp.path}/run',
        proc: proc,
        appPid: 1,
        stopGrace: const Duration(milliseconds: 100),
        signal: (pgid, s) async {
          signals.add((pgid, s));
          proc.groups.remove(pgid);
        },
      );
      DevServerRecord rec(int pid, String wt) => DevServerRecord(
        pid: pid,
        pgid: pid,
        worktree: wt,
        port: 4001,
        command: 'npm run dev',
        startedAt: DateTime(2026),
        appPid: 777,
      );
      await r.writeRecord(rec(31877, '/wt/busca'));
      await r.writeRecord(rec(40000, '/wt/velho')); // PID reused
      await r.writeRecord(rec(50000, '/wt/morto')); // gone

      final left = await r.leftovers();
      expect(left.map((x) => x.worktree), ['/wt/busca']);
      expect(File('${tmp.path}/run/50000.json').existsSync(), isFalse);
      expect(File('${tmp.path}/run/40000.json').existsSync(), isFalse);

      await r.endLeftover(left.single);
      expect(signals, [(31877, ProcessSignal.sigterm)]);
      expect(await r.leftovers(), isEmpty);
      expect(File('${tmp.path}/run/31877.json').existsSync(), isFalse);
    });

    test('"Deixar rodando" hides it for this run', () async {
      final proc = FakeProcInfo()
        ..groups[31877] = [31877]
        ..env[31877] = {'PROMPTORIUM_WORKTREE': '/wt/busca'};
      final r = DevServerRegistry(
        runDir: '${tmp.path}/run',
        proc: proc,
        appPid: 1,
      );
      await r.writeRecord(
        DevServerRecord(
          pid: 31877,
          pgid: 31877,
          worktree: '/wt/busca',
          port: 4001,
          command: 'x',
          startedAt: DateTime(2026),
          appPid: 2,
        ),
      );
      final left = await r.leftovers();
      r.dismissLeftover(left.single);
      expect(await r.leftovers(), isEmpty);
    });
  });

  test('Parar kills the whole group, children included (real processes, '
      'R5)', () async {
    if (!Platform.isLinux) return;
    final r = DevServerRegistry(
      runDir: '${tmp.path}/run',
      appPid: 1,
      stopGrace: const Duration(seconds: 5),
      probe: PortProbe(run: (e, a) async => _ss(''), http: (_) async => false),
    );
    final s = r.of(tmp.path);
    await s.start(
      config: const DevServerConfig(
        command: 'sleep 30 & sleep 31 & echo pronto; wait',
        readyText: 'pronto',
      ),
      port: 1,
    );
    await pumpUntil(() => s.status == DevServerStatus.running);
    final pgid = s.pgid!;
    const proc = ProcInfo();
    await pumpUntil(() => proc.group(pgid).length >= 3);
    final children = proc.group(pgid);
    expect(
      children.map(proc.cmdline).where((c) => c!.startsWith('sleep')),
      hasLength(2),
    );
    await s.stop();
    expect(proc.group(pgid), isEmpty);
    for (final p in children) {
      expect(Directory('/proc/$p').existsSync(), isFalse);
    }
    expect(s.status, DevServerStatus.stopped);
  });
}

Future<void> pumpUntil(
  bool Function() done, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('condição não aconteceu a tempo');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
