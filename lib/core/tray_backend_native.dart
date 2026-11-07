import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:window_manager/window_manager.dart';

import 'tray_service.dart';

/// [TrayBackend] on tray_manager 0.8's native API (a StatusNotifierItem over
/// D-Bus on Linux; no libayatana-appindicator). See
/// ~/.pub-cache/hosted/pub.dev/tray_manager-0.8.0/README.md ("Usage", "Moving
/// to the native API").
class NativeTrayBackend implements TrayBackend {
  // Kept for as long as the icon is shown: a collected wrapper removes it.
  tray.TrayIcon? _icon;
  tray.Menu? _menu;
  List<tray.MenuItem> _items = [];

  @override
  Future<void> show({
    required String iconAsset,
    required String tooltip,
    required List<TrayMenuEntry> menu,
    required Future<void> Function() onActivate,
  }) async {
    if (!tray.TrayManager.instance.isSupported()) {
      throw StateError('sem barramento de sessão D-Bus');
    }
    final icon = tray.TrayIcon.create();
    if (icon == null) throw StateError('não foi possível criar o ícone');
    _icon = icon;
    final image = tray.ImageAsset.fromAsset(iconAsset);
    if (image == null) throw TrayIconUnavailable(iconAsset);
    icon.icon = image;
    icon.setTooltip(tooltip);

    final (nativeMenu, items) = _build(menu);
    _menu = nativeMenu;
    _items = items;
    icon.setContextMenu(nativeMenu);
    // The panel opens the menu on a secondary click; a primary click (KDE) or
    // a double click (GNOME's AppIndicator extension) reaches [onActivate].
    icon.setContextMenuTrigger(tray.ContextMenuTrigger.rightClicked);
    icon.addListener((event) {
      if (event is tray.TrayIconClickedEvent ||
          event is tray.TrayIconDoubleClickedEvent) {
        unawaited(onActivate());
      }
    });
    if (!icon.setVisible(true)) {
      debugPrint('bandeja: o painel pode não exibir o ícone');
    }
  }

  /// The new icon and menu are built before anything changes, so a failure
  /// leaves the tray as it was; the old menu is freed only after the swap.
  @override
  Future<void> update({
    required String iconAsset,
    required String tooltip,
    required List<TrayMenuEntry> menu,
  }) async {
    final icon = _icon;
    if (icon == null) return;
    final image = tray.ImageAsset.fromAsset(iconAsset);
    if (image == null) throw TrayIconUnavailable(iconAsset);
    final (nativeMenu, items) = _build(menu);
    final oldMenu = _menu, oldItems = _items;
    icon.icon = image;
    icon.setTooltip(tooltip);
    icon.setContextMenu(nativeMenu);
    _menu = nativeMenu;
    _items = items;
    _free(oldMenu, oldItems);
  }

  (tray.Menu, List<tray.MenuItem>) _build(List<TrayMenuEntry> entries) {
    final menu = tray.Menu.create();
    if (menu == null) throw StateError('não foi possível criar o menu');
    final items = <tray.MenuItem>[];
    for (final entry in entries) {
      if (entry.isSeparator) {
        menu.addSeparator();
        continue;
      }
      final item = tray.MenuItem.createWithLabelAndType(
        entry.label,
        tray.MenuItemType.normal,
      );
      if (item == null) continue;
      final onSelected = entry.onSelected;
      if (onSelected == null) {
        item.isEnabled = false;
      } else {
        item.addListener((event) {
          if (event is tray.MenuItemClickedEvent) unawaited(onSelected());
        });
      }
      menu.addItem(item);
      items.add(item);
    }
    return (menu, items);
  }

  void _free(tray.Menu? menu, List<tray.MenuItem> items) {
    for (final item in items) {
      item.dispose();
    }
    menu?.dispose();
  }

  @override
  Future<void> dispose() async {
    _icon?.dispose();
    _icon = null;
    _free(_menu, _items);
    _items = [];
    _menu = null;
  }
}

/// [TrayWindow] on window_manager 0.5.
class WindowManagerTrayWindow implements TrayWindow {
  const WindowManagerTrayWindow();

  @override
  Future<bool> isVisible() => windowManager.isVisible();
  @override
  Future<bool> isMinimized() => windowManager.isMinimized();
  @override
  Future<bool> isFocused() => windowManager.isFocused();
  @override
  Future<void> show() => windowManager.show();
  @override
  Future<void> restore() => windowManager.restore();
  @override
  Future<void> focus() => windowManager.focus();
  @override
  Future<void> hide() => windowManager.hide();
}
