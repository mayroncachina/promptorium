import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/project/project_config.dart' show DevServerConfig;
import '../claude/claude_process.dart' show ProcessStarter;
import '../process/process_runner.dart';

/// Development server of a worktree (SPEC-051): the app starts the `dev:`
/// command in its own process group, follows the log, knows when it is up
/// and stops the whole group. Nothing here kills a process the app did not
/// start (R3).

enum DevServerStatus { stopped, starting, running, failed }

/// Who wrote a log line: the command (stdout / stderr) or the app.
enum DevLogKind { out, err, app }

@immutable
class DevLogLine {
  const DevLogLine(this.text, [this.kind = DevLogKind.out]);

  final String text;
  final DevLogKind kind;
}

/// The last [capacity] lines of the log (R4: 2.000).
class DevLogBuffer {
  DevLogBuffer({this.capacity = 2000});

  final int capacity;
  final _lines = ListQueue<DevLogLine>();

  int get length => _lines.length;
  List<DevLogLine> get lines => List.unmodifiable(_lines);

  void add(DevLogLine l) {
    _lines.add(l);
    while (_lines.length > capacity) {
      _lines.removeFirst();
    }
  }

  void clear() => _lines.clear();

  /// Lines with [query] (case-insensitive; empty = all).
  List<DevLogLine> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return lines;
    return [
      for (final l in _lines)
        if (l.text.toLowerCase().contains(q)) l,
    ];
  }

  /// The last [n] lines as text.
  String tail(int n) => _lines
      .skip(_lines.length > n ? _lines.length - n : 0)
      .map((l) => l.text)
      .join('\n');

  String get text => _lines.map((l) => l.text).join('\n');
}

/// Lines of a log that look like an error (R4: "Mandar erro para a sessão").
final _errorLine = RegExp(
  r'\b(error|erro|failed|exception|unhandled|cannot find|not found|ERR!)\b',
  caseSensitive: false,
);

bool looksLikeError(String line) => _errorLine.hasMatch(line);

/// The process listening on a port the app wanted (R3).
@immutable
class PortOwner {
  const PortOwner({this.pid, this.name, this.command, this.cwd});

  /// Null when `ss` does not show it (process of another user).
  final int? pid;
  final String? name;
  final String? command;
  final String? cwd;
}

/// Reads `/proc` (injected in tests).
class ProcInfo {
  const ProcInfo();

  /// Arguments joined by spaces; null when the process is gone.
  String? cmdline(int pid) {
    try {
      final f = File('/proc/$pid/cmdline');
      if (!f.existsSync()) return null;
      final raw = f.readAsStringSync();
      return raw.split('\x00').where((a) => a.isNotEmpty).join(' ');
    } catch (_) {
      return null;
    }
  }

  String? cwd(int pid) {
    try {
      return Link('/proc/$pid/cwd').targetSync();
    } catch (_) {
      return null;
    }
  }

  /// Process group (`/proc/<pid>/stat`, field 5).
  int? pgrp(int pid) {
    try {
      final stat = File('/proc/$pid/stat').readAsStringSync();
      final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
      return int.tryParse(fields[2]);
    } catch (_) {
      return null;
    }
  }

  Map<String, String> environ(int pid) {
    try {
      final raw = File('/proc/$pid/environ').readAsStringSync();
      return {
        for (final kv in raw.split('\x00'))
          if (kv.contains('='))
            kv.substring(0, kv.indexOf('=')): kv.substring(kv.indexOf('=') + 1),
      };
    } catch (_) {
      return const {};
    }
  }

  /// PIDs of the processes of group [pgid] (empty = the group is gone).
  List<int> group(int pgid) {
    final pids = <int>[];
    try {
      for (final e in Directory('/proc').listSync(followLinks: false)) {
        final pid = int.tryParse(
          e.uri.pathSegments.where((s) => s.isNotEmpty).last,
        );
        if (pid != null && pgrp(pid) == pgid) pids.add(pid);
      }
    } catch (_) {}
    return pids;
  }
}

