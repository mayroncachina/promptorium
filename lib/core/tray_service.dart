import 'dart:async';

import 'package:flutter/foundation.dart';

/// One item of the tray icon's menu.
typedef TrayMenuEntry = ({String label, Future<void> Function() onSelected});

/// What the tray icon needs from the native side (SPEC-020). The real one is
/// `NativeTrayBackend` (`tray_backend_native.dart`); tests use a fake.
abstract class TrayBackend {
  /// Shows the icon with [tooltip] and [menu]. [onActivate] runs on a click
  /// on the icon (KDE: a single click; GNOME's AppIndicator: a double click).
  /// Throws when the tray cannot be used (no session bus, missing library…).
  Future<void> show({
    required String iconAsset,
    required String tooltip,
    required List<TrayMenuEntry> menu,
    required Future<void> Function() onActivate,
  });

  /// Removes the icon.
  Future<void> dispose();
}

/// The window operations the tray icon drives (window_manager in the app).
abstract class TrayWindow {
  Future<bool> isVisible();
  Future<bool> isMinimized();
  Future<bool> isFocused();
  Future<void> show();
  Future<void> restore();
  Future<void> focus();
  Future<void> hide();
}

/// The Promptorium tray icon, Linux only (SPEC-020).
///
/// - A click shows, restores and focuses a hidden or minimized window (R2) and
///   hides a visible, focused one (R3). Hiding only hides: sessions, PTYs and
///   schedules keep running (R5).
/// - The menu has "Abrir" (R2) and "Sair", which runs [onQuit] — the same path
///   as closing the window (R4, R6).
/// - A tray that cannot be created is logged and ignored (R7); outside Linux
///   nothing is created (R8).
class TrayService {
  TrayService({
    required this.isLinux,
    required TrayBackend Function() backend,
    required this.window,
    required this.onQuit,
    void Function(String message)? log,
  }) : _backendFactory = backend,
       _log = log ?? debugPrint;

  static const iconAsset = 'assets/icon/icon-64.png';
  static const tooltip = 'Promptorium';
  static const openLabel = 'Abrir';
  static const quitLabel = 'Sair';

  final bool isLinux;
  final TrayWindow window;

  /// Ends the app the way closing the window does (stops sessions, PTYs and
  /// conversations, then destroys the window).
  final Future<void> Function() onQuit;

  final TrayBackend Function() _backendFactory;
  final void Function(String message) _log;
  TrayBackend? _backend;
  bool _quitting = false;

  /// Whether the icon is up.
  bool get isActive => _backend != null;

  /// Creates the icon. Never throws: returns false when there is none.
  Future<bool> start() async {
    if (!isLinux || _backend != null) return _backend != null;
    TrayBackend? backend;
    try {
      backend = _backendFactory();
      await backend.show(
        iconAsset: iconAsset,
        tooltip: tooltip,
        menu: [
          (label: openLabel, onSelected: open),
          (label: quitLabel, onSelected: quit),
        ],
        onActivate: toggle,
      );
      _backend = backend;
      return true;
    } catch (e) {
      _log('bandeja indisponível, seguindo sem o ícone: $e');
      if (backend != null) {
        try {
          await backend.dispose();
        } catch (_) {}
      }
      return false;
    }
  }

  /// A click on the icon: hides a visible, focused window; otherwise brings
  /// it to the front.
  Future<void> toggle() async {
    try {
      final visible = await window.isVisible();
      final minimized = visible && await window.isMinimized();
      final focused = visible && !minimized && await window.isFocused();
      if (focused) {
        await window.hide();
      } else {
        await _bringToFront(minimized: minimized);
      }
    } catch (e) {
      _log('bandeja: falha ao alternar a janela — $e');
    }
  }

  /// "Abrir": shows, restores and focuses the window.
  Future<void> open() async {
    try {
      final minimized = await window.isMinimized();
      await _bringToFront(minimized: minimized);
    } catch (e) {
      _log('bandeja: falha ao abrir a janela — $e');
    }
  }

  /// "Sair": removes the icon and ends the app through [onQuit].
  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    await dispose();
    await onQuit();
  }

  /// Removes the icon, if any.
  Future<void> dispose() async {
    final backend = _backend;
    _backend = null;
    if (backend == null) return;
    try {
      await backend.dispose();
    } catch (e) {
      _log('bandeja: $e');
    }
  }

  Future<void> _bringToFront({required bool minimized}) async {
    await window.show();
    if (minimized) await window.restore();
    await window.focus();
  }
}
