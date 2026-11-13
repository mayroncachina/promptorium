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
        ? AppColors.backgroundSolid.withValues(alpha: .1)
        : Colors.transparent,
  );

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: AppColors.amber,
      onPrimary: AppColors.backgroundSolid,
      secondary: AppColors.teal,
      onSecondary: AppColors.backgroundSolid,
      tertiary: AppColors.lilac,
      error: AppColors.red,
      onError: AppColors.backgroundSolid,
      surface: AppColors.panel,
      // Menus, dropdowns and other popups float over content without a
      // blur: they stay opaque (SPEC-049 R3).
      surfaceContainerLowest: AppColors.panelSolid,
      surfaceContainerLow: AppColors.panelSolid,
      surfaceContainer: AppColors.panelSolid,
      surfaceContainerHigh: AppColors.panelSolid,
      surfaceContainerHighest: AppColors.panelSolid,
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
      canvasColor: AppColors.panelSolid,
      dividerColor: AppColors.border,
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
    );

    return base.copyWith(
      // Floats over the content, as in the approved mockup (SPEC-034 R5).
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        width: 520,
        elevation: 6,
        backgroundColor: AppColors.surfaceRaisedSolid,
        actionTextColor: AppColors.amber,
        contentTextStyle: const TextStyle(color: AppColors.text, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
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
