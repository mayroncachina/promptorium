import 'dart:async';

import 'package:flutter/foundation.dart';

/// One item of the tray icon's menu. Without [onSelected] it is disabled.
class TrayMenuEntry {
  const TrayMenuEntry(this.label, [this.onSelected]) : isSeparator = false;

  const TrayMenuEntry.separator()
    : label = '',
      onSelected = null,
      isSeparator = true;

  final String label;
  final Future<void> Function()? onSelected;
  final bool isSeparator;
}

/// The overall state shown on the icon (SPEC-041 R1), most urgent first.
enum TrayState {
  attention('assets/icon/tray/tray-attention-24.png'),
  problem('assets/icon/tray/tray-problem-24.png'),
  working('assets/icon/tray/tray-working-24.png'),
  idle('assets/icon/tray/tray-idle-24.png');

  const TrayState(this.asset);

  final String asset;
}

/// A line of the radar in the menu: a heading when [id] is null, a clickable
/// item otherwise, a separator with [TrayRow.separator].
@immutable
class TrayRow {
  const TrayRow(this.label, {this.id}) : isSeparator = false;

  const TrayRow.separator() : label = '', id = null, isSeparator = true;

  final String label;
  final String? id;
  final bool isSeparator;

  @override
  bool operator ==(Object other) =>
      other is TrayRow &&
      other.label == label &&
      other.id == id &&
      other.isSeparator == isSeparator;

  @override
  int get hashCode => Object.hash(label, id, isSeparator);
}

/// What the tray shows (SPEC-041): the icon, the tooltip and the radar lines
/// above "Abrir" and "Sair".
@immutable
class TrayStatus {
  const TrayStatus({
    this.state = TrayState.idle,
    this.tooltip = TrayService.tooltip,
    this.rows = const [],
  });

  final TrayState state;
  final String tooltip;
  final List<TrayRow> rows;

  @override
  bool operator ==(Object other) =>
      other is TrayStatus &&
      other.state == state &&
      other.tooltip == tooltip &&
      listEquals(other.rows, rows);

  @override
  int get hashCode => Object.hash(state, tooltip, Object.hashAll(rows));
}

/// Thrown by a [TrayBackend] when it cannot load the icon asset, so the tray
/// can try the fallback icon (SPEC-029 R6) instead of giving up.
class TrayIconUnavailable implements Exception {
  TrayIconUnavailable(this.asset);
  final String asset;
  @override
  String toString() => 'ícone não encontrado: $asset';
}

/// What the tray icon needs from the native side (SPEC-020). The real one is
/// `NativeTrayBackend` (`tray_backend_native.dart`); tests use a fake.
abstract class TrayBackend {
  /// Shows the icon with [tooltip] and [menu]. [onActivate] runs on a click
  /// on the icon (KDE: a single click; GNOME's AppIndicator: a double click).
  /// Throws [TrayIconUnavailable] when [iconAsset] cannot be loaded, and
  /// other errors when the tray cannot be used (no session bus, missing
  /// library…).
  Future<void> show({
    required String iconAsset,
    required String tooltip,
    required List<TrayMenuEntry> menu,
    required Future<void> Function() onActivate,
  });

