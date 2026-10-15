import 'package:flutter/material.dart';

import 'ui/theme/app_theme.dart';
import 'ui/theme/tokens.dart';

class PromptoriumApp extends StatelessWidget {
  const PromptoriumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Promptorium',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const PlaceholderHome(),
    );
  }
}

/// Temporary home screen (Fase 1). Replaced by the AppShell in Fase 2.
class PlaceholderHome extends StatelessWidget {
  const PlaceholderHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/icon/icon-128.png', width: 96, height: 96),
            const SizedBox(height: 24),
            const Text(
              'Promptorium',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'O laboratório de onde operam os comandos dos seus agentes.',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            const Text(
              '> _',
              style: TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 14,
                color: AppColors.teal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
