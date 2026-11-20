import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ui/theme/tokens.dart';
import '../context_snapshot.dart';

/// Compact meter above the composer (SPEC-087 R2, R3, R7): occupied / free,
/// the compaction threshold and when it was measured. A click (or Enter)
/// opens the Contexto panel. Never shows 0% without a reading, and never a
/// percentage without a known capacity.
class ContextIndicator extends StatelessWidget {
  const ContextIndicator({
    super.key,
    required this.snapshot,
    required this.onOpen,
    this.alive = true,
    this.open = false,
    this.dense = false,
    this.trailingLabel,
  });

  final ContextSnapshot snapshot;
  final VoidCallback onOpen;

  /// The process is running (false = a reading from the history is old).
  final bool alive;

  /// The panel is open (focus ring, as in the mock).
  final bool open;

  /// Comparar: one meter per side, without the "Contexto" button.
  final bool dense;

  /// Dense only: a note at the end ("contexto próprio").
  final String? trailingLabel;

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    final warn = s.warning != null || _overThreshold(s);
    final parts = contextIndicatorParts(s, alive: alive);
    final border = open
        ? AppColors.amber
        : warn
        ? SessionColors.approvalBorder
        : AppColors.border;
    final bg = warn ? SessionColors.approvalBg : AppColors.surfaceRaisedSolid;
    return Semantics(
      button: true,
      label: contextSummary(s, alive: alive),
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('context-indicator'),
          onTap: onOpen,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: dense ? 30 : 32,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: border, width: open ? 1.5 : 1),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: dense ? 90 : 110,
                  height: 8,
                  child: ContextMiniBar(snapshot: s, warn: warn),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRect(
                    child: Text.rich(
                      TextSpan(children: parts),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                if (dense && trailingLabel != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    trailingLabel!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
                if (!dense) ...[
                  const SizedBox(width: 8),
                  const Text(
                    'Contexto',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static bool _overThreshold(ContextSnapshot s) {
    final c = s.current, t = s.threshold;
    return c != null && c.live && t != null && c.tokens >= t * .85;
  }
}

const _mono = TextStyle(
  fontFamily: AppFonts.mono,
  fontSize: 12,
  fontWeight: FontWeight.w600,
  color: AppColors.text,
);
const _sep = TextSpan(text: '   ·   ');

/// The spans of the indicator line, per state (R2, R3).
List<InlineSpan> contextIndicatorParts(ContextSnapshot s, {bool alive = true}) {
  final c = s.current;
  final threshold = s.threshold;
  final thresholdText = threshold != null
      ? 'compacta em ${contextTokens(threshold)}'
      : s.configuredAutocompact != null
      ? 'auto compactar: ${autocompactLabel(s.configuredAutocompact)}'
      : null;
  if (c == null) {
    if (s.pendingAfterCompaction) {
      return [
        const TextSpan(
          text: 'Contexto compactado · aguardando medição',
          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600),
        ),
        if (s.last != null) ...[
          _sep,
          TextSpan(
            text: '${contextTokens(s.last!.tokens)} fica só no histórico',
          ),
        ],
      ];
    }
    return [
      const TextSpan(
        text: 'Aguardando medição',
        style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600),
      ),
      if (s.model != null) ...[_sep, TextSpan(text: shortModel(s.model!))],
      if (thresholdText != null) ...[_sep, TextSpan(text: thresholdText)],
    ];
  }
  final cap = s.capacity;
  // R3: a reading rebuilt from the history is old even after a resume,
  // until the agent measures again.
  final stale = !c.live;
  return [
    TextSpan(text: contextTokens(c.tokens), style: _mono),
    if (cap != null)
      TextSpan(text: ' / ${contextTokens(cap)}')
    else
      const TextSpan(text: ' medidos'),
    if (cap == null) ...[_sep, const TextSpan(text: 'limite desconhecido')],
    if (s.percent != null) ...[
      _sep,
      TextSpan(text: '${s.percent}%', style: _mono),
    ],
    if (!stale && thresholdText != null) ...[
      _sep,
      TextSpan(
        text: s.untilCompaction == null
            ? thresholdText
            : s.untilCompaction == 0
            ? '$thresholdText · limiar atingido'
            : '$thresholdText, faltam ${contextTokens(s.untilCompaction!)}',
        style: s.warning != null
            ? const TextStyle(color: AppColors.amberLight)
            : null,
      ),
    ],
    _sep,
    TextSpan(
      text: stale
          ? '${_when(c.at)} · não é ao vivo'
          : c.turnEnd
          ? 'medido no turno ${c.turn}'
          : 'medido no turno ${c.turn} · em curso',
    ),
  ];
}

String _when(DateTime at) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final diff = today.difference(day).inDays;
  final hh = contextTime(at);
  if (diff == 0) return 'hoje, $hh';
  if (diff == 1) return 'ontem, $hh';
  return '${at.day.toString().padLeft(2, '0')}/${at.month.toString().padLeft(2, '0')}, $hh';
}

/// `claude-opus-5-5` → `opus`.
String shortModel(String model) {
  final m = RegExp(r'(opus|sonnet|haiku|fable)').firstMatch(model);
  return m?.group(1) ?? model;
}

/// Text summary for screen readers and tooltips (R12).
String contextSummary(ContextSnapshot s, {bool alive = true}) {
  final c = s.current;
  if (c == null) {
    return s.pendingAfterCompaction
        ? 'Contexto compactado, aguardando medição.'
        : 'Contexto: aguardando medição.';
  }
  final b = StringBuffer('Contexto: ${contextTokens(c.tokens)} tokens');
  if (s.capacity != null) {
    b.write(' de ${contextTokens(s.capacity!)}, ${s.percent}% ocupado');
  } else {
    b.write(', limite desconhecido');
  }
  if (s.threshold != null) {
    b.write('. Compactação automática em ${contextTokens(s.threshold!)}');
    if (s.untilCompaction != null) {
      b.write(', faltam ${contextTokens(s.untilCompaction!)}');
    }
  }
  b.write('. ');
  b.write(
    !c.live
        ? 'Leitura antiga, de ${_when(c.at)}.'
        : 'Medido no turno ${c.turn}.',
  );
  return b.toString();
}

/// The occupied / free bar with the threshold tick (R2, R7).
class ContextMiniBar extends StatelessWidget {
  const ContextMiniBar({super.key, required this.snapshot, this.warn = false});

  final ContextSnapshot snapshot;
  final bool warn;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: ContextBarPainter(snapshot, warn: warn));
}

class ContextBarPainter extends CustomPainter {
  ContextBarPainter(this.s, {this.warn = false, this.radius = 4});

