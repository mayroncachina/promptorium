import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../claude/claude_process_test.dart' show FakeProcess;

/// One line of a recorded App Server transcript (SPEC-093 R18):
/// `{"dir": "send"|"recv", "msg": {...}}`, already sanitized.
typedef CodexLine = ({String dir, Map<String, dynamic> msg});

/// Reads a transcript from `test/fixtures/codex/<version>/<name>.jsonl`.
List<CodexLine> readCodexTranscript(String path) => [
  for (final l in const LineSplitter().convert(File(path).readAsStringSync()))
    if (l.trim().isNotEmpty)
      (() {
        final j = jsonDecode(l) as Map<String, dynamic>;
        return (dir: j['dir'] as String, msg: j['msg'] as Map<String, dynamic>);
      })(),
];

/// In-memory App Server, including the effective policy returned by a thread.
///
/// [FakeCodex.replay] answers from a real transcript instead: each request
/// the app sends gets the recorded response to the next recorded request
/// with the same method (with the app's id), followed by the notifications
/// and server requests recorded after it. A `turn/start` replays everything
/// up to its `turn/completed`. Requests missing from the transcript use
/// [fallback] (e.g. `model/list` from the handshake) or an empty result.
class FakeCodex extends FakeProcess {
  FakeCodex({
    this.threadId = 'thread-codex',
    this.rejectYolo = false,
    this.models = const [
      {
        'id': 'test-model',
        'supportedReasoningEfforts': [],
        'inputModalities': ['text'],
      },
    ],
  }) : transcript = null,
       fallback = const {} {
    _timer = Timer.periodic(const Duration(milliseconds: 1), (_) => _respond());
  }

  FakeCodex.replay(List<CodexLine> this.transcript, {this.fallback = const {}})
    : threadId = '',
      rejectYolo = false,
      models = const [] {
    _timer = Timer.periodic(const Duration(milliseconds: 1), (_) => _replay());
  }

  final String threadId;
  final bool rejectYolo;

  /// `instructionSources` of `thread/*` (SPEC-104 R2); null = not sent.
  List<String>? instructionSources;

  /// Answer to `skills/list` (SPEC-104 R7); null = empty result.
  Map<String, dynamic>? skillsList;

  /// Answer to `hooks/list` (SPEC-103 R5); null = empty result.
  Map<String, dynamic>? hooksList;

  /// `hooks/list` fails with this message.
  String? hooksListError;

  /// Threads of the thread operations (SPEC-110), shared by the servers of
  /// a test: what the Codex keeps on disk. Null = they answer as before.
  FakeCodexStore? store;

  /// Threads this server loaded (`thread/revert` needs it).
  final loaded = <String>{};

  /// Sends a `hook/started` + `hook/completed` pair of [run] (SPEC-103 R6).
  void emitHook(Map<String, dynamic> run, {String? thread}) {
    for (final m in ['hook/started', 'hook/completed']) {
      emit(
        jsonEncode({
          'method': m,
          'params': {
            'threadId': thread ?? threadId,
            'turnId': 'turn-1',
            'run': {...run, if (m == 'hook/started') 'status': 'running'},
          },
        }),
      );
    }
  }

  /// `model/list` of the in-memory server; the first is the thread's.
  final List<Map<String, dynamic>> models;
  final List<CodexLine>? transcript;
  final Map<String, Map<String, dynamic>> fallback;
  late final Timer _timer;
  int _read = 0;
  int _cursor = 0;

  /// What the app answered to server requests (approvals), by request id.
  final appAnswers = <Object, Map<String, dynamic>>{};

  /// What the probe answered to the same server requests, by request id.
  Map<Object, Map<String, dynamic>> get recordedAnswers => {
    for (final l in transcript ?? const <CodexLine>[])
      if (l.dir == 'send' && l.msg['method'] == null && l.msg['id'] != null)
        l.msg['id'] as Object: l.msg,
  };

  /// App requests the transcript has no recording for.
  final unmatched = <String>[];

  bool _isClientRequest(CodexLine l) =>
      l.dir == 'send' && l.msg['method'] != null && l.msg['id'] != null;

