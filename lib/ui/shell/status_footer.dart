import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/tokens.dart';
import 'footer_stats.dart';

/// Fixed footer (28px) fed by [footerStatsProvider].
class StatusFooter extends ConsumerWidget {
  const StatusFooter({super.key});

  static const _mono = TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: 11,
    color: AppColors.text,
  );
  static const _monoDim = TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: 11,
    color: AppColors.textSecondary,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(footerStatsProvider);

    final (cliColor, cliText) = switch (s.cliStatus) {
      CliStatus.connected => (AppColors.teal, 'Claude Code CLI conectado'),
      CliStatus.notFound => (AppColors.red, 'Claude Code CLI não encontrado'),
      CliStatus.unknown => (AppColors.textMuted, 'Claude Code CLI —'),
    };

    String ratio(int? a, int? b) => a == null || b == null ? '—' : '$a/$b';

    final left = <Widget>[
      _group([
        _dot(cliColor),
        Text(cliText, key: const ValueKey('footer-cli')),
      ]),
      _separator(),
      _group([
        const Text('Sessões'),
        Text(ratio(s.sessionsActive, s.sessionsTotal), style: _mono),
        if ((s.sessionsWaiting ?? 0) > 0)
          Text(
            '· ${s.sessionsWaiting} aguardando',
            style: const TextStyle(color: AppColors.amber),
          ),
      ]),
      _group([
        const Text('Subagentes'),
        Text(
          s.subagentsRunning == null ? '—' : '${s.subagentsRunning} rodando',
          style: _mono,
        ),
      ]),
      _group([
        const Text('MCP'),
        Text(ratio(s.mcpConnected, s.mcpTotal), style: _mono),
        if ((s.mcpFailed ?? 0) > 0)
          Text(
            '· ${s.mcpFailed} falhou',
            style: const TextStyle(color: AppColors.red),
          ),
      ]),
    ];

    final right = <Widget>[
      Tooltip(
        message: 'Tokens hoje: entrada / saída / cache',
        child: _group([
          const Text('Tokens hoje'),
          Text(formatTokens(s.tokensToday), style: _mono),
          if (s.tokensIn != null && s.tokensOut != null)
            Text(
              '↑${formatTokens(s.tokensIn)} ↓${formatTokens(s.tokensOut)}'
              '${s.tokensCache == null ? '' : ' · cache ${formatTokens(s.tokensCache)}'}',
              style: _monoDim,
            ),
        ]),
      ),
      _separator(),
      _group([
        const Text('Uso 5h'),
        _UsageBar(
          value: s.usage5h,
          color: AppColors.teal,
          label: 'limite de 5 horas',
        ),
        Text(_pct(s.usage5h), style: _mono),
        if (s.usage5hResetsAt != null)
          Text('· reinicia em ${_until(s.usage5hResetsAt!)}'),
      ]),
      _group([
        const Text('Semana'),
        _UsageBar(
          value: s.usageWeek,
          color: AppColors.blue,
          label: 'limite semanal',
        ),
        Text(_pct(s.usageWeek), style: _mono),
      ]),
    ];

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
          fontFamily: AppFonts.sans,
          fontSize: 11,
          color: AppColors.textSecondary,
        ),
        maxLines: 1,
        child: Row(
          children: [
            // Wrap (clipped) instead of Row: never overflows on narrow windows.
            Expanded(
              child: Wrap(
                spacing: 16,
                crossAxisAlignment: WrapCrossAlignment.center,
                clipBehavior: Clip.hardEdge,
                children: left,
              ),
            ),
            const SizedBox(width: 16),
            Wrap(
              spacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: right,
            ),
          ],
        ),
      ),
    );
  }

  static String _pct(double? v) => v == null ? '—' : '${(v * 100).round()}%';

  static String _until(DateTime t) {
    final d = t.difference(DateTime.now());
    if (d.isNegative) return '0m';
    final h = d.inHours, m = d.inMinutes % 60;
    return h > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '${m}m';
  }

  static Widget _group(List<Widget> children) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(width: 6),
        children[i],
      ],
    ],
  );

  static Widget _dot(Color c) => Container(
    width: 6,
    height: 6,
    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
  );

  static Widget _separator() =>
      Container(width: 1, height: 14, color: AppColors.border);
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({
    required this.value,
    required this.color,
    required this.label,
  });

  final double? value;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final v = (value ?? 0).clamp(0.0, 1.0);
    return Semantics(
      label: value == null
          ? '$label: sem dados'
          : '${(v * 100).round()}% do $label',
      child: Container(
        width: 60,
        height: 6,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(3),
        ),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: v,
          heightFactor: 1,
          child: ColoredBox(color: color),
        ),
      ),
    );
  }
}
