import 'package:flutter/material.dart';

import '../../../core/providers/workspace_assets.dart';
import '../../../ui/theme/tokens.dart';

/// Tone of a provider badge (SPEC-104 R7).
enum BadgeTone { claude, codex, error, muted }

BadgeTone codexBadgeTone(CodexSkillState s) => switch (s) {
  CodexSkillState.active => BadgeTone.codex,
  CodexSkillState.error => BadgeTone.error,
  _ => BadgeTone.muted,
};

/// "Claude" / "Codex" / "Codex · erro" / "Só Claude Code" (SPEC-104 R7).
class ProviderBadge extends StatelessWidget {
  const ProviderBadge(this.text, {super.key, this.tone = BadgeTone.claude});

  final String text;
  final BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final (fg, border) = switch (tone) {
      BadgeTone.claude => (AppColors.teal, SessionColors.runningToolBorder),
      BadgeTone.codex => (AppColors.lilac, const Color(0xFF4A3A63)),
      BadgeTone.error => (AppColors.red, SessionColors.stopBorder),
      BadgeTone.muted => (AppColors.textMuted, AppColors.border),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 10.5, color: fg),
      ),
    );
  }
}
