import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/core/claude/claude_process.dart';

import 'claude_event_test.dart' show permissionRequestLine;

/// In-memory [Process]: tests push stdout/stderr lines and read stdin.
class FakeProcess implements Process {
  final stdoutCtl = StreamController<List<int>>();
  final stderrCtl = StreamController<List<int>>();
  final stdinBytes = <int>[];
  final _exit = Completer<int>();
  final signals = <ProcessSignal>[];
  bool exitOnSigterm = true;
  late final IOSink _stdin = IOSink(_Capture(stdinBytes));

  void emit(String line) => stdoutCtl.add(utf8.encode('$line\n'));

  void emitErr(String line) => stderrCtl.add(utf8.encode('$line\n'));

  List<Map<String, dynamic>> get writtenJson => [
    for (final l in const LineSplitter().convert(utf8.decode(stdinBytes)))
      jsonDecode(l) as Map<String, dynamic>,
  ];

  Future<void> finish([int code = 0]) async {
    await stdoutCtl.close();
    await stderrCtl.close();
    if (!_exit.isCompleted) _exit.complete(code);
  }

  @override
  Stream<List<int>> get stdout => stdoutCtl.stream;

  @override
  Stream<List<int>> get stderr => stderrCtl.stream;

  @override
  IOSink get stdin => _stdin;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  int get pid => 4242;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    signals.add(signal);
    if (signal == ProcessSignal.sigkill ||
        (exitOnSigterm && signal == ProcessSignal.sigterm)) {
      finish(-signal.signalNumber);
    }
    return true;
  }
}

class _Capture implements StreamConsumer<List<int>> {
  _Capture(this.sink);

  final List<int> sink;

  @override
  Future<void> addStream(Stream<List<int>> stream) =>
      stream.forEach(sink.addAll);

  @override
  Future<void> close() async {}
}

void main() {
  late FakeProcess fake;
  late List<String> startedArgs;
  late String startedExe;
  String? startedCwd;

  Future<ClaudeProcess> startFake([
    ClaudeOptions options = const ClaudeOptions(),
  ]) => ClaudeProcess.start(
    options,
    workingDirectory: '/tmp/ws',
    executable: '/opt/claude',
    starter: (exe, args, {workingDirectory, environment}) async {
      startedExe = exe;
      startedArgs = args;
      startedCwd = workingDirectory;
      return fake;
    },
  );

  setUp(() => fake = FakeProcess());

  test('starts with the built args and parses stdout lines', () async {
    final p = await startFake(const ClaudeOptions(model: 'haiku'));
    expect(startedExe, '/opt/claude');
    expect(startedCwd, '/tmp/ws');
    expect(startedArgs, containsAllInOrder(['--model', 'haiku']));

    final events = <ClaudeEvent>[];
    final logs = <String>[];
    // Lines emitted before anyone listens are buffered.
    fake.emit(
      '{"type":"system","subtype":"init","session_id":"s1","model":"m"}',
    );
    await Future<void>.delayed(Duration.zero);
    final done = p.events.forEach(events.add);
    p.logs.listen(logs.add);
    fake.emit('não é json');
    // A JSON object split across two chunks is reassembled by LineSplitter.
    fake.stdoutCtl.add(utf8.encode('{"type":"res'));
    fake.stdoutCtl.add(
      utf8.encode('ult","subtype":"success","total_cost_usd":0.01}\n'),
    );
    fake.emitErr('aviso no stderr');
    await fake.finish(0);
    await done;

    expect(events[0], isA<SystemInit>());
    expect(events[0].sessionId, 's1');
    expect((events[1] as UnknownEvent).raw, 'não é json');
    expect((events[2] as Result).totalCostUsd, 0.01);
    expect(await p.exitCode, 0);
    expect(logs, contains('aviso no stderr'));
    expect(p.isRunning, isFalse);
  });

  test('send with images: image blocks first, then the text', () async {
    final p = await startFake();
    await p.send(
      'o que é isto?',
      images: const [
        ImagePart(mediaType: 'image/png', base64: 'AAAA', name: 'a.png'),
      ],
    );
    final line = jsonDecode(
      const LineSplitter().convert(utf8.decode(fake.stdinBytes)).single,
    );
    expect(line['message']['content'], [
      {
        'type': 'image',
        'source': {'type': 'base64', 'media_type': 'image/png', 'data': 'AAAA'},
      },
      {'type': 'text', 'text': 'o que é isto?'},
    ]);
  });

  test('send / allow / deny write the Fase 0.3 format to stdin', () async {
    final p = await startFake();
    final events = <ClaudeEvent>[];
    p.events.listen(events.add);

    await p.send('olá');
    fake.emit(permissionRequestLine);
    await Future<void>.delayed(Duration.zero);
    final req = events.single as PermissionRequest;
    expect(p.pendingRequestIds, ['req-1']);

    await p.allow(req.requestId);
    await p.allow(
      'req-2',
      updatedInput: {'command': 'ls'},
      updatedPermissions: [req.permissionSuggestions.first],
    );
    await p.deny('req-3', 'não pode');
    expect(p.pendingRequestIds, isEmpty);

    final lines = const LineSplitter().convert(utf8.decode(fake.stdinBytes));
    expect(lines, hasLength(4));
    expect(
      lines[0],
      '{"type":"user","message":{"role":"user","content":"olá"},'
      '"parent_tool_use_id":null}',
    );
    expect(
      lines[1],
      '{"type":"control_response","response":{"subtype":"success",'
      '"request_id":"req-1","response":{"behavior":"allow",'
      '"updatedInput":{"command":"ls -la"}}}}',
    );
    expect(fake.writtenJson[2], {
      'type': 'control_response',
      'response': {
        'subtype': 'success',
        'request_id': 'req-2',
        'response': {
          'behavior': 'allow',
          'updatedInput': {'command': 'ls'},
          'updatedPermissions': [
            {
              'type': 'addRules',
              'rules': [
                {'toolName': 'Bash', 'ruleContent': 'ls:*'},
              ],
              'behavior': 'allow',
              'destination': 'localSettings',
            },
          ],
        },
      },
    });
    expect(
      lines[3],
      '{"type":"control_response","response":{"subtype":"success",'
      '"request_id":"req-3","response":{"behavior":"deny",'
      '"message":"não pode"}}}',
    );
    await fake.finish();
  });

  test('control_cancel_request clears the pending request', () async {
    final p = await startFake();
    p.events.listen((_) {});
    fake.emit(permissionRequestLine);
    fake.emit('{"type":"control_cancel_request","request_id":"req-1"}');
    await Future<void>.delayed(Duration.zero);
    expect(p.pendingRequestIds, isEmpty);
    await fake.finish();
  });

  test('stop sends SIGTERM, then SIGKILL after the timeout', () async {
    var p = await startFake();
    expect(await p.stop(), -ProcessSignal.sigterm.signalNumber);
    expect(fake.signals, [ProcessSignal.sigterm]);

    fake = FakeProcess()..exitOnSigterm = false;
    p = await startFake();
    await p.stop(timeout: const Duration(milliseconds: 20));
    expect(fake.signals, [ProcessSignal.sigterm, ProcessSignal.sigkill]);
    // Writes after exit are dropped, not thrown.
    await p.send('tarde demais');
    expect(fake.stdinBytes, isEmpty);
  });
}
