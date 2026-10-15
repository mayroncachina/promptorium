import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_icon.dart';
import '../../review/widgets/review_dialogs.dart' show ReviewDialogFrame;
import '../../sessions/widgets/session_style.dart';
import '../worktree_files.dart';

/// Asks for a relative path (new file / folder, rename), validated with
/// [WorktreeFiles.normalizeRelative]. Returns the text (null = cancelled).
Future<String?> showPathDialog(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  String action = 'Criar',
}) => showDialog<String>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (_) =>
      _PathDialog(title: title, label: label, initial: initial, action: action),
);

class _PathDialog extends StatefulWidget {
  const _PathDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.action,
  });

  final String title;
  final String label;
  final String initial;
  final String action;

  @override
  State<_PathDialog> createState() => _PathDialogState();
}

class _PathDialogState extends State<_PathDialog> {
  late final _ctl = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void initState() {
    super.initState();
    // Select the file name (not the folder part) when renaming.
    final slash = widget.initial.lastIndexOf('/');
    final dot = widget.initial.lastIndexOf('.');
    _ctl.selection = TextSelection(
      baseOffset: slash + 1,
      extentOffset: dot > slash + 1 ? dot : widget.initial.length,
    );
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      WorktreeFiles.normalizeRelative(_ctl.text);
    } on CodeFileException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    Navigator.of(context).pop(_ctl.text.trim());
  }

  @override
  Widget build(BuildContext context) => ReviewDialogFrame(
    key: const ValueKey('code-path-dialog'),
    title: widget.title,
    width: 460,
    content: [
      Text(
        widget.label,
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      const SizedBox(height: 8),
      TextField(
        key: const ValueKey('code-path-field'),
        controller: _ctl,
        autofocus: true,
        style: const TextStyle(
          fontFamily: AppFonts.mono,
          fontSize: 13,
          color: AppColors.text,
        ),
        decoration: InputDecoration(
          isDense: true,
          errorText: _error,
          hintText: 'lib/novo_arquivo.dart',
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
      ),
    ],
    actions: [
      SmallButton(label: 'Cancelar', onTap: () => Navigator.of(context).pop()),
      AmberButton(
        key: const ValueKey('code-path-ok'),
        label: widget.action,
        onTap: _submit,
      ),
    ],
  );
}

/// Yes / no confirmation (delete). Returns true when confirmed.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String action = 'Excluir',
}) async =>
    await showDialog<bool>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (context) => ReviewDialogFrame(
        key: const ValueKey('code-confirm-dialog'),
        title: title,
        width: 460,
        content: [
          Text(
            message,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
        actions: [
          SmallButton(
            label: 'Cancelar',
            onTap: () => Navigator.of(context).pop(false),
          ),
          SmallButton(
            key: const ValueKey('code-confirm-ok'),
            label: action,
            color: AppColors.red,
            border: SessionColors.stopBorder,
            onTap: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    ) ??
    false;

enum UnsavedChoice { save, discard, cancel }

/// Closing a tab with unsaved edits.
Future<UnsavedChoice> showUnsavedDialog(
  BuildContext context,
  String name,
) async =>
    await showDialog<UnsavedChoice>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (context) => ReviewDialogFrame(
        key: const ValueKey('code-unsaved-dialog'),
        title: 'Salvar $name?',
        width: 460,
        content: const [
          Text(
            'O arquivo tem alterações não salvas.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
        actions: [
          SmallButton(
            label: 'Cancelar',
            onTap: () => Navigator.of(context).pop(UnsavedChoice.cancel),
          ),
          SmallButton(
            key: const ValueKey('code-unsaved-discard'),
            label: 'Descartar',
            color: AppColors.red,
            border: SessionColors.stopBorder,
            onTap: () => Navigator.of(context).pop(UnsavedChoice.discard),
          ),
          AmberButton(
            key: const ValueKey('code-unsaved-save'),
            label: 'Salvar',
            onTap: () => Navigator.of(context).pop(UnsavedChoice.save),
          ),
        ],
      ),
    ) ??
    UnsavedChoice.cancel;

/// "Ir para arquivo" (Ctrl+P): fuzzy search over [files]. Returns the path.
Future<String?> showGoToFileDialog(BuildContext context, List<String> files) =>
    showDialog<String>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (_) => _GoToFile(files: files),
    );

class _GoToFile extends StatefulWidget {
  const _GoToFile({required this.files});

  final List<String> files;

  @override
  State<_GoToFile> createState() => _GoToFileState();
}

class _GoToFileState extends State<_GoToFile> {
  final _query = TextEditingController();
  int _selected = 0;
  late List<String> _items = fuzzyFilter(widget.files, '');

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _move(int d) => setState(() {
    if (_items.isNotEmpty) {
      _selected = (_selected + d + _items.length) % _items.length;
    }
  });

  void _pick(String path) => Navigator.of(context).pop(path);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.6),
      child: Material(
        key: const ValueKey('code-goto-dialog'),
        color: AppColors.panel,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 560,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                  _move(1),
              const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                  _move(-1),
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      AppIcon(
                        AppIcons.search,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('code-goto-field'),
                          controller: _query,
                          autofocus: true,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.text,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Ir para arquivo…',
                            hintStyle: TextStyle(
                              color: AppColors.textSecondary,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                          onChanged: (q) => setState(() {
                            _items = fuzzyFilter(widget.files, q);
                            _selected = 0;
                          }),
                          onSubmitted: (_) {
                            if (_items.isNotEmpty) _pick(_items[_selected]);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 340),
                  child: _items.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Nenhum arquivo encontrado',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: _items.length,
                          itemBuilder: (context, i) {
                            final f = _items[i];
                            final sel = i == _selected;
                            final slash = f.lastIndexOf('/');
                            return InkWell(
                              key: ValueKey('code-goto-$f'),
                              onTap: () => _pick(f),
                              child: Container(
                                height: 30,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: sel
                                      ? AppColors.amberTint
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      f.substring(slash + 1),
                                      style: TextStyle(
                                        fontFamily: AppFonts.mono,
                                        fontSize: 12,
                                        color: sel
                                            ? AppColors.amber
                                            : AppColors.text,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        slash < 0 ? '' : f.substring(0, slash),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontFamily: AppFonts.mono,
                                          fontSize: 11,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
