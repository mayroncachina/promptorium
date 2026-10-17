import 'dart:io';

import 'package:flutter/foundation.dart';

/// `/proc/<pid>/cmdline` (NUL-separated); null when the process is gone.
typedef CmdlineReader = String? Function(int pid);

String? readProcCmdline(int pid) {
  try {
    final f = File('/proc/$pid/cmdline');
    return f.existsSync() ? f.readAsStringSync() : null;
  } catch (_) {
    return null;
  }
}

/// Whether [cmdline] is the `claude` of session [sessionId] (the PID may
/// have been reused by something else after a reboot).
bool isSessionProcess(String cmdline, String sessionId) {
  final args = cmdline.split('\x00');
  return args.any((a) => a.endsWith('claude')) && args.contains(sessionId);
}

/// Ends (SIGTERM) the `claude` processes of [sessions] (id → pid) that are
/// still alive: left behind by a crash of the app. Returns the ids ended.
List<String> killOrphans(
  Map<String, int> sessions, {
  CmdlineReader read = readProcCmdline,
  bool Function(int pid)? kill,
}) {
  final ended = <String>[];
  for (final MapEntry(key: id, value: pid) in sessions.entries) {
    final cmd = read(pid);
    if (cmd == null || !isSessionProcess(cmd, id)) continue;
    try {
      if ((kill ?? (p) => Process.killPid(p))(pid)) ended.add(id);
    } catch (e) {
      debugPrint('processo órfão $pid não encerrado — $e');
    }
  }
  return ended;
}
