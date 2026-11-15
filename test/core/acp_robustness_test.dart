import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/core/providers/acp_provider.dart';
import 'package:promptorium/core/providers/agent_provider.dart';

import 'claude/claude_process_test.dart' show FakeProcess;

/// SPEC-071 R12 / R15: ACP agents that hang, die or print garbage.
void main() {
  const options = AgentStartOptions(
    workingDirectory: '/w',
    mode: PromptMode.edit,
  );

  test('handshake sem resposta expira e encerra o processo (R15)', () async {
    final fake = FakeProcess();
    final provider = AcpProvider(
      id: 'acp-x',
      displayName: 'X',
      command: ['x'],
      starter: (exe, args, {workingDirectory, environment}) async => fake,
      handshakeTimeout: const Duration(milliseconds: 100),
    );
    await expectLater(
      provider.start(options),
      throwsA(
        isA<AgentUnavailable>().having(
          (e) => e.message,
          'message',
          contains('initialize'),
        ),
      ),
    );
    expect(fake.signals, contains(ProcessSignal.sigterm));
  });

  test('erro no session/new encerra o processo (R15)', () async {
    final fake = FakeProcess();
    final provider = AcpProvider(
      id: 'acp-x',
      displayName: 'X',
      command: ['x'],
      starter: (exe, args, {workingDirectory, environment}) async => fake,
    );
    final starting = provider.start(options);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    fake.emit(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': {}}));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    fake.emit(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 2,
        'error': {'code': -1, 'message': 'sem sessão'},
      }),
    );
    await expectLater(starting, throwsA(anything));
    expect(fake.signals, contains(ProcessSignal.sigterm));
  });

  test(
    'agente que fecha o stdin não gera erro assíncrono solto (R15)',
    () async {
      final provider = AcpProvider(
        id: 'acp-x',
        displayName: 'X',
        command: ['sh'],
        // Closes its stdin at once: our writes hit a broken pipe.
        starter: (exe, args, {workingDirectory, environment}) =>
            Process.start('sh', ['-c', 'exec 0<&-; sleep 5']),
        handshakeTimeout: const Duration(milliseconds: 300),
      );
      await expectLater(
        provider.start(options),
        throwsA(isA<AgentUnavailable>()),
      );
      // Give the stdin error time to surface (it would fail the test zone).
      await Future<void>.delayed(const Duration(milliseconds: 100));
    },
  );

  test('bytes fora de UTF-8 não encerram os streams (R12)', () async {
    final fake = FakeProcess();
    final provider = AcpProvider(
      id: 'acp-x',
      displayName: 'X',
      command: ['x'],
      starter: (exe, args, {workingDirectory, environment}) async => fake,
    );
    final starting = provider.start(options);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    fake.stdoutCtl.add([0x6C, 0x69, 0xE9, 0x0A]); // "lié" in Latin-1
    fake.stderrCtl.add([0xFF, 0x0A]);
    fake.emit(jsonEncode({'jsonrpc': '2.0', 'id': 1, 'result': {}}));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    fake.emit(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': 2,
        'result': {'sessionId': 's1'},
      }),
    );
    final run = await starting;
    addTearDown(fake.finish);
    final events = <ClaudeEvent>[];
    run.events.listen(events.add);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect((events.single as SystemInit).sessionId, 's1');
    expect(run.isRunning, isTrue);
  });
}
