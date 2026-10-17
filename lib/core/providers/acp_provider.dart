import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../ui/widgets/app_icon.dart';
import '../claude/claude_event.dart';
import '../claude/claude_process.dart' show ProcessStarter;
import 'agent_provider.dart';

/// A coding agent that speaks the Agent Client Protocol (ACP: JSON-RPC 2.0
/// over stdio, one message per line), e.g. `gemini --experimental-acp`
/// (F18). Its messages are translated into the stream-json events the
/// Prompt timeline understands.
class AcpProvider implements AgentProvider {
  AcpProvider({
    required this.id,
    required this.displayName,
    required this.command,
    this.starter,
  });

  @override
  final String id;

  @override
  final String displayName;

  /// Executable and arguments (`['gemini', '--experimental-acp']`).
  final List<String> command;
  final ProcessStarter? starter;

  @override
  AppIconData get icon => AppIcons.sparkle;

  @override
  bool get enabled => command.isNotEmpty;

  @override
  List<String> get models => const ['inherit'];

  @override
  Future<AgentRun> start(AgentStartOptions options) async {
    if (command.isEmpty) {
      throw AgentUnavailable('$displayName: comando não configurado.');
    }
    final Process p;
    try {
      p = await (starter ?? _start)(
        command.first,
        command.sublist(1),
        workingDirectory: options.workingDirectory,
      );
    } on ProcessException catch (e) {
      throw AgentUnavailable(
        '$displayName: não foi possível executar ${command.first} '
        '(${e.message}).',
      );
    }
    final run = AcpRun(p, options, args: command);
    await run.open();
    return run;
  }

  static Future<Process> _start(
    String exe,
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) => Process.start(exe, args, workingDirectory: workingDirectory);
}

