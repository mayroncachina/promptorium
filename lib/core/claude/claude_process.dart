import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'claude_args.dart';
import 'claude_event.dart';

/// `Process.start` signature subset, injected so tests can fake the CLI.
typedef ProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
});

Future<Process> _defaultStarter(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) => Process.start(
  executable,
  arguments,
  workingDirectory: workingDirectory,
  environment: environment,
);

/// A long-lived `claude -p` stream-json session (plano, Fases 0.2 / 0.3).
///
/// stdout is parsed line by line into [events]; stderr goes to [logs]. The
/// stdin stays open until [stop] (closing it early makes the CLI abort
/// pending permission prompts).
class ClaudeProcess {
  ClaudeProcess._(this._process, this.executable, this.args) {
    _events = StreamController<ClaudeEvent>.broadcast(onListen: _flush);
    _logs = StreamController<String>.broadcast();
    _stdoutSub = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine, onDone: _onStdoutDone, onError: _onStreamError);
    _stderrSub = _process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_log, onError: _onStreamError);
    // Broken pipe after exit must not crash the app.
    _process.stdin.done.catchError((Object e) {
      _log('stdin: $e');
    });
    _exitCode = _process.exitCode.then((code) {
      _exited = true;
      return code;
    });
  }

  /// Starts `executable ...options.toArgs()` in [workingDirectory].
  ///
  /// [executable] should come from the startup check (see
  /// `claudeExecutableProvider` in `claude_cli.dart`).
  static Future<ClaudeProcess> start(
    ClaudeOptions options, {
    required String workingDirectory,
    String executable = 'claude',
    Map<String, String>? environment,
    ProcessStarter? starter,
  }) async {
    final args = options.toArgs();
    final process = await (starter ?? _defaultStarter)(
      executable,
      args,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    return ClaudeProcess._(process, executable, args);
  }

  final Process _process;
  final String executable;
  final List<String> args;

  late final StreamController<ClaudeEvent> _events;
  late final StreamController<String> _logs;
  late final StreamSubscription<String> _stdoutSub;
  late final StreamSubscription<String> _stderrSub;
  late final Future<int> _exitCode;
  bool _exited = false;
  bool _stdinClosed = false;
  Future<void> _writes = Future.value();

  /// Events received before the first listener (delivered on listen).
  final List<ClaudeEvent> _backlog = [];

  /// Inputs of unanswered permission requests (used as `updatedInput`).
  final Map<String, Map<String, dynamic>> _pending = {};

  int get pid => _process.pid;

  /// Parsed stdout lines (broadcast). Closes when stdout ends.
  Stream<ClaudeEvent> get events => _events.stream;

  /// stderr lines and internal warnings (broadcast).
  Stream<String> get logs => _logs.stream;

  Future<int> get exitCode => _exitCode;

  bool get isRunning => !_exited;

  /// Permission requests still waiting for [allow] / [deny].
  Iterable<String> get pendingRequestIds => _pending.keys;

  /// Sends a user message.
  Future<void> send(String text) => _write({
    'type': 'user',
    'message': {'role': 'user', 'content': text},
    'parent_tool_use_id': null,
  });

  /// Approves a `can_use_tool` request. [updatedInput] defaults to the
  /// original tool input; pass one of the request's `permissionSuggestions`
  /// in [updatedPermissions] for "Sempre permitir".
  Future<void> allow(
    String requestId, {
    Map<String, dynamic>? updatedInput,
    List<Object?>? updatedPermissions,
  }) {
    final input = updatedInput ?? _pending[requestId] ?? const {};
    _pending.remove(requestId);
    return _write(
      controlResponse(requestId, {
        'behavior': 'allow',
        'updatedInput': input,
        'updatedPermissions': ?updatedPermissions,
      }),
    );
  }

  /// Denies a `can_use_tool` request; [message] is shown to the model.
  Future<void> deny(String requestId, String message) {
    _pending.remove(requestId);
    return _write(
      controlResponse(requestId, {'behavior': 'deny', 'message': message}),
    );
  }

  /// `control_response` envelope (plano, Fase 0.3).
  @visibleForTesting
  static Map<String, dynamic> controlResponse(
    String requestId,
    Map<String, dynamic> response,
  ) => {
    'type': 'control_response',
    'response': {
      'subtype': 'success',
      'request_id': requestId,
      'response': response,
    },
  };

  /// SIGTERM, then SIGKILL if the process is still alive after [timeout].
  Future<int> stop({Duration timeout = const Duration(seconds: 5)}) async {
    if (!_exited) {
      _process.kill(ProcessSignal.sigterm);
      try {
        await _exitCode.timeout(timeout);
      } on TimeoutException {
        _log('claude não encerrou após SIGTERM; enviando SIGKILL');
        _process.kill(ProcessSignal.sigkill);
      }
    }
    final code = await _exitCode;
    await _closeStdin();
    return code;
  }

  // --- internals -------------------------------------------------------------

  Future<void> _write(Map<String, dynamic> message) {
    final line = '${jsonEncode(message)}\n';
    // Serialized: IOSink forbids writes while a flush is pending.
    return _writes = _writes.then((_) async {
      if (_exited || _stdinClosed) {
        _log('stdin fechada; mensagem descartada');
        return;
      }
      try {
        _process.stdin.add(utf8.encode(line));
        await _process.stdin.flush();
      } catch (e) {
        _log('stdin: $e');
      }
    });
  }

  Future<void> _closeStdin() async {
    if (_stdinClosed) return;
    _stdinClosed = true;
    await _writes;
    try {
      await _process.stdin.close();
    } catch (_) {
      // already broken
    }
  }

  void _onLine(String line) {
    if (line.trim().isEmpty) return;
    for (final event in ClaudeEvent.parseLine(line)) {
      switch (event) {
        case PermissionRequest(:final requestId, :final input):
          _pending[requestId] = input;
        case ControlCancel(:final requestId):
          _pending.remove(requestId);
        default:
          break;
      }
      _emit(event);
    }
  }

  void _emit(ClaudeEvent event) {
    if (_events.hasListener) {
      _events.add(event);
    } else {
      _backlog.add(event);
    }
  }

  void _flush() {
    if (_backlog.isEmpty) return;
    final copy = List.of(_backlog);
    _backlog.clear();
    copy.forEach(_events.add);
  }

  void _onStreamError(Object e) => _log('stream: $e');

  void _log(String line) {
    if (!_logs.isClosed) _logs.add(line);
  }

  Future<void> _onStdoutDone() async {
    await _stderrSub.asFuture<void>().catchError((_) {});
    await _stdoutSub.cancel();
    await _events.close();
    await _exitCode;
    await _closeStdin();
    await _logs.close();
  }
}
