import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../data/providers.dart';
import '../features/code/worktree_terminal.dart';
import '../features/prompt/conversation_manager.dart';
import '../features/prompt/compare/compare_controller.dart';
import '../features/resume/presence.dart' show presenceProvider;
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
    this._onCloseRefused,
    this.databaseTimeout = const Duration(seconds: 3),
    this.forceAfter = defaultForceAfter,
    void Function(String message)? log,
  }) : _exit = exitWith,
       _kill = kill ?? _killSelf,
       _log = log ?? debugPrint;

  /// The longest [_stopWork] takes: its slowest step, the development
  /// servers (SIGTERM, SIGKILL after 5 s, SPEC-051 R5).
  static const workTimeout = Duration(seconds: 8);

  /// Longer than [workTimeout] plus the database's 3 s, so the forced exit
  /// never cuts the log of a slow but normal shutdown (SPEC-070 R9).
  static const defaultForceAfter = Duration(seconds: 15);

  final Future<void> Function() _stopWork;
  final Future<void> Function() _closeDatabase;
  final Future<void> Function() _destroyWindow;
  final void Function(int code) _exit;
  final void Function() _kill;
  final void Function(String message) _log;

  /// Shows the window when a close is refused during an installation.
  final void Function()? _onCloseRefused;

  /// The database gets this long to close; then the app goes on without it:
  /// SQLite in WAL survives the process ending (R2).
  final Duration databaseTimeout;

  /// [exitProcess] still running after this long ends the process by force.
  final Duration forceAfter;

  Future<Duration?>? _stopping;
  bool _windowClosing = false;
  Timer? _forced;
  bool _installing = false;
  bool _closeAfterInstall = false;

  /// Whether an update is being installed (SPEC-070 R10).
  bool get installing => _installing;

  /// The update started installing: the window's close button and the
  /// tray's "Sair" wait for it (R10).
  void beginInstall() => _installing = true;

  /// The package is installed: the update now closes the app itself.
  void endInstall() => _installing = false;

  /// The update ended with the app still open (installation failed, or the
  /// launcher didn't start): a close asked during the installation happens
  /// now.
  Future<void> settleClose() async {
    _installing = false;
    if (!_closeAfterInstall) return;
    _closeAfterInstall = false;
    await closeWindow();
  }

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
  /// During an installation it doesn't close: the window comes back and the
  /// close happens when the installation ends (R10).
  Future<void> closeWindow() async {
    if (_installing) {
      _closeAfterInstall = true;
      _log(
        'encerramento: a atualização está instalando; '
        'o app fecha quando ela terminar',
      );
      _onCloseRefused?.call();
      return;
    }
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

/// Everything [AppShutdown.stop] ends before the database. Each step on its
/// own: one that fails doesn't keep the others from running (SPEC-070 R9).
Future<void> _stopWork(Ref ref) async {
  Future<void> step(String name, FutureOr<void> Function() run) async {
    try {
      await run();
    } catch (e) {
      debugPrint('encerramento: $name: $e');
    }
  }

  // SPEC-080 R1: the visto por último is written on closing.
  if (ref.exists(presenceProvider)) {
    await step('visto por último', () => ref.read(presenceProvider).flush());
  }
  await step(
    'terminais',
    () => ref.read(sessionTerminalsProvider.notifier).killAll(),
  );
  await step(
    'terminais do código',
    () => ref.read(worktreeTerminalsProvider.notifier).killAll(),
  );
  final mcp = ref.exists(appMcpServerProvider)
      ? ref.read(appMcpServerProvider)
      : null;
  await Future.wait([
    step(
      'sessões',
      () => Future.wait([
        ref.read(sessionManagerProvider.notifier).shutdown(),
        ref.read(conversationManagerProvider.notifier).shutdown(),
        // SPEC-079 R13: the sides of a comparison come back interrupted.
        if (ref.exists(compareControllerProvider))
          ref.read(compareControllerProvider.notifier).shutdown(),
      ]).timeout(const Duration(seconds: 4)),
    ),
    // Development servers: SIGTERM, SIGKILL after 5 s (SPEC-051 R5).
    step(
      'servidores',
      () => ref
          .read(devServerRegistryProvider)
          .stopAll()
          .timeout(AppShutdown.workTimeout),
    ),
    // The preview's Chromium windows (SPEC-051 R10).
    step(
      'preview',
      () => ref
          .read(previewBrowserProvider)
          .closeAll()
          .timeout(const Duration(seconds: 4)),
    ),
    // The app's MCP server (SPEC-052).
    if (mcp != null)
      step('mcp', () => mcp.stop().timeout(const Duration(seconds: 2))),
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
    onCloseRefused: () async {
      await windowManager.show();
      await windowManager.focus();
    },
  ),
);
