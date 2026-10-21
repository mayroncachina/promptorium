import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../providers/agent_provider.dart';

/// A single App Server connection. Requests and notifications are separate:
/// the server also sends requests whose ids can collide with client ids.
class CodexRpc {
  CodexRpc(this.process, {this.timeout = const Duration(seconds: 30)}) {
    process.stdin.done.catchError((Object _) {});
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_line, onDone: _done, onError: (Object e) => _done());
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((s) => _log(s), onError: (Object _) {});
    exitCode = process.exitCode.then((code) {
      exited = true;
      _failCalls('O Codex encerrou (código $code).');
      return code;
    });
  }

  final Process process;
  final Duration timeout;
  late final Future<int> exitCode;
  bool exited = false;
  int _id = 0;
  final _calls = <int, Completer<Map<String, dynamic>>>{};
  final messages = StreamController<Map<String, dynamic>>();
  final logs = StreamController<String>.broadcast();
  Future<void> _writes = Future.value();

  static String redact(String s) => s
      .replaceAll(RegExp(r'sk-[A-Za-z0-9_-]+'), '[redigido]')
      .replaceAll(
        RegExp(r'Bearer\s+\S+', caseSensitive: false),
        'Bearer [redigido]',
      )
      .replaceAllMapped(
        RegExp(
          r'((?:access_token|refresh_token|api_key|authorization)["\s:=]+)[^\s,}"]+',
          caseSensitive: false,
        ),
        (m) => '${m[1]}[redigido]',
      );

  void _log(String line) {
    if (!logs.isClosed) logs.add(redact(line));
  }

  Future<void> write(Map<String, dynamic> message) =>
      _writes = _writes.then((_) async {
        if (exited) throw const AgentUnavailable('O processo Codex encerrou.');
        process.stdin.writeln(jsonEncode(message));
        await process.stdin.flush();
      });

  Future<Map<String, dynamic>> request(
    String method,
    Map<String, dynamic> params,
  ) async {
    if (exited) throw const AgentUnavailable('O processo Codex encerrou.');
    final id = ++_id;
    final c = Completer<Map<String, dynamic>>();
    _calls[id] = c;
    // Install the timeout handler before writing: early exits may complete c.
    final response = c.future.timeout(
      timeout,
      onTimeout: () {
        throw AgentUnavailable('Codex: timeout em $method.');
      },
    );
    try {
      await write({'id': id, 'method': method, 'params': params});
    } catch (e) {
      if (!c.isCompleted) c.completeError(e);
    }
    try {
      return await response;
    } finally {
      _calls.remove(id);
    }
  }

  void _line(String line) {
    try {
      final m = jsonDecode(line);
      if (m is! Map<String, dynamic>) {
        _log('Codex: mensagem não é um objeto JSON.');
        return;
      }
      if (m['method'] == null && m['id'] is int) {
        final c = _calls.remove(m['id']);
        if (c == null) return;
        if (m['error'] != null) {
          c.completeError(AgentUnavailable(redact('Codex: ${m['error']}')));
        } else {
          c.complete(
            m['result'] is Map<String, dynamic>
                ? m['result'] as Map<String, dynamic>
                : const {},
          );
        }
      } else if (!messages.isClosed) {
        messages.add(m);
      }
    } on FormatException {
      // Do not echo malformed stdout: it may contain credentials.
      _log('Codex: linha JSON inválida.');
    }
  }

  void _failCalls(String reason) {
    for (final c in _calls.values) {
      if (!c.isCompleted) c.completeError(AgentUnavailable(reason));
    }
    _calls.clear();
  }

  void _done() {
    _failCalls('O Codex fechou a conexão.');
    unawaited(messages.close());
  }

  Future<int> stop({Duration timeout = const Duration(seconds: 5)}) async {
    if (!exited) {
      process.kill(ProcessSignal.sigterm);
      try {
        await exitCode.timeout(timeout);
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
      }
    }
    final code = await exitCode;
    try {
      await process.stdin.close();
    } catch (_) {}
    if (!logs.isClosed) await logs.close();
    return code;
  }
}
