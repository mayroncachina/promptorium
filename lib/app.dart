import 'package:flutter/material.dart';

import 'features/splash/splash_screen.dart';
import 'ui/shell/app_shell.dart';
import 'ui/theme/app_theme.dart';

class PromptoriumApp extends StatelessWidget {
  const PromptoriumApp({super.key, this.showSplash = true});

  /// false skips the splash (tests).
  final bool showSplash;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Promptorium',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: _Root(showSplash: showSplash),
    );
  }
}

/// Splash first, then the IDE shell.
class _Root extends StatefulWidget {
  const _Root({required this.showSplash});

  final bool showSplash;

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  late bool _splash = widget.showSplash;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: _splash
          ? SplashScreen(
              key: const ValueKey('splash'),
              onFinished: () => setState(() => _splash = false),
            )
          : const AppShell(key: ValueKey('shell')),
    );
  }
}
