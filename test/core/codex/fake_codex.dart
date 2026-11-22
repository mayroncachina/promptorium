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

  /// Answer to `hooks/list` (SPEC-103 R5); null = empty result.
  Map<String, dynamic>? hooksList;

  /// `hooks/list` fails with this message.
  String? hooksListError;

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
      final result = switch (m['method']) {
        'hooks/list' => hooksList ?? <String, dynamic>{},
        'initialize' => {'userAgent': 'codex-test'},
        'account/read' => {'requiresOpenaiAuth': false},
        'model/list' => {'data': models, 'nextCursor': null},
        'thread/start' || 'thread/resume' || 'thread/fork' => {
          'thread': {'id': threadId},
          'model': p['model'] ?? models.first['id'],
          'approvalPolicy': p['approvalPolicy'],
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
  @override
  Future<void> finish([int code = 0]) {
    _timer.cancel();
    return super.finish(code);
  }
}
