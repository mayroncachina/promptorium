import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sessions/widgets/session_terminal.dart';

/// Shell of the user (`$SHELL`, else `/bin/bash`).
String userShell() {
  final s = Platform.environment['SHELL'];
  return s != null && s.isNotEmpty ? s : '/bin/bash';
}

/// Whether the Code screen starts the worktree terminal by itself (widget
/// tests turn it off: no real PTY).
final codeTerminalAutoStartProvider = Provider<bool>((ref) => true);

/// One interactive shell per worktree (Código, Fase 10), kept alive while
/// switching screens / worktrees; killed when the app closes ([killAll],
/// called by `main`) or the container is disposed.
class WorktreeTerminals extends Notifier<Map<String, SessionTerminal>> {
  final Map<String, SessionTerminal> _all = {};

  @override
  Map<String, SessionTerminal> build() {
    ref.onDispose(killAll);
    return const {};
  }

  @override
  set state(Map<String, SessionTerminal> value) {
    _all
      ..clear()
      ..addAll(value);
    super.state = value;
  }

  bool isRunning(String path) => state[path]?.running ?? false;

  /// Starts `$SHELL` in [path] (no-op if one is running there).
  void open(String path) {
    final existing = state[path];
    if (existing != null && existing.running) return;
    final t = SessionTerminal(path);
    t.start(
      executable: userShell(),
      args: const [],
      cwd: path,
      // Full environment (PATH with flutter, etc.), not only flutter_pty's
      // short list.
      environment: Map.of(Platform.environment),
      onExit: () {
        if (ref.mounted) state = {...state};
      },
    );
    state = {...state, path: t};
  }

  void close(String path) {
    state[path]?.kill();
    state = {...state}..remove(path);
  }

  void killAll() {
    for (final t in _all.values) {
      t.kill();
    }
  }
}

final worktreeTerminalsProvider =
    NotifierProvider<WorktreeTerminals, Map<String, SessionTerminal>>(
      WorktreeTerminals.new,
    );