  void _replay() {
    final t = transcript!;
    final messages = writtenAll;
    while (_read < messages.length) {
      final m = messages[_read++];
      final method = m['method'];
      if (method == null && m['id'] != null) {
        appAnswers[m['id'] as Object] = m;
        // A recorded server request waits for the app's answer, as the
        // real App Server does (its `serverRequest/resolved` comes after).
        final paused = _paused;
        if (paused != null && paused.id == m['id']) {
          _paused = null;
          _cursor = _emitFrom(paused.from, paused.method);
        }
        continue;
      }
      if (method == null || m['id'] == null) continue;
      var i = _cursor;
      while (i < t.length &&
          !(_isClientRequest(t[i]) && t[i].msg['method'] == method)) {
        i++;
      }
      if (i >= t.length) {
        unmatched.add('$method');
        emit(
          jsonEncode({
            'id': m['id'],
            'result': fallback[method] ?? <String, dynamic>{},
          }),
        );
        continue;
      }
      final recordedId = t[i].msg['id'];
      final response = t.firstWhere(
        (l) =>
            l.dir == 'recv' &&
            l.msg['method'] == null &&
            l.msg['id'] == recordedId,
        orElse: () => (dir: 'recv', msg: {'result': <String, dynamic>{}}),
      );
      emit(jsonEncode({...response.msg, 'id': m['id']}));
      _cursor = _emitFrom(i + 1, '$method');
    }
  }

  /// A server request emitted and not answered yet: where to go on.
  ({Object id, int from, String method})? _paused;

  /// Emits the recorded notifications from [j] on; returns the next cursor.
  int _emitFrom(int j, String method) {
    final t = transcript!;
    for (; j < t.length; j++) {
      final l = t[j];
      if (method != 'turn/start' && _isClientRequest(l)) break;
      if (l.dir != 'recv' || l.msg['method'] == null) continue;
      emit(jsonEncode(l.msg));
      if (method == 'turn/start' && l.msg['method'] == 'turn/completed') {
        return j + 1;
      }
      final id = l.msg['id'];
      if (id != null &&
          t.any(
            (a) =>
                a.dir == 'send' && a.msg['id'] == id && a.msg['method'] == null,
          )) {
        _paused = (id: id as Object, from: j + 1, method: method);
        return j + 1;
      }
    }
    return j;
  }

  void _respond() {
    final messages = writtenJson;
    while (_read < messages.length) {
      final m = messages[_read++];
      if (m['id'] == null || m['method'] == null) continue;
      final p = m['params'] as Map;
      if (m['method'] == 'hooks/list' && hooksListError != null) {
        emit(
          jsonEncode({
            'id': m['id'],
            'error': {'code': -32603, 'message': hooksListError},
          }),
        );
        continue;
      }
      if (store != null) {
        final answer = store!.answer(this, '${m['method']}', p);
        if (answer != null) {
          if (answer['silent'] != true) {
            emit(jsonEncode({'id': m['id'], ...answer}));
          }
          continue;
        }
      }
      final result = switch (m['method']) {
        'hooks/list' => hooksList ?? <String, dynamic>{},
        'skills/list' => skillsList ?? <String, dynamic>{'data': []},
        'initialize' => {'userAgent': 'codex-test'},
        'account/read' => {'requiresOpenaiAuth': false},
        'model/list' => {'data': models, 'nextCursor': null},
        'thread/start' || 'thread/resume' || 'thread/fork' => {
          'thread': {'id': threadId},
          'model': p['model'] ?? models.first['id'],
          'approvalPolicy': p['approvalPolicy'],
          'instructionSources': ?instructionSources,
          'sandbox': {
            'type': rejectYolo
                ? 'workspaceWrite'
                : switch (p['sandbox']) {
                    'danger-full-access' => 'dangerFullAccess',
                    'read-only' => 'readOnly',
                    _ => 'workspaceWrite',
                  },
          },
        },
        'turn/start' => {
          'turn': {'id': 'turn-1'},
        },
        _ => <String, dynamic>{},
      };
      emit(jsonEncode({'id': m['id'], 'result': result}));
    }
  }

  /// The final agent message of the turn ([text] = the structured answer
  /// of an `outputSchema` turn, SPEC-093 R12).
  void answer(String text, {String id = 'msg-1'}) => emit(
    jsonEncode({
      'method': 'item/completed',
      'params': {
        'threadId': threadId,
        'item': {
          'id': id,
          'type': 'agentMessage',
          'text': text,
          'phase': 'final_answer',
        },
      },
    }),
  );

