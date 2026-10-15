import 'package:flutter/material.dart';

import 'tokens.dart';

/// Dark theme built from [AppColors] / [AppFonts].
abstract final class AppTheme {
  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: AppColors.amber,
      onPrimary: AppColors.background,
      secondary: AppColors.teal,
      onSecondary: AppColors.background,
      tertiary: AppColors.lilac,
      error: AppColors.red,
      onError: AppColors.background,
      surface: AppColors.panel,
      onSurface: AppColors.text,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.border,
      outlineVariant: AppColors.border,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      fontFamily: AppFonts.sans,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      dividerColor: AppColors.border,
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.text,
        displayColor: AppColors.text,
      ),
    );
  }
}
