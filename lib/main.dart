import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/app_shutdown.dart';
import 'core/claude/usage_poller.dart';
import 'core/dev/dev_server.dart';
import 'core/dev/preview_browser.dart';
import 'core/git/git_service.dart';
import 'core/perf/frame_monitor.dart';
import 'core/tray_backend_native.dart';
import 'core/tray_service.dart';
import 'features/board/autopilot.dart';
import 'features/home/tray_radar.dart';
import 'features/repository/graph/commit_model_badge.dart';
import 'features/repository/graph/graph_tab.dart' show graphAuthorBadgeProvider;
import 'features/review/pr_babysitter.dart';
import 'features/sessions/session_manager.dart';
import 'ui/theme/tokens.dart';

/// Kept for the app's lifetime: the native icon goes away with its wrapper.
TrayService? _tray;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // window_manager 0.5 quick start:
  // ~/.pub-cache/hosted/pub.dev/window_manager-0.5.2/README.md ("Usage").
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(1440, 900),
    minimumSize: Size(1100, 700),
    center: true,
    backgroundColor: AppColors.backgroundSolid,
    title: 'Promptorium',
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // local_notifier 0.1.6 README ("Usage"); needs libnotify on Linux.
  try {
    await localNotifier.setup(appName: 'Promptorium');
  } catch (e) {
    debugPrint('notificações indisponíveis: $e');
  }

  // Closing the window must not leave `claude` processes orphaned: intercept
  // the close (window_manager 0.5.2 `setPreventClose` + `onWindowClose`), stop every
  // session process / PTY, then destroy the window.
  final container = ProviderContainer(
    overrides: [
      // The model of the agents' commits beside the author (SPEC-045 R9).
      graphAuthorBadgeProvider.overrideWithValue(commitModelBadge),
    ],
  );
  // A worktree that goes away (merge, discard) stops its development server
  // first (SPEC-051 R5).
  GitService.beforeRemoveWorktree = (path) => Future.wait([
    container.read(devServerRegistryProvider).stopWorktree(path),
    container.read(previewBrowserProvider).close(path),
  ]);
  await windowManager.setPreventClose(true);
  final closeHandler = _CloseHandler(container);
  windowManager.addListener(closeHandler);
  // Tray icon on Linux (SPEC-020): show/hide the window; "Sair" takes the
  // same path as closing it. Without a tray it only logs (R7).
  _tray = TrayService(
    isLinux: Platform.isLinux,
    backend: NativeTrayBackend.new,
    window: const WindowManagerTrayWindow(),
    onQuit: closeHandler.close,
    onItem: (id) => openRadarItem(container, id),
  );
  unawaited(_tray!.start());
  // The radar on the tray (SPEC-041): the listener also keeps it alive while
  // the window is hidden.
  container.listen(
    trayRadarProvider,
    (_, radar) => _tray?.update(radar.status),
    fireImmediately: true,
  );
  // Plan usage in the footer: `claude -p /usage` costs no tokens.
  final usage = container.read(usagePollerProvider);
  unawaited(usage.refresh());
  Timer.periodic(const Duration(minutes: 5), (_) => usage.refresh());
  // Idle sessions (no activity for the configured time) free their process.
  Timer.periodic(const Duration(minutes: 1), (_) {
    container.read(sessionManagerProvider.notifier).closeIdle();
    // Scheduled autopilots (F17).
    container.read(autopilotProvider.notifier).scheduleTick();
  });
  // PRs under "Acompanhar PR" (F16).
  Timer.periodic(
    const Duration(minutes: 2),
    (_) => container.read(prBabysitterProvider.notifier).tick(),
  );

  // Frame timings to a file, only with PROMPTORIUM_QUADROS (SPEC-049 R7).
  FrameMonitor.fromEnvironment();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const PromptoriumApp(),
    ),
  );
}

/// The window's close button goes through [AppShutdown], like the tray's
/// "Sair" and the update (SPEC-070 R2).
class _CloseHandler with WindowListener {
  _CloseHandler(this.container);

  final ProviderContainer container;

  @override
  void onWindowClose() => close();

  Future<void> close() => container.read(appShutdownProvider).closeWindow();
}
