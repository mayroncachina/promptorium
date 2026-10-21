import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/codex/codex_rpc.dart';
import 'package:promptorium/core/providers/agent_provider.dart';

import 'claude/claude_process_test.dart' show FakeProcess;

Future<void> flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
    'correlates out-of-order replies and separates server requests',
    () async {
      final process = FakeProcess();
      final rpc = CodexRpc(process);
      final messages = <Map<String, dynamic>>[];
      rpc.messages.stream.listen(messages.add);
      final first = rpc.request('first', {});
      final second = rpc.request('second', {});
      await flush();
      process.emit(jsonEncode({'id': 1, 'method': 'approval', 'params': {}}));
      process.emit(
        jsonEncode({
          'id': 2,
          'result': {'value': 'second'},
        }),
      );
      process.emit(
        jsonEncode({
          'id': 1,
          'result': {'value': 'first'},
        }),
      );
      expect(await second, {'value': 'second'});
      expect(await first, {'value': 'first'});
      expect(messages.single['method'], 'approval');
      await rpc.stop();
    },
  );

  test('timeout releases a request and a late reply is harmless', () async {
    final process = FakeProcess();
    final rpc = CodexRpc(process, timeout: const Duration(milliseconds: 20));
    rpc.messages.stream.listen((_) {});
    await expectLater(
      rpc.request('slow', {}),
      throwsA(isA<AgentUnavailable>()),
    );
    process.emit(jsonEncode({'id': 1, 'result': {}}));
    final next = rpc.request('next', {});
    await flush();
    process.emit(
      jsonEncode({
        'id': 2,
        'result': {'ok': true},
      }),
    );
    expect(await next, {'ok': true});
    await rpc.stop();
  });

  test('invalid stdout and stderr never expose credentials', () async {
    final process = FakeProcess();
    final rpc = CodexRpc(process);
    rpc.messages.stream.listen((_) {});
    final logs = <String>[];
    rpc.logs.stream.listen(logs.add);
    process.emit('invalid sk-private');
    process.emitErr('Bearer secret sk-private api_key=hidden');
    await flush();
    expect(logs.join(), isNot(contains('secret')));
    expect(logs.join(), isNot(contains('sk-private')));
    expect(logs.join(), isNot(contains('hidden')));
    expect(logs.first, contains('JSON inválida'));
    await rpc.stop();
  });

  test('process exit fails outstanding calls', () async {
    final process = FakeProcess();
    final rpc = CodexRpc(process);
    rpc.messages.stream.listen((_) {});
    final pending = expectLater(
      rpc.request('pending', {}),
      throwsA(isA<AgentUnavailable>()),
    );
    await process.finish(1);
    await pending;
    await rpc.stop();
  });
}