/// Free / taken ports and "does it answer HTTP" (R3).
class PortProbe {
  PortProbe({
    ProcessRunner? run,
    this.proc = const ProcInfo(),
    Future<bool> Function(int port)? http,
  }) : _run = run ?? Process.run,
       _http = http ?? _httpAnswers;

  final ProcessRunner _run;
  final ProcInfo proc;
  final Future<bool> Function(int port) _http;

  /// Who listens on [port] (null = free). `ss -ltnp`; without `ss`, a bind
  /// on 127.0.0.1 tells whether it is free.
  Future<PortOwner?> owner(int port) async {
    try {
      final r = await _run('ss', ['-ltnpH', 'sport = :$port']);
      if (r.exitCode == 0) {
        final o = parseSs('${r.stdout}', port);
        if (o == null) return null;
        final pid = o.pid;
        return pid == null
            ? o
            : PortOwner(
                pid: pid,
                name: o.name,
                command: proc.cmdline(pid),
                cwd: proc.cwd(pid),
              );
      }
    } catch (_) {
      // No `ss`: bind below.
    }
    try {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      await s.close();
      return null;
    } catch (_) {
      return const PortOwner();
    }
  }

  /// The listener of [port] in the output of `ss -ltnp` (null = none).
  static PortOwner? parseSs(String out, int port) {
    for (final line in const LineSplitter().convert(out)) {
      final cols = line.trim().split(RegExp(r'\s+'));
      if (cols.length < 4 || cols.first == 'State') continue;
      if (!cols.any((c) => c.endsWith(':$port'))) continue;
      final m = RegExp(r'users:\(\("([^"]*)",pid=(\d+)').firstMatch(line);
      return PortOwner(
        name: m?.group(1),
        pid: m == null ? null : int.parse(m.group(2)!),
      );
    }
    return null;
  }

  Future<bool> respondsHttp(int port) => _http(port);

  static Future<bool> _httpAnswers(int port) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    try {
      final req = await client.getUrl(Uri.parse('http://localhost:$port/'));
      final res = await req.close().timeout(const Duration(seconds: 2));
      await res.drain<void>();
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// A port nobody listens on now (P4: `dev:` without `porta-base`).
  static Future<int> freePort() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = s.port;
    await s.close();
    return port;
  }
}

/// Sends [signal] to every process of group [pgid].
typedef GroupSignal = Future<void> Function(int pgid, ProcessSignal signal);

Future<void> killGroup(int pgid, ProcessSignal signal) async {
  try {
    await Process.run('kill', [
      '-s',
      signal == ProcessSignal.sigkill ? 'KILL' : 'TERM',
      '--',
      '-$pgid',
    ]);
  } catch (e) {
    debugPrint('kill -$pgid: $e');
  }
}

/// `~/.promptorium/run/dev/<pid>.json`: a server the app started (R5).
@immutable
class DevServerRecord {
  const DevServerRecord({
    required this.pid,
    required this.pgid,
    required this.worktree,
    required this.port,
    required this.command,
    required this.startedAt,
    required this.appPid,
  });

  final int pid, pgid, port, appPid;
  final String worktree, command;
  final DateTime startedAt;

  Map<String, Object> toJson() => {
    'pid': pid,
    'pgid': pgid,
    'worktree': worktree,
    'port': port,
    'command': command,
    'startedAt': startedAt.toIso8601String(),
    'appPid': appPid,
  };

  static DevServerRecord? fromJson(Object? j) {
    if (j is! Map) return null;
    final pid = j['pid'],
        pgid = j['pgid'],
        port = j['port'],
        wt = j['worktree'];
    if (pid is! int || pgid is! int || port is! int || wt is! String) {
      return null;
    }
    return DevServerRecord(
      pid: pid,
      pgid: pgid,
      worktree: wt,
      port: port,
      command: '${j['command'] ?? ''}',
      startedAt: DateTime.tryParse('${j['startedAt']}') ?? DateTime.now(),
      appPid: j['appPid'] is int ? j['appPid'] as int : 0,
    );
  }
}

