import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/tokens.dart';
import 'prototype_files.dart';

/// Deleting prototype screens (SPEC-027): confirmation, "Desfazer" and the
/// selection bar.

/// How long "Desfazer" is offered (R6).
const prototypeUndoWindow = Duration(seconds: 10);

/// Hint of the delete actions while screens are being generated (R8).
const deleteBusyHint = 'Aguarde a geração terminar';

/// `1 tela apagada` / `2 telas apagadas` (R10).
String deletedAnnouncement(int n) =>
    n == 1 ? '1 tela apagada' : '$n telas apagadas';

/// `Tela R2, variação C, apagada.` / `2 telas apagadas.` (R6).
String deletedMessage(List<MockupScreen> screens) => screens.length == 1
    ? 'Tela ${screens.single.requirement}, variação '
          '${screens.single.letterLabel}, apagada.'
    : '${screens.length} telas apagadas.';

/// A deletion that can still be undone (R6).
@immutable
class PrototypeUndo {
  const PrototypeUndo({
    required this.specId,
    required this.message,
    required this.undo,
  });

  final int specId;
  final String message;
  final Future<void> Function() undo;
}

/// The last deletion, offered for [prototypeUndoWindow]; afterwards (or on
/// leaving the spec) it is final. Kept in memory only: no trash folder.
class PrototypeUndoController extends Notifier<PrototypeUndo?> {
  Timer? _timer;

  @override
  PrototypeUndo? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  void offer(PrototypeUndo undo) {
    _timer?.cancel();
    state = undo;
    _timer = Timer(prototypeUndoWindow, dismiss);
  }

  /// The deletion becomes final.
  void dismiss() {
    _timer?.cancel();
    _timer = null;
    if (state != null) state = null;
  }

  /// Stops the timer now and drops the offer after the current frame (safe
  /// while the widget tree is being finalized).
  void discardLater() {
    _timer?.cancel();
    _timer = null;
    scheduleMicrotask(() {
      if (ref.mounted) dismiss();
    });
  }

  /// "Desfazer" (R6).
  Future<void> undo() async {
    final u = state;
    if (u == null) return;
    dismiss();
    await u.undo();
  }
}

final prototypeUndoProvider =
    NotifierProvider<PrototypeUndoController, PrototypeUndo?>(
      PrototypeUndoController.new,
    );

/// Keyboard hint (`Esc`, `Del`, `Ctrl+Z`).
class KeyHint extends StatelessWidget {
  const KeyHint(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.border),
        color: AppColors.background,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: AppFonts.mono,
          fontSize: 11,
          color: color ?? AppColors.textSecondary,
        ),
      ),
    ),
  );
}

/// Confirmation of the deletion (R4, R5): true when confirmed. [approved]
/// are the files approved in `## Protótipo`; [thumbs] file → PNG.
Future<bool> showDeleteScreensDialog(
  BuildContext context, {
  required List<MockupScreen> screens,
  required String specCode,
  required Set<String> approved,
  required Map<String, String> thumbs,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (ctx) => _DeleteDialog(
      screens: screens,
      folder: '${mockupDir(specCode)}/',
      approved: approved,
      thumbs: thumbs,
    ),
  );
  return ok ?? false;
}

class _DeleteDialog extends StatelessWidget {
  const _DeleteDialog({
    required this.screens,
    required this.folder,
    required this.approved,
    required this.thumbs,
  });

  final List<MockupScreen> screens;
  final String folder;
  final Set<String> approved;
  final Map<String, String> thumbs;