  void completeTurn() => emit(
    jsonEncode({
      'method': 'turn/completed',
      'params': {
        'threadId': threadId,
        'turn': {'id': 'turn-1', 'status': 'completed'},
      },
    }),
  );
  /// The process ended (its threads have no writer any more).
  bool ended = false;

  @override
  Future<void> finish([int code = 0]) {
    ended = true;
    _timer.cancel();
    return super.finish(code);
  }
}

/// The threads of the Codex as the 0.170 App Server answered in the probe of
/// SPEC-110 (real binary, local model provider): `thread/revert` only in a
/// connection that loaded the thread, forks that keep the turn ids, one
/// writer per thread, `turn not found`, archived threads that do not resume.
class FakeCodexStore {
  final threads = <String, List<String>>{};
  final archived = <String>{};

  /// `aggregatedOutput` of an item, by thread, turn and item.
  final outputs = <(String, String, String), String>{};

  /// Every thread operation, in order: `fork a`, `revert a t3`…
  final calls = <String>[];

  /// Method → error message (the request fails), or `null` = never answers.
  final fail = <String, String?>{};

  /// Thread → the server whose process writes it.
  final writers = <String, FakeCodex>{};

  var _forks = 0;

  Map<String, dynamic> _error(String message) => {
    'error': {'code': -32600, 'message': message},
  };

  Map<String, dynamic> _thread(String id) => {
    'result': {
      'thread': {'id': id, 'historyMode': 'paginated', 'turns': []},
    },
  };

  Map<String, dynamic>? answer(FakeCodex server, String method, Map p) {
    if (fail.containsKey(method)) {
      calls.add('$method falhou');
      final message = fail[method];
      return message == null ? {'silent': true} : _error(message);
    }
    final id = '${p['threadId']}';
    bool known() => threads.containsKey(id) && !archived.contains(id);
    switch (method) {
      case 'thread/start':
        threads[server.threadId] = [];
        server.loaded.add(server.threadId);
        writers[server.threadId] = server;
        return null;
      case 'thread/resume':
        if (archived.contains(id)) return _error('session $id is archived.');
        if (!known()) return _error('no rollout found for thread id $id');
        final w = writers[id];
        if (w != null && !identical(w, server) && !w.ended) {
          return _error('thread $id already has an active writer');
        }
        writers[id] = server;
        server.loaded.add(id);
        calls.add('resume $id');
        return _thread(id);
      case 'thread/fork':
        if (!known()) return _error('no rollout found for thread id $id');
        final copy = 'copia-${++_forks}';
        threads[copy] = [...threads[id]!];
        server.loaded.add(copy);
        calls.add('fork $id → $copy');
        server.emit(
          jsonEncode({
            'method': 'thread/started',
            'params': {
              'thread': {'id': copy},
            },
          }),
        );
        return _thread(copy);
      case 'thread/revert':
        if (!server.loaded.contains(id)) {
          return _error('thread not found: $id');
        }
        final before = '${p['beforeTurnId']}';
        final turns = threads[id] ?? const [];
        final i = turns.indexOf(before);
        if (i < 0) return _error('turn not found: $before');
        threads[id] = turns.sublist(0, i);
        calls.add('revert $id $before');
        return _thread(id);
      case 'thread/read':
        if (!known()) return _error('no rollout found for thread id $id');
        calls.add('read $id');
        return _thread(id);
      case 'thread/archive':
        if (!known()) return _error('no rollout found for thread id $id');
        archived.add(id);
        calls.add('archive $id');
        return {'result': <String, dynamic>{}};
      case 'thread/items/list':
        calls.add('items $id ${p['turnId']}');
        return {
          'result': {
            'data': [
              if (known() && threads[id]!.contains(p['turnId']))
                for (final MapEntry(key: (t, turn, item), :value)
                    in outputs.entries)
                  if (turn == p['turnId'] && (t == id || t == '*'))
                    {
                      'turnId': turn,
                      'item': {
                        'id': item,
                        'type': 'commandExecution',
                        'aggregatedOutput': value,
                      },
                    },
            ],
            'nextCursor': null,
          },
        };
    }
    return null;
  }
}
