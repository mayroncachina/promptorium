import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shell/editor_zoom.dart';
import '../theme/tokens.dart';

/// "− 100% +" control shown at the top of an editor.
class ZoomControl extends ConsumerWidget {
  const ZoomControl({super.key, required this.editorKey});

  final String editorKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zoom = ref.watch(editorZoomProvider(editorKey));
    final ctrl = ref.read(editorZoomProvider(editorKey).notifier);
    Widget btn(String label, String tip, VoidCallback onTap) => Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 24,
          height: 24,
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn('−', 'Diminuir zoom (Ctrl -)', ctrl.zoomOut),
          GestureDetector(
            onTap: ctrl.reset,
            child: SizedBox(
              width: 44,
              child: Text(
                '$zoom%',
                key: ValueKey('zoom-$editorKey'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 11,
                  color: AppColors.text,
                ),
              ),
            ),
          ),
          btn('+', 'Aumentar zoom (Ctrl =)', ctrl.zoomIn),
        ],
      ),
    );
  }
}