  /// Replaces what [show] put up. Throws, leaving the tray as it was, when
  /// the icon or the menu cannot be built (SPEC-041 R9).
  Future<void> update({
    required String iconAsset,
    required String tooltip,
    required List<TrayMenuEntry> menu,
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
/// - [update] shows the radar (SPEC-041): state on the icon, numbers on the
///   tooltip, items in the menu. A click on an item brings the window to the
///   front and runs [onItem]; the menu never acts on the item (R7).
class TrayService {
  TrayService({
    required this.isLinux,
    required TrayBackend Function() backend,
    required this.window,
    required this.onQuit,
    this.onItem,
    this.minInterval = const Duration(seconds: 1),
    void Function(String message)? log,
  }) : _backendFactory = backend,
       _log = log ?? debugPrint;

  /// The flask of the idle state (SPEC-041): same size and position as in the
  /// other states, so it does not jump when the state changes.
  static final iconAsset = TrayState.idle.asset;

  /// The mark without the dark square (SPEC-029 R3): 24 px, the size top
  /// bars use; the panel scales it for HiDPI. Used when [iconAsset] cannot
  /// be loaded.
  static const markIconAsset = 'assets/icon/mark/mark-24.png';

  /// The previous square icon, used when the mark cannot be loaded (R6).
  static const fallbackIconAsset = 'assets/icon/icon-64.png';
  static const tooltip = 'Promptorium';
  static const openLabel = 'Abrir';
  static const quitLabel = 'Sair';

  final bool isLinux;
  final TrayWindow window;

  /// Ends the app the way closing the window does (stops sessions, PTYs and
  /// conversations, then destroys the window).
  final Future<void> Function() onQuit;

  /// Opens the radar item with this id (SPEC-041 R6), after the window comes
  /// to the front.
  final Future<void> Function(String id)? onItem;

  /// The shortest time between two native updates (SPEC-041 R8).
  final Duration minInterval;

  final TrayBackend Function() _backendFactory;
  final void Function(String message) _log;
  TrayBackend? _backend;
  bool _quitting = false;
  TrayStatus _applied = const TrayStatus();
  TrayStatus _wanted = const TrayStatus();
  TrayStatus? _failed;
  Timer? _cooldown;

  /// Whether the icon is up.
  bool get isActive => _backend != null;

  /// Creates the icon. Never throws: returns false when there is none.
  Future<bool> start() async {
    if (!isLinux || _backend != null) return _backend != null;
    for (final asset in [iconAsset, markIconAsset, fallbackIconAsset]) {
      TrayBackend? backend;
      try {
        backend = _backendFactory();
        await backend.show(
          iconAsset: asset,
          tooltip: tooltip,
          menu: _menu(const []),
          onActivate: toggle,
        );
        _backend = backend;
        unawaited(_flush());
        return true;
      } catch (e) {
        if (backend != null) {
          try {
            await backend.dispose();
          } catch (_) {}
        }
        if (e is TrayIconUnavailable && asset != fallbackIconAsset) {
          _log('bandeja: marca indisponível, usando o ícone anterior: $e');
          continue;
        }
        _log('bandeja indisponível, seguindo sem o ícone: $e');
        return false;
      }
    }
    return false;
  }

  /// Shows [status] (SPEC-041). A change is applied at once, or when
  /// [minInterval] has passed since the last one; an equal status costs
  /// nothing. Without a tray it only remembers the status for [start].
  void update(TrayStatus status) {
    _wanted = status;
    unawaited(_flush());
  }

  Future<void> _flush() async {
    final backend = _backend;
    if (backend == null || _cooldown != null) return;
    if (_wanted == _applied || _wanted == _failed) return;
    final status = _wanted;
    _cooldown = Timer(minInterval, () {
      _cooldown = null;
      unawaited(_flush());
    });
    try {
      await backend.update(
        iconAsset: status.state.asset,
        tooltip: status.tooltip,
        menu: _menu(status.rows),
      );
      _applied = status;
      _failed = null;
    } catch (e) {
      // What is on the tray stays; the next change tries again (R9).
      _failed = status;
      _log('bandeja: falha ao atualizar — $e');
    }
  }

  List<TrayMenuEntry> _menu(List<TrayRow> rows) => [
    for (final row in rows)
      if (row.isSeparator)
        const TrayMenuEntry.separator()
      else
        TrayMenuEntry(
          // In DBusMenu a lone "_" marks a mnemonic and vanishes from the label.
          row.label.replaceAll('_', '__'),
          row.id == null ? null : () => _openItem(row.id!),
        ),
    if (rows.isNotEmpty) const TrayMenuEntry.separator(),
    TrayMenuEntry(openLabel, open),
    TrayMenuEntry(quitLabel, quit),
  ];

  /// A radar item: the same as "Abrir", then its destination.
  Future<void> _openItem(String id) async {
    await open();
    try {
      await onItem?.call(id);
    } catch (e) {
      _log('bandeja: falha ao abrir o item — $e');
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
    _cooldown?.cancel();
    _cooldown = null;
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
