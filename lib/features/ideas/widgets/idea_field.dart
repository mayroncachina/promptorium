import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../../ui/widgets/app_icon.dart';
import '../../sessions/widgets/session_style.dart';
import '../idea_import.dart';

/// Opens the native chooser filtered to PDF, Markdown and TXT (SPEC-057
/// R1); null when cancelled. Overridden in widget tests, where platform
/// channels do not answer.
final ideaFilePickerProvider = Provider<Future<String?> Function()>(
  (ref) => () async {
    final f = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'PDF, Markdown ou TXT',
          extensions: ideaImportExtensions,
        ),
      ],
      confirmButtonText: 'Importar',
    );
    return f?.path;
  },
);

/// Where the text in the field came from (R5).
class _Source {
  const _Source({
    required this.imported,
    required this.before,
    required this.after,
    required this.appended,
  });

  final ImportedText imported;

  /// The field before the import: what Remover gives back.
  final String before;

  /// The field right after the import: anything else means it was edited.
  final String after;

  final bool appended;
}

/// A PDF being read (R4).
class _Reading {
  _Reading(this.name, this.cancel);

  final String name;
  final ImportCancel cancel;
  int page = 0;
  int total = 0;
}

enum _Mode { append, replace }

/// "Conte a ideia" with file import (SPEC-057): the field, a footer with
/// "Importar arquivo" (Ctrl+O), the hint and the counter (R1), dropping a
/// file on it (R2), the PDF progress (R4), the source card (R5), the
/// add/replace choice (R6) and the messages (R7).
class IdeaField extends ConsumerStatefulWidget {
  const IdeaField({
    super.key,
    required this.controller,
    required this.fieldKey,
    required this.hint,
    this.minLines = 4,
    this.maxLines = 8,
    this.autofocus = false,
    this.onChanged,
  });

  /// Owned by the screen, which reads the idea from it.
  final TextEditingController controller;

  /// Key of the inner [TextField] (`new-spec-idea`, `project-idea`).
  final Key fieldKey;
  final String hint;
  final int minLines;
  final int maxLines;
  final bool autofocus;

  /// Called on typing and on every import or removal.
  final ValueChanged<String>? onChanged;

  @override
  ConsumerState<IdeaField> createState() => _IdeaFieldState();
}

class _IdeaFieldState extends ConsumerState<IdeaField> {
  final _focus = FocusNode(debugLabel: 'idea-field');
  bool _dragging = false;
  _Reading? _reading;
  _Source? _source;

  /// Waiting for "Adicionar ao fim" or "Substituir" (R6).
  ImportedText? _pending;
  _Mode _mode = _Mode.append;

  /// What Ctrl+Z gives back after "Substituir", while the field still holds
  /// the replacement.
  ({String before, String after})? _replaced;

  ImportProblem? _problem;
  List<ImportWarning> _warnings = const [];

  /// "Só o primeiro arquivo…" (R2).
  String? _notice;

