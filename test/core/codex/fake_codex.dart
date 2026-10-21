import 'dart:async';
import 'dart:convert';

import '../claude/claude_process_test.dart' show FakeProcess;

/// In-memory App Server, including the effective policy returned by a thread.
class FakeCodex extends FakeProcess {
  FakeCodex({this.threadId = 'thread-codex', this.rejectYolo = false}) {
    _timer = Timer.periodic(const Duration(milliseconds: 1), (_) => _respond());
  }
  final String threadId;
  final bool rejectYolo;
  late final Timer _timer;
  int _read = 0;
  void _respond() {
    final messages = writtenJson;
    while (_read < messages.length) {
      final m = messages[_read++];
      if (m['id'] == null || m['method'] == null) continue;
      final p = m['params'] as Map;
      final result = switch (m['method']) {
        'initialize' => {'userAgent': 'codex-test'},
        'account/read' => {'requiresOpenaiAuth': false},
        'model/list' => {
          'data': [
            {
              'id': 'test-model',
              'supportedReasoningEfforts': [],
              'inputModalities': ['text'],
            },
          ],
          'nextCursor': null,
        },
        'thread/start' || 'thread/resume' || 'thread/fork' => {
          'thread': {'id': threadId},
          'model': 'test-model',
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
