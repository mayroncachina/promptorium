import 'package:flutter/painting.dart';

/// Design tokens copied from the mockups (docs/mockups/*.dc.html).
/// See docs/plano-implementacao.md, Fase 1 item 5.
abstract final class AppColors {
  /// Window / page background.
  static const background = Color(0xFF0E1014);

  /// Panels, sidebars, cards.
  static const panel = Color(0xFF14171D);

  /// Borders and dividers.
  static const border = Color(0xFF252B35);

  /// Primary text.
  static const text = Color(0xFFE7E9EE);

  /// Secondary / muted text.
  static const textSecondary = Color(0xFFA0A8B6);

  /// Accent: amber (active nav item, primary actions).
  static const amber = Color(0xFFF2A541);

  /// Accent: teal (success, running, CLI connected).
  static const teal = Color(0xFF4FD1B5);

  /// Accent: blue (info, links).
  static const blue = Color(0xFF8EA4C8);

  /// Accent: red (errors, denials).
  static const red = Color(0xFFF27A6E);

  /// Accent: lilac (subagents, AI actions).
  static const lilac = Color(0xFFC79BF2);
}

/// Font families bundled in assets/fonts (registered in pubspec.yaml).
abstract final class AppFonts {
  static const sans = 'IBM Plex Sans';
  static const mono = 'JetBrains Mono';
}
