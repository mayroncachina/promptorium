import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Zoom level (percent) of one editor, keyed by editor name ('specs', 'code').
///
/// Fase 8/10 rebuild the `re_editor` `CodeEditorStyle(fontSize: base * zoom / 100)`.
/// Persistence (per editor) arrives with the database in Fase 3.
class EditorZoom extends Notifier<int> {
  EditorZoom(this.editorKey);

  final String editorKey;

  static const min = 70;
  static const max = 200;
  static const step = 10;
  static const defaultValue = 100;

  @override
  int build() => defaultValue;

  void zoomIn() => state = (state + step).clamp(min, max);

  void zoomOut() => state = (state - step).clamp(min, max);

  void reset() => state = defaultValue;
}

final editorZoomProvider = NotifierProvider.family<EditorZoom, int, String>(
  EditorZoom.new,
);