  Widget _thumb(MockupScreen x) {
    final png = thumbs[x.file];
    return Container(
      key: ValueKey('proto-remove-thumb-${x.file}'),
      width: 150,
      height: 94,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: png != null
          ? Image.file(
              File(png),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            )
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  x.file,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final one = screens.length == 1;
    final title = one
        ? 'Apagar a tela ${screens.single.spokenName}?'
        : 'Apagar ${screens.length} telas?';
    const mono = TextStyle(fontFamily: AppFonts.mono, fontSize: 12);
    const body = TextStyle(fontSize: 13, color: AppColors.textSecondary);
    final approvedOnes = [
      for (final x in screens)
        if (approved.contains(x.file)) x,
    ];
    final names = [for (final x in screens) x.file];
    return AlertDialog(
      key: const ValueKey('proto-remove-dialog'),
      backgroundColor: AppColors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      title: Text(
        title,
        key: const ValueKey('proto-remove-title'),
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (one)
                    _thumb(screens.single)
                  else
                    SizedBox(
                      width: 150,
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final x in screens.take(4))
                            SizedBox(
                              width: 73,
                              height: 46,
                              child: FittedBox(child: _thumb(x)),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          key: const ValueKey('proto-remove-files'),
                          TextSpan(
                            style: body.copyWith(color: AppColors.text),
                            children: [
                              TextSpan(
                                text: one ? 'O arquivo ' : 'Os arquivos ',
                              ),
                              TextSpan(text: names.join(', '), style: mono),
                              TextSpan(
                                text: one
                                    ? ' sai da pasta '
                                    : ' saem da pasta ',
                              ),
                              TextSpan(text: folder, style: mono),
                              const TextSpan(text: '.'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Logo depois, dá para desfazer por alguns segundos.',
                          style: body,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              for (final x in approvedOnes) ...[
                const SizedBox(height: 14),
                Container(
                  key: ValueKey('proto-remove-approved-${x.requirement}'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: SessionColors.approvalBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: SessionColors.approvalBorder),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 16,
                        color: AppColors.amber,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Esta é a tela aprovada do ${x.requirement}. A linha '
                          'dela também sai da seção Protótipo da spec, e o '
                          '${x.requirement} fica sem tela aprovada.',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          key: const ValueKey('proto-remove-cancel'),
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.text,
            side: const BorderSide(color: AppColors.border),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [Text('Cancelar'), SizedBox(width: 8), KeyHint('Esc')],
          ),
        ),
        FilledButton.icon(
          key: const ValueKey('proto-remove-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.red,
            foregroundColor: AppColors.onAmber,
          ),
          icon: const Icon(Icons.delete_outline, size: 16),
          label: Text(
            one ? 'Apagar tela' : 'Apagar ${screens.length} telas',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// "Tela … apagada." with "Desfazer" (R6), shown while the deletion of
/// [specId] can be undone.
class PrototypeUndoToast extends ConsumerWidget {
  const PrototypeUndoToast({super.key, required this.specId});

  final int specId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = ref.watch(prototypeUndoProvider);
    if (u == null || u.specId != specId) return const SizedBox.shrink();
    final ctrl = ref.read(prototypeUndoProvider.notifier);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Material(
        key: const ValueKey('proto-undo-toast'),
        color: AppColors.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.border),
        ),
        elevation: 6,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                u.message,
                key: const ValueKey('proto-undo-message'),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(width: 12),
              Tooltip(
                message: 'Desfazer (Ctrl+Z)',
                child: OutlinedButton(
                  key: const ValueKey('proto-undo'),
                  onPressed: ctrl.undo,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.text,
                    side: const BorderSide(color: AppColors.border),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.undo, size: 16),
                      SizedBox(width: 6),
                      Text('Desfazer'),
                      SizedBox(width: 8),
                      KeyHint('Ctrl+Z'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                key: const ValueKey('proto-undo-close'),
                tooltip: 'Fechar aviso',
                onPressed: ctrl.dismiss,
                iconSize: 16,
                visualDensity: VisualDensity.compact,
                color: AppColors.textSecondary,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bar above the canvas while two or more screens are selected (R3).
class PrototypeSelectionBar extends StatelessWidget {
  const PrototypeSelectionBar({
    super.key,
    required this.count,
    required this.onClear,
    required this.onDelete,
  });

  final int count;
  final VoidCallback onClear;

  /// Null while deleting is blocked (R8).
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('proto-selection-bar'),
    height: 52,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: const BoxDecoration(
      color: AppColors.panel,
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      children: [
        Text(
          '$count telas selecionadas',
          key: const ValueKey('proto-selection-count'),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 8),
        IconButton(
          key: const ValueKey('proto-selection-clear'),
          tooltip: 'Limpar seleção (Esc)',
          onPressed: onClear,
          iconSize: 16,
          color: AppColors.textSecondary,
          icon: const Icon(Icons.close, semanticLabel: 'Limpar seleção'),
        ),
        const Spacer(),
        _MaybeTooltip(
          message: onDelete == null ? deleteBusyHint : null,
          child: OutlinedButton.icon(
            key: const ValueKey('proto-selection-delete'),
            onPressed: onDelete,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.red,
              side: BorderSide(
                color: onDelete == null
                    ? AppColors.border
                    : SessionColors.stopBorder,
              ),
            ),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: Text('Apagar $count telas…'),
          ),
        ),
      ],
    ),
  );
}

/// [child] with a tooltip only when [message] is set.
class _MaybeTooltip extends StatelessWidget {
  const _MaybeTooltip({required this.message, required this.child});

  final String? message;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      message == null ? child : Tooltip(message: message, child: child);
}
