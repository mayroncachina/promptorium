import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../sessions/widgets/session_style.dart';
import '../spec_prints.dart';

/// The cards of the prints under the idea (SPEC-083 R4, R5, R12): the
/// thumbnail, the name and size, "Ver", "Remover" and the Bug/Referência
/// radio group.
class PrintCards extends StatelessWidget {
  const PrintCards({
    super.key,
    required this.prints,
    required this.onKind,
    required this.onRemove,
  });

  final List<SpecPrint> prints;
  final void Function(int index, PrintKind kind) onKind;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) => FocusTraversalGroup(
    child: Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final (i, s) in prints.indexed)
          _PrintCard(
            key: ValueKey('print-card-$i'),
            index: i,
            print: s,
            onKind: (k) => onKind(i, k),
            onRemove: () => onRemove(i),
          ),
      ],
    ),
  );
}

class _PrintCard extends StatelessWidget {
  const _PrintCard({
    super.key,
    required this.index,
    required this.print,
    required this.onKind,
    required this.onRemove,
  });

  final int index;
  final SpecPrint print;
  final ValueChanged<PrintKind> onKind;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final n = index + 1;
    final untyped = print.kind == null;
    return Container(
      width: 315,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: untyped ? SessionColors.approvalBorder : AppColors.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PrintThumbnail(print: print, index: index, width: 112, height: 76),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      print.name,
                      style: const TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${print.width}×${print.height}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppFonts.mono,
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    _IconAction(
                      key: ValueKey('print-remove-$index'),
                      icon: Icons.close,
                      label: 'Remover print $n',
                      onTap: onRemove,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'TIPO DO PRINT $n',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: .6,
                    fontWeight: FontWeight.w600,
                    color: untyped ? AppColors.amber : AppColors.textSecondary,
                  ),
                ),
                Semantics(
                  container: true,
                  label: 'Tipo do print $n',
                  child: RadioGroup<PrintKind>(
                    groupValue: print.kind,
                    onChanged: (k) {
                      if (k != null) onKind(k);
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final k in PrintKind.values)
                          _KindOption(
                            key: ValueKey('print-kind-$index-${k.json}'),
                            kind: k,
                            selected: print.kind == k,
                            onTap: () => onKind(k),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SmallButton(
                      key: ValueKey('print-view-$index'),
                      label: 'Ver',
                      height: 26,
                      semanticLabel: 'Ver print $n',
                      onTap: () => showPrintDialog(context, print, index),
                    ),
                    if (print.reduced)
                      Text(
                        'reduzido de ${print.originalWidth}×${print.originalHeight}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KindOption extends StatelessWidget {
  const _KindOption({
    super.key,
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final PrintKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: Radio<PrintKind>(
              value: kind,
              activeColor: AppColors.amber,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              kind.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: selected ? AppColors.text : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, size: 14, color: AppColors.textSecondary),
        ),
      ),
    ),
  );
}

/// The image of a print, with the name (and the description, after the
/// planning) as its alternative text (R12).
class PrintThumbnail extends StatelessWidget {
  const PrintThumbnail({
    super.key,
    required this.print,
    required this.index,
    this.width = 160,
    this.height = 100,
  });

  final SpecPrint print;
  final int index;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final alt = print.description.isEmpty
        ? print.name
        : '${print.name}: ${print.description}';
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.backgroundSolid,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.file(
        File(print.path),
        key: ValueKey('print-thumb-$index'),
        fit: BoxFit.contain,
        cacheWidth: (width * 2).round(),
        semanticLabel: alt,
        errorBuilder: (_, _, _) => Center(
          child: Text(
            print.name,
            semanticsLabel: alt,
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 11,
              color: AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// "Ver": the print at its real size (R4).
Future<void> showPrintDialog(
  BuildContext context,
  SpecPrint print,
  int index,
) => showAppDialog<void>(
  context: context,
  barrierColor: AppColors.scrim,
  builder: (ctx) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          Navigator.of(ctx).pop(),
    },
    child: Dialog(
      key: const ValueKey('print-dialog'),
      backgroundColor: AppColors.panelSolid,
      insetPadding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${print.name} · ${print.fullSizeLabel}',
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 12,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('print-dialog-close'),
                  autofocus: true,
                  tooltip: 'Fechar',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
          ),
          Flexible(
            child: InteractiveViewer(
              constrained: false,
              child: Image.file(
                File(print.path),
                semanticLabel: print.description.isEmpty
                    ? print.name
                    : '${print.name}: ${print.description}',
                errorBuilder: (_, _, _) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Não foi possível abrir o print.'),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);