/// Why the server is not up (R2 "Falhou", R3).
@immutable
class DevServerFailure {
  const DevServerFailure(this.reason, {this.owner, this.port});

  /// Short, for the header ("porta 4004 ocupada").
  final String reason;

  /// Set when the port is taken by a process the app did not start.
  final PortOwner? owner;
  final int? port;

  bool get portTaken => owner != null;
}

/// One worktree's server (one per worktree, see [DevServerRegistry]).
class DevServer {
  DevServer._(this.worktree, this._registry);

  final String worktree;
  final DevServerRegistry _registry;

  final logs = DevLogBuffer();
  final _changes = StreamController<void>.broadcast();

  DevServerStatus _status = DevServerStatus.stopped;
  DevServerStatus get status => _status;

  int? port;
  int? pid;
  int? pgid;
  String? command;

  /// Page of the preview (`caminho:`).
  String path = '/';
  DateTime? startedAt;
  DevServerFailure? failure;

  /// Started by an earlier run of the app and taken over (R3).
  bool adopted = false;

  /// "Usar o que está no ar": a server the app did not start (never killed).
  bool external = false;

  Process? _process;
  bool _stopping = false;
  Timer? _poll;
  int _run = 0;

  /// Fires on every change of state or log.
  Stream<void> get changes => _changes.stream;

  bool get isUp => _status == DevServerStatus.running;
  bool get isBusy =>
      _status == DevServerStatus.starting || _status == DevServerStatus.running;

  Uri? get url =>
      port == null ? null : Uri.parse('http://localhost:$port$path');

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  void _set(DevServerStatus s, {DevServerFailure? failure}) {
    _status = s;
    this.failure = failure;
    _notify();
  }

  void log(String text, [DevLogKind kind = DevLogKind.app]) {
    for (final l in const LineSplitter().convert(text)) {
      logs.add(
        DevLogLine(kind == DevLogKind.app ? 'promptorium: $l' : l, kind),
      );
    }
    _notify();
  }

  void _reset() {
    pid = null;
    pgid = null;
    startedAt = null;
    adopted = false;
    external = false;
    _process = null;
    _poll?.cancel();
  }

