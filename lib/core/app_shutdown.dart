import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../data/providers.dart';
import '../features/code/worktree_terminal.dart';
import '../features/prompt/conversation_manager.dart';
import '../features/sessions/session_manager.dart';
import '../features/sessions/widgets/session_terminal.dart';
import 'dev/dev_server.dart';
import 'dev/preview_browser.dart';
import 'mcp/app_mcp_config.dart';

/// How the app goes away (SPEC-070 R2): the window's close button, the tray's
/// "Sair" and the update all stop the same things, in the same order, with
/// the same time limits.
class AppShutdown {
  AppShutdown({
    required this._stopWork,
    required this._closeDatabase,
    required this._destroyWindow,
    void Function(int code) exitWith = exit,
    void Function()? kill,
    this.databaseTimeout = const Duration(seconds: 3),
    this.forceAfter = const Duration(seconds: 10),
    void Function(String message)? log,
  }) : _exit = exitWith,
       _kill = kill ?? _killSelf,
       _log = log ?? debugPrint;

  final Future<void> Function() _stopWork;
  final Future<void> Function() _closeDatabase;
  final Future<void> Function() _destroyWindow;
  final void Function(int code) _exit;
  final void Function() _kill;
  final void Function(String message) _log;

  /// The database gets this long to close; then the app goes on without it:
  /// SQLite in WAL survives the process ending (R2).
  final Duration databaseTimeout;

  /// [exitProcess] still running after this long ends the process by force.
  final Duration forceAfter;

  Future<Duration?>? _stopping;
  bool _windowClosing = false;
  Timer? _forced;

  static void _killSelf() => Process.killPid(pid, ProcessSignal.sigkill);

  /// Stops sessions, conversations, PTYs, development servers, the preview's
  /// Chromium and the MCP server, then closes the database. Runs once; later
  /// calls get the same result: how long the database took to close, or null
  /// when it didn't close within [databaseTimeout].
  Future<Duration?> stop() => _stopping ??= _stop();

  Future<Duration?> _stop() async {
    try {
      await _stopWork();
    } catch (e) {
      _log('encerramento: $e');
    }
    final watch = Stopwatch()..start();
    try {
      await _closeDatabase().timeout(databaseTimeout);
      return watch.elapsed;
    } on TimeoutException {
      return null;
    } catch (e) {
      _log('encerramento: banco: $e');
      return watch.elapsed;
    }
  }

  /// The window's close button and the tray's "Sair" (SPEC-020 R6).
  Future<void> closeWindow() async {
    if (_windowClosing) return;
    _windowClosing = true;
    final closed = await stop();
    if (closed == null) {
      _log(
        'encerramento: o banco não fechou em '
        '${databaseTimeout.inSeconds} s; saindo assim mesmo',
      );
    }
    await _destroyWindow();
  }

  /// Stops everything ([stop]) and exits with code 0, each step on [log].
  /// Still alive [forceAfter] after the call, the process is killed.
  Future<void> exitProcess({void Function(String message)? log}) async {
    final say = log ?? _log;
    say('encerrando');
    _forced ??= Timer(forceAfter, () {
      say('ainda aberto ${forceAfter.inSeconds} s depois; saindo à força');
      _kill();
    });
    final closed = await stop();
    say(
      closed == null
          ? 'o banco não fechou em ${databaseTimeout.inSeconds} s; '
                'saindo assim mesmo'
          : 'banco fechado em ${closed.inMilliseconds} ms',
    );
    say('saindo');
    _exit(0);
  }
}

/// Closes [db] to end the process. `AppDatabase.close()` first closes every
/// query stream, and drift waits for each listener to take the "done" event:
/// a stream whose subscription is paused (Riverpod pauses a provider nobody
/// is watching, like the one of a screen that was left) never takes it, and
/// the close never returns. That is what kept the update in "Instalando e
/// reiniciando…" (SPEC-070). Closing the connection alone ends SQLite (and
/// the drift isolate) without waiting for the streams, which die with the
/// process.
Future<void> closeDatabaseForExit(AppDatabase db) => db.executor.close();

/// Everything [AppShutdown.stop] ends before the database.
Future<void> _stopWork(Ref ref) async {
  ref.read(sessionTerminalsProvider.notifier).killAll();
  ref.read(worktreeTerminalsProvider.notifier).killAll();
  final mcp = ref.exists(appMcpServerProvider)
      ? ref.read(appMcpServerProvider)
      : null;
  await Future.wait([
    Future.wait([
      ref.read(sessionManagerProvider.notifier).shutdown(),
      ref.read(conversationManagerProvider.notifier).shutdown(),
    ]).timeout(const Duration(seconds: 4)),
    // Development servers: SIGTERM, SIGKILL after 5 s (SPEC-051 R5).
    ref
        .read(devServerRegistryProvider)
        .stopAll()
        .timeout(const Duration(seconds: 8)),
    // The preview's Chromium windows (SPEC-051 R10).
    ref
        .read(previewBrowserProvider)
        .closeAll()
        .timeout(const Duration(seconds: 4)),
    // The app's MCP server (SPEC-052).
    if (mcp != null) mcp.stop().timeout(const Duration(seconds: 2)),
  ]);
}

final appShutdownProvider = Provider<AppShutdown>(
  (ref) => AppShutdown(
    stopWork: () => _stopWork(ref),
    closeDatabase: () async {
      if (!ref.exists(appDatabaseProvider)) return;
      await closeDatabaseForExit(ref.read(appDatabaseProvider));
    },
    destroyWindow: windowManager.destroy,
  ),
);
