import 'package:flutter/material.dart';

import '../../ui/theme/tokens.dart';
import '../agents/widgets/agent_style.dart';

/// Row of toggles (one per value).
Widget choices({
  required String keyPrefix,
  required List<(String, String)> values,
  required String selected,
  required ValueChanged<String> onTap,
}) => Row(
  children: [
    for (final (id, label) in values)
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ToggleBox(
            key: ValueKey('$keyPrefix-$id'),
            on: selected == id,
            height: 32,
            onTap: () => onTap(id),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppFonts.mono,
                fontSize: 12,
                color: selected == id
                    ? AppColors.amber
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
  ],
);