  /// Starts [config] on [port] (null = a free port, P4) with [environment]
  /// (`worktreeEnvironment`, without the port). Checks the port first (R3).
  Future<void> start({
    required DevServerConfig config,
    int? port,
    Map<String, String> environment = const {},
  }) async {
    if (isBusy) return;
    final run = ++_run;
    _reset();
    logs.clear();
    command = config.command;
    path = config.path;
    final p = port ?? await _registry.pickPort();
    this.port = p;
    _set(DevServerStatus.starting);
    log('conferindo a porta $p antes de subir');
    final owner = await _registry.probe.owner(p);
    if (run != _run) return;
    if (owner != null) {
      final mine = await _registry.recordOwning(worktree, owner);
      if (mine != null) {
        pid = mine.pid;
        pgid = mine.pgid;
        adopted = true;
        startedAt = mine.startedAt;
        log(
          'a porta $p é do servidor que o app subiu para este worktree (PID ${mine.pid}) · reaproveitado',
        );
        _set(DevServerStatus.running);
        _watchGroup(run);
        return;
      }
      log('127.0.0.1:$p em uso');
      if (owner.pid != null) {
        log(
          '  users:(("${owner.name ?? '?'}",pid=${owner.pid}))',
          DevLogKind.out,
        );
      }
      if (owner.command != null) {
        log(
          '  cmd: ${owner.command}${owner.cwd == null ? '' : ' (cwd ${owner.cwd})'}',
          DevLogKind.out,
        );
      }
      log(
        'o processo não foi subido pelo app · nada foi iniciado nem encerrado',
        DevLogKind.err,
      );
      _set(
        DevServerStatus.failed,
        failure: DevServerFailure('porta $p ocupada', owner: owner, port: p),
      );
      return;
    }
    final env = {
      ...environment,
      'PROMPTORIUM_PORT': '$p',
      'PROMPTORIUM_WORKTREE': worktree,
    };
    final Process proc;
    try {
      proc = await _registry.starter(
        'setsid',
        ['sh', '-c', config.command],
        workingDirectory: worktree,
        environment: env,
      );
    } catch (e) {
      log('não deu para rodar o comando: $e', DevLogKind.err);
      _set(
        DevServerStatus.failed,
        failure: const DevServerFailure('o comando não rodou'),
      );
      return;
    }
    _process = proc;
    // Dart's children are not group leaders, so `setsid` does not fork:
    // the shell is the leader of the new group (pgid = pid).
    pid = proc.pid;
    pgid = proc.pid;
    logs.add(DevLogLine('\$ ${config.command}'));
    final record = DevServerRecord(
      pid: proc.pid,
      pgid: proc.pid,
      worktree: worktree,
      port: p,
      command: config.command,
      startedAt: DateTime.now(),
      appPid: _registry.appPid,
    );
    await _registry.writeRecord(record);
    void onLine(String line, DevLogKind kind) {
      if (run != _run) return;
      logs.add(DevLogLine(line, kind));
      final ready = config.readyText;
      if (_status == DevServerStatus.starting &&
          ready != null &&
          line.contains(ready)) {
        _up('"$ready" apareceu no log · servidor no ar');
      }
      _notify();
    }

    for (final (stream, kind) in [
      (proc.stdout, DevLogKind.out),
      (proc.stderr, DevLogKind.err),
    ]) {
      stream
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((l) => onLine(l, kind), onError: (_) {});
    }
    unawaited(
      proc.exitCode.then((code) async {
        await _registry.deleteRecord(record.pid);
        if (run != _run) return;
        _poll?.cancel();
        _process = null;
        if (_stopping) return;
        final was = _status;
        log('o comando terminou (código $code)', DevLogKind.err);
        pid = null;
        pgid = null;
        _set(
          DevServerStatus.failed,
          failure: DevServerFailure(
            was == DevServerStatus.running
                ? 'o servidor parou (código $code)'
                : 'o comando terminou (código $code)',
          ),
        );
      }),
    );
    if (config.readyText == null) {
      final deadline = DateTime.now().add(_registry.readyTimeout);
      _poll = Timer.periodic(_registry.pollInterval, (t) async {
        if (run != _run || _status != DevServerStatus.starting) {
          return t.cancel();
        }
        if (await _registry.probe.respondsHttp(p)) {
          if (run == _run && _status == DevServerStatus.starting) {
            t.cancel();
            _up('porta $p respondeu HTTP · servidor no ar');
          }
        } else if (DateTime.now().isAfter(deadline)) {
          t.cancel();
          await _timeout(run, p);
        }
      });
    } else {
      Timer(_registry.readyTimeout, () => _timeout(run, p));
    }
  }

  void _up(String note) {
    startedAt = DateTime.now();
    log('✓ $note');
    _set(DevServerStatus.running);
  }

  Future<void> _timeout(int run, int port) async {
    if (run != _run || _status != DevServerStatus.starting) return;
    final secs = _registry.readyTimeout.inSeconds;
    log('o servidor não ficou pronto em $secs s · parando', DevLogKind.err);
    await stop(quiet: true);
    _set(
      DevServerStatus.failed,
      failure: DevServerFailure('não ficou pronto em $secs s', port: port),
    );
  }

  /// An adopted server has no [Process]: notice when its group goes away.
  void _watchGroup(int run) {
    _poll = Timer.periodic(const Duration(seconds: 2), (t) {
      final g = pgid;
      if (run != _run || g == null || _status != DevServerStatus.running) {
        return t.cancel();
      }
      if (_registry.proc.group(g).isEmpty) {
        t.cancel();
        log('o servidor parou', DevLogKind.err);
        _reset();
        _set(
          DevServerStatus.failed,
          failure: const DevServerFailure('o servidor parou'),
        );
      }
    });
  }

