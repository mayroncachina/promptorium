import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The spec open in the Specs editor, for "Executar" outside the editor:
/// the agents read the file, so unsaved text (a fresh Plano) is saved first.
class SpecEditorHandle {
  int? _specId;
  Future<bool> Function()? _save;
  bool Function()? _dirty;

  void bind(int specId, Future<bool> Function() save, bool Function() dirty) {
    _specId = specId;
    _save = save;
    _dirty = dirty;
  }

  void unbind(Future<bool> Function()? save) {
    if (save != null && _save != save) return;
    _specId = null;
    _save = null;
    _dirty = null;
  }

  /// Whether [specId] is open with text not on disk.
  bool unsaved(int specId) => _specId == specId && (_dirty?.call() ?? false);

  /// Saves [specId] if it is open with unsaved text; false when it failed.
  Future<bool> saveIfUnsaved(int specId) async {
    if (!unsaved(specId)) return true;
    return await _save!();
  }
}

final specEditorHandleProvider = Provider<SpecEditorHandle>(
  (ref) => SpecEditorHandle(),
);