  final ContextSnapshot s;
  final bool warn;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final c = s.current;
    final cap = s.capacity;
    if (c == null) {
      // Waiting: a dashed outline (or stripes after compacting), never 0%.
      final p = Paint()
        ..color = AppColors.borderHover
        ..style = PaintingStyle.stroke;
      canvas.drawRRect(r, p);
      if (s.pendingAfterCompaction) _stripes(canvas, size, r);
      return;
    }
    canvas.drawRRect(r, Paint()..color = AppColors.border);
    if (cap == null || cap <= 0) {
      // No capacity: no fill proportion can be drawn honestly.
      _stripes(canvas, size, r);
      return;
    }
    final frac = (c.tokens / cap).clamp(0.0, 1.0);
    final w = (size.width * frac).clamp(size.height, size.width);
    canvas.save();
    canvas.clipRRect(r);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, size.height),
      Paint()..color = c.live ? AppColors.amber : AppColors.textMuted,
    );
    canvas.restore();
    final t = s.threshold;
    if (t != null && t < cap) {
      final x = size.width * t / cap;
      canvas.drawRect(
        Rect.fromLTWH(x - 1, -2, 2, size.height + 4),
        Paint()..color = AppColors.teal,
      );
    }
  }

  void _stripes(Canvas canvas, Size size, RRect r) {
    canvas.save();
    canvas.clipRRect(r);
    final p = Paint()
      ..color = AppColors.borderHover
      ..strokeWidth = 2;
    for (var x = -size.height; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(ContextBarPainter old) =>
      !identical(old.s, s) || old.warn != warn;
}

/// Enter / Space on a focused row (keyboard, R12).
final contextActivateKeys = {
  LogicalKeyboardKey.enter,
  LogicalKeyboardKey.numpadEnter,
  LogicalKeyboardKey.space,
};

/// Subagents of a history (R11): their own windows, not measured by the
/// app and never summed with the main one.
class SubagentContextNote extends StatelessWidget {
  const SubagentContextNote({super.key, required this.subagents});

  final List<String> subagents;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final s in subagents) {
      counts[s] = (counts[s] ?? 0) + 1;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final MapEntry(key: name, value: n) in counts.entries)
          Container(
            key: ValueKey('context-subagent-$name'),
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.view_week_outlined,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: n == 1
                          ? 'Subagente $name · '
                          : 'Subagentes $name ($n) · ',
                      children: const [
                        TextSpan(
                          text: 'contexto separado · medição indisponível',
                          style: TextStyle(
                            color: AppColors.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