  /// "Usar o que está no ar" (R3): the preview opens [port] without starting
  /// anything; the app never stops that process.
  void useRunning(int port) {
    _run++;
    _reset();
    this.port = port;
    external = true;
    startedAt = DateTime.now();
    log('usando o que já está no ar na porta $port · o app não vai encerrá-lo');
    _set(DevServerStatus.running);
  }

  /// SIGTERM to the group, SIGKILL after the grace period (R5). A server the
  /// app did not start ([external]) is only forgotten.
  Future<void> stop({bool quiet = false}) async {
    final g = pgid;
    _poll?.cancel();
    if (external || g == null) {
      _run++;
      _reset();
      if (!quiet) _set(DevServerStatus.stopped);
      return;
    }
    _stopping = true;
    try {
      await _registry.signal(g, ProcessSignal.sigterm);
      if (!await _registry.waitGone(g, _registry.stopGrace)) {
        log(
          'o grupo $g não saiu em ${_registry.stopGrace.inSeconds} s · SIGKILL',
          DevLogKind.err,
        );
        await _registry.signal(g, ProcessSignal.sigkill);
        await _registry.waitGone(g, const Duration(seconds: 2));
      }
      final p = pid;
      if (p != null) await _registry.deleteRecord(p);
      await _process?.exitCode.timeout(
        const Duration(seconds: 1),
        onTimeout: () => -1,
      );
    } finally {
      _stopping = false;
    }
    _run++;
    _reset();
    if (!quiet) {
      log('servidor parado');
      _set(DevServerStatus.stopped);
    }
  }

  void dispose() {
    _poll?.cancel();
    _changes.close();
  }
}

/// One [DevServer] per worktree, with the records in [runDir] (R5).
class DevServerRegistry {
  DevServerRegistry({
    required this.runDir,
    ProcessStarter? starter,
    PortProbe? probe,
    this.proc = const ProcInfo(),
    GroupSignal? signal,
    int? appPid,
    this.readyTimeout = const Duration(minutes: 2),
    this.stopGrace = const Duration(seconds: 5),
    this.pollInterval = const Duration(milliseconds: 500),
    Future<int> Function()? freePort,
  }) : starter = starter ?? _start,
       probe = probe ?? PortProbe(proc: proc),
       signal = signal ?? killGroup,
       appPid = appPid ?? pid,
       _freePort = freePort ?? PortProbe.freePort;

  final String runDir;
  final ProcessStarter starter;
  final PortProbe probe;
  final ProcInfo proc;
  final GroupSignal signal;
  final int appPid;
  final Duration readyTimeout, stopGrace, pollInterval;
  final Future<int> Function() _freePort;

  final _servers = <String, DevServer>{};
  final _dismissed = <int>{};

  static Future<Process> _start(
    String exe,
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) => Process.start(
    exe,
    args,
    workingDirectory: workingDirectory,
    environment: environment,
  );

  DevServer of(String worktree) =>
      _servers.putIfAbsent(worktree, () => DevServer._(worktree, this));

  /// The server of [worktree] when one was created (no side effect).
  DevServer? existing(String worktree) => _servers[worktree];

  Iterable<DevServer> get servers => _servers.values;

  /// A free port not used by another server of the app.
  Future<int> pickPort() async {
    final taken = {
      for (final s in _servers.values)
        if (s.isBusy) s.port,
    };
    for (var i = 0; i < 20; i++) {
      final p = await _freePort();
      if (!taken.contains(p)) return p;
    }
    return _freePort();
  }

