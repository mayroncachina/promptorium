import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Starts a detached process (tests replace it).
typedef DetachedStarter = Future<void> Function(
  String exe,
  List<String> args,
  String cwd,
);

Future<void> _startDetached(String exe, List<String> args, String cwd) async {
  await Process.start(
    exe,
    args,
    workingDirectory: cwd,
    mode: ProcessStartMode.detached,
  );
}

/// Opens a worktree in the system terminal or in the editor, without
/// touching the project root (SPEC-032 R9).
class WorktreeLauncher {
  WorktreeLauncher({DetachedStarter? start, this.which = _which})
    : _start = start ?? _startDetached;

  final DetachedStarter _start;

  /// Whether an executable is on the PATH.
  final Future<bool> Function(String exe) which;

  static Future<bool> _which(String exe) async {
    try {
      return (await Process.run('which', [exe])).exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  /// Terminals tried in order.
  static const terminals = [
    'x-terminal-emulator',
    'gnome-terminal',
    'konsole',
    'xterm',
  ];

  /// Opens a terminal in [path]; with [command], runs it there and keeps the
  /// shell open afterwards. Returns the terminal used, or null (none found).
  Future<String?> terminal(String path, [String? command]) async {
    for (final t in terminals) {
      if (!await which(t)) continue;
      final shell = command == null
          ? null
          : ['bash', '-lc', '$command; exec bash'];
      final args = shell == null
          ? <String>[]
          : switch (t) {
              'gnome-terminal' => ['--', ...shell],
              _ => ['-e', ...shell],
            };
      try {
        await _start(t, args, path);
        return t;
      } on ProcessException catch (e) {
        debugPrint('$t: $e');
      }
    }
    return null;
  }

  /// Opens [path] in [editor] (default `code`), or in the file manager
  /// (`xdg-open`) when the editor is not installed. Returns what was used.
  Future<String> editor(String path, {String? editor}) async {
    final parts = (editor?.trim().isNotEmpty ?? false)
        ? editor!.trim().split(RegExp(r'\s+'))
        : ['code'];
    if (await which(parts.first)) {
      await _start(parts.first, [...parts.skip(1), path], path);
      return parts.first;
    }
    await _start('xdg-open', [path], path);
    return 'xdg-open';
  }
}

final worktreeLauncherProvider = Provider<WorktreeLauncher>(
  (ref) => WorktreeLauncher(),
);
