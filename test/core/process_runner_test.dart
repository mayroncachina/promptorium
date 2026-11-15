import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/gh_cli.dart';
import 'package:promptorium/core/process/process_runner.dart';

/// SPEC-071 R12 / R16: the shared process runners.
void main() {
  const script = r"printf 'a\351b'; printf 'c\377d' >&2";

  test('runner padrão e o do gh trocam bytes fora de UTF-8 (R12)', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final runs = [
      await c.read(processRunnerProvider)('sh', ['-c', script]),
      await c.read(cliRunnerProvider)('sh', ['-c', script]),
      await runKillingOnTimeout('sh', [
        '-c',
        script,
      ], timeout: const Duration(seconds: 5)),
    ];
    for (final r in runs) {
      expect(r.exitCode, 0);
      expect(r.stdout, 'a�b');
      expect(r.stderr, 'c�d');
    }
  });

  test(
    'runKillingOnTimeout encerra o processo no limite e só então falha (R16)',
    () async {
      final tmp = Directory.systemTemp.createTempSync('promptorium-run-');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final pidFile = '${tmp.path}/pid';
      final sw = Stopwatch()..start();
      await expectLater(
        runKillingOnTimeout(
          'sh',
          ['-c', 'echo \$\$ > $pidFile; trap "" TERM; sleep 30 & wait'],
          timeout: const Duration(milliseconds: 300),
          killGrace: const Duration(milliseconds: 300),
        ),
        throwsA(isA<TimeoutException>()),
      );
      // TERM ignored: SIGKILL after the grace, and the exit was awaited.
      expect(sw.elapsed, lessThan(const Duration(seconds: 3)));
      final pid = File(pidFile).readAsStringSync().trim();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final stat = File('/proc/$pid/stat');
      expect(
        !stat.existsSync() || stat.readAsStringSync().contains(') Z '),
        isTrue,
      );
    },
  );
}