  /// Polls until group [pgid] has no process left; false on timeout.
  Future<bool> waitGone(int pgid, Duration timeout) async {
    final end = DateTime.now().add(timeout);
    while (true) {
      if (proc.group(pgid).isEmpty) return true;
      if (DateTime.now().isAfter(end)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> writeRecord(DevServerRecord r) async {
    try {
      await Directory(runDir).create(recursive: true);
      await File('$runDir/${r.pid}.json').writeAsString(jsonEncode(r.toJson()));
    } catch (e) {
      debugPrint('registro do servidor ${r.pid} não gravado — $e');
    }
  }

  Future<void> deleteRecord(int pid) async {
    try {
      final f = File('$runDir/$pid.json');
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<List<DevServerRecord>> records() async {
    final dir = Directory(runDir);
    if (!await dir.exists()) return const [];
    final out = <DevServerRecord>[];
    await for (final f in dir.list()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      try {
        final r = DevServerRecord.fromJson(jsonDecode(await f.readAsString()));
        if (r != null) out.add(r);
      } catch (_) {}
    }
    return out;
  }

  /// Whether group [r.pgid] still runs the server of [r] (the PID may have
  /// been reused): one of its processes has `PROMPTORIUM_WORKTREE` = the
  /// record's worktree.
  bool isAlive(DevServerRecord r) => proc
      .group(r.pgid)
      .any((p) => proc.environ(p)['PROMPTORIUM_WORKTREE'] == r.worktree);

  /// The record of [worktree] whose group holds the port of [owner] (R3:
  /// the port is taken by a server the app started for this worktree).
  Future<DevServerRecord?> recordOwning(
    String worktree,
    PortOwner owner,
  ) async {
    final p = owner.pid;
    if (p == null) return null;
    final group = proc.pgrp(p);
    for (final r in await records()) {
      if (r.worktree == worktree && r.pgid == group && isAlive(r)) return r;
    }
    return null;
  }

  /// Servers left by a run of the app that crashed (R5), still alive. Dead
  /// records are removed.
  Future<List<DevServerRecord>> leftovers() async {
    final mine = {
      for (final s in _servers.values)
        if (s.pgid != null) s.pgid,
    };
    final out = <DevServerRecord>[];
    for (final r in await records()) {
      if (mine.contains(r.pgid)) continue;
      if (!isAlive(r)) {
        await deleteRecord(r.pid);
        continue;
      }
      if (r.appPid == appPid || _dismissed.contains(r.pid)) continue;
      out.add(r);
    }
    return out;
  }

  /// "Deixar rodando": not offered again in this run.
  void dismissLeftover(DevServerRecord r) => _dismissed.add(r.pid);

  /// "Encerrar" a leftover: TERM / KILL to its group, only after checking
  /// it is still the app's server.
  Future<void> endLeftover(DevServerRecord r) async {
    if (isAlive(r)) {
      await signal(r.pgid, ProcessSignal.sigterm);
      if (!await waitGone(r.pgid, stopGrace)) {
        await signal(r.pgid, ProcessSignal.sigkill);
        await waitGone(r.pgid, const Duration(seconds: 2));
      }
    }
    await deleteRecord(r.pid);
  }

  /// Stops the server of [worktree] (before the worktree is removed, R5).
  Future<void> stopWorktree(String worktree) async {
    final s = _servers[worktree];
    if (s != null && (s.isBusy || s.pgid != null)) await s.stop();
  }

  /// Every server (closing the app, R5).
  Future<void> stopAll() => Future.wait([
    for (final s in _servers.values)
      if (s.isBusy || s.pgid != null) s.stop(),
  ]);
}

/// `~/.promptorium/run/dev` (R5).
final devServerRunDirProvider = Provider<String>(
  (ref) => '${Platform.environment['HOME'] ?? ''}/.promptorium/run/dev',
);

final devServerRegistryProvider = Provider<DevServerRegistry>(
  (ref) => DevServerRegistry(runDir: ref.watch(devServerRunDirProvider)),
);

/// The server of a worktree (by path).
final devServerProvider = Provider.family<DevServer, String>(
  (ref, worktree) => ref.watch(devServerRegistryProvider).of(worktree),
);

/// Ticks on every change of the worktree's server (state or log): watch it
/// to rebuild, then read [devServerProvider].
final devServerTickProvider = StreamProvider.autoDispose.family<int, String>((
  ref,
  worktree,
) {
  final server = ref.watch(devServerProvider(worktree));
  var n = 0;
  return server.changes.map((_) => ++n);
});
