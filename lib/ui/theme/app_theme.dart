import 'package:flutter/material.dart';

import '../widgets/app_pressable.dart';
import 'tokens.dart';

/// Dark theme built from [AppColors] / [AppFonts].
abstract final class AppTheme {
  /// The overlay of a [FilledButton], as in Material, minus hover: that one is
  /// the [HoverLayer] of the theme, which fades in `quick` (SPEC-034 R6). A
  /// style with its own `foregroundColor` needs this to keep the same hover.
  static final filledOverlay = WidgetStateProperty.resolveWith<Color?>(
    (states) =>
        states.contains(WidgetState.pressed) ||
            states.contains(WidgetState.focused)
        ? AppColors.background.withValues(alpha: .1)
        : Colors.transparent,
  );

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
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          overlayColor: filledOverlay,
          backgroundBuilder: (context, states, child) => Stack(
            fit: StackFit.passthrough,
            children: [
              HoverLayer(
                visible: states.contains(WidgetState.hovered),
                decoration: const BoxDecoration(
                  color: AppPressable.primaryTint,
                ),
              ),
              ?child,
            ],
          ),
        ),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.text,
        displayColor: AppColors.text,
      ),
    );
  }
}