/// One ACP agent process: `initialize`, `session/new` (or `session/load`
/// to continue), then one `session/prompt` per message.
class AcpRun implements AgentRun {
  AcpRun(this._p, this._o, {required this.args}) {
    _p.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_line, onDone: _done);
    _p.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_logs.add);
    _exit = _p.exitCode.then((c) {
      _exited = true;
      return c;
    });
  }

  final Process _p;
  final AgentStartOptions _o;

  @override
  final List<String> args;

  /// Single subscription: events before the listener are buffered.
  final _events = StreamController<ClaudeEvent>();
  final _logs = StreamController<String>.broadcast();
  late final Future<int> _exit;
  bool _exited = false;
  int _nextId = 0;
  final Map<int, Completer<Object?>> _calls = {};

  /// Permission requests of the agent waiting for the user: our id →
  /// (JSON-RPC id, options).
  final Map<String, (Object, List<Map<String, dynamic>>)> _asks = {};
  String? _session;
  final StringBuffer _text = StringBuffer();
  int _toolIndex = 0;

  /// Kinds of tool call refused without asking in the read-only mode.
  static const _writes = {'edit', 'delete', 'move', 'execute'};

  @override
  Stream<ClaudeEvent> get events => _events.stream;

  @override
  Stream<String> get logs => _logs.stream;

  @override
  bool get isRunning => !_exited;

  @override
  Future<int> get exitCode => _exit;

  void _emit(Map<String, dynamic> json) {
    if (!_events.isClosed) _events.add(ClaudeEvent.fromJson(json));
  }

  void _write(Map<String, dynamic> m) {
    if (_exited) return;
    _p.stdin.writeln(jsonEncode({'jsonrpc': '2.0', ...m}));
  }

  Future<Object?> _request(String method, Map<String, dynamic> params) {
    final id = ++_nextId;
    final c = Completer<Object?>();
    _calls[id] = c;
    _write({'id': id, 'method': method, 'params': params});
    return c.future;
  }

  /// Handshake and session.
  Future<void> open() async {
    final init = await _request('initialize', {
      'protocolVersion': 1,
      'clientCapabilities': {
        'fs': {'readTextFile': false, 'writeTextFile': false},
      },
    });
    final caps = init is Map ? init['agentCapabilities'] : null;
    final canLoad = caps is Map && caps['loadSession'] == true;
    final cwd = _o.workingDirectory;
    if (_o.resumeId != null && canLoad && !_o.forkSession) {
      await _request('session/load', {
        'sessionId': _o.resumeId,
        'cwd': cwd,
        'mcpServers': const [],
      });
      _session = _o.resumeId;
    } else {
      final r = await _request('session/new', {
        'cwd': cwd,
        'mcpServers': const [],
      });
      _session = r is Map ? '${r['sessionId'] ?? ''}' : null;
    }
    _emit({
      'type': 'system',
      'subtype': 'init',
      'session_id': _session,
      'cwd': cwd,
      'model': 'acp',
      'tools': const [],
      'mcp_servers': const [],
      'permissionMode': _o.mode.name,
    });
  }

  @override
  Future<void> send(String text, {List<ImagePart> images = const []}) async {
    _text.clear();
    final started = DateTime.now();
    Object? r;
    var failed = false;
    try {
      r = await _request('session/prompt', {
        'sessionId': _session,
        'prompt': [
          {'type': 'text', 'text': text},
          for (final i in images)
            {'type': 'image', 'mimeType': i.mediaType, 'data': i.base64},
        ],
      });
    } catch (e) {
      failed = true;
      _logs.add('acp: $e');
    }
    final full = _text.toString();
    if (full.isNotEmpty) {
      _emit({
        'type': 'assistant',
        'message': {
          'role': 'assistant',
          'content': [
            {'type': 'text', 'text': full},
          ],
        },
        'session_id': _session,
      });
    }
    final stop = r is Map ? '${r['stopReason'] ?? ''}' : '';
    final ok = !failed && (stop == 'end_turn' || stop.isEmpty);
    _emit({
      'type': 'result',
      'subtype': ok ? 'success' : 'error_during_execution',
      'is_error': !ok,
      'result': full,
      'total_cost_usd': 0,
      'duration_ms': DateTime.now().difference(started).inMilliseconds,
      'num_turns': 1,
      'usage': const {},
      'session_id': _session,
    });
  }

  void _line(String line) {
    Object? m;
    try {
      m = jsonDecode(line);
    } on FormatException {
      _logs.add(line);
      return;
    }
    if (m is! Map<String, dynamic>) return;
    final id = m['id'];
    final method = m['method'];
    if (method == null && id is int) {
      // A response to one of our calls.
      final c = _calls.remove(id);
      if (c == null) return;
      if (m['error'] != null) {
        c.completeError(
          AgentUnavailable('${(m['error'] as Map?)?['message'] ?? m['error']}'),
        );
      } else {
        c.complete(m['result']);
      }
      return;
    }
    final params = m['params'] is Map<String, dynamic>
        ? m['params'] as Map<String, dynamic>
        : const <String, dynamic>{};
    switch (method) {
      case 'session/update':
        _update(params['update']);
      case 'session/request_permission':
        _ask(id!, params);
      default:
        // fs/* and anything else the client did not announce.
        if (id != null) {
          _write({
            'id': id,
            'error': {'code': -32601, 'message': 'Método não suportado'},
          });
        }
    }
  }

  void _update(Object? u) {
    if (u is! Map) return;
    String textOf(Object? content) {
      if (content is Map && content['type'] == 'text') {
        return '${content['text'] ?? ''}';
      }
      if (content is List) {
        return content.map((c) {
          if (c is Map && c['type'] == 'content') return textOf(c['content']);
          return textOf(c);
        }).join();
      }
      return '';
    }

    switch (u['sessionUpdate']) {
      case 'agent_message_chunk':
        final t = textOf(u['content']);
        _text.write(t);
        _emit({
          'type': 'stream_event',
          'event': {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {'type': 'text_delta', 'text': t},
          },
        });
      case 'agent_thought_chunk':
        _emit({
          'type': 'stream_event',
          'event': {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {
              'type': 'thinking_delta',
              'thinking': textOf(u['content']),
            },
          },
        });
      case 'tool_call':
        _emit({
          'type': 'assistant',
          'message': {
            'role': 'assistant',
            'content': [
              {
                'type': 'tool_use',
                'id': '${u['toolCallId'] ?? 'acp-${++_toolIndex}'}',
                'name': '${u['title'] ?? u['kind'] ?? 'ferramenta'}',
                'input': u['rawInput'] is Map ? u['rawInput'] : const {},
              },
            ],
          },
          'session_id': _session,
        });
      case 'tool_call_update':
        final status = u['status'];
        if (status != 'completed' && status != 'failed') return;
        _emit({
          'type': 'user',
          'message': {
            'role': 'user',
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': '${u['toolCallId']}',
                'content': textOf(u['content']),
                'is_error': status == 'failed',
              },
            ],
          },
          'session_id': _session,
        });
    }
  }

  void _ask(Object rpcId, Map<String, dynamic> params) {
    final call = params['toolCall'] is Map
        ? params['toolCall'] as Map
        : const {};
    final options = [
      for (final o in (params['options'] as List? ?? const []))
        if (o is Map<String, dynamic>) o,
    ];
    if (_o.mode == PromptMode.ask && _writes.contains(call['kind'])) {
      _answer(rpcId, options, allow: false);
      return;
    }
    final ours = 'acp-$rpcId';
    _asks[ours] = (rpcId, options);
    _emit({
      'type': 'control_request',
      'request_id': ours,
      'request': {
        'subtype': 'can_use_tool',
        'tool_name': '${call['title'] ?? call['kind'] ?? 'ferramenta'}',
        'input': call['rawInput'] is Map ? call['rawInput'] : const {},
        'tool_use_id': call['toolCallId'],
        if (options.any((o) => o['kind'] == 'allow_always'))
          'permission_suggestions': [
            {'type': 'acp', 'kind': 'allow_always'},
          ],
      },
    });
  }

  void _answer(
    Object rpcId,
    List<Map<String, dynamic>> options, {
    required bool allow,
    bool always = false,
  }) {
    Map<String, dynamic>? pick(List<String> kinds) {
      for (final k in kinds) {
        for (final o in options) {
          if (o['kind'] == k) return o;
        }
      }
      return null;
    }

    final o = allow
        ? pick(
            always
                ? ['allow_always', 'allow_once']
                : ['allow_once', 'allow_always'],
          )
        : pick(['reject_once', 'reject_always']);
    _write({
      'id': rpcId,
      'result': {
        'outcome': o == null
            ? {'outcome': 'cancelled'}
            : {'outcome': 'selected', 'optionId': o['optionId']},
      },
    });
  }

  @override
  Future<void> approve(
    String requestId, {
    List<Object?>? updatedPermissions,
  }) async {
    final a = _asks.remove(requestId);
    if (a == null) return;
    _answer(a.$1, a.$2, allow: true, always: updatedPermissions != null);
  }

  @override
  Future<void> deny(String requestId, String message) async {
    final a = _asks.remove(requestId);
    if (a == null) return;
    _answer(a.$1, a.$2, allow: false);
  }

  @override
  Future<int> stop({Duration timeout = const Duration(seconds: 5)}) async {
    if (!_exited) {
      try {
        await _p.stdin.close();
      } catch (_) {}
      _p.kill(ProcessSignal.sigterm);
      try {
        await _exit.timeout(timeout);
      } on TimeoutException {
        _p.kill(ProcessSignal.sigkill);
      }
    }
    return _exit;
  }

  void _done() {
    unawaited(_events.close());
    for (final c in _calls.values) {
      if (!c.isCompleted) {
        c.completeError(const AgentUnavailable('O agente ACP encerrou.'));
      }
    }
    _calls.clear();
  }
}

/// `nome = comando` per line (Configurações → Provedores ACP) → providers'
/// (id, name, command). The id is the name as a slug.
List<({String id, String name, List<String> command})> parseAcpAgents(
  String text,
) => [
  for (final l in const LineSplitter().convert(text))
    if (l.contains('=') && !l.trimLeft().startsWith('#'))
      () {
        final i = l.indexOf('=');
        final name = l.substring(0, i).trim();
        final cmd = l
            .substring(i + 1)
            .trim()
            .split(RegExp(r'\s+'))
            .where((s) => s.isNotEmpty)
            .toList();
        return (
          id: 'acp-${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}',
          name: name,
          command: cmd,
        );
      }(),
].where((a) => a.name.isNotEmpty && a.command.isNotEmpty).toList();

/// Default of the ACP agents setting.
const defaultAcpAgents = 'Gemini CLI = gemini --experimental-acp';
