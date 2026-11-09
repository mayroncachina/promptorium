import 'package:flutter/painting.dart';

/// Design tokens copied from the mockups (docs/mockups/*.dc.html).
/// See docs/plano-implementacao.md, Fase 1 item 5.
abstract final class AppColors {
  /// Page background and the wells inside panels (code blocks, fields): a
  /// 30% black (SPEC-049 R1, R3). Over a [panelSolid] it composes to
  /// [backgroundSolid], so a well keeps its depth; over the backdrop it only
  /// dims it a little, and the lights still show.
  static const background = Color(0x4D000000);

  /// The opaque page colour: the window itself, text drawn on amber, and
  /// anything that must hide what is behind it.
  static const backgroundSolid = Color(0xFF0E1014);

  /// Border of text fields: 3:1 against the background (SPEC-039 R12).
  static const inputBorder = Color(0xFF626C7C);

  /// Panels, sidebars, cards: glass (SPEC-049 R3). Over [backgroundSolid]
  /// it composes to [panelSolid], the colour panels had before the glass.
  static const panel = Color(0x8C191D24);

  /// [panel] when it must not let anything through: surfaces content scrolls
  /// under, menus, tooltips.
  static const panelSolid = Color(0xFF14171D);

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

  /// Raised controls on panels (workspace selector, chips): glass, a step
  /// lighter than [panel]. Over [backgroundSolid] it composes to
  /// [surfaceRaisedSolid].
  static const surfaceRaised = Color(0x99222732);

  /// [surfaceRaised] when it must not let anything through.
  static const surfaceRaisedSolid = Color(0xFF1A1E26);

  /// Border of a card or button under the mouse.
  static const borderHover = Color(0xFF3A4250);

  /// Active nav item background (amber tint).
  static const amberTint = Color(0xFF2A2418);

  /// Text/icons drawn on top of amber.
  static const onAmber = Color(0xFF1A1206);

  /// Text of a disabled action, on [surfaceRaised]: 4,5:1 or more without
  /// lowering the opacity (SPEC-025 R10, SPEC-024 R10).
  static const textDisabled = Color(0xFF8A93A3);

  /// Dimmed text (splash footer, idle status).
  static const textMuted = Color(0xFF7C8595);

  /// Splash: liquid fill.
  static const liquid = Color(0xFF0E5E55);

  /// Splash: bubbles.
  static const bubble = Color(0xFF7FE6D2);

  /// Splash: chevron and caret.
  static const glowText = Color(0xFFB8FFF2);

  /// Modal barrier behind dialogs (command palette).
  static const scrim = Color(0x99000000);
}

/// Sessions-screen colors from the mockup (1 · Sessões) not in [AppColors].
abstract final class SessionColors {
  static const selectedBg = Color(0xFF1F2430);
  static const selectedBorder = Color(0xFF2E3542);
  static const approvalBg = Color(0xFF241E12);
  static const approvalBorder = Color(0xFF5C4520);
  static const stopBorder = Color(0xFF5A2E2A);
  static const runningToolBorder = Color(0xFF2F6B5E);
  static const runningToolBg = Color(0xFF11201D);
  static const addBg = Color(0xFF12241F);
  static const delBg = Color(0xFF2A1715);

  /// Border of the "Bloqueado" pill (MCP screen).
  static const blockedBorder = Color(0xFF3A4250);

  /// Terminal selection highlight.
  static const terminalSelection = Color(0x553A4458);

  /// Bottom panel (terminal) of the Code screen.
  static const terminalPanel = Color(0xFF0B0D10);
}

/// Font families bundled in assets/fonts (registered in pubspec.yaml).
abstract final class AppFonts {
  static const sans = 'IBM Plex Sans';
  static const mono = 'JetBrains Mono';
}

/// Review-screen colors from the mockup (Review.dc.html) not in [AppColors].
abstract final class ReviewColors {
  /// Line numbers of the diff.
  static const lineNumber = Color(0xFF4A5260);

  /// "Aceitar hunk" (also used for accepted hunks).
  static const acceptBorder = Color(0xFF2F6B5E);
  static const acceptBg = Color(0xFF11201D);
}

/// Canvas of the Quadro (Quadro-Canvas.dc.html), translated to the dark
/// theme. Each step state also differs by shape, not only by colour.
abstract final class CanvasColors {
  /// Dot grid of the background.
  static const grid = Color(0xFF232833);

  static const done = Color(0xFF5BC88A);
  static const running = Color(0xFFF08A4B);
  static const review = Color(0xFFE07AB0);
  static const needsInput = AppColors.amber;
  static const verifying = AppColors.teal;
  static const pending = AppColors.textMuted;

  /// Agent nodes and reference links (distinct from the running orange).
  static const agent = Color(0xFF7FA6F2);

  /// Skill nodes (distinct from the verifying teal).
  static const skill = AppColors.lilac;

  /// Tooltip cards over the canvas.
  static const tooltip = Color(0xFF1F2430);
}

/// Colour of a spec (SPEC-045 R2): its lane in the Grafo and its dot in
/// the Releases and in the commit panel. The Quadro's cards have no colour
/// of their own (only the stage pill), so the spec's colour is born here,
/// from the four tones of the mockups plus the Quadro's pink and teal, by
/// the spec number: six specs in a row never share one.
abstract final class SpecColors {
  static const palette = [
    AppColors.amber,
    Color(0xFF8EC5FF),
    Color(0xFFC59BFF),
    Color(0xFF5BC88A),
    Color(0xFFE07AB0),
    AppColors.teal,
  ];

  /// The spec (`spec/042-…`).
  static Color of(int number) => palette[number % palette.length];

  /// Its tasks (`spec/042-t4-…`): the same tone, lighter (R3).
  static Color task(int number) =>
      Color.lerp(of(number), const Color(0xFFFFFFFF), .45)!;

  /// The default branch: light grey, always on the first lane.
  static const defaultBranch = Color(0xFFC9CED8);

  /// Any other branch.
  static const other = Color(0xFF8A93A3);
}