  TextEditingController get _text => widget.controller;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refresh);
    _text.addListener(_refresh);
  }

  @override
  void didUpdateWidget(IdeaField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    _text.removeListener(_refresh);
    _reading?.cancel.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _changed() => widget.onChanged?.call(_text.text);

  /// Typing clears the messages (R7).
  void _typed(String _) {
    if (_problem != null || _warnings.isNotEmpty || _notice != null) {
      setState(() {
        _problem = null;
        _warnings = const [];
        _notice = null;
      });
    }
    _changed();
  }

  Future<void> _pick({bool swap = false}) async {
    if (_reading != null) return;
    final path = await ref.read(ideaFilePickerProvider)();
    if (path == null || !mounted) return;
    await _import(path, swap: swap);
  }

  Future<void> _dropped(DropDoneDetails d) async {
    setState(() => _dragging = false);
    if (d.files.isEmpty) return;
    final first = d.files.first;
    await _import(
      first.path,
      notice: d.files.length > 1
          ? 'Importamos só ${first.name}; o campo recebe um arquivo por vez.'
          : null,
    );
  }

  Future<void> _import(String path, {bool swap = false, String? notice}) async {
    if (_reading != null) return;
    final reading = _Reading(path.split('/').last, ImportCancel());
    setState(() {
      _problem = null;
      _warnings = const [];
      _notice = notice;
      _pending = null;
      _reading = reading;
    });
    try {
      final r = await ref
          .read(ideaImportProvider)
          .read(
            path,
            cancel: reading.cancel,
            onProgress: (page, total) {
              if (!mounted) return;
              setState(() {
                reading.page = page;
                reading.total = total;
              });
            },
          );
      if (!mounted) return;
      final source = _source;
      final base = swap && source != null && _text.text == source.after
          ? source.before
          : _text.text;
      setState(() => _reading = null);
      if (base.trim().isEmpty) {
        _apply(r, base: '', mode: _Mode.replace);
      } else {
        setState(() {
          _pending = r;
          _pendingBase = base;
          _mode = _Mode.append;
        });
      }
    } on ImportCancelled {
      if (mounted) setState(() => _reading = null);
    } on ImportProblem catch (e) {
      if (mounted) {
        setState(() {
          _reading = null;
          _problem = e;
        });
      }
    }
  }

  String _pendingBase = '';

  void _apply(ImportedText r, {required String base, required _Mode mode}) {
    final previous = _text.text;
    final String text;
    final ImportedText fitted;
    final String before;
    if (mode == _Mode.append) {
      before = base.trimRight();
      fitted = r.fit(ideaMaxChars - before.length - 2);
      text = fitted.text.isEmpty ? before : '$before\n\n${fitted.text}';
    } else {
      before = '';
      fitted = r.fit(ideaMaxChars);
      text = fitted.text;
    }
    // The caret at the start of the file text, so it shows from the top.
    final start = mode == _Mode.append && before.isNotEmpty
        ? before.length + 2
        : 0;
    _text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: start > text.length ? text.length : start,
      ),
    );
    setState(() {
      _pending = null;
      _warnings = fitted.warnings;
      _source = _Source(
        imported: fitted,
        before: before,
        after: text,
        appended: mode == _Mode.append,
      );
      _replaced = mode == _Mode.replace && previous.trim().isNotEmpty
          ? (before: previous, after: text)
          : null;
    });
    _focus.requestFocus();
    _changed();
  }

  void _confirmChoice() {
    final r = _pending;
    if (r == null) return;
    _apply(r, base: _pendingBase, mode: _mode);
  }

  void _cancelChoice() {
    setState(() => _pending = null);
    _focus.requestFocus();
  }

  Future<void> _remove() async {
    final source = _source;
    if (source == null) return;
    if (_text.text != source.after && !await _confirmRemove(source)) return;
    _text.value = TextEditingValue(
      text: source.before,
      selection: TextSelection.collapsed(offset: source.before.length),
    );
    setState(() {
      _source = null;
      _replaced = null;
      _warnings = const [];
    });
    _focus.requestFocus();
    _changed();
  }

  Future<bool> _confirmRemove(_Source source) async {
    final ok = await showAppDialog<bool>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('idea-remove-dialog'),
        backgroundColor: AppColors.panel,
        title: const Text(
          'Remover o texto do arquivo?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: 380,
          child: Text(
            'Você editou o campo depois de importar ${source.imported.name}. '
            'Remover volta o campo para como estava antes do arquivo, e as '
            'edições feitas depois se perdem.',
            style: const TextStyle(fontSize: 13, height: 1.45),
          ),
        ),
        actions: [
          OutlinedButton(
            key: const ValueKey('idea-remove-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.red,
              side: const BorderSide(color: SessionColors.stopBorder),
            ),
            child: const Text('Remover'),
          ),
          FilledButton(
            key: const ValueKey('idea-remove-keep'),
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.amber,
              foregroundColor: AppColors.onAmber,
            ),
            child: const Text(
              'Manter',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// Ctrl+Z right after "Substituir" gives the old text back (R6); any other
  /// undo is the field's own.
  bool _undo() {
    final r = _replaced;
    if (r != null && _text.text == r.after) {
      _text.value = TextEditingValue(
        text: r.before,
        selection: TextSelection.collapsed(offset: r.before.length),
      );
      setState(() {
        _replaced = null;
        _source = null;
        _warnings = const [];
      });
      _changed();
      return true;
    }
    return false;
  }

  Future<void> _showOverflow(TruncatedWarning w) => showAppDialog<void>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (ctx) => AlertDialog(
      key: const ValueKey('idea-overflow-dialog'),
      backgroundColor: AppColors.panel,
      title: Text(
        'O que ficou de fora · ${formatCount(w.overflow.length)} caracteres',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 560,
        height: 360,
        child: SingleChildScrollView(
          child: SelectableText(
            w.overflow,
            key: const ValueKey('idea-overflow-text'),
            style: const TextStyle(fontSize: 12, height: 1.5),
          ),
        ),
      ),
      actions: [
        SmallButton(
          key: const ValueKey('idea-overflow-copy'),
          label: 'Copiar',
          height: 32,
          onTap: () => Clipboard.setData(ClipboardData(text: w.overflow)),
        ),
        AmberButton(
          key: const ValueKey('idea-overflow-close'),
          label: 'Fechar',
          height: 32,
          onTap: () => Navigator.of(ctx).pop(),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final reading = _reading;
    final source = _source;
    final showProgress =
        reading != null && reading.total > ideaProgressMinPages;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showProgress) ...[
          _ProgressCard(
            reading: reading,
            onCancel: () => reading.cancel.cancel(),
          ),
          const SizedBox(height: 10),
        ] else if (source != null) ...[
          _SourceCard(
            source: source,
            onSwap: reading == null ? () => _pick(swap: true) : null,
            onRemove: reading == null ? _remove : null,
          ),
          const SizedBox(height: 10),
        ],
        if (_problem != null) ...[
          _Message.problem(_problem!),
          const SizedBox(height: 10),
        ],
        for (final w in _warnings) ...[
          _Message.warning(
            w,
            onShowOverflow: w is TruncatedWarning
                ? () => _showOverflow(w)
                : null,
          ),
          const SizedBox(height: 10),
        ],
        if (_notice != null) ...[
          _Message(
            key: const ValueKey('idea-notice'),
            error: false,
            title: _notice!,
            detail: null,
            command: null,
            onAction: null,
          ),
          const SizedBox(height: 10),
        ],
        DropTarget(
          key: const ValueKey('idea-drop'),
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: _dropped,
          child: _box(reading),
        ),
        if (_pending != null) ...[
          const SizedBox(height: 8),
          _Choice(
            name: _pending!.name,
            mode: _mode,
            onMode: (m) => setState(() => _mode = m),
            onCancel: _cancelChoice,
            onConfirm: _confirmChoice,
          ),
        ],
      ],
    );
  }

  Widget _box(_Reading? reading) {
    final focused = _focus.hasFocus;
    final count = _text.text.length;
    final field = Actions(
      actions: {UndoTextIntent: _UndoReplaceAction(_undo)},
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyO, control: true): () =>
              _pick(),
        },
        child: TextField(
          key: widget.fieldKey,
          controller: _text,
          focusNode: _focus,
          autofocus: widget.autofocus,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          inputFormatters: [LengthLimitingTextInputFormatter(ideaMaxChars)],
          style: const TextStyle(
            fontSize: 13,
            height: 1.6,
            color: AppColors.text,
          ),
          decoration: InputDecoration(
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            isDense: true,
            contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            hintText: widget.hint,
            hintStyle: const TextStyle(color: AppColors.textMuted),
          ),
          onChanged: _typed,
        ),
      ),
    );
    final footer = Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          SmallButton(
            key: const ValueKey('idea-import'),
            label: 'Importar arquivo',
            icon: Icons.attach_file,
            semanticLabel: 'Importar arquivo PDF, Markdown ou TXT (Ctrl+O)',
            fontWeight: FontWeight.w600,
            onTap: reading == null ? () => _pick() : null,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'PDF, Markdown ou TXT · ou arraste para o campo',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ),
          if (count > 0)
            Semantics(
              label: '$count de $ideaMaxChars caracteres',
              excludeSemantics: true,
              child: Text(
                '${formatCount(count)} / ${formatCount(ideaMaxChars)}',
                key: const ValueKey('idea-counter'),
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
    final radius = BorderRadius.circular(8);
    return Stack(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: radius,
            border: Border.all(
              color: focused && !_dragging
                  ? AppColors.amber
                  : AppColors.inputBorder,
              width: focused && !_dragging ? 1.5 : 1,
            ),
          ),
          child: Opacity(
            opacity: _dragging ? .25 : 1,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [field, footer],
            ),
          ),
        ),
        if (_dragging)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                key: const ValueKey('idea-drop-overlay'),
                painter: const _DashedBorder(AppColors.amber),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: .06),
                    borderRadius: radius,
                  ),
                  alignment: Alignment.center,
                  child: Semantics(
                    liveRegion: true,
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.file_upload_outlined,
                          size: 26,
                          color: AppColors.amber,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Solte para carregar o texto',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'PDF, Markdown ou TXT · até 20 MB',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Overrides the field's undo (see [_IdeaFieldState._undo]); [callingAction]
/// is the field's own undo.
class _UndoReplaceAction extends ContextAction<UndoTextIntent> {
  _UndoReplaceAction(this.onUndo);

  /// True when it handled the undo.
  final bool Function() onUndo;

  @override
  Object? invoke(UndoTextIntent intent, [BuildContext? context]) =>
      onUndo() ? null : callingAction?.invoke(intent);
}

/// The square with the file type (`PDF`, `MD`, `TXT`).
class _KindBadge extends StatelessWidget {
  const _KindBadge(this.kind);

  final ImportKind kind;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (kind) {
      ImportKind.pdf => ('PDF', AppColors.red),
      ImportKind.markdown => ('MD', AppColors.teal),
      ImportKind.text => ('TXT', AppColors.blue),
    };
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.bottomCenter,
      padding: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        border: Border.all(color: color.withValues(alpha: .45)),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppFonts.mono,
          fontSize: 8,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// The file the text came from, with Trocar and Remover (R5).
class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.source,
    required this.onSwap,
    required this.onRemove,
  });

  final _Source source;
  final VoidCallback? onSwap;
  final VoidCallback? onRemove;

  /// `3 páginas · 4.812 caracteres carregados no campo`.
  static String line(_Source s) {
    final r = s.imported;
    final what = r.pages == null
        ? r.kind.label
        : '${r.pages} ${r.pages == 1 ? 'página' : 'páginas'}';
    final where = s.appended ? 'adicionados ao fim' : 'carregados no campo';
    return '$what · ${formatCount(r.chars)} caracteres $where';
  }

  @override
  Widget build(BuildContext context) {
    final r = source.imported;
    final detail = line(source);
    return Semantics(
      container: true,
      label: 'Arquivo importado: ${r.name}, $detail',
      child: Container(
        key: const ValueKey('idea-source'),
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        decoration: BoxDecoration(
          color: SessionColors.runningToolBg,
          border: Border.all(color: SessionColors.runningToolBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            ExcludeSemantics(child: _KindBadge(r.kind)),
            const SizedBox(width: 10),
            Expanded(
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      key: const ValueKey('idea-source-detail'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            TextButton.icon(
              key: const ValueKey('idea-source-swap'),
              onPressed: onSwap,
              icon: const Icon(Icons.swap_horiz, size: 15),
              label: Semantics(
                label: 'Trocar o arquivo',
                excludeSemantics: true,
                child: const Text('Trocar'),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.amber,
                textStyle: const TextStyle(
                  fontFamily: AppFonts.sans,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('idea-source-remove'),
              tooltip: 'Remover o texto do arquivo',
              onPressed: onRemove,
              iconSize: 16,
              color: AppColors.textSecondary,
              icon: AppIcon(AppIcons.close, size: 14),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Lendo o PDF… página x de n" with Cancelar (R4).
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.reading, required this.onCancel});

  final _Reading reading;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final status = 'página ${reading.page} de ${reading.total}';
    return Container(
      key: const ValueKey('idea-progress'),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        border: Border.all(color: AppColors.borderHover),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const ExcludeSemantics(child: _KindBadge(ImportKind.pdf)),
          const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              liveRegion: true,
              label: 'Lendo o PDF ${reading.name}, $status',
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lendo o PDF… $status',
                    key: const ValueKey('idea-progress-label'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: reading.total == 0
                          ? null
                          : reading.page / reading.total,
                      minHeight: 3,
                      color: AppColors.amber,
                      backgroundColor: AppColors.border,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            key: const ValueKey('idea-progress-cancel'),
            onPressed: onCancel,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.amber,
              textStyle: const TextStyle(
                fontFamily: AppFonts.sans,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }
}

/// An error (red: the text did not go in) or a warning (amber: it did), near
/// the field and announced (R7, R9).
class _Message extends StatelessWidget {
  const _Message({
    super.key,
    required this.error,
    required this.title,
    required this.detail,
    required this.command,
    required this.onAction,
  });

  _Message.problem(ImportProblem p)
    : this(
        key: const ValueKey('idea-problem'),
        error: true,
        title: p.title,
        detail: p.detail,
        command: p.command,
        onAction: null,
      );

  _Message.warning(ImportWarning w, {VoidCallback? onShowOverflow})
    : this(
        key: ValueKey('idea-warning-${w.runtimeType}'),
        error: false,
        title: w.title,
        detail: w.detail,
        command: null,
        onAction: onShowOverflow,
      );

  final bool error;
  final String title;
  final String? detail;
  final String? command;

  /// "Ver o que ficou de fora".
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final color = error ? AppColors.red : AppColors.amber;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: error ? SessionColors.delBg : SessionColors.approvalBg,
          border: Border.all(
            color: error
                ? SessionColors.stopBorder
                : SessionColors.approvalBorder,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: error
                  ? AppIcon(AppIcons.warning, size: 15, color: color)
                  : Icon(Icons.info_outline, size: 15, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (detail != null && detail!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      detail!,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  if (command != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: SelectableText(
                        command!,
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                  if (onAction != null) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      key: const ValueKey('idea-overflow'),
                      onPressed: onAction,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 28),
                        foregroundColor: AppColors.amber,
                        textStyle: const TextStyle(
                          fontFamily: AppFonts.sans,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Ver o que ficou de fora'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "O campo já tem texto": Adicionar ao fim (default) or Substituir, as a
/// radio group (R6, R9).
class _Choice extends StatelessWidget {
  const _Choice({
    required this.name,
    required this.mode,
    required this.onMode,
    required this.onCancel,
    required this.onConfirm,
  });

  final String name;
  final _Mode mode;
  final ValueChanged<_Mode> onMode;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    const options = [
      (
        _Mode.append,
        Icons.add,
        'Adicionar ao fim',
        'Seu texto fica em cima; o do arquivo vem depois de uma linha em '
            'branco.',
      ),
      (
        _Mode.replace,
        Icons.swap_horiz,
        'Substituir',
        'Troca o que você escreveu pelo texto do arquivo. Ctrl+Z desfaz.',
      ),
    ];
    return Material(
      key: const ValueKey('idea-choice'),
      color: AppColors.panelSolid,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.borderHover),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): onCancel,
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'O campo já tem texto · $name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              RadioGroup<_Mode>(
                groupValue: mode,
                onChanged: (m) {
                  if (m != null) onMode(m);
                },
                child: Column(
                  children: [
                    for (final (value, icon, title, subtitle) in options) ...[
                      _Option(
                        value: value,
                        selected: value == mode,
                        icon: icon,
                        title: title,
                        subtitle: subtitle,
                        autofocus: value == _Mode.append,
                      ),
                      if (value == _Mode.append) const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SmallButton(
                    key: const ValueKey('idea-choice-cancel'),
                    label: 'Cancelar',
                    height: 32,
                    fontSize: 13,
                    onTap: onCancel,
                  ),
                  const SizedBox(width: 8),
                  AmberButton(
                    key: const ValueKey('idea-choice-confirm'),
                    label: mode == _Mode.append ? 'Adicionar' : 'Substituir',
                    height: 32,
                    fontSize: 13,
                    onTap: onConfirm,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.value,
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.autofocus,
  });

  final _Mode value;
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppColors.amberTint : Colors.transparent,
    shape: RoundedRectangleBorder(
      side: BorderSide(
        color: selected ? SessionColors.approvalBorder : AppColors.border,
      ),
      borderRadius: BorderRadius.circular(8),
    ),
    child: RadioListTile<_Mode>(
      key: ValueKey('idea-choice-${value.name}'),
      value: value,
      autofocus: autofocus,
      dense: true,
      activeColor: AppColors.amber,
      contentPadding: const EdgeInsets.only(left: 4, right: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      title: Row(
        children: [
          Icon(icon, size: 14, color: selected ? AppColors.amber : null),
          const SizedBox(width: 6),
          Text(title, style: const TextStyle(fontSize: 13)),
        ],
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
      ),
    ),
  );
}

/// Border drawn with dashes: the field as a drop area (R2).
class _DashedBorder extends CustomPainter {
  const _DashedBorder(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
      );
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 10) {
        canvas.drawPath(m.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorder old) => old.color != color;
}
