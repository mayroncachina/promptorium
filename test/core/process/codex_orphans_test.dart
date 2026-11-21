import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/codex/codex_rpc.dart';
import 'package:promptorium/core/process/orphans.dart';

/// SPEC-096 R15: the `codex app-server` leads its own process group, is
/// ended with it, and is recognized as an orphan at the next start.
void main() {
  test('orphans: a codex app-server of a saved session is ended too; '
      'another codex command or a reused PID is not', () {
    final killed = <int>[];
    final ended = killOrphans(
      {'claude': 10, 'codex': 20, 'tui': 30, 'reused': 40},
      read: (pid) => switch (pid) {
        10 => '/home/u/.local/bin/claude\x00--resume\x00claude\x00',
        20 => '/home/u/.local/bin/codex\x00app-server\x00-c\x00x=1\x00',
        30 => '/home/u/.local/bin/codex\x00resume\x00t\x00', // the TUI
        40 => '/usr/bin/vim\x00codex\x00',
        _ => null,
      },
      kill: (pid) {
        killed.add(pid);
        return true;
      },
    );
    expect(ended, ['claude', 'codex']);
    expect(killed, [10, 20]);
    expect(isCodexAppServer('codex\x00app-server\x00'), isTrue);
    expect(isCodexAppServer('/usr/bin/codex\x00login\x00'), isFalse);
  });

  test('stop ends the whole group: a child of the App Server (a command it '
      'ran) does not outlive it', () async {
    if (!File('/usr/bin/setsid').existsSync()) return;
    final tmp = Directory.systemTemp.createTempSync('codex-group-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final pidFile = File('${tmp.path}/child.pid');
    // A stand-in App Server: starts a long child and waits on stdin.
    final p = await Process.start('setsid', [
      'bash',
      '-c',
      'sleep 300 & echo \$! > ${pidFile.path}; cat',
    ]);
    final rpc = CodexRpc(p, group: true, timeout: const Duration(seconds: 2));
    for (var i = 0; i < 100 && !pidFile.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final child = int.parse(pidFile.readAsStringSync().trim());
    expect(Directory('/proc/$child').existsSync(), isTrue);
    await rpc.stop();
    for (var i = 0; i < 100 && Directory('/proc/$child').existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final status = File('/proc/$child/status');
    final alive =
        status.existsSync() && !status.readAsStringSync().contains('State:\tZ');
    expect(alive, isFalse, reason: 'o filho do grupo foi encerrado');
  });
}
