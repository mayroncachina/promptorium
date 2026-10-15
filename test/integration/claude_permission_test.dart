@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/claude/claude_cli.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/core/claude/claude_process.dart';
import 'package:uuid/uuid.dart';

/// Real CLI round trip (plano, Fase 4): Bash request → control_request →
/// allow → command runs → result success. Costs ~US$ 0.01 with haiku.
void main() {
  test('Bash permission via stdio is approved and the command runs', () async {
    final home = Platform.environment['HOME'] ?? '';
    final cli = await detectClaudeCli(
      run: Process.run,
      candidates: ['claude', '$home/.local/bin/claude'],
    );
    final dir = Directory.systemTemp.createTempSync('promptorium-int-');
    addTearDown(() => dir.deleteSync(recursive: true));

    final p = await ClaudeProcess.start(
      ClaudeOptions(
        sessionId: const Uuid().v4(),
        model: 'haiku',
        permissionMode: ClaudePermissionMode.defaultMode,
        strictMcpConfig: true,
        maxBudgetUsd: 0.05,
        maxTurns: 4,
        includePartialMessages: false,
      ),
      workingDirectory: dir.path,
      executable: cli.executable,
    );
    final logs = <String>[];
    p.logs.listen(logs.add);

    final seen = <ClaudeEvent>[];
    PermissionRequest? request;
    Result? result;
    await p.send(
      'Use the Bash tool to run exactly: echo promptorium-ok > saida.txt . '
      'Do nothing else.',
    );
    await for (final e in p.events.timeout(const Duration(minutes: 2))) {
      seen.add(e);
      if (e is PermissionRequest && request == null) {
        request = e;
        await p.allow(e.requestId);
      } else if (e is Result) {
        result = e;
        break;
      }
    }
    await p.stop();

    // ignore: avoid_print
    print(
      'integração: tool=${request?.toolName} input=${request?.input} '
      'result=${result?.subtype} custo=${result?.totalCostUsd} '
      'turnos=${result?.numTurns} eventos=${seen.length} '
      'desconhecidos=${seen.whereType<UnknownEvent>().length}',
    );
    expect(request, isNotNull, reason: 'stderr: ${logs.join('\n')}');
    expect(request!.toolName, 'Bash');
    expect(request.input['command'], contains('promptorium-ok'));
    expect(result, isNotNull);
    expect(result!.subtype, 'success');
    expect(seen.whereType<ToolResult>().any((r) => !r.isError), isTrue);
    expect(
      File('${dir.path}/saida.txt').readAsStringSync().trim(),
      'promptorium-ok',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
