import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';

import '../../shell/editor_zoom.dart';
import '../../theme/tokens.dart';
import 'code_editor_theme.dart';
import 'code_language.dart';
import 'find_panel.dart';

export 'package:re_editor/re_editor.dart'
    show CodeLineEditingController, CodeFindController;

export 'code_language.dart';

/// Font size of an editor at [zoomPercent] (`EditorZoom`, 70–200 %).
double editorFontSize(double base, int zoomPercent) => base * zoomPercent / 100;

/// Editor shortcuts: re_editor defaults (Ctrl+F find, Ctrl+S save, …) plus
/// Ctrl+H for replace (the default on Linux is Ctrl+Alt+F, kept too).
class AppCodeShortcuts extends DefaultCodeShortcutsActivatorsBuilder {
  const AppCodeShortcuts();

  @override
  List<ShortcutActivator>? build(CodeShortcutType type) {
    final base = super.build(type);
    if (type == CodeShortcutType.replace) {
      return [
        const SingleActivator(LogicalKeyboardKey.keyH, control: true),
        ...?base,
      ];
    }
    return base;
  }
}

/// Reusable code editor (Specs, Fase 8; Código, Fase 10): re_editor
/// [CodeEditor] with the app dark theme, highlight by [language], line
/// numbers, find / replace (Ctrl+F / Ctrl+H) and zoom from
/// [editorZoomProvider] (`fontSize = baseFontSize × zoom`, saved per
/// [editorKey]; Ctrl+= / Ctrl+- / Ctrl+0 are handled by the shell for the
/// screen's editor, the "− 100% +" control is [ZoomControl]).
class AppCodeEditor extends ConsumerStatefulWidget {
  const AppCodeEditor({
    super.key,
    required this.controller,
    required this.editorKey,
    this.language = CodeLanguage.plaintext,
    this.readOnly = false,
    this.onSave,
    this.onChanged,
    this.findController,
    this.focusNode,
    this.baseFontSize = 13,
    this.wordWrap = false,
    this.autofocus = false,
    this.hint,
  });

  final CodeLineEditingController controller;

  /// Zoom key (`specs`, `code`, …): `app_settings` `editor.zoom.<key>`.
  final String editorKey;
  final CodeLanguage language;
  final bool readOnly;

  /// Ctrl+S inside the editor.
  final VoidCallback? onSave;
  final ValueChanged<CodeLineEditingValue>? onChanged;

  /// Optional external find controller (tests / toolbar buttons); one is
  /// created otherwise.
  final CodeFindController? findController;
  final FocusNode? focusNode;

  /// Font size at 100 % (mockup: 12–13 px).
  final double baseFontSize;
  final bool wordWrap;
  final bool autofocus;
  final String? hint;

  @override
  ConsumerState<AppCodeEditor> createState() => _AppCodeEditorState();
}

class _AppCodeEditorState extends ConsumerState<AppCodeEditor> {
  CodeFindController? _ownFind;

  CodeFindController get _find =>
      widget.findController ??
      (_ownFind ??= CodeFindController(widget.controller));

  @override
  void didUpdateWidget(covariant AppCodeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller && _ownFind != null) {
      _ownFind!.dispose();
      _ownFind = null;
    }
  }

  @override
  void dispose() {
    _ownFind?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zoom = ref.watch(editorZoomProvider(widget.editorKey));
    final fontSize = editorFontSize(widget.baseFontSize, zoom);
    final lang = widget.language;
    final numberStyle = TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: fontSize,
      color: CodeEditorColors.lineNumber,
    );
    return CodeEditor(
      key: ValueKey('code-editor-${widget.editorKey}'),
      controller: widget.controller,
      findController: _find,
      focusNode: widget.focusNode,
      readOnly: widget.readOnly,
      autofocus: widget.autofocus,
      wordWrap: widget.wordWrap,
      hint: widget.hint,
      onChanged: widget.onChanged,
      padding: const EdgeInsets.only(left: 6, right: 16, top: 12, bottom: 24),
      style: CodeEditorStyle(
        fontSize: fontSize,
        fontFamily: AppFonts.mono,
        fontHeight: 1.6,
        textColor: AppColors.text,
        hintTextColor: AppColors.textMuted,
        backgroundColor: AppColors.background,
        selectionColor: CodeEditorColors.selection,
        highlightColor: CodeEditorColors.findMatch,
        cursorColor: AppColors.amber,
        cursorLineColor: CodeEditorColors.cursorLine,
        chunkIndicatorColor: AppColors.textMuted,
        codeTheme: CodeHighlightTheme(
          languages: {lang.id: CodeHighlightThemeMode(mode: lang.mode)},
          theme: promptoriumCodeTheme,
        ),
      ),
      shortcutsActivatorsBuilder: const AppCodeShortcuts(),
      shortcutOverrideActions: {
        if (widget.onSave != null)
          CodeShortcutSaveIntent: CallbackAction<CodeShortcutSaveIntent>(
            onInvoke: (_) {
              widget.onSave!();
              return null;
            },
          ),
      },
      indicatorBuilder:
          (context, editingController, chunkController, notifier) => Row(
            children: [
              DefaultCodeLineNumber(
                controller: editingController,
                notifier: notifier,
                textStyle: numberStyle,
                focusedTextStyle: numberStyle.copyWith(
                  color: CodeEditorColors.lineNumberFocused,
                ),
              ),
              DefaultCodeChunkIndicator(
                width: 16,
                controller: chunkController,
                notifier: notifier,
              ),
            ],
          ),
      leadingDivider: Container(width: 1, color: AppColors.border),
      findBuilder: (context, controller, readOnly) =>
          CodeFindPanel(controller: controller, readOnly: readOnly),
    );
  }
}
