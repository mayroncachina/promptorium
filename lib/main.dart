import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
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
      await container
          .read(sessionManagerProvider.notifier)
          .shutdown()
          .timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('encerramento: $e');
    }
    await windowManager.destroy();
  }
}
