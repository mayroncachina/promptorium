import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/usage_tracker.dart' show planWindowExpired;
import '../theme/tokens.dart';
import '../../core/providers/agent_registry.dart';
import '../../core/codex/codex_cli.dart';
import '../../core/providers/provider_preferences.dart';
import '../../core/providers/provider_availability.dart';
import '../../data/providers.dart';
import 'navigation.dart';
import 'footer_stats.dart';

/// Fixed footer (28px) fed by [footerStatsProvider]. Redraws every minute so
/// the "reinicia em" countdowns stay right and a window that reset stops
/// showing its old usage.
class StatusFooter extends ConsumerStatefulWidget {
  const StatusFooter({super.key});

  @override
  ConsumerState<StatusFooter> createState() => _StatusFooterState();
}

class _StatusFooterState extends ConsumerState<StatusFooter> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

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
  Widget build(BuildContext context) {
    final s = ref.watch(footerStatsProvider);
    final now = DateTime.now();

    final (legacyColor, legacyText) = switch (s.cliStatus) {
      CliStatus.connected => (AppColors.teal, 'Claude Code CLI conectado'),
      CliStatus.notFound => (AppColors.red, 'Claude Code CLI não encontrado'),
      CliStatus.unknown => (AppColors.textMuted, 'Claude Code CLI —'),
    };

    final cliText = s.providerStatus == null
        ? legacyText
        : '${s.providerName} CLI ${s.providerStatus}';
    final cliColor = s.providerStatus == null
        ? legacyColor
        : s.providerStatus == 'conectado'
        ? AppColors.teal
        : AppColors.textMuted;

    String ratio(int? a, int? b) => a == null || b == null ? '—' : '$a/$b';

    final left = <Widget>[
      _ProviderSelector(text: cliText, color: cliColor, selected: s.providerId),
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

    final limitOn = s.limitRejected && !planWindowExpired(s.limitResetsAt, now);
    final right = <Widget>[
      if (s.providerId != 'claude')
        const Text('Consumo indisponível')
      else ...[
        _window(
          key: const ValueKey('footer-usage-5h'),
          title: 'Uso 5h',
          name: 'limite de 5 horas',
          value: s.usage5h,
          resetsAt: s.usage5hResetsAt,
          color: AppColors.teal,
          now: now,
          // Weekly limit → the weekly window; anything else → the 5h one.
          limitResetsAt: limitOn && s.limitType != 'seven_day'
              ? s.limitResetsAt ?? s.usage5hResetsAt
              : null,
        ),
        _window(
          key: const ValueKey('footer-usage-week'),
          title: 'Semana',
          name: 'limite semanal',
          value: s.usageWeek,
          resetsAt: s.usageWeekResetsAt,
          color: AppColors.blue,
          now: now,
          limitResetsAt: limitOn && s.limitType == 'seven_day'
              ? s.limitResetsAt ?? s.usageWeekResetsAt
              : null,
        ),
      ],
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

  /// One plan window: bar, % used, % left and the reset countdown, from the
  /// last `rate_limit_event`. A stored window that already reset shows "—".
  /// [limitResetsAt] set = this window hit the limit (`rejected`): red notice
  /// with the time left instead of "resta / reinicia".
  Widget _window({
    required Key key,
    required String title,
    required String name,
    required double? value,
    required DateTime? resetsAt,
    required Color color,
    required DateTime now,
    DateTime? limitResetsAt,
  }) {
    final expired = planWindowExpired(resetsAt, now);
    final v = expired ? null : value;
    final barColor = v == null
        ? color
        : v >= 1
        ? AppColors.red
        : v >= 0.8
        ? AppColors.amber
        : color;
    final limited = v != null && limitResetsAt != null;
    final tip = limited
        ? 'O $name do plano foi atingido: novas respostas falham até '
              '${_when(limitResetsAt, now)} (em ${_until(limitResetsAt, now)}).'
        : v == null
        ? (expired
              ? 'O $name reiniciou; o uso atualiza na próxima resposta do '
                    'Claude.'
              : 'Uso do $name: aparece na primeira resposta do Claude.')
        : 'Uso do $name: ${_pct(v)} usado, ${_pct(_left(v))} disponível'
              '${resetsAt == null ? '' : '. Reinicia ${_when(resetsAt, now)} (em ${_until(resetsAt, now)})'}.';
    return Tooltip(
      key: key,
      message: tip,
      child: _group([
        Text(title),
        _UsageBar(value: v, color: barColor, label: name),
        Text(_pct(v), style: _mono),
        if (limited)
          Text(
            '· limite atingido · volta em ${_until(limitResetsAt, now)}',
            key: const ValueKey('footer-limit'),
            style: const TextStyle(color: AppColors.red),
          )
        else ...[
          if (v != null) Text('· resta ${_pct(_left(v))}', style: _monoDim),
          if (v != null && resetsAt != null)
            Text('· reinicia em ${_until(resetsAt, now)}'),
        ],
      ]),
    );
  }

  static double _left(double used) => (1 - used).clamp(0.0, 1.0);

  static String _pct(double? v) => v == null ? '—' : '${(v * 100).round()}%';

  static String _until(DateTime t, DateTime now) {
    final d = t.difference(now);
    if (d.isNegative) return '0m';
    final days = d.inDays, h = d.inHours % 24, m = d.inMinutes % 60;
    if (days > 0) return '${days}d${h.toString().padLeft(2, '0')}h';
    return d.inHours > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '${m}m';
  }

  /// `às 18:30` today, `sex 14:00` on another day.
  static String _when(DateTime t, DateTime now) {
    final l = t.toLocal(), n = now.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final hm = '${two(l.hour)}:${two(l.minute)}';
    if (l.year == n.year && l.month == n.month && l.day == n.day) {
      return 'às $hm';
    }
    const days = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
    return '${days[l.weekday - 1]} ${two(l.day)}/${two(l.month)} às $hm';
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

class _ProviderSelector extends ConsumerWidget {
  const _ProviderSelector({
    required this.text,
    required this.color,
    required this.selected,
  });
  final String text;
  final Color color;
  final String selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      key: const ValueKey('footer-provider-selector'),
      tooltip: 'Selecionar provedor',
      initialValue: selected,
      position: PopupMenuPosition.over,
      onSelected: (id) async {
        final value = ref.read(providerAvailabilityProvider(id)).value;
        if (value?.available == true) {
          final ws = ref.read(activeWorkspaceProvider);
          await ref
              .read(appSettingsProvider.notifier)
              .set(providerPreferenceKey(ws?.id), id);
        } else if (context.mounted) {
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Provedor indisponível'),
              content: Text(
                value?.message ??
                    'Verificação em andamento. Aguarde e tente novamente.',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    if (id == 'codex') {
                      ref.invalidate(codexCliInfoProvider);
                    }
                    ref.invalidate(providerAvailabilityProvider(id));
                    Navigator.pop(context);
                  },
                  child: const Text('Verificar novamente'),
                ),
                TextButton(
                  onPressed: () {
                    ref
                        .read(navigationProvider.notifier)
                        .go(AppSection.settings);
                    Navigator.pop(context);
                  },
                  child: const Text('Configurações'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Fechar'),
                ),
              ],
            ),
          );
        }
      },
      itemBuilder: (context) {
        final ws = ref.read(activeWorkspaceProvider);
        final all = ref.read(agentProvidersProvider);
        return [
          PopupMenuItem<String>(
            enabled: false,
            child: Text(
              ws == null ? 'Padrão global' : 'Padrão do projeto: ${ws.name}',
            ),
          ),
          const PopupMenuItem<String>(
            enabled: false,
            child: Text('Aplicar às novas execuções'),
          ),
          for (final p in all)
            PopupMenuItem<String>(
              value: p.id,
              key: ValueKey('footer-provider-${p.id}'),
              child: Consumer(
                builder: (context, ref, _) {
                  final availability = ref.watch(
                    providerAvailabilityProvider(p.id),
                  );
                  final status = availability.when(
                    data: (v) => v.label,
                    error: (_, _) => 'não verificado',
                    loading: () => 'verificando…',
                  );
                  return SizedBox(
                    width: 320,
                    child: Row(
                      children: [
                        Icon(
                          p.id == selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${p.displayName} · $status',
                            maxLines: 2,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ];
      },
      child: Semantics(
        button: true,
        label:
            '$text. Selecionar provedor para novas execuções. ${ref.watch(activeWorkspaceProvider) == null ? 'Padrão global' : 'Padrão do projeto'}',
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 290),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  key: const ValueKey('footer-cli'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.arrow_drop_up, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
