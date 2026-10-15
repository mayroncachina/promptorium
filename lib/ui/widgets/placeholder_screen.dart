import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'zoom_control.dart';

/// Temporary screen body used until each feature is implemented.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title, this.editorKey});

  final String title;

  /// When set, shows the zoom control of that editor (specs / code).
  final String? editorKey;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Em construção',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            if (editorKey != null) ...[
              const SizedBox(height: 16),
              ZoomControl(editorKey: editorKey!),
            ],
          ],
        ),
      ),
    );
  }
}
