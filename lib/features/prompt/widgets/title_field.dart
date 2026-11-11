import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ui/theme/tokens.dart';

/// Longest title of a conversation (SPEC-056 R3).
const maxTitleLength = 120;

/// Message under an empty title (R3).
const emptyTitleMessage =
    'O título não pode ficar vazio. Esc volta ao anterior.';

/// [text] as a title: trimmed, one line, at most [maxTitleLength]
/// characters; null when nothing is left (R3).
String? normalizeTitle(String text) {
  final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return null;
  return t.length > maxTitleLength ? t.substring(0, maxTitleLength) : t;
}

/// The title being edited, in the header or in a row of the list (R2):
/// starts with the whole text selected, Enter or leaving saves, Esc goes back
/// to [initial]. An empty title shows [emptyTitleMessage] and is not saved.
class TitleField extends StatefulWidget {
  const TitleField({
    super.key,
    required this.initial,
    required this.onSave,
    required this.onCancel,
    this.compact = false,
    this.fieldKey,
  });

  final String initial;

  /// Called once with the normalized title (only when it changed).
  final ValueChanged<String> onSave;
  final VoidCallback onCancel;

  /// In a row of the list: smaller, without the buttons and the hint.
  final bool compact;
  final Key? fieldKey;

  @override
  State<TitleField> createState() => _TitleFieldState();
}

class _TitleFieldState extends State<TitleField> {
  late final _text = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );
  final _focus = FocusNode(debugLabel: 'title-field');
  bool _done = false;

  bool get _empty => normalizeTitle(_text.text) == null;

  @override
  void initState() {
    super.initState();
    _text.addListener(_changed);
    _focus.addListener(_onFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    // Leaving with the screen or the selection is not a save.
    _focus.removeListener(_onFocus);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool _wasEmpty = false;

  void _changed() {
    if (_empty != _wasEmpty) setState(() => _wasEmpty = _empty);
  }

  /// Leaving the field saves (R2); an empty one goes back to the title.
  void _onFocus() {
    if (_focus.hasFocus || _done) return;
    if (_empty) {
      _cancel();
    } else {
      _save();
    }
  }

  void _save() {
    if (_done) return;
    final t = normalizeTitle(_text.text);
    if (t == null) {
      // Enter on an empty title: the message stays, nothing is saved.
      _focus.requestFocus();
      return;
    }
    _done = true;
    if (t == widget.initial) {
      widget.onCancel();
    } else {
      widget.onSave(t);
    }
  }

  void _cancel() {
    if (_done) return;
    _done = true;
    widget.onCancel();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final error = _empty;
    final compact = widget.compact;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(compact ? 6 : 8),
      borderSide: BorderSide(
        color: error ? AppColors.red : AppColors.amber,
        width: 1.5,
      ),
    );
    final field = Focus(
      onKeyEvent: _onKey,
      child: TextField(
        key: widget.fieldKey,
        controller: _text,
        focusNode: _focus,
        maxLines: 1,
        inputFormatters: [
          LengthLimitingTextInputFormatter(maxTitleLength),
          FilteringTextInputFormatter.deny(RegExp(r'[\n\r]')),
        ],
        onSubmitted: (_) => _save(),
        style: TextStyle(
          fontSize: compact ? 13 : 15,
          fontWeight: compact ? FontWeight.w500 : FontWeight.w600,
          color: AppColors.text,
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AppColors.background,
          contentPadding: EdgeInsets.symmetric(
            horizontal: 10,
            vertical: compact ? 8 : 9,
          ),
          enabledBorder: border,
          focusedBorder: border,
          border: border,
          semanticCounterText: '',
          hintText: 'Título da conversa',
        ),
      ),
    );
    final message = error
        ? Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 14,
                    color: AppColors.red,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      emptyTitleMessage,
                      key: const ValueKey('title-empty-error'),
                      style: TextStyle(
                        fontSize: compact ? 11 : 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        : null;
    if (compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [field, ?message],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: field),
            const SizedBox(width: 8),
            // Inside the field's tap region (a click here is not a blur
            // that saves) and out of Tab: Enter and Esc are the keyboard's.
            TextFieldTapRegion(
              child: ExcludeFocus(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _IconAction(
                      key: const ValueKey('title-save'),
                      icon: Icons.check,
                      tooltip: 'Salvar título',
                      color: AppColors.teal,
                      onPressed: error ? null : _save,
                    ),
                    _IconAction(
                      key: const ValueKey('title-cancel'),
                      icon: Icons.close,
                      tooltip: 'Cancelar',
                      color: AppColors.textSecondary,
                      onPressed: _cancel,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            const ExcludeSemantics(
              child: Text(
                'Enter salva · Esc cancela',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
        ?message,
      ],
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 28,
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      iconSize: 16,
      color: color,
      icon: Icon(icon),
    ),
  );
}
