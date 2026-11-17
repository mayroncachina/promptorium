import 'package:flutter/material.dart';

import '../../../../ui/theme/tokens.dart';
import '../replay_step.dart';

/// Colors and badges of the replay (SPEC-082 R3, R13): each kind has a
/// letter and an icon besides the color.
abstract final class ReplayColors {
  static const read = AppColors.blue;
  static const edit = AppColors.amber;
  static const run = AppColors.teal;
  static const talk = Color(0xFFC9CED8);
  static const thinking = AppColors.lilac;
  static const error = AppColors.red;
  static const dim = Color(0xFF2C323D);
  static const lane = Color(0xFF151920);
  static const turn = Color(0xFF3A4250);

  static Color of(ReplayStep s) {
    if (s.outcome == ReplayOutcome.error) return error;
    return switch (s.kind) {
      ReplayKind.read || ReplayKind.web || ReplayKind.subagent => read,
      ReplayKind.edit => edit,
      ReplayKind.run || ReplayKind.other => run,
      ReplayKind.thinking || ReplayKind.plan => thinking,
      ReplayKind.user || ReplayKind.assistant => talk,
      ReplayKind.mark => markColor(s.mark),
    };
  }

  static Color kindColor(ReplayKind k) => switch (k) {
    ReplayKind.read || ReplayKind.web || ReplayKind.subagent => read,
    ReplayKind.edit => edit,
    ReplayKind.run || ReplayKind.other => run,
    ReplayKind.thinking || ReplayKind.plan => thinking,
    ReplayKind.user || ReplayKind.assistant => talk,
    ReplayKind.mark => AppColors.textSecondary,
  };

  static Color laneColor(ReplayLane l) => switch (l) {
    ReplayLane.read => read,
    ReplayLane.edit => edit,
    ReplayLane.run => run,
    ReplayLane.talk => talk,
  };

  static IconData laneIcon(ReplayLane l) => switch (l) {
    ReplayLane.read => Icons.visibility_outlined,
    ReplayLane.edit => Icons.edit_outlined,
    ReplayLane.run => Icons.terminal,
    ReplayLane.talk => Icons.chat_bubble_outline,
  };

  static Color markColor(ReplayMarkKind? m) => switch (m) {
    ReplayMarkKind.gatePassed => AppColors.teal,
    ReplayMarkKind.gateFailed || ReplayMarkKind.error => error,
    ReplayMarkKind.compaction => AppColors.blue,
    ReplayMarkKind.resume => AppColors.amber,
    _ => AppColors.textMuted,
  };
}

/// The square badge with the kind's letter ("E", "R"…).
class ReplayKindBadge extends StatelessWidget {
  const ReplayKindBadge(this.step, {super.key, this.size = 16});

  final ReplayStep step;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = ReplayColors.of(step);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        step.kind.letter,
        style: TextStyle(
          fontFamily: AppFonts.mono,
          fontSize: size * .62,
          fontWeight: FontWeight.w700,
          color: AppColors.onAmber,
          height: 1,
        ),
      ),
    );
  }
}

/// One-line label of a step: "Edit ci_fixer.dart +6 −2", "Bash flutter
/// test", "pensando", the start of a message.
String replayStepLabel(ReplayStep s) {
  final t = s.tool;
  if (t != null) {
    final path = s.filePath;
    final target = path == null ? s.target : baseName(path);
    final stats = s.added == null ? '' : ' ${s.statsLabel}';
    return '${t.name} $target$stats';
  }
  return switch (s.kind) {
    ReplayKind.thinking => 'pensando',
    ReplayKind.user || ReplayKind.assistant => '"${s.target}"',
    _ => s.target,
  };
}

/// Spoken / hover description: "42 · Edit lib/x.dart +6 −2 · 14:32".
String replayStepTip(ReplayStep s, {String? root}) {
  final path = s.filePath;
  final t = s.tool;
  final body = t == null
      ? replayStepLabel(s)
      : '${t.name} ${path == null ? s.target : relativePath(path, root)}'
            '${s.added == null ? '' : ' ${s.statsLabel}'}';
  final at = clock(s.at);
  return '${s.index + 1} · $body${at.isEmpty ? '' : ' · $at'}';
}

/// Screen reader value of the scrubber (R13): "Passo 42 de 180, Editar
/// ci_fixer.dart, mais 6 menos 2, 14:32".
String replaySemanticValue(ReplayStep s, int total) {
  final parts = <String>['Passo ${s.index + 1} de $total', s.kind.label];
  final path = s.filePath;
  final what = path == null ? s.target : baseName(path);
  if (what.isNotEmpty) parts[1] = '${s.kind.label} $what';
  if (s.added != null) {
    parts.add('mais ${s.added} menos ${s.removed ?? 0}');
  }
  if (s.outcome == ReplayOutcome.error) parts.add('com erro');
  if (s.outcome == ReplayOutcome.denied) parts.add('negado');
  final at = clock(s.at);
  if (at.isNotEmpty) parts.add(at);
  return parts.join(', ');
}

String formatDurationShort(Duration? d) {
  if (d == null) return '–';
  if (d.inMinutes >= 1) return '${d.inMinutes} min';
  return '${d.inSeconds} s';
}

/// "82 k tokens".
String formatTokens(int n) =>
    n >= 1000 ? '${(n / 1000).round()} k tokens' : '$n tokens';
