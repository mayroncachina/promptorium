import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';

/// Zoom level (percent) of one editor, keyed by editor name ('specs', 'code').
///
/// Fase 8/10 rebuild the `re_editor` `CodeEditorStyle(fontSize: base * zoom / 100)`.
/// Persisted per editor in `app_settings` (`editor.zoom.<key>`).
class EditorZoom extends Notifier<int> {
  EditorZoom(this.editorKey);

  final String editorKey;

  static const min = 70;
  static const max = 200;
  static const step = 10;
  static const defaultValue = 100;

  @override
  int build() {
    final saved = ref
        .read(appSettingsProvider.notifier)
        .getInt(AppSettingKeys.editorZoom(editorKey));
    return (saved ?? defaultValue).clamp(min, max);
  }

  void zoomIn() => _set(state + step);

  void zoomOut() => _set(state - step);

  void reset() => _set(defaultValue);

  void _set(int value) {
    state = value.clamp(min, max);
    ref
        .read(appSettingsProvider.notifier)
        .set(AppSettingKeys.editorZoom(editorKey), '$state');
  }
}

final editorZoomProvider = NotifierProvider.family<EditorZoom, int, String>(
  EditorZoom.new,
);
