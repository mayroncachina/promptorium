import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/claude/usage_poller.dart';
import 'features/code/worktree_terminal.dart';
import 'features/prompt/conversation_manager.dart';
import 'features/review/pr_babysitter.dart';
import 'features/sessions/session_manager.dart';
import 'features/sessions/widgets/session_terminal.dart';
import 'ui/theme/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // window_manager 0.5 quick start:
  // ~/.pub-cache/hosted/pub.dev/window_manager-0.5.2/README.md ("Usage").
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(1440, 900),
    minimumSize: Size(1100, 700),
    center: true,
    backgroundColor: AppColors.background,
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
  final container = ProviderContainer();
  await windowManager.setPreventClose(true);
  windowManager.addListener(_CloseHandler(container));
  // Plan usage in the footer: `claude -p /usage` costs no tokens.
  final usage = container.read(usagePollerProvider);
  unawaited(usage.refresh());
  Timer.periodic(const Duration(minutes: 5), (_) => usage.refresh());
  // Idle sessions (no activity for the configured time) free their process.
  Timer.periodic(
    const Duration(minutes: 1),
    (_) => container.read(sessionManagerProvider.notifier).closeIdle(),
  );
  // PRs under "Acompanhar PR" (F16).
  Timer.periodic(
    const Duration(minutes: 2),
    (_) => container.read(prBabysitterProvider.notifier).tick(),
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const PromptoriumApp(),
    ),
  );
}

class _CloseHandler with WindowListener {
  _CloseHandler(this.container);

  final ProviderContainer container;
  bool _closing = false;

  @override
  void onWindowClose() => _close();

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    try {
      container.read(sessionTerminalsProvider.notifier).killAll();
      container.read(worktreeTerminalsProvider.notifier).killAll();
      await Future.wait([
        container.read(sessionManagerProvider.notifier).shutdown(),
        container.read(conversationManagerProvider.notifier).shutdown(),
      ]).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('encerramento: $e');
    }
    await windowManager.destroy();
  }
}
