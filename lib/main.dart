import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
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

  runApp(const ProviderScope(child: PromptoriumApp()));
}
