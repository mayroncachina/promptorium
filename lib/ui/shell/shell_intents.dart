import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'navigation.dart';

class OpenPaletteIntent extends Intent {
  const OpenPaletteIntent();
}

enum ZoomOp { zoomIn, zoomOut, reset }

class ZoomIntent extends Intent {
  const ZoomIntent(this.op);

  final ZoomOp op;
}

/// Ctrl+N: "Nova sessão".
class NewSessionIntent extends Intent {
  const NewSessionIntent();
}

class GoToSectionIntent extends Intent {
  const GoToSectionIntent(this.section);

  final AppSection section;
}

const _digits = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
];

/// Global shortcuts of the shell.
final Map<ShortcutActivator, Intent> shellShortcuts = {
  const SingleActivator(LogicalKeyboardKey.keyK, control: true):
      const OpenPaletteIntent(),
  const SingleActivator(LogicalKeyboardKey.keyN, control: true):
      const NewSessionIntent(),
  // Ctrl+= / Ctrl++ (with or without Shift, main row or numpad).
  const SingleActivator(LogicalKeyboardKey.equal, control: true):
      const ZoomIntent(ZoomOp.zoomIn),
  const SingleActivator(LogicalKeyboardKey.equal, control: true, shift: true):
      const ZoomIntent(ZoomOp.zoomIn),
  const SingleActivator(LogicalKeyboardKey.add, control: true):
      const ZoomIntent(ZoomOp.zoomIn),
  const SingleActivator(LogicalKeyboardKey.add, control: true, shift: true):
      const ZoomIntent(ZoomOp.zoomIn),
  const SingleActivator(LogicalKeyboardKey.numpadAdd, control: true):
      const ZoomIntent(ZoomOp.zoomIn),
  const SingleActivator(LogicalKeyboardKey.minus, control: true):
      const ZoomIntent(ZoomOp.zoomOut),
  const SingleActivator(LogicalKeyboardKey.numpadSubtract, control: true):
      const ZoomIntent(ZoomOp.zoomOut),
  const SingleActivator(LogicalKeyboardKey.digit0, control: true):
      const ZoomIntent(ZoomOp.reset),
  const SingleActivator(LogicalKeyboardKey.numpad0, control: true):
      const ZoomIntent(ZoomOp.reset),
  for (var i = 0; i < AppSection.navItems.length; i++)
    SingleActivator(_digits[i], control: true): GoToSectionIntent(
      AppSection.navItems[i],
    ),
};
